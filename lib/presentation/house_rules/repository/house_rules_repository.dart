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
  ///
  /// Positions only: moving a rule is not a change to what it says, so this
  /// must leave the wording stamp alone — see [fetchAcks].
  Future<void> saveOrder(List<HouseRuleModel> rules);

  /// Writes the starter set at fixed ids, so running it twice cannot leave
  /// the house with two copies of every rule.
  Future<void> seedRules(List<HouseRuleModel> rules, {required String by});

  /// What [phone] has agreed to: rule id → the wording version they saw, as
  /// milliseconds since the epoch. An empty map means they have agreed to
  /// nothing yet — which is also what a failed read returns, so the gate errs
  /// towards asking rather than towards letting somebody past.
  Future<Map<String, int>> fetchAcks(String phone);

  Future<void> saveAcks(
    String phone,
    Map<String, int> acks, {
    required String name,
  });
}
