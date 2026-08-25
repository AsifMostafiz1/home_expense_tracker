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
import '../widgets/settle_debt_sheet.dart';

/// One person's account: every rupee that has passed between the two of them,
/// and what it comes to.
///
/// The person is looked up by key on every build rather than passed in whole,
/// so the screen follows the live list — an entry added from here changes the
/// balance above it at once, and an account emptied of rows closes itself.
class PersonLedgerScreen extends StatefulWidget {
  final String personKey;

  const PersonLedgerScreen({super.key, required this.personKey});

  @override
  State<PersonLedgerScreen> createState() => _PersonLedgerScreenState();
}

class _PersonLedgerScreenState extends State<PersonLedgerScreen> {
  /// Which side of the account to show, or null for both.
  DebtFlow? _flow;

  /// `yyyy-MM`, or null for every month. Held as the key rather than a date
  /// so it can be compared against [DebtEntry.monthKey] directly.
  String? _month;

  /// Pull-to-refresh: back to the account as it opens.
  ///
  /// Both filters go, because a refresh that left them on would answer "why
  /// am I not seeing the entry I just added" with silence — the row is there,
  /// it is behind a chip somebody set five minutes ago. The streams keep the
  /// rows current on their own; re-attaching them is what recovers a listener
  /// that fell over while the connection was gone.
  Future<void> _refresh(PersonalController c) async {
    setState(() {
      _flow = null;
      _month = null;
    });
    await c.refreshAll();
  }

  /// The history, narrowed to what the two filters ask for.
  ///
  /// A month that has been emptied out from under the filter — the last entry
  /// in it deleted — falls back to every month rather than showing nothing,
  /// which would read as a bug rather than as a filter.
  List<DebtEntry> _visible(PersonBalance person, Set<String> months) {
    final String? month = _month != null && months.contains(_month) ? _month : null;

    return person.entries.where((entry) {
      if (_flow != null && entry.flow != _flow) return false;
      if (month != null && entry.monthKey != month) return false;
      return true;
    }).toList(growable: false);
  }

  int _count(PersonBalance person, Set<String> months, {DebtFlow? flow}) {
    final String? month = _month != null && months.contains(_month) ? _month : null;

    return person.entries.where((entry) {
      if (flow != null && entry.flow != flow) return false;
      if (month != null && entry.monthKey != month) return false;
      return true;
    }).length;
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<PersonalController>(
      builder: (c) {
        final PersonBalance? person = c.personFor(widget.personKey);

        // Every row deleted — there is no account left to look at.
        if (person == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Get.currentRoute.contains('PersonLedgerScreen')) Get.back();
          });
          return const SizedBox.shrink();
        }

        // Running totals are worked out over the whole account and looked up
        // by entry id, so a filtered list still shows the balance each row
        // actually left behind — not a total restarted from the filter.
        final Map<String, double> balances = person.runningBalances;

