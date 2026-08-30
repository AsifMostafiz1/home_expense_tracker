import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:demo_project/presentation/personal/controller/personal_controller.dart';
import 'package:demo_project/presentation/personal/model/custom_category.dart';
import 'package:demo_project/presentation/personal/model/debt_entry.dart';
import 'package:demo_project/presentation/personal/model/ledger_person.dart';
import 'package:demo_project/presentation/personal/model/personal_transaction.dart';
import 'package:demo_project/presentation/personal/model/subcategory.dart';
import 'package:demo_project/presentation/personal/repository/personal_repository.dart';
import 'package:demo_project/presentation/personal/view/personal_finance_screen.dart';
import 'package:demo_project/presentation/personal/widgets/category_breakdown.dart';
import 'package:demo_project/utils/app_translations.dart';
import 'package:demo_project/utils/app_ui.dart';

/// The ledger, with no Firestore behind it — the screen only ever sees two
/// streams, so a fake is a pair of values.
class _FakeLedger implements PersonalRepository {
  final List<PersonalTransaction> rows;
  final List<DebtEntry> dues;
  final List<Subcategory> subs;

  _FakeLedger(this.rows, {this.dues = const [], this.subs = const []});

  @override
  Stream<List<PersonalTransaction>> watchTransactions(String ownerPhone) =>
      Stream<List<PersonalTransaction>>.value(rows);

  @override
  Stream<List<DebtEntry>> watchDebts(String ownerPhone) =>
      Stream<List<DebtEntry>>.value(dues);

  @override
  Future<void> saveTransaction(PersonalTransaction transaction) async {}

  @override
  Future<void> deleteTransaction(String id) async {}

  @override
  Future<void> saveDebtEntry(DebtEntry entry) async {}

  @override
  Future<void> deleteDebtEntry(String id) async {}

  @override
  Stream<List<LedgerPerson>> watchPeople(String ownerPhone) =>
      Stream<List<LedgerPerson>>.value(const []);

  @override
  Future<void> savePerson(LedgerPerson person) async {}

  @override
  Future<void> renamePerson({
    required List<DebtEntry> entries,
    List<String> personIds = const [],
    required String name,
  }) async {}

  @override
  Future<void> deletePerson(
    List<DebtEntry> entries, {
    List<String> personIds = const [],
  }) async {}

  @override
  Stream<List<CustomCategory>> watchCategories(String ownerPhone) =>
      Stream<List<CustomCategory>>.value(const []);

  @override
  Future<String> saveCategory(CustomCategory category) async => category.id;

  @override
  Future<void> deleteCategory(
    String id, {
    required List<PersonalTransaction> entries,
    List<String> subcategoryIds = const [],
  }) async {}

  @override
  Stream<CategoryOrder> watchCategoryOrder(String ownerPhone) =>
      Stream<CategoryOrder>.value(const CategoryOrder());

  @override
  Future<void> saveCategoryOrder(String ownerPhone, CategoryOrder order) async {}

  @override
  Stream<List<Subcategory>> watchSubcategories(String ownerPhone) =>
      Stream<List<Subcategory>>.value(subs);

  @override
  Future<String> saveSubcategory(Subcategory subcategory) async =>
      subcategory.id;

  @override
  Future<void> deleteSubcategory(
    String id, {
    required List<PersonalTransaction> entries,
  }) async {}

  @override
  Future<void> seedSubcategories(
    String ownerPhone,
    List<Subcategory> seeds,
  ) async {}
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
      note: 'Monthly pay',
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
    List<DebtEntry> dues = const [],
    List<Subcategory> subs = const [],
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
    Get.put<PersonalRepository>(
        _FakeLedger(rows ?? ledger, dues: dues, subs: subs));
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

