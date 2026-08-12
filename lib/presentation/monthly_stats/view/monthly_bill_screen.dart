import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../utils/app_ui.dart';
import '../controller/monthly_stats_controller.dart';
import '../model/monthly_bill_model.dart';
import '../widgets/bill_amount_field.dart';
import '../widgets/month_picker_sheet.dart';
import '../widgets/monthly_stats_skeletons.dart';

/// Stable per-member accent, matching the members screen so the same person
/// keeps the same color everywhere.
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

/// One month's house bills.
///
/// The form is ordered the way the money is: the rent first, because it is the
/// only bill that has to be argued over per member, then the costs that simply
/// divide, and finally what each person ends up owing. Every total is derived
/// from the fields as they are typed — nothing waits for a save to add up.
class MonthlyBillScreen extends GetView<MonthlyStatsController> {
  const MonthlyBillScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<MonthlyStatsController>(
      builder: (c) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: CustomAppBar(
            title: AppUi.monthLabel(c.formMonth),
            actions: [_buildMenu(context, c)],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              _buildMonthBanner(context, c),
              if (c.editingBill == null && c.templateBill != null) ...[
                const SizedBox(height: 12),
                _buildTemplateCard(context, c),
              ],
              const SizedBox(height: 18),
              _buildRentSection(context, c),
              const SizedBox(height: 14),
              _buildUtilitiesSection(context, c),
              const SizedBox(height: 14),
              _buildWifiSection(context, c),
              const SizedBox(height: 14),
              _buildOthersSection(context, c),
            ],
          ),
          bottomNavigationBar: _buildSaveBar(context, c),
        );
      },
    );
  }

  /// ------------------------------------------------------------------- menu

  Widget _buildMenu(BuildContext context, MonthlyStatsController c) {
    final MonthlyBillModel? saved = c.editingBill;

    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        if (value == 'copy') {
          c.applyTemplate();
        } else if (value == 'delete' && saved != null) {
          _confirmDelete(context, c, saved);
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'copy',
          enabled: c.templateBill != null,
          child: Row(
            children: [
              Icon(Icons.copy_all_rounded, size: 19, color: AppUi.muted(context)),
              const SizedBox(width: 12),
              Text('copy_previous_month'.tr),
            ],
          ),
        ),
        if (saved != null)
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline_rounded,
                    size: 19, color: Colors.red.shade400),
                const SizedBox(width: 12),
                Text(
                  'delete_month_bills'.tr,
                  style: TextStyle(color: Colors.red.shade400),
                ),
              ],
            ),
          ),
      ],
    );
  }

  void _confirmDelete(
    BuildContext context,
    MonthlyStatsController c,
    MonthlyBillModel bill,
  ) {
    showConfirmDialog(
      title: 'delete_month_bills'.tr,
      message: 'confirm_delete_month'
          .trParams({'month': AppUi.monthLabel(bill.monthDate)}),
      detail: 'delete_month_note'.tr,
      confirmText: 'delete'.tr,
      onConfirm: () async {
        final bool deleted = await c.deleteBill(bill);
        if (deleted && context.mounted) {
          Navigator.of(context).maybePop();
        }
      },
    );
  }

  /// ----------------------------------------------------------- month banner

  Widget _buildMonthBanner(BuildContext context, MonthlyStatsController c) {
    final MonthlyBillModel? saved = c.editingBill;
    final Color primary = Theme.of(context).colorScheme.primary;

    final String status = saved == null
        ? 'new_setup'.tr
        : (saved.updatedBy.isEmpty
            ? 'bill_saved_status'.tr
            : 'updated_by'.trParams({'name': saved.updatedBy}));

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppUi.neutralSurface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppUi.tint(context, primary),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(Icons.event_note_rounded, size: 19, color: primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppUi.monthLabel(c.formMonth),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11.5, color: AppUi.muted(context)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => showMonthPickerSheet(
              context,
              c,
              selected: c.formMonth,
              onSelected: c.setFormMonth,
            ),
            child: Text('change'.tr),
          ),
        ],
      ),
    );
  }

  /// ---------------------------------------------------------- template card

  /// Next month is nearly always last month with a couple of numbers moved, so
  /// the shortcut is offered before the empty form, not buried in a menu.
  Widget _buildTemplateCard(BuildContext context, MonthlyStatsController c) {
    final MonthlyBillModel source = c.templateBill!;
    final Color primary = Theme.of(context).colorScheme.primary;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppUi.tint(context, primary),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: primary.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.auto_awesome_rounded, size: 20, color: primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'use_previous_month'
                      .trParams({'month': AppUi.monthLabel(source.monthDate)}),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  'use_previous_month_hint'.tr,
                  style: TextStyle(
                    fontSize: 11.5,
                    height: 1.4,
                    color: AppUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: c.applyTemplate,
            style: TextButton.styleFrom(
              backgroundColor: Theme.of(context).cardColor,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(
              'apply'.tr,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }

  /// ------------------------------------------------------------------- rent

  Widget _buildRentSection(BuildContext context, MonthlyStatsController c) {
    return _section(
      context,
      icon: Icons.home_rounded,
      color: Colors.indigo,
      title: 'home_rent'.tr,
      subtitle: 'home_rent_hint'.tr,
      children: [
        BillAmountField(
          controller: c.homeRentController,
          hero: true,
          errorText: c.homeRentError,
          onChanged: c.onAmountChanged,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(child: _buildRentBalance(context, c)),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: c.formShares.isEmpty ? null : c.splitRentEqually,
              icon: const Icon(Icons.calculate_outlined, size: 17),
              label: Text(
                'split_equally'.tr,
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: AppUi.hairline(context)),
        const SizedBox(height: 12),
        Text(
          'member_split'.tr.toUpperCase(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            color: AppUi.muted(context),
          ),
        ),
        const SizedBox(height: 10),
        if (c.formShares.isEmpty)
          _buildEmptySplit(context, c)
        else
          for (final RentShare share in c.formShares)
            _buildShareRow(context, c, share),
      ],
    );
  }

  /// The running answer to "does this add up?", in the place where the
  /// question comes up — so a mismatch is never discovered at save time.
  Widget _buildRentBalance(BuildContext context, MonthlyStatsController c) {
    final double remaining = c.formRentRemaining;

    late final MaterialColor color;
    late final IconData icon;
    late final String label;

    if (c.formHomeRent <= 0 && c.formAssignedRent <= 0) {
      color = Colors.blueGrey;
      icon = Icons.info_outline_rounded;
      label = 'rent_split_hint'.tr;
    } else if (c.isRentBalanced) {
      color = Colors.green;
      icon = Icons.check_circle_rounded;
      label = 'rent_balanced'.trParams({'amount': AppUi.amount(c.formHomeRent)});
    } else if (remaining > 0) {
      color = Colors.orange;
      icon = Icons.pending_outlined;
      label = 'rent_remaining'.trParams({'amount': AppUi.amount(remaining)});
    } else {
      color = Colors.red;
      icon = Icons.error_outline_rounded;
      label = 'rent_over'.trParams({'amount': AppUi.amount(remaining.abs())});
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppUi.tint(context, color),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppUi.accent(context, color)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: AppUi.accent(context, color),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What stands in for the split list when there is nobody in it — a state
  /// that always says which of the three it is, and offers the way out.
  Widget _buildEmptySplit(BuildContext context, MonthlyStatsController c) {
    if (c.isMembersLoading) return const MemberSplitSkeleton();

    final bool failed = c.membersError.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(
            failed ? Icons.cloud_off_rounded : Icons.person_off_outlined,
            size: 17,
            color: AppUi.muted(context),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              failed ? 'failed_load_members'.tr : 'no_members_to_split'.tr,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: AppUi.muted(context),
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => c.refreshMembers(syncForm: true),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: Text(
              'retry'.tr,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildShareRow(
    BuildContext context,
    MonthlyStatsController c,
    RentShare share,
  ) {
    final TextEditingController? field = c.rentControllers[share.phone];
    if (field == null) return const SizedBox.shrink();

    final MaterialColor color = _colorFor(share.name);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppUi.tint(context, color),
              shape: BoxShape.circle,
              border: Border.all(color: color.withOpacity(0.35), width: 1.5),
            ),
            child: Text(
              _initialsOf(share.name),
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: AppUi.accent(context, color),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  share.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppUi.body(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'pays_in_total'
                      .trParams({'amount': AppUi.amount(c.formTotalFor(share))}),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          BillAmountField(
            controller: field,
            onChanged: c.onAmountChanged,
            width: 112,
          ),
        ],
      ),
    );
  }

  /// -------------------------------------------------------------- utilities

  Widget _buildUtilitiesSection(BuildContext context, MonthlyStatsController c) {
    return _section(
      context,
      icon: Icons.bolt_rounded,
      color: Colors.amber,
      title: 'home_utilities'.tr,
      subtitle: 'split_equally_hint'.tr,
      children: [
        _amountRow(context, c,
            icon: Icons.water_drop_outlined,
            label: 'water_bill'.tr,
            controller: c.waterController),
        _amountRow(context, c,
            icon: Icons.shield_outlined,
            label: 'security_bill'.tr,
            controller: c.securityController),
        _amountRow(context, c,
            icon: Icons.electrical_services_rounded,
            label: 'electricity_bill'.tr,
            controller: c.electricityController),
        _amountRow(context, c,
            icon: Icons.cleaning_services_outlined,
            label: 'cleaning_bill'.tr,
            controller: c.cleaningController,
            isLast: true),
        const SizedBox(height: 12),
        Divider(height: 1, color: AppUi.hairline(context)),
        const SizedBox(height: 10),
        _totalRow(context, 'utilities_total'.tr,
            AppUi.amount(c.formUtilitiesTotal)),
      ],
    );
  }

  /// ------------------------------------------------------------------- wifi

  Widget _buildWifiSection(BuildContext context, MonthlyStatsController c) {
    return _section(
      context,
      icon: Icons.wifi_rounded,
      color: Colors.blue,
      title: 'wifi_bill'.tr,
      subtitle: 'split_equally_hint'.tr,
      children: [
        _amountRow(context, c,
            icon: Icons.router_outlined,
            label: 'monthly_wifi'.tr,
            controller: c.wifiController,
            isLast: true),
      ],
    );
  }

  /// ----------------------------------------------------------------- others

  Widget _buildOthersSection(BuildContext context, MonthlyStatsController c) {
    return _section(
      context,
      icon: Icons.category_outlined,
      color: Colors.teal,
      title: 'other_costs'.tr,
      subtitle: 'other_costs_hint'.tr,
      children: [
        _amountRow(context, c,
            icon: Icons.add_shopping_cart_rounded,
            label: 'amount'.tr,
            controller: c.otherController,
            isLast: true),
        const SizedBox(height: 12),
        CustomTextField(
          controller: c.otherNoteController,
          hintText: 'note_optional'.tr,
          prefixIcon: Icons.edit_note_rounded,
        ),
      ],
    );
  }

  /// --------------------------------------------------------------- save bar

  Widget _buildSaveBar(BuildContext context, MonthlyStatsController c) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: AppUi.hairline(context))),
        boxShadow: AppUi.softShadow(context),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'grand_total'.tr,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: AppUi.muted(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AppUi.amount(c.formGrandTotal),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                        color: AppUi.body(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 150,
                child: CustomButton(
                  text: c.editingBill == null ? 'save'.tr : 'update'.tr,
                  height: 50,
                  borderRadius: 14,
                  fontSize: 15,
                  isLoading: c.isSaving,
                  onPressed: () async {
                    final bool saved = await c.saveBill();
                    if (saved && context.mounted) {
                      Navigator.of(context).maybePop();
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ----------------------------------------------------------- shared parts

  Widget _section(
    BuildContext context, {
    required IconData icon,
    required MaterialColor color,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppUi.tint(context, color),
                  borderRadius: BorderRadius.circular(12),
                ),
                child:
                    Icon(icon, size: 19, color: AppUi.accent(context, color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: AppUi.body(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        height: 1.35,
                        color: AppUi.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  Widget _amountRow(
    BuildContext context,
    MonthlyStatsController c, {
    required IconData icon,
    required String label,
    required TextEditingController controller,
    bool isLast = false,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: AppUi.muted(context)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: AppUi.body(context),
              ),
            ),
          ),
          const SizedBox(width: 8),
          BillAmountField(
            controller: controller,
            onChanged: c.onAmountChanged,
            width: 120,
          ),
        ],
      ),
    );
  }

  Widget _totalRow(BuildContext context, String label, String value) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: AppUi.muted(context),
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.3,
            color: AppUi.body(context),
          ),
        ),
      ],
    );
  }
}
