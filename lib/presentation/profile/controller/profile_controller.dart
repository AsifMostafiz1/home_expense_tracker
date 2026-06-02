import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/app_constant.dart';
import '../../auth/view/sign_in_screen.dart';
import '../../auth/binding/auth_binding.dart';
import '../../auth/model/user_model.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../model/edit_log_model.dart';

class ProfileController extends GetxController implements GetxService {
  String userName = '';
  String userPhone = '';
  UserModel? userModel;
  bool isAdminUser = false;
  List<EditLogModel> allEditLogs = [];
  List<EditLogModel> editLogs = [];

  DateTime? filterStartDate;
  DateTime? filterEndDate;
  UserModel? filterTargetUser;
  List<UserModel> availableUsers = [];

  int totalMealsEaten = 0;
  double totalMealExpense = 0.0;
  double totalOtherExpense = 0.0;

  bool isLoading = true;
  bool isUpdating = false;

  ThemeMode themeMode = ThemeMode.system;
  String currentLanguage = 'en';

  @override
  void onInit() {
    super.onInit();
    
    // Set default filter to current month
    DateTime now = DateTime.now();
    filterStartDate = DateTime(now.year, now.month, 1);
    filterEndDate = DateTime(now.year, now.month + 1, 0); // Last day of current month

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
          isAdminUser = userModel!.isAdmin == '1';
          // Sync with prefs
          await prefs.setString(AppConstant.keyUserName, userName);
          await prefs.setString(AppConstant.keyIsAdmin, userModel!.isAdmin);
        }
        
        await _fetchLifetimeStats();
        await fetchUsersForFilter();
        await _fetchEditLogs();
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

  Future<void> _fetchEditLogs() async {
    try {
      Query query = FirebaseFirestore.instance
          .collection(AppConstant.collectionEditLogs)
          .orderBy('createdAt', descending: true);

      QuerySnapshot snapshot = await query.get();
      allEditLogs = snapshot.docs.map((doc) => EditLogModel.fromMap(doc.id, doc.data() as Map<String, dynamic>)).toList();
      applyFilters();
    } catch (e) {
      print('Error fetching edit logs: $e');
    }
  }

  void applyFilters() {
    editLogs = allEditLogs.where((log) {
      if (filterStartDate != null) {
        if (log.createdAt.isBefore(filterStartDate!)) return false;
      }
      if (filterEndDate != null) {
        DateTime end = filterEndDate!.add(const Duration(days: 1));
        if (log.createdAt.isAfter(end) || log.createdAt.isAtSameMomentAs(end)) return false;
      }
      if (filterTargetUser != null) {
        if (log.targetUserPhone != filterTargetUser!.phone) return false;
      }
      return true;
    }).toList();
    update();
  }

  void setDateFilter(DateTime? start, DateTime? end) {
    filterStartDate = start;
    filterEndDate = end;
    applyFilters();
  }

  void setUserFilter(UserModel? user) {
    filterTargetUser = user;
    applyFilters();
  }

  void clearFilters() {
    filterStartDate = null;
    filterEndDate = null;
    filterTargetUser = null;
    applyFilters();
  }

  Future<void> fetchUsersForFilter() async {
    try {
      QuerySnapshot snapshot = await FirebaseFirestore.instance.collection(AppConstant.collectionUsers).get();
      availableUsers = snapshot.docs.map((doc) => UserModel.fromMap(doc.data() as Map<String, dynamic>)).toList();
      update();
    } catch(e) {
      print('Error fetching users for filter: $e');
    }
  }

  Future<void> updateProfile({required String name, required String password}) async {
    try {
      isUpdating = true;
      update();

      await FirebaseFirestore.instance
          .collection(AppConstant.collectionUsers)
          .doc(userPhone)
          .update({
        'name': name,
        'password': password,
      });

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstant.keyUserName, name);
      
      await _loadUserData();
      
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
    await prefs.remove(AppConstant.keyIsLoggedIn);
    await prefs.remove(AppConstant.keyUserPhone);
    await prefs.remove(AppConstant.keyUserName);
    await prefs.remove(AppConstant.keyUserProfileImage);
    await FirebaseAuth.instance.signOut();
    Get.deleteAll(force: true);
    Get.offAll(() => const SignInScreen(), binding: AuthBinding());
  }
}
