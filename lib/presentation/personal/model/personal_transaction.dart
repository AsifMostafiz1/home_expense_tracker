import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
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

  /// Where the row came from. Empty for one the member typed in themselves;
  /// [sourceHouse] for the copy of a shared house expense, which is written
  /// and removed by the house screen and is read-only here.
  final String source;

  /// The day the money moved, as `yyyy-MM-dd` — the same shape the meal
  /// documents use, so a month is a string comparison rather than a range
  /// query needing its own index.
  final String date;

  /// The time of day it happened, kept as two numbers the way the house
  /// expenses keep theirs — a `TimeOfDay` has no storage form of its own.
  final int timeHour;
  final int timeMinute;

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
    this.timeHour = 0,
    this.timeMinute = 0,
    this.source = '',
    this.createdAt,
    this.pending = false,
  });

  /// A row that belongs to the house expense screen — the member paid for the
  /// house, so it counts against their own money too, but the entry itself is
  /// owned over there. Its document id is the house expense's own id, so an
  /// edit or a delete there reaches this copy without a lookup.
  static const String sourceHouse = 'house';

  bool get isIncome => flow == MoneyFlow.income;

  bool get isFromHouse => source == sourceHouse;

  DateTime get day => DateTime.tryParse(date) ?? DateTime.now();

  TimeOfDay get time => TimeOfDay(hour: timeHour, minute: timeMinute);

  /// Day and clock as one value — what orders two entries made on the same
  /// day, and what a picker starts from when the entry is opened again.
  DateTime get moment => DateTime(
        day.year,
        day.month,
        day.day,
        timeHour,
        timeMinute,
      );

  /// Minutes since midnight, for sorting within a day.
  int get minuteOfDay => timeHour * 60 + timeMinute;

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
      timeHour: (map['time_hour'] as num?)?.toInt() ?? 0,
      timeMinute: (map['time_minute'] as num?)?.toInt() ?? 0,
      source: (map['source'] ?? '').toString(),
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
        'time_hour': timeHour,
        'time_minute': timeMinute,
        'source': source,
      };

  PersonalTransaction copyWith({
    String? id,
    MoneyFlow? flow,
    double? amount,
    String? category,
    String? note,
    String? date,
    int? timeHour,
    int? timeMinute,
  }) {
    return PersonalTransaction(
      id: id ?? this.id,
      ownerPhone: ownerPhone,
      flow: flow ?? this.flow,
      amount: amount ?? this.amount,
      category: category ?? this.category,
      note: note ?? this.note,
      date: date ?? this.date,
      timeHour: timeHour ?? this.timeHour,
      timeMinute: timeMinute ?? this.timeMinute,
      source: source,
      createdAt: createdAt,
      pending: pending,
    );
  }
}
