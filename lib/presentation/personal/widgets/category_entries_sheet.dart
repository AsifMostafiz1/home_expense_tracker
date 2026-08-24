import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/personal_category.dart';
import '../model/personal_summary.dart';
import '../model/personal_transaction.dart';

/// What is behind one bar of the month's breakdown.
///
/// "Food, ৳805, 94%" is the answer to "what am I spending on"; the question
/// straight after it is always "on what, though" — and scrolling the month's
/// whole list hunting for the food rows is a poor way to be told. So the bar
/// opens onto its own rows, grouped by day like every other list in the app.
///
/// Read-only on purpose, and drawn without tap targets so it does not pretend
/// otherwise: this is a magnifying glass held over the month, and the entries
/// themselves are edited in the list it came from.
Future<void> showCategoryEntriesSheet(
  BuildContext context, {
  required String category,
  required bool income,
}) {
  return Get.bottomSheet(
    _CategoryEntriesSheet(category: category, income: income),
    isScrollControlled: true,
  );
}

class _CategoryEntriesSheet extends StatelessWidget {
  final String category;
  final bool income;

  const _CategoryEntriesSheet({required this.category, required this.income});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<PersonalController>(
      builder: (c) {
        final PersonalCategory bucket = PersonalCategory.of(category);

        final List<PersonalTransaction> rows = c.monthTransactions
            .where((entry) => entry.isIncome == income)
            .where((entry) => _keyOf(entry) == category)
            .toList();

        final double total =
            rows.fold<double>(0, (sum, entry) => sum + entry.amount);
        final double side = income ? c.monthMoney.income : c.monthMoney.expense;
        final List<MoneyDay> days = MoneyDay.group(rows);

        return Container(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 44,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: AppUi.muted(context).withOpacity(0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                _buildHeader(context, c, bucket, rows.length, total, side),
                const SizedBox(height: 6),
                // Bounded, not free: a category with forty rows in it should
                // scroll inside the sheet rather than push it off the screen.
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.only(top: 10, bottom: 12),
                    children: [
                      for (final MoneyDay day in days) ...[
                        _buildDay(context, day, bucket),
                        const SizedBox(height: 14),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// An entry saved before a category was picked has none; it is shown under
  /// the same bucket the breakdown counted it in.
  String _keyOf(PersonalTransaction entry) =>
      entry.category.isEmpty ? PersonalCategory.unknown.key : entry.category;

  Widget _buildHeader(
    BuildContext context,
    PersonalController c,
    PersonalCategory bucket,
    int count,
    double total,
    double side,
  ) {
    final int percent = side <= 0 ? 0 : ((total / side) * 100).round();

    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppUi.tint(context, bucket.color),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(bucket.icon,
              size: 21, color: AppUi.accent(context, bucket.color)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                bucket.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: AppUi.body(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${AppUi.monthLabel(c.selectedMonth)} · '
                '${'entries_count'.trParams({'count': '$count'})}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11.5, color: AppUi.muted(context)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '${income ? '+' : '−'}${AppUi.amount(total)}',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: AppUi.accent(
                    context, income ? Colors.green : Colors.deepOrange),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              '$percent%',
              style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
            ),
          ],
        ),
      ],
    );
  }

  /// One day, headed the way the month's own list heads its days.
  Widget _buildDay(BuildContext context, MoneyDay day, PersonalCategory bucket) {
    final double dayTotal = day.entries
        .fold<double>(0, (sum, entry) => sum + entry.amount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              AppUi.dayLabel(day.date),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: AppUi.muted(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Divider(color: AppUi.hairline(context), height: 1)),
            const SizedBox(width: 10),
            Text(
              '${income ? '+' : '−'}${AppUi.amount(dayTotal)}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: AppUi.body(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        for (final PersonalTransaction entry in day.entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _buildRow(context, entry, bucket),
          ),
      ],
    );
  }

  Widget _buildRow(
    BuildContext context,
    PersonalTransaction entry,
    PersonalCategory bucket,
  ) {
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          margin: const EdgeInsets.only(right: 11),
          decoration: BoxDecoration(
            color: AppUi.accent(context, bucket.color),
            shape: BoxShape.circle,
          ),
        ),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                entry.note.isEmpty ? bucket.label : entry.note,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppUi.body(context),
                ),
              ),
              const SizedBox(height: 1),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      entry.time.format(context),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11, color: AppUi.muted(context)),
                    ),
                  ),
                  if (entry.isFromHouse) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.home_rounded,
                        size: 11, color: AppUi.muted(context)),
                  ],
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          AppUi.amount(entry.amount),
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.bold,
            color: AppUi.body(context),
          ),
        ),
      ],
    );
  }
}
