import 'package:flutter/material.dart';
import 'package:get/get.dart';

import 'custom_category.dart';

/// One bucket a personal entry can fall into.
///
/// The key is what Firestore stores; the label is looked up at read time, so
/// a ledger written in Bangla reads in English the moment the app is switched
/// over. An entry whose key is not in this list still shows — see [of] — which
/// is what keeps an older document readable after this list changes.
///
/// Two kinds share this shape. The fixed ones below are the app's own, the
/// same for everybody and not removable. The member's own live in Firestore
/// as [CustomCategory] rows and reach here through [register]: the controller
/// feeds every snapshot in, and [of] then resolves a custom key anywhere a
/// fixed one resolves — the breakdowns, the entry rows, the picker.
class PersonalCategory {
  final String key;
  final IconData icon;
  final MaterialColor color;

  /// The member's own name for a custom category. A fixed category has none
  /// and is named through translation instead.
  final String? custom;

  const PersonalCategory(this.key, this.icon, this.color, {this.custom});

  String get label => custom ?? 'cat_$key'.tr;

  bool get isCustom => custom != null;

  static const List<PersonalCategory> expense = [
    PersonalCategory('food', Icons.restaurant_rounded, Colors.orange),
    PersonalCategory('transport', Icons.directions_bus_rounded, Colors.blue),
    PersonalCategory('shopping', Icons.shopping_bag_rounded, Colors.pink),
    PersonalCategory('rent', Icons.home_rounded, Colors.brown),
    PersonalCategory('health', Icons.favorite_rounded, Colors.red),
    PersonalCategory('education', Icons.school_rounded, Colors.indigo),
    PersonalCategory('family', Icons.family_restroom_rounded, Colors.purple),
    PersonalCategory('other_expense', Icons.more_horiz_rounded, Colors.blueGrey),
  ];

  static const List<PersonalCategory> income = [
    PersonalCategory('salary', Icons.account_balance_wallet_rounded, Colors.green),
    PersonalCategory('business', Icons.storefront_rounded, Colors.teal),
    PersonalCategory('freelance', Icons.laptop_mac_rounded, Colors.blue),
    PersonalCategory('bonus', Icons.card_giftcard_rounded, Colors.amber),
    PersonalCategory('rent_income', Icons.home_work_rounded, Colors.brown),
    PersonalCategory('other_income', Icons.more_horiz_rounded, Colors.blueGrey),
  ];

  /// Retired from the picker but not from history: entries filed under these
  /// while they were on offer keep their icon and label. New entries cannot
  /// choose them.
  static const List<PersonalCategory> _retired = [
    PersonalCategory('bills', Icons.receipt_long_rounded, Colors.teal),
    PersonalCategory('entertainment', Icons.movie_rounded, Colors.deepPurple),
    PersonalCategory('savings', Icons.savings_rounded, Colors.green),
  ];

  static const PersonalCategory unknown =
      PersonalCategory('uncategorised', Icons.label_outline_rounded, Colors.grey);

  /// The signed-in member's own categories, keyed by document id — what [of]
  /// falls through to after the fixed lists. Replaced whole on every
  /// snapshot, so a rename or a delete elsewhere reads right here at once.
  static Map<String, PersonalCategory> _custom = const {};

  static List<PersonalCategory> _customExpense = const [];
  static List<PersonalCategory> _customIncome = const [];

  /// How the member arranged their picker — see [CategoryOrder]. Empty until
  /// their order document lands, which reads as the default arrangement.
  static CategoryOrder _order = const CategoryOrder();

  static void register(List<CustomCategory> categories) {
    _custom = {
      for (final CustomCategory category in categories)
        category.id: category.toCategory(),
    };
    _customExpense = [
      for (final CustomCategory category in categories)
        if (!category.isIncome) category.toCategory(),
    ];
    _customIncome = [
      for (final CustomCategory category in categories)
        if (category.isIncome) category.toCategory(),
    ];
  }

  static void registerOrder(CategoryOrder order) => _order = order;

  /// Empties everything [register] and [registerOrder] were fed. Called when
  /// the controller that fed them closes: the registry is the signed-in
  /// member's, and it must not outlive their sign-in — the next account
  /// would read this one's categories until their own snapshot landed.
  static void clearRegistry() {
    _custom = const {};
    _customExpense = const [];
    _customIncome = const [];
    _order = const CategoryOrder();
  }

  static List<PersonalCategory> forIncome(bool isIncome) =>
      isIncome ? income : expense;

  /// What the entry sheet offers: the fixed list with the member's own after
  /// it, rearranged to however the member last dragged them.
  ///
  /// The saved order leads and everything it has not met follows in default
  /// order — so a category made after the last drag still shows, at the end,
  /// and a key whose category is gone is silently passed over.
  static List<PersonalCategory> pickerFor(bool isIncome) {
    final Map<String, PersonalCategory> byKey = {
      for (final PersonalCategory category in forIncome(isIncome))
        category.key: category,
      for (final PersonalCategory category
          in isIncome ? _customIncome : _customExpense)
        category.key: category,
    };

    final List<PersonalCategory> arranged = [];
    for (final String key in _order.forIncome(isIncome)) {
      final PersonalCategory? category = byKey.remove(key);
      if (category != null) arranged.add(category);
    }
    arranged.addAll(byKey.values);
    return arranged;
  }

  /// The bucket a house expense lands in when it is copied into the payer's
  /// own ledger. The house's `expense` type is the shared groceries, so it is
  /// food; `others` is the gas, the wifi and the rest, which is not.
  static String forHouseExpense(String houseType) =>
      houseType == 'others' ? 'other_expense' : 'food';

  /// The category behind a stored key, whichever side it belongs to.
  static PersonalCategory of(String key) {
    for (final PersonalCategory category in expense) {
      if (category.key == key) return category;
    }
    for (final PersonalCategory category in income) {
      if (category.key == key) return category;
    }
    for (final PersonalCategory category in _retired) {
      if (category.key == key) return category;
    }
    return _custom[key] ?? unknown;
  }
}
