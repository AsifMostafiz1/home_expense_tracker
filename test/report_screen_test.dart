import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:demo_project/presentation/personal/controller/personal_controller.dart';
import 'package:demo_project/presentation/personal/model/personal_transaction.dart';
import 'package:demo_project/presentation/personal/model/subcategory.dart';
import 'package:demo_project/presentation/personal/repository/personal_repository.dart';
import 'package:demo_project/presentation/personal/view/personal_report_screen.dart';
import 'package:demo_project/utils/app_translations.dart';

import 'fake_ledger.dart';

/// A day inside this month, so the fixtures sit in the period the screen
/// opens on however long from now this runs.
String _today(int day) {
  final DateTime now = DateTime.now();
  final DateTime date = DateTime(now.year, now.month, day);
  return '${date.year}-${date.month.toString().padLeft(2, '0')}'
      '-${date.day.toString().padLeft(2, '0')}';
}

void main() {
  const List<Subcategory> subs = [
    Subcategory(id: 'bazar', parent: 'food', name: 'Groceries'),
    Subcategory(id: 'resto', parent: 'food', name: 'Restaurant'),
    Subcategory(id: 'bus', parent: 'transport', name: 'Bus'),
  ];

  final List<PersonalTransaction> ledger = [
    PersonalTransaction(
        id: '1',
        amount: 300,
        date: _today(2),
        category: 'food',
        subcategory: 'bazar'),
    PersonalTransaction(
        id: '2',
        amount: 200,
        date: _today(3),
        category: 'food',
        subcategory: 'bazar'),
    PersonalTransaction(
        id: '3',
        amount: 120,
        date: _today(4),
        category: 'food',
        subcategory: 'resto'),
    PersonalTransaction(id: '4', amount: 80, date: _today(5), category: 'food'),
    PersonalTransaction(
        id: '5',
        amount: 200,
        date: _today(6),
        category: 'transport',
        subcategory: 'bus'),
    PersonalTransaction(
        id: '6',
        amount: 5000,
        date: _today(1),
        category: 'salary',
        flow: MoneyFlow.income),
  ];

  Future<void> pumpReport(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({
      'userPhone': '01711111111',
      'userName': 'Mostafiz',
    });

    // Tall on purpose: every category is a chip on this screen, and a chip
    // below the fold cannot be tapped.
    tester.view.physicalSize = const Size(560 * 3, 3000 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    Get.testMode = true;
    Get.put<PersonalRepository>(FakeLedger(ledger, subs: subs));
    Get.put(PersonalController(repository: Get.find<PersonalRepository>()));
    addTearDown(Get.reset);

    await tester.pumpWidget(GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      home: const PersonalReportScreen(),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  testWidgets('the screen opens on every category and no tag row',
      (tester) async {
    await pumpReport(tester);

    expect(find.text('All categories'), findsOneWidget);
    expect(find.text('6 entries match'), findsOneWidget);
    // Tags belong to a picked category; nothing is picked yet.
    expect(find.text('Groceries'), findsNothing);
    expect(find.text('Reset'), findsNothing);
  });

  testWidgets('several categories can be picked at once', (tester) async {
    await pumpReport(tester);

    await tap(tester, find.text('Food'));
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('4 entries match'), findsOneWidget);

    await tap(tester, find.text('Transport'));
    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('5 entries match'), findsOneWidget);

    // Each picked category brings its own tags, and only its own.
    expect(find.text('Groceries'), findsOneWidget);
    expect(find.text('Bus'), findsOneWidget);
    expect(find.text('Untagged'), findsNWidgets(2));

    // Unpicking puts the report back, tag row and all. The chips come
    // before the tag rows, so the chip is the first of the two the
    // category's name is now on.
    await tap(tester, find.text('Transport').first);
    expect(find.text('Bus'), findsNothing);
    expect(find.text('4 entries match'), findsOneWidget);
  });

  testWidgets('a tag narrows its own category and no other', (tester) async {
    await pumpReport(tester);

    await tap(tester, find.text('Food'));
    await tap(tester, find.text('Transport'));

    // Food down to one of its tags; transport is untouched, so its own row
    // still counts.
    await tap(tester, find.text('Restaurant'));
    expect(find.text('1 selected'), findsOneWidget);
    expect(find.text('2 entries match'), findsOneWidget);

    // A second tag of the same category widens that category alone: two
    // tags of food now, under the two categories the report is of.
    await tap(tester, find.text('Groceries'));
    expect(find.text('2 selected'), findsNWidgets(2));
    expect(find.text('4 entries match'), findsOneWidget);

    // The untagged rows are a pick like any other — the expense categories
    // are listed first, so the food row's is the first of the two.
    await tap(tester, find.text('Untagged').first);
    expect(find.text('5 entries match'), findsOneWidget);
  });

  testWidgets('All widens one category back, Reset clears every pick',
      (tester) async {
    await pumpReport(tester);

    await tap(tester, find.text('Food'));
    await tap(tester, find.text('Restaurant'));
    expect(find.text('2 entries match'), findsNothing);
    expect(find.text('1 entries match'), findsOneWidget);

    await tap(tester, find.text('All'));
    expect(find.text('4 entries match'), findsOneWidget);

    await tap(tester, find.text('Reset'));
    expect(find.text('All categories'), findsOneWidget);
    expect(find.text('6 entries match'), findsOneWidget);
    expect(find.text('Groceries'), findsNothing);
  });

  testWidgets('switching side offers that side only, and drops the picks',
      (tester) async {
    await pumpReport(tester);

    await tap(tester, find.text('Food'));
    expect(find.text('1 selected'), findsOneWidget);

    // The side dropdown, opened through the item it is showing.
    await tap(tester, find.text('All — income & expense'));
    await tap(tester, find.text('Income').last);

    expect(find.text('All categories'), findsOneWidget);
    expect(find.text('Food'), findsNothing);
    expect(find.text('Salary'), findsOneWidget);
    expect(find.text('1 entries match'), findsOneWidget);
  });
}
