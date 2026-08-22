import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../controller/chat_controller.dart';
import '../model/pinned_message_model.dart';

/// Everything the house has pinned, in the order it arranged them.
///
/// The order is the point of the screen: whichever pin sits at the top is the
/// one the banner under the chat's app bar shows, so dragging one up there is
/// how the house decides what everybody sees first. Anybody can drag —
/// pinning is not an admin's job here, and neither is arranging.
class PinnedMessagesScreen extends StatelessWidget {
  const PinnedMessagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ChatController>(
      builder: (c) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: CustomAppBar(title: 'pinned_messages'.tr),
          body: c.pinnedMessages.isEmpty
              ? _buildEmpty(context)
              : _buildList(context, c),
        );
      },
    );
  }

  Widget _buildList(BuildContext context, ChatController c) {
    return ReorderableListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      // The whole card is not the grip: a long press anywhere on a pin would
      // fight the row's own tap, which jumps to the message.
      buildDefaultDragHandles: false,
      header: Padding(
        padding: const EdgeInsets.only(top: 12, bottom: 16),
        child: _buildHeader(context, c),
      ),
      itemCount: c.pinnedMessages.length,
      onReorder: c.reorderPins,
      proxyDecorator: (child, index, animation) => Material(
        color: Colors.transparent,
        elevation: 6,
        borderRadius: BorderRadius.circular(18),
        shadowColor: Colors.black.withOpacity(0.3),
        child: child,
      ),
      itemBuilder: (context, index) {
        final PinnedMessage pin = c.pinnedMessages[index];
        return Padding(
          key: ValueKey<String>(pin.messageId),
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildPinCard(context, c, pin, index),
        );
      },
    );
  }

  /// What this list is, and which of them the thread is showing.
  Widget _buildHeader(BuildContext context, ChatController c) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppUi.tint(context, primary),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.push_pin_rounded, size: 20, color: primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'pinned_count'.trParams({'count': '${c.pinnedCount}'}),
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'pinned_reorder_hint'.tr,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.3,
                    color: AppUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPinCard(
    BuildContext context,
    ChatController c,
    PinnedMessage pin,
    int index,
  ) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool isTop = index == 0;

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _jumpTo(context, c, pin),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 6, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            // The top one is what the banner shows, so it says so.
            border: Border.all(
              color: isTop ? primary.withOpacity(0.45) : AppUi.hairline(context),
              width: isTop ? 1.4 : 1,
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ProfileAvatar(
                name: pin.senderName,
                phone: pin.senderPhone,
                imageUrl: pin.senderImage,
                size: 38,
                background: primary.withOpacity(0.14),
                foreground: primary,
                fontSize: 14,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            pin.senderName.isEmpty
                                ? 'unknown'.tr
                                : pin.senderName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: AppUi.body(context),
                            ),
                          ),
                        ),
                        if (isTop) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: primary.withOpacity(0.14),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'shown_on_top'.tr,
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.3,
                                color: primary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            pin.preview,
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: AppUi.body(context).withOpacity(0.85),
                            ),
                          ),
                        ),
                        if (pin.hasImage) ...[
                          const SizedBox(width: 10),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: Image.network(
                              pin.imageUrl!,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) =>
                                  const SizedBox.shrink(),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _footnote(pin),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11, color: AppUi.muted(context)),
                    ),
                  ],
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'unpin_message'.tr,
                    icon: Icon(Icons.push_pin_outlined,
                        size: 19, color: AppUi.muted(context)),
                    onPressed: () => c.unpin(pin.messageId),
                  ),
                  ReorderableDragStartListener(
                    index: index,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
                      child: Icon(Icons.drag_handle_rounded,
                          size: 19, color: AppUi.muted(context)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// When it was sent, and who pinned it.
  String _footnote(PinnedMessage pin) {
    final String when = pin.sentAt == null
        ? ''
        : DateFormat('dd MMM, hh:mm a').format(pin.sentAt!);
    final String by = pin.pinnedByName.trim();
    if (by.isEmpty) return when;
    final String pinned = 'pinned_by'.trParams({'name': by});
    return when.isEmpty ? pinned : '$when · $pinned';
  }

  /// Back to the thread, and onto the message itself.
  ///
  /// Only the most recent hundred messages are loaded, and a pin outlives
  /// that — so a pin from months ago has nothing to scroll to, and says so
  /// rather than swallowing the tap.
  void _jumpTo(BuildContext context, ChatController c, PinnedMessage pin) {
    Get.back();
    if (!c.scrollToMessage(pin.messageId)) {
      CustomSnackbar.show(
          type: SnackbarType.info, message: 'message_not_loaded'.tr);
    }
  }

  Widget _buildEmpty(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.push_pin_outlined,
                size: 56, color: AppUi.muted(context).withOpacity(0.5)),
            const SizedBox(height: 16),
            Text(
              'no_pinned_messages'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w600,
                color: AppUi.body(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'no_pinned_messages_hint'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12.5, height: 1.4, color: AppUi.muted(context)),
            ),
          ],
        ),
      ),
    );
  }
}
