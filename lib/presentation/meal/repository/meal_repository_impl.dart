import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../utils/app_constant.dart';
import '../model/meal_stats.dart';
import 'meal_repository.dart';

class MealRepositoryImpl implements MealRepository {
  @override
  Future<Map<String, int>> fetchDailyMeals(String userPhone) async {
    QuerySnapshot snapshot = await FirebaseFirestore.instance
        .collection(AppConstant.collectionMeals)
        .where('user_phone', isEqualTo: userPhone)
        .get();

    final Map<String, int> mealsMap = {};
    for (var doc in snapshot.docs) {
      var data = doc.data() as Map<String, dynamic>;
      DateTime date = DateTime.parse(data['date_time']);
      int count = data['meal_count'] ?? 0;
      String dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      mealsMap[dateKey] = count;
    }
    return mealsMap;
  }

  @override
  Future<MealStats> fetchMonthlyStats(String userPhone, DateTime focusedDay) async {
    String startPrefix = '${focusedDay.year}-${focusedDay.month.toString().padLeft(2, '0')}-01';
    DateTime nextMonth = DateTime(focusedDay.year, focusedDay.month + 1, 1);
    String endPrefix = '${nextMonth.year}-${nextMonth.month.toString().padLeft(2, '0')}-01';

    // Meals
    QuerySnapshot mealSnap = await FirebaseFirestore.instance
        .collection(AppConstant.collectionMeals)
        .where('date_time', isGreaterThanOrEqualTo: startPrefix)
        .where('date_time', isLessThan: endPrefix)
        .get();

    int myCount = 0;
    int totalCount = 0;
    final Map<String, Map<String, dynamic>> othersMap = {};
    final Map<String, int> dailyMeals = {};

    for (var doc in mealSnap.docs) {
      var data = doc.data() as Map<String, dynamic>;
      int count = data['meal_count'] ?? 0;
      String phone = data['user_phone'] ?? '';
      String name = data['user_name'] ?? 'Unknown';
      String dateStr = data['date_time'];
      DateTime date = DateTime.parse(dateStr);
      String dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      dailyMeals[dateKey] = count;
      totalCount += count;
      if (phone == userPhone) {
        myCount += count;
      } else {
        if (othersMap.containsKey(phone)) {
          othersMap[phone]!['count'] = (othersMap[phone]!['count'] as int) + count;
        } else {
          othersMap[phone] = {'name': name, 'count': count, 'phone': phone};
        }
      }
    }

    // Expenses
    QuerySnapshot expenseSnap = await FirebaseFirestore.instance
        .collection(AppConstant.collectionExpenses)
        .where('date', isGreaterThanOrEqualTo: startPrefix)
        .where('date', isLessThan: endPrefix)
        .get();

    double totalExpense = 0;
    double myExpense = 0;

    for (var doc in expenseSnap.docs) {
      var data = doc.data() as Map<String, dynamic>;
      double amount = (data['amount'] ?? 0).toDouble();
      String phone = data['user_phone'] ?? '';
      String name = data['user_name'] ?? 'Unknown';
      totalExpense += amount;
      if (phone == userPhone) {
        myExpense += amount;
      } else {
        if (!othersMap.containsKey(phone)) {
          othersMap[phone] = {'name': name, 'count': 0, 'phone': phone, 'expense': amount};
        } else {
          othersMap[phone]!['expense'] = (othersMap[phone]!['expense'] as double? ?? 0) + amount;
        }
      }
    }

    // Ensure expense field exists for all others
    for (var key in othersMap.keys) {
      othersMap[key]!.putIfAbsent('expense', () => 0.0);
    }

    return MealStats(
      myCount: myCount,
      totalCount: totalCount,
      totalExpense: totalExpense,
      myExpense: myExpense,
      otherUsersMeals: othersMap.values.toList(),
      dailyMeals: dailyMeals,
    );
  }

  @override
  Future<void> addBulkMeal(String userName, String userPhone) async {
    DateTime now = DateTime.now();
    int daysInMonth = DateTime(now.year, now.month + 1, 0).day;
    WriteBatch batch = FirebaseFirestore.instance.batch();
    for (int i = 1; i <= daysInMonth; i++) {
      DateTime currentDate = DateTime(now.year, now.month, i);
      int count = currentDate.weekday == DateTime.friday ? 2 : 1;
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
  }

  @override
  Future<void> updateMeal(String userName, String userPhone, DateTime date, int count) async {
    String docId = '${userPhone}_${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    DocumentReference docRef = FirebaseFirestore.instance.collection(AppConstant.collectionMeals).doc(docId);
    await docRef.set({
      'meal_count': count,
      'date_time': date.toIso8601String(),
      'user_name': userName,
      'user_phone': userPhone,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }
}