        // Newest first, and only the months the account has anything in.
        final List<String> months = person.entries
            .map((entry) => entry.monthKey)
            .where((key) => key.isNotEmpty)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));

        final Set<String> monthSet = months.toSet();
        final List<DebtEntry> visible = _visible(person, monthSet);

        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: CustomAppBar(
            title: person.name.isEmpty ? 'unknown'.tr : person.name,
            actions: [_buildMenu(context, c, person)],
          ),
          body: RefreshIndicator(
            color: Theme.of(context).colorScheme.primary,
            onRefresh: () => _refresh(c),
            child: ListView(
              // Pulled from anywhere, including an account short enough not to
              // scroll on its own — which is most of them.
              physics: const AlwaysScrollableScrollPhysics(),
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
                if (!person.isEmpty) ...[
                  const SizedBox(height: 10),
                  _buildFlowFilter(context, person, monthSet),
                  if (months.length > 1) ...[
                    const SizedBox(height: 8),
                    _buildMonthFilter(context, months),
                  ],
                ],
                const SizedBox(height: 12),
                if (person.isEmpty)
                  _buildEmptyHistory(context)
                else if (visible.isEmpty)
                  _buildNothingMatched(context)
                else
                  for (final DebtEntry entry in visible) ...[
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
          ),
          bottomNavigationBar: _buildActionBar(context, person),
        );
      },
    );
  }

  /// Which side of the account to read, each chip carrying its own count.
  ///
  /// The counts are the reason to reach for this at all: an account of thirty
  /// rows with two repayments in it is one where "ধার দিয়েছি 2" is the whole
  /// answer, and nobody has to tap to find that out. They follow the month
  /// filter, so the two read together rather than contradicting each other.
  Widget _buildFlowFilter(
    BuildContext context,
    PersonBalance person,
    Set<String> months,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _flowChip(context, null, 'filter_all'.tr, null,
            _count(person, months)),
        _flowChip(
          context,
          DebtFlow.gave,
          'debt_taken'.tr,
          Icons.add_rounded,
          _count(person, months, flow: DebtFlow.gave),
          tone: Colors.green,
        ),
        _flowChip(
          context,
          DebtFlow.got,
          'debt_given'.tr,
          Icons.remove_rounded,
          _count(person, months, flow: DebtFlow.got),
          tone: Colors.deepOrange,
        ),
      ],
    );
  }

  Widget _flowChip(
    BuildContext context,
    DebtFlow? flow,
    String label,
    IconData? icon,
    int count, {
    MaterialColor? tone,
  }) {
    final bool selected = _flow == flow;
    final MaterialColor colour = tone ?? Colors.blueGrey;
    final Color accent = AppUi.accent(context, colour);

    return GestureDetector(
      // Tapping the chip already on is not an accident worth acting on.
      onTap: selected ? null : () => setState(() => _flow = flow),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppUi.tint(context, colour)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent.withOpacity(0.6) : AppUi.hairline(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon,
                  size: 13, color: selected ? accent : AppUi.muted(context)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? accent : AppUi.body(context),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$count',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: selected ? accent : AppUi.muted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// One month at a time, and only offered once the account has more than one
  /// — a single-month history is already the answer to "which month".
  ///
  /// Scrolls sideways rather than wrapping: a long account would otherwise
  /// push the entries themselves off the screen behind rows of month chips.
  Widget _buildMonthFilter(BuildContext context, List<String> months) {
    return SizedBox(
      height: 34,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.zero,
        children: [
          _monthChip(context, null, 'all_months'.tr),
          for (final String key in months) ...[
            const SizedBox(width: 8),
            _monthChip(context, key, _monthLabel(key)),
          ],
        ],
      ),
    );
  }

  /// `2026-08` → `Aug 2026`, and back to the raw key if it will not parse.
  static String _monthLabel(String key) {
    final DateTime? month = DateTime.tryParse('$key-01');
    if (month == null) return key;
    return '${AppUi.shortMonth(month)} ${month.year}';
  }

  Widget _monthChip(BuildContext context, String? key, String label) {
    final bool selected = _month == key;
    final Color primary = Theme.of(context).colorScheme.primary;

    return GestureDetector(
      onTap: selected ? null : () => setState(() => _month = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? primary.withOpacity(0.12)
              : Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? primary.withOpacity(0.6) : AppUi.hairline(context),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            color: selected ? primary : AppUi.body(context),
          ),
        ),
      ),
    );
  }

  /// The account has rows, just none the filters let through — and a way back
  /// out, since the filters that hid them are two taps up the screen.
  Widget _buildNothingMatched(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Column(
        children: [
          Text(
            'no_entries_of_filter'.tr,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppUi.muted(context),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => setState(() {
              _flow = null;
              _month = null;
            }),
            child: Text(
              'clear_filters'.tr,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
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
        : (person.owesMe ? 'debt_taken'.tr : 'debt_given'.tr);

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
              _stat(context, 'total_debt_taken'.tr, person.totalGave,
                  Colors.green),
              Container(
                width: 1,
                height: 30,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppUi.hairline(context),
              ),
              _stat(context, 'total_debt_given'.tr, person.totalGot,
                  Colors.deepOrange),
            ],
          ),
          if (!person.isSettled) ...[
            const SizedBox(height: 14),
            _buildSettleButton(context, person, tone),
          ],
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

  /// The one thing left to do about an open account: hand the money back, or
  /// take it back.
  ///
  /// Only while something is outstanding — on a squared-off account there is
  /// nothing to settle, and the two buttons at the bottom already cover
  /// starting the account up again.
  Widget _buildSettleButton(
    BuildContext context,
    PersonBalance person,
    MaterialColor tone,
  ) {
    final Color accent = AppUi.accent(context, tone);

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => showSettleDebtSheet(context, person: person),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: accent.withOpacity(0.45)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.handshake_outlined, size: 17, color: accent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  person.owesMe ? 'settle_pay_back'.tr : 'settle_collect'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
        ),
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
                          ? (entry.isGave ? 'debt_taken'.tr : 'debt_given'.tr)
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

  /// Where the account stood after one entry: `+` is still owed to them, `−`
  /// is still owed by them.
  static String _balanceLine(double balance) {
    if (balance.abs() < 0.005) return 'all_settled'.tr;
    final String label = balance > 0 ? 'debt_taken'.tr : 'debt_given'.tr;
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
                  label: 'debt_taken'.tr,
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
                  label: 'debt_given'.tr,
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
