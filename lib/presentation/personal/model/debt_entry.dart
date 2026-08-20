import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Which way the money moved between the two people.
enum DebtFlow {
  /// Money handed over — they owe it back.
  gave,

  /// Money taken — it is owed to them.
  got,
}

/// One line of a private account kept with one other person.
///
/// A repayment is not a special kind of row: money coming back is simply a
/// [DebtFlow.got] against the same person, which is why a person's whole
/// history adds up to what is still outstanding without any row ever being
/// edited or closed.
///
/// The other person is a name typed by the owner, not a member of the house —
/// this ledger has nothing to do with who else uses the app.
class DebtEntry {
  final String id;
  final String ownerPhone;
  final String personName;

  /// Optional, and only ever the owner's own note of it — used to keep two
  /// people with the same name apart, and to offer a call button.
  final String personPhone;

  final DebtFlow flow;
  final double amount;
  final String note;

  /// `yyyy-MM-dd`, as in [PersonalTransaction].
  final String date;

  /// The time of day the money moved, as two numbers — see
  /// [PersonalTransaction.timeHour].
  final int timeHour;
  final int timeMinute;

  final DateTime? createdAt;
  final bool pending;

  const DebtEntry({
    this.id = '',
    this.ownerPhone = '',
    this.personName = '',
    this.personPhone = '',
    this.flow = DebtFlow.gave,
    this.amount = 0,
    this.note = '',
    this.date = '',
    this.timeHour = 0,
    this.timeMinute = 0,
    this.createdAt,
    this.pending = false,
  });

  bool get isGave => flow == DebtFlow.gave;

  DateTime get day => DateTime.tryParse(date) ?? DateTime.now();

  TimeOfDay get time => TimeOfDay(hour: timeHour, minute: timeMinute);

  DateTime get moment => DateTime(
        day.year,
        day.month,
        day.day,
        timeHour,
        timeMinute,
      );

  int get minuteOfDay => timeHour * 60 + timeMinute;

  /// Positive when it adds to what is owed *to* the owner.
  double get signedAmount => isGave ? amount : -amount;

  /// What groups entries into one person: the phone when there is one, the
  /// name otherwise. Case and spacing are ignored so "Rakib " and "rakib" do
  /// not become two accounts.
  String get personKey => personPhone.trim().isNotEmpty
      ? personPhone.trim()
      : personName.trim().toLowerCase();

  factory DebtEntry.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool pending = false,
  }) {
    return DebtEntry(
      id: id,
      ownerPhone: (map['owner_phone'] ?? '').toString(),
      personName: (map['person_name'] ?? '').toString(),
      personPhone: (map['person_phone'] ?? '').toString(),
      flow: (map['direction'] ?? 'gave') == 'got' ? DebtFlow.got : DebtFlow.gave,
      amount: (map['amount'] as num?)?.toDouble() ?? 0,
      note: (map['note'] ?? '').toString(),
      date: (map['date'] ?? '').toString(),
      timeHour: (map['time_hour'] as num?)?.toInt() ?? 0,
      timeMinute: (map['time_minute'] as num?)?.toInt() ?? 0,
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      pending: pending,
    );
  }

  Map<String, dynamic> toMap() => {
        'owner_phone': ownerPhone,
        'person_name': personName,
        'person_phone': personPhone,
        'direction': isGave ? 'gave' : 'got',
        'amount': amount,
        'note': note,
        'date': date,
        'time_hour': timeHour,
        'time_minute': timeMinute,
      };

  DebtEntry copyWith({
    String? personName,
    String? personPhone,
    DebtFlow? flow,
    double? amount,
    String? note,
    String? date,
    int? timeHour,
    int? timeMinute,
  }) {
    return DebtEntry(
      id: id,
      ownerPhone: ownerPhone,
      personName: personName ?? this.personName,
      personPhone: personPhone ?? this.personPhone,
      flow: flow ?? this.flow,
      amount: amount ?? this.amount,
      note: note ?? this.note,
      date: date ?? this.date,
      timeHour: timeHour ?? this.timeHour,
      timeMinute: timeMinute ?? this.timeMinute,
      createdAt: createdAt,
      pending: pending,
    );
  }
}

/// Everything owed with one person, rolled up.
class PersonBalance {
  final String key;
  final String name;
  final String phone;
  final List<DebtEntry> entries;

  const PersonBalance({
    required this.key,
    required this.name,
    required this.phone,
    required this.entries,
  });

  /// Positive: they owe the owner. Negative: the owner owes them.
  double get balance =>
      entries.fold<double>(0, (running, entry) => running + entry.signedAmount);

  double get totalGave => entries
      .where((entry) => entry.isGave)
      .fold<double>(0, (running, entry) => running + entry.amount);

  double get totalGot => entries
      .where((entry) => !entry.isGave)
      .fold<double>(0, (running, entry) => running + entry.amount);

  bool get isSettled => balance.abs() < 0.005;

  bool get owesMe => balance > 0.005;

  /// What the account came to after each entry, keyed by entry id.
  ///
  /// Walked oldest-first, which is the only order a running total means
  /// anything in — the list itself is newest-first for reading. This is what
  /// makes a repayment row legible: the row says money came in, the balance
  /// beside it says there is still something to come.
  Map<String, double> get runningBalances {
    final List<DebtEntry> chronological = List<DebtEntry>.from(entries)
      ..sort((a, b) {
        final int byDate = a.date.compareTo(b.date);
        return byDate != 0 ? byDate : a.minuteOfDay.compareTo(b.minuteOfDay);
      });

    double running = 0;
    final Map<String, double> out = {};
    for (final DebtEntry entry in chronological) {
      running += entry.signedAmount;
      out[entry.id] = running;
    }
    return out;
  }

  DateTime? get lastActivity {
    DateTime? latest;
    for (final DebtEntry entry in entries) {
      final DateTime day = entry.day;
      if (latest == null || day.isAfter(latest)) latest = day;
    }
    return latest;
  }
}
