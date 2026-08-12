import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import '../model/month_cost_summary.dart';
import 'member_cost_ledger.dart';

/// A member's own month, as a statement.
///
/// Four bands, in the order the question is asked: which month and is it
/// settled, the one number that matters, what it is made of, and the way to
/// the full working. Stacking those as loose blocks is what made the first
/// version read as a list of leftovers.
class MyMonthCard extends StatelessWidget {
  final MemberCostSummary member;
  final MonthCostSummary summary;

  /// Omitted where the full breakdown is already on screen.
  final VoidCallback? onMoreInfo;

  const MyMonthCard({
    super.key,
    required this.member,
    required this.summary,
    this.onMoreInfo,
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool paid = member.settled;

    // A settled month reports what was handed over, not what was owed — the
    // two can differ if the bills were edited afterwards.
    final double amount =
        paid ? member.settledAmount : member.grandTotal.abs();

    final String heading = paid
        ? 'you_paid'
        : (member.willGet ? 'you_will_get' : 'you_need_to_pay');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppUi.hairline(context)),
        boxShadow: AppUi.softShadow(context),
      ),
      child: Column(
        children: [
          // ------------------------------------------------------ the month
          Container(
            color: AppUi.tint(context, primary),
            padding: const EdgeInsets.fromLTRB(16, 11, 12, 11),
            child: Row(
              children: [
                Icon(Icons.event_note_rounded, size: 16, color: primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    AppUi.monthLabel(summary.month),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.bold,
                      color: AppUi.body(context),
                    ),
                  ),
                ),
                _statusPill(context, paid),
              ],
            ),
          ),

          // ------------------------------------------------------ the number
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
            child: Column(
              children: [
                Text(
                  heading.tr.toUpperCase(),
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.1,
                    color: AppUi.muted(context),
                  ),
                ),
                const SizedBox(height: 6),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    AppUi.amount(amount),
                    style: TextStyle(
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1.6,
                      height: 1.05,
                      color: AppUi.body(context),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'your_share_hint'.trParams({
                    'meals': '${member.mealCount}',
                    'month': AppUi.monthLabel(summary.mealMonth),
                  }),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppUi.muted(context),
                  ),
                ),
              ],
            ),
          ),

          // -------------------------------------------------- what it is of
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppUi.neutralSurface(context),
              border: Border(top: BorderSide(color: AppUi.hairline(context))),
            ),
            child: Row(
              children: [
                _stat(context, 'house_bills'.tr, member.houseBills),
                _statDivider(context),
                _stat(context, 'meal_costs_total'.tr, member.mealTotal),
                _statDivider(context),
                _stat(context, 'total_paid'.tr, member.paid, credit: true),
              ],
            ),
          ),

          // ------------------------------------------------------ the action
          if (onMoreInfo != null)
            Material(
              color: Theme.of(context).cardColor,
              child: InkWell(
                onTap: onMoreInfo,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    border:
                        Border(top: BorderSide(color: AppUi.hairline(context))),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'more_info'.tr,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.bold,
                          color: primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.arrow_forward_rounded,
                          size: 16, color: primary),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _statusPill(BuildContext context, bool paid) {
    final MaterialColor color = paid ? Colors.green : Colors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            paid ? Icons.verified_rounded : Icons.schedule_rounded,
            size: 11,
            color: AppUi.accent(context, color),
          ),
          const SizedBox(width: 5),
          Text(
            (paid ? 'status_paid' : 'status_unpaid').tr.toUpperCase(),
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

  Widget _stat(BuildContext context, String label, double value,
      {bool credit = false}) {
    return Expanded(
      child: Column(
        children: [
          Text(
            AppUi.amount(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.3,
              color: credit && value > 0
                  ? AppUi.accent(context, Colors.teal)
                  : AppUi.body(context),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppUi.muted(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statDivider(BuildContext context) => Container(
        width: 1,
        height: 24,
        color: AppUi.hairline(context),
      );
}

/// The full receipt behind [MyMonthCard], on request.
void showMyBreakdownSheet(
  BuildContext context,
  MemberCostSummary member,
  MonthCostSummary summary,
) {
  Get.bottomSheet(
    Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppUi.muted(context).withOpacity(0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'your_breakdown'.tr,
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: AppUi.body(context),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'bills_of_month'.trParams(
                              {'month': AppUi.monthLabel(summary.month)}),
                          style: TextStyle(
                            fontSize: 11.5,
                            color: AppUi.muted(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: AppUi.hairline(context)),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Column(
                  children: [
                    MemberCostLedger(
                      member: member,
                      mealRate: summary.mealRate,
                      showSharedHint: true,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline_rounded,
                            size: 13, color: AppUi.muted(context)),
                        const SizedBox(width: 7),
                        Expanded(
                          child: Text(
                            'meal_month_note'.trParams(
                                {'month': AppUi.monthLabel(summary.mealMonth)}),
                            style: TextStyle(
                              fontSize: 11,
                              height: 1.4,
                              color: AppUi.muted(context),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ),
    isScrollControlled: true,
  );
}
