import 'package:cloud_firestore/cloud_firestore.dart';

/// One house rule, kept in both languages.
///
/// An admin types the English and the Bangla wording together, so a rule is
/// never half-written: whichever language a member reads the app in, the rule
/// is there in that language. The fallback in [text] is for the other case —
/// a document that arrives with one side missing should still show something
/// rather than a blank line.
class HouseRuleModel {
  final String id;
  final String textEn;
  final String textBn;

  /// Where the rule sits in the list, 0-based. Firestore keeps no order of
  /// its own, so the order an admin arranges them in lives on the document.
  final int order;

  final String updatedBy;
  final DateTime? updatedAt;

  /// Written on this device and not acknowledged by the server yet.
  final bool pending;

  const HouseRuleModel({
    this.id = '',
    this.textEn = '',
    this.textBn = '',
    this.order = 0,
    this.updatedBy = '',
    this.updatedAt,
    this.pending = false,
  });

  factory HouseRuleModel.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool pending = false,
  }) {
    return HouseRuleModel(
      id: id,
      textEn: (map['text_en'] ?? '').toString(),
      textBn: (map['text_bn'] ?? '').toString(),
      order: (map['order'] as num?)?.toInt() ?? 0,
      updatedBy: (map['updated_by'] ?? '').toString(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      pending: pending,
    );
  }

  /// The stored fields only — the timestamp and the author are stamped by the
  /// repository, which is the one place that may decide them.
  Map<String, dynamic> toMap() => {
        'text_en': textEn,
        'text_bn': textBn,
        'order': order,
      };

  /// The rule as [languageCode] reads it, falling back to the other language
  /// when that side was never filled in.
  String text(String languageCode) {
    final String preferred = languageCode == 'bn' ? textBn : textEn;
    if (preferred.trim().isNotEmpty) return preferred;
    return (languageCode == 'bn' ? textEn : textBn).trim();
  }

  /// The same rule in the other language, for the muted second line — empty
  /// when there is nothing to add, including when both texts are identical.
  String secondaryText(String languageCode) {
    final String other = languageCode == 'bn' ? textEn : textBn;
    if (other.trim().isEmpty) return '';
    if (other.trim() == text(languageCode).trim()) return '';
    return other;
  }

  /// When this wording was last changed, as the number an acknowledgement is
  /// compared against. A rule whose stamp has not landed yet reads as 0, so
  /// nobody is asked to agree to a version the server has not confirmed.
  int get version => updatedAt?.millisecondsSinceEpoch ?? 0;

  HouseRuleModel copyWith({
    String? id,
    String? textEn,
    String? textBn,
    int? order,
    String? updatedBy,
    DateTime? updatedAt,
    bool? pending,
  }) {
    return HouseRuleModel(
      id: id ?? this.id,
      textEn: textEn ?? this.textEn,
      textBn: textBn ?? this.textBn,
      order: order ?? this.order,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedAt: updatedAt ?? this.updatedAt,
      pending: pending ?? this.pending,
    );
  }
}
