import 'debt_entry.dart';
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

  /// `2026-08` back into a date, or null when the stored day was never one.
  static DateTime? monthFromKey(String key) {
    if (key.length < 7) return null;
    final int? year = int.tryParse(key.substring(0, 4));
    final int? month = int.tryParse(key.substring(5, 7));
    if (year == null || month == null || month < 1 || month > 12) return null;
    return DateTime(year, month);
  }

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

/// Everything a member is worth, as the month being looked at closes.
///
/// A running balance rather than a monthly figure: what a month does not
/// spend is still there the month after, so every entry up to and including
/// that month counts. Nothing later does — walking back to July shows July's
/// closing position, not today's. The dues are cut on the same date for the
/// same reason; a July balance sitting next to today's dues would be neither.
///
/// The dues belong in here because they are money that has been committed:
/// what is owed to the member is coming, what they owe is going, and a wallet
/// that ignored both would be wrong the moment either was settled. It is a
/// position, not the cash in a pocket — which is what the breakdown screen
/// exists to say.
///
/// The four parts are kept separate so that breakdown can show its working.
class WalletBalance {
  /// Everything recorded before this month came to.
  final double opening;

  /// What this month itself added or took away.
  final double net;

  /// Outstanding dues owed *to* the member.
  final double receivable;

  /// Outstanding dues the member owes.
  final double payable;

  const WalletBalance({
    this.opening = 0,
    this.net = 0,
    this.receivable = 0,
    this.payable = 0,
  });

  /// The money side alone — what was earned and spent, with no dues in it.
  double get money => opening + net;

  /// What the dues come to, netted across both directions.
  double get dues => receivable - payable;

  double get balance => money + dues;

  bool get isShort => balance < 0;

  bool get hasDues => receivable > 0.005 || payable > 0.005;

  static WalletBalance of(
    DateTime month,
    Iterable<PersonalTransaction> transactions, {
    Iterable<DebtEntry> debts = const <DebtEntry>[],
  }) {
    final String key = PersonalTransaction.monthKeyOf(month);
    double opening = 0;
    double net = 0;

    for (final PersonalTransaction entry in transactions) {
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

    // Each person's account is settled before it takes a side. Somebody lent
    // 1,000 who has paid 600 back is 400 still to come — not 1,000 to come
    // and 600 to go, which would inflate both totals and net out the same.
    final Map<String, double> byPerson = {};
    for (final DebtEntry entry in debts) {
      final String entryKey = entry.monthKey;
      if (entryKey.isEmpty || entryKey.compareTo(key) > 0) continue;
      byPerson[entry.personKey] =
          (byPerson[entry.personKey] ?? 0) + entry.signedAmount;
    }

    double receivable = 0;
    double payable = 0;
    for (final double balance in byPerson.values) {
      if (balance > 0.005) {
        receivable += balance;
      } else if (balance < -0.005) {
        payable += balance.abs();
      }
    }

    return WalletBalance(
      opening: opening,
      net: net,
      receivable: receivable,
      payable: payable,
    );
  }
}

/// The months a wallet balance is built out of, and the years before them.
///
/// Only the year being looked at is broken into months. Everything older is
/// one figure — what the member came into that year holding — because a
/// statement that lists every month since the ledger opened stops being
/// readable somewhere in its second year, and the month-by-month of a closed
/// year is not what somebody checking this month's position came for.
///
/// [broughtForward] plus every month here is exactly [WalletBalance.money]:
/// both are worked out by the same rule, so the breakdown adds up to the
/// figure it is breaking down.
class WalletTimeline {
  /// The year the months below belong to.
  final int year;

  /// Everything recorded before the 1st of January of [year].
  final double broughtForward;

  /// Months inside [year] up to and including the one being looked at, oldest
  /// first. That month is always present, empty or not — a statement should
  /// show the month it is about. The quiet ones before it are left out: a run
  /// of zeroes is a list to scroll past rather than anything to read.
  final List<MonthMoney> months;

  const WalletTimeline({
    required this.year,
    this.broughtForward = 0,
    this.months = const [],
  });

  /// Whether there is an older-years line to show at all. A ledger opened
  /// this year has nothing before it, and a zero row would be noise.
  bool get hasBroughtForward => broughtForward.abs() > 0.005;

  static WalletTimeline of(
    DateTime month,
    Iterable<PersonalTransaction> all,
  ) {
    final String key = PersonalTransaction.monthKeyOf(month);
    // `yyyy-MM` sorts as the calendar runs, so "before this year" is a single
    // string comparison against that year's January.
    final String yearOpens = '${month.year.toString().padLeft(4, '0')}-01';

    double broughtForward = 0;
    final Set<String> keys = {key};

    for (final PersonalTransaction entry in all) {
      final String entryKey = entry.monthKey;
      if (entryKey.isEmpty || entryKey.compareTo(key) > 0) continue;

      if (entryKey.compareTo(yearOpens) < 0) {
        broughtForward += entry.signedAmount;
      } else {
        keys.add(entryKey);
      }
    }

    final List<String> ordered = keys.toList()..sort();
    final List<MonthMoney> months = [];
    for (final String monthKey in ordered) {
      final DateTime? date = MonthMoney.monthFromKey(monthKey);
      if (date != null) months.add(MonthMoney.of(date, all));
    }

    return WalletTimeline(
      year: month.year,
      broughtForward: broughtForward,
      months: months,
    );
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
