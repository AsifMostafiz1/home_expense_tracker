import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../../../common/widgets/avatar_picker.dart';
import '../../../common/widgets/local_image.dart';
import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../controller/chat_controller.dart';
import '../controller/chat_list_controller.dart';
import '../controller/voice_recorder_controller.dart';
import '../model/chat_message_model.dart';
import '../model/chat_thread_model.dart';
import '../model/outgoing_image_model.dart';
import '../model/voice_note_model.dart';
import '../../monthly_stats/controller/monthly_stats_controller.dart';
import '../../monthly_stats/view/monthly_stats_screen.dart';
import '../widgets/chat_presence.dart';
import '../widgets/chat_search_results.dart';
import '../widgets/group_avatar.dart';
import '../widgets/group_settings_sheet.dart';
import '../widgets/pinned_banner.dart';
import '../widgets/typing_bubble.dart';
import '../widgets/voice_bubble.dart';
import '../widgets/voice_recorder_bar.dart';
import '../../../services/voice_player_service.dart';
import 'chat_media_screen.dart';
import 'chat_media_viewer.dart';
import 'pinned_messages_screen.dart';

/// The little round button that lives inside the search pill. An `IconButton`
/// carries a 48px touch target that will not fit in a 42px bar, so this keeps
/// the tap area to what the pill has room for.
class _SearchIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _SearchIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Icon(icon, size: 17, color: AppUi.muted(context)),
        ),
      ),
    );
  }
}

/// One conversation, whichever it is.
///
/// The house group and a direct chat are the same screen: the same bubbles,
/// the same composer, the same reactions and replies. Only the header and the
/// controller behind it differ — see [tag].
class ChatScreen extends StatefulWidget {
  /// Which conversation to show. Null is the house group, whose controller the
  /// dashboard keeps registered untagged; anything else is a direct thread's
  /// conversation id, which is also the tag its controller lives under.
  final String? tag;

  const ChatScreen({super.key, this.tag});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  ChatController get controller => Get.find<ChatController>(tag: widget.tag);

  /// The composer's microphone. One per screen, because a recording belongs
  /// to the conversation it was started in — see [VoiceRecorderController].
  VoiceRecorderController get _recorder =>
      Get.find<VoiceRecorderController>(tag: widget.tag);

  /// True between the finger coming off the microphone and the recorder
  /// having actually started, which is not instant the first time — the
  /// permission sheet is in the way. Without it, a quick tap while that is
  /// resolving would leave the microphone open with nobody holding it.
  bool _micReleased = false;

