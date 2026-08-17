import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/push_notification_service.dart';
import '../../../services/supabase_storage_service.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/supabase_config.dart';
import '../model/chat_message_model.dart';
import '../model/outgoing_image_model.dart';
import '../repository/chat_repository.dart';

class ChatController extends GetxController implements GetxService {
  final ChatRepository repository;

  ChatController({required this.repository});

  final TextEditingController messageController = TextEditingController();
  final ScrollController scrollController = ScrollController();
  final FocusNode messageFocusNode = FocusNode();

  List<ChatMessageModel> messages = [];
  String userName = '';
  String userPhone = '';
  String? userProfileImage;
  bool isAdminUser = false;
  StreamSubscription? _messagesSubscription;
  ChatMessageModel? replyingToMessage;

  /// The message whose text the composer is currently rewriting. Sending while
  /// this is set edits that message instead of posting a new one.
  ChatMessageModel? editingMessage;

  String? highlightedMessageId;

  /// How long a member has to think better of what they said. Admins are not
  /// on the clock — house business sometimes has to be corrected long after
  /// it was posted.
  static const Duration editWindow = Duration(minutes: 5);

  List<Map<String, dynamic>> allUsers = [];
  List<Map<String, dynamic>> filteredMentionUsers = [];
  bool isMentioning = false;
  int _currentMentionStartIndex = -1;

  int unseenCount = 0;
  bool isChatScreenVisible = false;

  Map<String, List<Map<String, dynamic>>> messageSeenBy = {};
  StreamSubscription? _seenStatusSubscription;

  final SupabaseStorageService _storage = SupabaseStorageService();

  /// How many pictures may ride on one send. A cap keeps a stray "select all"
  /// in the gallery from queueing a hundred uploads.
  static const int maxAttachments = 10;

  /// Pictures sitting in the composer, chosen but not sent.
  final List<PickedImage> pendingAttachments = [];

  /// Pictures being uploaded, drawn at the end of the thread as their own
  /// bubbles. Oldest first — the queue works through them in order so the
  /// thread reads in the order they were picked.
  final List<OutgoingImage> outgoingImages = [];

  bool _draining = false;

  @override
  void onInit() {
    super.onInit();
    _loadUserConfig();
    _initChatStream();
    _initSeenStatusStream();
    _fetchAllUsers();

    // Ensure subscribed to personal topic for notifications
    _subscribeToTopic();

    messageController.addListener(_onTextChanged);
  }

  void _subscribeToTopic() async {
    // Always ensure subscribed to group chat
    PushNotificationService().subscribeToGroupTopic();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    String phone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    if (phone.isNotEmpty) {
      print('FCM: ChatController initiating personal subscription for phone: $phone');
      PushNotificationService().subscribeToUserTopic(phone);
    }
  }

