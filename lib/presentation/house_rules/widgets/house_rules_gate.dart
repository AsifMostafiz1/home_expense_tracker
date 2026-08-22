import 'package:flutter/foundation.dart';
import 'package:get/get.dart';

import '../controller/house_rules_controller.dart';
import '../view/rules_acknowledge_screen.dart';

/// What the gate did, so the home screen's queue knows whether anything
/// stood in front of the user.
enum HouseRulesGateResult {
  /// Every rule was already agreed to, or there are none to agree to.
  notNeeded,

  /// The acknowledgement screen was shown and answered.
  shown,
}

/// The check that puts unagreed house rules in front of a member on the way
/// into the app.
///
/// A rule counts as outstanding when it has never been acknowledged, or when
/// its wording changed after it was — see `HouseRulesController.needsAck`. So
/// a member agrees once and is left alone until an admin adds or rewrites
/// something, which is exactly when the house needs them to look again.
class HouseRulesGate {
  const HouseRulesGate._();

  static bool _showing = false;

  /// Whether the acknowledgement screen is in front of the user right now.
  ///
  /// It is mandatory and it is an ordinary route, so anything that pops its
  /// way back to the home screen — a tapped notification — has to wait for it
  /// rather than dismissing it.
  static bool get isShowing => _showing;

  static Future<HouseRulesGateResult> maybeShow() async {
    if (_showing) return HouseRulesGateResult.notNeeded;

    final HouseRulesController? controller = _controller();
    if (controller == null) return HouseRulesGateResult.notNeeded;

    // Both are already in flight from the controller's own start-up; this
    // waits on them rather than firing a second read. Firestore answers from
    // its local copy when there is no connection, so an offline launch still
    // gets an answer — the timeout is for the case where it somehow does not,
    // since this queue holds up every other prompt behind it.
    await _bounded(controller.rulesReady);
    await _bounded(controller.acksReady);

    if (!controller.hasPendingRules) return HouseRulesGateResult.notNeeded;
    if (Get.context == null) return HouseRulesGateResult.notNeeded;

    _showing = true;
    try {
      controller.beginAcknowledgement();
      await Get.to<void>(
        () => const RulesAcknowledgeScreen(),
        fullscreenDialog: true,
      );
      return HouseRulesGateResult.shown;
    } finally {
      _showing = false;
    }
  }

  static const Duration _wait = Duration(seconds: 8);

  static Future<void> _bounded(Future<void> work) =>
      work.timeout(_wait, onTimeout: () {});

  /// The controller is registered lazily, so the first caller builds it —
  /// which also starts the live rules listener for the session.
  static HouseRulesController? _controller() {
    try {
      return Get.find<HouseRulesController>();
    } catch (e) {
      debugPrint('House rules: controller unavailable — $e');
      return null;
    }
  }
}
