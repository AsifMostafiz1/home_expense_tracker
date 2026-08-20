import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

/// Which way the money went.
enum MoneyFlow { income, expense }

/// One line in a member's own ledger — money they earned or money they spent.
///
/// Nothing here touches the house: no meals, no shared expenses, no other
/// member. Every document carries the owner's phone and is only ever read
/// back with that filter.
class PersonalTransaction {
  final String id;
  final String ownerPhone;
  final MoneyFlow flow;
  final double amount;
  final String category;
  final String note;

  /// The day the money moved, as `yyyy-MM-dd` — the same shape the meal
  /// documents use, so a month is a string comparison rather than a range
  /// query needing its own index.
  final String date;

  final DateTime? createdAt;

  /// Written on this device and not acknowledged by the server yet.
  final bool pending;

  const PersonalTransaction({
    this.id = '',
    this.ownerPhone = '',
    this.flow = MoneyFlow.expense,
    this.amount = 0,
    this.category = '',
    this.note = '',
    this.date = '',
    this.createdAt,
    this.pending = false,
  });

  bool get isIncome => flow == MoneyFlow.income;

  DateTime get day => DateTime.tryParse(date) ?? DateTime.now();

  /// `2026-08` — what the month filters and the trend chart group on.
  String get monthKey => date.length >= 7 ? date.substring(0, 7) : '';

  /// Signed, so a list of these can simply be summed.
  double get signedAmount => isIncome ? amount : -amount;

  static String keyOf(DateTime date) => DateFormat('yyyy-MM-dd').format(date);

  static String monthKeyOf(DateTime month) => DateFormat('yyyy-MM').format(month);

  factory PersonalTransaction.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool pending = false,
  }) {
    return PersonalTransaction(
      id: id,
      ownerPhone: (map['owner_phone'] ?? '').toString(),
      flow: (map['type'] ?? 'expense') == 'income'
          ? MoneyFlow.income
          : MoneyFlow.expense,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      category: (map['category'] ?? '').toString(),
      note: (map['note'] ?? '').toString(),
      date: (map['date'] ?? '').toString(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      pending: pending,
    );
  }

  Map<String, dynamic> toMap() => {
        'owner_phone': ownerPhone,
        'type': isIncome ? 'income' : 'expense',
        'amount': amount,
        'category': category,
        'note': note,
        'date': date,
      };

  PersonalTransaction copyWith({
    String? id,
    MoneyFlow? flow,
    double? amount,
    String? category,
    String? note,
    String? date,
  }) {
    return PersonalTransaction(
      id: id ?? this.id,
      ownerPhone: ownerPhone,
      flow: flow ?? this.flow,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      note: note ?? this.note,
      date: date ?? this.date,
      createdAt: createdAt,
      pending: pending,
    );
  }
}
