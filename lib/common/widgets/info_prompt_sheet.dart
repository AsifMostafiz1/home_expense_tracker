import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../utils/app_ui.dart';
import 'custom_button.dart';

/// One line inside an [InfoPromptSheet] — an icon and the thing it explains.
class InfoPromptPoint {
  final IconData icon;
  final String text;

  const InfoPromptPoint(this.icon, this.text);
}

/// The shell the home screen's launch-time asks are built from: a badge, what
/// the ask is about, a few lines of why, and the accept / not-now pair.
///
/// Shared so that "set up this month's meals" and "add a profile picture" read
/// as the same kind of interruption rather than two separate designs.
class InfoPromptSheet extends StatelessWidget {
  /// The circle at the top. Passed in whole — one sheet shows the member's
  /// initials, another an icon.
  final Widget badge;

  final String title;
  final String message;
  final List<InfoPromptPoint> points;

  final String actionLabel;
  final VoidCallback onAction;

  /// Spins the action button while the work behind it runs — the meal sheet
  /// does its writing before it closes.
  final bool isLoading;

  final String dismissLabel;
  final VoidCallback onDismiss;

  const InfoPromptSheet({
    super.key,
    required this.badge,
    required this.title,
    required this.message,
    required this.points,
    required this.actionLabel,
    required this.onAction,
    this.isLoading = false,
    required this.dismissLabel,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back button and barrier taps are held off while the action runs, so
      // the sheet cannot be closed out from under its own write.
      canPop: !isLoading,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppUi.hairline(context),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            badge,
            const SizedBox(height: 20),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: AppUi.muted(context),
              ),
            ),
            if (points.isNotEmpty) ...[
              const SizedBox(height: 20),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                decoration: BoxDecoration(
                  color: AppUi.neutralSurface(context),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppUi.hairline(context)),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < points.length; i++) ...[
                      if (i > 0) const SizedBox(height: 12),
                      _point(context, points[i]),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 24),
            CustomButton(
              text: actionLabel,
              isLoading: isLoading,
              onPressed: onAction,
            ),
            const SizedBox(height: 4),
            TextButton(
              // Left tappable while the action runs would let someone close
              // the sheet out from under a batch write.
              onPressed: isLoading ? null : onDismiss,
              child: Text(
                dismissLabel,
                style: TextStyle(color: AppUi.muted(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _point(BuildContext context, InfoPromptPoint point) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppUi.tint(context, primary),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(point.icon, size: 16, color: primary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            point.text,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: AppUi.body(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// Opens [sheet] the way every prompt in this family is opened, and answers
/// with whatever the sheet closed itself with.
Future<T?> showInfoPromptSheet<T>(Widget sheet) => Get.bottomSheet<T>(
      sheet,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
    );
