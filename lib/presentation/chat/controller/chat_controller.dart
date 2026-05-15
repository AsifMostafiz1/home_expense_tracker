import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../../../services/fcm_v1_service.dart';
import '../../../utils/app_constant.dart';
import '../model/chat_message_model.dart';
import '../repository/chat_repository.dart';

class ChatController extends GetxController implements GetxService {
  final ChatRepository repository;
  
  ChatController({required this.repository});

  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();

  List<ChatMessageModel> messages = [];
  String userName = '';
  String userPhone = '';
  String? userProfileImage;
  StreamSubscription? _messagesSubscription;
  ChatMessageModel? replyingToMessage;
  String? highlightedMessageId;

  List<Map<String, dynamic>> allUsers = [];
  List<Map<String, dynamic>> filteredMentionUsers = [];
  bool isMentioning = false;
  int _currentMentionStartIndex = -1;

  @override
  void onInit() {
    super.onInit();
    _loadUserConfig();
    _initChatStream();
    _fetchAllUsers();
    messageController.addListener(_onTextChanged);
  }

  @override
  void onClose() {
    _messagesSubscription?.cancel();
    messageController.removeListener(_onTextChanged);
    messageController.dispose();
    scrollController.dispose();
    super.onClose();
  }

  Future<void> _fetchAllUsers() async {
    try {
      allUsers = await repository.fetchChatUsers();
    } catch (e) {
      print('Error fetching users: $e');
    }
  }

  void _onTextChanged() {
    final text = messageController.text;
    final cursorPosition = messageController.selection.baseOffset;
    
    if (cursorPosition <= 0) {
      if (isMentioning) {
        isMentioning = false;
        update();
      }
      return;
    }

    int atIndex = -1;
    for (int i = cursorPosition - 1; i >= 0; i--) {
      if (text[i] == '@') {
        if (i == 0 || text[i - 1] == ' ' || text[i - 1] == '\n') {
          atIndex = i;
          break;
        }
      } else if (text[i] == ' ' || text[i] == '\n') {
        break;
      }
    }

    if (atIndex != -1) {
      String query = text.substring(atIndex + 1, cursorPosition).toLowerCase();
      
      // Filter real users
      List<Map<String, dynamic>> users = allUsers.where((user) {
        String name = (user['name'] ?? '').toString().toLowerCase();
        return name.contains(query);
      }).toList();

      // Add 'everyone' option if it matches query or query is small
      if ('everyone'.contains(query) || query.isEmpty) {
        users.insert(0, {'name': 'everyone', 'phone': 'all'});
      }

      filteredMentionUsers = users;
      _currentMentionStartIndex = atIndex;
      if (!isMentioning) {
        isMentioning = true;
      }
      update();
    } else {
      if (isMentioning) {
        isMentioning = false;
        update();
      }
    }
  }

  void insertMention(String name) {
    final text = messageController.text;
    final cursorPosition = messageController.selection.baseOffset;
    
    if (_currentMentionStartIndex != -1 && cursorPosition >= _currentMentionStartIndex) {
      String before = text.substring(0, _currentMentionStartIndex);
      String after = text.substring(cursorPosition);
      String formattedName = name.replaceAll(' ', '');
      String mention = '@$formattedName ';
      
      messageController.value = TextEditingValue(
        text: before + mention + after,
        selection: TextSelection.collapsed(offset: before.length + mention.length),
      );
    }
    
    isMentioning = false;
    update();
  }

