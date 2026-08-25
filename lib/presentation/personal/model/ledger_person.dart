import 'package:cloud_firestore/cloud_firestore.dart';

/// Somebody an account is kept with, saved on their own.
///
/// A person used to exist only as a side effect of the first entry against
/// them, so the list could not be set up ahead of time — adding "Bou" meant
/// recording a fifty-thousand-taka loan in the same breath. This is the
/// person by themselves: a name, and a phone when there is one. What passes
/// between the two of them is still [DebtEntry], added from inside the
/// account afterwards.
class LedgerPerson {
  final String id;
  final String ownerPhone;
  final String name;

  /// Optional, and the owner's own note of it — used to keep two people with
  /// the same name apart, and to offer a call button.
  final String phone;

  final DateTime? createdAt;
  final bool pending;

  const LedgerPerson({
    this.id = '',
    this.ownerPhone = '',
    this.name = '',
    this.phone = '',
    this.createdAt,
    this.pending = false,
  });

  /// The same rule [DebtEntry.personKey] uses — the phone when there is one,
  /// the folded name otherwise — which is what makes a saved person and their
  /// entries one row rather than two.
  String get key => phone.trim().isNotEmpty
      ? phone.trim()
      : name.trim().toLowerCase();

  factory LedgerPerson.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool pending = false,
  }) {
    return LedgerPerson(
      id: id,
      ownerPhone: (map['owner_phone'] ?? '').toString(),
      name: (map['person_name'] ?? '').toString(),
      phone: (map['person_phone'] ?? '').toString(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      pending: pending,
    );
  }

  Map<String, dynamic> toMap() => {
        'owner_phone': ownerPhone,
        'person_name': name,
        'person_phone': phone,
      };
}
