import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../view/sign_in_screen.dart';
import '../../dashboard/view/dashboard_screen.dart';
import '../../../utils/app_constant.dart';
import '../model/user_model.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../repository/auth_repository.dart';
import '../binding/auth_binding.dart';

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
          type: SnackbarType.error, message: 'Please fill all fields');
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
            message: 'User with this phone number already exists');
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
          type: SnackbarType.success, message: 'Account created successfully');

      Get.offAll(() => const DashboardScreen());
    } catch (e) {
      isLoading = false;
      update();
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'Failed to create account.');
    }
  }

  Future<void> signIn() async {
    String phone = phoneController.text.trim();
    String password = passwordController.text.trim();

    if (phone.isEmpty || password.isEmpty) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'Please fill all fields');
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
              type: SnackbarType.success, message: 'Login successful');
          Get.offAll(() => const DashboardScreen());
        } else {
          isLoading = false;
          update();
          CustomSnackbar.show(
              type: SnackbarType.error, message: 'Incorrect password');
        }
      } else {
        isLoading = false;
        update();
        CustomSnackbar.show(
            type: SnackbarType.error, message: 'User not found');
      }
    } catch (e) {
      isLoading = false;
      update();
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'Failed to sign in.');
    }
  }

  Future<void> signOut() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Get.deleteAll(force: true);

    Get.offAll(() => const SignInScreen(), binding: AuthBinding());
  }
}