  Future<void> _loadUserConfig() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    userName = prefs.getString(AppConstant.keyUserName) ?? 'Unknown';
    userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    userProfileImage = prefs.getString(AppConstant.keyUserProfileImage);
    update();
  }

  void _initChatStream() {
    _messagesSubscription = repository.getMessagesStream().listen((newMessages) {
      messages = newMessages;
      update();
    }, onError: (error) {
      print('Error listening to chat stream: $error');
    });
  }

  void setReply(ChatMessageModel message) {
    replyingToMessage = message;
    update();
  }

  void cancelReply() {
    replyingToMessage = null;
    update();
  }

  String? forceShowTimeMessageId;

  void toggleTimeDisplay(String messageId) {
    if (forceShowTimeMessageId == messageId) {
      forceShowTimeMessageId = null;
    } else {
      forceShowTimeMessageId = messageId;
    }
    update();
  }

  final Map<String, GlobalKey> messageKeys = {};

  GlobalKey getKeyForMessage(String id) {
    if (!messageKeys.containsKey(id)) {
      messageKeys[id] = GlobalKey();
    }
    return messageKeys[id]!;
  }

  void scrollToMessage(String messageId) {
    int index = messages.indexWhere((m) => m.id == messageId);
    if (index == -1) return;

    final key = messageKeys[messageId];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
      _highlightMessage(messageId);
    } else {
      scrollController.animateTo(
        index * 80.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      ).then((_) {
        Future.delayed(const Duration(milliseconds: 50), () {
          if (key != null && key.currentContext != null) {
            Scrollable.ensureVisible(
              key.currentContext!,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeInOut,
              alignment: 0.5,
            );
            _highlightMessage(messageId);
          }
        });
      });
    }
  }

  void _highlightMessage(String messageId) {
    highlightedMessageId = messageId;
    update();
    Future.delayed(const Duration(seconds: 2), () {
      if (highlightedMessageId == messageId) {
        highlightedMessageId = null;
        update();
      }
    });
  }

  Future<void> sendMessage() async {
    final text = messageController.text.trim();
    if (text.isEmpty) return;

    messageController.clear();
    final replyTo = replyingToMessage;
    cancelReply();
    
    // Refresh user config to get latest profile image
    await _loadUserConfig();
    
    // Scroll to bottom optimistically (messages are reversed, so scroll to 0)
    if (scrollController.hasClients) {
      scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    try {
      await repository.sendMessage(text, userName, userPhone, senderImage: userProfileImage, replyTo: replyTo);
      
      // Determine notification targets
      final RegExp mentionRegExp = RegExp(r'@(\w+)');
      final Iterable<RegExpMatch> matches = mentionRegExp.allMatches(text);
      final List<String> mentionList = matches.map((m) => m.group(1) ?? '').toList();
      final bool hasEveryone = mentionList.contains('everyone');
      
      List<String>? targetPhones;
      if (mentionList.isNotEmpty && !hasEveryone) {
        // Targeted mentions
        targetPhones = [];
        for (final mention in mentionList) {
          final user = allUsers.firstWhereOrNull((u) => (u['name'] ?? '').toString().replaceAll(' ', '') == mention);
          if (user != null && user['phone'] != null) {
            targetPhones.add(user['phone']);
          }
        }
        // Also notify the person being replied to
        if (replyTo != null && !targetPhones.contains(replyTo.senderPhone)) {
          targetPhones.add(replyTo.senderPhone);
        }
      } else if (replyTo != null) {
        // No mentions but it's a reply
        targetPhones = [replyTo.senderPhone];
      }

      // If mentions is empty AND replyTo is null, targetPhones stays null (sends to group_chat)
      // If mentions has everyone, targetPhones stays null (sends to group_chat)

      _sendPushNotification(text, userName, replyTo: replyTo, targetPhones: targetPhones);
    } catch (e) {
      print('Error sending message: $e');
      Get.snackbar(
        'Error',
        'Failed to send message.',
        snackPosition: SnackPosition.BOTTOM,
        backgroundColor: Colors.red.shade100,
        colorText: Colors.red.shade900,
      );
    }
  }

  Future<void> reactToMessage(ChatMessageModel message, String emoji) async {
    try {
      await repository.toggleReaction(message.id, userPhone, emoji);
      
      // Notify the message sender about the reaction
      if (message.senderPhone != userPhone) {
        _sendPushNotification(
          '$userName reacted $emoji to your message', 
          userName, 
          targetPhones: [message.senderPhone],
          isReaction: true,
        );
      }
    } catch (e) {
      print('Error reacting to message: $e');
    }
  }

  Future<void> _sendPushNotification(String text, String senderName, {ChatMessageModel? replyTo, List<String>? targetPhones, bool isReaction = false}) async {
    try {
      final String accessToken = await FcmV1Service().getAccessToken();
      if (accessToken.isEmpty) return;

      final RegExp mentionRegExp = RegExp(r'@(\w+)');
      final Iterable<RegExpMatch> matches = mentionRegExp.allMatches(text);
      final List<String> mentionList = matches.map((m) => m.group(1) ?? '').toList();
      final bool hasEveryone = mentionList.contains('everyone');
      final String mentions = mentionList.join(',');

      final String projectId = 'home-expense-tracker-54c89'; 
      final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send');
      
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };

      String notificationTitle = 'New message from $senderName';
      if (isReaction) {
        notificationTitle = 'Reaction from $senderName';
      } else if (hasEveryone) {
        notificationTitle = '📢 @everyone: New message from $senderName';
      } else if (mentionList.isNotEmpty) {
        notificationTitle = '👋 You were mentioned by $senderName';
      } else if (replyTo != null) {
        notificationTitle = '💬 $senderName replied to you';
      }

      final List<String> topics = [];
      if (targetPhones != null && targetPhones.isNotEmpty) {
        for (final phone in targetPhones) {
          String safePhone = phone.replaceAll(RegExp(r'[^a-zA-Z0-9-_.~%]'), '');
          topics.add('user_$safePhone');
        }
      } else {
        topics.add('group_chat');
      }
      
      for (final topic in topics) {
        final body = {
          'message': {
            'topic': topic,
            'data': {
              'title': notificationTitle,
              'body': text,
              'senderName': senderName,
              'senderPhone': userPhone,
              'replyToSenderName': replyTo?.senderName ?? '',
              'mentions': mentions,
              'isEveryone': hasEveryone.toString(),
              'type': 'chat_message',
              'click_action': 'FLUTTER_NOTIFICATION_CLICK',
            },
          }
        };

        await http.post(url, headers: headers, body: jsonEncode(body));
      }
    } catch (e) {
      print('Error sending push notification: $e');
    }
  }
}
