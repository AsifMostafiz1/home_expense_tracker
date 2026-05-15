import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/app_constant.dart';
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

      _navigateToNext();
    } catch (e) {
      print("Error checking app version: $e");
      _navigateToNext();
    }
  }

  Future<void> _navigateToNext() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool(AppConstant.keyIsLoggedIn) ?? false;

    if (isLoggedIn) {
      Get.offAll(() => const DashboardScreen());
    } else {
      Get.offAll(() => const SignInScreen());
    }
  }
}
