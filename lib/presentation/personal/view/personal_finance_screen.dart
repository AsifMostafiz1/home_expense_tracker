import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/debt_entry.dart';
import '../model/personal_category.dart';
import '../model/personal_summary.dart';
import '../model/personal_transaction.dart';
import '../widgets/add_person_sheet.dart';
import '../widgets/category_breakdown.dart';
import '../widgets/category_entries_sheet.dart';
import '../widgets/money_trend_chart.dart';
import '../widgets/personal_skeletons.dart';
import '../widgets/transaction_sheet.dart';
import 'person_ledger_screen.dart';
import 'wallet_breakdown_screen.dart';

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
  void initState() {
    super.initState();
    // The screen is rebuilt every time the tab is entered; the controller is
    // not. So this is where "opening the ledger" gets to mean this month.
    Get.find<PersonalController>().resetToCurrentMonth();
  }

  /// Pull-to-refresh means start again.
  ///
  /// Everything this visit had set goes back to how the screen opens: the
  /// month, the filter over the list, the chart somebody unfolded, the column
  /// they tapped inside it. A half refresh is the confusing one — rows
  /// changing underneath a filter that stayed put, or a fresh read landing in
  /// a month nobody is looking at any more.
  ///
  /// Not the tab, though: which book is open is where the reader is, not
  /// something they set, and throwing them back to the other one is not a
  /// refresh.
  Future<void> _refreshMoney(PersonalController c) async {
    setState(() {
      _entryFlow = null;
      _trendOpen = false;
      _resetToken++;
    });
    // Silent, and it does not need to be anything else — the setState above
    // is already rebuilding everything that reads the month.
    c.resetToCurrentMonth();
    await c.refreshAll();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  bool get _onDues => _tabs.index == 1;

  /// Whether the six-month chart is open. Held here rather than inside the
  /// chart: the list disposes what scrolls out of it, and a fold that reset
  /// itself on every scroll would be an annoyance rather than a setting.
  /// Shut to begin with — the month on screen is what the tab is for.
  bool _trendOpen = false;

  /// Which side of the month's list is being shown, or null for both. Lives
  /// with the screen rather than the controller: it is a way of reading this
  /// visit, not a setting, and arriving at the ledger should show everything.
  MoneyFlow? _entryFlow;

  /// Bumped by a refresh, and used as the trend chart's key. The chart holds
  /// one thing of its own — which column was tapped — and a new key is what
  /// gets rid of it, since nothing out here can reach in and clear it.
  int _resetToken = 0;

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
          // Just the plus, the way the house expense screen's is: which book
          // it adds to is the tab that is open, and a label repeating that
          // sits on top of the list it is trying not to cover. What it does
          // still has a name for anyone who holds it, and for screen readers.
          //
          // On the dues side it adds a person, not a due. Amounts belong
          // inside somebody's account, where both directions are one tap
          // away — asking for a name and a figure at the same moment made
          // adding a person to the list impossible without inventing a loan.
          floatingActionButton: FloatingActionButton(
            onPressed: () => _onDues
                ? showAddPersonSheet(context)
                : showTransactionSheet(context),
            backgroundColor: primary,
            foregroundColor: Colors.white,
            tooltip: _onDues ? 'add_person'.tr : 'add_entry'.tr,
            child: const Icon(Icons.add_rounded),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              RefreshIndicator(
                color: primary,
                onRefresh: () => _refreshMoney(c),
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
    final List<MoneyDay> days = c.monthDays(flow: _entryFlow);

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        _buildMonthSwitcher(context, c),
        const SizedBox(height: 14),
        _buildWalletHero(context, c),
        const SizedBox(height: 14),
        MoneyTrendChart(
          key: ValueKey<int>(_resetToken),
          months: c.trend,
          focused: c.selectedMonth,
          expanded: _trendOpen,
          onToggle: () => setState(() => _trendOpen = !_trendOpen),
        ),
        if (spending.isNotEmpty) ...[
          const SizedBox(height: 14),
          CategoryBreakdown(
            totals: spending,
            total: month.expense,
            title: 'where_money_went'.tr,
            onTap: (bucket) => showCategoryEntriesSheet(
              context,
              category: bucket.category,
              income: false,
            ),
          ),
        ],
        if (earning.isNotEmpty) ...[
          const SizedBox(height: 14),
          CategoryBreakdown(
            totals: earning,
            total: month.income,
            title: 'where_money_came_from'.tr,
            onTap: (bucket) => showCategoryEntriesSheet(
              context,
              category: bucket.category,
              income: true,
            ),
          ),
        ],
        const SizedBox(height: 22),
        Text(
          'this_months_entries'.tr.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: 1.2,
            color: AppUi.muted(context),
          ),
        ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 10),
          _buildFlowFilter(context, c),
        ],
        const SizedBox(height: 12),
        if (entries.isEmpty)
          _buildInlineEmpty(context, 'no_entries_this_month'.tr)
        else if (days.isEmpty)
          _buildInlineEmpty(context, 'no_entries_of_kind'.tr)
        else
          for (final MoneyDay day in days) ...[
            _buildDayGroup(context, c, day),
            const SizedBox(height: 18),
          ],
      ],
    );
  }

  /// Which side of the month to read.
  ///
  /// Chips rather than a segmented bar, and each carrying its own count: the
  /// counts are the reason to reach for this at all — a month of forty rows
  /// with one salary in it is a month where "Income 1" is the whole answer,
  /// and nobody has to tap to find that out.
  Widget _buildFlowFilter(BuildContext context, PersonalController c) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _flowChip(context, null, 'filter_all'.tr, null, c.monthCount()),
        _flowChip(
          context,
          MoneyFlow.income,
          'income'.tr,
          Icons.north_east_rounded,
          c.monthCount(flow: MoneyFlow.income),
          tone: Colors.green,
        ),
        _flowChip(
          context,
          MoneyFlow.expense,
          'expense_word'.tr,
          Icons.south_west_rounded,
          c.monthCount(flow: MoneyFlow.expense),
          tone: Colors.deepOrange,
        ),
      ],
    );
  }

  Widget _flowChip(
    BuildContext context,
    MoneyFlow? flow,
    String label,
    IconData? icon,
    int count, {
    MaterialColor? tone,
  }) {
    final bool selected = _entryFlow == flow;
    final MaterialColor colour = tone ?? Colors.blueGrey;
    final Color accent = AppUi.accent(context, colour);

    return GestureDetector(
      // Tapping the chip already on is not an accident worth acting on.
      onTap: selected ? null : () => setState(() => _entryFlow = flow),
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
                  size: 13,
                  color: selected ? accent : AppUi.muted(context)),
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
                fontWeight: FontWeight.w900,
                color: selected ? accent : AppUi.muted(context),
              ),
            ),
          ],
        ),
      ),
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

  /// The wallet, and the month that moved it.
  ///
  /// The balance is the headline because it is the number that answers "can I
  /// afford this". The month's own figures are the working behind it — what
  /// was already there, what came in, what went out — so they sit underneath
  /// in that order rather than competing for the top line.
  ///
  /// Drawn on a gradient like the house expense summary, so a member's two
  /// ledgers open with the same kind of card. Value contrast does the work on
  /// top of it: accent hues would fight the ground, as they do over there.
  Widget _buildWalletHero(BuildContext context, PersonalController c) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final MonthMoney month = c.monthMoney;
    final WalletBalance wallet = c.wallet;

    final DateTime now = DateTime.now();
    final bool isThisMonth =
        c.selectedMonth.year == now.year && c.selectedMonth.month == now.month;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primary, primary.withOpacity(0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primary.withOpacity(0.30),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_balance_wallet_rounded,
                  size: 15, color: Colors.white70),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'wallet'.tr.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const Icon(Icons.lock_outline_rounded,
                  size: 12, color: Colors.white70),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  'private_to_you'.tr,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 10.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                // The button hugs the figure rather than sitting at the far
                // edge: it is about this number, not about the card.
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        walletFigure(wallet.balance),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 34,
                          height: 1.1,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                    Material(
                      // Transparent, and above the gradient — an ink splash
                      // paints on the nearest Material, which without this is
                      // the page underneath and therefore invisible.
                      color: Colors.transparent,
                      child: IconButton(
                        onPressed: () =>
                            Get.to(() => const WalletBreakdownScreen()),
                        icon: const Icon(Icons.info_outline_rounded),
                        iconSize: 18,
                        color: Colors.white70,
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(
                            minWidth: 34, minHeight: 34),
                        splashRadius: 18,
                        tooltip: 'how_it_adds_up'.tr,
                      ),
                    ),
                  ],
                ),
              ),
              // Nothing recorded this month moved nothing — a "+৳0" pill
              // would be noise next to the balance.
              if (!month.isEmpty) ...[
                const SizedBox(width: 10),
                _MonthNetChip(net: month.net, month: c.selectedMonth),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Text(
            !isThisMonth
                ? 'wallet_as_of'
                    .trParams({'month': AppUi.monthLabel(c.selectedMonth)})
                : wallet.isShort
                    ? 'wallet_short'.tr
                    : wallet.hasDues
                        ? 'wallet_with_dues'.tr
                        : 'wallet_in_hand'.tr,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 16),
          // The working behind the figure above, left to right in the order
          // it happens: what was already there, what came in, what went out.
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.16),
              borderRadius: BorderRadius.circular(16),
            ),
            // The money only. The dues are in the figure above and named in
            // the line under it; spelling them out again here would give two
            // rows of five numbers to a card whose job is to carry one.
            // The button beside the balance is where they are itemised.
            child: Row(
              children: [
                _heroStat(
                    'carried_in'.tr, wallet.opening, Icons.history_rounded),
                _heroStatDivider(),
                _heroStat('income'.tr, month.income, Icons.north_east_rounded),
                _heroStatDivider(),
                _heroStat(
                    'expense_word'.tr, month.expense, Icons.south_west_rounded),
              ],
            ),
          ),
          if (!month.isEmpty) ...[
            const SizedBox(height: 14),
            _MonthSpendBar(month: month),
            const SizedBox(height: 7),
            Text(
              _monthVerdict(month),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 11, height: 1.35),
            ),
          ],
        ],
      ),
    );
  }

  /// What the month did, in one line.
  ///
  /// Three different things to say, not one with a number swapped in: a month
  /// that spent past its income is not a month that "kept 0%" — the figure
  /// that matters there is how far past, and by how much. And a month with no
  /// income at all has no share to be a percentage of.
  String _monthVerdict(MonthMoney month) {
    if (!month.isOverspent) {
      return 'kept_share'
          .trParams({'percent': '${(month.savedShare * 100).round()}'});
    }

    if (month.income <= 0) {
      return 'overspent_no_income'
          .trParams({'amount': AppUi.amount(month.expense)});
    }

    return 'overspent_share'.trParams({
      'percent': '${(month.spentShare * 100).round()}',
      'amount': AppUi.amount(month.overspend),
    });
  }

  Widget _heroStat(String label, double value, IconData icon) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 11, color: Colors.white70),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 10.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            walletFigure(value),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _heroStatDivider() => Container(
        width: 1,
        height: 26,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: Colors.white.withOpacity(0.22),
      );

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
                        // which day this was. Flexible like the category
                        // beside it, so the badges that follow are never the
                        // ones pushed off the edge — they are the part of
                        // this line that cannot be read from anywhere else.
                        Flexible(
                          child: Text(
                            entry.time.format(context),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 11, color: AppUi.muted(context)),
                          ),
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
  ///
  /// Named for what the member did rather than for what follows from it —
  /// "borrowed" is a thing they remember doing, where "total to get" is a
  /// conclusion they have to work back from. What follows from it is the line
  /// under the figure, and it is put in terms of the wallet: borrowing puts
  /// money in it, lending takes money out, which is the way round the wallet
  /// on the other tab already counts them.
  ///
  /// Lent out comes first — money the member has put out and is waiting on is
  /// the half they open this tab to check.
  Widget _buildDuesHero(BuildContext context, PersonalController c) {
    return IntrinsicHeight(
      child: Row(
        // Two cards of the same height whichever way their hints wrap — a
        // pair sitting at different heights reads as a mistake.
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _duesCard(
              context,
              label: 'debt_given'.tr,
              hint: 'debt_given_hint'.tr,
              amount: c.totalPayable,
              icon: Icons.call_made_rounded,
              color: Colors.deepOrange,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _duesCard(
              context,
              label: 'debt_taken'.tr,
              hint: 'debt_taken_hint'.tr,
              amount: c.totalReceivable,
              icon: Icons.call_received_rounded,
              color: Colors.green,
            ),
          ),
        ],
      ),
    );
  }

  /// [label] is what was done, [hint] is what it did to the wallet — one line
  /// under the figure, because "lent out" and "borrowed" are the two words
  /// people most reliably say the wrong way round.
  Widget _duesCard(
    BuildContext context, {
    required String label,
    required String hint,
    required double amount,
    required IconData icon,
    required MaterialColor color,
  }) {
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
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppUi.body(context),
                  ),
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
          const SizedBox(height: 4),
          Text(
            hint,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.35,
              color: AppUi.muted(context),
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
        : (person.owesMe ? 'debt_taken'.tr : 'debt_given'.tr);

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
              // Somebody on this list may also be in the house, in which
              // case their picture is already known — the directory resolves
              // it from the name or phone the account was opened with. It
              // falls back to the same initials in the same tinted circle, so
              // a person from outside the app looks exactly as before.
              ProfileAvatar(
                name: person.name,
                phone: person.phone,
                size: 44,
                background: AppUi.tint(context, tone),
                foreground: AppUi.accent(context, tone),
                fontSize: 15,
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
                          ? 'no_entries_yet'.tr
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
/// How the month sat against its own income.
///
/// Inside it, the bar is what was kept: a full bar is a month that spent
/// nothing. Past it, the scale changes to what was spent — the stretch the
/// income covered, then the stretch it did not — because "how far over" is
/// the only question left once the answer to "did it fit" is no. A bar that
/// simply sat empty at 0% said neither.
///
/// Value contrast rather than hue, like the split bar on the house expense
/// summary: a red on this ground goes muddy.
/// ---------------------------------------------------------------------------

class _MonthSpendBar extends StatelessWidget {
  final MonthMoney month;

  const _MonthSpendBar({required this.month});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        height: 6,
        child: month.isOverspent ? _overspent() : _kept(),
      ),
    );
  }

  Widget _kept() {
    return LinearProgressIndicator(
      value: month.savedShare,
      minHeight: 6,
      backgroundColor: Colors.white.withOpacity(0.25),
      valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
    );
  }

  /// The whole bar is what was spent: the bright stretch is the part the
  /// income paid for, the dim one is the part nothing paid for.
  Widget _overspent() {
    // Rounded to a flex weight rather than used as a fraction — a Row lays
    // out in whole units, and a hundredth of a taka is not a pixel.
    final int covered = (month.income * 100).round().clamp(0, 100000000);
    final int over = (month.overspend * 100).round().clamp(1, 100000000);

    return Row(
      children: [
        if (covered > 0) ...[
          Expanded(
            flex: covered,
            child: Container(color: Colors.white.withOpacity(0.95)),
          ),
          const SizedBox(width: 3),
        ],
        Expanded(
          flex: over,
          child: Container(color: Colors.white.withOpacity(0.38)),
        ),
      ],
    );
  }
}

/// ---------------------------------------------------------------------------
/// What the month on screen did to the wallet, as a pill beside the balance.
/// Direction is carried by the arrow and the sign rather than by a colour —
/// green and orange both go muddy on a saturated ground.
/// ---------------------------------------------------------------------------

class _MonthNetChip extends StatelessWidget {
  final double net;
  final DateTime month;

  const _MonthNetChip({required this.net, required this.month});

  @override
  Widget build(BuildContext context) {
    final bool up = net >= 0;

    return Tooltip(
      message: (up ? 'saved_this_month' : 'overspent_this_month').tr,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(up ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                size: 13, color: Colors.white),
            const SizedBox(width: 5),
            Text(
              '${up ? '+' : '−'}${AppUi.amount(net.abs())}'
              ' · ${AppUi.shortMonth(month)}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
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
