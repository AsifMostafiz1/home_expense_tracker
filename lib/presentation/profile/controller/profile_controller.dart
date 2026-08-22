import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/member_avatar_service.dart';
import '../../../services/supabase_storage_service.dart';
import '../../../utils/supabase_config.dart';
import '../../../utils/app_constant.dart';
import '../../auth/view/sign_in_screen.dart';
import '../../auth/binding/auth_binding.dart';
import '../../auth/model/user_model.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../model/edit_log_model.dart';

/// The period presets offered on the edit history screen. [custom] is any
/// range picked by hand from the calendar.
enum EditLogPeriod { thisMonth, lastMonth, last7Days, allTime, custom }

class ProfileController extends GetxController implements GetxService {
  String userName = '';
  String userPhone = '';
  UserModel? userModel;
  bool isAdminUser = false;
  List<EditLogModel> allEditLogs = [];
  List<EditLogModel> editLogs = [];

  /// Edit history has its own load state so its screen can show a skeleton,
  /// an error with retry, and pull-to-refresh without touching the profile
  /// page's [isLoading].
  bool isEditLogsLoading = false;
  bool editLogsLoaded = false;
  String editLogsError = '';

  DateTime? filterStartDate;
  DateTime? filterEndDate;
  EditLogPeriod filterPeriod = EditLogPeriod.thisMonth;
  UserModel? filterTargetUser;

  /// One of [EditLogModel.knownTypes]; null shows every type.
  String? filterType;
  List<UserModel> availableUsers = [];

  int totalMealsEaten = 0;
  double totalMealExpense = 0.0;
  double totalOtherExpense = 0.0;

  bool isLoading = true;
  bool isUpdating = false;

  final SupabaseStorageService _storage = SupabaseStorageService();

  /// Avatar chosen on the edit screen but not saved yet. Held locally so the
  /// upload happens on "save changes" — backing out of the form should not
  /// have already replaced the picture.
  File? pickedProfileImage;
  bool clearProfileImage = false;

  ThemeMode themeMode = ThemeMode.system;
  String currentLanguage = 'en';

  @override
  void onInit() {
    super.onInit();

    _applyPeriodDates(EditLogPeriod.thisMonth);

    _loadThemeMode();
    _loadLanguage();
    _loadUserData();
  }

  Future<void> _loadThemeMode() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? themeStr = prefs.getString(AppConstant.keyThemeMode);
    if (themeStr != null) {
      if (themeStr == 'light')
        themeMode = ThemeMode.light;
      else if (themeStr == 'dark')
        themeMode = ThemeMode.dark;
      else
        themeMode = ThemeMode.system;
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
    if (mode == ThemeMode.light)
      themeStr = 'light';
    else if (mode == ThemeMode.dark) themeStr = 'dark';

    await prefs.setString(AppConstant.keyThemeMode, themeStr);
  }

