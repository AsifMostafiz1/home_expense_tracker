import 'package:cloud_firestore/cloud_firestore.dart';

/// A finer cut inside one category, made by the member — "bazar" and
/// "restaurant" inside food, say. Kept per account like the categories, and
/// referenced from transactions by document id, so a rename is one write.
///
/// [parent] is the category's key: a fixed key like `food`, or a custom
/// category's document id — every category can hold them. A name is all a
/// subcategory has; it borrows its colour from its parent wherever it shows.
class Subcategory {
  final String id;
  final String ownerPhone;
  final String parent;
  final String name;
  final DateTime? createdAt;

  /// Written on this device and not acknowledged by the server yet.
  final bool pending;

  const Subcategory({
    this.id = '',
    this.ownerPhone = '',
    this.parent = '',
    this.name = '',
    this.createdAt,
    this.pending = false,
  });

  factory Subcategory.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool pending = false,
  }) {
    return Subcategory(
      id: id,
      ownerPhone: (map['owner_phone'] ?? '').toString(),
      parent: (map['parent'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      pending: pending,
    );
  }

  Map<String, dynamic> toMap() => {
        'owner_phone': ownerPhone,
        'parent': parent,
        'name': name,
      };
}
