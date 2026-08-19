import '../model/house_rule_model.dart';

abstract class HouseRulesRepository {
  /// The house rules as they stand, in the order an admin arranged them.
  Stream<List<HouseRuleModel>> watchRules();

  Future<void> addRule({
    required String textEn,
    required String textBn,
    required int order,
    required String by,
  });

  Future<void> updateRule(
    String id, {
    required String textEn,
    required String textBn,
    required String by,
  });

  Future<void> deleteRule(String id);

  /// Writes the new position of every rule that moved, in one batch.
  Future<void> saveOrder(List<HouseRuleModel> rules, {required String by});

  /// Writes the starter set at fixed ids, so running it twice cannot leave
  /// the house with two copies of every rule.
  Future<void> seedRules(List<HouseRuleModel> rules, {required String by});
}
