import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/debt_entry.dart';
import '../widgets/debt_entry_sheet.dart';

/// One person's account: every rupee that has passed between the two of them,
/// and what it comes to.
///
/// The person is looked up by key on every build rather than passed in whole,
/// so the screen follows the live list — an entry added from here changes the
/// balance above it at once, and an account emptied of rows closes itself.
class PersonLedgerScreen extends StatelessWidget {
  final String personKey;

  const PersonLedgerScreen({super.key, required this.personKey});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<PersonalController>(
      builder: (c) {
        final PersonBalance? person = c.personFor(personKey);

        // Every row deleted — there is no account left to look at.
        if (person == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Get.currentRoute.contains('PersonLedgerScreen')) Get.back();
          });
          return const SizedBox.shrink();
        }

        final Map<String, double> balances = person.runningBalances;

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: CustomAppBar(
            title: person.name.isEmpty ? 'unknown'.tr : person.name,
            actions: [_buildMenu(context, c, person)],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              _buildBalanceCard(context, person),
              const SizedBox(height: 20),
              Text(
                'history'.tr.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: AppUi.muted(context),
                ),
              ),
              const SizedBox(height: 12),
              if (person.isEmpty)
                _buildEmptyHistory(context)
              else
                for (final DebtEntry entry in person.entries) ...[
                  _buildEntryTile(
                    context,
                    c,
                    entry,
                    balanceAfter: balances[entry.id] ?? 0,
                  ),
                  const SizedBox(height: 10),
                ],
            ],
          ),
          bottomNavigationBar: _buildActionBar(context, person),
        );
      },
    );
  }

  /// An account opened from the dues screen and not yet written into — the
  /// buttons that fill it are already at the bottom of this screen, so this
  /// only has to point at them.
  Widget _buildEmptyHistory(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 22),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Text(
        'no_entries_for_person'.tr,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 12.5,
          height: 1.5,
          color: AppUi.muted(context),
        ),
      ),
    );
  }

  Widget _buildMenu(
    BuildContext context,
    PersonalController c,
    PersonBalance person,
  ) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert_rounded, size: 22),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        if (value == 'call') {
          launchUrl(Uri(scheme: 'tel', path: person.phone));
        } else if (value == 'delete') {
          showConfirmDialog(
            title: 'delete_person_ledger'.tr,
            message: 'confirm_delete_person_ledger'.tr,
            detail: '${person.name} · ${person.entries.length}',
            confirmText: 'delete'.tr,
            onConfirm: () => c.deletePerson(person),
          );
        }
      },
      itemBuilder: (_) => [
        if (person.phone.isNotEmpty)
          PopupMenuItem<String>(
            value: 'call',
            child: Row(
              children: [
                Icon(Icons.call_rounded, size: 19, color: AppUi.muted(context)),
                const SizedBox(width: 12),
                Text('call'.tr),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded,
                  size: 19, color: Colors.red.shade400),
              const SizedBox(width: 12),
              Text('delete_person_ledger'.tr,
                  style: TextStyle(color: Colors.red.shade400)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBalanceCard(BuildContext context, PersonBalance person) {
    final MaterialColor tone = person.isSettled
        ? Colors.blueGrey
        : (person.owesMe ? Colors.green : Colors.deepOrange);
    final String label = person.isSettled
        ? 'all_settled'.tr
        : (person.owesMe ? 'owes_you'.tr : 'you_owe'.tr);

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        color: AppUi.tint(context, tone),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: tone.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11.5, color: AppUi.muted(context)),
          ),
          const SizedBox(height: 4),
          Text(
            AppUi.amount(person.balance.abs()),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
              color: AppUi.accent(context, tone),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _stat(context, 'total_i_gave'.tr, person.totalGave, Colors.green),
              Container(
                width: 1,
                height: 30,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppUi.hairline(context),
              ),
              _stat(context, 'total_i_got'.tr, person.totalGot,
                  Colors.deepOrange),
            ],
          ),
          if (person.phone.isNotEmpty) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.phone_outlined, size: 13, color: AppUi.muted(context)),
                const SizedBox(width: 6),
                Text(
                  person.phone,
                  style: TextStyle(fontSize: 12, color: AppUi.muted(context)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(
    BuildContext context,
    String label,
    double value,
    MaterialColor color,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
          ),
          const SizedBox(height: 3),
          Text(
            AppUi.amount(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppUi.accent(context, color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryTile(
    BuildContext context,
    PersonalController c,
    DebtEntry entry, {
    required double balanceAfter,
  }) {
    final MaterialColor tone = entry.isGave ? Colors.green : Colors.deepOrange;

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showDebtEntrySheet(context, entry: entry),
        onLongPress: () => showConfirmDialog(
          title: 'delete_entry'.tr,
          message: 'confirm_delete_entry'.tr,
          detail: '${AppUi.amount(entry.amount)} · '
              '${DateFormat('dd MMM, yyyy').format(entry.day)}',
          confirmText: 'delete'.tr,
          onConfirm: () => c.deleteDebtEntry(entry),
        ),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppUi.hairline(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppUi.tint(context, tone),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  entry.isGave ? Icons.add_rounded : Icons.remove_rounded,
                  size: 17,
                  color: AppUi.accent(context, tone),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.note.isEmpty
                          ? (entry.isGave ? 'due_will_get'.tr : 'due_will_pay'.tr)
                          : entry.note,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: AppUi.body(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '${DateFormat('dd MMM, yyyy').format(entry.day)}'
                          ' · ${entry.time.format(context)}',
                          style: TextStyle(
                              fontSize: 11, color: AppUi.muted(context)),
                        ),
                        if (entry.pending) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.cloud_upload_outlined,
                              size: 12, color: AppUi.muted(context)),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _balanceLine(balanceAfter),
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                        color: AppUi.muted(context),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${entry.isGave ? '+' : '−'}${AppUi.amount(entry.amount)}',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: AppUi.accent(context, tone),
                ),
              ),
              _buildEntryMenu(context, c, entry),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEntryMenu(
    BuildContext context,
    PersonalController c,
    DebtEntry entry,
  ) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, size: 18, color: AppUi.muted(context)),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      tooltip: 'options'.tr,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        if (value == 'edit') {
          showDebtEntrySheet(context, entry: entry);
        } else if (value == 'delete') {
          showConfirmDialog(
            title: 'delete_entry'.tr,
            message: 'confirm_delete_entry'.tr,
            detail: '${AppUi.amount(entry.amount)} · '
                '${DateFormat('dd MMM, yyyy').format(entry.day)}',
            confirmText: 'delete'.tr,
            onConfirm: () => c.deleteDebtEntry(entry),
          );
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 19, color: AppUi.muted(context)),
              const SizedBox(width: 12),
              Text('edit_entry'.tr),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete_outline_rounded,
                  size: 19, color: Colors.red.shade400),
              const SizedBox(width: 12),
              Text('delete_entry'.tr,
                  style: TextStyle(color: Colors.red.shade400)),
            ],
          ),
        ),
      ],
    );
  }

  /// Where the account stood after one entry: `+` is money still to come
  /// back, `−` is money still owed out.
  static String _balanceLine(double balance) {
    if (balance.abs() < 0.005) return 'all_settled'.tr;
    final String label = balance > 0 ? 'due_will_get'.tr : 'due_will_pay'.tr;
    return '${'balance_after'.tr}: $label ${AppUi.amount(balance.abs())}';
  }

  /// Both directions sit at the bottom, because from inside an account the
  /// next entry is nearly always a repayment one way or the other.
  Widget _buildActionBar(BuildContext context, PersonBalance person) {
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
                child: _actionButton(
                  context,
                  label: 'due_will_get'.tr,
                  icon: Icons.add_rounded,
                  color: Colors.green,
                  onTap: () => showDebtEntrySheet(
                    context,
                    personName: person.name,
                    personPhone: person.phone,
                    flow: DebtFlow.gave,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _actionButton(
                  context,
                  label: 'due_will_pay'.tr,
                  icon: Icons.remove_rounded,
                  color: Colors.deepOrange,
                  onTap: () => showDebtEntrySheet(
                    context,
                    personName: person.name,
                    personPhone: person.phone,
                    flow: DebtFlow.got,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton(
    BuildContext context, {
    required String label,
    required IconData icon,
    required MaterialColor color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: AppUi.tint(context, color),
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 15),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 17, color: AppUi.accent(context, color)),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppUi.accent(context, color),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
