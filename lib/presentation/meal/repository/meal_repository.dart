import '../model/meal_stats.dart';

abstract class MealRepository {
  Future<Map<String, int>> fetchDailyMeals(String userPhone);
  Future<MealStats> fetchMonthlyStats(String userPhone, DateTime focusedDay);
  Future<void> addBulkMeal(String userName, String userPhone, DateTime date);
  Future<void> updateMeal(String userName, String userPhone, DateTime date, int count);
  Future<void> updateShoppingList(String text);
  Future<Map<String, dynamic>?> fetchShoppingList();
}
