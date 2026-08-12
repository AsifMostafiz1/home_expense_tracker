import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../utils/app_constant.dart';
import '../../meal/model/meal_stats.dart';
import '../../meal/repository/meal_repository.dart';
import '../../member/model/member_model.dart';
import '../model/month_cost_summary.dart';
import '../model/monthly_bill_model.dart';
import '../repository/settings_repository.dart';

/// The read-only month breakdown: this month's house bills next to last
/// month's meals, per member.
///
/// Kept apart from [SettingsController] because it owns a fetch of its own —
/// the meal statistics for a month the meal screen may never have opened.
class MonthDetailsController extends GetxController implements GetxService {
  final MealRepository mealRepository;
  final SettingsRepository settingsRepository;

  MonthDetailsController({
    required this.mealRepository,
    required this.settingsRepository,
  });

  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  MonthlyBillModel? bill;

  MonthCostSummary? summary;
  bool isLoading = true;
  String errorMessage = '';

  DateTime get mealMonth => MonthCostSummary.mealMonthOf(month);

  /// Seeds the screen before it is pushed — the navigation convention used
  /// everywhere in this app, since no route here takes arguments.
  void open(DateTime month, MonthlyBillModel? bill) {
    this.month = DateTime(month.year, month.month);
    this.bill = bill;
    summary = null;
    errorMessage = '';
    isLoading = true;
    update();

    load();
  }

  /// Called when the bill form closes: the month may have been saved, changed
  /// or deleted, so the bill is taken again from the settings list.
  Future<void> refreshBill(MonthlyBillModel? bill) async {
    this.bill = bill;
    await load();
  }

  Future<void> load() async {
    try {
      isLoading = true;
      errorMessage = '';
      update();

      SharedPreferences prefs = await SharedPreferences.getInstance();
      final String userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
      final String userName = prefs.getString(AppConstant.keyUserName) ?? '';

      // The month's own statistics, read straight from the meal repository:
      // it is a pure function of the month, unlike the meal controller, whose
      // figures belong to whatever month its calendar is sitting on.
      final MealStats stats =
          await mealRepository.fetchMonthlyStats(userPhone, mealMonth);

      final List<MemberModel> members =
          await settingsRepository.fetchActiveMembers();

      summary = MonthCostSummary.build(
        month: month,
        bill: bill,
        stats: stats,
        currentUserPhone: userPhone,
        currentUserName: userName,
        activeMembers: members,
      );
    } catch (e) {
      errorMessage = e.toString();
      debugPrint('Error loading month details: $e');
    } finally {
      isLoading = false;
      update();
    }
  }
}
