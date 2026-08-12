import 'package:cloud_firestore/cloud_firestore.dart';

double _toDouble(dynamic value) => (value as num?)?.toDouble() ?? 0.0;

/// One member's share of the house rent for a month.
///
/// Rent is the only bill that is not divided evenly — rooms differ, so the
/// amounts do too. The name is stored alongside the phone number so an old
/// month still reads correctly after someone leaves the house.
class RentShare {
  final String phone;
  final String name;
  final double amount;

  const RentShare({
    required this.phone,
    required this.name,
    this.amount = 0,
  });

  factory RentShare.fromMap(Map<String, dynamic> map) {
    return RentShare(
      phone: map['phone'] ?? '',
      name: map['name'] ?? '',
      amount: _toDouble(map['amount']),
    );
  }

  Map<String, dynamic> toMap() => {
        'phone': phone,
        'name': name,
        'amount': amount,
      };

  RentShare copyWith({String? name, double? amount}) => RentShare(
        phone: phone,
        name: name ?? this.name,
        amount: amount ?? this.amount,
      );
}

/// Proof that a member's share for the month has been handed over.
///
/// The amount is stamped at the moment it is collected, so a later edit to the
/// bills cannot rewrite what was actually taken.
class SettlementRecord {
  final double amount;
  final String by;
  final DateTime? at;

  const SettlementRecord({
    this.amount = 0,
    this.by = '',
    this.at,
  });

  factory SettlementRecord.fromMap(Map<String, dynamic> map) {
    return SettlementRecord(
      amount: _toDouble(map['amount']),
      by: map['by'] ?? '',
      at: (map['at'] as Timestamp?)?.toDate(),
    );
  }
}

/// The house bills for a single month.
///
/// Stored under a deterministic `YYYY-MM` document id: a month can only exist
/// once, "load last month" is a single read, and the id alone sorts the list
/// chronologically.
///
/// Only [homeRent] is split per member. Utilities, wifi and other costs are
/// shared equally between everyone listed in [rentShares] — that list is the
/// month's roster, kept as a snapshot so past months are never rewritten by
/// today's member list.
class MonthlyBillModel {
  final String id;
  final int year;
  final int month;

  final double homeRent;
  final List<RentShare> rentShares;

  final double waterBill;
  final double securityBill;
  final double electricityBill;
  final double cleaningBill;

  final double wifiBill;
  final double otherCost;
  final String otherNote;

  /// Who has already paid up, keyed by phone. Written only by the collect
  /// action — never by the bill form, which is why it is absent from [toMap].
  final Map<String, SettlementRecord> settlements;

  final String updatedBy;
  final DateTime? updatedAt;

  MonthlyBillModel({
    required this.id,
    required this.year,
    required this.month,
    this.homeRent = 0,
    this.rentShares = const [],
    this.waterBill = 0,
    this.securityBill = 0,
    this.electricityBill = 0,
    this.cleaningBill = 0,
    this.wifiBill = 0,
    this.otherCost = 0,
    this.otherNote = '',
    this.settlements = const {},
    this.updatedBy = '',
    this.updatedAt,
  });

  /// `2026-08` — the document id for the month [date] falls in.
  static String monthKeyOf(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}';

  DateTime get monthDate => DateTime(year, month);

  double get utilitiesTotal =>
      waterBill + securityBill + electricityBill + cleaningBill;

  /// Everything divided equally: utilities, wifi and other costs.
  double get sharedTotal => utilitiesTotal + wifiBill + otherCost;

  double get grandTotal => homeRent + sharedTotal;

  double get assignedRent =>
      rentShares.fold(0.0, (total, share) => total + share.amount);

  int get memberCount => rentShares.length;

  double get perHeadShared => memberCount == 0 ? 0 : sharedTotal / memberCount;

  /// What one member owes for the month: their own rent plus the equal share.
  double totalFor(RentShare share) => share.amount + perHeadShared;

  bool get isEmpty => grandTotal == 0;

  bool isSettled(String phone) => settlements.containsKey(phone);

  /// Counted against the month's own roster: someone who only shows up in the
  /// meal data can still be collected from, but they are not one of the people
  /// this month's bills were split between.
  int get settledCount =>
      rentShares.where((share) => settlements.containsKey(share.phone)).length;

  int get pendingCount => memberCount - settledCount;

  bool get isFullySettled => memberCount > 0 && pendingCount == 0;

  /// A copy carrying one changed settlement — pass null to clear it.
  MonthlyBillModel withSettlement(String phone, SettlementRecord? record) {
    final Map<String, SettlementRecord> next = Map.of(settlements);
    if (record == null) {
      next.remove(phone);
    } else {
      next[phone] = record;
    }

    return MonthlyBillModel(
      id: id,
      year: year,
      month: month,
      homeRent: homeRent,
      rentShares: rentShares,
      waterBill: waterBill,
      securityBill: securityBill,
      electricityBill: electricityBill,
      cleaningBill: cleaningBill,
      wifiBill: wifiBill,
      otherCost: otherCost,
      otherNote: otherNote,
      settlements: next,
      updatedBy: updatedBy,
      updatedAt: updatedAt,
    );
  }

  factory MonthlyBillModel.fromMap(String id, Map<String, dynamic> map) {
    final List<String> parts = id.split('-');

    return MonthlyBillModel(
      id: id,
      year: (map['year'] as num?)?.toInt() ??
          int.tryParse(parts.first) ??
          DateTime.now().year,
      month: (map['month'] as num?)?.toInt() ??
          (parts.length > 1 ? int.tryParse(parts[1]) ?? 1 : 1),
      homeRent: _toDouble(map['home_rent']),
      rentShares: ((map['rent_shares'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => RentShare.fromMap(Map<String, dynamic>.from(e)))
          .toList(),
      waterBill: _toDouble(map['water_bill']),
      securityBill: _toDouble(map['security_bill']),
      electricityBill: _toDouble(map['electricity_bill']),
      cleaningBill: _toDouble(map['cleaning_bill']),
      wifiBill: _toDouble(map['wifi_bill']),
      otherCost: _toDouble(map['other_cost']),
      otherNote: map['other_note'] ?? '',
      settlements: ((map['settlements'] as Map?) ?? {}).map(
        (key, value) => MapEntry(
          key.toString(),
          SettlementRecord.fromMap(
            Map<String, dynamic>.from(value as Map? ?? {}),
          ),
        ),
      ),
      updatedBy: map['updated_by'] ?? '',
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  /// Deliberately without `settlements`: the bill form builds this map, and a
  /// month saved from the form must not wipe who has already paid. Collections
  /// are written by their own merge, from the details screen.
  Map<String, dynamic> toMap() => {
        'month_key': id,
        'year': year,
        'month': month,
        'home_rent': homeRent,
        'rent_shares': rentShares.map((share) => share.toMap()).toList(),
        'water_bill': waterBill,
        'security_bill': securityBill,
        'electricity_bill': electricityBill,
        'cleaning_bill': cleaningBill,
        'wifi_bill': wifiBill,
        'other_cost': otherCost,
        'other_note': otherNote,
        // Denormalised so a summary row never has to add the parts back up.
        'shared_total': sharedTotal,
        'grand_total': grandTotal,
        'per_head_shared': perHeadShared,
        'member_count': memberCount,
      };
}
