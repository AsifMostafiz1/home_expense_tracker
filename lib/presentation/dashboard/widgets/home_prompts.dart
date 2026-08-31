import 'package:get/get.dart';

import '../../../utils/user_session.dart';
import '../../house_rules/widgets/house_rules_gate.dart';
import '../../meal/widgets/bulk_meal_prompt_sheet.dart';
import '../../profile/widgets/profile_photo_prompt_sheet.dart';

/// The asks the home screen makes on the way in, run as a queue.
///
/// Only one thing may stand in front of the user at a time, so these are
/// ordered rather than fired together:
///
///   1. the month's meals — until that month exists nothing on the meal
///      screen works, so it comes first;
///   2. the house rules — mandatory, and the only one of the three that is
///      not the user's to postpone;
///   3. the profile picture — a nicety, and the first thing to give way.
///
/// A refused meal prompt ends the queue for the picture, and so does a rules
/// screen that had to be shown: somebody who has just worked through one
/// thing is not in the mood for a second. Both are still pending, so the next
/// launch offers them again.
class HomePrompts {
  const HomePrompts._();

  static bool _running = false;

  /// [isHomeOnTop] tells this whether the home screen is still what the user
  /// is looking at. A tapped notification opens a thread, a bill or the rules
  /// over it while this queue is still waiting its turn, and the two asks
  /// that are the user's to postpone have no business landing on top of
  /// somebody's message. The rules are not one of them — see below.
  static Future<void> run({bool Function()? isHomeOnTop}) async {
    if (_running) return;
    _running = true;

    try {
      await _waitForOverlays();
      if (Get.context == null) return;
      if (_overlayBusy) return;

      final bool onHome = isHomeOnTop?.call() ?? true;

      // A general user has no meals to set up and no house rules to agree
      // to — both asks belong to the house life their account is not part
      // of. Only the photo nicety survives for them.
      final bool general = UserSession.isGeneral;

      final BulkMealPromptResult meals = onHome && !general
          ? await BulkMealPrompt.maybeShow()
          : BulkMealPromptResult.notNeeded;

      // Let a sheet finish sliding out before the next thing arrives.
      if (meals != BulkMealPromptResult.notNeeded) {
        await Future.delayed(const Duration(milliseconds: 700));
      }

      // Runs whatever the meal sheet was answered with, and wherever the
      // reader has ended up: agreeing to the rules is not something a member
      // gets to put off by waving a sheet away — or by having tapped a
      // notification on the way in.
      if (!general) {
        final HouseRulesGateResult rules = await HouseRulesGate.maybeShow();
        if (rules == HouseRulesGateResult.shown) return;
      }

      if (!onHome) return;
      if (meals == BulkMealPromptResult.dismissed) return;

      await ProfilePhotoPrompt.maybeShow();
    } finally {
      _running = false;
    }
  }

  /// The rules check on its own — for coming back to an app that was left
  /// open, where the queue above has already run for this launch but an admin
  /// may have published something in the meantime.
  static Future<void> runRulesGate() async {
    if (_running) return;
    _running = true;

    try {
      if (Get.context == null) return;
      if (_overlayBusy) return;
      if (UserSession.isGeneral) return;
      await HouseRulesGate.maybeShow();
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
