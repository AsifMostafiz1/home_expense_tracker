import 'personal_transaction.dart';

/// One month's money, in and out.
class MonthMoney {
  final DateTime month;
  final double income;
  final double expense;

  const MonthMoney({
    required this.month,
    this.income = 0,
    this.expense = 0,
  });

  double get net => income - expense;

  bool get isEmpty => income == 0 && expense == 0;

  /// Whichever side is bigger — what a bar chart has to scale against.
  double get peak => income > expense ? income : expense;

  /// How much of what came in was kept, 0–1. Meaningless without income, and
  /// negative when more went out than came in, so it is clamped for display.
  double get savedShare {
    if (income <= 0) return 0;
    return (net / income).clamp(0.0, 1.0);
  }

  /// What went out as a share of what came in — 1.2 is a fifth more spent
  /// than earned. Zero without income, where [overspend] is the whole story
  /// and a ratio would divide by nothing.
  double get spentShare => income <= 0 ? 0 : expense / income;

  /// What was spent past the end of what came in. Zero for a month that
  /// stayed inside its income.
  double get overspend => expense > income ? expense - income : 0;

  bool get isOverspent => overspend > 0;

  static MonthMoney of(DateTime month, Iterable<PersonalTransaction> all) {
    final String key = PersonalTransaction.monthKeyOf(month);
    double income = 0;
    double expense = 0;

    for (final PersonalTransaction entry in all) {
      if (entry.monthKey != key) continue;
      if (entry.isIncome) {
        income += entry.amount;
      } else {
        expense += entry.amount;
      }
    }

    return MonthMoney(month: month, income: income, expense: expense);
  }
}

/// What is left in hand, and the month that last moved it.
///
/// A running balance rather than a monthly figure: what a month does not
/// spend is still there the month after, so every entry up to and including
/// the month being looked at counts. Nothing later does — walking back to
/// July shows July's closing balance, not today's.
///
/// [opening] and [net] are kept apart so the card can show its working:
/// carried in, plus what came in, less what went out.
class WalletBalance {
  /// Everything recorded before this month came to.
  final double opening;

  /// What this month itself added or took away.
  final double net;

  const WalletBalance({this.opening = 0, this.net = 0});

  double get balance => opening + net;

  bool get isShort => balance < 0;

  static WalletBalance of(DateTime month, Iterable<PersonalTransaction> all) {
    final String key = PersonalTransaction.monthKeyOf(month);
    double opening = 0;
    double net = 0;

    for (final PersonalTransaction entry in all) {
      final String entryKey = entry.monthKey;
      // A row with no readable date belongs to no month, so it cannot be
      // placed either side of this one.
      if (entryKey.isEmpty) continue;

      // `yyyy-MM` sorts the same way the calendar runs, so which side of the
      // month a row falls on is a string comparison.
      final int side = entryKey.compareTo(key);
      if (side > 0) continue;

      if (side < 0) {
        opening += entry.signedAmount;
      } else {
        net += entry.signedAmount;
      }
    }

    return WalletBalance(opening: opening, net: net);
  }
}

/// One day of the ledger: what was recorded that day, and what it came to.
///
/// The month's list is grouped rather than flat for the same reason the house
/// expense screen groups its own — a run of entries reads as "what happened on
/// the 20th", not as a dozen unrelated lines. A day is the unit people
/// remember spending in.
class MoneyDay {
  final DateTime date;

  /// That day's entries, latest first.
  final List<PersonalTransaction> entries;

  const MoneyDay({required this.date, this.entries = const []});

  double get income => entries
      .where((entry) => entry.isIncome)
      .fold<double>(0, (sum, entry) => sum + entry.amount);

  double get expense => entries
      .where((entry) => !entry.isIncome)
      .fold<double>(0, (sum, entry) => sum + entry.amount);

  /// What the day came to. Usually all spending, so usually negative — but a
  /// day with earnings in it has to be able to end up either way.
  double get net => income - expense;

  /// Groups [entries] by the day they happened, newest day first.
  ///
  /// Sorted here rather than trusted from the caller: the repository already
  /// hands its list over in this order, and a grouping that silently depended
  /// on that would break the first time somebody fed it anything else.
  static List<MoneyDay> group(Iterable<PersonalTransaction> entries) {
    final Map<String, List<PersonalTransaction>> byDay = {};
    for (final PersonalTransaction entry in entries) {
      byDay.putIfAbsent(entry.date, () => <PersonalTransaction>[]).add(entry);
    }

    final List<MoneyDay> days = [];
    for (final List<PersonalTransaction> items in byDay.values) {
      // Within a day, the clock — so the order matches the order things
      // happened in, latest at the top.
      items.sort((a, b) => b.minuteOfDay.compareTo(a.minuteOfDay));
      days.add(MoneyDay(
        date: items.first.day,
        entries: List<PersonalTransaction>.unmodifiable(items),
      ));
    }

    days.sort((a, b) => b.date.compareTo(a.date));
    return days;
  }
}

/// One category's share of a month.
class CategoryTotal {
  final String category;
  final double amount;

  const CategoryTotal(this.category, this.amount);

  /// [total] is the whole side (all income, or all expense) — 0–1.
  double share(double total) => total <= 0 ? 0 : amount / total;
}
