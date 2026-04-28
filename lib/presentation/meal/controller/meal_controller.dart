import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/app_constant.dart';

class MealController extends GetxController {
  final Rx<DateTime> focusedDay = DateTime.now().obs;
  final Rx<DateTime?> selectedDay = DateTime.now().obs;

  var isLoading = false.obs;
  var isFetchingMeals = true.obs;
  var isFetchingStats = false.obs;
  var dailyMeals = <String, int>{}.obs;

  var myMealCount = 0.obs;
  var otherUsersMeals = <Map<String, dynamic>>[].obs;
  var totalMealCount = 0.obs;

  late final DateTime firstDay;
  late final DateTime lastDay;

  @override
  void onInit() {
    super.onInit();
    final DateTime today = DateTime.now();
    // Previous 3 months and current month
    firstDay = DateTime(today.year, today.month - 3, 1);
    lastDay = DateTime(today.year, today.month + 1, 0); // End of current month
    fetchMeals();
    fetchMonthlyStats();
  }

  void onDaySelected(DateTime selected, DateTime focused) {
    selectedDay.value = selected;
    focusedDay.value = focused;
    showUpdateMealBottomSheet(selected);
  }
  
  void onPageChanged(DateTime focused) {
    focusedDay.value = focused;
    fetchMonthlyStats();
  }

  Future<void> fetchMeals() async {
    try {
      isFetchingMeals.value = true;
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);

      if (userPhone == null) {
        isFetchingMeals.value = false;
        return;
      }

      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection(AppConstant.collectionMeals)
          .where('user_phone', isEqualTo: userPhone)
          .get();

      Map<String, int> mealsMap = {};
      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        DateTime date = DateTime.parse(data['date_time']);
        int count = data['meal_count'] ?? 0;
        
        String dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        mealsMap[dateKey] = count;
      }
      
      dailyMeals.assignAll(mealsMap);
    } catch (e) {
      print('Error fetching meals: $e');
    } finally {
      isFetchingMeals.value = false;
    }
  }

  Future<void> fetchMonthlyStats() async {
    try {
      isFetchingStats.value = true;
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);

      if (userPhone == null) return;

      DateTime focused = focusedDay.value;
      
      String startPrefix = '${focused.year}-${focused.month.toString().padLeft(2, '0')}-01';
      DateTime nextMonth = DateTime(focused.year, focused.month + 1, 1);
      String endPrefix = '${nextMonth.year}-${nextMonth.month.toString().padLeft(2, '0')}-01';

      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection(AppConstant.collectionMeals)
          .where('date_time', isGreaterThanOrEqualTo: startPrefix)
          .where('date_time', isLessThan: endPrefix)
          .get();

      int myCount = 0;
      int totalCount = 0;
      Map<String, Map<String, dynamic>> othersMap = {};

      for (var doc in snapshot.docs) {
        var data = doc.data() as Map<String, dynamic>;
        int count = data['meal_count'] ?? 0;
        String phone = data['user_phone'] ?? '';
        String name = data['user_name'] ?? 'Unknown';
        
        totalCount += count;

        if (phone == userPhone) {
          myCount += count;
        } else {
          if (othersMap.containsKey(phone)) {
            othersMap[phone]!['count'] = (othersMap[phone]!['count'] as int) + count;
          } else {
            othersMap[phone] = {
              'name': name,
              'count': count,
              'phone': phone,
            };
          }
        }
      }

      myMealCount.value = myCount;
      totalMealCount.value = totalCount;
      otherUsersMeals.value = othersMap.values.toList();
    } catch (e) {
      print('Error fetching monthly stats: $e');
    } finally {
      isFetchingStats.value = false;
    }
  }

  bool get canAddBulkMeal {
    if (isFetchingMeals.value) return false;

    final now = DateTime.now();
    
    // Check if focused month is the current month
    if (focusedDay.value.year != now.year || focusedDay.value.month != now.month) {
      return false;
    }
    
    // Check if current month data is already in dailyMeals
    String currentMonthPrefix = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    
    bool hasData = dailyMeals.keys.any((key) => key.startsWith(currentMonthPrefix));
    
    return !hasData;
  }

  int getMealCount(DateTime date) {
    String dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    return dailyMeals[dateKey] ?? 0;
  }

  int _getDefaultMealCountForDay(DateTime date) {
    // Friday count 2, other days count 1
    return date.weekday == DateTime.friday ? 2 : 1;
  }

  Future<void> addBulkMeal() async {
    try {
      isLoading.value = true;
      
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userName = prefs.getString(AppConstant.keyUserName);
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);

      if (userName == null || userPhone == null) {
        isLoading.value = false;
        Get.snackbar('Error', 'User info not found. Please sign in again.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }

      DateTime now = DateTime.now();
      // Get the number of days in the current month
      int daysInMonth = DateTime(now.year, now.month + 1, 0).day;

      WriteBatch batch = FirebaseFirestore.instance.batch();

      for (int i = 1; i <= daysInMonth; i++) {
        DateTime currentDate = DateTime(now.year, now.month, i);
        int count = _getDefaultMealCountForDay(currentDate);

        // Define a unique document ID for each day's meal for the user
        String docId = '${userPhone}_${currentDate.year}-${currentDate.month.toString().padLeft(2, '0')}-${currentDate.day.toString().padLeft(2, '0')}';
        
        DocumentReference docRef = FirebaseFirestore.instance.collection(AppConstant.collectionMeals).doc(docId);
        
        batch.set(docRef, {
          'meal_count': count,
          'date_time': currentDate.toIso8601String(),
          'user_name': userName,
          'user_phone': userPhone,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      await batch.commit();
      
      // Refresh the fetched meals
      await fetchMeals();
      await fetchMonthlyStats();

      isLoading.value = false;
      Get.snackbar('Success', 'Bulk meals added for the current month!',
          snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      isLoading.value = false;
      Get.snackbar('Error', 'Failed to add bulk meals.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }
  Future<void> updateSingleMeal(DateTime date, int count) async {
    try {
      Get.back(); // Close bottom sheet
      isLoading.value = true;
      
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userName = prefs.getString(AppConstant.keyUserName);
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);

      if (userName == null || userPhone == null) {
        isLoading.value = false;
        Get.snackbar('Error', 'User info not found. Please sign in again.',
            snackPosition: SnackPosition.BOTTOM);
        return;
      }

      String docId = '${userPhone}_${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      DocumentReference docRef = FirebaseFirestore.instance.collection(AppConstant.collectionMeals).doc(docId);
      
      await docRef.set({
        'meal_count': count,
        'date_time': date.toIso8601String(),
        'user_name': userName,
        'user_phone': userPhone,
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      
      await fetchMeals();
      await fetchMonthlyStats();
      
      isLoading.value = false;
      Get.snackbar('Success', 'Meal updated successfully!', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      isLoading.value = false;
      Get.snackbar('Error', 'Failed to update meal.', snackPosition: SnackPosition.BOTTOM);
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
            const Text(
              'Update Meal Count',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              formattedDate,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 6, // 2 rows of 6
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 1,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                int count = index; // 0 to 11
                return Obx(() {
                  bool isSelected = selectedCount.value == count;
                  return InkWell(
                    onTap: () => selectedCount.value = count,
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade300,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isSelected ? Colors.white : Colors.black87,
                        ),
                      ),
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
                    borderRadius: BorderRadius.circular(12),
                  ),
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
