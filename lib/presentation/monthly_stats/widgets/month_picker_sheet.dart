import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../utils/app_ui.dart';
import '../controller/monthly_stats_controller.dart';
import '../model/monthly_bill_model.dart';

/// The month list behind both "add a month" and "change month".
///
/// Every row says whether that month is already set up and what it came to, so
/// the choice is made in the sheet rather than by opening months one by one.
void showMonthPickerSheet(
  BuildContext context,
  MonthlyStatsController controller, {
  required ValueChanged<DateTime> onSelected,
  DateTime? selected,
}) {
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
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'select_month'.tr,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context),
                  ),
                ),
              ),
            ),
            Divider(height: 1, color: AppUi.hairline(context)),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: [
                  for (final DateTime month in controller.selectableMonths)
                    _MonthRow(
                      month: month,
                      bill: controller.billForMonth(month),
                      isSelected: selected != null &&
                          selected.year == month.year &&
                          selected.month == month.month,
                      onTap: () {
                        closeOverlayRoute();
                        onSelected(month);
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 10),
          ],
        ),
      ),
    ),
    isScrollControlled: true,
  );
}

class _MonthRow extends StatelessWidget {
  final DateTime month;
  final MonthlyBillModel? bill;
  final bool isSelected;
  final VoidCallback onTap;

  const _MonthRow({
    required this.month,
    required this.bill,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool isSetUp = bill != null && !bill!.isEmpty;

    return Material(
      color: isSelected ? AppUi.tint(context, primary) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
          child: Row(
            children: [
              Icon(
                isSetUp
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                size: 20,
                color: isSetUp
                    ? AppUi.accent(context, Colors.green)
                    : AppUi.muted(context),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  AppUi.monthLabel(month),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected ? primary : AppUi.body(context),
                  ),
                ),
              ),
              Text(
                isSetUp ? AppUi.amount(bill!.grandTotal) : 'not_set_up'.tr,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: isSetUp ? AppUi.body(context) : AppUi.muted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
