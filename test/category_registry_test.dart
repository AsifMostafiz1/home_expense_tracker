import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/presentation/personal/model/custom_category.dart';
import 'package:demo_project/presentation/personal/model/personal_category.dart';
import 'package:demo_project/presentation/personal/model/personal_transaction.dart';

void main() {
  tearDown(PersonalCategory.clearRegistry);

  test('the fixed expense picker no longer offers the retired three', () {
    final List<String> keys =
        PersonalCategory.forIncome(false).map((c) => c.key).toList();

    expect(keys, isNot(contains('bills')));
    expect(keys, isNot(contains('entertainment')));
    expect(keys, isNot(contains('savings')));
    expect(keys.first, 'food');
    expect(keys, contains('other_expense'));
  });

  test('a retired key still names its category — old entries keep reading', () {
    expect(PersonalCategory.of('bills').key, 'bills');
    expect(PersonalCategory.of('entertainment').key, 'entertainment');
    expect(PersonalCategory.of('savings').key, 'savings');
    expect(identical(PersonalCategory.of('bills'), PersonalCategory.unknown),
        isFalse);
  });

  test('a registered custom category resolves and joins its own side', () {
    PersonalCategory.register(const [
      CustomCategory(id: 'abc123', name: 'Pet care', iconKey: 'pet'),
      CustomCategory(
          id: 'def456', name: 'Tips', flow: MoneyFlow.income, iconKey: 'star'),
    ]);

    expect(PersonalCategory.of('abc123').label, 'Pet care');
    expect(PersonalCategory.of('abc123').isCustom, isTrue);

    final List<String> expenseKeys =
        PersonalCategory.pickerFor(false).map((c) => c.key).toList();
    final List<String> incomeKeys =
        PersonalCategory.pickerFor(true).map((c) => c.key).toList();

    expect(expenseKeys, contains('abc123'));
    expect(expenseKeys, isNot(contains('def456')));
    expect(incomeKeys, contains('def456'));
    expect(incomeKeys, isNot(contains('abc123')));
  });

  test('an unregistered key falls to unknown, and the registry can be cleared',
      () {
    PersonalCategory.register(
        const [CustomCategory(id: 'abc123', name: 'Pet care')]);
    expect(PersonalCategory.of('abc123').isCustom, isTrue);

    PersonalCategory.clearRegistry();
    expect(
        identical(PersonalCategory.of('abc123'), PersonalCategory.unknown),
        isTrue);
  });

  test('the saved order leads the picker and the unmet follow it', () {
    PersonalCategory.register(
        const [CustomCategory(id: 'abc123', name: 'Pet care')]);
    PersonalCategory.registerOrder(const CategoryOrder(
      expense: ['abc123', 'transport', 'food', 'gone-key'],
    ));

    final List<String> keys =
        PersonalCategory.pickerFor(false).map((c) => c.key).toList();

    // The dragged three come first; a key whose category is gone is skipped;
    // everything the order has never met keeps the default order after them.
    expect(keys.sublist(0, 3), ['abc123', 'transport', 'food']);
    expect(keys, isNot(contains('gone-key')));
    expect(keys.sublist(3).first, 'shopping');
    expect(keys.length, PersonalCategory.forIncome(false).length + 1);
  });

  test('an empty order reads as the default arrangement', () {
    final List<String> keys =
        PersonalCategory.pickerFor(false).map((c) => c.key).toList();
    expect(keys,
        PersonalCategory.forIncome(false).map((c) => c.key).toList());
  });

  test('rearranging one side leaves the other side alone', () {
    const CategoryOrder order = CategoryOrder(income: ['bonus', 'salary']);
    final CategoryOrder next =
        order.withSide(false, const ['transport', 'food']);

    expect(next.income, ['bonus', 'salary']);
    expect(next.expense, ['transport', 'food']);
  });
}
