import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../../services/background_sync_service.dart';
import '../../../services/connectivity_service.dart';
import '../../../utils/app_constant.dart';
import '../../expense/model/expense_model.dart';
import '../model/meal_stats.dart';
import 'meal_repository.dart';

/// Firestore-backed. Writes are offline-first — they land in Firestore's
/// local store at once and wait for the server's acknowledgement only while
/// there is a connection to wait on (see [_commit]); the same shape as the
/// expense and chat repositories.
class MealRepositoryImpl implements MealRepository {
  /// Optional, for the same reason as everywhere else: with none, every write
  /// simply waits for its acknowledgement.
  final ConnectivityService? connectivity;

  MealRepositoryImpl({this.connectivity});

  static const Duration _ackTimeout = Duration(seconds: 8);
  static const Duration _readTimeout = Duration(seconds: 15);

  CollectionReference<Map<String, dynamic>> get _announcements =>
      FirebaseFirestore.instance.collection(AppConstant.collectionAnnouncements);

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
    final Map<String, int> totalDailyMeals = {};
    final Map<String, List<Map<String, dynamic>>> userDailyMeals = {};

    for (var doc in mealSnap.docs) {
      var data = doc.data() as Map<String, dynamic>;
      int count = data['meal_count'] ?? 0;
      String phone = data['user_phone'] ?? '';
      String name = data['user_name'] ?? 'Unknown';
      String dateStr = data['date_time'];
      DateTime date = DateTime.parse(dateStr);
      String dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
      
      // Calculate total for all users per day
      totalDailyMeals[dateKey] = (totalDailyMeals[dateKey] ?? 0) + count;
      
      // Calculate per user per day
      if (!userDailyMeals.containsKey(dateKey)) {
        userDailyMeals[dateKey] = [];
      }
      userDailyMeals[dateKey]!.add({'name': name, 'count': count});
      
      totalCount += count;
      if (phone == userPhone) {
        myCount += count;
        // Only current user's meals for dailyMeals (markers)
        dailyMeals[dateKey] = count;
      } else {
        if (othersMap.containsKey(phone)) {
          othersMap[phone]!['count'] =
              (othersMap[phone]!['count'] as int) + count;
          (othersMap[phone]!['daily_meals'] as Map<String, int>)[dateKey] = count;
        } else {
          othersMap[phone] = {
            'name': name,
            'count': count,
            'phone': phone,
            'daily_meals': {dateKey: count}
          };
        }
      }
    }

