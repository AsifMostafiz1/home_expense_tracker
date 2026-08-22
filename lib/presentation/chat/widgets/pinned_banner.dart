import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import '../controller/chat_controller.dart';
import '../model/pinned_message_model.dart';

/// The strip under the group chat's app bar.
///
/// One pin at a time, whichever the house has dragged to the top of the list,
/// with a count of the rest beside it. Tapping opens the full list — there is
/// only room for one line here, and cycling through them a tap at a time would
/// hide the reordering that decides what shows.
class PinnedBanner extends StatelessWidget {
  final VoidCallback onTap;

  const PinnedBanner({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ChatController>(
      builder: (c) {
        final PinnedMessage? pin = c.topPin;
        if (pin == null) return const SizedBox.shrink();

        final Color primary = Theme.of(context).colorScheme.primary;

        return Material(
          color: Theme.of(context).cardColor,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 10, 8),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: AppUi.hairline(context)),
                ),
              ),
              child: Row(
                children: [
                  // The accent bar a quoted message uses, for the same reason:
                  // this line is not the thread, it is something held above it.
                  Container(
                    width: 3,
                    height: 34,
                    decoration: BoxDecoration(
                      color: primary,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Icon(Icons.push_pin_rounded, size: 15, color: primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'pinned_message'.tr,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: primary,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          // Who said it, then what — the way the chat list
                          // previews a conversation.
                          pin.senderName.isEmpty
                              ? pin.preview
                              : '${pin.senderName.split(' ').first}: ${pin.preview}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.2,
                            color: AppUi.body(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (pin.hasImage) ...[
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.network(
                        pin.imageUrl!,
                        width: 30,
                        height: 30,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  // Only worth a badge once there is more than one — a "1"
                  // next to the only pin says nothing.
                  if (c.pinnedCount > 1)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: primary.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${c.pinnedCount}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: primary,
                        ),
                      ),
                    ),
                  Icon(Icons.chevron_right_rounded,
                      size: 18, color: AppUi.muted(context)),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
