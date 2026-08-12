import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/custom_app_bar.dart';
import '../../../utils/app_ui.dart';
import '../controller/month_details_controller.dart';
import '../controller/settings_controller.dart';
import '../model/month_cost_summary.dart';
import '../widgets/settings_skeletons.dart';
import 'monthly_bill_screen.dart';

/// Stable per-member accent, matching the members and bill screens.
const List<MaterialColor> _memberColors = [
  Colors.orange,
  Colors.purple,
  Colors.pink,
  Colors.blue,
  Colors.teal,
];

MaterialColor _colorFor(String name) =>
    _memberColors[name.hashCode.abs() % _memberColors.length];

String _initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty && RegExp(r'[\wঀ-৿]').hasMatch(p))
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
}

/// One month, member by member.
///
/// The screen exists to answer a single question at the end of a month — what
/// does each person owe — so both halves of the answer are on it: the house
/// bills for this month, and the meals from the month before, which is when
/// this house eats and how it settles.
class MonthDetailsScreen extends GetView<MonthDetailsController> {
  const MonthDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MonthDetailsController>(
      builder: (c) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: CustomAppBar(
            title: AppUi.monthLabel(c.month),
            actions: [
              // The one way into the bill form for a month that already exists.
              IconButton(
                tooltip: 'edit_bills'.tr,
                icon: const Icon(Icons.edit_outlined, size: 21),
                onPressed: () => _openBillForm(c),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Builder(
            builder: (_) {
              if (c.isLoading) {
                return const MonthDetailsSkeleton();
              }

              if (c.errorMessage.isNotEmpty || c.summary == null) {
                return _buildErrorState(context, c);
              }

              final MonthCostSummary summary = c.summary!;

              return RefreshIndicator(
                onRefresh: c.load,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                  children: [
                    _buildHeaderCard(context, summary),
                    const SizedBox(height: 14),
                    if (!summary.hasMealData) ...[
                      _buildNoMealNote(context, summary),
                      const SizedBox(height: 14),
                    ],
                    _buildRatesCard(context, summary),
                    const SizedBox(height: 22),
                    _buildSectionLabel(context, 'members_share'.tr),
                    const SizedBox(height: 12),
                    for (final MemberCostSummary member in summary.members)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildMemberCard(context, member, summary),
                      ),
                    const SizedBox(height: 6),
                    _buildCollectCard(context, summary),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _openBillForm(MonthDetailsController c) async {
    final SettingsController settings = Get.find<SettingsController>();
    settings.startBill(c.month);
    await Get.to(() => const MonthlyBillScreen());

    // Saved, edited or deleted — whichever it was, the figures here are stale
    // the moment that screen closes.
    await c.refreshBill(settings.billForMonth(c.month));
  }

  /// ------------------------------------------------------------------ header

  Widget _buildHeaderCard(BuildContext context, MonthCostSummary summary) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
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
                child: Icon(Icons.summarize_rounded, color: primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppUi.monthLabel(summary.month),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.3,
                        color: AppUi.body(context),
                      ),
                    ),
                    const SizedBox(height: 3),
                    // Which month each half of the number comes from, said
                    // once, at the top, so no figure below needs explaining.
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _sourceChip(
                          context,
                          Icons.receipt_long_rounded,
                          'bills_of_month'.trParams(
                              {'month': AppUi.monthLabel(summary.month)}),
                        ),
                        _sourceChip(
                          context,
                          Icons.restaurant_rounded,
                          'meals_of_month'.trParams(
                              {'month': AppUi.monthLabel(summary.mealMonth)}),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _heroStat(context, 'house_bills_total'.tr,
                  AppUi.amount(summary.billsTotal)),
              _heroDivider(context),
              _heroStat(context, 'meal_costs_total'.tr,
                  AppUi.amount(summary.mealsTotal)),
              _heroDivider(context),
              _heroStat(
                  context, 'to_collect'.tr, AppUi.amount(summary.grandTotal)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _sourceChip(BuildContext context, IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: AppUi.muted(context)),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: AppUi.muted(context),
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
              fontSize: 15.5,
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
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: AppUi.hairline(context),
      );

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

  /// ------------------------------------------------------------------- rates

  /// The three numbers every figure below is derived from. Shown because an
  /// admin is asked "why is my meal cost that much?" far more often than
  /// "what is my meal cost?".
  Widget _buildRatesCard(BuildContext context, MonthCostSummary summary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Column(
        children: [
          _rateRow(
            context,
            icon: Icons.restaurant_rounded,
            color: Colors.deepOrange,
            label: 'meal_rate'.tr,
            value: 'per_meal_rate'
                .trParams({'amount': AppUi.amount(summary.mealRate)}),
            note: 'meals_count'.trParams({'count': '${summary.totalMeals}'}),
          ),
          const SizedBox(height: 12),
          _rateRow(
            context,
            icon: Icons.shopping_basket_outlined,
            color: Colors.teal,
            label: 'other_rate'.tr,
            value: AppUi.amount(summary.otherRate),
            note: 'per_member'.tr,
          ),
          const SizedBox(height: 12),
          _rateRow(
            context,
            icon: Icons.home_rounded,
            color: Colors.indigo,
            label: 'shared_bills'.tr,
            value: AppUi.amount(summary.bill?.perHeadShared ?? 0),
            note: 'per_member'.tr,
          ),
        ],
      ),
    );
  }

  Widget _rateRow(
    BuildContext context, {
    required IconData icon,
    required MaterialColor color,
    required String label,
    required String value,
    required String note,
  }) {
    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppUi.tint(context, color),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, size: 17, color: AppUi.accent(context, color)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: AppUi.body(context),
            ),
          ),
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.3,
                color: AppUi.body(context),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              note,
              style: TextStyle(fontSize: 10.5, color: AppUi.muted(context)),
            ),
          ],
        ),
      ],
    );
  }

  /// ------------------------------------------------------------ member card

  /// The member's month as a receipt: what is charged, what they already
  /// covered, and the one line that survives the subtraction. Reading it top
  /// to bottom is the conversation an admin has when someone asks "why this
  /// much?", so every figure that goes into the answer is on the card.
  Widget _buildMemberCard(
    BuildContext context,
    MemberCostSummary member,
    MonthCostSummary summary,
  ) {
    final MaterialColor color = _colorFor(member.name);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppUi.tint(context, color),
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: color.withOpacity(0.35), width: 1.5),
                ),
                child: Text(
                  _initialsOf(member.name),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppUi.accent(context, color),
                  ),
                ),
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
                            member.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: AppUi.body(context),
                            ),
                          ),
                        ),
                        if (member.isMe) ...[
                          const SizedBox(width: 6),
                          _badge(context, 'you'.tr, Colors.teal),
                        ],
                        if (!member.inBills) ...[
                          const SizedBox(width: 6),
                          _badge(context, 'meals_only'.tr, Colors.blueGrey),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'meals_count'.trParams({'count': '${member.mealCount}'}),
                      style:
                          TextStyle(fontSize: 11.5, color: AppUi.muted(context)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(height: 1, color: AppUi.hairline(context)),
          const SizedBox(height: 6),

          // Charged ------------------------------------------------------
          _ledgerRow(
            context,
            sign: '+',
            label: 'house_bills'.tr,
            note: 'rent_plus_shared'.trParams({
              'rent': AppUi.amount(member.rent),
              'shared': AppUi.amount(member.sharedBills),
            }),
            value: member.houseBills,
          ),
          _ledgerRow(
            context,
            sign: '+',
            label: 'meal_cost'.tr,
            note: member.mealCount == 0
                ? null
                : 'meals_times_rate'.trParams({
                    'count': '${member.mealCount}',
                    'rate': AppUi.amount(summary.mealRate),
                  }),
            value: member.mealCost,
          ),
          _ledgerRow(
            context,
            sign: '+',
            label: 'other_cost'.tr,
            value: member.otherCost,
          ),

          _ledgerRule(context),
          _ledgerRow(
            context,
            label: 'subtotal'.tr,
            value: member.subtotal,
            emphasis: true,
          ),

          // Paid ---------------------------------------------------------
          const SizedBox(height: 4),
          _ledgerRow(
            context,
            sign: '−',
            label: 'meal_paid'.tr,
            value: member.mealPaid,
            credit: true,
          ),
          _ledgerRow(
            context,
            sign: '−',
            label: 'other_paid'.tr,
            value: member.otherPaid,
            credit: true,
          ),
          const SizedBox(height: 10),
          _grandTotalStrip(context, member),
        ],
      ),
    );
  }

  /// One line of the receipt. The sign lives in its own column so the labels
  /// and the amounts each stay on a straight edge.
  Widget _ledgerRow(
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
  Widget _ledgerRule(BuildContext context) => Padding(
        padding: const EdgeInsets.only(left: 16, top: 4, bottom: 2),
        child: Divider(height: 1, color: AppUi.hairline(context)),
      );

  Widget _grandTotalStrip(BuildContext context, MemberCostSummary member) {
    // Someone who covered more than their share is owed money back; the strip
    // says which way it goes instead of printing a minus sign.
    final MaterialColor color = member.willGet ? Colors.teal : Colors.indigo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
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
            size: 16,
            color: AppUi.accent(context, color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              member.willGet ? 'will_get'.tr : 'grand_total'.tr,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.6,
                color: AppUi.accent(context, color),
              ),
            ),
          ),
          Text(
            AppUi.amount(member.grandTotal.abs()),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: AppUi.accent(context, color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _badge(BuildContext context, String label, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: AppUi.tint(context, color),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.5,
          color: AppUi.accent(context, color),
        ),
      ),
    );
  }

  /// ----------------------------------------------------------------- footer

  Widget _buildCollectCard(BuildContext context, MonthCostSummary summary) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppUi.tint(context, primary),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // The same subtraction the member cards do, at house level.
          _footerRow(context, 'subtotal'.tr, AppUi.amount(summary.subtotal)),
          const SizedBox(height: 6),
          _footerRow(context, 'total_paid'.tr,
              '− ${AppUi.amount(summary.paidTotal)}',
              credit: true),
          const SizedBox(height: 8),
          Divider(height: 1, color: AppUi.hairline(context)),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'to_collect'.tr,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context),
                  ),
                ),
              ),
              Text(
                AppUi.amount(summary.grandTotal),
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: AppUi.body(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'meal_month_note'
                .trParams({'month': AppUi.monthLabel(summary.mealMonth)}),
            style: TextStyle(
              fontSize: 11,
              height: 1.4,
              color: AppUi.muted(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footerRow(
    BuildContext context,
    String label,
    String value, {
    bool credit = false,
  }) {
    final Color color =
        credit ? AppUi.accent(context, Colors.teal) : AppUi.muted(context);

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: AppUi.muted(context),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildNoMealNote(BuildContext context, MonthCostSummary summary) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppUi.tint(context, Colors.orange),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded,
              size: 17, color: AppUi.accent(context, Colors.orange)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'no_meal_data'
                  .trParams({'month': AppUi.monthLabel(summary.mealMonth)}),
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: AppUi.accent(context, Colors.orange),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ------------------------------------------------------------------ error

  Widget _buildErrorState(BuildContext context, MonthDetailsController c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(26),
              decoration: BoxDecoration(
                color: AppUi.tint(context, Colors.red),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded,
                  size: 44, color: AppUi.accent(context, Colors.red)),
            ),
            const SizedBox(height: 22),
            Text(
              'failed_load_details'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppUi.body(context).withOpacity(0.75),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'check_connection'.tr,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppUi.muted(context),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: c.load,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: Text('retry'.tr),
            ),
          ],
        ),
      ),
    );
  }
}
