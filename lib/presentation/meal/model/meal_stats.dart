class MealStats {
  final int myCount;
  final int totalCount;
  final double totalExpense;
  final double myExpense;
  final List<Map<String, dynamic>> otherUsersMeals;
  final Map<String, int> dailyMeals;

  MealStats({
    required this.myCount,
    required this.totalCount,
    required this.totalExpense,
    required this.myExpense,
    required this.otherUsersMeals,
    required this.dailyMeals,
  });
}