  testWidgets('the six-month chart starts folded and opens on a tap',
      (tester) async {
    await pumpLedger(tester);

    // Folded: the title and the six-month totals, no chart and no hint.
    expect(find.text('Last six months'), findsOneWidget);
    expect(find.text('৳225,000'), findsOneWidget); // income over six months
    expect(find.text('৳143,888.5'), findsOneWidget); // expense over six months
    expect(find.text('Tap a month to see its numbers'), findsNothing);

    await tester.tap(find.text('Last six months'));
    await tester.pumpAndSettle();

    // Open: the chart and its hint, and the totals give way to the legend.
    expect(find.text('Tap a month to see its numbers'), findsOneWidget);
    expect(find.text('৳225,000'), findsNothing);

    await tester.tap(find.text('Last six months'));
    await tester.pumpAndSettle();
    expect(find.text('Tap a month to see its numbers'), findsNothing);
  });

  testWidgets('the wallet carries the dues, and shows its working',
      (tester) async {
    // July carried forward +100, August +100, owed 100, owing 50 — so 250.
    await pumpLedger(
      tester,
      rows: [
        PersonalTransaction(
          id: '1',
          amount: 100,
          date: _dayIn(1, 2),
          flow: MoneyFlow.income,
          category: 'salary',
        ),
        PersonalTransaction(
          id: '2',
          amount: 100,
          date: _dayIn(0, 5),
          flow: MoneyFlow.income,
          category: 'salary',
        ),
      ],
      dues: [
        DebtEntry(
          id: 'd1',
          personName: 'Rakib',
          flow: DebtFlow.gave,
          amount: 100,
          date: _dayIn(0, 6),
        ),
        DebtEntry(
          id: 'd2',
          personName: 'Karim',
          flow: DebtFlow.got,
          amount: 50,
          date: _dayIn(0, 7),
        ),
      ],
    );

    expect(find.text('৳250'), findsOneWidget);
    expect(find.text('Your money, and the dues on either side of it'),
        findsOneWidget);
    // The dues are in that figure, not spelled out on the card — the strip
    // under it stays the money alone.
    expect(find.text('Total to get'), findsNothing);
    expect(find.text('Total to pay'), findsNothing);

    // The button beside the balance opens the statement behind it.
    await tester.tap(find.byIcon(Icons.info_outline_rounded));
    await tester.pumpAndSettle();

    expect(find.text('MONTH BY MONTH'), findsOneWidget);
    expect(find.text('DUES'), findsOneWidget);

    // Two months of +৳100 — or, if this month happens to be January, one of
    // them folded into the previous year's carry — and Rakib's ৳100 to come.
    expect(find.text('+৳100'), findsNWidgets(3));
    expect(find.text('+৳200'), findsOneWidget); // the money subtotal

    // The dues are named, one line each, not one lump.
    expect(find.text('Rakib'), findsOneWidget);
    expect(find.text('Borrowed'), findsOneWidget);
    expect(find.text('Karim'), findsOneWidget);
    expect(find.text('Lent out'), findsOneWidget);
    expect(find.text('−৳50'), findsOneWidget);
    expect(find.text('+৳50'), findsOneWidget); // the dues subtotal

    // The hero and the total line at the foot of the statement.
    expect(find.text('৳250'), findsNWidgets(2));
  });

