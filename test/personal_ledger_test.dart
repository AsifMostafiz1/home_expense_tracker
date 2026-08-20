import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/presentation/personal/model/debt_entry.dart';
import 'package:demo_project/presentation/personal/model/personal_category.dart';
import 'package:demo_project/presentation/personal/model/personal_summary.dart';
import 'package:demo_project/presentation/personal/model/personal_transaction.dart';
import 'package:demo_project/presentation/personal/view/personal_finance_screen.dart';
import 'package:demo_project/presentation/personal/view/person_ledger_screen.dart';

PersonalTransaction _tx(String date, double amount, {bool income = false}) =>
    PersonalTransaction(
      flow: income ? MoneyFlow.income : MoneyFlow.expense,
      amount: amount,
      date: date,
      category: income ? 'salary' : 'food',
    );

DebtEntry _due(double amount, {bool gave = true, String name = 'Rakib'}) =>
    DebtEntry(
      personName: name,
      flow: gave ? DebtFlow.gave : DebtFlow.got,
      amount: amount,
      date: '2026-08-10',
    );

void main() {
  test('a month adds up income, expense and what was kept', () {
    final all = [
      _tx('2026-08-01', 30000, income: true),
      _tx('2026-08-03', 5000),
      _tx('2026-08-19', 2500),
      _tx('2026-07-28', 9999), // another month entirely
    ];

    final august = MonthMoney.of(DateTime(2026, 8), all);
    expect(august.income, 30000);
    expect(august.expense, 7500);
    expect(august.net, 22500);
    expect(august.savedShare, closeTo(0.75, 0.0001));
    expect(august.peak, 30000);

    final july = MonthMoney.of(DateTime(2026, 7), all);
    expect(july.expense, 9999);
    expect(july.income, 0);
    expect(july.savedShare, 0); // no income to keep a share of
    expect(MonthMoney.of(DateTime(2026, 6), all).isEmpty, isTrue);
  });

  test('a person balance is what is left after repayments', () {
    final owing = PersonBalance(
      key: 'rakib',
      name: 'Rakib',
      phone: '',
      entries: [_due(1000), _due(400, gave: false)],
    );
    expect(owing.balance, 600);
    expect(owing.owesMe, isTrue);
    expect(owing.isSettled, isFalse);
    expect(owing.totalGave, 1000);
    expect(owing.totalGot, 400);

    final settled = PersonBalance(
      key: 'rakib',
      name: 'Rakib',
      phone: '',
      entries: [_due(1000), _due(1000, gave: false)],
    );
    expect(settled.isSettled, isTrue);
    expect(settled.owesMe, isFalse);

    final iOwe = PersonBalance(
      key: 'nabil',
      name: 'Nabil',
      phone: '',
      entries: [_due(750, gave: false)],
    );
    expect(iOwe.balance, -750);
    expect(iOwe.owesMe, isFalse);
  });

  test('the running balance walks the entries oldest first', () {
    const lent = DebtEntry(
      id: 'a',
      personName: 'Shetu',
      flow: DebtFlow.gave,
      amount: 2000,
      date: '2026-08-20',
      timeHour: 9,
    );
    const backOne = DebtEntry(
      id: 'b',
      personName: 'Shetu',
      flow: DebtFlow.got,
      amount: 200,
      date: '2026-08-20',
      timeHour: 11,
    );
    const backTwo = DebtEntry(
      id: 'c',
      personName: 'Shetu',
      flow: DebtFlow.got,
      amount: 1800,
      date: '2026-08-20',
      timeHour: 14,
    );

    // The list is newest-first, the way the screen shows it.
    final person = PersonBalance(
      key: 'shetu',
      name: 'Shetu',
      phone: '',
      entries: [backTwo, backOne, lent],
    );

    final balances = person.runningBalances;
    expect(balances['a'], 2000); // lent — 2000 to come back
    expect(balances['b'], 1800); // 200 returned
    expect(balances['c'], 0); // the rest returned, square
    expect(person.isSettled, isTrue);
  });

  test('entries group by phone when there is one, by name otherwise', () {
    expect(_due(10, name: ' Rakib ').personKey, 'rakib');
    expect(
      const DebtEntry(personName: 'Rakib', personPhone: '01711').personKey,
      '01711',
    );
  });

  test('a category key always resolves to something showable', () {
    expect(PersonalCategory.of('food').key, 'food');
    expect(PersonalCategory.of('salary').key, 'salary');
    expect(PersonalCategory.of('made_up_key').key,
        PersonalCategory.unknown.key);
  });

  test('an entry carries the clock as well as the calendar', () {
    const entry = PersonalTransaction(
      amount: 100,
      date: '2026-08-20',
      timeHour: 15,
      timeMinute: 45,
    );
    expect(entry.time.hour, 15);
    expect(entry.time.minute, 45);
    expect(entry.minuteOfDay, 15 * 60 + 45);
    expect(entry.moment, DateTime(2026, 8, 20, 15, 45));
    expect(entry.toMap()['time_hour'], 15);
    expect(entry.toMap()['time_minute'], 45);

    // A row written before the clock existed still reads back as midnight
    // rather than blowing up.
    final old = PersonalTransaction.fromMap('x', {
      'amount': 50,
      'date': '2026-07-01',
      'type': 'expense',
    });
    expect(old.minuteOfDay, 0);

    const due = DebtEntry(
      amount: 500,
      date: '2026-08-20',
      timeHour: 9,
      timeMinute: 5,
    );
    expect(due.time.hour, 9);
    expect(due.moment, DateTime(2026, 8, 20, 9, 5));
    expect(due.toMap()['time_minute'], 5);
  });

  test('screens are constructible', () {
    expect(const PersonalFinanceScreen(), isNotNull);
    expect(const PersonLedgerScreen(personKey: 'rakib'), isNotNull);
  });
}