  bool get _isDirect => widget.tag != null;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // One screen, one microphone. A thread opened twice — from the dashboard
    // and again from a notification — must not leave the first one's recorder
    // registered with nobody to close it.
    if (Get.isRegistered<VoiceRecorderController>(tag: widget.tag)) {
      Get.delete<VoiceRecorderController>(tag: widget.tag, force: true);
    }
    // A recording that hits the ceiling is sent as it stands, rather than
    // waiting on a finger that may never come up.
    Get.put(VoiceRecorderController(), tag: widget.tag).onMaximumReached =
        _finishRecording;
    // Being on screen is what marks a thread read — for the group that is the
    // in-memory badge, for a direct chat the count in Firestore.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.setChatScreenVisible(true);
    });
  }

  /// Coming back to a thread that was left open is opening it again.
  ///
  /// What arrived while the app was away is on screen the moment it returns,
  /// notifications and all — and those the reader never tapped would sit in
  /// the tray for messages they have already read.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!mounted) return;
    if (!Get.isRegistered<ChatController>(tag: widget.tag)) return;
    if (state == AppLifecycleState.resumed) {
      controller.setChatScreenVisible(true);
    } else {
      // Away from the app is not typing, whatever is left in the composer.
      controller.stopTyping();
      // Nor is it recording. The microphone must not be left open behind a
      // screen the reader has walked away from, and half a sentence cut off
      // by a phone call is not a message anybody wants sent.
      if (Get.isRegistered<VoiceRecorderController>(tag: widget.tag)) {
        _recorder.cancel();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // Safe from here: with `false` this only flips a flag, it does not ask
    // anything to rebuild.
    controller.setChatScreenVisible(false);

    // A direct chat's controller belongs to its screen — it holds two live
    // Firestore listeners, and one per conversation ever opened would pile
    // up. `force` because a GetxService is otherwise never taken down.
    // Safe here: Flutter unmounts a subtree's children before the parent's
    // `dispose`, so every builder listening to this controller is already
    // gone.
    // Leaving the thread stops whatever was talking in it: a voice message
    // playing on over another screen is nobody's idea of what a back button
    // does.
    if (Get.isRegistered<VoicePlayerService>()) {
      Get.find<VoicePlayerService>().stop();
    }
    Get.delete<VoiceRecorderController>(tag: widget.tag, force: true);

    final String? tag = widget.tag;
    if (tag != null) Get.delete<ChatController>(tag: tag, force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ChatController>(
      tag: widget.tag,
      // Back closes the search before it closes the conversation — leaving
      // the thread from a list of results is not what that gesture means.
      builder: (c) => PopScope(
        canPop: !c.isSearching,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && c.isSearching) c.closeSearch();
        },
        child: _buildScaffold(context),
      ),
    );
  }

  Widget _buildScaffold(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      // Both halves of the screen swap when a search opens, so both hang off
      // the same builder rather than the header being redrawn by hand.
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: GetBuilder<ChatController>(
          tag: widget.tag,
          builder: (c) => _buildAppBar(context),
        ),
      ),
      body: GetBuilder<ChatController>(
        tag: widget.tag,
        builder: (c) => c.isSearching
            ? ChatSearchResults(controller: c)
            : _buildThread(context),
      ),
    );
  }

  Widget _buildThread(BuildContext context) {
    return Column(
      children: [
        // Held above the thread rather than in it: a pin is something the
        // house wants seen no matter how far back it has scrolled.
        if (!_isDirect) PinnedBanner(onTap: _openPinned),
        Expanded(
          child: GetBuilder<ChatController>(
            tag: widget.tag,
            builder: (controller) {
              // Messages still on their way out — uploading, or waiting
              // for a connection — sit past the newest message, at the
              // bottom of a reversed list. Grouped the way the thread
              // itself is, so a batch of pictures is a grid straight away.
              final List<List<OutgoingMessage>> outgoingRows =
                  controller.outgoingRows;
              final int pending = outgoingRows.length;
              final bool typing = controller.typingUsers.isNotEmpty;

              if (controller.messages.isEmpty && pending == 0 && !typing) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                      const SizedBox(height: 16),
                      Text(
                        'no_messages_yet'.tr,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _isDirect
                            ? 'say_hi_to'.trParams(
                                {'name': controller.thread.peerName})
                            : 'start_conversation'.tr,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                      ),
                    ],
                  ),
                );
              }

              // One row is one bubble: a message on its own, or every
              // picture of a single send.
              final List<List<ChatMessageModel>> rows = controller.rows;
              final bool loadingMore = controller.isLoadingHistory;
              final int total = rows.length +
                  pending +
                  (typing ? 1 : 0) +
                  (loadingMore ? 1 : 0);

              return ListView.builder(
                controller: controller.scrollController,
                reverse: true,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                itemCount: total,
                itemBuilder: (context, slot) {
                  // The far end of a reversed list is the top of the thread,
                  // which is where the page still being read back belongs.
                  if (loadingMore && slot == total - 1) {
                    return const _HistoryLoader();
                  }

                  // Slot zero is the bottom of a reversed list — where the
                  // next message will land, and so where the dots promising
                  // one belong.
                  if (typing && slot == 0) return const TypingBubble();

                  final int position = typing ? slot - 1 : slot;

                  if (position < pending) {
                    // Newest first, like everything else in a reversed list.
                    return _OutgoingBubble(
                      items: outgoingRows[pending - 1 - position],
                      controller: controller,
                    );
                  }

                  final int index = position - pending;
                  final List<ChatMessageModel> row = rows[index];
                  // The bubble hangs on the first picture of a send — the one
                  // carrying the caption and the reply.
                  final message = ChatController.anchorOf(row);
                  final isMe = message.senderPhone == controller.userPhone;

                  bool isFirstInGroup = true;
                  bool isLastInGroup = true;
                  bool showDateHeader = false;

                  if (index < rows.length - 1) {
                    final nextMessage =
                        ChatController.anchorOf(rows[index + 1]);
                    if (nextMessage.senderPhone == message.senderPhone) {
                      isFirstInGroup = false;
                    }

                    final messageDate = DateFormat('yyyy-MM-dd').format(message.createdAt);
                    final nextMessageDate = DateFormat('yyyy-MM-dd').format(nextMessage.createdAt);
                    if (messageDate != nextMessageDate) {
                      showDateHeader = true;
                    }
                  } else {
                    showDateHeader = true;
                  }

                  if (index > 0) {
                    final nextMessage =
                        ChatController.anchorOf(rows[index - 1]);
                    if (nextMessage.senderPhone == message.senderPhone) {
                      isLastInGroup = false;
                    }
                  }

                  return _MessageBubble(
                    key: controller.getKeyForMessage(message.id),
                    message: message,
                    album: row,
                    isMe: isMe,
                    isFirstInGroup: isFirstInGroup,
                    isLastInGroup: isLastInGroup,
                    showDateHeader: showDateHeader,
                    controller: controller,
                  );
                },
              );
            },
          ),
        ),
        _buildMessageInput(context),
      ],
    );
  }

  /// The header. A group says how many people are in it; a direct chat says
  /// whether the other person is around, which is the thing a sender actually
  /// wants to know before they type.
  PreferredSizeWidget _buildAppBar(BuildContext context) {
    if (controller.isSearching) return _buildSearchAppBar(context);

    return CustomAppBar(
      centerTitle: false,
      titleWidget: GetBuilder<ChatController>(
        tag: widget.tag,
        builder: (c) => GetBuilder<ChatListController>(
          // One builder for both halves of the header: the member stream the
          // chat list already holds carries the presence dot *and* the faces
          // the group icon is made of.
          builder: (list) => Row(
            children: [
              _isDirect
                  ? _peerAvatar(context, c.thread)
                  : GroupAvatar(
                      imageUrl: c.groupInfo.imageUrl,
                      members: list.houseMembers,
                      size: 40,
                      gapColor: Theme.of(context).cardColor,
                    ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      c.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                        color: AppUi.body(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    _buildSubtitle(context, c, list),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'search'.tr,
          icon: Icon(Icons.search_rounded, color: AppUi.body(context)),
          onPressed: controller.toggleSearch,
        ),
        _buildChatMenu(context),
      ],
    );
  }

  /// The header while a search is open: the field takes the whole bar, and
  /// the only way out is the cross — the thread is not on screen to go back
  /// to.
  PreferredSizeWidget _buildSearchAppBar(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool typed = controller.searchQuery.trim().isNotEmpty;
    final int matches = typed ? controller.searchResults.length : 0;

    return CustomAppBar(
      centerTitle: false,
      // The arrow leaves the search, not the conversation — the same thing
      // the back gesture does while this bar is up.
      leading: IconButton(
        tooltip: 'cancel'.tr,
        icon: Icon(Icons.arrow_back_ios, size: 20, color: AppUi.body(context)),
        onPressed: controller.closeSearch,
      ),
      titleWidget: Container(
        height: 42,
        padding: const EdgeInsets.only(left: 14, right: 5),
        decoration: BoxDecoration(
          color: AppUi.neutralSurface(context),
          borderRadius: BorderRadius.circular(21),
          border: Border.all(color: primary.withOpacity(0.35), width: 1.2),
        ),
        child: Row(
          children: [
            Icon(Icons.search_rounded, size: 19, color: primary),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                controller: controller.searchController,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: controller.onSearchChanged,
                cursorColor: primary,
                cursorWidth: 1.6,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.2,
                  color: AppUi.body(context),
                ),
                decoration: InputDecoration(
                  hintText: 'search_messages'.tr,
                  hintStyle: TextStyle(
                    color: AppUi.muted(context),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w400,
                  ),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
            // How many hits, right where the eye already is while typing —
            // the list below does not have to be looked at to know whether
            // the word is in here at all.
            if (typed) ...[
              Text(
                '$matches',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: matches == 0 ? AppUi.muted(context) : primary,
                ),
              ),
              const SizedBox(width: 4),
              // Empties the field without closing the search: the next word
              // is usually typed straight after the last one failed.
              _SearchIconButton(
                icon: Icons.close_rounded,
                tooltip: 'clear'.tr,
                onTap: () {
                  controller.searchController.clear();
                  controller.onSearchChanged('');
                },
              ),
            ] else
              const SizedBox(width: 4),
          ],
        ),
      ),
      actions: const [SizedBox(width: 14)],
    );
  }

  /// What the conversation offers beyond the conversation itself.
  ///
  /// Every thread has a gallery — the pictures in it are worth reaching
  /// without scrolling back through everything that was said around them.
  /// The rest is the group's own furniture: what it is pinned, what it is
  /// called, what it looks like. A direct chat is named after the person it
  /// is with and pins nothing.
  Widget _buildChatMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: AppUi.body(context)),
      tooltip: 'options'.tr,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        if (value == 'media') openChatMedia(tag: widget.tag);
        if (value == 'settings') showGroupSettingsSheet(context);
        if (value == 'pinned') _openPinned();
        if (value == 'delete') _confirmDeleteChat();
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'media',
          child: Row(
            children: [
              Icon(Icons.photo_library_outlined,
                  size: 19, color: AppUi.muted(context)),
              const SizedBox(width: 12),
              Text('media'.tr),
            ],
          ),
        ),
        if (!_isDirect)
        PopupMenuItem<String>(
          value: 'pinned',
          child: Row(
            children: [
              Icon(Icons.push_pin_outlined,
                  size: 19, color: AppUi.muted(context)),
              const SizedBox(width: 12),
              Text('pinned_messages'.tr),
              // The banner only appears once something is pinned, so the
              // count belongs here too — it is the one way in that is always
              // on screen.
              if (controller.pinnedCount > 0) ...[
                const SizedBox(width: 8),
                Text(
                  '${controller.pinnedCount}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (!_isDirect)
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              Icon(Icons.settings_outlined,
                  size: 19, color: AppUi.muted(context)),
              const SizedBox(width: 12),
              Text('group_settings'.tr),
            ],
          ),
        ),
        // Last, and the only one in red: everything above this opens
        // something, and this one takes something away. Direct chats only —
        // the house group is not one member's to delete.
        if (_isDirect)
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              const Icon(Icons.delete_outline_rounded,
                  size: 19, color: Colors.red),
              const SizedBox(width: 12),
              Text(
                'delete_chat'.tr,
                style: const TextStyle(color: Colors.red),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// Asks before emptying the thread, and says whose copy is going.
  ///
  /// Worth spelling out, because a member reading "delete" reasonably fears
  /// they are about to take the conversation away from the person they were
  /// having it with — and what actually happens is the opposite: the other
  /// end keeps every word, and the next message still arrives here.
  void _confirmDeleteChat() {
    showConfirmDialog(
      title: 'delete_chat'.tr,
      message:
          'delete_chat_confirm'.trParams({'name': controller.thread.peerName}),
      detail: 'delete_chat_note'.tr,
      confirmText: 'delete'.tr,
      onConfirm: () async {
        await controller.clearHistory();
        CustomSnackbar.show(
          message: 'chat_deleted'.tr,
          type: SnackbarType.success,
        );
      },
    );
  }

  void _openPinned() => Get.to(() => const PinnedMessagesScreen());

  /// "Active now", "Active 20m ago" — or, for the group, how many members it
  /// has. While somebody is writing, it says that instead: whatever else this
  /// line could say, that is the one worth the space.
  Widget _buildSubtitle(
    BuildContext context,
    ChatController c,
    ChatListController list,
  ) {
    // Somebody writing outranks whether they are around: it is the newer
    // news, and it is what a reader is watching this line for.
    final String? typing = c.typingLabel;
    if (typing != null) {
      return Text(
        typing,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      );
    }

    final ChatUser? peer = list.userByPhone(c.thread.peerPhone);
    final bool online = _isDirect && (peer?.isOnline ?? false);

    final String label = _isDirect
        ? presenceLabel(peer)
        : (list.memberCount > 0
            ? 'member_count'.trParams({'count': '${list.memberCount}'})
            : 'house_group_subtitle'.tr);

    return PresenceLine(label: label, online: online, fontSize: 12);
  }

  Widget _peerAvatar(BuildContext context, ChatThread thread) {
    final Color primary = Theme.of(context).colorScheme.primary;
    return ProfileAvatar(
      name: thread.peerName,
      phone: thread.peerPhone,
      imageUrl: thread.peerImage,
      size: 40,
      background: primary.withOpacity(0.15),
      foreground: primary,
      fontSize: 15,
    );
  }

  Widget _buildMessageInput(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.05),
            blurRadius: 15,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            GetBuilder<ChatController>(
              tag: widget.tag,
              builder: (controller) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (controller.isMentioning) _buildMentionSuggestionBox(context),
                    if (controller.replyingToMessage != null) _buildReplyPreview(context),
                    if (controller.editingMessage != null) _buildEditPreview(context),
                    if (controller.pendingAttachments.isNotEmpty)
                      _buildAttachmentStrip(context),
                  ],
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: GetBuilder<VoiceRecorderController>(
                tag: widget.tag,
                builder: (recorder) => Row(
                  children: [
                    Expanded(
                      child: recorder.isRecording
                          ? VoiceRecorderBar(
                              recorder: recorder,
                              onCancel: recorder.cancel,
                            )
                          : _buildComposerField(context),
                    ),
                    const SizedBox(width: 12),
                    _buildComposerAction(context, recorder),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The rounded pill the composer types into: the picture button, the text
  /// field, and nothing else. Lifted out because while a voice message is
  /// being recorded it is not there at all — the recording bar stands in its
  /// place, and the two read better side by side than nested.
  Widget _buildComposerField(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        children: [
          // Camera or gallery — the same menu the profile
          // screen uses, minus the "remove" entry. Hidden
          // while editing: a picture cannot join a message
          // that has already been sent.
          GetBuilder<ChatController>(
            tag: widget.tag,
            builder: (controller) =>
                controller.editingMessage != null
                    ? const SizedBox(width: 16)
                    : IconButton(
                        tooltip: 'send_photo'.tr,
                        icon: Icon(
                          Icons.add_photo_alternate_outlined,
                          color: Theme.of(context)
                              .colorScheme
                              .primary,
                        ),
                        onPressed: () => showPhotoSourceSheet(
                          context,
                          onPick: controller.pickChatImages,
                        ),
                      ),
          ),
          Expanded(
            child: GetBuilder<ChatController>(
              tag: widget.tag,
              builder: (controller) => TextField(
                controller: controller.messageController,
                focusNode: controller.messageFocusNode,
                textCapitalization: TextCapitalization.sentences,
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  // Once a picture is attached, whatever is
                  // typed becomes its caption.
                  hintText: controller.pendingAttachments.isEmpty
                      ? 'type_message'.tr
                      : 'add_caption'.tr,
                  hintStyle: TextStyle(color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6)),
                  border: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  /// The one round button at the end of the composer, which is three buttons
  /// depending on what there is to do with it.
  ///
  /// A microphone when the composer is empty, held down to record — the
  /// gesture every chat app has settled on, and the reason there is no
  /// separate voice screen. A paper plane once there is something to send. A
  /// tick while an already-sent message is being corrected. Once a recording
  /// is locked it becomes the send for that, since there is no longer a
  /// finger on it to let go of.
  Widget _buildComposerAction(
      BuildContext context, VoiceRecorderController recorder) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return GetBuilder<ChatController>(
      tag: widget.tag,
      builder: (chat) => ValueListenableBuilder<TextEditingValue>(
        // The swap between microphone and paper plane happens on a keystroke,
        // which is not something the chat controller redraws for.
        valueListenable: chat.messageController,
        builder: (context, typed, _) {
          final bool hasSomethingToSend = typed.text.trim().isNotEmpty ||
              chat.pendingAttachments.isNotEmpty ||
              chat.editingMessage != null;
          // A locked recording is sent by tapping; a held one by letting go.
          final bool sends = recorder.isLocked || hasSomethingToSend;
          final bool recording = recorder.isRecording;

          final IconData icon = recorder.isLocked
              ? Icons.send_rounded
              : hasSomethingToSend
                  ? (chat.editingMessage != null
                      ? Icons.check_rounded
                      : Icons.send_rounded)
                  : Icons.mic_rounded;

          return GestureDetector(
            onTap: () {
              if (recorder.isLocked) {
                _finishRecording();
              } else if (hasSomethingToSend) {
                chat.sendMessage();
              } else if (!recording) {
                // A tap is not a recording. Say what would have been.
                CustomSnackbar.show(
                  type: SnackbarType.info,
                  message: 'hold_to_record'.tr,
                );
              }
            },
            onLongPressStart: sends ? null : (_) => _startRecording(),
            onLongPressMoveUpdate: sends
                ? null
                : (details) =>
                    recorder.trackDrag(details.localOffsetFromOrigin),
            onLongPressEnd: sends ? null : (_) => _releaseRecording(),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: EdgeInsets.all(recording && !recorder.isLocked ? 18 : 12),
              decoration: BoxDecoration(
                color: recorder.willCancel
                    ? Theme.of(context).colorScheme.error
                    : primary,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: primary.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Icon(
                recorder.willCancel ? Icons.delete_outline_rounded : icon,
                color: Colors.white,
                size: 24,
              ),
            ),
          );
        },
      ),
    );
  }

  /// Opens the microphone. If the finger came up while the permission sheet
  /// was still on screen, the recording is closed the moment it opens — which
  /// is what a tap means.
  Future<void> _startRecording() async {
    _micReleased = false;
    // Recording over a voice message that is still playing would record it
    // as well as the sender.
    if (Get.isRegistered<VoicePlayerService>()) {
      await Get.find<VoicePlayerService>().stop();
    }
    final bool started = await _recorder.start();
    if (!mounted || !started) return;
    if (_micReleased) await _finishRecording();
  }

  /// The finger has come up. Locked recordings ignore it — they are the ones
  /// that carry on without it.
  Future<void> _releaseRecording() async {
    _micReleased = true;
    if (!_recorder.isRecording || _recorder.isLocked) return;
    await _finishRecording();
  }

  /// Ends a recording the way the gesture asked for: dropped if the finger
  /// slid far enough left, sent otherwise. Anything under a second is neither
  /// — see `VoiceRecorderController.minimum`.
  Future<void> _finishRecording() async {
    final VoiceRecorderController recorder = _recorder;
    if (!recorder.isRecording) return;

    if (recorder.willCancel) {
      await recorder.cancel();
      return;
    }

    final RecordedVoice? clip = await recorder.stop();
    if (clip == null) return;
    await controller.sendVoice(clip);
  }

  /// Sits where the reply preview sits, for the same reason: the composer has
  /// stopped being a blank sheet and the sender should be able to see that at
  /// a glance.
  Widget _buildEditPreview(BuildContext context) {
    final message = controller.editingMessage!;
    final Color primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.edit_rounded, color: primary, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'editing_message'.tr,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: primary,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: () => controller.cancelEditing(clearText: true),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: Colors.grey.shade600,
          ),
        ],
      ),
    );
  }

  /// The pictures waiting in the composer. Scrolls sideways, and each one can
  /// be dropped before the send.
  Widget _buildAttachmentStrip(BuildContext context) {
    final List<PickedImage> attachments = controller.pendingAttachments;

    return Container(
      height: 92,
      width: double.infinity,
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: attachments.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, index) {
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: LocalImage(
                        attachments[index].file.path,
                        width: 68,
                        height: 68,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: () => controller.removeAttachment(index),
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.65),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Theme.of(context).cardColor,
                              width: 1.5,
                            ),
                          ),
                          child: const Icon(Icons.close_rounded,
                              size: 13, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          IconButton(
            tooltip: 'cancel'.tr,
            icon: const Icon(Icons.delete_outline_rounded, size: 20),
            color: Theme.of(context).colorScheme.error,
            onPressed: controller.clearAttachments,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildReplyPreview(BuildContext context) {
    final message = controller.replyingToMessage!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
      ),
      child: Row(
        children: [
          Icon(Icons.reply_rounded, color: Theme.of(context).colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'replying_to'.trParams({'name': message.senderName}),
                  style: TextStyle(
                    fontWeight: FontWeight.bold, 
                    color: Theme.of(context).colorScheme.primary, 
                    fontSize: 13
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  // A picture with no caption still needs something to quote.
                  message.preview,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.7), fontSize: 13),
                ),
              ],
            ),
          ),
          if (message.hasImage) ...[
            const SizedBox(width: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                message.imageUrl!,
                width: 38,
                height: 38,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            onPressed: controller.cancelReply,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            color: Colors.grey.shade600,
          ),
        ],
      ),
    );
  }

  Widget _buildMentionSuggestionBox(BuildContext context) {
    if (controller.filteredMentionUsers.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Container(
      constraints: const BoxConstraints(maxHeight: 150),
      margin: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      // The surface lives on a Material, not on the Container's decoration,
      // so the tiles below can paint their ink splashes.
      child: Material(
        color: Theme.of(context).cardColor,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Theme.of(context).dividerColor),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: EdgeInsets.zero,
          itemCount: controller.filteredMentionUsers.length,
          itemBuilder: (context, index) {
            final user = controller.filteredMentionUsers[index];
            final name = user['name'] ?? 'unknown'.tr;

            return ListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              leading: ProfileAvatar(
                name: name,
                phone: user['phone']?.toString(),
                imageUrl: user['image']?.toString(),
                size: 28,
                background: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                foreground: Theme.of(context).colorScheme.primary,
                fontSize: 12,
              ),
              title:
                  Text(name, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              onTap: () => controller.insertMention(name),
            );
          },
        ),
      ),
    );
  }
}

/// The mark at the top of the thread while the page above it is being read
/// back — see `ChatController.loadOlderMessages`. Small and quiet: it is not
/// an empty screen waiting to be filled, it is a conversation that already
/// has plenty on it.
class _HistoryLoader extends StatelessWidget {
  const _HistoryLoader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary.withOpacity(0.6),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final ChatMessageModel message;

  /// Every message this bubble stands for, newest first. One entry for
  /// anything sent on its own; for a batch of pictures, all of them — and
  /// [message] is then the first of the send, the one carrying the caption.
  final List<ChatMessageModel> album;
  final bool isMe;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final bool showDateHeader;
  final ChatController controller;
  final LayerLink _layerLink = LayerLink();

  _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.showDateHeader,
    required this.controller,
    List<ChatMessageModel>? album,
  }) : album = album ?? <ChatMessageModel>[message];

  /// Whether this bubble is drawing several pictures rather than one.
  bool get _isAlbum => album.length > 1;

  @override
  Widget build(BuildContext context) {
    final showTime = controller.forceShowTimeMessageId == message.id;
    final isHighlighted = controller.highlightedMessageId == message.id;

    return Column(
      children: [
        if (showDateHeader)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _getFormattedDate(message.createdAt),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                ),
              ),
            ),
          ),
        Dismissible(
          key: Key(message.id.isEmpty ? message.hashCode.toString() : message.id),
          // Nothing to quote once a message is gone.
          direction: message.deleted
              ? DismissDirection.none
              : DismissDirection.startToEnd,
          confirmDismiss: (direction) async {
            controller.setReply(message);
            return false;
          },
          background: Container(
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.only(left: 20),
            child: Icon(Icons.reply_rounded, color: Theme.of(context).colorScheme.primary),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 500),
            padding: EdgeInsets.only(
              bottom: isLastInGroup ? 8 : 2,
              top: isFirstInGroup ? 16 : 0,
            ),
            decoration: BoxDecoration(
              color: isHighlighted ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.transparent,
            ),
            child: Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe && isLastInGroup)
                  Container(
                    margin: const EdgeInsets.only(right: 4),
                    // The URL stamped on the message is only as fresh as the
                    // moment it was sent, so the directory gets first refusal
                    // and the stamped one is the fallback.
                    child: ProfileAvatar(
                      name: message.senderName,
                      phone: message.senderPhone,
                      imageUrl: message.senderImage,
                      size: 28,
                      background: Colors.amber.shade100,
                      foreground: Colors.amber,
                      fontSize: 12,
                    ),
                  )
                else if (!isMe)
                  const SizedBox(width: 32),

                Flexible(
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: isMe ? 50 : 0,
                      right: !isMe ? 50 : 0,
                    ),
                    child: Column(
                      crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                      children: [
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CompositedTransformTarget(
                              link: _layerLink,
                              child: GestureDetector(
                                // A deleted message has nothing left to react
                                // to, reply to or copy.
                                onLongPress: message.deleted
                                    ? null
                                    : () {
                                        HapticFeedback.mediumImpact();
                                        _showReactionPicker(context, controller, message, _layerLink, isMe);
                                      },
                                // A message the app composed goes where it
                                // came from; anything somebody typed shows
                                // its clock instead.
                                onTap: message.hasAction && !message.deleted
                                    ? () => _openAction(context)
                                    : () =>
                                        controller.toggleTimeDisplay(message.id),
                                child: Container(
                                  // A picture sits tight against the bubble
                                  // edge; only text needs the roomy padding.
                                  // A picture sits tight against the bubble
                                  // edge and a voice message nearly so — its
                                  // play button is already round. Only text
                                  // needs the roomy padding.
                                  padding: message.hasImage
                                      ? EdgeInsets.only(
                                          left: 4,
                                          right: 4,
                                          top: 4,
                                          bottom: (message.reactions != null && message.reactions!.isNotEmpty) ? 16 : 4,
                                        )
                                      : message.hasAudio
                                          ? EdgeInsets.only(
                                              left: 8,
                                              right: 12,
                                              top: 8,
                                              bottom: (message.reactions != null && message.reactions!.isNotEmpty) ? 20 : 8,
                                            )
                                          : EdgeInsets.only(
                                          left: 16,
                                          right: 16,
                                          top: 12,
                                          bottom: (message.reactions != null && message.reactions!.isNotEmpty) ? 20 : 12,
                                        ),
                                  decoration: BoxDecoration(
                                    color: isMe 
                                        ? Theme.of(context).colorScheme.primary 
                                        : (Theme.of(context).brightness == Brightness.dark 
                                            ? Theme.of(context).cardColor 
                                            : Colors.black.withOpacity(0.05)),
                                    borderRadius: BorderRadius.only(
                                      topLeft: Radius.circular(!isMe ? (isFirstInGroup ? 20 : 4) : 20),
                                      topRight: Radius.circular(isMe ? (isFirstInGroup ? 20 : 4) : 20),
                                      bottomLeft: Radius.circular(!isMe ? (isLastInGroup ? 20 : 4) : 20),
                                      bottomRight: Radius.circular(isMe ? (isLastInGroup ? 20 : 4) : 20),
                                    ),
                                  ),
                                  child: message.deleted
                                      ? _buildDeletedContent(context)
                                      : Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      if (message.replyToText != null)
                                        Padding(
                                          padding: EdgeInsets.symmetric(
                                              horizontal: message.hasImage ? 4 : 0),
                                          child: _buildReplyContent(context),
                                        ),
                                      if (message.hasImage)
                                        _isAlbum
                                            ? _buildAlbum(context)
                                            : _buildImage(context),
                                      if (message.hasAudio)
                                        VoiceBubble(
                                          id: message.id,
                                          url: message.audioUrl!,
                                          stamped: message.audioDuration,
                                          waveform: message.audioWave ??
                                              const <int>[],
                                          isMe: isMe,
                                        ),
                                      if (message.text.trim().isNotEmpty)
                                        Padding(
                                          padding: message.hasImage
                                              ? const EdgeInsets.fromLTRB(8, 8, 8, 4)
                                              : EdgeInsets.zero,
                                          child: RichText(
                                            text: TextSpan(
                                              children: _parseMentionText(message.text, context, isMe),
                                              style: TextStyle(
                                                fontSize: 15,
                                                height: 1.3,
                                                color: isMe ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                                              ),
                                            ),
                                          ),
                                        ),
                                      if (message.hasAction && !message.deleted)
                                        _buildActionFooter(context),
                                      if (message.isEdited) _buildEditedMark(context),
                                      if (isMe && message.isPending)
                                        _buildPendingMark(context),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            
                            if (message.reactions != null && message.reactions!.isNotEmpty)
                              Positioned(
                                bottom: -12,
                                right: isMe ? 0 : null,
                                left: !isMe ? 0 : null,
                                child: _buildReactions(context, message, isMe),
                              ),
                          ],
                        ),
                        
                        if (message.reactions != null && message.reactions!.isNotEmpty)
                          const SizedBox(height: 12),
                        
                        _buildSeenAvatars(context),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (showTime)
          Padding(
            padding: EdgeInsets.only(
              top: 4,
              left: isMe ? 0 : 48,
              right: isMe ? 8 : 0,
            ),
            child: Text(
              DateFormat('hh:mm a').format(message.createdAt),
              style: TextStyle(
                fontSize: 10,
                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
              ),
            ),
          ),
      ],
    );
  }

  /// `Tap to see details` under a message the app composed.
  ///
  /// Rendered from the message's action rather than written into its words,
  /// so the line and the behaviour cannot disagree — and so it arrives in
  /// each reader's own language rather than the sender's.
  Widget _buildActionFooter(BuildContext context) {
    final Color color = isMe
        ? Colors.white.withOpacity(0.9)
        : Theme.of(context).colorScheme.primary;

    return Padding(
      padding: EdgeInsets.only(
        top: 8,
        left: message.hasImage ? 8 : 0,
        right: message.hasImage ? 8 : 0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Divider(height: 1, thickness: 1, color: color.withOpacity(0.25)),
          const SizedBox(height: 6),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.insights_rounded, size: 13, color: color),
              const SizedBox(width: 6),
              Text(
                'tap_to_see_details'.tr,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Opens whatever the message points at. An action this build does not know
  /// — one added by a newer version — leaves the words on screen and does
  /// nothing, which is the only safe answer.
  void _openAction(BuildContext context) {
    if (message.action != ChatMessageModel.actionMonthlySummary) return;
    // The months there each carry a figure; the launch only worked out this
    // one — see MonthlyStatsController.ensureHistory.
    if (Get.isRegistered<MonthlyStatsController>()) {
      Get.find<MonthlyStatsController>().ensureHistory();
    }
    Get.to(() => const MonthlyStatsScreen());
  }

  /// A small clock under the words while the message is on this device only
  /// — Firestore has it, the server does not yet. Gone the moment it lands.
  ///
  /// The words beside it only appear when the app knows it is offline. On a
  /// working connection this state lasts a few hundred milliseconds, and a
  /// line of text flashing under every sent message reads as a stutter; the
  /// clock alone is enough. Waiting with no connection is the case that
  /// actually needs explaining.
  Widget _buildPendingMark(BuildContext context) {
    final bool explain = !controller.isOnline;

    return Padding(
      padding: EdgeInsets.only(
        top: 3,
        left: message.hasImage ? 8 : 0,
        right: message.hasImage ? 8 : 0,
        bottom: message.hasImage ? 4 : 0,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.schedule_rounded,
              size: 11, color: Colors.white.withOpacity(0.75)),
          if (explain) ...[
            const SizedBox(width: 3),
            Text(
              'waiting_to_sync'.tr,
              style: TextStyle(
                fontSize: 10,
                color: Colors.white.withOpacity(0.75),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// What is left of a deleted message. The bubble stays so replies pointing
  /// at it still land somewhere, and so the gap is explained rather than
  /// mysterious.
  Widget _buildDeletedContent(BuildContext context) {
    final Color color = isMe
        ? Colors.white.withOpacity(0.75)
        : (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey)
            .withOpacity(0.8);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.block_rounded, size: 15, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            message.deletedByAdmin
                ? 'message_deleted_by_admin'.tr
                : 'message_deleted'.tr,
            style: TextStyle(
              fontSize: 14,
              height: 1.3,
              fontStyle: FontStyle.italic,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  /// `edited` — and who by, when that was not the person who wrote it.
  Widget _buildEditedMark(BuildContext context) {
    final Color color = isMe
        ? Colors.white.withOpacity(0.7)
        : (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey)
            .withOpacity(0.7);

    return Padding(
      padding: EdgeInsets.only(
        top: 3,
        left: message.hasImage ? 8 : 0,
        right: message.hasImage ? 8 : 0,
        bottom: message.hasImage ? 4 : 0,
      ),
      child: Text(
        message.editedByOther ? 'edited_by_admin'.tr : 'edited'.tr,
        style: TextStyle(
          fontSize: 10,
          fontStyle: FontStyle.italic,
          color: color,
        ),
      ),
    );
  }

  /// Ties the bubble's picture to the full-screen one so they fly into each
  /// other. Unique per message, which is all a hero tag has to be.
  String get _imageHeroTag => 'chat_image_${message.id}';

  /// Opens the thread's pictures, starting at this one.
  ///
  /// Every picture in the thread rather than only the one that was tapped:
  /// a photo opened from a conversation is expected to swipe on to the next,
  /// which a single-picture screen cannot do however it is dressed up. Same
  /// viewer the gallery uses, so the zoom, the counter, the strip along the
  /// bottom and the way back to the message all come with it — only the list
  /// differs, and this one is the thread's own, oldest first, the order it is
  /// read in.
  void _openImage(BuildContext context, [ChatMessageModel? tapped]) {
    final ChatMessageModel target = tapped ?? message;
    final List<ChatMessageModel> photos = <ChatMessageModel>[
      for (final ChatMessageModel item in controller.messages.reversed)
        if (!item.deleted && (item.imageUrl?.isNotEmpty ?? false)) item,
    ];

    final int index = photos.indexWhere((item) => item.id == target.id);
    // Only reachable if the thread moved under the tap. Nothing to open, and
    // a viewer on a picture that is no longer there is worse than nothing.
    if (index < 0) return;

    Get.to(
      () => ChatMediaViewer(
        items: photos,
        initialIndex: index,
        // The width a bubble is capped at — the copy already decoded for the
        // thread stands in until the full-size one arrives.
        thumbCacheWidth:
            (240 * MediaQuery.of(context).devicePixelRatio).round(),
        heroTagFor: (ChatMessageModel item) => 'chat_image_${item.id}',
        onJumpToMessage: (ChatMessageModel item) {
          Get.back();
          controller.scrollToMessage(item.id);
        },
      ),
      // Black on black: the picture is already on screen and flying into
      // place, so a slide underneath it only reads as a stutter.
      opaque: false,
      transition: Transition.fadeIn,
      duration: const Duration(milliseconds: 220),
      preventDuplicates: false,
    );
  }

  /// The picture inside a bubble.
  ///
  /// Laid out from the dimensions stamped on the message, so the thread keeps
  /// its shape while the bytes are still coming down — the bubble never jumps
  /// under a reader's thumb. A tap opens it full screen, at this picture,
  /// with the rest of the thread's a swipe away.
  Widget _buildImage(BuildContext context) {
    return GestureDetector(
      onTap: () => _openImage(context),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240, maxHeight: 320),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: message.imageAspectRatio,
            child: Hero(
              tag: _imageHeroTag,
              child: Image.network(
                message.imageUrl!,
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) {
                  if (progress == null) return child;
                  return Container(
                    color: Colors.black.withOpacity(0.06),
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 26,
                      height: 26,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: isMe
                            ? Colors.white
                            : Theme.of(context).colorScheme.primary,
                        value: progress.expectedTotalBytes == null
                            ? null
                            : progress.cumulativeBytesLoaded /
                                progress.expectedTotalBytes!,
                      ),
                    ),
                  );
                },
                errorBuilder: (_, __, ___) => Container(
                  color: Colors.black.withOpacity(0.06),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.broken_image_outlined,
                          color: isMe ? Colors.white70 : Colors.grey, size: 28),
                      const SizedBox(height: 6),
                      Text(
                        'image_load_failed'.tr,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          color: isMe ? Colors.white70 : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The pictures of one send, drawn as a grid.
  ///
  /// Every picture is still its own message underneath — a tap opens that one
  /// in the viewer, and the gallery lists them separately — but a batch reads
  /// as one thing arriving, so it is drawn as one thing. Two side by side,
  /// three as a wide one over a pair, four as a square; past four the fourth
  /// tile counts what is behind it, the way every chat app does.
  ///
  /// The bubble is the same width a single picture is capped at, so a thread
  /// of mixed sends keeps one edge.
  Widget _buildAlbum(BuildContext context) {
    // Oldest first: the order they were picked, and the order they were sent.
    final List<ChatMessageModel> shots = album.reversed.toList();
    const double gap = 2;

    // Laid out in fractions rather than pixels — the bubble is capped at the
    // width a single picture is capped at, and gives way on a narrow screen
    // the same as one does.
    Widget half(int i, {int extra = 0}) => Expanded(
          child: AspectRatio(
            aspectRatio: 1,
            child: _albumTile(context, shots[i], 120, extra: extra),
          ),
        );

    Widget wide(int i) => AspectRatio(
          aspectRatio: 8 / 5,
          child: _albumTile(context, shots[i], 240),
        );

    Widget pair(int a, int b, {int extra = 0}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            half(a),
            const SizedBox(width: gap),
            half(b, extra: extra),
          ],
        );

    late final Widget grid;
    if (shots.length == 2) {
      grid = pair(0, 1);
    } else if (shots.length == 3) {
      grid = Column(
        mainAxisSize: MainAxisSize.min,
        children: [wide(0), const SizedBox(height: gap), pair(1, 2)],
      );
    } else {
      // Four tiles whatever the count; anything past them is a number on the
      // last one, and the viewer has the rest a swipe away.
      grid = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          pair(0, 1),
          const SizedBox(height: gap),
          pair(2, 3, extra: shots.length - 4),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: grid,
      ),
    );
  }

  /// One picture of a grid. [extra], when there is one, is how many more the
  /// send carried than the grid has room for.
  Widget _albumTile(
    BuildContext context,
    ChatMessageModel shot,
    double approxWidth, {
    int extra = 0,
  }) {
    // A tile is a fraction of the bubble, so the full-width decode a single
    // picture needs would be several times the pixels that ever reach the
    // screen — and a batch of ten of them is what runs a phone out of memory.
    // A hint, not a measurement: the tile takes its real size from the grid.
    final int cacheWidth =
        (approxWidth * MediaQuery.of(context).devicePixelRatio).round();

    return GestureDetector(
      onTap: () => _openImage(context, shot),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Hero(
            tag: 'chat_image_${shot.id}',
            child: Image.network(
              shot.imageUrl!,
              fit: BoxFit.cover,
              cacheWidth: cacheWidth,
              loadingBuilder: (context, child, progress) {
                if (progress == null) return child;
                return Container(
                  color: Colors.black.withOpacity(0.06),
                  alignment: Alignment.center,
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: isMe
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary,
                      value: progress.expectedTotalBytes == null
                          ? null
                          : progress.cumulativeBytesLoaded /
                              progress.expectedTotalBytes!,
                    ),
                  ),
                );
              },
              errorBuilder: (_, __, ___) => Container(
                color: Colors.black.withOpacity(0.06),
                alignment: Alignment.center,
                child: Icon(Icons.broken_image_outlined,
                    color: isMe ? Colors.white70 : Colors.grey, size: 22),
              ),
            ),
          ),
          if (extra > 0)
            Container(
              color: Colors.black.withOpacity(0.45),
              alignment: Alignment.center,
              child: Text(
                '+$extra',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSeenAvatars(BuildContext context) {
    // The writer of a message is never one of the people who "saw" it — their
    // own send marks it read on their device, which would otherwise put their
    // face in the row under their own bubble.
    //
    // Across the whole row, not just the bubble's anchor: a read receipt
    // points at the newest message somebody has seen, which for an album is
    // the last picture of it rather than the first — the one this bubble is
    // hung on. One face per person however many of them they landed on.
    final Map<String, Map<String, dynamic>> byPhone = {};
    for (final ChatMessageModel item in album) {
      for (final status in controller.messageSeenBy[item.id] ?? const []) {
        final String phone = status['userPhone']?.toString() ?? '';
        if (phone.isEmpty || phone == message.senderPhone) continue;
        byPhone[phone] = status;
      }
    }
    final seenBy = byPhone.values.toList();
    if (seenBy.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Wrap(
            spacing: -4, // Overlap avatars slightly
            children: seenBy.map((status) {
              final imageUrl = status['userImage'];
              final name = status['userName'] ?? '';
              
              return Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 1.5),
                ),
                child: ProfileAvatar(
                  name: name,
                  phone: status['userPhone']?.toString(),
                  imageUrl: imageUrl?.toString(),
                  size: 14,
                  background: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                  foreground: Theme.of(context).colorScheme.primary,
                  fontSize: 5,
                ),
              );
            }).toList(),
          ),
          const SizedBox(width: 6),
          Text(
            'seen'.tr,
            style: TextStyle(
              fontSize: 9,
              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReplyContent(BuildContext context) {
    return GestureDetector(
      onTap: () {
        if (message.replyToMessageId != null) {
          controller.scrollToMessage(message.replyToMessageId!);
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: isMe ? Colors.white.withOpacity(0.2) : Theme.of(context).colorScheme.primary.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border(
            left: BorderSide(
              color: isMe ? Colors.white : Theme.of(context).colorScheme.primary, 
              width: 3
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.replyToSenderName ?? 'unknown'.tr,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                      color: isMe ? Colors.white : Theme.of(context).colorScheme.primary
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    message.replyToText!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isMe ? Colors.white.withOpacity(0.9) : Theme.of(context).textTheme.bodyMedium?.color
                    ),
                  ),
                ],
              ),
            ),
            // A quoted picture shows itself, the way a quoted line shows its
            // words.
            if (message.replyToImage != null) ...[
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(
                  message.replyToImage!,
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showReactionPicker(BuildContext context, ChatController controller, ChatMessageModel message, LayerLink link, bool isMe) {
    late OverlayEntry overlayEntry;
    
    overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          GestureDetector(
            onTap: () => overlayEntry.remove(),
            child: Container(color: Colors.transparent),
          ),
          CompositedTransformFollower(
            link: link,
            showWhenUnlinked: false,
            targetAnchor: isMe ? Alignment.topRight : Alignment.topLeft,
            followerAnchor: isMe ? Alignment.bottomRight : Alignment.bottomLeft,
            offset: const Offset(0, -5), // Positioned 5px above the bubble
            child: Material(
              color: Colors.transparent,
              child: _ReactionPickerWidget(
                onEmojiSelected: (emoji) {
                  controller.reactToMessage(message, emoji);
                  overlayEntry.remove();
                },
                onMoreTapped: () {
                  overlayEntry.remove();
                  _showMessageActions(context, controller, message);
                },
              ),
            ),
          ),
        ],
      ),
    );

    Overlay.of(context).insert(overlayEntry);
  }

  /// Everything that can be done to a message that is not a reaction.
  ///
  /// Reached from the "⋯" at the end of the reaction row rather than a second
  /// long-press: a sheet can grow entries without ever running off the top of
  /// the screen, which an anchored menu above the bubble would.
  void _showMessageActions(
    BuildContext context,
    ChatController controller,
    ChatMessageModel message,
  ) {
    final bool canEdit = controller.canEdit(message);
    final bool canDelete = controller.canDelete(message);
    final bool hasText = message.text.trim().isNotEmpty;
    final bool pinned = controller.isPinned(message.id);
    final Color error = Theme.of(context).colorScheme.error;

    Get.bottomSheet(
      SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.reply_rounded),
              title: Text('reply'.tr),
              onTap: () {
                closeOverlayRoute();
                controller.setReply(message);
              },
            ),
            // Anyone may pin. Keeping a rent reminder from scrolling away is
            // not an admin's errand, and asking one every time would mean it
            // never happened.
            if (controller.isGroupChat && message.id.isNotEmpty)
              ListTile(
                leading: Icon(pinned
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded),
                title: Text(pinned ? 'unpin_message'.tr : 'pin_message'.tr),
                onTap: () {
                  closeOverlayRoute();
                  controller.togglePin(message);
                },
              ),
            if (hasText)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: Text('copy'.tr),
                onTap: () {
                  closeOverlayRoute();
                  Clipboard.setData(ClipboardData(text: message.text));
                  CustomSnackbar.show(
                      type: SnackbarType.success, message: 'copied'.tr);
                },
              ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: Text('edit_message'.tr),
                // Spelled out, because editing another member's words is not
                // something to do by accident.
                subtitle: message.senderPhone != controller.userPhone
                    ? Text('as_admin'.tr, style: const TextStyle(fontSize: 11))
                    : null,
                onTap: () {
                  closeOverlayRoute();
                  controller.startEditing(message);
                },
              ),
            if (canDelete)
              ListTile(
                leading: Icon(Icons.delete_outline_rounded, color: error),
                title: Text('delete_message'.tr, style: TextStyle(color: error)),
                subtitle: message.senderPhone != controller.userPhone
                    ? Text('as_admin'.tr, style: const TextStyle(fontSize: 11))
                    : null,
                onTap: () {
                  closeOverlayRoute();
                  showConfirmDialog(
                    title: 'delete_message'.tr,
                    message: 'confirm_delete_message'.tr,
                    detail: message.preview,
                    confirmText: 'delete'.tr,
                    onConfirm: () => controller.deleteMessage(message),
                  );
                },
              ),
          ],
        ),
      ),
      backgroundColor: Theme.of(context).cardColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    );
  }

  Widget _buildReactions(BuildContext context, ChatMessageModel message, bool isMe) {
    final Map<String, int> counts = {};
    message.reactions!.forEach((user, emoji) {
      counts[emoji] = (counts[emoji] ?? 0) + 1;
    });

    return GestureDetector(
      onTap: () => _showReactionDetails(context, message),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withOpacity(1.0),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: Theme.of(context).dividerColor.withOpacity(0.5), width: 0.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: counts.entries.map((entry) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.key, 
                    style: const TextStyle(
                      fontSize: 12, // Reduced for compactness
                      color: Colors.black, // Force full color depth
                    )
                  ),
                  if (entry.value > 1) ...[
                    const SizedBox(width: 2),
                    Text(
                      entry.value.toString(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodySmall?.color,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showReactionDetails(BuildContext context, ChatMessageModel message) {
    if (message.reactions == null || message.reactions!.isEmpty) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.5,
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.2),
                blurRadius: 20,
                offset: const Offset(0, -5),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Reactions',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).textTheme.bodyLarge?.color,
                      ),
                    ),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Theme.of(context).dividerColor.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 20),
                      ),
                    ),
                  ],
                ),
              ),
              
              // List
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: message.reactions!.length,
                  itemBuilder: (context, index) {
                    final entry = message.reactions!.entries.elementAt(index);
                    final userPhone = entry.key;
                    final emoji = entry.value;
                    
                    // Lookup user details
                    final user = controller.allUsers.firstWhere(
                      (u) => u['phone'] == userPhone, 
                      orElse: () => <String, dynamic>{},
                    );
                    final name = user['name'] ?? 'Unknown';
                    final imageUrl = user['image'];
                    
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          ProfileAvatar(
                            name: name,
                            // The reaction key, not `user['phone']` — the
                            // lookup above yields an empty map for someone who
                            // has since left the house.
                            phone: userPhone,
                            imageUrl: imageUrl?.toString(),
                            size: 44,
                            background: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                            foreground: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Text(
                              name,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            emoji,
                            style: const TextStyle(
                              fontSize: 32, // Large for bottom sheet clarity
                              color: Colors.black,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),

              // Bottom Summary (as seen in screenshot)
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: Theme.of(context).dividerColor.withOpacity(0.1))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).dividerColor.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'ALL',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: 20),
                    ...(() {
                      final Map<String, int> counts = {};
                      message.reactions!.forEach((_, emoji) {
                        counts[emoji] = (counts[emoji] ?? 0) + 1;
                      });
                      return counts.entries.map((e) => Padding(
                        padding: const EdgeInsets.only(right: 15),
                        child: Row(
                          children: [
                            Text(
                              e.key, 
                              style: const TextStyle(
                                fontSize: 22, // Increased for summary
                                color: Colors.black,
                              )
                            ),
                            const SizedBox(width: 4),
                            Text(
                              e.value.toString(),
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: Theme.of(context).textTheme.bodySmall?.color,
                              ),
                            ),
                          ],
                        ),
                      ));
                    })(),
                  ],
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
  }

  String _getFormattedDate(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final messageDate = DateTime(date.year, date.month, date.day);

    if (messageDate == today) return 'today'.tr;
    if (messageDate == yesterday) return 'yesterday'.tr;
    return DateFormat('MMM dd, yyyy').format(date);
  }

  List<TextSpan> _parseMentionText(String text, BuildContext context, bool isMe) {
    final RegExp mentionRegExp = RegExp(r'@\w+');
    final Iterable<RegExpMatch> matches = mentionRegExp.allMatches(text);
    
    if (matches.isEmpty) {
      return [TextSpan(text: text)];
    }

    List<TextSpan> spans = [];
    int currentIndex = 0;

    for (final match in matches) {
      if (match.start > currentIndex) {
        spans.add(TextSpan(text: text.substring(currentIndex, match.start)));
      }
      
      spans.add(TextSpan(
        text: match.group(0),
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: isMe ? Colors.white : Theme.of(context).colorScheme.primary,
        ),
      ));
      
      currentIndex = match.end;
    }

    if (currentIndex < text.length) {
      spans.add(TextSpan(text: text.substring(currentIndex)));
    }

    return spans;
  }
}