  @override
  void onClose() {
    _messagesSubscription?.cancel();
    _seenStatusSubscription?.cancel();
    messageController.removeListener(_onTextChanged);
    messageController.dispose();
    messageFocusNode.dispose();
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

    if (_currentMentionStartIndex != -1 &&
        cursorPosition >= _currentMentionStartIndex) {
      String before = text.substring(0, _currentMentionStartIndex);
      String after = text.substring(cursorPosition);
      String formattedName = name.replaceAll(' ', '');
      String mention = '@$formattedName ';

      messageController.value = TextEditingValue(
        text: before + mention + after,
        selection:
            TextSelection.collapsed(offset: before.length + mention.length),
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
    isAdminUser = prefs.getString(AppConstant.keyIsAdmin) == '1';
    update();
  }

  void _initChatStream() {
    _messagesSubscription =
        repository.getMessagesStream().listen((newMessages) {
      if (!isChatScreenVisible && messages.isNotEmpty) {
        final existingIds = messages.map((m) => m.id).toSet();
        for (var msg in newMessages) {
          if (!existingIds.contains(msg.id) && msg.senderPhone != userPhone) {
            unseenCount++;
          }
        }
      }
      messages = newMessages;
      if (isChatScreenVisible && messages.isNotEmpty) {
        _updateMySeenStatus();
      }
      update();
    }, onError: (error) {
      print('Error listening to chat stream: $error');
    });
  }

  void setChatScreenVisible(bool visible) {
    isChatScreenVisible = visible;
    if (visible) {
      unseenCount = 0;
      if (messages.isNotEmpty) {
        _updateMySeenStatus();
      }
      update();
    }
  }

  void _initSeenStatusStream() {
    _seenStatusSubscription =
        repository.getSeenStatusStream().listen((statuses) {
      Map<String, List<Map<String, dynamic>>> newSeenMap = {};

      for (var status in statuses) {
        String? messageId = status['lastSeenMessageId'];
        String? phone = status['userPhone'];

        // Don't show my own seen status to myself, or if data is invalid
        if (messageId != null && phone != null && phone != userPhone) {
          newSeenMap[messageId] ??= [];
          newSeenMap[messageId]!.add(status);
        }
      }

      messageSeenBy = newSeenMap;
      update();
    });
  }

  void _updateMySeenStatus() {
    if (messages.isEmpty || userPhone.isEmpty) return;

    // The first message in the list is the latest one (descending order)
    final latestMessageId = messages.first.id;
    if (latestMessageId.isNotEmpty) {
      repository.updateSeenStatus(
          latestMessageId, userPhone, userName, userProfileImage);
    }
  }

  void setReply(ChatMessageModel message) {
    replyingToMessage = message;
    cancelEditing();
    update();
    messageFocusNode.requestFocus();
  }

  void cancelReply() {
    replyingToMessage = null;
    update();
  }

  bool _isMine(ChatMessageModel message) => message.senderPhone == userPhone;

  /// The live version of a message the caller is holding. The composer keeps a
  /// snapshot from the moment editing started, and an admin can delete that
  /// message while the keyboard is still up.
  ChatMessageModel _current(ChatMessageModel message) =>
      messages.firstWhereOrNull((m) => m.id == message.id) ?? message;

  bool _withinWindow(ChatMessageModel message) =>
      DateTime.now().difference(message.createdAt) < editWindow;

  /// Own messages for five minutes; anything, any time, for an admin.
  ///
  /// A message still on its way out has no id yet, so there is nothing to
  /// rewrite either.
  bool canEdit(ChatMessageModel message) =>
      !message.deleted &&
      message.id.isNotEmpty &&
      (isAdminUser || (_isMine(message) && _withinWindow(message)));

  bool canDelete(ChatMessageModel message) =>
      !message.deleted &&
      message.id.isNotEmpty &&
      (isAdminUser || (_isMine(message) && _withinWindow(message)));

  /// Loads a message back into the composer. Sending from here rewrites it
  /// rather than posting again.
  void startEditing(ChatMessageModel message) {
    if (!canEdit(message)) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'edit_window_expired'.tr);
      return;
    }

    editingMessage = message;
    replyingToMessage = null;
    // A picture cannot be swapped out from here — only what was said about it.
    pendingAttachments.clear();
    messageController.text = message.text;
    messageController.selection =
        TextSelection.collapsed(offset: messageController.text.length);
    update();
    messageFocusNode.requestFocus();
  }

  void cancelEditing({bool clearText = false}) {
    if (editingMessage == null) return;
    editingMessage = null;
    if (clearText) messageController.clear();
    update();
  }

