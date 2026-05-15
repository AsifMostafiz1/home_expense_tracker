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
      filteredMentionUsers = allUsers.where((user) {
        String name = (user['name'] ?? '').toString().toLowerCase();
        return name.contains(query);
      }).toList();
      
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
      // Send FCM Notification to all other users
      _sendPushNotification(text, userName, replyTo: replyTo);
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

  Future<void> _sendPushNotification(String text, String senderName, {ChatMessageModel? replyTo}) async {
    try {
      final String accessToken = await FcmV1Service().getAccessToken();
      if (accessToken.isEmpty) {
        print('Failed to get access token');
        return;
      }

      final RegExp mentionRegExp = RegExp(r'@(\w+)');
      final Iterable<RegExpMatch> matches = mentionRegExp.allMatches(text);
      final String mentions = matches.map((m) => m.group(1) ?? '').join(',');

      final String projectId = 'home-expense-tracker-54c89'; // from your service_account.json
      final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$projectId/messages:send');
      
      final headers = {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $accessToken',
      };
      
      final body = {
        'message': {
          'topic': 'group_chat',
          // Removed 'notification' to make it a data-only message.
          // This allows the app to intercept it in the background and decide whether to show it.
          'data': {
            'title': 'New message from $senderName',
            'body': text,
            'senderName': senderName,
            'senderPhone': userPhone,
            'replyToSenderName': replyTo?.senderName ?? '',
            'mentions': mentions,
            'type': 'chat_message',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
        }
      };

      final response = await http.post(
        url,
        headers: headers,
        body: jsonEncode(body),
      );
      
      if (response.statusCode != 200) {
        print('FCM Send Error: ${response.body}');
      }
    } catch (e) {
      print('Error sending push notification: $e');
    }
  }
}
