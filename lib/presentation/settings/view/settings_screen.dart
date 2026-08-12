import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../utils/app_ui.dart';
import '../controller/month_details_controller.dart';
import '../controller/settings_controller.dart';
import '../model/monthly_bill_model.dart';
import '../widgets/month_picker_sheet.dart';
import '../widgets/settings_skeletons.dart';
import 'month_details_screen.dart';
import 'monthly_bill_screen.dart';

/// Admin-only house settings.
///
/// The screen answers one question first — is this month set up? — and keeps
/// every month that came before it a tap away, because next month's setup
/// almost always starts from the last one.
class SettingsScreen extends GetView<SettingsController> {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(
        title: 'settings'.tr,
        actions: [
          GetBuilder<SettingsController>(
            builder: (c) {
              if (!c.isAdminUser || c.isLoading) return const SizedBox(width: 16);
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: IconButton(
                  tooltip: 'add_month'.tr,
                  icon: const Icon(Icons.calendar_month_rounded, size: 22),
                  onPressed: () => _showMonthPicker(context, c),
                ),
              );
            },
          ),
        ],
      ),
      body: GetBuilder<SettingsController>(
        builder: (c) {
          // Loading first: the role is read from preferences on init, so a
          // check before that lands would flash the locked state at an admin.
          if (c.isLoading) {
            return const SettingsListSkeleton();
          }

          // The tile that leads here is admin-only; this is the second lock,
          // for a session whose role was revoked while it was open.
          if (!c.isAdminUser) return _buildLockedState(context);

          if (c.errorMessage.isNotEmpty) return _buildErrorState(context, c);

          return RefreshIndicator(
            onRefresh: c.loadSettings,
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
  Widget _buildCurrentMonthCard(BuildContext context, SettingsController c) {
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
          // Straight to the form: this card is where the month gets set up and
          // corrected. Reading the breakdown is the row below it.
          CustomButton(
            text: isSetUp
                ? 'edit_month'.trParams({'month': AppUi.monthLabel(month)})
                : 'set_up_month'.trParams({'month': AppUi.monthLabel(month)}),
            height: 48,
            borderRadius: 14,
            fontSize: 15,
            onPressed: () => _openBill(context, c, month),
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
    SettingsController c,
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
                    const SizedBox(height: 3),
                    Text(
                      'members_count'.trParams({'count': '${bill.memberCount}'}),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppUi.muted(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
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

  Widget _buildLockedState(BuildContext context) {
    return _centeredState(
      context,
      icon: Icons.lock_outline_rounded,
      color: Colors.orange,
      title: 'admin_only'.tr,
      hint: 'admin_only_hint'.tr,
    );
  }

  Widget _buildErrorState(BuildContext context, SettingsController c) {
    return _centeredState(
      context,
      icon: Icons.cloud_off_rounded,
      color: Colors.red,
      title: 'failed_load_bills'.tr,
      hint: 'check_connection'.tr,
      action: TextButton.icon(
        onPressed: c.loadSettings,
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
  /// nothing in it has nothing to break down, so it opens on the form.
  /// Editing an existing month is reached from the details app bar.
  void _openMonth(BuildContext context, SettingsController c, DateTime month) {
    final MonthlyBillModel? bill = c.billForMonth(month);
    if (bill == null || bill.isEmpty) {
      _openBill(context, c, month);
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

  void _openBill(BuildContext context, SettingsController c, DateTime month) {
    c.startBill(month);
    Get.to(() => const MonthlyBillScreen());
  }

  /// Month picker for setting up a month other than this one — the month
  /// ahead, or one that was missed.
  void _showMonthPicker(BuildContext context, SettingsController c) {
    showMonthPickerSheet(
      context,
      c,
      onSelected: (month) => _openMonth(context, c, month),
    );
  }
}