  /// Empties a message for everyone, and takes its picture out of storage with
  /// it — an orphaned object is a deleted photo that is still one URL away.
  Future<void> deleteMessage(ChatMessageModel message) async {
    if (!canDelete(_current(message))) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'delete_window_expired'.tr);
      return;
    }

    try {
      await repository.deleteMessage(
        message.id,
        byAdmin: !_isMine(message),
        actorPhone: userPhone,
      );

      if (message.hasImage) {
        await _storage.deleteByPublicUrl(message.imageUrl);
      }

      if (editingMessage?.id == message.id) cancelEditing(clearText: true);
      if (replyingToMessage?.id == message.id) cancelReply();
    } catch (e) {
      debugPrint('Error deleting message: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_message'.tr);
    }
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
      scrollController
          .animateTo(
        index * 80.0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      )
          .then((_) {
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

  /// Adds pictures to the composer. The camera gives one, the gallery as many
  /// as the sender taps.
  ///
  /// Everything is downscaled on the device before it goes anywhere: a modern
  /// phone camera produces several MB per shot, and nothing in this thread is
  /// ever drawn wider than a phone screen.
  Future<void> pickChatImages(ImageSource source) async {
    try {
      final ImagePicker picker = ImagePicker();
      final List<XFile> picked;

      if (source == ImageSource.camera) {
        final XFile? shot = await picker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
        );
        picked = shot == null ? const <XFile>[] : <XFile>[shot];
      } else {
        picked = await picker.pickMultiImage(
          maxWidth: 1600,
          maxHeight: 1600,
          imageQuality: 80,
        );
      }
      if (picked.isEmpty) return;

      final int room = maxAttachments - pendingAttachments.length;
      if (room <= 0 || picked.length > room) {
        CustomSnackbar.show(
          type: SnackbarType.warning,
          message: 'attachment_limit_reached'
              .trParams({'count': '$maxAttachments'}),
        );
        if (room <= 0) return;
      }

      for (final XFile file in picked.take(room)) {
        pendingAttachments.add(await _measure(File(file.path)));
      }
      update();
    } catch (e) {
      debugPrint('Error picking chat image: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_pick_image'.tr);
    }
  }

  /// Reads a picture's pixel size. Decoded one at a time and released straight
  /// away — a batch of ten full bitmaps held at once is tens of megabytes.
  Future<PickedImage> _measure(File file) async {
    try {
      final ui.Image decoded = await decodeImageFromList(await file.readAsBytes());
      final PickedImage picked = PickedImage(
        file: file,
        width: decoded.width.toDouble(),
        height: decoded.height.toDouble(),
      );
      decoded.dispose();
      return picked;
    } catch (e) {
      // Unreadable dimensions are not worth refusing the picture over; the
      // bubble falls back to a square.
      debugPrint('Could not measure image: $e');
      return PickedImage(file: file, width: 0, height: 0);
    }
  }

  void removeAttachment(int index) {
    if (index < 0 || index >= pendingAttachments.length) return;
    pendingAttachments.removeAt(index);
    update();
  }

  void clearAttachments() {
    if (pendingAttachments.isEmpty) return;
    pendingAttachments.clear();
    update();
  }

  Future<void> sendMessage() async {
    final String text = messageController.text.trim();

    // An edit is a different write entirely: no new message, no attachments.
    final ChatMessageModel? editing = editingMessage;
    if (editing != null) {
      await _submitEdit(editing, text);
      return;
    }

    final List<PickedImage> attachments =
        List<PickedImage>.from(pendingAttachments);
    if (text.isEmpty && attachments.isEmpty) return;

    messageController.clear();
    pendingAttachments.clear();
    final replyTo = replyingToMessage;
    cancelReply();

    // Refresh user config to get latest profile image
    await _loadUserConfig();

    _scrollToLatest();

    if (attachments.isEmpty) {
      await _deliver(text: text, replyTo: replyTo);
      return;
    }

    // The caption and the reply ride on the first picture, the way every chat
    // app does it; the rest go out as bare images.
    final String batch = DateTime.now().microsecondsSinceEpoch.toString();
    for (int i = 0; i < attachments.length; i++) {
      outgoingImages.add(OutgoingImage(
        localId: '${batch}_$i',
        picked: attachments[i],
        caption: i == 0 ? text : '',
        replyTo: i == 0 ? replyTo : null,
      ));
    }
    update();
    _drainOutgoing();
  }

  Future<void> _submitEdit(ChatMessageModel message, String text) async {
    // Clearing the words off a text-only message is a delete wearing a
    // disguise; the delete action says so out loud, and this should not.
    if (text.isEmpty && !message.hasImage) {
      CustomSnackbar.show(
          type: SnackbarType.warning, message: 'message_cannot_be_empty'.tr);
      return;
    }

    // Re-checked here, not only when the menu opened: five minutes can run out
    // while the keyboard is up, and the message can be deleted underneath it.
    if (!canEdit(_current(message))) {
      cancelEditing(clearText: true);
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'edit_window_expired'.tr);
      return;
    }

    cancelEditing(clearText: true);
    if (text == message.text.trim()) return;

    try {
      await repository.editMessage(message.id, text, userPhone);
    } catch (e) {
      debugPrint('Error editing message: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_edit_message'.tr);
    }
  }

  /// Works the upload queue one picture at a time, so a batch lands in the
  /// order it was picked instead of in whatever order the network returns.
  Future<void> _drainOutgoing() async {
    if (_draining) return;
    _draining = true;

    try {
      while (true) {
        final OutgoingImage? next =
            outgoingImages.firstWhereOrNull((image) => !image.failed);
        if (next == null) return;
        await _uploadAndDeliver(next);
      }
    } finally {
      _draining = false;
    }
  }

  Future<void> _uploadAndDeliver(OutgoingImage image) async {
    try {
      final Uint8List bytes = await image.file.readAsBytes();

      final String url = await _storage.uploadBytes(
        bytes,
        folder: SupabaseConfig.folderChat,
        extension: _storage.extensionOf(image.file.path),
      );

      // Dropped before the write: from here on Firestore's own local echo puts
      // the message on screen, and two copies of the same picture would show.
      outgoingImages.remove(image);
      update();

      await _deliver(
        text: image.caption,
        replyTo: image.replyTo,
        imageUrl: url,
        // Measured when the picture was picked, so the receiving side can lay
        // the bubble out before a single byte has downloaded.
        imageWidth: image.picked.width,
        imageHeight: image.picked.height,
      );
    } catch (e) {
      debugPrint('Error uploading chat image: $e');
      // Stays in the list, marked — the sender decides whether to retry or
      // drop it, and the queue moves on to the next one meanwhile.
      image.failed = true;
      update();
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_send_image'.tr);
    }
  }

  void retryOutgoingImage(OutgoingImage image) {
    image.failed = false;
    update();
    _drainOutgoing();
  }

  void discardOutgoingImage(OutgoingImage image) {
    outgoingImages.remove(image);
    update();
  }

  /// Writes one message and notifies whoever it concerns.
  Future<void> _deliver({
    required String text,
    ChatMessageModel? replyTo,
    String? imageUrl,
    double? imageWidth,
    double? imageHeight,
  }) async {
    try {
      await repository.sendMessage(
        text,
        userName,
        userPhone,
        senderImage: userProfileImage,
        replyTo: replyTo,
        imageUrl: imageUrl,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      );

      // Determine notification targets
      final RegExp mentionRegExp = RegExp(r'@(\w+)');
      final Iterable<RegExpMatch> matches = mentionRegExp.allMatches(text);
      final List<String> mentionList =
          matches.map((m) => m.group(1) ?? '').toList();
      final bool hasEveryone = mentionList.contains('everyone');

      List<String>? targetPhones;
      if (mentionList.isNotEmpty && !hasEveryone) {
        // Targeted mentions
        targetPhones = [];
        for (final mention in mentionList) {
          final user = allUsers.firstWhereOrNull((u) =>
              (u['name'] ?? '').toString().replaceAll(' ', '') == mention);
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

      _sendPushNotification(
        // A bare picture has no words to push, so the notification says what
        // arrived instead of arriving empty.
        text.isEmpty ? '📷 ${'photo'.tr}' : text,
        userName,
        replyTo: replyTo,
        targetPhones: targetPhones,
        imageUrl: imageUrl,
      );
    } catch (e) {
      print('Error sending message: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_send_message'.tr);
    }
  }

  /// The list is reversed, so the newest message sits at offset zero.
  void _scrollToLatest() {
    if (!scrollController.hasClients) return;
    scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  Future<void> reactToMessage(ChatMessageModel message, String emoji) async {
    // Nothing left to react to, and the write would put the field back.
    if (message.deleted || message.id.isEmpty) return;

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

  Future<void> _sendPushNotification(String text, String senderName,
      {ChatMessageModel? replyTo,
      List<String>? targetPhones,
      bool isReaction = false,
      String? imageUrl}) async {
    String notificationTitle = 'New message from $senderName';

    final RegExp mentionRegExp = RegExp(r'@(\w+)');
    final Iterable<RegExpMatch> matches = mentionRegExp.allMatches(text);
    final List<String> mentionList =
        matches.map((m) => m.group(1) ?? '').toList();
    final bool hasEveryone = mentionList.contains('everyone');
    final String mentions = mentionList.join(',');

    if (isReaction) {
      notificationTitle = 'Reaction from $senderName';
    } else if (imageUrl != null && mentionList.isEmpty && replyTo == null) {
      notificationTitle = '📷 $senderName sent a photo';
    } else if (hasEveryone) {
      notificationTitle = '📢 @everyone: New message from $senderName';
    } else if (mentionList.isNotEmpty) {
      notificationTitle = '👋 You were mentioned by $senderName';
    } else if (replyTo != null) {
      notificationTitle = '💬 $senderName replied to you';
    }

    await PushNotificationService().sendPushNotification(
      title: notificationTitle,
      body: text,
      targetPhones: targetPhones,
      // Rides along as the notification's big picture, so a photo is visible
      // from the shade without opening the app.
      imageUrl: imageUrl,
      data: {
        'senderName': senderName,
        'senderPhone': userPhone,
        'replyToSenderName': replyTo?.senderName ?? '',
        'mentions': mentions,
        'isEveryone': hasEveryone.toString(),
        'type': 'chat_message',
      },
    );
  }
}
