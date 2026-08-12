import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../controller/month_details_controller.dart';
import '../controller/monthly_stats_controller.dart';
import '../model/month_cost_summary.dart';
import '../model/monthly_bill_model.dart';
import '../widgets/my_month_card.dart';
import '../widgets/month_picker_sheet.dart';
import '../widgets/monthly_stats_skeletons.dart';
import 'month_details_screen.dart';
import 'monthly_bill_screen.dart';

/// Admin-only monthly statistics for the house.
///
/// The screen answers one question first — is this month set up? — and keeps
/// every month that came before it a tap away, because next month's setup
/// almost always starts from the last one.
class MonthlyStatsScreen extends GetView<MonthlyStatsController> {
  const MonthlyStatsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(
        title: 'monthly_statistics'.tr,
        actions: [
          GetBuilder<MonthlyStatsController>(
            builder: (c) {
              if (c.isLoading) return const SizedBox(width: 16);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  tooltip: c.isAdminUser ? 'add_month'.tr : 'select_month'.tr,
                  icon: const Icon(Icons.calendar_month_rounded, size: 22),
                  onPressed: () => _showMonthPicker(context, c),
                ),
              );
            },
          ),
        ],
      ),
      body: GetBuilder<MonthlyStatsController>(
        builder: (c) {
          if (c.isLoading) {
            return const MonthlyStatsSkeleton();
          }

          if (c.errorMessage.isNotEmpty) return _buildErrorState(context, c);

          return RefreshIndicator(
            onRefresh: c.refreshStats,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 40),
              children: [
                _buildHeader(context),
                const SizedBox(height: 18),
                _buildCurrentMonthCard(context, c),
                const SizedBox(height: 28),
                _buildSectionLabel(context, 'saved_months'.tr),
                const SizedBox(height: 12),
                if (c.bills.isEmpty)
                  _buildEmptyMonths(context)
                else
                  for (final MonthlyBillModel bill in c.bills)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildMonthRow(context, c, bill),
                    ),
              ],
            ),
          );
        },
      ),
    );
  }

  /// ----------------------------------------------------------------- header

  Widget _buildHeader(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppUi.tint(context, primary),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(Icons.receipt_long_rounded, color: primary, size: 22),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'house_bills'.tr,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppUi.body(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'house_bills_hint'.tr,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.35,
                  color: AppUi.muted(context),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionLabel(BuildContext context, String label) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        color: AppUi.muted(context),
      ),
    );
  }

  /// ------------------------------------------------------- this month card

  /// The month everyone is living in right now, with its one obvious action.
  ///
  /// An admin is running the house, so the card carries the house's figures.
  /// A member is only ever asking one thing — what do I owe — so theirs
  /// carries that instead, with the working folded into a sheet.
  Widget _buildCurrentMonthCard(BuildContext context, MonthlyStatsController c) {
    if (!c.isAdminUser) return _buildMyMonthCard(context, c);

    final Color primary = Theme.of(context).colorScheme.primary;
    final DateTime month = c.thisMonth;
    final MonthlyBillModel? bill = c.currentMonthBill;
    final bool isSetUp = bill != null && !bill.isEmpty;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppUi.tint(context, primary),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.today_rounded, color: primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'this_month'.tr.toUpperCase(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1,
                        color: AppUi.muted(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppUi.monthLabel(month),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                        color: AppUi.body(context),
                      ),
                    ),
                  ],
                ),
              ),
              _statusPill(context, isSetUp),
            ],
          ),
          const SizedBox(height: 16),
          if (isSetUp) ...[
            Row(
              children: [
                _heroStat(context, 'total_bill'.tr,
                    AppUi.amount(bill.grandTotal)),
                _heroDivider(context),
                _heroStat(context, 'shared_per_member'.tr,
                    AppUi.amount(bill.perHeadShared)),
                _heroDivider(context),
                _heroStat(context, 'members'.tr, '${bill.memberCount}'),
              ],
            ),
            const SizedBox(height: 16),
          ] else ...[
            Text(
              'this_month_not_set_hint'.tr,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.45,
                color: AppUi.muted(context),
              ),
            ),
            const SizedBox(height: 16),
          ],
          // For an admin this card is where the month gets set up and
          // corrected; everyone else gets the way in to read it. A member
          // looking at a month nobody has set up yet gets no button at all,
          // because there is nothing behind it for them.
          if (c.isAdminUser)
            CustomButton(
              text: isSetUp
                  ? 'edit_month'.trParams({'month': AppUi.monthLabel(month)})
                  : 'set_up_month'.trParams({'month': AppUi.monthLabel(month)}),
              height: 48,
              borderRadius: 14,
              fontSize: 15,
              onPressed: () => _openBill(context, c, month),
            )
          else if (isSetUp)
            CustomButton(
              text: 'view_month'.trParams({'month': AppUi.monthLabel(month)}),
              height: 48,
              borderRadius: 14,
              fontSize: 15,
              onPressed: () => _openDetails(context, month, bill),
            ),
        ],
      ),
    );
  }

  /// How much of the month is still to be collected — the question an admin
  /// scanning this list is actually asking.
  Widget _collectionPill(BuildContext context, MonthlyBillModel bill) {
    final bool done = bill.isFullySettled;
    final MaterialColor color = done ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppUi.tint(context, color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            done ? Icons.verified_rounded : Icons.pending_outlined,
            size: 10,
            color: AppUi.accent(context, color),
          ),
          const SizedBox(width: 4),
          Text(
            done
                ? 'all_collected'.tr
                : 'pending_count'.trParams({'count': '${bill.pendingCount}'}),
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: AppUi.accent(context, color),
            ),
          ),
        ],
      ),
    );
  }

  /// ------------------------------------------------------- my month card

  /// What the member owes this month, and nothing else — the house's totals
  /// are not their business at a glance. Everything behind the number lives
  /// one tap away in the breakdown sheet.
  Widget _buildMyMonthCard(BuildContext context, MonthlyStatsController c) {
    final MonthlyBillModel? bill = c.currentMonthBill;
    final bool isSetUp = bill != null && !bill.isEmpty;
    final MemberCostSummary? mine = c.myCost;
    final MonthCostSummary? summary = c.myMonthSummary;

    if (!isSetUp || mine == null || summary == null) {
      return _buildMyMonthPlaceholder(context, c, isSetUp);
    }

    return MyMonthCard(
      member: mine,
      summary: summary,
      onMoreInfo: () => showMyBreakdownSheet(context, mine, summary),
    );
  }

  /// The same frame, with the reason there is no number in it yet.
  Widget _buildMyMonthPlaceholder(
    BuildContext context,
    MonthlyStatsController c,
    bool isSetUp,
  ) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool waiting = isSetUp && c.isMyCostLoading;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppUi.tint(context, primary),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: primary.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(14),
            ),
            child: waiting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : Icon(Icons.event_note_rounded, color: primary, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppUi.monthLabel(c.thisMonth),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  waiting
                      ? 'loading_members'.tr
                      : (isSetUp
                          ? 'you_not_in_month'.tr
                          : 'this_month_not_set_hint'.tr),
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: AppUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusPill(BuildContext context, bool isSetUp) {
    final MaterialColor color = isSetUp ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppUi.tint(context, color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isSetUp ? Icons.check_circle_rounded : Icons.pending_outlined,
            size: 12,
            color: AppUi.accent(context, color),
          ),
          const SizedBox(width: 5),
          Text(
            (isSetUp ? 'bill_saved_status' : 'not_set_up').tr.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.5,
              color: AppUi.accent(context, color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStat(BuildContext context, String label, String value) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.4,
              color: AppUi.body(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 2,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.3,
              color: AppUi.muted(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroDivider(BuildContext context) => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: AppUi.hairline(context),
      );

  /// -------------------------------------------------------------- month row

  Widget _buildMonthRow(
    BuildContext context,
    MonthlyStatsController c,
    MonthlyBillModel bill,
  ) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool isThisMonth =
        bill.id == MonthlyBillModel.monthKeyOf(c.thisMonth);

    return Material(
      color: Theme.of(context).cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: AppUi.hairline(context)),
      ),
      child: InkWell(
        onTap: () => _openDetails(context, bill.monthDate, bill),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppUi.tint(context, primary),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.event_note_rounded, size: 20, color: primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            AppUi.monthLabel(bill.monthDate),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppUi.body(context),
                            ),
                          ),
                        ),
                        if (isThisMonth) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppUi.tint(context, Colors.teal),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              'this_month'.tr.toUpperCase(),
                              style: TextStyle(
                                fontSize: 8.5,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0.5,
                                color: AppUi.accent(context, Colors.teal),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            'members_count'
                                .trParams({'count': '${bill.memberCount}'}),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: AppUi.muted(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (c.isAdminUser) ...[
                          const SizedBox(width: 6),
                          _collectionPill(context, bill),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // An admin reads the house's total for the month; a member reads
              // their own — what they owe, or what they already handed over.
              if (!c.isAdminUser)
                _myMonthAmount(context, c, bill)
              else
                Text(
                  AppUi.amount(bill.grandTotal),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.3,
                    color: AppUi.body(context),
                  ),
                ),
              Icon(Icons.chevron_right_rounded,
                  size: 20, color: AppUi.muted(context)),
            ],
          ),
        ),
      ),
    );
  }

  /// A member's own line on a saved month: `Pay ৳2,254` until it is collected,
  /// then `Paid ৳2,254` — the amount that actually changed hands.
  Widget _myMonthAmount(
    BuildContext context,
    MonthlyStatsController c,
    MonthlyBillModel bill,
  ) {
    final double? amount = c.myAmountFor(bill);

    if (amount == null) {
      return Text(
        c.isMyCostLoading ? '…' : '—',
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.bold,
          color: AppUi.muted(context),
        ),
      );
    }

    final bool paid = c.hasPaid(bill);
    final MaterialColor color = paid ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppUi.tint(context, color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            paid ? Icons.check_circle_rounded : Icons.schedule_rounded,
            size: 13,
            color: AppUi.accent(context, color),
          ),
          const SizedBox(width: 5),
          Text(
            (paid ? 'paid_amount' : 'pay_amount')
                .trParams({'amount': AppUi.amount(amount.abs())}),
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.2,
              color: AppUi.accent(context, color),
            ),
          ),
        ],
      ),
    );
  }

  /// ----------------------------------------------------------------- states

  Widget _buildEmptyMonths(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 24),
      decoration: BoxDecoration(
        color: AppUi.neutralSurface(context),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined,
              size: 34, color: AppUi.muted(context)),
          const SizedBox(height: 12),
          Text(
            'no_bills_yet'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: AppUi.body(context).withOpacity(0.75),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'no_bills_hint'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppUi.muted(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, MonthlyStatsController c) {
    return _centeredState(
      context,
      icon: Icons.cloud_off_rounded,
      color: Colors.red,
      title: 'failed_load_bills'.tr,
      hint: 'check_connection'.tr,
      action: TextButton.icon(
        onPressed: c.loadStats,
        icon: const Icon(Icons.refresh_rounded, size: 18),
        label: Text('retry'.tr),
      ),
    );
  }

  Widget _centeredState(
    BuildContext context, {
    required IconData icon,
    required MaterialColor color,
    required String title,
    required String hint,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: AppUi.tint(context, color),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 44, color: AppUi.accent(context, color)),
            ),
            const SizedBox(height: 22),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppUi.body(context).withOpacity(0.75),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppUi.muted(context),
              ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action,
            ],
          ],
        ),
      ),
    );
  }

  /// ---------------------------------------------------------------- actions

  /// A month that already has bills opens on its breakdown; a month with
  /// nothing in it has nothing to break down, so an admin gets the form and
  /// everyone else is told there is nothing there yet.
  void _openMonth(BuildContext context, MonthlyStatsController c, DateTime month) {
    final MonthlyBillModel? bill = c.billForMonth(month);

    if (bill == null || bill.isEmpty) {
      if (c.isAdminUser) {
        _openBill(context, c, month);
      } else {
        CustomSnackbar.show(
          type: SnackbarType.info,
          message: 'month_not_set_up_yet'
              .trParams({'month': AppUi.monthLabel(month)}),
        );
      }
      return;
    }

    _openDetails(context, month, bill);
  }

  void _openDetails(
    BuildContext context,
    DateTime month,
    MonthlyBillModel bill,
  ) {
    Get.find<MonthDetailsController>().open(month, bill);
    Get.to(() => const MonthDetailsScreen());
  }

  void _openBill(BuildContext context, MonthlyStatsController c, DateTime month) {
    c.startBill(month);
    Get.to(() => const MonthlyBillScreen());
  }

  /// Month picker for setting up a month other than this one — the month
  /// ahead, or one that was missed.
  void _showMonthPicker(BuildContext context, MonthlyStatsController c) {
    showMonthPickerSheet(
      context,
      c,
      onSelected: (month) => _openMonth(context, c, month),
    );
  }
}
