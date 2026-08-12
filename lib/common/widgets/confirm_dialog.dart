import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// ---------------------------------------------------------------------------
/// Dialog / sheet dismissal that survives a visible snackbar.
///
/// `Get.back()` cannot be trusted here. GetX 4 carries a compatibility shim:
///
/// ```dart
/// if (isSnackbarOpen && !closeOverlays) {
///   closeCurrentSnackbar();
///   return;            // <- the dialog below is never popped
/// }
/// ```
///
/// So whenever a toast happens to be on screen, the first `Get.back()` only
/// eats the toast and the dialog stays put — the button looks dead. Popping the
/// route through [Navigator] skips the shim entirely.
/// ---------------------------------------------------------------------------

/// Closes the top-most dialog or bottom sheet opened through GetX.
///
/// Safe to call from a controller, where no widget context is at hand. Does
/// nothing when no overlay route is open, so it can never pop the page itself.
void closeOverlayRoute() {
  final BuildContext? context = Get.context;
  if (context == null) return;

  final bool hasOverlay =
      (Get.isDialogOpen ?? false) || (Get.isBottomSheetOpen ?? false);
  if (!hasOverlay) return;

  final NavigatorState navigator = Navigator.of(context);
  if (navigator.canPop()) navigator.pop();
}

/// A confirm dialog whose buttons keep working while a snackbar is showing.
///
/// [onConfirm] runs after the dialog is closed. Any lingering toast is cleared
/// first so the action's own feedback is not queued behind a stale one.
Future<void> showConfirmDialog({
  required String title,
  required String message,
  required String confirmText,
  required VoidCallback onConfirm,
  String? detail,
  Color confirmColor = Colors.red,
}) {
  return Get.dialog(
    Builder(
      builder: (dialogContext) {
        final Color muted =
            (Theme.of(dialogContext).textTheme.bodySmall?.color ?? Colors.grey)
                .withOpacity(0.65);
        final bool hasDetail = detail != null && detail.trim().isNotEmpty;

        return AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(message),
              if (hasDetail) ...[
                const SizedBox(height: 12),
                Text(
                  detail,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.4,
                    color: muted,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('cancel'.tr),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Get.closeAllSnackbars();
                onConfirm();
              },
              child: Text(confirmText),
            ),
          ],
        );
      },
    ),
  );
}
