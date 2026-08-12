import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import '../model/month_cost_summary.dart';

/// One member's month as a receipt: what is charged, what they already
/// covered, and the one line that survives the subtraction.
///
/// Shared by the admin's per-member cards and by the member's own breakdown
/// sheet — the same arithmetic must not be laid out two different ways
/// depending on who is looking at it.
class MemberCostLedger extends StatelessWidget {
  final MemberCostSummary member;
  final double mealRate;

  /// Whether to spell out how the house bills split into rent and shared
  /// costs. A member's own rent is theirs to see; another member's is not.
  final bool showRentSplit;

  const MemberCostLedger({
    super.key,
    required this.member,
    required this.mealRate,
    this.showRentSplit = true,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Charged --------------------------------------------------------
        _row(
          context,
          sign: '+',
          label: 'house_bills'.tr,
          note: showRentSplit
              ? 'rent_plus_shared'.trParams({
                  'rent': AppUi.amount(member.rent),
                  'shared': AppUi.amount(member.sharedBills),
                })
              : null,
          value: member.houseBills,
        ),
        _row(
          context,
          sign: '+',
          label: 'meal_cost'.tr,
          note: member.mealCount == 0
              ? null
              : 'meals_times_rate'.trParams({
                  'count': '${member.mealCount}',
                  'rate': AppUi.amount(mealRate),
                }),
          value: member.mealCost,
        ),
        _row(
          context,
          sign: '+',
          label: 'other_cost'.tr,
          value: member.otherCost,
        ),

        _rule(context),
        _row(
          context,
          label: 'subtotal'.tr,
          value: member.subtotal,
          emphasis: true,
        ),

        // Paid -----------------------------------------------------------
        const SizedBox(height: 4),
        _row(
          context,
          sign: '−',
          label: 'meal_paid'.tr,
          value: member.mealPaid,
          credit: true,
        ),
        _row(
          context,
          sign: '−',
          label: 'other_paid'.tr,
          value: member.otherPaid,
          credit: true,
        ),
        const SizedBox(height: 10),
        MemberGrandTotalStrip(member: member),
      ],
    );
  }

  /// One line of the receipt. The sign lives in its own column so the labels
  /// and the amounts each stay on a straight edge.
  Widget _row(
    BuildContext context, {
    String? sign,
    required String label,
    required double value,
    String? note,
    bool credit = false,
    bool emphasis = false,
  }) {
    final Color valueColor =
        credit ? AppUi.accent(context, Colors.teal) : AppUi.body(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            child: Text(
              sign ?? '',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w900,
                color: credit
                    ? AppUi.accent(context, Colors.teal)
                    : AppUi.muted(context),
              ),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: emphasis ? 13.5 : 13,
                    fontWeight: emphasis ? FontWeight.bold : FontWeight.w500,
                    color: AppUi.body(context),
                  ),
                ),
                if (note != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    note,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: AppUi.muted(context),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            AppUi.amount(value),
            style: TextStyle(
              fontSize: emphasis ? 15 : 13.5,
              fontWeight: emphasis ? FontWeight.bold : FontWeight.w600,
              letterSpacing: -0.3,
              color: valueColor,
            ),
          ),
        ],
      ),
    );
  }

  /// Ruled under the charges, the way a bill is added up on paper — indented
  /// past the sign column so it lines up with the numbers it totals.
  Widget _rule(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 16, top: 4, bottom: 2),
        child: Divider(height: 1, color: AppUi.hairline(context)),
      );
}

/// The line that survives the subtraction.
class MemberGrandTotalStrip extends StatelessWidget {
  final MemberCostSummary member;
  final bool large;

  const MemberGrandTotalStrip({
    super.key,
    required this.member,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    // Someone who covered more than their share is owed money back; the strip
    // says which way it goes instead of printing a minus sign.
    final MaterialColor color = member.willGet ? Colors.teal : Colors.indigo;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: large ? 14 : 12),
      decoration: BoxDecoration(
        color: AppUi.tint(context, color),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(
            member.willGet
                ? Icons.trending_up_rounded
                : Icons.account_balance_wallet_outlined,
            size: large ? 18 : 16,
            color: AppUi.accent(context, color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              member.willGet ? 'will_get'.tr : 'grand_total'.tr,
              style: TextStyle(
                fontSize: large ? 12.5 : 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: AppUi.accent(context, color),
              ),
            ),
          ),
          Text(
            AppUi.amount(member.grandTotal.abs()),
            style: TextStyle(
              fontSize: large ? 22 : 18,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: AppUi.accent(context, color),
            ),
          ),
        ],
      ),
    );
  }
}
