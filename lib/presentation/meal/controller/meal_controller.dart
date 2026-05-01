import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/app_constant.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../repository/meal_repository.dart';
import '../model/meal_stats.dart';


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
  Map<String, int> dailyMeals = {};
  int myMealCount = 0;
  List<Map<String, dynamic>> otherUsersMeals = [];
  int totalMealCount = 0;
  double totalMonthlyExpense = 0.0;
  double myMonthlyExpense = 0.0;

  double get avgMealRate {
    if (totalMealCount == 0) return 0.0;
    return totalMonthlyExpense / totalMealCount;
  }

  late final DateTime firstDay;
  late final DateTime lastDay;

  @override
  void onInit() {
    super.onInit();
    final DateTime today = DateTime.now();
    firstDay = DateTime(today.year, today.month - 3, 1);
    lastDay = DateTime(today.year, today.month + 1, 0);
    fetchMeals();
    fetchMonthlyStats();
  }

  void onDaySelected(DateTime selected, DateTime focused) {
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

  Future<void> fetchMeals() async {
    try {
      isFetchingMeals = true;
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

  Future<void> fetchMonthlyStats() async {
    try {
      isFetchingStats = true;
      update();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);
      if (userPhone == null) return;
      MealStats stats = await repository.fetchMonthlyStats(userPhone, focusedDay);
      myMealCount = stats.myCount;
      totalMealCount = stats.totalCount;
      totalMonthlyExpense = stats.totalExpense;
      myMonthlyExpense = stats.myExpense;
      otherUsersMeals = stats.otherUsersMeals;
      dailyMeals = stats.dailyMeals;
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
    if (focusedDay.year != now.year || focusedDay.month != now.month) return false;
    String currentMonthPrefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    return !dailyMeals.keys.any((key) => key.startsWith(currentMonthPrefix));
  }

  int getMealCount(DateTime date) {
    String dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return dailyMeals[dateKey] ?? 0;
  }

  int _defaultMealCountForDay(DateTime date) => date.weekday == DateTime.friday ? 2 : 1;

  Future<void> addBulkMeal() async {
    try {
      isLoading = true;
      update();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userName = prefs.getString(AppConstant.keyUserName);
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);
      if (userName == null || userPhone == null) {
        CustomSnackbar.show(type: SnackbarType.error, message: 'User info not found.');
        return;
      }
      await repository.addBulkMeal(userName, userPhone);
      await fetchMeals();
      await fetchMonthlyStats();
      CustomSnackbar.show(type: SnackbarType.success, message: 'Bulk meals added!');
    } catch (e) {
      CustomSnackbar.show(type: SnackbarType.error, message: 'Failed to add bulk meals.');
    } finally {
      isLoading = false;
      update();
    }
  }

  Future<void> updateSingleMeal(DateTime date, int count) async {
    try {
      Get.back();
      isLoading = true;
      update();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userName = prefs.getString(AppConstant.keyUserName);
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);
      if (userName == null || userPhone == null) {
        CustomSnackbar.show(type: SnackbarType.error, message: 'User info not found.');
        return;
      }
      await repository.updateMeal(userName, userPhone, date, count);
      await fetchMeals();
      await fetchMonthlyStats();
      CustomSnackbar.show(type: SnackbarType.success, message: 'Meal updated!');
    } catch (e) {
      CustomSnackbar.show(type: SnackbarType.error, message: 'Failed to update meal.');
    } finally {
      isLoading = false;
      update();
    }
  }

  void showUpdateMealBottomSheet(DateTime date) {
    String dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    int currentCount = dailyMeals[dateKey] ?? 0;
    RxInt selectedCount = currentCount.obs;

    List<String> months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    String formattedDate = '${date.day} ${months[date.month - 1]}, ${date.year}';

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Update Meal Count', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Text(formattedDate, style: const TextStyle(fontSize: 14, color: Colors.grey)),
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
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300),
                      ),
                      alignment: Alignment.center,
                      child: Text('$index', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: isSelected ? Colors.white : Colors.black87)),
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
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Submit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }
}