/// A message that has been sent but is not in the thread yet — uploading,
/// or waiting for a connection.
///
/// Drawn as the sender's own bubble at the end of the thread so the send feels
/// immediate; it is replaced by the real message the moment delivery lands.
/// A failed one stays put with a way back — dropping a message on a flaky
/// connection would be the worst possible answer.
class _OutgoingBubble extends StatelessWidget {
  /// Everything this bubble stands for, oldest first — one message, or every
  /// picture of a batch still on its way out.
  final List<OutgoingMessage> items;
  final ChatController controller;

  const _OutgoingBubble({required this.items, required this.controller});

  /// The one the bubble is hung on: the first of a batch is what carries the
  /// caption and the reply, the same as in a delivered album.
  OutgoingMessage get item => items.first;

  bool get _isAlbum => items.length > 1;

  /// A batch is only as delivered as its worst picture.
  bool get _failed => items.any((OutgoingMessage each) => each.failed);

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool hasImage = item.hasImage;
    final bool hasAudio = item.hasAudio;
    final String? imagePath = item.imagePath;

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 50),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: hasImage
                  ? const EdgeInsets.all(4)
                  : hasAudio
                      ? const EdgeInsets.fromLTRB(8, 8, 12, 6)
                      : const EdgeInsets.fromLTRB(16, 10, 16, 8),
              decoration: BoxDecoration(
                color: primary.withOpacity(_failed ? 0.5 : 1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (item.hasReply)
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                          hasImage ? 4 : 0, hasImage ? 4 : 0, hasImage ? 4 : 0, 6),
                      child: _quote(context),
                    ),
                  if (hasAudio)
                    PendingVoiceBubble(
                      duration: item.audioDuration,
                      waveform: item.audioWave ?? const <int>[],
                      failed: _failed,
                      sending: controller.isSendingOut,
                    )
                  else if (hasImage && _isAlbum)
                    _pendingAlbum(context)
                  else if (hasImage && imagePath != null)
                    ConstrainedBox(
                      constraints:
                          const BoxConstraints(maxWidth: 240, maxHeight: 320),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        // Same shape the finished bubble will have, so nothing
                        // shifts when the upload lands and the real message
                        // takes this one's place.
                        child: AspectRatio(
                          aspectRatio: item.aspectRatio,
                          child: _pendingTile(context, item),
                        ),
                      ),
                    ),
                  if (item.text.isNotEmpty)
                    Padding(
                      padding: hasImage
                          ? const EdgeInsets.fromLTRB(8, 8, 8, 4)
                          : EdgeInsets.zero,
                      child: Text(
                        item.text,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 15, height: 1.3),
                      ),
                    ),
                  Padding(
                    padding: hasImage
                        ? const EdgeInsets.fromLTRB(8, 4, 8, 4)
                        : const EdgeInsets.only(top: 4),
                    child: _failed ? _failedRow(context) : _statusRow(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A batch of pictures on its way out, laid out exactly the way the thread
  /// will lay it out once it lands — so nothing jumps when the uploads finish
  /// and the real album takes this bubble's place.
  Widget _pendingAlbum(BuildContext context) {
    const double gap = 2;

    Widget half(int i, {int extra = 0}) => Expanded(
          child: AspectRatio(
            aspectRatio: 1,
            child: _pendingTile(context, items[i], extra: extra),
          ),
        );

    Widget pair(int a, int b, {int extra = 0}) => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            half(a),
            const SizedBox(width: gap),
            half(b, extra: extra),
          ],
        );

    late final Widget grid;
    if (items.length == 2) {
      grid = pair(0, 1);
    } else if (items.length == 3) {
      grid = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AspectRatio(
            aspectRatio: 8 / 5,
            child: _pendingTile(context, items[0]),
          ),
          const SizedBox(height: gap),
          pair(1, 2),
        ],
      );
    } else {
      grid = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          pair(0, 1),
          const SizedBox(height: gap),
          pair(2, 3, extra: items.length - 4),
        ],
      );
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: grid,
      ),
    );
  }

  /// One picture waiting to go, under the mark that says what is happening to
  /// it — uploading, waiting for a connection, or refused.
  Widget _pendingTile(BuildContext context, OutgoingMessage each,
      {int extra = 0}) {
    final String? path = each.imagePath;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (path != null) LocalImage(path, fit: BoxFit.cover),
        Container(
          color: Colors.black.withOpacity(0.35),
          alignment: Alignment.center,
          child: extra > 0
              ? Text(
                  '+$extra',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                  ),
                )
              : each.failed
                  ? const Icon(Icons.error_outline_rounded,
                      color: Colors.white, size: 26)
                  : controller.isDelivering
                      ? const SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.schedule_rounded,
                          color: Colors.white, size: 26),
        ),
      ],
    );
  }

  /// "Sending" while the outbox is working on it, "waiting for connection"
  /// while it cannot — so the sender knows which it is.
  ///
  /// It used to be `isDelivering && isOnline`, which let a reachability probe
  /// against an unrelated host overrule a send that was visibly in progress —
  /// one slow probe put "waiting for connection" under a message already on
  /// its way. See `ChatController.isSendingOut`.
  Widget _statusRow(BuildContext context) {
    final bool delivering = controller.isSendingOut;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          delivering ? Icons.cloud_upload_outlined : Icons.schedule_rounded,
          size: 11,
          color: Colors.white.withOpacity(0.85),
        ),
        const SizedBox(width: 4),
        Text(
          delivering ? 'sending'.tr : 'waiting_for_connection'.tr,
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontSize: 11,
          ),
        ),
      ],
    );
  }

  Widget _failedRow(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'send_failed'.tr,
          style: const TextStyle(color: Colors.white, fontSize: 11),
        ),
        const SizedBox(width: 10),
        // A batch is retried or dropped as a batch: the sender picked those
        // pictures as one send and does not want half of them.
        _action(context, Icons.refresh_rounded, 'retry'.tr, () {
          for (final OutgoingMessage each in items) {
            if (each.failed) controller.retryOutgoing(each);
          }
        }),
        const SizedBox(width: 6),
        _action(context, Icons.close_rounded, 'cancel'.tr, () {
          for (final OutgoingMessage each in List<OutgoingMessage>.from(items)) {
            controller.discardOutgoing(each);
          }
        }),
      ],
    );
  }

  /// The message being replied to, the way the finished bubble will quote it.
  Widget _quote(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(10),
        border: const Border(left: BorderSide(color: Colors.white, width: 3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item.replyToSenderName ?? '',
            style: const TextStyle(
                color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 2),
          Text(
            item.replyToText ?? '',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                color: Colors.white.withOpacity(0.85), fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _action(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 12, color: Colors.white),
            const SizedBox(width: 4),
            Text(label,
                style: const TextStyle(color: Colors.white, fontSize: 11)),
          ],
        ),
      ),
    );
  }
}

