import 'house_rule_model.dart';

/// The rules a house starts with, offered on the empty screen.
///
/// Data, not translations: once seeded these live in Firestore like any other
/// rule, and an admin is free to reword, reorder or remove them. The ids are
/// fixed so seeding twice rewrites the same seven documents instead of
/// stacking a second copy on top.
const List<HouseRuleModel> kDefaultHouseRules = [
  HouseRuleModel(
    id: 'seed_rent',
    order: 0,
    textEn: 'Pay the house rent by the 10th of every month.',
    textBn: 'প্রতি মাসের ১০ তারিখের মধ্যে বাসা ভাড়া পরিশোধ করতে হবে।',
  ),
  HouseRuleModel(
    id: 'seed_house_clean',
    order: 1,
    textEn: 'Keep the house clean and tidy.',
    textBn: 'বাসা পরিষ্কার-পরিচ্ছন্ন রাখতে হবে।',
  ),
  HouseRuleModel(
    id: 'seed_washroom',
    order: 2,
    textEn: 'Leave the washroom clean after every use.',
    textBn: 'ব্যবহারের পর ওয়াশরুম পরিষ্কার রাখতে হবে।',
  ),
  HouseRuleModel(
    id: 'seed_balcony',
    order: 3,
    textEn: 'Keep the balcony clean.',
    textBn: 'বেলকনি পরিষ্কার রাখতে হবে।',
  ),
  HouseRuleModel(
    id: 'seed_bazar',
    order: 4,
    textEn: 'Do the bazar when it is your turn.',
    textBn: 'নিজের পালা অনুযায়ী বাজার করতে হবে।',
  ),
  HouseRuleModel(
    id: 'seed_power',
    order: 5,
    textEn: 'Do not leave lights and fans running for no reason.',
    textBn: 'অযথা লাইট-ফ্যান চালু রাখবেন না।',
  ),
  HouseRuleModel(
    id: 'seed_app_entry',
    order: 6,
    textEn: 'Add your meals and expenses to the app on time.',
    textBn: 'সময়মতো অ্যাপে মিল ও খরচ যোগ করবেন।',
  ),
];
