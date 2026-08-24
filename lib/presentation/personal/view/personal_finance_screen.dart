import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/debt_entry.dart';
import '../model/personal_category.dart';
import '../model/personal_summary.dart';
import '../model/personal_transaction.dart';
import '../widgets/category_breakdown.dart';
import '../widgets/debt_entry_sheet.dart';
import '../widgets/money_trend_chart.dart';
import '../widgets/personal_skeletons.dart';
import '../widgets/transaction_sheet.dart';
import 'person_ledger_screen.dart';

/// A member's own books, kept apart from everything the house shares.
///
/// Two tabs, because they answer two different questions: what happened to my
/// own money this month, and who is square with me. Neither reads a meal, a
/// shared expense or another member — this ledger is private to the phone
/// signed in.
class PersonalFinanceScreen extends StatefulWidget {
  const PersonalFinanceScreen({super.key});

  @override
  State<PersonalFinanceScreen> createState() => _PersonalFinanceScreenState();
}

class _PersonalFinanceScreenState extends State<PersonalFinanceScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this)
    // The button in the corner adds to whichever book is open.
    ..addListener(() => setState(() {}));

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _onDues => _tabs.index == 1;

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return GetBuilder<PersonalController>(
      builder: (c) {
        return Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: CustomAppBar(
            title: 'my_ledger'.tr,
            bottom: _LedgerSwitcher(
              index: _tabs.index,
              onSelected: (index) => _tabs.animateTo(index),
            ),
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _onDues
                ? showDebtEntrySheet(context)
                : showTransactionSheet(context),
            backgroundColor: primary,
            foregroundColor: Colors.white,
            icon: const Icon(Icons.add_rounded),
            label: Text(_onDues ? 'add_due_entry'.tr : 'add_entry'.tr),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              RefreshIndicator(
                color: primary,
                onRefresh: c.refreshAll,
                child: c.isLoading
                    ? const PersonalMoneySkeleton()
                    : _buildMoneyTab(context, c),
              ),
              RefreshIndicator(
                color: primary,
                onRefresh: c.refreshAll,
                child: c.isLoading
                    ? const PersonalDebtSkeleton()
                    : _buildDuesTab(context, c),
              ),
            ],
          ),
        );
      },
    );
  }

  /// ------------------------------------------------------------- money tab

  Widget _buildMoneyTab(BuildContext context, PersonalController c) {
    final MonthMoney month = c.monthMoney;
    final List<PersonalTransaction> entries = c.monthTransactions;
    final List<CategoryTotal> spending = c.categoryTotals(income: false);
    final List<CategoryTotal> earning = c.categoryTotals(income: true);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        _buildMonthSwitcher(context, c),
        const SizedBox(height: 14),
        _buildMonthHero(context, month),
        const SizedBox(height: 14),
        MoneyTrendChart(months: c.trend, focused: c.selectedMonth),
        if (spending.isNotEmpty) ...[
          const SizedBox(height: 14),
          CategoryBreakdown(
            totals: spending,
            total: month.expense,
            title: 'where_money_went'.tr,
          ),
        ],
        if (earning.isNotEmpty) ...[
          const SizedBox(height: 14),
          CategoryBreakdown(
            totals: earning,
            total: month.income,
            title: 'where_money_came_from'.tr,
          ),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: Text(
                'this_months_entries'.tr.toUpperCase(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: AppUi.muted(context),
                ),
              ),
            ),
            Text(
              '${entries.length}',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w900,
                color: AppUi.muted(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          _buildInlineEmpty(context, 'no_entries_this_month'.tr)
        else
          for (final MoneyDay day in c.monthDays) ...[
            _buildDayGroup(context, c, day),
            const SizedBox(height: 18),
          ],
      ],
    );
  }

  /// ------------------------------------------------------------- day group

  /// One day's entries under one heading, the same shape the house expense
  /// screen groups by — the two ledgers should read alike.
  Widget _buildDayGroup(
    BuildContext context,
    PersonalController c,
    MoneyDay day,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppUi.neutralSurface(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppUi.hairline(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_today_rounded,
                      size: 12, color: AppUi.muted(context)),
                  const SizedBox(width: 6),
                  Text(
                    AppUi.dayLabel(day.date),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppUi.body(context).withOpacity(0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Divider(color: AppUi.hairline(context), height: 1),
            ),
            const SizedBox(width: 12),
            _buildDayTotal(context, day),
          ],
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppUi.hairline(context)),
            boxShadow: AppUi.softShadow(context),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (int i = 0; i < day.entries.length; i++) ...[
                _buildTransactionRow(context, c, day.entries[i]),
                if (i != day.entries.length - 1)
                  Divider(
                    height: 1,
                    indent: 64,
                    endIndent: 12,
                    color: AppUi.hairline(context),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// What the day came to. One figure rather than two, because most days are
  /// all spending — but it keeps the sign and the colour the rows use, so a
  /// day that earned more than it spent says so.
  Widget _buildDayTotal(BuildContext context, MoneyDay day) {
    final double net = day.net;

    if (net == 0) {
      return Text(
        AppUi.amount(0),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.bold,
          color: AppUi.muted(context),
        ),
      );
    }

    final MaterialColor tone = net > 0 ? Colors.green : Colors.deepOrange;
    return Text(
      '${net > 0 ? '+' : '−'}${AppUi.amount(net.abs())}',
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: AppUi.accent(context, tone),
      ),
    );
  }

  Widget _buildMonthSwitcher(BuildContext context, PersonalController c) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: c.previousMonth,
            icon: const Icon(Icons.chevron_left_rounded),
            color: AppUi.body(context),
            tooltip: 'previous_month'.tr,
          ),
          Expanded(
            child: Text(
              AppUi.monthLabel(c.selectedMonth),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppUi.body(context),
              ),
            ),
          ),
          IconButton(
            // Nothing is recorded ahead of today, so there is nothing to walk
            // forward into.
            onPressed: c.canGoForward ? c.nextMonth : null,
            icon: const Icon(Icons.chevron_right_rounded),
            color: AppUi.body(context),
            disabledColor: AppUi.muted(context).withOpacity(0.4),
            tooltip: 'next_month'.tr,
          ),
        ],
      ),
    );
  }

  /// The month in three numbers, with what was kept out of what came in.
  Widget _buildMonthHero(BuildContext context, MonthMoney month) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool ahead = month.net >= 0;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: AppUi.tint(context, primary),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: primary.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  (ahead ? 'saved_this_month' : 'overspent_this_month').tr,
                  style: TextStyle(fontSize: 11.5, color: AppUi.muted(context)),
                ),
              ),
              Icon(Icons.lock_outline_rounded,
                  size: 12, color: AppUi.muted(context)),
              const SizedBox(width: 4),
              Text(
                'private_to_you'.tr,
                style: TextStyle(fontSize: 10.5, color: AppUi.muted(context)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            AppUi.amount(month.net.abs()),
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
              color: AppUi.accent(
                  context, ahead ? Colors.green : Colors.deepOrange),
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _heroStat(context, 'income'.tr, month.income,
                  Icons.north_east_rounded, Colors.green),
              Container(
                width: 1,
                height: 30,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppUi.hairline(context),
              ),
              _heroStat(context, 'expense_word'.tr, month.expense,
                  Icons.south_west_rounded, Colors.deepOrange),
            ],
          ),
          if (month.income > 0) ...[
            const SizedBox(height: 14),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: month.savedShare,
                minHeight: 6,
                backgroundColor: AppUi.tint(context, Colors.deepOrange),
                valueColor: AlwaysStoppedAnimation<Color>(
                    AppUi.accent(context, Colors.green)),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'kept_share'.trParams(
                  {'percent': '${(month.savedShare * 100).round()}'}),
              style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _heroStat(
    BuildContext context,
    String label,
    double value,
    IconData icon,
    MaterialColor color,
  ) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 13, color: AppUi.accent(context, color)),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            AppUi.amount(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppUi.body(context),
            ),
          ),
        ],
      ),
    );
  }

  /// One entry, inside its day's card — so no border or radius of its own.
  Widget _buildTransactionRow(
    BuildContext context,
    PersonalController c,
    PersonalTransaction entry,
  ) {
    final PersonalCategory category = PersonalCategory.of(entry.category);
    final MaterialColor tone = entry.isIncome ? Colors.green : Colors.deepOrange;
    // Paid for the house: shown here because the money was this member's, but
    // the entry belongs to the house screen and is only changed there.
    final bool fromHouse = entry.isFromHouse;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => fromHouse
            ? _explainHouseEntry()
            : showTransactionSheet(context, entry: entry),
        onLongPress: () => fromHouse
            ? _explainHouseEntry()
            : _confirmDeleteTransaction(context, c, entry),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppUi.tint(context, category.color),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(category.icon,
                    size: 19, color: AppUi.accent(context, category.color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.note.isEmpty ? category.label : entry.note,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: AppUi.body(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        // Just the clock: the heading above already says
                        // which day this was.
                        Text(
                          entry.time.format(context),
                          style: TextStyle(
                              fontSize: 11, color: AppUi.muted(context)),
                        ),
                        if (entry.note.isNotEmpty) ...[
                          Text(' · ',
                              style: TextStyle(
                                  fontSize: 11, color: AppUi.muted(context))),
                          Flexible(
                            child: Text(
                              category.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 11, color: AppUi.muted(context)),
                            ),
                          ),
                        ],
                        if (fromHouse) ...[
                          const SizedBox(width: 6),
                          const _HouseTag(),
                        ],
                        if (entry.pending) ...[
                          const SizedBox(width: 6),
                          Icon(Icons.cloud_upload_outlined,
                              size: 12, color: AppUi.muted(context)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${entry.isIncome ? '+' : '−'}${AppUi.amount(entry.amount)}',
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.bold,
                  color: AppUi.accent(context, tone),
                ),
              ),
              // The long press does the same thing, but a menu is the only
              // one of the two anybody finds. A house row has neither choice
              // to offer, so it says why instead.
              if (fromHouse)
                IconButton(
                  icon: Icon(Icons.lock_outline_rounded,
                      size: 18, color: AppUi.muted(context)),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                  splashRadius: 18,
                  tooltip: 'from_house_expense'.tr,
                  onPressed: _explainHouseEntry,
                )
              else
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
    PersonalTransaction entry,
  ) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, size: 18, color: AppUi.muted(context)),
      padding: EdgeInsets.zero,
      splashRadius: 18,
      tooltip: 'options'.tr,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        if (value == 'edit') {
          showTransactionSheet(context, entry: entry);
        } else if (value == 'delete') {
          _confirmDeleteTransaction(context, c, entry);
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

  /// Why a house row will not open. Editing it here would leave the house's
  /// own copy behind and the two would stop agreeing, so the change has to be
  /// made where the entry was recorded.
  void _explainHouseEntry() {
    CustomSnackbar.show(
      type: SnackbarType.info,
      message: 'house_entry_locked'.tr,
      duration: const Duration(seconds: 4),
    );
  }

  void _confirmDeleteTransaction(
    BuildContext context,
    PersonalController c,
    PersonalTransaction entry,
  ) {
    showConfirmDialog(
      title: 'delete_entry'.tr,
      message: 'confirm_delete_entry'.tr,
      detail:
          '${AppUi.amount(entry.amount)} · ${PersonalCategory.of(entry.category).label}',
      confirmText: 'delete'.tr,
      onConfirm: () => c.deleteTransaction(entry),
    );
  }

  /// -------------------------------------------------------------- dues tab

  Widget _buildDuesTab(BuildContext context, PersonalController c) {
    final List<PersonBalance> people = c.people;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        _buildDuesHero(context, c),
        const SizedBox(height: 20),
        if (people.isEmpty)
          _buildInlineEmpty(context, 'no_dues_yet'.tr)
        else
          for (final PersonBalance person in people) ...[
            _buildPersonTile(context, person),
            const SizedBox(height: 10),
          ],
      ],
    );
  }

  /// The two totals, kept apart: netting them would hide a thousand lent
  /// behind a thousand borrowed.
  Widget _buildDuesHero(BuildContext context, PersonalController c) {
    return Row(
      children: [
        Expanded(
          child: _duesCard(context, 'you_will_receive'.tr, c.totalReceivable,
              Icons.call_received_rounded, Colors.green),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _duesCard(context, 'you_will_pay'.tr, c.totalPayable,
              Icons.call_made_rounded, Colors.deepOrange),
        ),
      ],
    );
  }

  Widget _duesCard(
    BuildContext context,
    String label,
    double amount,
    IconData icon,
    MaterialColor color,
  ) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppUi.tint(context, color),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: AppUi.accent(context, color)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            AppUi.amount(amount),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: AppUi.accent(context, color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonTile(BuildContext context, PersonBalance person) {
    final MaterialColor tone = person.isSettled
        ? Colors.blueGrey
        : (person.owesMe ? Colors.green : Colors.deepOrange);
    final String label = person.isSettled
        ? 'all_settled'.tr
        : (person.owesMe ? 'owes_you'.tr : 'you_owe'.tr);

    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Get.to(() => PersonLedgerScreen(personKey: person.key)),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 14, 16, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppUi.hairline(context)),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppUi.tint(context, tone),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  _initials(person.name),
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: AppUi.accent(context, tone),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      person.name.isEmpty ? 'unknown'.tr : person.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.bold,
                        color: AppUi.body(context),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      person.lastActivity == null
                          ? '${person.entries.length}'
                          : '$label · ${AppUi.dayLabel(person.lastActivity!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          TextStyle(fontSize: 11.5, color: AppUi.muted(context)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                person.isSettled
                    ? AppUi.amount(0)
                    : AppUi.amount(person.balance.abs()),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppUi.accent(context, tone),
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

  static String _initials(String name) {
    final List<String> parts =
        name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.first.toUpperCase();
    return (parts.first.characters.first + parts.last.characters.first)
        .toUpperCase();
  }

  /// ---------------------------------------------------------------- shared

  Widget _buildInlineEmpty(BuildContext context, String message) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 20),
      decoration: BoxDecoration(
        color: AppUi.neutralSurface(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Column(
        children: [
          Icon(Icons.inbox_rounded, size: 30, color: AppUi.muted(context)),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              height: 1.45,
              color: AppUi.muted(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// The mark on a row that came from the house expense screen — small, next to
/// the category, so a ledger that suddenly has entries nobody typed here still
/// explains itself.
/// ---------------------------------------------------------------------------

class _HouseTag extends StatelessWidget {
  const _HouseTag();

  @override
  Widget build(BuildContext context) {
    final Color accent = AppUi.accent(context, Colors.indigo);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppUi.tint(context, Colors.indigo),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.home_rounded, size: 10, color: accent),
          const SizedBox(width: 3),
          Text(
            'from_house_expense'.tr,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// The two books, as one segmented pill — the same control the expense screen
/// switches months with, so the two screens read as one app.
/// ---------------------------------------------------------------------------

class _LedgerSwitcher extends StatelessWidget implements PreferredSizeWidget {
  final int index;
  final ValueChanged<int> onSelected;

  const _LedgerSwitcher({required this.index, required this.onSelected});

  @override
  Size get preferredSize => const Size.fromHeight(58);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppUi.neutralSurface(context),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppUi.hairline(context)),
        ),
        child: Row(
          children: [
            _segment(context, 0, 'money_tab'.tr),
            _segment(context, 1, 'dues_tab'.tr),
          ],
        ),
      ),
    );
  }

  Widget _segment(BuildContext context, int slot, String label) {
    final bool selected = index == slot;
    final Color primary = Theme.of(context).colorScheme.primary;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelected(slot),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? primary : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: primary.withOpacity(0.30),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ]
                : null,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: selected ? Colors.white : AppUi.muted(context),
            ),
          ),
        ),
      ),
    );
  }
}
