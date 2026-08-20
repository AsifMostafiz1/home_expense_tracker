import 'package:flutter/material.dart';
import 'package:get/get.dart';

/// One bucket a personal entry can fall into.
///
/// The key is what Firestore stores; the label is looked up at read time, so
/// a ledger written in Bangla reads in English the moment the app is switched
/// over. An entry whose key is not in this list still shows — see [of] — which
/// is what keeps an older document readable after this list changes.
class PersonalCategory {
  final String key;
  final IconData icon;
  final MaterialColor color;

  const PersonalCategory(this.key, this.icon, this.color);

  String get label => 'cat_$key'.tr;

  static const List<PersonalCategory> expense = [
    PersonalCategory('food', Icons.restaurant_rounded, Colors.orange),
    PersonalCategory('transport', Icons.directions_bus_rounded, Colors.blue),
    PersonalCategory('shopping', Icons.shopping_bag_rounded, Colors.pink),
    PersonalCategory('bills', Icons.receipt_long_rounded, Colors.teal),
    PersonalCategory('rent', Icons.home_rounded, Colors.brown),
    PersonalCategory('health', Icons.favorite_rounded, Colors.red),
    PersonalCategory('education', Icons.school_rounded, Colors.indigo),
    PersonalCategory('family', Icons.family_restroom_rounded, Colors.purple),
    PersonalCategory('entertainment', Icons.movie_rounded, Colors.deepPurple),
    PersonalCategory('savings', Icons.savings_rounded, Colors.green),
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

  static const PersonalCategory unknown =
      PersonalCategory('uncategorised', Icons.label_outline_rounded, Colors.grey);

  static List<PersonalCategory> forIncome(bool isIncome) =>
      isIncome ? income : expense;

  /// The category behind a stored key, whichever side it belongs to.
  static PersonalCategory of(String key) {
    for (final PersonalCategory category in expense) {
      if (category.key == key) return category;
    }
    for (final PersonalCategory category in income) {
      if (category.key == key) return category;
    }
    return unknown;
  }
}
