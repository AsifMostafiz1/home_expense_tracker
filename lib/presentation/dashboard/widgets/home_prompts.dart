import 'package:get/get.dart';

import '../../meal/widgets/bulk_meal_prompt_sheet.dart';
import '../../profile/widgets/profile_photo_prompt_sheet.dart';

/// The asks the home screen makes on the way in, run as a queue.
///
/// Only one thing may stand in front of the user at a time, so these are
/// ordered rather than fired together. The month's meals come first: until
/// that month exists nothing else on the meal screen works, whereas a missing
/// profile picture costs nobody anything today.
///
/// A refused meal prompt ends the queue for this launch — someone who has just
/// waved one sheet away is not in the mood for a second. The picture is still
/// pending, so the next launch offers it again.
class HomePrompts {
  const HomePrompts._();

  static bool _running = false;

  static Future<void> run() async {
    if (_running) return;
    _running = true;

    try {
      await _waitForOverlays();
      if (Get.context == null) return;
      if (_overlayBusy) return;

      final BulkMealPromptResult meals = await BulkMealPrompt.maybeShow();
      if (meals == BulkMealPromptResult.dismissed) return;

      // Let the first sheet finish sliding out before the next one arrives.
      if (meals == BulkMealPromptResult.added) {
        await Future.delayed(const Duration(milliseconds: 700));
      }

      await ProfilePhotoPrompt.maybeShow();
    } finally {
      _running = false;
    }
  }

  static bool get _overlayBusy =>
      (Get.isDialogOpen ?? false) || (Get.isBottomSheetOpen ?? false);

  /// The splash raises the notification permission dialog shortly after the
  /// home screen appears. Landing a sheet on top of it reads as a glitch, so
  /// wait for a clear frame — bounded, since a sheet the user opened
  /// themselves would otherwise hold this open forever.
  static Future<void> _waitForOverlays() async {
    await Future.delayed(const Duration(milliseconds: 1500));

    for (int i = 0; i < 10; i++) {
      if (!_overlayBusy) return;
      await Future.delayed(const Duration(milliseconds: 500));
    }
  }
}
