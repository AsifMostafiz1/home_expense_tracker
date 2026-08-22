import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_constant.dart';

/// Who is around right now.
///
/// One field — `last_active` on the member's own `users` document — stamped
/// while the app is in front and left alone the moment it goes to the
/// background. The chat list reads it back through the member stream it is
/// already listening to, so presence costs no extra read anywhere.
///
/// Deliberately coarse: a heartbeat every couple of minutes, counted as
/// "online" for twice that. A finer signal would mean a write per screen
/// change for every member of the house, and nobody is watching the dot that
/// closely.
class PresenceService extends GetxController
    with WidgetsBindingObserver
    implements GetxService {
  static const Duration beat = Duration(minutes: 2);

  Timer? _timer;
  String _phone = '';
  bool _inForeground = true;
  bool _observing = false;

  /// Safe to call more than once: signing in re-runs the initial binding on
  /// an instance that is already registered, so this lands twice on a fresh
  /// account.
  Future<void> init() async {
    if (!_observing) {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    }
    await _resolvePhone();

    _timer?.cancel();
    _timer = Timer.periodic(beat, (_) {
      if (_inForeground) _touch();
    });
    _touch();
  }

  Future<void> _resolvePhone() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    _phone = prefs.getString(AppConstant.keyUserPhone) ?? '';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _inForeground = state == AppLifecycleState.resumed;
    // Coming back counts as activity; leaving deliberately does not stamp
    // anything, so the last beat simply ages out of the window.
    if (_inForeground) _touch();
  }

  /// Best effort and never awaited by anything: a heartbeat that does not
  /// land is a dot that goes grey, which is the honest answer anyway.
  ///
  /// Re-reads the phone number when it does not have one — the service starts
  /// before anybody has signed in, and the beat should pick the account up
  /// without waiting for a relaunch.
  Future<void> _touch() async {
    if (_phone.isEmpty) await _resolvePhone();
    if (_phone.isEmpty) return;

    try {
      await FirebaseFirestore.instance
          .collection(AppConstant.collectionUsers)
          .doc(_phone)
          .set({'last_active': FieldValue.serverTimestamp()},
              SetOptions(merge: true));
    } catch (e) {
      debugPrint('Presence: not stamped — $e');
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.onClose();
  }
}
