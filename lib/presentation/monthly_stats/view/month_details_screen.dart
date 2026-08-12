import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/custom_app_bar.dart';
import '../../../utils/app_ui.dart';
import '../controller/month_details_controller.dart';
import '../controller/monthly_stats_controller.dart';
import '../model/month_cost_summary.dart';
import '../widgets/member_cost_ledger.dart';
import '../widgets/my_month_card.dart';
import '../widgets/monthly_stats_skeletons.dart';
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
              // The one way into the bill form for a month that already
              // exists — and only for someone who may change it.
              if (c.isAdminUser)
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
                onRefresh: c.refreshDetails,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 36),
                  children: [
                    // A member opens this screen to check their own figure,
                    // so it leads — the house's totals are the admin's view.
                    if (!c.isAdminUser && c.myCost != null)
                      MyMonthCard(
                        member: c.myCost!,
                        summary: summary,
                        onMoreInfo: () => showMyBreakdownSheet(
                            context, c.myCost!, summary),
                      )
                    else
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
                        child: _buildMemberCard(context, c, member, summary),
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
    final MonthlyStatsController stats = Get.find<MonthlyStatsController>();
    stats.startBill(c.month);
    await Get.to(() => const MonthlyBillScreen());

    // Saved, edited or deleted — whichever it was, the figures here are stale
    // the moment that screen closes.
    await c.refreshBill(stats.billForMonth(c.month));
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
    MonthDetailsController c,
    MemberCostSummary member,
    MonthCostSummary summary,
  ) {
    final MaterialColor color = _colorFor(member.name);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        // A collected member is edged in green: the state is visible while
        // scrolling past, without reading a single number.
        border: Border.all(
          color: member.settled
              ? Colors.green.withOpacity(AppUi.isDark(context) ? 0.45 : 0.35)
              : AppUi.hairline(context),
        ),
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
          MemberCostLedger(
            member: member,
            mealRate: summary.mealRate,
            // How the rent is divided is the admin's business, and each
            // member's own. It is not everyone's.
            showRentSplit: c.isAdminUser || member.isMe,
          ),
          const SizedBox(height: 10),
          _buildCollectAction(context, c, member),
        ],
      ),
    );
  }

  /// The admin's tick-off: one tap says the money is in hand, and the same
  /// row takes it back, because miscounting cash is ordinary.
  Widget _buildCollectAction(
    BuildContext context,
    MonthDetailsController c,
    MemberCostSummary member,
  ) {
    final bool busy = c.settlingPhone == member.phone;
    final VoidCallback? onTap = c.settlingPhone == null
        ? () => c.toggleSettled(member)
        : null;

    // A member reads the state; they do not get to change it. Pending is
    // still worth saying out loud — it is what they owe.
    if (!c.isAdminUser) {
      final MaterialColor color = member.settled ? Colors.green : Colors.orange;

      return Row(
        children: [
          Icon(
            member.settled
                ? Icons.verified_rounded
                : Icons.pending_outlined,
            size: 16,
            color: AppUi.accent(context, color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              member.settled
                  ? 'collected_amount'
                      .trParams({'amount': AppUi.amount(member.settledAmount)})
                  : 'not_collected_yet'.tr,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppUi.accent(context, color),
              ),
            ),
          ),
        ],
      );
    }

    if (member.settled) {
      return Row(
        children: [
          Icon(Icons.verified_rounded,
              size: 17, color: AppUi.accent(context, Colors.green)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'collected_amount'
                      .trParams({'amount': AppUi.amount(member.settledAmount)}),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: AppUi.accent(context, Colors.green),
                  ),
                ),
                if (member.settledBy.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    'collected_by'.trParams({'name': member.settledBy}),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 10.5, color: AppUi.muted(context)),
                  ),
                ],
              ],
            ),
          ),
          if (busy)
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            TextButton(
              onPressed: onTap,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
                foregroundColor: AppUi.muted(context),
              ),
              child: Text(
                'undo'.tr,
                style: const TextStyle(
                    fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
            ),
        ],
      );
    }

    return SizedBox(
      width: double.infinity,
      height: 42,
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: busy
            ? const SizedBox(
                width: 15,
                height: 15,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.check_circle_outline_rounded, size: 18),
        label: Text(
          'mark_collected'.tr,
          style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppUi.accent(context, Colors.green),
          side: BorderSide(
            color: Colors.green.withOpacity(AppUi.isDark(context) ? 0.5 : 0.35),
          ),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        ),
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
          const SizedBox(height: 10),
          // How far along the collection is, in the same card as the number
          // being collected.
          Row(
            children: [
              Icon(
                summary.isFullySettled
                    ? Icons.verified_rounded
                    : Icons.pending_outlined,
                size: 14,
                color: AppUi.accent(
                    context, summary.isFullySettled ? Colors.green : Colors.orange),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  summary.isFullySettled
                      ? 'all_collected'.tr
                      : 'collected_progress'.trParams({
                          'done': '${summary.settledCount}',
                          'total': '${summary.members.length}',
                        }),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppUi.accent(context,
                        summary.isFullySettled ? Colors.green : Colors.orange),
                  ),
                ),
              ),
              if (summary.collectedTotal > 0)
                Text(
                  AppUi.amount(summary.collectedTotal),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: AppUi.accent(context, Colors.green),
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
