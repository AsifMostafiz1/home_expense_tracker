import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/presentation/personal/model/debt_entry.dart';
import 'package:demo_project/presentation/personal/model/default_subcategories.dart';
import 'package:demo_project/presentation/personal/model/personal_category.dart';
import 'package:demo_project/presentation/personal/model/personal_summary.dart';
import 'package:demo_project/presentation/personal/model/personal_transaction.dart';
import 'package:demo_project/presentation/personal/model/subcategory.dart';
import 'package:demo_project/presentation/personal/view/personal_finance_screen.dart';
import 'package:demo_project/presentation/personal/view/person_ledger_screen.dart';
import 'package:demo_project/presentation/chat/model/chat_message_model.dart';
import 'package:demo_project/presentation/monthly_stats/model/month_cost_summary.dart';
import 'package:demo_project/presentation/monthly_stats/model/month_summary_message.dart';

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

  test('the wallet carries what a month did not spend into the next', () {
    final all = [
      // July: 100 in, 50 out.
      _tx('2026-07-02', 100, income: true),
      _tx('2026-07-14', 50),
      // August: 100 in, 80 out.
      _tx('2026-08-05', 100, income: true),
      _tx('2026-08-21', 80),
    ];

    final august = WalletBalance.of(DateTime(2026, 8), all);
    expect(august.opening, 50); // July's leftover
    expect(august.net, 20);
    expect(august.balance, 70);
    expect(august.isShort, isFalse);

    // Looking back at July shows July's closing balance, not today's.
    final july = WalletBalance.of(DateTime(2026, 7), all);
    expect(july.opening, 0);
    expect(july.balance, 50);

    // And a month before anything was recorded is empty rather than negative.
    expect(WalletBalance.of(DateTime(2026, 6), all).balance, 0);
  });

  test('the statement splits this year by month and rolls up the rest', () {
    final all = [
      _tx('2025-03-10', 200, income: true), // a closed year
      _tx('2025-11-02', 100), //  ... and a spend in it
      _tx('2026-07-04', 250, income: true),
      _tx('2026-07-19', 50),
      _tx('2026-08-06', 100, income: true),
      _tx('2026-09-01', 999), // a month not reached yet
    ];

    final timeline = WalletTimeline.of(DateTime(2026, 8), all);
    expect(timeline.year, 2026);
    // 2025 comes in as one figure: 200 earned less 100 spent.
    expect(timeline.broughtForward, 100);
    expect(timeline.hasBroughtForward, isTrue);

    // This year, month by month, oldest first — and September left out.
    expect(timeline.months.map((month) => month.month.month), [7, 8]);
    expect(timeline.months.first.net, 200);
    expect(timeline.months.last.net, 100);

    // Which is exactly the money side of the wallet it explains.
    final wallet = WalletBalance.of(DateTime(2026, 8), all);
    expect(
      timeline.broughtForward +
          timeline.months.fold<double>(0, (sum, m) => sum + m.net),
      wallet.money,
    );

    // The month being looked at is always a line, even with nothing in it.
    final quiet = WalletTimeline.of(DateTime(2026, 10), all);
    expect(quiet.months.map((month) => month.month.month), [7, 8, 9, 10]);
    expect(quiet.months.last.isEmpty, isTrue);

    // A ledger that only ever ran this year has nothing to carry in.
    final fresh = WalletTimeline.of(DateTime(2026, 8), [_tx('2026-08-06', 10)]);
    expect(fresh.hasBroughtForward, isFalse);
    expect(fresh.months.length, 1);
  });

  test('the wallet counts the dues on both sides', () {
    final money = [
      _tx('2026-07-02', 100, income: true), // July, carried forward
      _tx('2026-08-05', 100, income: true), // August
    ];
    final dues = [
      _due(100), // handed over — to come back
      _due(50, gave: false, name: 'Karim'), // taken — to be paid back
    ];

    final wallet =
        WalletBalance.of(DateTime(2026, 8), money, debts: dues);
    expect(wallet.opening, 100);
    expect(wallet.net, 100);
    expect(wallet.money, 200);
    expect(wallet.receivable, 100);
    expect(wallet.payable, 50);
    expect(wallet.dues, 50);
    expect(wallet.balance, 250);
    expect(wallet.hasDues, isTrue);

    // Without the dues it is the money alone, and says there are none.
    final moneyOnly = WalletBalance.of(DateTime(2026, 8), money);
    expect(moneyOnly.balance, 200);
    expect(moneyOnly.hasDues, isFalse);
  });

  test('a due settled between two people takes only one side', () {
    // 1,000 lent, 600 paid back: 400 still to come, not 1,000 to come and
    // 600 to go — which would net out the same and inflate both totals.
    final wallet = WalletBalance.of(DateTime(2026, 8), const [], debts: [
      _due(1000),
      _due(600, gave: false),
    ]);
    expect(wallet.receivable, 400);
    expect(wallet.payable, 0);
    expect(wallet.balance, 400);

    // Squared off entirely, that person is on neither side.
    final settled = WalletBalance.of(DateTime(2026, 8), const [], debts: [
      _due(1000),
      _due(1000, gave: false),
    ]);
    expect(settled.hasDues, isFalse);
    expect(settled.balance, 0);
  });

  test('dues are cut at the same month the money is', () {
    // Every fixture due is dated 2026-08-10.
    final august = WalletBalance.of(DateTime(2026, 8), const [], debts: [
      _due(100),
    ]);
    expect(august.receivable, 100);

    // Looking back at July, a due taken on in August has not happened yet.
    final july = WalletBalance.of(DateTime(2026, 7), const [], debts: [
      _due(100),
    ]);
    expect(july.receivable, 0);
    expect(july.balance, 0);
  });

  test('a wallet that has spent more than it earned says so', () {
    final all = [
      _tx('2026-08-01', 100, income: true),
      _tx('2026-08-02', 130),
    ];

    final wallet = WalletBalance.of(DateTime(2026, 8), all);
    expect(wallet.balance, -30);
    expect(wallet.isShort, isTrue);

    // A row with no readable date belongs to no month and is left out.
    expect(
      WalletBalance.of(DateTime(2026, 8), [...all, _tx('', 500)]).balance,
      -30,
    );
  });

  test('a month that spends past its income says how far past', () {
    final over = MonthMoney.of(DateTime(2026, 8), [
      _tx('2026-08-01', 500, income: true),
      _tx('2026-08-04', 855),
    ]);
    expect(over.isOverspent, isTrue);
    expect(over.overspend, 355);
    expect((over.spentShare * 100).round(), 171);
    // The kept share bottoms out, which is exactly why it cannot be the only
    // thing shown for a month like this.
    expect(over.savedShare, 0);

    final inside = MonthMoney.of(DateTime(2026, 8), [
      _tx('2026-08-01', 500, income: true),
      _tx('2026-08-04', 400),
    ]);
    expect(inside.isOverspent, isFalse);
    expect(inside.overspend, 0);
    expect((inside.spentShare * 100).round(), 80);
    expect(inside.savedShare, closeTo(0.2, 0.0001));

    // Spending with nothing coming in has no share to be a percentage of.
    final noIncome = MonthMoney.of(DateTime(2026, 8), [_tx('2026-08-04', 855)]);
    expect(noIncome.isOverspent, isTrue);
    expect(noIncome.overspend, 855);
    expect(noIncome.spentShare, 0);

    // And a month that spent exactly what it earned is not overspent.
    final exact = MonthMoney.of(DateTime(2026, 8), [
      _tx('2026-08-01', 500, income: true),
      _tx('2026-08-04', 500),
    ]);
    expect(exact.isOverspent, isFalse);
    expect((exact.spentShare * 100).round(), 100);
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

  test('the month list groups into days, newest first', () {
    // The order the repository hands them over in.
    final all = [
      _tx('2026-08-22', 10),
      _tx('2026-08-21', 635),
      _tx('2026-08-20', 30),
      _tx('2026-08-20', 20, income: true),
    ];

    final days = MoneyDay.group(all);
    expect(days.map((d) => d.date), [
      DateTime(2026, 8, 22),
      DateTime(2026, 8, 21),
      DateTime(2026, 8, 20),
    ]);
    expect(days.map((d) => d.entries.length), [1, 1, 2]);

    // A day with both sides of the ledger in it nets out.
    final twentieth = days.last;
    expect(twentieth.income, 20);
    expect(twentieth.expense, 30);
    expect(twentieth.net, -10);
  });

  test('a day orders its own entries by the clock, latest first', () {
    const morning = PersonalTransaction(
      id: 'a',
      amount: 10,
      date: '2026-08-20',
      timeHour: 9,
      timeMinute: 5,
    );
    const evening = PersonalTransaction(
      id: 'b',
      amount: 30,
      date: '2026-08-20',
      timeHour: 19,
      timeMinute: 21,
    );

    // Handed over in the wrong order on purpose — the grouping sorts rather
    // than trusting its caller.
    final days = MoneyDay.group([morning, evening]);
    expect(days.single.entries.map((e) => e.id), ['b', 'a']);
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

  test('a house expense copy says where it came from', () {
    const mine = PersonalTransaction(amount: 100, date: '2026-08-20');
    expect(mine.isFromHouse, isFalse);
    expect(mine.toMap()['source'], '');

    const copied = PersonalTransaction(
      id: 'expense-doc-id',
      amount: 100,
      date: '2026-08-20',
      source: PersonalTransaction.sourceHouse,
    );
    expect(copied.isFromHouse, isTrue);
    expect(copied.toMap()['source'], 'house');

    // A row written before the copies existed is the member's own.
    final old = PersonalTransaction.fromMap('x', {
      'amount': 50,
      'date': '2026-07-01',
      'type': 'expense',
    });
    expect(old.isFromHouse, isFalse);

    // And the flag survives being read back and edited.
    final read = PersonalTransaction.fromMap('expense-doc-id', copied.toMap());
    expect(read.isFromHouse, isTrue);
    expect(read.copyWith(amount: 120).isFromHouse, isTrue);
  });

  test('a house expense copy lands in the bucket its type belongs to', () {
    // The shared groceries.
    expect(PersonalCategory.forHouseExpense('expense'), 'food');
    // The gas, the wifi and the rest.
    expect(PersonalCategory.forHouseExpense('others'), 'other_expense');
    // Both keys are real categories, so the row draws with an icon.
    expect(PersonalCategory.of(PersonalCategory.forHouseExpense('expense')).key,
        isNot(PersonalCategory.unknown.key));
    expect(PersonalCategory.of(PersonalCategory.forHouseExpense('others')).key,
        isNot(PersonalCategory.unknown.key));
  });

  test('a house meal copy is tagged, and tagged with the same one twice', () {
    final Subcategory? first =
        DefaultSubcategories.houseTagFor('01711', 'expense');
    expect(first, isNotNull);
    expect(first!.parent, PersonalCategory.forHouseExpense('expense'));
    expect(first.name, 'Meal');
    expect(first.ownerPhone, '01711');

    // The id is derived, not random: the second house expense of the month
    // asks for the same document rather than a second chip beside it.
    final Subcategory second =
        DefaultSubcategories.houseTagFor('01711', 'expense')!;
    expect(second.id, first.id);

    // One per member, not one for the house.
    expect(DefaultSubcategories.houseTagFor('01722', 'expense')!.id,
        isNot(first.id));

    // And it cannot collide with a starter chip of the same category.
    final Iterable<String> seeded = DefaultSubcategories.forOwner('01711')
        .where((sub) => sub.parent == 'food')
        .map((sub) => sub.id);
    expect(seeded, isNot(contains(first.id)));

    // The gas and the wifi are not one recurring thing, so they wear none.
    expect(DefaultSubcategories.houseTagFor('01711', 'others'), isNull);
    // Nor is there anything to tag without an owner to tag it for.
    expect(DefaultSubcategories.houseTagFor('', 'expense'), isNull);
  });

  test('screens are constructible', () {
    expect(const PersonalFinanceScreen(), isNotNull);
    expect(const PersonLedgerScreen(personKey: 'rakib'), isNotNull);
  });

  group('a month shared as a chat message', () {
    const owes = MemberCostSummary(
      phone: '01711',
      name: 'Rakib',
      isMe: false,
      inBills: true,
      rent: 3000,
      sharedBills: 500,
      mealCount: 28,
      mealCost: 1470,
      otherCost: 320,
      mealPaid: 1040,
      otherPaid: 0,
    );

    // More paid in than charged — the house owes this one.
    const isOwed = MemberCostSummary(
      phone: '01822',
      name: 'Shetu',
      isMe: false,
      inBills: true,
      rent: 1000,
      sharedBills: 0,
      mealCount: 10,
      mealCost: 500,
      otherCost: 100,
      mealPaid: 2400,
      otherPaid: 0,
    );

    const alreadyPaid = MemberCostSummary(
      phone: '01933',
      name: 'Mostafiz',
      isMe: true,
      inBills: true,
      rent: 3000,
      sharedBills: 500,
      mealCount: 20,
      mealCost: 1000,
      otherCost: 320,
      mealPaid: 0,
      otherPaid: 0,
      settled: true,
      settledAmount: 4820,
    );

    final summary = MonthCostSummary(
      month: DateTime(2026, 8),
      mealMonth: DateTime(2026, 7),
      bill: null,
      mealRate: 52.5,
      otherRate: 320,
      totalMeals: 234,
      members: const [owes, isOwed, alreadyPaid],
    );

    test('the house message names everyone and nobody twice', () {
      final text = MonthSummaryMessage.forHouse(summary);

      for (final name in ['Rakib', 'Shetu', 'Mostafiz']) {
        expect(text, contains(name),
            reason: '$name is missing from the group message');
        expect(RegExp(name).allMatches(text).length, 1);
      }
      expect(text, contains('2026'));
    });

    test('the message is names and amounts, and nothing else', () {
      final text = MonthSummaryMessage.forHouse(summary);

      // The rates, the house total and who has paid up all live on the
      // ledger. Repeating them here is what made a wall of text.
      expect(text, isNot(contains('234')), reason: 'total meals leaked in');
      expect(text, isNot(contains('52.5')), reason: 'the meal rate leaked in');
      expect(text, isNot(contains('320')), reason: 'the other rate leaked in');
      expect(text, isNot(contains('✅')));

      // Three members, one line each, under a heading and a blank line.
      expect(text.split('\n').where((l) => l.startsWith('•')).length, 3);
    });

    test("a member's message carries their figure and nobody else's", () {
      final text = MonthSummaryMessage.forMember(summary, owes);

      expect(text, isNot(contains('Shetu')));
      expect(text, isNot(contains('Mostafiz')));
      // 3000 + 500 + 1470 + 320 = 5290 charged, 1040 paid, 4250 owed. Only
      // the last of those belongs in the message.
      expect(text, contains('4,250'));
      expect(text, isNot(contains('5,290')));
      expect(text, isNot(contains('1,040')));
    });

    test('somebody the house owes is not asked for money', () {
      expect(isOwed.willGet, isTrue);
      final text = MonthSummaryMessage.forMember(summary, isOwed);
      // 1000 + 500 + 100 = 1600 charged against 2400 paid.
      expect(text, contains('800'));
      // Never as a negative figure — the sign is carried by the words.
      expect(text, isNot(contains('-800')));
      expect(text, isNot(contains('\u2212800')));
    });

    test('a message the app composed says what tapping it opens', () {
      // The footer and the navigation both hang off this, so a shared
      // summary that carried no action would be a dead end.
      const shared = ChatMessageModel.actionMonthlySummary;
      expect(shared, isNotEmpty);

      final tappable = ChatMessageModel(
        id: 'm1',
        text: MonthSummaryMessage.forHouse(summary),
        senderName: 'Mostafiz',
        senderPhone: '01933',
        createdAt: DateTime(2026, 8, 31),
        action: shared,
      );
      expect(tappable.hasAction, isTrue);
      expect(tappable.toMap()['action'], shared);

      // A round trip through Firestore keeps it.
      expect(
        ChatMessageModel.fromMap('m1', {'action': shared}).action,
        shared,
      );

      // And an ordinary typed message carries none, so its bubble keeps the
      // clock its tap has always shown.
      expect(ChatMessageModel.fromMap('m2', const {}).hasAction, isFalse);
      expect(
        ChatMessageModel.fromMap('m3', const {'action': ''}).hasAction,
        isFalse,
      );
    });
  });
}
