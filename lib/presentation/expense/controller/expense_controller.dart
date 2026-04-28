import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/app_constant.dart';
import 'package:intl/intl.dart';

class ExpenseModel {
  String id;
  String description;
  double amount;
  DateTime date;
  TimeOfDay time;
  String userName;
  String userPhone;

  ExpenseModel({
    required this.id,
    required this.description,
    required this.amount,
    required this.date,
    required this.time,
    required this.userName,
    required this.userPhone,
  });

  factory ExpenseModel.fromMap(String id, Map<String, dynamic> map) {
    return ExpenseModel(
      id: id,
      description: map['description'] ?? '',
      amount: (map['amount'] ?? 0).toDouble(),
      date: DateTime.parse(map['date']),
      time: TimeOfDay(
        hour: map['time_hour'] ?? 0, 
        minute: map['time_minute'] ?? 0
      ),
      userName: map['user_name'] ?? '',
      userPhone: map['user_phone'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'description': description,
      'amount': amount,
      'date': date.toIso8601String(),
      'time_hour': time.hour,
      'time_minute': time.minute,
      'user_name': userName,
      'user_phone': userPhone,
    };
  }
}

class ExpenseController extends GetxController {
  var isLoading = false.obs;
  var expenses = <ExpenseModel>[].obs;
  var groupedExpenses = <String, List<ExpenseModel>>{}.obs;

  double get currentMonthTotal => expenses.fold(0.0, (sum, item) => sum + item.amount);

  final amountController = TextEditingController();
  final descriptionController = TextEditingController();
  
  var selectedDate = DateTime.now().obs;
  var selectedTime = TimeOfDay.now().obs;

  @override
  void onInit() {
    super.onInit();
    fetchExpenses();
  }

  void clearForm() {
    amountController.clear();
    descriptionController.clear();
    selectedDate.value = DateTime.now();
    selectedTime.value = TimeOfDay.now();
  }

  Future<void> fetchExpenses() async {
    try {
      isLoading.value = true;
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);

      if (userPhone == null) {
        isLoading.value = false;
        return;
      }

      QuerySnapshot snapshot = await FirebaseFirestore.instance
          .collection(AppConstant.collectionExpenses)
          .where('user_phone', isEqualTo: userPhone)
          .get();

      List<ExpenseModel> fetchedList = snapshot.docs.map((doc) {
        return ExpenseModel.fromMap(doc.id, doc.data() as Map<String, dynamic>);
      }).toList();

      // Filter for current month only
      DateTime now = DateTime.now();
      fetchedList = fetchedList.where((exp) => exp.date.year == now.year && exp.date.month == now.month).toList();

      // Sort by date then time descending locally
      fetchedList.sort((a, b) {
        // Truncate time from date for accurate comparison
        DateTime dateA = DateTime(a.date.year, a.date.month, a.date.day);
        DateTime dateB = DateTime(b.date.year, b.date.month, b.date.day);
        
        int dateCmp = dateB.compareTo(dateA);
        if (dateCmp != 0) return dateCmp;
        
        int timeA = a.time.hour * 60 + a.time.minute;
        int timeB = b.time.hour * 60 + b.time.minute;
        return timeB.compareTo(timeA);
      });

      expenses.assignAll(fetchedList);
      groupExpenses();

    } catch (e) {
      print('Error fetching expenses: $e');
    } finally {
      isLoading.value = false;
    }
  }

  void groupExpenses() {
    Map<String, List<ExpenseModel>> map = {};
    for (var exp in expenses) {
      // Create a clean date representation for grouping
      DateTime cleanDate = DateTime(exp.date.year, exp.date.month, exp.date.day);
      String dateStr = DateFormat('dd MMMM, yyyy').format(cleanDate);
      
      if (!map.containsKey(dateStr)) {
        map[dateStr] = [];
      }
      map[dateStr]!.add(exp);
    }
    groupedExpenses.value = map;
  }

  Future<void> submitExpense({String? expenseId}) async {
    String amountStr = amountController.text.trim();
    String desc = descriptionController.text.trim();
    
    if (amountStr.isEmpty) {
      Get.snackbar('Error', 'Please enter amount', snackPosition: SnackPosition.BOTTOM);
      return;
    }

    double amount = double.tryParse(amountStr) ?? 0.0;

    try {
      Get.back(); // close bottom sheet
      isLoading.value = true;
      
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userName = prefs.getString(AppConstant.keyUserName);
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);

      if (userName == null || userPhone == null) return;

      Map<String, dynamic> data = {
        'description': desc.isEmpty ? 'Expense' : desc,
        'amount': amount,
        'date': selectedDate.value.toIso8601String(),
        'time_hour': selectedTime.value.hour,
        'time_minute': selectedTime.value.minute,
        'user_name': userName,
        'user_phone': userPhone,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (expenseId == null) {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection(AppConstant.collectionExpenses).add(data);
      } else {
        await FirebaseFirestore.instance.collection(AppConstant.collectionExpenses).doc(expenseId).update(data);
      }

      await fetchExpenses();
      Get.snackbar('Success', expenseId == null ? 'Expense added' : 'Expense updated', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Error', 'Failed to save expense', snackPosition: SnackPosition.BOTTOM);
    } finally {
      isLoading.value = false;
    }
  }

  Future<void> deleteExpense(String id) async {
    try {
      isLoading.value = true;
      await FirebaseFirestore.instance.collection(AppConstant.collectionExpenses).doc(id).delete();
      await fetchExpenses();
      Get.snackbar('Success', 'Expense deleted', snackPosition: SnackPosition.BOTTOM);
    } catch (e) {
      Get.snackbar('Error', 'Failed to delete expense', snackPosition: SnackPosition.BOTTOM);
      isLoading.value = false;
    }
  }
}