  testWidgets('opening the ledger comes back to this month', (tester) async {
    await pumpLedger(tester);

    final DateTime now = DateTime.now();
    final DateTime lastMonth = DateTime(now.year, now.month - 1);

    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();
    expect(find.text(AppUi.monthLabel(lastMonth)), findsOneWidget);

    // Away to another screen and back. The controller survives that — it is
    // registered for the session — but the month it was left on should not.
    await tester.pumpWidget(const MaterialApp(home: Scaffold()));
    await tester.pumpAndSettle();
    await tester.pumpWidget(GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      home: const PersonalFinanceScreen(),
    ));
    await tester.pumpAndSettle();

    expect(find.text(AppUi.monthLabel(DateTime(now.year, now.month))),
        findsOneWidget);
    expect(find.text(AppUi.monthLabel(lastMonth)), findsNothing);
  });

  testWidgets('the list filters down to one side of the month',
      (tester) async {
    await pumpLedger(tester);

    // Two entries in the month on screen: pay in, a house copy out.
    expect(find.text('Monthly pay'), findsOneWidget);
    expect(find.text('Bazar for the house'), findsOneWidget);

    // Expense only: the pay row goes, the house copy stays. `.last` because
    // the wallet card above carries the same two words as its labels.
    await tester.tap(find.text('Expense').last);
    await tester.pumpAndSettle();
    expect(find.text('Bazar for the house'), findsOneWidget);
    expect(find.text('Monthly pay'), findsNothing);

    // Income only: the other way round.
    await tester.tap(find.text('Income').last);
    await tester.pumpAndSettle();
    expect(find.text('Bazar for the house'), findsNothing);
    expect(find.text('Monthly pay'), findsOneWidget);

    // And back to both.
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();
    expect(find.text('Bazar for the house'), findsOneWidget);
    expect(find.text('Monthly pay'), findsOneWidget);
  });

  testWidgets('the filter totals say how much, and nine figures do not break',
      (tester) async {
    // Both on one day, so neither figure collides with a day header's net.
    // Nine figures on each side — an overflow anywhere would fail the pump.
    await pumpLedger(tester, rows: [
      PersonalTransaction(
        id: '1',
        amount: 123456789.5,
        date: _dayIn(0, 3),
        flow: MoneyFlow.income,
        category: 'salary',
      ),
      PersonalTransaction(
        id: '2',
        amount: 98765432.25,
        date: _dayIn(0, 3),
        category: 'food',
      ),
    ]);

    // Both sides' totals sit beside the chips.
    expect(find.text('+৳123,456,789.5'), findsWidgets);
    expect(find.text('−৳98,765,432.25'), findsWidgets);

    // Narrowed to one side, only that side's figure survives — anywhere.
    await tester.tap(find.text('Expense').last);
    await tester.pumpAndSettle();
    expect(find.text('+৳123,456,789.5'), findsNothing);
    expect(find.text('−৳98,765,432.25'), findsWidgets);
  });

  testWidgets('a category bar opens the entries behind it', (tester) async {
    await pumpLedger(tester);

    // The month switcher's own arrow is the same glyph, so the finder has to
    // be pinned to the breakdown card.
    await tester.tap(find
        .descendant(
          of: find.byType(CategoryBreakdown),
          matching: find.byIcon(Icons.chevron_right_rounded),
        )
        .first);
    await tester.pumpAndSettle();

    // The sheet is headed by the category, the month and what it came to —
    // month and count share one line, so match inside it.
    expect(find.textContaining('1 entries'), findsOneWidget);
    expect(find.text('Bazar for the house'), findsWidgets);
    // The figure is in the sheet's header and its day heading, on top of the
    // screen it was opened from — the count above is the unique assertion.
    expect(find.text('−৳88,888.5'), findsWidgets);
  });

  testWidgets('the category sheet opens on All and narrows by tag',
      (tester) async {
    await pumpLedger(
      tester,
      rows: [
        PersonalTransaction(
          id: '1',
          amount: 300,
          date: _dayIn(0, 5),
          category: 'food',
          subcategory: 'sub_bazar',
          note: 'Weekly bazar',
        ),
        PersonalTransaction(
          id: '2',
          amount: 120,
          date: _dayIn(0, 6),
          category: 'food',
          subcategory: 'sub_resto',
          note: 'Kacchi night',
        ),
        PersonalTransaction(
          id: '3',
          amount: 80,
          date: _dayIn(0, 7),
          category: 'food',
          note: 'Tea',
        ),
      ],
      subs: const [
        Subcategory(id: 'sub_bazar', parent: 'food', name: 'Groceries'),
        Subcategory(id: 'sub_resto', parent: 'food', name: 'Restaurant'),
      ],
    );

    await tester.tap(find
        .descendant(
          of: find.byType(CategoryBreakdown),
          matching: find.byIcon(Icons.chevron_right_rounded),
        )
        .first);
    await tester.pumpAndSettle();

    // Every note is now on screen twice: once in the month's list behind,
    // once in the sheet — the sheet opened on All.
    expect(find.text('Weekly bazar'), findsNWidgets(2));
    expect(find.text('Kacchi night'), findsNWidgets(2));
    expect(find.text('Tea'), findsNWidgets(2));
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Restaurant'), findsOneWidget);

    // One tag on: only its row stays in the sheet, the others are left to
    // the list behind. The untagged one goes too.
    await tester.tap(find.text('Restaurant'));
    await tester.pumpAndSettle();
    expect(find.text('Kacchi night'), findsNWidgets(2));
    expect(find.text('Weekly bazar'), findsOneWidget);
    expect(find.text('Tea'), findsOneWidget);

    // And back to everything. The row is scrolled back first: the tag's
    // total took width from it, and the tapped chip was kept in view at the
    // far end — in this wide test font that leaves "All" partly off the
    // left edge, as it would on a phone with a row of many tags.
    await tester.drag(find.text('Restaurant'), const Offset(400, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All').last);
    await tester.pumpAndSettle();
    expect(find.text('Weekly bazar'), findsNWidgets(2));
    expect(find.text('Tea'), findsNWidgets(2));
  });

  testWidgets('the tag just tapped stays in view when its total appears',
      (tester) async {
    // Enough tags to overflow the row, and money on the last one so the
    // quiet total shows up beside the row the moment it is tapped — which
    // is what steals width from the scrolling part.
    const List<String> names = [
      'Tag one', 'Tag two', 'Tag three', 'Tag four',
      'Tag five', 'Tag six', 'Tag seven', 'Tag eight',
    ];
    await pumpLedger(
      tester,
      rows: [
        PersonalTransaction(
          id: '1',
          amount: 1500,
          date: _dayIn(0, 5),
          category: 'food',
          subcategory: 'sub_8',
          note: 'Feast',
        ),
      ],
      subs: [
        for (int i = 0; i < names.length; i++)
          Subcategory(id: 'sub_${i + 1}', parent: 'food', name: names[i]),
      ],
    );

    await tester.tap(find
        .descendant(
          of: find.byType(CategoryBreakdown),
          matching: find.byIcon(Icons.chevron_right_rounded),
        )
        .first);
    await tester.pumpAndSettle();

    // Scroll the tab row to its end and tap the last tag.
    await tester.drag(find.text('Tag one'), const Offset(-2000, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tag eight'));
    await tester.pumpAndSettle();

    // The total is there — and the tapped chip is still wholly inside the
    // row's viewport, not pushed under it.
    expect(find.text('−৳1,500'), findsWidgets);
    final Rect chip = tester.getRect(find.text('Tag eight'));
    final Rect viewport = tester.getRect(find
        .ancestor(
          of: find.text('Tag eight'),
          matching: find.byType(SingleChildScrollView),
        )
        .first);
    expect(chip.left, greaterThanOrEqualTo(viewport.left - 0.5));
    expect(chip.right, lessThanOrEqualTo(viewport.right + 0.5));
  });

  testWidgets('a refresh puts the whole visit back to how it opened',
      (tester) async {
    await pumpLedger(tester);

    final DateTime now = DateTime.now();
    final DateTime lastMonth = DateTime(now.year, now.month - 1);

    // Set the three things a visit can change.
    await tester.tap(find.text('Expense').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Last six months'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chevron_left_rounded));
    await tester.pumpAndSettle();

    expect(find.text('Monthly pay'), findsNothing); // filtered to expense
    expect(find.text('Tap a month to see its numbers'), findsOneWidget);
    expect(find.text(AppUi.monthLabel(lastMonth)), findsOneWidget);

    // Pull down.
    await tester.fling(
        find.byType(ListView).first, const Offset(0, 400), 1200);
    await tester.pumpAndSettle();

    expect(find.text(AppUi.monthLabel(DateTime(now.year, now.month))),
        findsOneWidget);
    expect(find.text('Monthly pay'), findsOneWidget); // filter cleared
    expect(find.text('Bazar for the house'), findsOneWidget);
    expect(find.text('Tap a month to see its numbers'), findsNothing);
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
