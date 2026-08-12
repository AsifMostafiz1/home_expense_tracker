import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../utils/app_constant.dart';
import 'package:intl/intl.dart';
import '../../meal/controller/meal_controller.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../model/expense_model.dart';
import '../repository/expense_repository.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../services/push_notification_service.dart';

class ExpenseController extends GetxController implements GetxService {
  final ExpenseRepository repository;

  ExpenseController({required this.repository});

  bool isLoading = false;
  List<ExpenseModel> expenses = [];
  Map<String, List<ExpenseModel>> groupedExpenses = {};
  int selectedMonthIndex = 0; // 0 for current, 1 for next
  String selectedType = 'expense'; // 'expense' or 'others'

  DateTime get targetMonth {
    DateTime now = DateTime.now();
    if (selectedMonthIndex == 0) return now;
    return DateTime(now.year, now.month + 1, 1);
  }

  String get selectedMonthName => DateFormat('MMMM, yyyy').format(targetMonth);

  double get displayTotal =>
      filteredExpenses.fold(0.0, (sum, item) => sum + item.amount);

  double get mealTotal =>
      filteredExpenses.where((exp) => exp.type == 'expense').fold(0.0, (sum, item) => sum + item.amount);

  double get othersTotal =>
      filteredExpenses.where((exp) => exp.type == 'others').fold(0.0, (sum, item) => sum + item.amount);

  List<ExpenseModel> get filteredExpenses {
    DateTime target = targetMonth;
    return expenses.where((exp) => exp.date.year == target.year && exp.date.month == target.month).toList();
  }

  void setMonthIndex(int index) {
    selectedMonthIndex = index;
    groupExpenses();
    update();
  }

  void setExpenseType(String type) {
    selectedType = type;
    update();
  }

  final amountController = TextEditingController();
  final descriptionController = TextEditingController();
  String? amountError;

  DateTime selectedDate = DateTime.now();
  TimeOfDay selectedTime = TimeOfDay.now();

  @override
  void onInit() {
    super.onInit();
    fetchExpenses();
  }

  void clearForm() {
    amountController.clear();
    descriptionController.clear();
    amountError = null;
    selectedDate = DateTime.now();
    selectedTime = TimeOfDay.now();
    selectedType = 'expense';
    update();
  }

  void updateSelectedDate(DateTime date) {
    selectedDate = date;
    update();
  }

  void updateSelectedTime(TimeOfDay time) {
    selectedTime = time;
    update();
  }

  /// [background] is the pull-to-refresh path: the list stays on screen and
  /// is swapped once the response lands, instead of collapsing to a skeleton
  /// the user has already seen.
  Future<void> fetchExpenses({bool background = false}) async {
    try {
      isLoading = !background;
      update();
      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? userPhone = prefs.getString(AppConstant.keyUserPhone);

      if (userPhone == null) {
        isLoading = false;
        update();
        return;
      }

      List<ExpenseModel> fetchedList = await repository.fetchExpenses(userPhone);

      // Filter for current and next month
      DateTime now = DateTime.now();
      DateTime nextMonth = DateTime(now.year, now.month + 1, 1);
      fetchedList = fetchedList.where((exp) {
        bool isCurrent = exp.date.year == now.year && exp.date.month == now.month;
        bool isNext = exp.date.year == nextMonth.year && exp.date.month == nextMonth.month;
        return isCurrent || isNext;
      }).toList();

      // Sort by date then time descending locally
      fetchedList.sort((a, b) {
        DateTime dateA = DateTime(a.date.year, a.date.month, a.date.day);
        DateTime dateB = DateTime(b.date.year, b.date.month, b.date.day);

        int dateCmp = dateB.compareTo(dateA);
        if (dateCmp != 0) return dateCmp;

        int timeA = a.time.hour * 60 + a.time.minute;
        int timeB = b.time.hour * 60 + b.time.minute;
        return timeB.compareTo(timeA);
      });

      expenses = fetchedList;
      groupExpenses();
    } catch (e) {
      print('Error fetching expenses: $e');
    } finally {
      isLoading = false;
      update();
    }
  }

  void groupExpenses() {
    Map<String, List<ExpenseModel>> map = {};
    for (var exp in filteredExpenses) {
      DateTime cleanDate = DateTime(exp.date.year, exp.date.month, exp.date.day);
      String dateStr = DateFormat('dd MMMM, yyyy').format(cleanDate);

      if (!map.containsKey(dateStr)) {
        map[dateStr] = [];
      }
      map[dateStr]!.add(exp);
    }
    groupedExpenses = map;
  }

