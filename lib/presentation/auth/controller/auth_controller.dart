import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../view/sign_in_screen.dart';
import '../../dashboard/view/dashboard_screen.dart';
import '../../../utils/app_constant.dart';
import '../model/user_model.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../repository/auth_repository.dart';
import '../binding/auth_binding.dart';
import '../../../common/binding/initial_binding.dart';

class AuthController extends GetxController implements GetxService {
  final AuthRepository repository;

  AuthController({required this.repository});

  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();

  bool isLoading = false;
  bool isPasswordVisible = false;

  void togglePasswordVisibility() {
    isPasswordVisible = !isPasswordVisible;
    update();
  }

  @override
  void onClose() {
    nameController.dispose();
    phoneController.dispose();
    passwordController.dispose();
    super.onClose();
  }

  Future<void> signUp() async {
    String name = nameController.text.trim();
    String phone = phoneController.text.trim();
    String password = passwordController.text.trim();

    if (name.isEmpty || phone.isEmpty || password.isEmpty) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'please_fill_all_fields'.tr);
      return;
    }

    final bangladeshiPhoneRegex = RegExp(r'^01[346789]\d{8}$');
    if (!bangladeshiPhoneRegex.hasMatch(phone)) {
      CustomSnackbar.show(
          type: SnackbarType.error,
          message: 'invalid_phone_number'.tr);
      return;
    }

    try {
      isLoading = true;
      update();

      bool exists = await repository.checkUserExists(phone);
      if (exists) {
        isLoading = false;
        update();
        CustomSnackbar.show(
            type: SnackbarType.error,
            message: 'user_already_exists'.tr);
        return;
      }

      UserModel newUser = UserModel(
        name: name,
        phone: phone,
        password: password,
      );

      await repository.signUp(newUser);

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstant.keyIsLoggedIn, true);
      await prefs.setString(AppConstant.keyUserPhone, phone);
      await prefs.setString(AppConstant.keyUserName, name);

      isLoading = false;
      update();
      CustomSnackbar.show(
          type: SnackbarType.success, message: 'account_created_success'.tr);

      Get.offAll(() => const DashboardScreen(), binding: InitialBinding());
    } catch (e) {
      isLoading = false;
      update();
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_create_account'.tr);
    }
  }

  Future<void> signIn() async {
    String phone = phoneController.text.trim();
    String password = passwordController.text.trim();

    if (phone.isEmpty || password.isEmpty) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'please_fill_all_fields'.tr);
      return;
    }

    try {
      isLoading = true;
      update();

      UserModel? user = await repository.signIn(phone);

      if (user != null) {
        if (user.password == password) {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setBool(AppConstant.keyIsLoggedIn, true);
          await prefs.setString(AppConstant.keyUserPhone, user.phone);
          await prefs.setString(AppConstant.keyUserName, user.name);

          isLoading = false;
          update();
          CustomSnackbar.show(
              type: SnackbarType.success, message: 'login_successful'.tr);
          Get.offAll(() => const DashboardScreen(), binding: InitialBinding());
        } else {
          isLoading = false;
          update();
          CustomSnackbar.show(
              type: SnackbarType.error, message: 'incorrect_password'.tr);
        }
      } else {
        isLoading = false;
        update();
        CustomSnackbar.show(
            type: SnackbarType.error, message: 'user_not_found'.tr);
      }
    } catch (e) {
      isLoading = false;
      update();
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_sign_in'.tr);
    }
  }

  Future<void> signOut() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await FirebaseAuth.instance.signOut();
    Get.deleteAll(force: true);

    Get.offAll(() => const SignInScreen(), binding: AuthBinding());
  }
}
