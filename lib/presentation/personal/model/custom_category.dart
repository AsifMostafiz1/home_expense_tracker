import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'personal_category.dart';
import 'personal_transaction.dart';

/// A category the member made for themselves, kept per account the way their
/// transactions are — no other member sees it, and it sits beside the fixed
/// list in the picker.
///
/// The transaction rows reference it by its document id, so a rename is one
/// write to this document and every entry follows; only a delete has to touch
/// the rows, and those move to the fixed "other" bucket of their side.
class CustomCategory {
  final String id;
  final String ownerPhone;
  final String name;
  final MoneyFlow flow;
  final String iconKey;
  final String colorKey;
  final DateTime? createdAt;

  /// Written on this device and not acknowledged by the server yet.
  final bool pending;

  const CustomCategory({
    this.id = '',
    this.ownerPhone = '',
    this.name = '',
    this.flow = MoneyFlow.expense,
    this.iconKey = '',
    this.colorKey = '',
    this.createdAt,
    this.pending = false,
  });

  bool get isIncome => flow == MoneyFlow.income;

  IconData get icon => icons[iconKey] ?? Icons.label_rounded;

  MaterialColor get color => colors[colorKey] ?? Colors.blueGrey;

  /// The shape the rest of the module speaks — same fields as a fixed
  /// category, with the member's own name standing in for a translation.
  PersonalCategory toCategory() =>
      PersonalCategory(id, icon, color, custom: name);

  /// The icons on offer when making one. Stored by key rather than by code
  /// point: a code point out of the database defeats icon tree-shaking, and a
  /// key an old app version does not know still falls back to something.
  static const Map<String, IconData> icons = {
    'label': Icons.label_rounded,
    'cart': Icons.shopping_cart_rounded,
    'cafe': Icons.local_cafe_rounded,
    'gift': Icons.card_giftcard_rounded,
    'phone': Icons.smartphone_rounded,
    'wifi': Icons.wifi_rounded,
    'bolt': Icons.bolt_rounded,
    'water': Icons.water_drop_rounded,
    'gas': Icons.local_fire_department_rounded,
    'fuel': Icons.local_gas_station_rounded,
    'repair': Icons.build_rounded,
    'pet': Icons.pets_rounded,
    'fitness': Icons.fitness_center_rounded,
    'medicine': Icons.medication_rounded,
    'travel': Icons.flight_rounded,
    'movie': Icons.movie_rounded,
    'game': Icons.sports_esports_rounded,
    'music': Icons.music_note_rounded,
    'book': Icons.menu_book_rounded,
    'clothes': Icons.checkroom_rounded,
    'beauty': Icons.face_retouching_natural_rounded,
    'charity': Icons.volunteer_activism_rounded,
    'savings': Icons.savings_rounded,
    'bank': Icons.account_balance_rounded,
    'card': Icons.credit_card_rounded,
    'work': Icons.work_rounded,
    'star': Icons.star_rounded,
  };

  /// The colours on offer — the module's own palette, so a custom chip sits
  /// beside the fixed ones without looking like a guest.
  static const Map<String, MaterialColor> colors = {
    'orange': Colors.orange,
    'deepOrange': Colors.deepOrange,
    'red': Colors.red,
    'pink': Colors.pink,
    'purple': Colors.purple,
    'deepPurple': Colors.deepPurple,
    'indigo': Colors.indigo,
    'blue': Colors.blue,
    'cyan': Colors.cyan,
    'teal': Colors.teal,
    'green': Colors.green,
    'lightGreen': Colors.lightGreen,
    'amber': Colors.amber,
    'brown': Colors.brown,
    'blueGrey': Colors.blueGrey,
  };

  factory CustomCategory.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool pending = false,
  }) {
    return CustomCategory(
      id: id,
      ownerPhone: (map['owner_phone'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      flow: (map['type'] ?? 'expense') == 'income'
          ? MoneyFlow.income
          : MoneyFlow.expense,
      iconKey: (map['icon'] ?? '').toString(),
      colorKey: (map['color'] ?? '').toString(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      pending: pending,
    );
  }

  Map<String, dynamic> toMap() => {
        'owner_phone': ownerPhone,
        'name': name,
        'type': isIncome ? 'income' : 'expense',
        'icon': iconKey,
        'color': colorKey,
      };

  CustomCategory copyWith({
    String? name,
    String? iconKey,
    String? colorKey,
  }) {
    return CustomCategory(
      id: id,
      ownerPhone: ownerPhone,
      name: name ?? this.name,
      flow: flow,
      iconKey: iconKey ?? this.iconKey,
      colorKey: colorKey ?? this.colorKey,
      createdAt: createdAt,
      pending: pending,
    );
  }
}

/// The order one member keeps their picker in, both sides in one document —
/// a drag writes the whole arrangement, so half an arrangement can never
/// land.
///
/// Keys only, not categories: a key whose category is gone is skipped at
/// read time, and a category the order has never met — a fixed one shipped
/// later, a custom one just made — simply follows at the end. So the lists
/// never need cleaning up.
class CategoryOrder {
  final List<String> expense;
  final List<String> income;

  /// The subcategory arrangements, one list of ids per parent key. A parent
  /// that was never dragged is simply absent and keeps its default order.
  final Map<String, List<String>> subs;

  /// Whether this account has been dealt its starter subcategories. Kept on
  /// the same document so no extra read or listener is needed to know.
  final bool subsSeeded;

  /// True when this snapshot came out of the local cache rather than the
  /// server. Not stored — it is about the read, not the record. The seeding
  /// check refuses to act on it: a fresh install with no cache reads as
  /// "never seeded", and acting on that would deal a second hand to an
  /// account that was seeded and then pruned on another device.
  final bool fromCache;

  const CategoryOrder({
    this.expense = const [],
    this.income = const [],
    this.subs = const {},
    this.subsSeeded = false,
    this.fromCache = false,
  });

  List<String> forIncome(bool isIncome) => isIncome ? income : expense;

  List<String> subsOf(String parent) => subs[parent] ?? const [];

  CategoryOrder withSide(bool isIncome, List<String> keys) => CategoryOrder(
        expense: isIncome ? expense : keys,
        income: isIncome ? keys : income,
        subs: subs,
        subsSeeded: subsSeeded,
        fromCache: fromCache,
      );

  CategoryOrder withSubs(String parent, List<String> ids) => CategoryOrder(
        expense: expense,
        income: income,
        subs: {...subs, parent: ids},
        subsSeeded: subsSeeded,
        fromCache: fromCache,
      );

  factory CategoryOrder.fromMap(
    Map<String, dynamic>? map, {
    bool fromCache = false,
  }) {
    if (map == null) return CategoryOrder(fromCache: fromCache);
    List<String> read(dynamic value) => [
          for (final dynamic key in (value as List<dynamic>? ?? const []))
            key.toString(),
        ];
    return CategoryOrder(
      expense: read(map['expense']),
      income: read(map['income']),
      subs: {
        for (final MapEntry<String, dynamic> entry
            in ((map['subs'] as Map<String, dynamic>?) ?? const {}).entries)
          entry.key: read(entry.value),
      },
      subsSeeded: map['subs_seeded'] == true,
      fromCache: fromCache,
    );
  }

  /// The arrangements alone — the seeded flag is written by the seeding
  /// batch and must not be dragged along by every drag of a chip.
  Map<String, dynamic> toMap() =>
      {'expense': expense, 'income': income, 'subs': subs};
}
