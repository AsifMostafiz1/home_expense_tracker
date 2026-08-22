import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/push_notification_service.dart';
import '../../../services/push_outbox_service.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_enums.dart';
import '../model/app_config_model.dart';
import '../repository/settings_repository.dart';

/// App-wide settings: the version every launch is checked against, and the
/// link the update screen sends people to.
///
/// Small screen, high stakes — publishing a version above the build in
/// people's hands locks them out of the app until they install the new one.
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
}
