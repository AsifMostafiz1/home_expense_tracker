import '../model/meal_stats.dart';

abstract class MealRepository {
  Future<Map<String, int>> fetchDailyMeals(String userPhone);
  Future<MealStats> fetchMonthlyStats(String userPhone, DateTime focusedDay);
  Future<void> addBulkMeal(String userName, String userPhone, DateTime date);
  Future<void> updateMeal(String userName, String userPhone, DateTime date, int count);
  Future<void> updateAnnouncement(String text, String userName);
  Future<List<Map<String, dynamic>>> fetchAnnouncement();
  Future<void> resolveAnnouncement(String id, String userName);
  Future<void> deleteAnnouncement(String id);
}
