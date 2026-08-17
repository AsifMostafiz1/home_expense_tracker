import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/chat_outbox_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/push_notification_service.dart';
import '../../../services/supabase_storage_service.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_enums.dart';
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
  final ChatOutboxService _outbox = Get.find<ChatOutboxService>();
  final ConnectivityService _connectivity = Get.find<ConnectivityService>();

  /// How many pictures may ride on one send. A cap keeps a stray "select all"
  /// in the gallery from queueing a hundred uploads.
  static const int maxAttachments = 10;

  /// Pictures sitting in the composer, chosen but not sent.
  final List<PickedImage> pendingAttachments = [];

  /// Messages sent but not yet in the thread — waiting for a connection, or
  /// mid-upload — drawn at the end of the thread as their own bubbles.
  /// Oldest first, the order they will go out in.
  List<OutgoingMessage> get outgoing => _outbox.items;

  /// Whether the outbox is working right now, as opposed to waiting for a
  /// connection — the bubbles say "sending" for one and "waiting" for the
  /// other.
  bool get isDelivering => _outbox.isDelivering;

  bool get isOnline => _connectivity.isOnline;

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
    // The outgoing bubbles are drawn from the outbox; redraw as it moves.
    _outbox.addListener(_onOutboxChanged);
    _connectivity.addListener(_onOutboxChanged);
  }

  void _onOutboxChanged() => update();

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
    _outbox.removeListener(_onOutboxChanged);
    _connectivity.removeListener(_onOutboxChanged);
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

  /// Whether an edit or delete can go through right now. The five-minute
  /// window is measured by the server's clock when the write *arrives*, so a
  /// member's change queued offline and delivered twenty minutes later would
  /// be refused — and the message would quietly come back. Better to say so
  /// up front. Admins are not on the clock, so theirs simply queue.
  bool _canReviseNow() => isAdminUser || isOnline;

  void _explainReviseNeedsConnection() {
    CustomSnackbar.show(
        type: SnackbarType.warning, message: 'revise_needs_connection'.tr);
  }

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
    if (!_canReviseNow()) {
      _explainReviseNeedsConnection();
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
    if (!_canReviseNow()) {
      _explainReviseNeedsConnection();
      return;
    }

    try {
      await repository.deleteMessage(
        message.id,
        byAdmin: !_isMine(message),
        actorPhone: userPhone,
      );

      // Best effort, and only with a connection — offline the object is
      // left behind rather than the delete held up on it.
      if (message.hasImage && isOnline) {
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

    // Everything goes through the outbox — see ChatOutboxService. Online it
    // is delivered a moment later; offline it waits, on disk, and goes out
    // with the next connection whether or not the app is open by then.
    if (attachments.isEmpty) {
      await _enqueue(text: text, replyTo: replyTo);
      return;
    }

    // The caption and the reply ride on the first picture, the way every chat
    // app does it; the rest go out as bare images.
    final String batch = DateTime.now().microsecondsSinceEpoch.toString();
    for (int i = 0; i < attachments.length; i++) {
      await _enqueue(
        localId: '${batch}_$i',
        text: i == 0 ? text : '',
        replyTo: i == 0 ? replyTo : null,
        image: attachments[i],
      );
    }
  }

  /// Hands one message to the outbox, with its notification already worked
  /// out — the job that finally sends it may be running in the background,
  /// with no mention list to consult.
  Future<void> _enqueue({
    String? localId,
    required String text,
    ChatMessageModel? replyTo,
    PickedImage? image,
  }) async {
    final _PushPlan push = _planPush(text, replyTo: replyTo, hasImage: image != null);
    try {
      await _outbox.enqueue(
        localId: localId ?? DateTime.now().microsecondsSinceEpoch.toString(),
        text: text,
        image: image?.file,
        imageWidth: image?.width,
        imageHeight: image?.height,
        replyToId: replyTo?.id,
        replyToText: replyTo?.preview,
        replyToSenderName: replyTo?.senderName,
        replyToSenderPhone: replyTo?.senderPhone,
        replyToImage: replyTo?.imageUrl,
        senderName: userName,
        senderPhone: userPhone,
        senderImage: userProfileImage,
        pushTitle: push.title,
        pushBody: push.body,
        pushTargets: push.targets,
        pushData: push.data,
      );
    } catch (e) {
      debugPrint('Error queueing message: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_send_message'.tr);
    }
  }

  void retryOutgoing(OutgoingMessage item) => _outbox.retry(item);

  void discardOutgoing(OutgoingMessage item) => _outbox.discard(item);

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
      // Decided here from the message on screen, so it is one plain write —
      // a transaction needs the server and would fail offline.
      final bool removing = _current(message).reactions?[userPhone] == emoji;
      await repository.setReaction(message.id, userPhone, removing ? null : emoji);

      // Notify the message sender about the reaction — only with a
      // connection; a reaction is not worth queueing a notification for.
      if (!removing && message.senderPhone != userPhone && isOnline) {
        _notifyReaction(message, emoji);
      }
    } catch (e) {
      print('Error reacting to message: $e');
    }
  }

  /// Works out who a message's notification goes to and what it says. Kept
  /// as data rather than sent, so the outbox can fire it once the message is
  /// really in — from the app or from the background job.
  _PushPlan _planPush(String text,
      {ChatMessageModel? replyTo, bool hasImage = false}) {
    final RegExp mentionRegExp = RegExp(r'@(\w+)');
    final List<String> mentionList = mentionRegExp
        .allMatches(text)
        .map((m) => m.group(1) ?? '')
        .toList();
    final bool hasEveryone = mentionList.contains('everyone');

    // Targets. Named people, plus whoever is being replied to; nobody named
    // means the whole group, and so does @everyone.
    List<String>? targets;
    if (mentionList.isNotEmpty && !hasEveryone) {
      targets = [];
      for (final mention in mentionList) {
        final user = allUsers.firstWhereOrNull((u) =>
            (u['name'] ?? '').toString().replaceAll(' ', '') == mention);
        if (user != null && user['phone'] != null) {
          targets.add(user['phone']);
        }
      }
      if (replyTo != null && !targets.contains(replyTo.senderPhone)) {
        targets.add(replyTo.senderPhone);
      }
    } else if (replyTo != null) {
      targets = [replyTo.senderPhone];
    }

    String title = 'New message from $userName';
    if (hasImage && mentionList.isEmpty && replyTo == null) {
      title = '📷 $userName sent a photo';
    } else if (hasEveryone) {
      title = '📢 @everyone: New message from $userName';
    } else if (mentionList.isNotEmpty) {
      title = '👋 You were mentioned by $userName';
    } else if (replyTo != null) {
      title = '💬 $userName replied to you';
    }

    return _PushPlan(
      title: title,
      // A bare picture has no words to push, so the notification says what
      // arrived instead of arriving empty.
      body: text.isEmpty ? '📷 ${'photo'.tr}' : text,
      targets: targets,
      data: {
        'senderName': userName,
        'senderPhone': userPhone,
        'replyToSenderName': replyTo?.senderName ?? '',
        'mentions': mentionList.join(','),
        'isEveryone': hasEveryone.toString(),
        'type': 'chat_message',
      },
    );
  }

  Future<void> _notifyReaction(ChatMessageModel message, String emoji) async {
    await PushNotificationService().sendPushNotification(
      title: 'Reaction from $userName',
      body: '$userName reacted $emoji to your message',
      targetPhones: [message.senderPhone],
      data: {
        'senderName': userName,
        'senderPhone': userPhone,
        'replyToSenderName': '',
        'mentions': '',
        'isEveryone': 'false',
        'type': 'chat_message',
      },
    );
  }
}

/// A notification worked out but not yet sent.
class _PushPlan {
  final String title;
  final String body;
  final List<String>? targets;
  final Map<String, String> data;

  const _PushPlan({
    required this.title,
    required this.body,
    required this.targets,
    required this.data,
  });
}
