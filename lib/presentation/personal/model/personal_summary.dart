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

/// One category's share of a month.
class CategoryTotal {
  final String category;
  final double amount;

  const CategoryTotal(this.category, this.amount);

  /// [total] is the whole side (all income, or all expense) — 0–1.
  double share(double total) => total <= 0 ? 0 : amount / total;
}
