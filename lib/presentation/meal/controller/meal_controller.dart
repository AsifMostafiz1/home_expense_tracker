import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/push_notification_service.dart';
import '../../../utils/app_constant.dart';
import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../repository/meal_repository.dart';
import '../model/meal_stats.dart';
import '../../expense/model/expense_model.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../services/fcm_v1_service.dart';

class MealController extends GetxController implements GetxService {
  // Dependencies
  final MealRepository repository;

  MealController({required this.repository});

  // State variables (non-reactive, managed via update())
  DateTime focusedDay = DateTime.now();
  DateTime? selectedDay;
  bool isLoading = false;
  bool isFetchingMeals = true;
  bool isFetchingStats = true;
  bool isAdminUser = false;
  Map<String, int> dailyMeals = {};
  Map<String, int> totalDailyMeals = {};
  Map<String, List<Map<String, dynamic>>> userDailyMeals = {};
  int myMealCount = 0;
  List<Map<String, dynamic>> otherUsersMeals = [];
  int totalMealCount = 0;
  double totalMonthlyExpense = 0.0;
  double myMonthlyExpense = 0.0;
  double totalOtherExpense = 0.0;
  double myOtherExpense = 0.0;
  int userCount = 1;
  List<Map<String, dynamic>> announcements = [];
  List<ExpenseModel> myExpenses = [];
  final announcementController = TextEditingController();

  /// Id of the announcement the user dismissed with the card's close button.
  /// A newer announcement has a different id, so the card comes back on its own.
  String? dismissedAnnouncementId;

  /// Announcements still waiting on someone — resolved ones are hidden for
  /// every member because the flag is stored on the server.
  List<Map<String, dynamic>> get pendingAnnouncements =>
      announcements.where((a) => a['resolved'] != true).toList();

  /// The newest pending announcement, or null when there is none or the user
  /// dismissed it locally with the close button.
  Map<String, dynamic>? get visibleAnnouncement {
    final pending = pendingAnnouncements;
    if (pending.isEmpty) return null;
    final latest = pending.first;
    if (latest['id'] != null && latest['id'] == dismissedAnnouncementId) {
      return null;
    }
    return latest;
  }

  double get avgMealRate {
    if (totalMealCount == 0) return 0.0;
    return totalMonthlyExpense / totalMealCount;
  }

  double get otherCostPerPerson {
    if (userCount == 0) return 0.0;
    return totalOtherExpense / userCount;
  }

  late final DateTime firstDay;
  late final DateTime lastDay;

  @override
  void onInit() {
    super.onInit();
    final DateTime today = DateTime.now();
    firstDay = DateTime(today.year, today.month - 2, 1);
    lastDay = DateTime(today.year, today.month + 2, 0);
    _loadAdminStatus();
    _loadDismissedAnnouncement();
    fetchMeals();
    fetchMonthlyStats();
    fetchAnnouncement();
  }