    // How many people share the house.
    //
    // Removed accounts stay in Firestore as tombstones, so the raw document
    // count is not the member count — the same `removed == true` rule the
    // member and monthly-bill lists use has to be applied here too. It is not
    // only a label: this is the divisor behind the "other" rate, so counting a
    // tombstone spreads the house's spending one head too thin and everybody
    // is charged too little.
    QuerySnapshot usersSnap = await FirebaseFirestore.instance
        .collection(AppConstant.collectionUsers)
        .get();
    int userCount = usersSnap.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      return data?['removed'] != true;
    }).length;

    // Expenses
    QuerySnapshot expenseSnap = await FirebaseFirestore.instance
        .collection(AppConstant.collectionExpenses)
        .where('date', isGreaterThanOrEqualTo: startPrefix)
        .where('date', isLessThan: endPrefix)
        .get();

    double totalExpense = 0;
    double myExpense = 0;
    double totalOtherExpense = 0;
    double myOtherExpense = 0;
    final List<ExpenseModel> myExpenses = [];

    for (var doc in expenseSnap.docs) {
      var data = doc.data() as Map<String, dynamic>;
      double amount = (data['amount'] ?? 0).toDouble();
      String phone = data['user_phone'] ?? '';
      String name = data['user_name'] ?? 'Unknown';
      String type = data['type'] ?? 'expense';

      final expenseItem = ExpenseModel.fromMap(doc.id, data);

      if (type == 'expense') {
        totalExpense += amount;
        if (phone == userPhone) {
          myExpense += amount;
          myExpenses.add(expenseItem);
        } else {
          if (!othersMap.containsKey(phone)) {
            othersMap[phone] = {
              'name': name,
              'count': 0,
              'phone': phone,
              'expense': amount,
              'other_expense': 0.0,
              'daily_meals': {},
              'expenses': [expenseItem]
            };
          } else {
            othersMap[phone]!['expense'] =
                (othersMap[phone]!['expense'] as double? ?? 0) + amount;
            othersMap[phone]!.putIfAbsent('expenses', () => []);
            (othersMap[phone]!['expenses'] as List).add(expenseItem);
          }
        }
      } else {
        totalOtherExpense += amount;
        if (phone == userPhone) {
          myOtherExpense += amount;
          myExpenses.add(expenseItem);
        } else {
          if (!othersMap.containsKey(phone)) {
            othersMap[phone] = {
              'name': name,
              'count': 0,
              'phone': phone,
              'expense': 0.0,
              'other_expense': amount,
              'daily_meals': {},
              'expenses': [expenseItem]
            };
          } else {
            othersMap[phone]!['other_expense'] =
                (othersMap[phone]!['other_expense'] as double? ?? 0) + amount;
            othersMap[phone]!.putIfAbsent('expenses', () => []);
            (othersMap[phone]!['expenses'] as List).add(expenseItem);
          }
        }
      }
    }

    // Ensure fields exist for all others
    for (var key in othersMap.keys) {
      othersMap[key]!.putIfAbsent('expense', () => 0.0);
      othersMap[key]!.putIfAbsent('other_expense', () => 0.0);
      othersMap[key]!.putIfAbsent('daily_meals', () => <String, int>{});
      othersMap[key]!.putIfAbsent('expenses', () => <ExpenseModel>[]);
    }

    return MealStats(
      myCount: myCount,
      totalCount: totalCount,
      totalExpense: totalExpense,
      myExpense: myExpense,
      totalOtherExpense: totalOtherExpense,
      myOtherExpense: myOtherExpense,
      userCount: userCount,
      otherUsersMeals: othersMap.values.toList(),
      dailyMeals: dailyMeals,
      totalDailyMeals: totalDailyMeals,
      userDailyMeals: userDailyMeals,
      myExpenses: myExpenses,
    );
  }

  @override
  Future<void> addBulkMeal(String userName, String userPhone, DateTime date) async {
    int daysInMonth = DateTime(date.year, date.month + 1, 0).day;
    WriteBatch batch = FirebaseFirestore.instance.batch();
    for (int i = 1; i <= daysInMonth; i++) {
      DateTime currentDate = DateTime(date.year, date.month, i);
      int count = (currentDate.weekday == DateTime.friday ||
              currentDate.weekday == DateTime.saturday)
          ? 2
          : 1;
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
    await _commit(batch.commit());
  }

  @override
  Future<void> updateMeal(String userName, String userPhone, DateTime date, int count) async {
    String docId = '${userPhone}_${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    DocumentReference docRef = FirebaseFirestore.instance.collection(AppConstant.collectionMeals).doc(docId);
    await _commit(docRef.set({
      'meal_count': count,
      'date_time': date.toIso8601String(),
      'user_name': userName,
      'user_phone': userPhone,
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)));
  }

  @override
  Future<void> updateAnnouncement(String text, String userName) {
    return _commit(_announcements.doc().set({
      'text': text,
      'user_name': userName,
      'updatedAt': FieldValue.serverTimestamp(),
    }));
  }

  @override
  Future<List<Map<String, dynamic>>> fetchAnnouncement(
      {bool fromCache = false}) async {
    final Query<Map<String, dynamic>> query =
        _announcements.orderBy('updatedAt', descending: true);

    // `estimate`: an announcement written offline has no server time yet;
    // the device's clock stands in so it still sorts and shows a time
    // instead of falling off the bottom under "unknown date".
    final QuerySnapshot<Map<String, dynamic>> snapshot = fromCache
        ? await query.get(const GetOptions(
            source: Source.cache,
            serverTimestampBehavior: ServerTimestampBehavior.estimate,
          ))
        : await query
            .get(const GetOptions(
              source: Source.server,
              serverTimestampBehavior: ServerTimestampBehavior.estimate,
            ))
            .timeout(_readTimeout);

    return snapshot.docs.map((doc) {
      final Map<String, dynamic> data = doc.data();
      data['id'] = doc.id;
      data['pending'] = doc.metadata.hasPendingWrites;
      return data;
    }).toList();
  }

  @override
  Stream<List<Map<String, dynamic>>> watchAnnouncements() {
    return _announcements
        .orderBy('updatedAt', descending: true)
        // Metadata too, for the reason the chat stream includes it: an
        // announcement going from "on this device" to "on the server" changes
        // nothing in its data, and the "waiting to sync" mark on it has to
        // clear all the same.
        .snapshots(includeMetadataChanges: true)
        .map(_announcementsOf);
  }

  List<Map<String, dynamic>> _announcementsOf(
      QuerySnapshot<Map<String, dynamic>> snapshot) {
    // A snapshot the server answered is proof the internet is reachable, and
    // one arrives far more often than the connectivity probe would ask.
    if (!snapshot.metadata.isFromCache) connectivity?.reportReachable();

    final List<Map<String, dynamic>> items = snapshot.docs.map((doc) {
      final Map<String, dynamic> data = doc.data();
      data['id'] = doc.id;
      data['pending'] = doc.metadata.hasPendingWrites;
      // `snapshots()` takes no `serverTimestampBehavior`, unlike a one-shot
      // read, so the estimate [fetchAnnouncement] asks for is filled in here
      // instead: an announcement written on this device happened just now,
      // and left with no time it would show no date at all.
      data['updatedAt'] ??= Timestamp.now();
      return data;
    }).toList();

    // Sorted again on this side, because the one the server did cannot place
    // an announcement whose timestamp it has not stamped yet — a post made
    // offline would sink under every older one.
    items.sort((a, b) => _postedAt(b).compareTo(_postedAt(a)));
    return items;
  }

  /// When an announcement was posted, whatever shape its stamp is in.
  static DateTime _postedAt(Map<String, dynamic> announcement) {
    final Object? at = announcement['updatedAt'];
    if (at is Timestamp) return at.toDate();
    if (at is String) return DateTime.tryParse(at) ?? DateTime.now();
    return DateTime.now();
  }

  /// Marks the announcement resolved for everyone — the flag lives on the
  /// server, so the card disappears from every member's meal screen.
  @override
  Future<void> resolveAnnouncement(String id, String userName) {
    return _commit(_announcements.doc(id).set({
      'resolved': true,
      'resolved_by': userName,
      'resolved_at': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true)));
  }

  @override
  Future<void> deleteAnnouncement(String id) =>
      _commit(_announcements.doc(id).delete());

  /// Waits for the server's acknowledgement while online — a rejected write
  /// still surfaces as an error — and returns at once when offline, leaving
  /// the write in Firestore's queue for the next connection.
  Future<void> _commit(Future<void> write) async {
    if (connectivity?.isOffline ?? false) {
      unawaited(write.catchError(
        (Object e) => debugPrint('Meal: queued write failed — $e'),
      ));
      BackgroundSyncService.schedule();
      return;
    }

    try {
      await write.timeout(_ackTimeout);
    } on TimeoutException {
      debugPrint('Meal: write not acknowledged in time — queued');
      BackgroundSyncService.schedule();
    }
  }
}
