import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/custom_app_bar.dart';
import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/debt_entry.dart';
import '../model/personal_summary.dart';
import '../model/personal_transaction.dart';

/// Where the wallet figure comes from, line by line.
///
/// The card on the ledger gives one number; a number that four different
/// things feed into needs somewhere to be taken apart, or it is asking to be
/// trusted rather than read. So this is a statement, not a dashboard: the same
/// parts in the order they stack, each with what it contributed, and a total
/// ruled off underneath the way a paper ledger would do it.
///
/// It reads the controller live rather than taking a snapshot, so an entry
/// added while this is open — or a month switched behind it — is reflected
/// here too.
class WalletBreakdownScreen extends StatelessWidget {
  const WalletBreakdownScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(title: 'wallet'.tr),
      body: GetBuilder<PersonalController>(
        builder: (c) {
          final WalletBalance wallet = c.wallet;

          final WalletTimeline timeline = c.walletTimeline;
          final List<PersonBalance> people = c.walletPeople;

          // With no dues there is only one section, and its subtotal would
          // simply be the wallet again.
          final bool split = people.isNotEmpty;

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _buildTotalCard(context, c, wallet),
              const SizedBox(height: 24),
              _sectionLabel(context, 'month_by_month'.tr),
              const SizedBox(height: 12),
              _buildMonthsCard(context, c, timeline, wallet,
                  showSubtotal: split),
              if (split) ...[
                const SizedBox(height: 22),
                _sectionLabel(context, 'dues_tab'.tr),
                const SizedBox(height: 12),
                _buildDuesCard(context, people, wallet, showSubtotal: true),
              ],
              const SizedBox(height: 22),
              _buildWalletTotal(context, wallet),
              const SizedBox(height: 16),
              _buildNote(context),
            ],
          );
        },
      ),
    );
  }

  /// The same gradient the ledger opens with, so arriving here feels like
  /// turning the card over rather than landing somewhere else.
  Widget _buildTotalCard(
    BuildContext context,
    PersonalController c,
    WalletBalance wallet,
  ) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
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
                  AppUi.monthLabel(c.selectedMonth).toUpperCase(),
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
            ],
          ),
          const SizedBox(height: 14),
          Text(
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
          const SizedBox(height: 4),
          Text(
            wallet.hasDues ? 'wallet_with_dues'.tr : 'wallet_in_hand'.tr,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w900,
        letterSpacing: 1.2,
        color: AppUi.muted(context),
      ),
    );
  }

  /// The money side, in the order it happened: what came into this year, then
  /// each month of it that had anything in it.
  Widget _buildMonthsCard(
    BuildContext context,
    PersonalController c,
    WalletTimeline timeline,
    WalletBalance wallet, {
    required bool showSubtotal,
  }) {
    final String current = PersonalTransaction.monthKeyOf(c.selectedMonth);

    final List<Widget> rows = [];

    if (timeline.hasBroughtForward) {
      rows.add(_buildLine(
        context,
        icon: Icons.history_rounded,
        tone: Colors.blueGrey,
        label: 'carried_in'.tr,
        detail: 'carried_in_detail'.trParams({'when': '${timeline.year - 1}'}),
        amount: timeline.broughtForward,
      ));
    }

    for (final MonthMoney month in timeline.months) {
      if (rows.isNotEmpty) rows.add(_divider(context));

      // The month the ledger is actually showing wears the app's own colour;
      // the ones it stands on are quieter.
      final bool isCurrent =
          PersonalTransaction.monthKeyOf(month.month) == current;

      rows.add(_buildLine(
        context,
        icon: Icons.calendar_month_rounded,
        tone: isCurrent ? Colors.indigo : Colors.blueGrey,
        label: AppUi.monthLabel(month.month),
        detail: 'month_in_out'.trParams({
          'income': AppUi.amount(month.income),
          'expense': AppUi.amount(month.expense),
        }),
        amount: month.net,
        emphasised: isCurrent,
      ));
    }

    if (showSubtotal) {
      rows.add(_buildSubtotal(context, 'money_tab'.tr, wallet.money));
    }

    return _card(context, rows);
  }

  /// The dues, one person at a time — a total says how exposed the member is,
  /// a name says who to call about it.
  Widget _buildDuesCard(
    BuildContext context,
    List<PersonBalance> people,
    WalletBalance wallet, {
    required bool showSubtotal,
  }) {
    final List<Widget> rows = [];

    for (final PersonBalance person in people) {
      if (rows.isNotEmpty) rows.add(_divider(context));
      rows.add(_buildPersonLine(context, person));
    }

    if (showSubtotal) {
      rows.add(_buildSubtotal(context, 'dues_tab'.tr, wallet.dues));
    }

    return _card(context, rows);
  }

  Widget _card(BuildContext context, List<Widget> rows) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.hairline(context)),
        boxShadow: AppUi.softShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }

  Widget _divider(BuildContext context) => Divider(
        height: 1,
        indent: 64,
        endIndent: 16,
        color: AppUi.hairline(context),
      );

  Widget _buildLine(
    BuildContext context, {
    required IconData icon,
    required MaterialColor tone,
    required String label,
    required String detail,
    required double amount,
    bool emphasised = false,
  }) {
    return _line(
      context,
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppUi.tint(context, tone),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, size: 18, color: AppUi.accent(context, tone)),
      ),
      label: label,
      detail: detail,
      amount: amount,
      emphasised: emphasised,
    );
  }

  Widget _buildPersonLine(BuildContext context, PersonBalance person) {
    final bool owesMe = person.owesMe;
    final MaterialColor tone = owesMe ? Colors.green : Colors.deepOrange;
    final String initial =
        person.name.trim().isEmpty ? '?' : person.name.trim()[0].toUpperCase();

    return _line(
      context,
      leading: Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppUi.tint(context, tone),
          shape: BoxShape.circle,
        ),
        child: Text(
          initial,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: AppUi.accent(context, tone),
          ),
        ),
      ),
      label: person.name.trim().isEmpty ? 'person_name'.tr : person.name,
      detail: (owesMe ? 'debt_taken' : 'debt_given').tr,
      // Negative when it is the member who has to pay: the column reads as
      // one running set of adjustments, not as two separate totals.
      amount: owesMe ? person.balance : -person.balance.abs(),
    );
  }

  Widget _line(
    BuildContext context, {
    required Widget leading,
    required String label,
    required String detail,
    required double amount,
    bool emphasised = false,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        children: [
          leading,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: emphasised ? FontWeight.w800 : FontWeight.w600,
                    color: AppUi.body(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    height: 1.3,
                    color: AppUi.muted(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            signedFigure(amount),
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: amount == 0
                  ? AppUi.muted(context)
                  : AppUi.accent(
                      context, amount > 0 ? Colors.green : Colors.deepOrange),
            ),
          ),
        ],
      ),
    );
  }

  /// What a section came to, ruled off from the lines above it.
  Widget _buildSubtotal(BuildContext context, String label, double amount) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: AppUi.neutralSurface(context),
        border: Border(
          top: BorderSide(color: AppUi.hairline(context)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: AppUi.muted(context),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            signedFigure(amount),
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.bold,
              color: AppUi.body(context),
            ),
          ),
        ],
      ),
    );
  }

  /// The sum of everything above. No icon and a heavier rule, so it reads as
  /// the answer rather than as one more line of the question.
  Widget _buildWalletTotal(BuildContext context, WalletBalance wallet) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppUi.hairline(context), width: 1.5),
        boxShadow: AppUi.softShadow(context),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'wallet'.tr,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w900,
                color: AppUi.body(context),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            walletFigure(wallet.balance),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: -0.5,
              color: wallet.isShort
                  ? AppUi.accent(context, Colors.deepOrange)
                  : AppUi.body(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNote(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline_rounded, size: 14, color: AppUi.muted(context)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'wallet_dues_note'.tr,
            style: TextStyle(
              fontSize: 11.5,
              height: 1.45,
              color: AppUi.muted(context),
            ),
          ),
        ),
      ],
    );
  }
}

/// `৳250` / `−৳250`. A balance is not a gain, so it carries no plus.
String walletFigure(double value) =>
    '${value < 0 ? '−' : ''}${AppUi.amount(value.abs())}';

/// `+৳100` / `−৳50` / `৳0` — a line in a statement says which way it pushed.
String signedFigure(double value) {
  if (value == 0) return AppUi.amount(0);
  return '${value > 0 ? '+' : '−'}${AppUi.amount(value.abs())}';
}
