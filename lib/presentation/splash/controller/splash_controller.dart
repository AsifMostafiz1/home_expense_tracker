import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/notification_permission_service.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_enums.dart';
import '../../dashboard/view/dashboard_screen.dart';
import '../../auth/view/sign_in_screen.dart';
import '../../update/view/update_screen.dart';

class SplashController extends GetxController {
  @override
  void onInit() {
    super.onInit();
    _checkAppVersion();
  }

  Future<void> _checkAppVersion() async {
    try {
      // Small delay for splash aesthetic
      await Future.delayed(const Duration(seconds: 2));

      DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection(AppConstant.collectionConfig)
          .doc(AppConstant.docBusinessConfig)
          .get();

      if (doc.exists) {
        Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
        String firestoreVersionStr = data['app_version'] ?? "1.0";
        double firestoreVersion = double.tryParse(firestoreVersionStr) ?? 1.0;
        String downloadUrl = data['app_download_link'] ?? "https://facebook.com";

        if (AppConstant.appVersion < firestoreVersion) {
          Get.offAll(() => UpdateScreen(downloadUrl: downloadUrl));
          return;
        }
      }

      await _navigateToNext();
    } catch (e) {
      print("Error checking app version: $e");
      await _navigateToNext();
    }

    await _promptForNotificationPermission();
  }

  /// Asks for the notification permission on every launch that gets past the
  /// splash, so someone who declined — or who never saw the prompt at all —
  /// gets another chance without digging through system settings.
  ///
  /// Deliberately after navigation: `Get.offAll` tears down every route above
  /// it, so a dialog raised any earlier would be swept away with the splash.
  Future<void> _promptForNotificationPermission() async {
    // Let the route transition finish before anything is layered on top.
    await Future.delayed(const Duration(milliseconds: 600));
    await NotificationPermissionService().ensurePermission();
  }

  Future<void> _navigateToNext() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool(AppConstant.keyIsLoggedIn) ?? false;

    if (!isLoggedIn) {
      Get.offAll(() => const SignInScreen());
      return;
    }

    // An admin can remove a member, or change their role, while that member is
    // still signed in on their own device. Both live in local preferences, so
    // re-read the account on every launch.
    final Map<String, dynamic>? account = await _loadAccount(prefs);

    if (account != null) {
      if (account.isEmpty || account['removed'] == true) {
        await _clearSession(prefs);
        Get.offAll(() => const SignInScreen());
        CustomSnackbar.show(
          type: SnackbarType.error,
          message: 'account_removed_message'.tr,
        );
        return;
      }
      await _syncSession(prefs, account);
    }

    Get.offAll(() => const DashboardScreen());
  }

  /// The signed-in user's record.
  ///
  /// `null` means the lookup failed (offline, Firestore down) and the session
  /// should be left alone — a network blip must not lock everyone out. An
  /// empty map means the account is gone.
  Future<Map<String, dynamic>?> _loadAccount(SharedPreferences prefs) async {
    final String? phone = prefs.getString(AppConstant.keyUserPhone);
    if (phone == null || phone.isEmpty) return null;

    try {
      final DocumentSnapshot doc = await FirebaseFirestore.instance
          .collection(AppConstant.collectionUsers)
          .doc(phone)
          .get();

      if (!doc.exists) return const {};
      return doc.data() as Map<String, dynamic>? ?? const {};
    } catch (e) {
      return null;
    }
  }

  /// Pulls the role and name back from the server, so an admin promoting or
  /// demoting someone reaches that person's device without a re-login.
  Future<void> _syncSession(
    SharedPreferences prefs,
    Map<String, dynamic> account,
  ) async {
    await prefs.setString(
        AppConstant.keyIsAdmin, (account['isAdmin'] ?? '0').toString());

    final String name = (account['name'] ?? '').toString();
    if (name.isNotEmpty) {
      await prefs.setString(AppConstant.keyUserName, name);
    }
  }

  Future<void> _clearSession(SharedPreferences prefs) async {
    await prefs.remove(AppConstant.keyIsLoggedIn);
    await prefs.remove(AppConstant.keyUserPhone);
    await prefs.remove(AppConstant.keyUserName);
    await prefs.remove(AppConstant.keyUserProfileImage);
    await prefs.remove(AppConstant.keyIsAdmin);
    await prefs.remove(AppConstant.keySavedPhone);
    await prefs.remove(AppConstant.keySavedPassword);
  }
}