class _ReactionPickerWidget extends StatefulWidget {
  final Function(String) onEmojiSelected;

  /// Opens the rest of the actions — reply, copy, edit, delete.
  final VoidCallback onMoreTapped;

  const _ReactionPickerWidget({
    required this.onEmojiSelected,
    required this.onMoreTapped,
  });

  @override
  State<_ReactionPickerWidget> createState() => _ReactionPickerWidgetState();
}

class _ReactionPickerWidgetState extends State<_ReactionPickerWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final List<String> _emojis = ['❤️', '👍', '👎', '😂', '😮', '😢', '😡'];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor.withOpacity(1.0), // Ensure fully opaque
          borderRadius: BorderRadius.circular(30),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
          border: Border.all(color: Theme.of(context).dividerColor, width: 0.5),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ..._emojis.map((emoji) => _buildEmojiItem(emoji)),
            Container(
              width: 1,
              height: 22,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: Theme.of(context).dividerColor,
            ),
            GestureDetector(
              onTap: widget.onMoreTapped,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Icon(
                  Icons.more_horiz_rounded,
                  size: 22,
                  color: Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmojiItem(String emoji) {
    return GestureDetector(
      onTap: () => widget.onEmojiSelected(emoji),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: 1),
          duration: Duration(milliseconds: 300 + (_emojis.indexOf(emoji) * 50)),
          curve: Curves.easeOutBack,
          builder: (context, value, child) {
            return Transform.scale(
              scale: value,
              child: child,
            );
          },
          child: Text(
            emoji,
            style: const TextStyle(
              fontSize: 22, // Reduced for a more balanced look
              color: Colors.black, // Force full color rendering
            ),
          ),
        ),
      ),
    );
  }
}
