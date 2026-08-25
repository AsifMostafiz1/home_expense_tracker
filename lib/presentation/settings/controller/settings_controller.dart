import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/daily_reminder_service.dart';
import '../../../services/push_notification_service.dart';
import '../../../services/push_outbox_service.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_enums.dart';
import '../model/app_config_model.dart';
import '../repository/settings_repository.dart';

/// App-wide settings, in two halves that share one Firestore document and
/// nothing else: the version every launch is checked against, and the daily
/// meal reminder the house gets in the evening.
///
/// They save separately — see [save] and [saveReminder] — because the stakes
/// are not comparable. Publishing a version above the build in people's hands
/// locks them out of the app until they install the new one; moving the
/// reminder half an hour does not.
class SettingsController extends GetxController implements GetxService {
  final SettingsRepository repository;

  SettingsController({required this.repository});

  bool isLoading = true;
  bool isSaving = false;
  String errorMessage = '';

  bool isAdminUser = false;
  String userName = '';
  String userPhone = '';

  AppConfigModel? config;

  final TextEditingController versionController = TextEditingController();
  final TextEditingController linkController = TextEditingController();

  String? versionError;
  String? linkError;

  /// ------------------------------------------------------- daily reminder

  bool isSavingReminder = false;

  bool reminderEnabled = false;

  /// `HH:mm`, 24-hour. Local to whichever device raises it — see
  /// [DailyReminderService].
  String reminderTime = AppConfigModel.defaultReminderTime;

  /// What the document held when it was last read. Kept so the save bar can
  /// tell an admin who has changed something from one who is only looking.
  bool _savedReminderEnabled = false;
  String _savedReminderTime = AppConfigModel.defaultReminderTime;

  bool get reminderDirty =>
      reminderEnabled != _savedReminderEnabled ||
      reminderTime != _savedReminderTime;

  bool isSendingTest = false;

  /// How long until the next reminder is due, worded for a sentence.
  ///
  /// Read off the hour as it is set right now, which is what an admin who has
  /// just moved it wants to know: a time already past today means the first
  /// one lands tomorrow, and saying so out loud is the difference between a
  /// working reminder and one that looks broken all evening.
  String get untilNextReminder {
    final Duration left = DailyReminderService.nextOccurrence(
      reminderHour,
      reminderMinute,
    ).difference(DateTime.now());

    if (left.inMinutes < 60) {
      return 'in_minutes'.trParams({'count': '${left.inMinutes + 1}'});
    }
    return 'in_hours'.trParams({'count': '${left.inHours}'});
  }

  int get reminderHour => AppConfigModel.hourOf(reminderTime);

  int get reminderMinute => AppConfigModel.minuteOf(reminderTime);

  /// The version this build reports — what the splash screen compares against.
  double get installedVersion => AppConstant.appVersion;

  double get enteredVersion => double.tryParse(versionController.text.trim()) ?? 0;

  /// True when saving would send this very device to the update screen.
  bool get locksOutThisBuild => enteredVersion > installedVersion;

  /// True when the version already published is ahead of this build.
  bool get updateRequired => (config?.versionValue ?? 0) > installedVersion;

  @override
  void onInit() {
    super.onInit();
    _loadSession().then((_) => load());
  }

  @override
  void onClose() {
    versionController.dispose();
    linkController.dispose();
    super.onClose();
  }

