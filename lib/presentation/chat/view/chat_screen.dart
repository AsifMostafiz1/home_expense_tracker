import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import '../../../common/widgets/avatar_picker.dart';
import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../common/widgets/image_viewer_screen.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../controller/chat_controller.dart';
import '../controller/chat_list_controller.dart';
import '../model/chat_message_model.dart';
import '../model/chat_thread_model.dart';
import '../model/outgoing_image_model.dart';
import '../widgets/chat_presence.dart';
import '../widgets/group_avatar.dart';
import '../widgets/group_settings_sheet.dart';
import '../widgets/pinned_banner.dart';
import 'pinned_messages_screen.dart';

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

class _ChatScreenState extends State<ChatScreen> {
  ChatController get controller => Get.find<ChatController>(tag: widget.tag);

  bool get _isDirect => widget.tag != null;

  @override
  void initState() {
    super.initState();
    // Being on screen is what marks a thread read — for the group that is the
    // in-memory badge, for a direct chat the count in Firestore.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) controller.setChatScreenVisible(true);
    });
  }

  @override
  void dispose() {
    // Safe from here: with `false` this only flips a flag, it does not ask
    // anything to rebuild.
    controller.setChatScreenVisible(false);

    // A direct chat's controller belongs to its screen — it holds two live
    // Firestore listeners, and one per conversation ever opened would pile
    // up. `force` because a GetxService is otherwise never taken down.
    // Safe here: Flutter unmounts a subtree's children before the parent's
    // `dispose`, so every builder listening to this controller is already
    // gone.
    final String? tag = widget.tag;
    if (tag != null) Get.delete<ChatController>(tag: tag, force: true);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _buildAppBar(context),
      body: Column(
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
                // bottom of a reversed list.
                final int pending = controller.outgoing.length;

                if (controller.messages.isEmpty && pending == 0) {
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

                return ListView.builder(
                  controller: controller.scrollController,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  itemCount: controller.messages.length + pending,
                  itemBuilder: (context, position) {
                    if (position < pending) {
                      // Newest first, like everything else in a reversed list.
                      return _OutgoingBubble(
                        item: controller.outgoing[pending - 1 - position],
                        controller: controller,
                      );
                    }

                    final int index = position - pending;
                    final message = controller.messages[index];
                    final isMe = message.senderPhone == controller.userPhone;

                    bool isFirstInGroup = true;
                    bool isLastInGroup = true;
                    bool showDateHeader = false;

                    if (index < controller.messages.length - 1) {
                      final nextMessage = controller.messages[index + 1];
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
                      final nextMessage = controller.messages[index - 1];
                      if (nextMessage.senderPhone == message.senderPhone) {
                        isLastInGroup = false;
                      }
                    }

                    return _MessageBubble(
                      key: controller.getKeyForMessage(message.id),
                      message: message,
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
      ),
    );
  }

  /// The header. A group says how many people are in it; a direct chat says
  /// whether the other person is around, which is the thing a sender actually
  /// wants to know before they type.
  PreferredSizeWidget _buildAppBar(BuildContext context) {
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
      actions: _isDirect ? null : [_buildGroupMenu(context)],
    );
  }

  /// The group's own settings — what it is called, and what it looks like.
  /// Nothing here belongs to a direct chat, which is named after the person
  /// it is with.
  Widget _buildGroupMenu(BuildContext context) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: AppUi.body(context)),
      tooltip: 'options'.tr,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        if (value == 'settings') showGroupSettingsSheet(context);
        if (value == 'pinned') _openPinned();
      },
      itemBuilder: (_) => [
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
      ],
    );
  }

  void _openPinned() => Get.to(() => const PinnedMessagesScreen());

  /// "Active now", "Active 20m ago" — or, for the group, how many members it
  /// has.
  Widget _buildSubtitle(
    BuildContext context,
    ChatController c,
    ChatListController list,
  ) {
    final ChatUser? peer = list.userByPhone(c.thread.peerPhone);
    final bool online = _isDirect && (peer?.isOnline ?? false);

    final String label = _isDirect
        ? presenceLabel(peer)
        : (list.memberCount > 0
            ? 'member_count'.trParams({'count': '${list.memberCount}'})
            : 'house_group_subtitle'.tr);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (online) ...[
          Container(
            width: 7,
            height: 7,
            decoration: const BoxDecoration(
              color: Color(0xFF22C55E),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: online ? FontWeight.w600 : FontWeight.w400,
              color: online ? const Color(0xFF16A34A) : AppUi.muted(context),
            ),
          ),
        ),
      ],
    );
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
              child: Row(
                children: [
                  Expanded(
                    child: Container(
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
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: controller.sendMessage,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      // A tick rather than a paper plane while editing —
                      // nothing is being sent, something is being corrected.
                      child: GetBuilder<ChatController>(
                        tag: widget.tag,
                        builder: (controller) => Icon(
                          controller.editingMessage != null
                              ? Icons.check_rounded
                              : Icons.send_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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
                      child: Image.file(
                        attachments[index].file,
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

class _MessageBubble extends StatelessWidget {
  final ChatMessageModel message;
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
  });

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
                                onTap: () => controller.toggleTimeDisplay(message.id),
                                child: Container(
                                  // A picture sits tight against the bubble
                                  // edge; only text needs the roomy padding.
                                  padding: message.hasImage
                                      ? EdgeInsets.only(
                                          left: 4,
                                          right: 4,
                                          top: 4,
                                          bottom: (message.reactions != null && message.reactions!.isNotEmpty) ? 16 : 4,
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
                                      if (message.hasImage) _buildImage(context),
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

  /// The picture inside a bubble.
  ///
  /// Laid out from the dimensions stamped on the message, so the thread keeps
  /// its shape while the bytes are still coming down — the bubble never jumps
  /// under a reader's thumb. A tap opens it full screen.
  Widget _buildImage(BuildContext context) {
    return GestureDetector(
      onTap: () => Get.to(() => ImageViewerScreen(
            imageUrl: message.imageUrl!,
            title: message.senderName,
            subtitle: DateFormat('dd MMM, hh:mm a').format(message.createdAt),
            caption: message.text,
            heroTag: _imageHeroTag,
          )),
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

  Widget _buildSeenAvatars(BuildContext context) {
    final seenBy = controller.messageSeenBy[message.id] ?? [];
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
  final OutgoingMessage item;
  final ChatController controller;

  const _OutgoingBubble({required this.item, required this.controller});

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool hasImage = item.hasImage;
    final File? file = item.file;

    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8, left: 50),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Flexible(
            child: Container(
              padding: hasImage
                  ? const EdgeInsets.all(4)
                  : const EdgeInsets.fromLTRB(16, 10, 16, 8),
              decoration: BoxDecoration(
                color: primary.withOpacity(item.failed ? 0.5 : 1),
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
                  if (hasImage && file != null)
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
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.file(file, fit: BoxFit.cover),
                              Container(
                                color: Colors.black.withOpacity(0.35),
                                alignment: Alignment.center,
                                child: item.failed
                                    ? const Icon(Icons.error_outline_rounded,
                                        color: Colors.white, size: 30)
                                    : controller.isDelivering
                                        ? const SizedBox(
                                            width: 30,
                                            height: 30,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.5,
                                              color: Colors.white,
                                            ),
                                          )
                                        : const Icon(Icons.schedule_rounded,
                                            color: Colors.white, size: 30),
                              ),
                            ],
                          ),
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
                    child: item.failed ? _failedRow(context) : _statusRow(context),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
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
        _action(context, Icons.refresh_rounded, 'retry'.tr,
            () => controller.retryOutgoing(item)),
        const SizedBox(width: 6),
        _action(context, Icons.close_rounded, 'cancel'.tr,
            () => controller.discardOutgoing(item)),
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
