import '../model/meal_stats.dart';

abstract class MealRepository {
  Future<Map<String, int>> fetchDailyMeals(String userPhone);
  Future<MealStats> fetchMonthlyStats(String userPhone, DateTime focusedDay);
  Future<void> addBulkMeal(String userName, String userPhone, DateTime date);
  Future<void> updateMeal(String userName, String userPhone, DateTime date, int count);
  Future<void> updateAnnouncement(String text, String userName);

  /// Newest first. Each map carries `id`, and `pending` — true while the
  /// announcement, or a change to it, is on this device only. [fromCache]
  /// reads what the device holds, instantly and with no network; the default
  /// goes to the server and fails when it cannot be reached.
  Future<List<Map<String, dynamic>>> fetchAnnouncement({bool fromCache = false});
  Future<void> resolveAnnouncement(String id, String userName);
  Future<void> deleteAnnouncement(String id);
}