  Future<void> _loadSession() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    userName = prefs.getString(AppConstant.keyUserName) ?? '';
    userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    isAdminUser = prefs.getString(AppConstant.keyIsAdmin) == '1';
    update();
  }

  /// [background] is the pull-to-refresh path — the form stays put and the
  /// values are swapped once the read lands.
  Future<void> load({bool background = false}) async {
    try {
      if (!background) {
        isLoading = true;
        errorMessage = '';
        update();
      }

      final AppConfigModel loaded = await repository.fetchAppConfig();
      config = loaded;

      versionController.text = loaded.appVersion;
      linkController.text = loaded.downloadLink;
      versionError = null;
      linkError = null;
      errorMessage = '';

      reminderEnabled = loaded.reminderEnabled;
      reminderTime = loaded.reminderTime;
      _savedReminderEnabled = loaded.reminderEnabled;
      _savedReminderTime = loaded.reminderTime;
    } catch (e) {
      debugPrint('Error loading app config: $e');
      if (background && config != null) {
        CustomSnackbar.show(
            type: SnackbarType.error, message: 'failed_load_config'.tr);
      } else {
        errorMessage = e.toString();
      }
    } finally {
      isLoading = false;
      update();
    }
  }

  Future<void> refreshConfig() => load(background: true);

  void onFieldChanged([String? _]) {
    if (versionError != null || linkError != null) {
      versionError = null;
      linkError = null;
    }
    update();
  }

  /// Opens the link as a member would, so a wrong address is caught here
  /// rather than by someone locked out of the app.
  Future<void> openDownloadLink() async {
    final Uri? uri = _validLink(linkController.text.trim());
    if (uri == null) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'invalid_link'.tr);
      return;
    }

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Error opening download link: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'could_not_open_link'.tr);
    }
  }

  Uri? _validLink(String value) {
    final Uri? uri = Uri.tryParse(value);
    if (uri == null || !uri.isAbsolute) return null;
    if (uri.scheme != 'http' && uri.scheme != 'https') return null;
    if (uri.host.isEmpty) return null;
    return uri;
  }

  /// Checks the form without writing, so the screen can warn before it asks
  /// for confirmation.
  bool validate() {
    versionError = null;
    linkError = null;

    final double version = enteredVersion;
    if (versionController.text.trim().isEmpty || version <= 0) {
      versionError = 'invalid_version'.tr;
    }

    if (_validLink(linkController.text.trim()) == null) {
      linkError = 'invalid_link'.tr;
    }

    update();
    return versionError == null && linkError == null;
  }

  Future<bool> save() async {
    if (!isAdminUser) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'admin_only_action'.tr);
      return false;
    }

    if (!validate()) return false;

    try {
      isSaving = true;
      update();

      // Stored as text on purpose — see AppConfigModel.
      final AppConfigModel next = AppConfigModel(
        appVersion: versionController.text.trim(),
        downloadLink: linkController.text.trim(),
        updatedBy: userName,
      );

      // Read before the save overwrites it: whether this publishes something
      // new to download is the difference between the two.
      final double previous = config?.versionValue ?? 0;

      await repository.saveAppConfig(next.toMap(), by: userName);
      await load(background: true);

      CustomSnackbar.show(
          type: SnackbarType.success, message: 'config_saved'.tr);

      if (next.versionValue > previous) {
        await _notifyMembersBehind(next);
      }
      return true;
    } catch (e) {
      debugPrint('Error saving app config: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_config'.tr);
      return false;
    } finally {
      isSaving = false;
      update();
    }
  }

  /// Tells the members who have to install the new build — and only them.
  ///
  /// Who is behind comes from what each device stamped on its own record at
  /// its last launch, so somebody already running this version is not asked
  /// to install it again. That stamp is one launch out of date the moment
  /// somebody updates, so the notice carries the version with it and a device
  /// that turns out to be current drops it on arrival rather than showing it
  /// — see `PushNotificationService`.
  ///
  /// Only a version that went *up* gets here: correcting the download link,
  /// or fixing a typo in the number, is not a release.
  Future<void> _notifyMembersBehind(AppConfigModel next) async {
    try {
      final List<String> phones =
          await repository.fetchPhonesBehind(next.versionValue);
      // This device is publishing it; whether it is behind is between the
      // admin and the splash screen.
      phones.remove(userPhone);

      if (phones.isEmpty) {
        CustomSnackbar.show(
            type: SnackbarType.info, message: 'everyone_up_to_date'.tr);
        return;
      }

      final Map<String, String> payload = {
        'type': 'app_update',
        'version': next.appVersion,
        'downloadLink': next.downloadLink,
        'senderName': userName,
        'senderPhone': userPhone,
      };

      if (Get.isRegistered<PushOutboxService>()) {
        // Through the outbox: publishing a version while the admin's own
        // connection is down must still reach people once it is back.
        await Get.find<PushOutboxService>().send(
          title: 'update_available_title'.tr,
          body: 'update_available_body'.trParams({'version': next.appVersion}),
          targetPhones: phones,
          data: payload,
          dataOnly: true,
        );
      } else {
        await PushNotificationService().sendPushNotification(
          title: 'update_available_title'.tr,
          body: 'update_available_body'.trParams({'version': next.appVersion}),
          targetPhones: phones,
          data: payload,
          dataOnly: true,
        );
      }

      CustomSnackbar.show(
        type: SnackbarType.success,
        message: 'update_notified'.trParams({'count': '${phones.length}'}),
      );
    } catch (e) {
      debugPrint('Config: update notice failed — $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_notify_update'.tr);
    }
  }

  /// ------------------------------------------------------- daily reminder

  void setReminderEnabled(bool value) {
    if (!isAdminUser || reminderEnabled == value) return;
    reminderEnabled = value;
    update();
  }

  /// [hour] and [minute] on a 24-hour clock, as the time picker hands them
  /// over.
  void setReminderTime(int hour, int minute) {
    if (!isAdminUser) return;
    final String next = '${hour.toString().padLeft(2, '0')}:'
        '${minute.toString().padLeft(2, '0')}';
    if (next == reminderTime) return;
    reminderTime = next;
    update();
  }

  /// Saves the reminder settings and gets them onto everyone's device.
  ///
  /// Three steps, in an order that matters. Firestore first, because that is
  /// what a device reads at its next launch and what the whole house
  /// eventually agrees with. Then this device's own job, so the admin who just
  /// changed the hour does not have to wait for their own message to come
  /// back round through FCM. Then the silent message that carries the change
  /// to every device that is not being held — see [DailyReminderService].
  ///
  /// The last two are best-effort: a change that reached Firestore is saved
  /// whether or not it was delivered tonight, and the next launch picks it up.
  Future<bool> saveReminder() async {
    if (!isAdminUser) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'admin_only_action'.tr);
      return false;
    }

    // Nothing moved, so nothing to write — and nothing to wake every device in
    // the house for.
    if (!reminderDirty) {
      CustomSnackbar.show(
          type: SnackbarType.info, message: 'no_changes_to_save'.tr);
      return false;
    }

    try {
      isSavingReminder = true;
      update();

      final AppConfigModel next = (config ?? const AppConfigModel()).copyWith(
        reminderEnabled: reminderEnabled,
        reminderTime: reminderTime,
        updatedBy: userName,
      );

      // Only the reminder's own two fields: the version and the download link
      // belong to the other tab, and an admin editing one must not publish a
      // half-typed version from the other.
      await repository.saveAppConfig(next.toReminderMap(), by: userName);

      config = next;
      _savedReminderEnabled = reminderEnabled;
      _savedReminderTime = reminderTime;

      final bool armed = await DailyReminderService.sync(next);
      await _broadcastReminderConfig(next);

      if (!armed) {
        // Saved, but this device will not act on it. Everyone else still
        // will, so this is a warning about the admin's own phone rather than
        // a failed save.
        CustomSnackbar.show(
            type: SnackbarType.warning, message: 'reminder_not_armed'.tr);
        return true;
      }

      CustomSnackbar.show(
        type: SnackbarType.success,
        message: reminderEnabled
            ? 'reminder_saved_at'.trParams({'when': untilNextReminder})
            : 'reminder_turned_off'.tr,
      );
      return true;
    } catch (e) {
      debugPrint('Error saving the daily reminder: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_reminder'.tr);
      return false;
    } finally {
      isSavingReminder = false;
      update();
    }
  }

  /// Raises tonight's reminder now, so an admin can see the thing itself
  /// instead of waiting until the evening to find out whether it works.
  ///
  /// The message is put in a snackbar as well as the notification tray. That
  /// is the point of it: if the tray stays empty but the snackbar reads
  /// correctly, the summary is fine and it is the phone's notification
  /// permission that is off — the one failure the app cannot see for itself.
  Future<void> sendTestReminder() async {
    if (isSendingTest) return;

    try {
      isSendingTest = true;
      update();

      final String body = await DailyReminderService.showNow();
      CustomSnackbar.show(type: SnackbarType.success, message: body);
    } catch (e) {
      debugPrint('Reminder: test failed — $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_test_reminder'.tr);
    } finally {
      isSendingTest = false;
      update();
    }
  }

  /// Tells every device the reminder has moved, without showing anything.
  ///
  /// Data-only and untargeted: this goes to the house topic rather than to a
  /// list of phones, because it is not news anybody reads — it is a setting
  /// each device applies to itself, and one that misses it is corrected at
  /// its next launch anyway.
  Future<void> _broadcastReminderConfig(AppConfigModel next) async {
    final Map<String, String> payload = {
      'type': 'reminder_config',
      'enabled': next.reminderEnabled ? '1' : '0',
      'time': next.reminderTime,
      'senderName': userName,
      'senderPhone': userPhone,
    };

    // FCM needs a title and a body even for a message nothing will show;
    // these are never read.
    const String unused = 'reminder_config';

    try {
      if (Get.isRegistered<PushOutboxService>()) {
        // Through the outbox, for the reason the version notice goes that
        // way: a change made while the admin's own connection is down must
        // still reach people once it is back.
        await Get.find<PushOutboxService>().send(
          title: unused,
          body: unused,
          data: payload,
          dataOnly: true,
        );
      } else {
        await PushNotificationService().sendPushNotification(
          title: unused,
          body: unused,
          data: payload,
          dataOnly: true,
        );
      }
    } catch (e) {
      debugPrint('Reminder: could not broadcast the change — $e');
    }
  }
}