  void changeLanguage(String langCode) async {
    currentLanguage = langCode;
    Locale locale =
        langCode == 'bn' ? const Locale('bn', 'BD') : const Locale('en', 'US');
    Get.updateLocale(locale);
    update();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstant.keyLanguage, langCode);
  }

  /// The account and the lifetime figures, read again.
  ///
  /// The role badge and the menu under it come from the user document, which
  /// is read once on the way in. An admin promoting or demoting somebody sends
  /// that member a notification, and the tap on it lands here — on the very
  /// page that is showing the old role until this runs.
  Future<void> refreshProfile() => _loadUserData();

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
        // The history screen has its own skeleton, so the profile page does
        // not wait on this read; it is only started here so the list is
        // usually ready by the time that screen is opened.
        unawaited(loadEditLogs(silent: true));
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

  /// Reads the whole edit log. While a list is already on screen it stays
  /// put and is swapped once the read lands; a failure then is a snackbar
  /// (or nothing at all when [silent]) rather than a blank page. Before the
  /// first successful read a failure becomes the screen's error state.
  Future<void> loadEditLogs({bool silent = false}) async {
    if (isEditLogsLoading) return; // a read is already in flight
    try {
      isEditLogsLoading = true;
      editLogsError = '';
      update();

      final results = await Future.wait<QuerySnapshot>([
        FirebaseFirestore.instance
            .collection(AppConstant.collectionEditLogs)
            .orderBy('createdAt', descending: true)
            .get(),
        FirebaseFirestore.instance
            .collection(AppConstant.collectionUsers)
            .get(),
      ]);

      allEditLogs = results[0]
          .docs
          .map((doc) =>
              EditLogModel.fromMap(doc.id, doc.data() as Map<String, dynamic>))
          .toList();
      availableUsers = results[1]
          .docs
          .map((doc) => UserModel.fromMap(doc.data() as Map<String, dynamic>))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      editLogsLoaded = true;
      applyFilters();
    } catch (e) {
      debugPrint('Error fetching edit logs: $e');
      if (!editLogsLoaded) {
        editLogsError = e.toString();
      } else if (!silent) {
        CustomSnackbar.show(
            type: SnackbarType.error, message: 'failed_load_edit_history'.tr);
      }
    } finally {
      isEditLogsLoading = false;
      update();
    }
  }

  /// First open of the history screen: start a read only if none has
  /// succeeded yet and none is running (a failed one is retried here).
  void ensureEditLogsLoaded() {
    if (!editLogsLoaded && !isEditLogsLoading) loadEditLogs();
  }

  Future<void> refreshEditLogs() => loadEditLogs();

  /// Admin-only: removes one history entry for everyone. The row leaves the
  /// list at once; while offline the delete sits in Firestore's queue for
  /// the next connection rather than holding the screen up.
  Future<void> deleteEditLog(EditLogModel log) async {
    if (!isAdminUser) return;

    final bool offline = Get.isRegistered<ConnectivityService>() &&
        Get.find<ConnectivityService>().isOffline;
    final Future<void> write = FirebaseFirestore.instance
        .collection(AppConstant.collectionEditLogs)
        .doc(log.id)
        .delete();

    void dropLocally() {
      allEditLogs.removeWhere((l) => l.id == log.id);
      applyFilters();
    }

    if (offline) {
      dropLocally();
      unawaited(write.catchError(
          (Object e) => debugPrint('Queued edit log delete failed: $e')));
      CustomSnackbar.show(
          type: SnackbarType.info,
          message: 'announcement_change_saved_offline'.tr);
      return;
    }

    try {
      await write;
      dropLocally();
      CustomSnackbar.show(
          type: SnackbarType.success, message: 'edit_log_deleted'.tr);
    } catch (e) {
      debugPrint('Error deleting edit log: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_edit_log'.tr);
    }
  }

  void applyFilters() {
    editLogs = allEditLogs.where((log) {
      if (!_matchesDate(log) || !_matchesUser(log)) return false;
      if (filterType != null && log.type != filterType) return false;
      return true;
    }).toList();
    update();
  }

  bool _matchesDate(EditLogModel log) {
    if (filterStartDate != null && log.createdAt.isBefore(filterStartDate!)) {
      return false;
    }
    if (filterEndDate != null) {
      final DateTime end = filterEndDate!.add(const Duration(days: 1));
      if (!log.createdAt.isBefore(end)) return false;
    }
    return true;
  }

  bool _matchesUser(EditLogModel log) =>
      filterTargetUser == null ||
      log.targetUserPhone == filterTargetUser!.phone;

  /// How many entries the current period and user leave for [type] — the
  /// number on each type chip, so it stays honest while a type is selected.
  int countForType(String? type) => allEditLogs
      .where((log) =>
          _matchesDate(log) &&
          _matchesUser(log) &&
          (type == null || log.type == type))
      .length;

  /// The types that actually occur in the log, in [EditLogModel.knownTypes]
  /// order, so the chip row never offers a filter that can only be empty.
  List<String> get presentTypes {
    final Set<String> seen = allEditLogs.map((l) => l.type).toSet();
    return [
      ...EditLogModel.knownTypes.where(seen.contains),
      ...seen.where((t) => !EditLogModel.knownTypes.contains(t)),
    ];
  }

  /// Anything narrower than the default view (this month, everyone, all types).
  bool get hasActiveFilters =>
      filterTargetUser != null ||
      filterType != null ||
      filterPeriod != EditLogPeriod.thisMonth;

  void _applyPeriodDates(EditLogPeriod period,
      {DateTime? start, DateTime? end}) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    filterPeriod = period;
    switch (period) {
      case EditLogPeriod.thisMonth:
        filterStartDate = DateTime(now.year, now.month, 1);
        filterEndDate = DateTime(now.year, now.month + 1, 0);
        break;
      case EditLogPeriod.lastMonth:
        filterStartDate = DateTime(now.year, now.month - 1, 1);
        filterEndDate = DateTime(now.year, now.month, 0);
        break;
      case EditLogPeriod.last7Days:
        filterStartDate = today.subtract(const Duration(days: 6));
        filterEndDate = today;
        break;
      case EditLogPeriod.allTime:
        filterStartDate = null;
        filterEndDate = null;
        break;
      case EditLogPeriod.custom:
        filterStartDate = start;
        filterEndDate = end;
        break;
    }
  }

  void setPeriod(EditLogPeriod period) {
    _applyPeriodDates(period);
    applyFilters();
  }

  void setDateFilter(DateTime? start, DateTime? end) {
    _applyPeriodDates(EditLogPeriod.custom, start: start, end: end);
    applyFilters();
  }

  void setUserFilter(UserModel? user) {
    filterTargetUser = user;
    applyFilters();
  }

  void setTypeFilter(String? type) {
    filterType = type;
    applyFilters();
  }

  /// Back to the default view: this month, every member, every type.
  void clearFilters() {
    filterTargetUser = null;
    filterType = null;
    _applyPeriodDates(EditLogPeriod.thisMonth);
    applyFilters();
  }

  /// The empty state's escape hatch — drop every filter, including the period.
  void showAllTime() {
    filterTargetUser = null;
    filterType = null;
    _applyPeriodDates(EditLogPeriod.allTime);
    applyFilters();
  }

  /// Picks a new avatar from [source]. Downscaled before it ever leaves the
  /// device — a full-resolution camera shot is several MB, and nothing here
  /// renders larger than a circle avatar.
  Future<void> pickProfileImage(ImageSource source) async {
    try {
      final XFile? picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (picked == null) return;

      pickedProfileImage = File(picked.path);
      clearProfileImage = false;
      update();
    } catch (e) {
      debugPrint('Error picking image: $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_pick_image'.tr);
    }
  }

  /// Marks the current avatar for removal on the next save.
  void removeProfileImage() {
    pickedProfileImage = null;
    clearProfileImage = true;
    update();
  }

  /// Drops any unsaved avatar choice — called when the edit screen is left.
  void discardProfileImageChanges() {
    pickedProfileImage = null;
    clearProfileImage = false;
  }

  /// Saves the profile. [password] blank means "leave it as it is" — the form
  /// starts empty, so most saves never touch it.
  Future<void> updateProfile(
      {required String name, String password = ''}) async {
    try {
      isUpdating = true;
      update();

      // Images live in Supabase Storage; Firestore only ever holds the URL.
      final String? previousImage = userModel?.profileImage;
      String? imageUrl = previousImage;
      if (clearProfileImage) {
        imageUrl = null;
      } else if (pickedProfileImage != null) {
        imageUrl = await _storage.uploadFile(
          pickedProfileImage!,
          folder: SupabaseConfig.folderProfile,
        );
      }

      final Map<String, dynamic> changes = {
        'name': name,
        'profileImage': imageUrl,
      };
      // Only written when the form actually carried one. Falling back to the
      // record in memory would write an empty password — and lock the account
      // out — on any save that ran before that record finished loading.
      if (password.trim().isNotEmpty) {
        changes['password'] = password.trim();
      }

      await FirebaseFirestore.instance
          .collection(AppConstant.collectionUsers)
          .doc(userPhone)
          .update(changes);

      // Only after Firestore points at the new object. Deleting first would
      // leave the avatar broken for good if the write then failed.
      if (imageUrl != previousImage) {
        await _storage.deleteByPublicUrl(previousImage);
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstant.keyUserName, name);
      // Chat reads this pref to stamp outgoing messages with the sender avatar.
      if (imageUrl == null) {
        await prefs.remove(AppConstant.keyUserProfileImage);
      } else {
        await prefs.setString(AppConstant.keyUserProfileImage, imageUrl);
      }

      // Push it into the shared directory straight away so every avatar in the
      // app repaints on the way back, without waiting for the next Firestore read.
      if (Get.isRegistered<MemberAvatarService>()) {
        Get.find<MemberAvatarService>().setMyImage(userPhone, imageUrl);
      }

      discardProfileImageChanges();
      await _loadUserData();

      CustomSnackbar.show(
          type: SnackbarType.success, message: 'profile_updated_success'.tr);
      Get.back();
    } catch (e, stack) {
      debugPrint('Error updating profile: $e');
      debugPrint('Stack trace: $stack');
      CustomSnackbar.show(
          type: SnackbarType.error,
          message: '${'failed_update_profile'.tr}: $e');
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
