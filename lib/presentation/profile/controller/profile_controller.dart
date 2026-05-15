import 'dart:io';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/app_constant.dart';
import '../../auth/view/sign_in_screen.dart';
import '../../auth/binding/auth_binding.dart';
import '../../auth/model/user_model.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';

class ProfileController extends GetxController implements GetxService {
  String userName = '';
  String userPhone = '';
  UserModel? userModel;

  int totalMealsEaten = 0;
  double totalMealExpense = 0.0;
  double totalOtherExpense = 0.0;

  bool isLoading = true;
  bool isUpdating = false;

  ThemeMode themeMode = ThemeMode.system;
  String currentLanguage = 'en';

  File? pickedImage;
  final ImagePicker _picker = ImagePicker();

  @override
  void onInit() {
    super.onInit();
    _loadThemeMode();
    _loadLanguage();
    _loadUserData();
  }

  Future<void> _loadThemeMode() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? themeStr = prefs.getString(AppConstant.keyThemeMode);
    if (themeStr != null) {
      if (themeStr == 'light') themeMode = ThemeMode.light;
      else if (themeStr == 'dark') themeMode = ThemeMode.dark;
      else themeMode = ThemeMode.system;
    }
    update();
  }

  Future<void> _loadLanguage() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    currentLanguage = prefs.getString(AppConstant.keyLanguage) ?? 'en';
    update();
  }

  void changeThemeMode(ThemeMode mode) async {
    themeMode = mode;
    Get.changeThemeMode(mode);
    update();
    
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String themeStr = 'system';
    if (mode == ThemeMode.light) themeStr = 'light';
    else if (mode == ThemeMode.dark) themeStr = 'dark';
    
    await prefs.setString(AppConstant.keyThemeMode, themeStr);
  }

  void changeLanguage(String langCode) async {
    currentLanguage = langCode;
    Locale locale = langCode == 'bn' ? const Locale('bn', 'BD') : const Locale('en', 'US');
    Get.updateLocale(locale);
    update();
    
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstant.keyLanguage, langCode);
  }

  Future<void> _loadUserData() async {
    try {
      isLoading = true;
      update();
      
      SharedPreferences prefs = await SharedPreferences.getInstance();
      userName = prefs.getString(AppConstant.keyUserName) ?? '';
      userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
      
      if (userPhone.isNotEmpty) {
        DocumentSnapshot doc = await FirebaseFirestore.instance
            .collection(AppConstant.collectionUsers)
            .doc(userPhone)
            .get();
        
        if (doc.exists) {
          userModel = UserModel.fromMap(doc.data() as Map<String, dynamic>);
          userName = userModel!.name;
          // Sync with prefs
          await prefs.setString(AppConstant.keyUserName, userName);
          if (userModel!.profileImage != null) {
            await prefs.setString(AppConstant.keyUserProfileImage, userModel!.profileImage!);
          } else {
            await prefs.remove(AppConstant.keyUserProfileImage);
          }
        }
        
        await _fetchLifetimeStats();
      }
    } catch (e) {
      print('Error loading user data: $e');
    } finally {
      isLoading = false;
      update();
    }
  }

  Future<void> _fetchLifetimeStats() async {
    try {
      // Fetch all meals
      QuerySnapshot mealSnap = await FirebaseFirestore.instance
          .collection(AppConstant.collectionMeals)
          .where('user_phone', isEqualTo: userPhone)
          .get();

      int meals = 0;
      for (var doc in mealSnap.docs) {
        var data = doc.data() as Map<String, dynamic>;
        meals += (data['meal_count'] as num?)?.toInt() ?? 0;
      }
      totalMealsEaten = meals;

      // Fetch all expenses
      QuerySnapshot expenseSnap = await FirebaseFirestore.instance
          .collection(AppConstant.collectionExpenses)
          .where('user_phone', isEqualTo: userPhone)
          .get();

      double mealExp = 0.0;
      double otherExp = 0.0;
      for (var doc in expenseSnap.docs) {
        var data = doc.data() as Map<String, dynamic>;
        double amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
        String type = data['type'] ?? 'expense';

        if (type == 'expense') {
          mealExp += amount;
        } else if (type == 'others') {
          otherExp += amount;
        }
      }
      totalMealExpense = mealExp;
      totalOtherExpense = otherExp;

    } catch (e) {
      print('Error fetching lifetime stats: $e');
    }
  }

  Future<void> pickImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 50);
    if (image != null) {
      pickedImage = File(image.path);
      update();
    }
  }

  Future<void> updateProfile({required String name, required String password}) async {
    try {
      isUpdating = true;
      update();

      String? imageUrl = userModel?.profileImage;

      if (pickedImage != null) {
        final storageRef = FirebaseStorage.instance
            .ref()
            .child('profile_images')
            .child('$userPhone.jpg');
        
        await storageRef.putFile(pickedImage!);
        imageUrl = await storageRef.getDownloadURL();
      }

      await FirebaseFirestore.instance
          .collection(AppConstant.collectionUsers)
          .doc(userPhone)
          .update({
        'name': name,
        'password': password,
        'profileImage': imageUrl,
      });

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstant.keyUserName, name);
      if (imageUrl != null) {
        await prefs.setString(AppConstant.keyUserProfileImage, imageUrl);
      }
      
      await _loadUserData();
      pickedImage = null;
      
      CustomSnackbar.show(type: SnackbarType.success, message: 'profile_updated_success'.tr);
      Get.back();
    } catch (e, stack) {
      debugPrint('Error updating profile: $e');
      debugPrint('Stack trace: $stack');
      CustomSnackbar.show(type: SnackbarType.error, message: '${'failed_update_profile'.tr}: $e');
    } finally {
      isUpdating = false;
      update();
    }
  }

  Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await FirebaseAuth.instance.signOut();
    Get.deleteAll(force: true);
    Get.offAll(() => const SignInScreen(), binding: AuthBinding());
  }
}
