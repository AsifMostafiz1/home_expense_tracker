import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/app_constant.dart';

/// Asks for the notification permission at a moment the OS will actually
/// honour it.
///
/// The system dialog is raised by the host Activity, so it can only appear once
/// that Activity is created *and* resumed. Requesting from `main()` — before
/// `runApp()` — resolves to `denied` without any popup ever being drawn, which
/// reads to the user as "the app blocked notifications by itself". Everything
/// here is therefore driven from the widget tree, after the first frame.
class NotificationPermissionService {
  static final NotificationPermissionService _instance =
      NotificationPermissionService._internal();
  factory NotificationPermissionService() => _instance;
  NotificationPermissionService._internal();

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;

  /// Guards against two prompts racing — e.g. a resume landing while the
  /// launch-time request is still on screen.
  bool _inFlight = false;

  /// Set when we hand the user off to system settings, so the trip back can
  /// re-check without nagging every unrelated app switch.
  bool _awaitingSettingsReturn = false;

  bool get awaitingSettingsReturn => _awaitingSettingsReturn;

  Future<bool> isGranted() async {
    if (Platform.isAndroid) {
      return Permission.notification.isGranted;
    }
    final NotificationSettings settings = await _fcm.getNotificationSettings();
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Requests the permission if it is not granted yet.
  ///
  /// Runs on every app open: a user who declined once can grant on a later
  /// launch without hunting through settings. When the OS has stopped showing
  /// its own dialog, [showSettingsFallback] decides whether we explain the
  /// situation in-app and offer a route to settings.
  Future<bool> ensurePermission({bool showSettingsFallback = true}) async {
    if (_inFlight) return false;
    _inFlight = true;

    try {
      if (await isGranted()) return true;

      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final bool askedBefore =
          prefs.getBool(AppConstant.keyNotificationPermissionAsked) ?? false;

      final bool granted = await _request();
      await prefs.setBool(AppConstant.keyNotificationPermissionAsked, true);
      if (granted) return true;

      // `request()` returns instantly, with no popup, once Android/iOS have
      // retired the dialog for this app. Settings is then the only way in —
      // but only offer it to someone who has already seen and dismissed the
      // system prompt at least once.
      final bool dialogRetired =
          Platform.isAndroid && await Permission.notification.isPermanentlyDenied;

      if (showSettingsFallback && (dialogRetired || askedBefore)) {
        await _showSettingsDialog();
      }
      return false;
    } finally {
      _inFlight = false;
    }
  }

  /// Re-reads the status after the user comes back from system settings.
  Future<bool> refreshAfterSettingsReturn() async {
    _awaitingSettingsReturn = false;
    return isGranted();
  }

  Future<bool> _request() async {
    if (Platform.isAndroid) {
      // Android 12 and below grant this at install time; `request()` is a
      // no-op there and simply reports the install-time grant back.
      final PermissionStatus status = await Permission.notification.request();
      return status.isGranted;
    }

    final NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  Future<void> _showSettingsDialog() async {
    if (Get.isDialogOpen ?? false) return;
    if (Get.context == null) return;

    await Get.dialog(
      Builder(
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text('notifications_off_title'.tr),
          content: Text('notifications_off_message'.tr),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text('not_now'.tr),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _awaitingSettingsReturn = true;
                openAppSettings();
              },
              child: Text('open_settings'.tr),
            ),
          ],
        ),
      ),
      barrierDismissible: false,
    );
  }
}