  Future<void> submitExpense({ExpenseModel? existingExpense}) async {
    String amountStr = amountController.text.trim();
    String desc = descriptionController.text.trim();

    amountError = null;
    update();

    if (amountStr.isEmpty) {
      amountError = 'please_enter_amount'.tr;
      update();
      return;
    }

    double? parsedAmount = double.tryParse(amountStr);
    if (parsedAmount == null || parsedAmount <= 0) {
      amountError = 'please_enter_valid_amount'.tr;
      update();
      return;
    }

    double amount = parsedAmount;

    try {
      Get.back(); // close bottom sheet
      isLoading = true;
      update();

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? currentUserName = prefs.getString(AppConstant.keyUserName);
      String? currentUserPhone = prefs.getString(AppConstant.keyUserPhone);

      if (currentUserName == null || currentUserPhone == null) return;

      String finalUserName = existingExpense != null ? existingExpense.userName : currentUserName;
      String finalUserPhone = existingExpense != null ? existingExpense.userPhone : currentUserPhone;

      Map<String, dynamic> data = {
        'description': desc.isEmpty ? 'expense'.tr : desc,
        'amount': amount,
        'date': selectedDate.toIso8601String(),
        'time_hour': selectedTime.hour,
        'time_minute': selectedTime.minute,
        'user_name': finalUserName,
        'user_phone': finalUserPhone,
        'type': selectedType,
        'updatedAt': DateTime.now().toIso8601String(), // Or use FieldValue.serverTimestamp() in repository
      };

      if (existingExpense == null) {
        data['createdAt'] = DateTime.now().toIso8601String();
        await repository.addExpense(data);
      } else {
        await repository.updateExpense(existingExpense.id, data);
        
        if (finalUserPhone != currentUserPhone) {
          String logDesc = 'Expense "${existingExpense.description}" edited: amount ${existingExpense.amount} -> $amount';
          await FirebaseFirestore.instance.collection(AppConstant.collectionEditLogs).add({
            'adminName': currentUserName,
            'adminPhone': currentUserPhone,
            'targetUserName': finalUserName,
            'targetUserPhone': finalUserPhone,
            'type': 'expense',
            'description': logDesc,
            'createdAt': FieldValue.serverTimestamp(),
          });
          
          await PushNotificationService().sendPushNotification(
            title: 'Admin Updated Your Expense',
            body: '$currentUserName has updated your expense "${existingExpense.description}".',
            targetPhones: [finalUserPhone],
          );
        }
      }

      await fetchExpenses();
      if (Get.isRegistered<MealController>()) {
        Get.find<MealController>().fetchMonthlyStats();
      }
      CustomSnackbar.show(
          type: SnackbarType.success,
          message: existingExpense == null ? 'expense_added'.tr : 'expense_updated'.tr);
    } catch (e) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_save_expense'.tr);
    } finally {
      isLoading = false;
      update();
    }
  }

  Future<void> deleteExpense(ExpenseModel expense) async {
    try {
      isLoading = true;
      update();
      await repository.deleteExpense(expense.id);

      SharedPreferences prefs = await SharedPreferences.getInstance();
      String? currentUserPhone = prefs.getString(AppConstant.keyUserPhone);
      String? currentUserName = prefs.getString(AppConstant.keyUserName);

      if (currentUserPhone != null && currentUserName != null && expense.userPhone != currentUserPhone) {
         String logDesc = 'Expense "${expense.description}" of ৳${expense.amount} deleted';
         await FirebaseFirestore.instance.collection(AppConstant.collectionEditLogs).add({
            'adminName': currentUserName,
            'adminPhone': currentUserPhone,
            'targetUserName': expense.userName,
            'targetUserPhone': expense.userPhone,
            'type': 'expense',
            'description': logDesc,
            'createdAt': FieldValue.serverTimestamp(),
          });

          await PushNotificationService().sendPushNotification(
            title: 'Admin Deleted Your Expense',
            body: '$currentUserName has deleted your expense "${expense.description}".',
            targetPhones: [expense.userPhone],
          );
      }
      await fetchExpenses();
      if (Get.isRegistered<MealController>()) {
        Get.find<MealController>().fetchMonthlyStats();
      }
      CustomSnackbar.show(type: SnackbarType.success, message: 'expense_deleted'.tr);
    } catch (e) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_delete_expense'.tr);
      isLoading = false;
      update();
    }
  }
}