  Future<void> _loadAdminStatus() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    isAdminUser = prefs.getString(AppConstant.keyIsAdmin) == '1';
    update();
  }

  Future<void> _loadDismissedAnnouncement() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    dismissedAnnouncementId =
        prefs.getString(AppConstant.keyDismissedAnnouncementId);
    update();
  }

  /// Hides the announcement card for this user only, until a newer
  /// announcement arrives.
  Future<void> dismissAnnouncement() async {
    final String? id = visibleAnnouncement?['id'] as String?;
    if (id == null) return;

    dismissedAnnouncementId = id;
    update();

    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstant.keyDismissedAnnouncementId, id);
  }

  /// Marks an announcement resolved on the server, so it disappears from the
  /// meal screen for every member.
  Future<void> resolveAnnouncement(String id) async {
    isLoading = true;
    update();

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userName = prefs.getString(AppConstant.keyUserName);

      await repository.resolveAnnouncement(id, userName ?? 'unknown'.tr);
      await fetchAnnouncement();
      CustomSnackbar.show(
          type: SnackbarType.success, message: 'announcement_resolved'.tr);
    } catch (e) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_resolve_announcement'.tr);
    } finally {
      isLoading = false;
      update();
    }
  }

  /// Deletes an announcement for everyone. Any member is allowed to do this.
  Future<void> deleteAnnouncement(String id) async {
    isLoading = true;
    update();

    try {
      await repository.deleteAnnouncement(id);
      if (dismissedAnnouncementId == id) {
        dismissedAnnouncementId = null;
        await (await SharedPreferences.getInstance())
            .remove(AppConstant.keyDismissedAnnouncementId);
      }
      await fetchAnnouncement();
      CustomSnackbar.show(
          type: SnackbarType.success, message: 'announcement_deleted'.tr);
    } catch (e) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_announcement'.tr);
    } finally {
      isLoading = false;
      update();
    }
  }

  /// Whether this user already has meals recorded in the month [date] falls
  /// in — which, in practice, means the bulk add has been run for it.
  bool hasMealsForMonth(DateTime date) {
    final String prefix =
        '${date.year}-${date.month.toString().padLeft(2, '0')}';
    return dailyMeals.keys.any((key) => key.startsWith(prefix));
  }

  /// Day-by-day editing is a correction to a month that has been filled in.
  /// Before that, the month has no rows to correct.
  bool get canEditDays => hasMealsForMonth(focusedDay);

  void onDaySelected(DateTime selected, DateTime focused) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Block previous days
    if (selected.isBefore(today)) {
      return;
    }

    // The bulk add is what creates the month; editing a single day before
    // that would leave one lone entry and no month behind it.
    if (!hasMealsForMonth(selected)) {
      CustomSnackbar.show(
        type: SnackbarType.info,
        message: 'add_bulk_meal_first'.tr,
      );
      return;
    }

    selectedDay = selected;
    focusedDay = focused;
    showUpdateMealBottomSheet(selected);
    update();
  }

  void onPageChanged(DateTime focused) {
    focusedDay = focused;
    fetchMonthlyStats();
    update();
  }

  /// [background] keeps what is on screen while a pull-to-refresh runs.
  Future<void> fetchMeals({bool background = false}) async {
    try {
      isFetchingMeals = !background;
      update();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);
      if (userPhone == null) return;
      dailyMeals = await repository.fetchDailyMeals(userPhone);
    } catch (e) {
      print('Error fetching meals: $e');
    } finally {
      isFetchingMeals = false;
      update();
    }
  }

  Future<void> fetchMonthlyStats({bool background = false}) async {
    try {
      isFetchingStats = !background;
      update();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);
      if (userPhone == null) return;
      MealStats stats =
          await repository.fetchMonthlyStats(userPhone, focusedDay);
      myMealCount = stats.myCount;
      totalMealCount = stats.totalCount;
      totalMonthlyExpense = stats.totalExpense;
      myMonthlyExpense = stats.myExpense;
      totalOtherExpense = stats.totalOtherExpense;
      myOtherExpense = stats.myOtherExpense;
      userCount = stats.userCount;
      otherUsersMeals = stats.otherUsersMeals;
      dailyMeals.addAll(stats.dailyMeals);
      totalDailyMeals.addAll(stats.totalDailyMeals);
      userDailyMeals.addAll(stats.userDailyMeals);
      myExpenses = List<ExpenseModel>.from(stats.myExpenses);
    } catch (e) {
      print('Error fetching monthly stats: $e');
    } finally {
      isFetchingStats = false;
      update();
    }
  }

  bool get canAddBulkMeal {
    if (isFetchingMeals) return false;
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 1, 1);

    // Only allow for current and next month
    bool isCurrentMonth =
        focusedDay.year == now.year && focusedDay.month == now.month;
    bool isNextMonth = focusedDay.year == nextMonth.year &&
        focusedDay.month == nextMonth.month;

    if (!isCurrentMonth && !isNextMonth) return false;

    String monthPrefix =
        '${focusedDay.year}-${focusedDay.month.toString().padLeft(2, '0')}';
    return !dailyMeals.keys.any((key) => key.startsWith(monthPrefix));
  }

  int getMealCount(DateTime date) {
    String dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return dailyMeals[dateKey] ?? 0;
  }

  int getTodayTotal() {
    final now = DateTime.now();
    String dateKey =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    return totalDailyMeals[dateKey] ?? 0;
  }

  int getTomorrowTotal() {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    String dateKey =
        '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
    return totalDailyMeals[dateKey] ?? 0;
  }

  int _defaultMealCountForDay(DateTime date) =>
      (date.weekday == DateTime.friday || date.weekday == DateTime.saturday)
          ? 2
          : 1;

  Future<void> addBulkMeal() async {
    try {
      isLoading = true;
      update();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userName = prefs.getString(AppConstant.keyUserName);
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);
      if (userName == null || userPhone == null) {
        CustomSnackbar.show(
            type: SnackbarType.error, message: 'user_info_not_found'.tr);
        return;
      }
      await repository.addBulkMeal(userName, userPhone, focusedDay);
      await fetchMeals();
      await fetchMonthlyStats();
      CustomSnackbar.show(
          type: SnackbarType.success, message: 'bulk_meals_added'.tr);
    } catch (e) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_add_bulk_meals'.tr);
    } finally {
      isLoading = false;
      update();
    }
  }

  Future<void> updateSingleMeal(DateTime date, int count) async {
    try {
      closeOverlayRoute();
      isLoading = true;
      update();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userName = prefs.getString(AppConstant.keyUserName);
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);
      if (userName == null || userPhone == null) {
        CustomSnackbar.show(
            type: SnackbarType.error, message: 'user_info_not_found'.tr);
        return;
      }
      await repository.updateMeal(userName, userPhone, date, count);
      await fetchMeals();
      await fetchMonthlyStats();
      CustomSnackbar.show(type: SnackbarType.success, message: 'meal_updated'.tr);
    } catch (e) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_update_meal'.tr);
    } finally {
      isLoading = false;
      update();
    }
  }

  void showUpdateMealBottomSheet(DateTime date) {
    String dateKey =
        '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    int currentCount = dailyMeals[dateKey] ?? 0;
    RxInt selectedCount = currentCount.obs;

    List<String> months = [
      'jan'.tr,
      'feb'.tr,
      'mar'.tr,
      'apr'.tr,
      'may'.tr,
      'jun'.tr,
      'jul'.tr,
      'aug'.tr,
      'sep'.tr,
      'oct'.tr,
      'nov'.tr,
      'dec'.tr
    ];
    String formattedDate =
        '${date.day} ${months[date.month - 1]}, ${date.year}';

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(Get.context!).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('update_meal_count'.tr,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(formattedDate,
                style: TextStyle(fontSize: 14, color: Theme.of(Get.context!).textTheme.bodySmall?.color)),
            const SizedBox(height: 24),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                return Obx(() {
                  bool isSelected = selectedCount.value == index;
                  return InkWell(
                    onTap: () => selectedCount.value = index,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).dividerColor),
                      ),
                      alignment: Alignment.center,
                      child: Text('$index',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color:
                                  isSelected ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color)),
                    ),
                  );
                });
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => updateSingleMeal(date, selectedCount.value),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(Get.context!).colorScheme.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('submit'.tr,
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  void showAdminUpdateMealBottomSheet(DateTime date, String otherUserName, String otherUserPhone) {
    String dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    int currentCount = 0;
    if (userDailyMeals.containsKey(dateKey)) {
      final list = userDailyMeals[dateKey]!;
      for (var user in list) {
        if (user['name'] == otherUserName) {
          currentCount = user['count'];
          break;
        }
      }
    }
    
    RxInt selectedCount = currentCount.obs;
    List<String> months = ['jan'.tr, 'feb'.tr, 'mar'.tr, 'apr'.tr, 'may'.tr, 'jun'.tr, 'jul'.tr, 'aug'.tr, 'sep'.tr, 'oct'.tr, 'nov'.tr, 'dec'.tr];
    String formattedDate = '${date.day} ${months[date.month - 1]}, ${date.year}';

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(Get.context!).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('update_user_meal'.trParams({'name': otherUserName}),
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade700)),
            const SizedBox(height: 8),
            Text(formattedDate,
                style: TextStyle(fontSize: 14, color: Theme.of(Get.context!).textTheme.bodySmall?.color)),
            const SizedBox(height: 24),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                return Obx(() {
                  bool isSelected = selectedCount.value == index;
                  return InkWell(
                    onTap: () => selectedCount.value = index,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? Colors.blue.shade600 : Theme.of(context).dividerColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: isSelected ? Colors.blue.shade600 : Theme.of(context).dividerColor),
                      ),
                      alignment: Alignment.center,
                      child: Text('$index',
                          style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color)),
                    ),
                  );
                });
              },
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () {
                  final int newCount = selectedCount.value;
                  closeOverlayRoute(); // close bottom sheet
                  showConfirmDialog(
                    title: 'confirm_edit'.tr,
                    message: 'confirm_edit_meal'.trParams({
                      'name': otherUserName,
                      'old': currentCount.toString(),
                      'new': newCount.toString(),
                      'date': formattedDate,
                    }),
                    confirmText: 'confirm'.tr,
                    confirmColor: Colors.blue.shade600,
                    onConfirm: () => _updateOtherUserMeal(date, newCount,
                        currentCount, otherUserName, otherUserPhone),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text('submit'.tr, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  Future<void> _updateOtherUserMeal(DateTime date, int newCount, int oldCount, String otherUserName, String otherUserPhone) async {
    try {
      isLoading = true;
      update();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? adminName = prefs.getString(AppConstant.keyUserName);
      String? adminPhone = prefs.getString(AppConstant.keyUserPhone);
      
      if (adminName == null || adminPhone == null) return;

      await repository.updateMeal(otherUserName, otherUserPhone, date, newCount);

      // Log the edit
      List<String> months = ['jan'.tr, 'feb'.tr, 'mar'.tr, 'apr'.tr, 'may'.tr, 'jun'.tr, 'jul'.tr, 'aug'.tr, 'sep'.tr, 'oct'.tr, 'nov'.tr, 'dec'.tr];
      String formattedDate = '${date.day} ${months[date.month - 1]}, ${date.year}';
      
      await FirebaseFirestore.instance.collection(AppConstant.collectionEditLogs).add({
        'adminName': adminName,
        'adminPhone': adminPhone,
        'targetUserName': otherUserName,
        'targetUserPhone': otherUserPhone,
        'type': 'meal',
        'description': 'Meal count changed from $oldCount to $newCount on $formattedDate',
        'createdAt': FieldValue.serverTimestamp(),
      });

      await PushNotificationService().sendPushNotification(
        title: 'Admin Updated Your Meal',
        body: '$adminName has changed your meal count from $oldCount to $newCount on $formattedDate.',
        targetPhones: [otherUserPhone],
      );

      await fetchMeals();
      await fetchMonthlyStats();
      CustomSnackbar.show(type: SnackbarType.success, message: 'Meal updated for $otherUserName');
    } catch (e) {
      CustomSnackbar.show(type: SnackbarType.error, message: 'Failed to update user meal');
    } finally {
      isLoading = false;
      update();
    }
  }

  Future<void> fetchAnnouncement() async {
    try {
      announcements = await repository.fetchAnnouncement();
    } catch (e) {
      print('Error fetching announcements: $e');
    }
    update();
  }



  Future<void> submitAnnouncement() async {
    String text = announcementController.text.trim();
    if (text.isEmpty) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'please_enter_announcement'.tr);
      return;
    }

    isLoading = true;
    update();

    try {
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userName = prefs.getString(AppConstant.keyUserName);

      await repository.updateAnnouncement(text, userName ?? 'unknown'.tr);
      
      // Send Push Notification
      String? userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
      await PushNotificationService().sendPushNotification(
        title: 'new_announcement_from'.trParams({'name': userName ?? 'unknown'.tr}),
        body: text,
        data: {
          'senderName': userName ?? 'unknown'.tr,
          'senderPhone': userPhone,
          'type': 'announcement',
        },
      );

      await fetchAnnouncement();
      announcementController.clear();
      closeOverlayRoute();
      CustomSnackbar.show(type: SnackbarType.success, message: 'announcement_updated'.tr);
    } catch (e) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_update_announcement'.tr);
    } finally {
      isLoading = false;
      update();
    }
  }
}
