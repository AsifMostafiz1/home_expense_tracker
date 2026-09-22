import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import '../model/month_cost_summary.dart';
import '../model/monthly_bill_model.dart';

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

  /// Whether to say in words what the shared half covers. Worth a line where
  /// the ledger is read on its own; noise in a list of many members.
  final bool showSharedHint;

  /// What the flat other cost was made of. Null or empty leaves the line
  /// bare, as it always was.
  final OtherCostBreakdown? otherBreakdown;

  /// The month's bill, read by the shared hint to name what the shared half
  /// was actually made of. Without it the hint falls back to the general
  /// sentence.
  final MonthlyBillModel? bill;

  /// How many items a line names before the rest become a count.
  static const int _itemsShown = 4;

  const MemberCostLedger({
    super.key,
    required this.member,
    required this.mealRate,
    this.showRentSplit = true,
    this.showSharedHint = false,
    this.otherBreakdown,
    this.bill,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      // The rows fill the width on their own; anything narrower — the hint —
      // would otherwise be centred by the column's default.
      crossAxisAlignment: CrossAxisAlignment.start,
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
        if (showSharedHint) _sharedHint(context),
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
          note: _otherSplit(),
          detail: _itemsLine(context, otherBreakdown?.items ?? const []),
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
          detail: _itemsLine(context, member.otherPaidItems, credit: true),
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
    Widget? detail,
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
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  detail,
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

  /// The house total and the heads it was split between — the sum behind
  /// the flat figure, the way the meal line shows its multiplication.
  String? _otherSplit() {
    final OtherCostBreakdown? breakdown = otherBreakdown;
    if (breakdown == null || breakdown.isEmpty || breakdown.headCount == 0) {
      return null;
    }
    return 'total_split_members'.trParams({
      'total': AppUi.amount(breakdown.total),
      'count': '${breakdown.headCount}',
    });
  }

  /// A list of items, largest first; past a handful they are counted
  /// rather than named, so the line stays a summary. Null when empty.
  Widget? _itemsLine(
    BuildContext context,
    List<OtherCostItem> items, {
    bool credit = false,
  }) {
    if (items.isEmpty) return null;

    final int rest = items.length - _itemsShown;
    return _itemsText(
      context,
      [
        for (final OtherCostItem item in items.take(_itemsShown))
          (
            item.name.isEmpty ? 'untitled_item'.tr : item.name,
            item.amount,
          ),
      ],
      credit: credit,
      trailing: rest > 0 ? 'and_more_rows'.trParams({'count': '$rest'}) : null,
      maxLines: 2,
    );
  }

  /// Names what the shared half covers, so the figure is not a bare number
  /// someone has to ask about — this month's own bills, item by item, each
  /// at the one member's share of it.
  Widget _sharedHint(BuildContext context) {
    final List<(String, double)> items = _sharedItems();
    final TextStyle muted = TextStyle(
      fontSize: 10.5,
      height: 1.35,
      color: AppUi.muted(context),
    );

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 8, bottom: 4),
      child: items.isEmpty
          ? Text('shared_bills_include'.tr, style: muted)
          : _itemsText(
              context,
              items,
              leading: 'shared_bills_include_prefix'.tr,
              amountFirst: true,
            ),
    );
  }

  /// The bill's shared lines that carry an amount, in the order the bill
  /// form asks for them, each divided down to one member's share. The
  /// free-form cost goes by its note when it has one.
  List<(String, double)> _sharedItems() {
    final MonthlyBillModel? month = bill;
    if (month == null || month.sharedTotal <= 0 || month.memberCount == 0) {
      return const [];
    }

    final String otherLabel = month.otherNote.trim().isEmpty
        ? 'other_costs'.tr
        : month.otherNote.trim();
    final List<(String, double)> lines = [
      ('water_bill'.tr, month.waterBill),
      ('security_bill'.tr, month.securityBill),
      ('electricity_bill'.tr, month.electricityBill),
      ('cleaning_bill'.tr, month.cleaningBill),
      ('wifi_bill'.tr, month.wifiBill),
      (otherLabel, month.otherCost),
    ];

    return [
      for (final (String label, double amount) in lines)
        if (amount > 0) (label, amount / month.memberCount),
    ];
  }

  /// Items as one flowing line, the amounts picked out in colour so each
  /// figure can be found at a glance among the muted names — teal on the
  /// paid side, as the row's own figure is.
  Widget _itemsText(
    BuildContext context,
    List<(String, double)> items, {
    String? leading,
    String? trailing,
    bool amountFirst = false,
    bool credit = false,
    int? maxLines,
  }) {
    final TextStyle muted = TextStyle(
      fontSize: 10.5,
      height: 1.35,
      color: AppUi.muted(context),
    );
    final TextStyle figure = muted.copyWith(
      fontWeight: FontWeight.w700,
      color: AppUi.accent(context, credit ? Colors.teal : Colors.indigo),
    );

    final List<InlineSpan> spans = [
      if (leading != null) TextSpan(text: '$leading '),
    ];
    for (int i = 0; i < items.length; i++) {
      final (String label, double amount) = items[i];
      if (i > 0) spans.add(const TextSpan(text: ' · '));
      final TextSpan value =
          TextSpan(text: AppUi.amount(amount), style: figure);
      spans.addAll(amountFirst
          ? [value, TextSpan(text: ' $label')]
          : [TextSpan(text: '$label '), value]);
    }
    if (trailing != null) spans.add(TextSpan(text: ' · $trailing'));

    return Text.rich(
      TextSpan(style: muted, children: spans),
      maxLines: maxLines,
      overflow: maxLines == null ? null : TextOverflow.ellipsis,
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
