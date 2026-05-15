class MealStats {
  final int myCount;
  final int totalCount;
  final double totalExpense;
  final double myExpense;
  final double totalOtherExpense;
  final double myOtherExpense;
  final int userCount;
  final List<Map<String, dynamic>> otherUsersMeals;
  final Map<String, int> dailyMeals;
  final Map<String, int> totalDailyMeals;
  final Map<String, List<Map<String, dynamic>>> userDailyMeals;

  MealStats({
    required this.myCount,
    required this.totalCount,
    required this.totalExpense,
    required this.myExpense,
    required this.totalOtherExpense,
    required this.myOtherExpense,
    required this.userCount,
    required this.otherUsersMeals,
    required this.dailyMeals,
    required this.totalDailyMeals,
    required this.userDailyMeals,
  });
}
