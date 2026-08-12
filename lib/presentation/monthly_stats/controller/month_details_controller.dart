import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_enums.dart';
import '../../meal/model/meal_stats.dart';
import '../../meal/repository/meal_repository.dart';
import '../../member/model/member_model.dart';
import '../model/month_cost_summary.dart';
import '../model/monthly_bill_model.dart';
import '../repository/monthly_stats_repository.dart';
import 'monthly_stats_controller.dart';

/// The read-only month breakdown: this month's house bills next to last
/// month's meals, per member.
///
/// Kept apart from [MonthlyStatsController] because it owns a fetch of its own —
/// the meal statistics for a month the meal screen may never have opened.
class MonthDetailsController extends GetxController implements GetxService {
  final MealRepository mealRepository;
  final MonthlyStatsRepository statsRepository;

  MonthDetailsController({
    required this.mealRepository,
    required this.statsRepository,
  });

  DateTime month = DateTime(DateTime.now().year, DateTime.now().month);
  MonthlyBillModel? bill;

  MonthCostSummary? summary;
  bool isLoading = true;
  String errorMessage = '';

  /// The member currently being collected from, so only that row shows work
  /// in progress instead of the whole page.
  String? settlingPhone;

  String userName = '';
  String userPhone = '';

  /// Everyone can read a month; only an admin can mark it collected.
  bool isAdminUser = false;

  // Kept so marking a collection can rebuild the summary from what is already
  // in hand — the meals of a closed month do not change because someone paid.
  MealStats? _stats;
  List<MemberModel> _members = const [];

  DateTime get mealMonth => MonthCostSummary.mealMonthOf(month);

  /// This month's row for whoever is looking, when they have one.
  MemberCostSummary? get myCost {
    final MonthCostSummary? current = summary;
    if (current == null) return null;
    for (final MemberCostSummary member in current.members) {
      if (member.phone == userPhone) return member;
    }
    return null;
  }

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
  /// or deleted, so the bill is taken again from the months list.
  Future<void> refreshBill(MonthlyBillModel? bill) async {
    this.bill = bill;
    await load(background: true);
  }

  /// Pull-to-refresh. Not named `refresh` — GetX already has one.
  Future<void> refreshDetails() => load(background: true);

  /// Pull-to-refresh and post-edit reloads pass [background]: the content is
  /// already on screen, so it stays there until the new figures arrive.
  Future<void> load({bool background = false}) async {
    try {
      if (!background || summary == null) {
        isLoading = true;
        errorMessage = '';
        update();
      }

      SharedPreferences prefs = await SharedPreferences.getInstance();
      userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
      userName = prefs.getString(AppConstant.keyUserName) ?? '';
      isAdminUser = prefs.getString(AppConstant.keyIsAdmin) == '1';

      // The month's own statistics, read straight from the meal repository:
      // it is a pure function of the month, unlike the meal controller, whose
      // figures belong to whatever month its calendar is sitting on.
      _stats = await mealRepository.fetchMonthlyStats(userPhone, mealMonth);
      _members = await statsRepository.fetchActiveMembers();

      _rebuild();
    } catch (e) {
      debugPrint('Error loading month details: $e');
      if (background && summary != null) {
        CustomSnackbar.show(
            type: SnackbarType.error, message: 'failed_load_details'.tr);
      } else {
        errorMessage = e.toString();
      }
    } finally {
      isLoading = false;
      update();
    }
  }

  void _rebuild() {
    final MealStats? stats = _stats;
    if (stats == null) return;

    summary = MonthCostSummary.build(
      month: month,
      bill: bill,
      stats: stats,
      currentUserPhone: userPhone,
      currentUserName: userName,
      activeMembers: _members,
    );
  }

  /// Marks a member's share collected, or puts it back on the list.
  ///
  /// The write is one key inside the month's document, so nothing else about
  /// the bills is touched; the summary is rebuilt from what is already loaded
  /// rather than re-reading a closed month's meals.
  Future<void> toggleSettled(MemberCostSummary member) async {
    final MonthlyBillModel? current = bill;
    if (current == null || settlingPhone != null) return;
    if (!isAdminUser) {
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'admin_only_action'.tr);
      return;
    }

    final bool settle = !member.settled;

    try {
      settlingPhone = member.phone;
      update();

      await statsRepository.setMemberSettled(
        current.id,
        member.phone,
        settled: settle,
        amount: member.grandTotal,
        by: userName,
      );

      bill = current.withSettlement(
        member.phone,
        settle
            ? SettlementRecord(
                amount: member.grandTotal,
                by: userName,
                at: DateTime.now(),
              )
            : null,
      );
      _rebuild();

      // The months list counts what is still pending from the same document.
      if (Get.isRegistered<MonthlyStatsController>()) {
        Get.find<MonthlyStatsController>().loadStats();
      }

      CustomSnackbar.show(
        type: SnackbarType.success,
        message: (settle ? 'marked_collected' : 'marked_pending')
            .trParams({'name': member.name}),
      );
    } catch (e) {
      debugPrint('Error updating settlement: $e');
      CustomSnackbar.show(
        type: SnackbarType.error,
        message: 'failed_update_settlement'.tr,
      );
    } finally {
      settlingPhone = null;
      update();
    }
  }
}
