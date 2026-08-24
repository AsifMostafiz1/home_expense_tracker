import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:demo_project/presentation/personal/controller/personal_controller.dart';
import 'package:demo_project/presentation/personal/model/debt_entry.dart';
import 'package:demo_project/presentation/personal/model/personal_transaction.dart';
import 'package:demo_project/presentation/personal/repository/personal_repository.dart';
import 'package:demo_project/presentation/personal/view/personal_finance_screen.dart';
import 'package:demo_project/utils/app_translations.dart';

/// The ledger, with no Firestore behind it — the screen only ever sees two
/// streams, so a fake is a pair of values.
class _FakeLedger implements PersonalRepository {
  final List<PersonalTransaction> rows;

  _FakeLedger(this.rows);

  @override
  Stream<List<PersonalTransaction>> watchTransactions(String ownerPhone) =>
      Stream<List<PersonalTransaction>>.value(rows);

  @override
  Stream<List<DebtEntry>> watchDebts(String ownerPhone) =>
      Stream<List<DebtEntry>>.value(const []);

  @override
  Future<void> saveTransaction(PersonalTransaction transaction) async {}

  @override
  Future<void> deleteTransaction(String id) async {}

  @override
  Future<void> saveDebtEntry(DebtEntry entry) async {}

  @override
  Future<void> deleteDebtEntry(String id) async {}

  @override
  Future<void> deletePerson(List<DebtEntry> entries) async {}
}

/// `yyyy-MM-dd` inside the month [monthsBack] before this one, so the fixtures
/// stay in the window the screen opens on however long from now this runs.
String _dayIn(int monthsBack, int day) {
  final DateTime now = DateTime.now();
  final DateTime date = DateTime(now.year, now.month - monthsBack, day);
  return '${date.year}-${date.month.toString().padLeft(2, '0')}'
      '-${date.day.toString().padLeft(2, '0')}';
}

void main() {
  // Five figures on both sides — the widest the card realistically gets, and
  // the case that would push a Row past its edge.
  final List<PersonalTransaction> ledger = [
    PersonalTransaction(
      id: '1',
      amount: 100000,
      date: _dayIn(1, 2),
      flow: MoneyFlow.income,
      category: 'salary',
    ),
    PersonalTransaction(
      id: '2',
      amount: 55000,
      date: _dayIn(1, 14),
      category: 'food',
    ),
    PersonalTransaction(
      id: '3',
      amount: 125000,
      date: _dayIn(0, 5),
      flow: MoneyFlow.income,
      category: 'salary',
    ),
    PersonalTransaction(
      id: '4',
      amount: 88888.5,
      date: _dayIn(0, 12),
      category: 'food',
      note: 'Bazar for the house',
      source: PersonalTransaction.sourceHouse,
    ),
  ];

  Future<void> pumpLedger(
    WidgetTester tester, {
    List<PersonalTransaction>? rows,
  }) async {
    SharedPreferences.setMockInitialValues({
      'userPhone': '01711111111',
      'userName': 'Mostafiz',
    });

    // Wider than a phone on purpose. Tests draw in a font where every glyph is
    // a full square, so a line of text comes out roughly twice the width it
    // has on a device — 480 here is a narrower phone than it looks.
    tester.view.physicalSize = const Size(480 * 3, 1400 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    Get.testMode = true;
    Get.put<PersonalRepository>(_FakeLedger(rows ?? ledger));
    Get.put(PersonalController(repository: Get.find<PersonalRepository>()));
    addTearDown(Get.reset);

    await tester.pumpWidget(GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      home: const PersonalFinanceScreen(),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('the wallet card shows the balance and its working',
      (tester) async {
    await pumpLedger(tester);

    expect(find.text('WALLET'), findsOneWidget);

    // 100,000 − 55,000 carried in, then 125,000 in and 88,888.5 out.
    expect(find.text('Carried in'), findsOneWidget);
    expect(find.text('৳45,000'), findsOneWidget);
    expect(find.text('৳81,111.5'), findsOneWidget);
    // This month's two sides also appear on their own rows further down.
    expect(find.text('৳125,000'), findsWidgets);
    expect(find.text('৳88,888.5'), findsWidgets);

    // What this month did to it, beside the balance.
    expect(find.text('+৳36,111.5 · ${_shortMonthNow()}'), findsOneWidget);

    // Inside its income, so the line under the bar is the kept share.
    expect(find.text('You kept 29% of what came in'), findsOneWidget);

    // The button that adds to this book is the plus and nothing else.
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(find.text('Add entry'), findsNothing);
  });

  testWidgets('a month past its income says how far past, not "kept 0%"',
      (tester) async {
    await pumpLedger(tester, rows: [
      PersonalTransaction(
        id: '1',
        amount: 500,
        date: _dayIn(0, 3),
        flow: MoneyFlow.income,
        category: 'salary',
      ),
      PersonalTransaction(
        id: '2',
        amount: 855,
        date: _dayIn(0, 9),
        category: 'food',
      ),
    ]);

    expect(
      find.text('Spent 171% of what came in — ৳355 more than you earned'),
      findsOneWidget,
    );
    expect(find.textContaining('You kept'), findsNothing);

    // The wallet itself is down by the same amount, and says so.
    expect(find.text('−৳355'), findsOneWidget);
    expect(find.text('More has gone out than has come in'), findsOneWidget);
  });

  testWidgets('a month with nothing coming in is not a percentage',
      (tester) async {
    await pumpLedger(tester, rows: [
      PersonalTransaction(
        id: '1',
        amount: 855,
        date: _dayIn(0, 9),
        category: 'food',
      ),
    ]);

    expect(
      find.text('Nothing came in this month — ৳855 went out'),
      findsOneWidget,
    );
  });

  testWidgets('a new entry starts on today while this month is on screen',
      (tester) async {
    await pumpLedger(tester);

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    expect(find.text(DateFormat('dd MMM, yyyy').format(DateTime.now())),
        findsOneWidget);
  });

  testWidgets('a new entry starts in the month being looked at',
      (tester) async {
    await pumpLedger(tester);

    // Step back a month. Today is not even in it, so opening the sheet on
    // today would file the entry into a month the screen is not showing.
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(FloatingActionButton));
    await tester.pumpAndSettle();

    final DateTime now = DateTime.now();
    final DateTime lastMonth = DateTime(now.year, now.month - 1, 1);
    expect(find.text(DateFormat('dd MMM, yyyy').format(lastMonth)),
        findsOneWidget);
    expect(find.text(DateFormat('dd MMM, yyyy').format(now)), findsNothing);
  });

  testWidgets('a house row is marked and offers no menu', (tester) async {
    await pumpLedger(tester);

    await tester.dragUntilVisible(
      find.text('Bazar for the house'),
      find.byType(ListView).first,
      const Offset(0, -200),
    );
    await tester.pumpAndSettle();

    expect(find.text('HOUSE'), findsOneWidget);

    // Two rows this month: the salary, which keeps its menu, and the house
    // copy, which has a lock where the menu would be. The card at the top
    // carries the other lock — the one on "only you can see this".
    expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
    expect(find.byIcon(Icons.lock_outline_rounded), findsNWidgets(2));
  });
}

String _shortMonthNow() {
  const List<String> months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return months[DateTime.now().month - 1];
}
