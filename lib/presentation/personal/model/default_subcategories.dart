import 'package:get/get.dart';

import 'subcategory.dart';

/// The starter subcategories a fresh account is dealt, one small hand per
/// fixed category — the way the house rules ship with defaults.
///
/// Dealt once and then owned outright: they are written as ordinary
/// [Subcategory] documents, so the member renames, deletes and adds to them
/// exactly as if they had typed every one in themselves. Nothing here is
/// consulted again after the deal — deleting "বাজার" does not bring it back.
///
/// Each seed is a name pair, English then Bangla; whichever language the
/// app is in when the account is dealt is the language the names land in.
class DefaultSubcategories {
  DefaultSubcategories._();

  static const Map<String, List<List<String>>> _byParent = {
    // expense
    'food': [
      ['Groceries', 'বাজার'],
      ['Restaurant', 'রেস্টুরেন্ট'],
      ['Snacks', 'নাস্তা'],
    ],
    'transport': [
      ['Bus', 'বাস'],
      ['Rickshaw', 'রিকশা'],
      ['Ride share', 'রাইড শেয়ার'],
      ['Fuel', 'জ্বালানি'],
    ],
    'shopping': [
      ['Clothes', 'পোশাক'],
      ['Electronics', 'ইলেকট্রনিকস'],
      ['Household', 'গৃহস্থালি'],
    ],
    // The utilities live here: the Bills category is retired, and the rent
    // is where those payments sit in most households' heads.
    'rent': [
      ['House rent', 'বাসা ভাড়া'],
      ['Electricity', 'বিদ্যুৎ'],
      ['Gas', 'গ্যাস'],
      ['Water', 'পানি'],
      ['Internet', 'ইন্টারনেট'],
    ],
    'health': [
      ['Medicine', 'ওষুধ'],
      ['Doctor', 'ডাক্তার'],
      ['Tests', 'টেস্ট'],
    ],
    'education': [
      ['Books', 'বই'],
      ['Tuition', 'টিউশন'],
      ['Course fee', 'কোর্স ফি'],
    ],
    'family': [
      ['Parents', 'বাবা-মা'],
      ['Children', 'সন্তান'],
      ['Gifts', 'উপহার'],
    ],
    // Entertainment rides here as a tag for the same reason the utilities
    // ride under rent — its category is retired, its spending is not.
    'other_expense': [
      ['Entertainment', 'বিনোদন'],
      ['Mobile recharge', 'মোবাইল রিচার্জ'],
      ['Donation', 'দান'],
    ],
    // income
    'salary': [
      ['Monthly salary', 'মাসিক বেতন'],
      ['Overtime', 'ওভারটাইম'],
      ['Allowance', 'ভাতা'],
    ],
    'business': [
      ['Sales', 'বিক্রি'],
      ['Profit', 'লাভ'],
    ],
    'freelance': [
      ['Project', 'প্রজেক্ট'],
      ['Client payment', 'ক্লায়েন্ট পেমেন্ট'],
    ],
    'bonus': [
      ['Festival bonus', 'উৎসব বোনাস'],
      ['Gift', 'উপহার'],
    ],
    'rent_income': [
      ['House rent', 'বাসা ভাড়া'],
      ['Shop rent', 'দোকান ভাড়া'],
    ],
    'other_income': [
      ['Cashback', 'ক্যাশব্যাক'],
      ['Refund', 'রিফান্ড'],
    ],
  };

  /// One member's full deal, named in the language their app is speaking.
  static List<Subcategory> forOwner(String ownerPhone) {
    final bool bengali = Get.locale?.languageCode == 'bn';

    return [
      for (final MapEntry<String, List<List<String>>> parent
          in _byParent.entries)
        for (final List<String> pair in parent.value)
          Subcategory(
            id: _idFor(ownerPhone, parent.key, pair[0]),
            ownerPhone: ownerPhone,
            parent: parent.key,
            name: bengali ? pair[1] : pair[0],
          ),
    ];
  }

  /// The tag a house expense wears once it is copied into the payer's own
  /// ledger — see `PersonalCategory.forHouseExpense` for the category it
  /// lands in. The house's meal spending is one recurring thing, so it all
  /// goes under one "Meal" chip inside food and a month's own bazar stays a
  /// filter away from what the house ate. The `others` type — the gas, the
  /// wifi, the rest — is not one thing, and carries no tag.
  ///
  /// Named and dealt exactly like the seeds above: whichever language the
  /// app is speaking when the first house expense is copied is the language
  /// the chip is named in, and the id is derived rather than random, so the
  /// house side writes this document once and finds it every time after.
  static Subcategory? houseTagFor(String ownerPhone, String houseType) {
    if (ownerPhone.isEmpty || houseType == 'others') return null;

    const String parent = 'food';
    return Subcategory(
      id: _idFor(ownerPhone, parent, 'Meal', prefix: 'house'),
      ownerPhone: ownerPhone,
      parent: parent,
      name: Get.locale?.languageCode == 'bn' ? 'মিল' : 'Meal',
    );
  }

  /// Deterministic, so two devices dealing the same fresh account write the
  /// same documents instead of two of each.
  static String _idFor(
    String ownerPhone,
    String parent,
    String enName, {
    String prefix = 'seed',
  }) =>
      '${prefix}_${ownerPhone}_${parent}_${enName.toLowerCase().replaceAll(' ', '_')}';
}
