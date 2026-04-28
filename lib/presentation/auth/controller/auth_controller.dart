import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../view/sign_in_screen.dart';
import '../../dashboard/view/dashboard_screen.dart';
import '../../../utils/app_constant.dart';
import '../model/user_model.dart';

class AuthController extends GetxController {
  final nameController = TextEditingController();
  final phoneController = TextEditingController();
  final passwordController = TextEditingController();
  
  var isLoading = false.obs;
  var isPasswordVisible = false.obs;

  void togglePasswordVisibility() {
    isPasswordVisible.value = !isPasswordVisible.value;
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
      Get.snackbar('Error', 'Please fill all fields',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    try {
      isLoading.value = true;

      // Check if user already exists
      DocumentSnapshot userDoc = await FirebaseFirestore.instance.collection(AppConstant.collectionUsers).doc(phone).get();
      if (userDoc.exists) {
        isLoading.value = false;
        Get.snackbar('Error', 'User with this phone number already exists',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }

      // Create UserModel instance
      UserModel newUser = UserModel(
        name: name,
        phone: phone,
        password: password,
      );

      // Storing data in Firestore (Firebase Database)
      await FirebaseFirestore.instance.collection(AppConstant.collectionUsers).doc(phone).set({
        ...newUser.toMap(),
        'createdAt': FieldValue.serverTimestamp(),
      });
      
      // Save to SharedPreferences
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstant.keyIsLoggedIn, true);
      await prefs.setString(AppConstant.keyUserPhone, phone);
      await prefs.setString(AppConstant.keyUserName, name);

      isLoading.value = false;
      Get.snackbar('Success', 'Account created successfully',
          snackPosition: SnackPosition.BOTTOM);
      
      Get.offAll(() => const DashboardScreen());
    } catch (e) {
      isLoading.value = false;
      Get.snackbar('Error', 'Failed to create account. Make sure Firebase is configured.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> signIn() async {
    String phone = phoneController.text.trim();
    String password = passwordController.text.trim();

    if (phone.isEmpty || password.isEmpty) {
      Get.snackbar('Error', 'Please fill all fields',
          snackPosition: SnackPosition.BOTTOM);
      return;
    }

    try {
      isLoading.value = true;
      
      DocumentSnapshot doc = await FirebaseFirestore.instance.collection(AppConstant.collectionUsers).doc(phone).get();
      
      if (doc.exists) {
        var data = doc.data() as Map<String, dynamic>;
        UserModel user = UserModel.fromMap(data);

        if (user.password == password) {
          // Save to SharedPreferences
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setBool(AppConstant.keyIsLoggedIn, true);
          await prefs.setString(AppConstant.keyUserPhone, user.phone);
          await prefs.setString(AppConstant.keyUserName, user.name);

          isLoading.value = false;
          Get.snackbar('Success', 'Login successful',
              snackPosition: SnackPosition.BOTTOM);
          Get.offAll(() => const DashboardScreen());
        } else {
          isLoading.value = false;
          Get.snackbar('Error', 'Incorrect password',
              snackPosition: SnackPosition.BOTTOM);
        }
      } else {
        isLoading.value = false;
        Get.snackbar('Error', 'User not found',
            snackPosition: SnackPosition.BOTTOM);
      }
    } catch (e) {
      isLoading.value = false;
      Get.snackbar('Error', 'Failed to sign in. Make sure Firebase is configured.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> signOut() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    Get.deleteAll(force: true);
    
    Get.offAll(() => const SignInScreen());
  }
}
