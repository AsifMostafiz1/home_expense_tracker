import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:demo_project/presentation/personal/model/personal_report.dart';
import 'package:demo_project/presentation/personal/model/personal_transaction.dart';
import 'package:demo_project/presentation/personal/model/report_pages.dart';
import 'package:demo_project/presentation/personal/model/subcategory.dart';
import 'package:demo_project/presentation/personal/widgets/report_page.dart';
import 'package:demo_project/utils/app_translations.dart';

/// The page is drawn to fixed heights the planner counted on. These pump
/// the fullest pages the planner can produce and let the framework's own
/// overflow assertion say whether the widgets kept to the numbers.
void main() {
  final DateTimeRange range = DateTimeRange(
    start: DateTime(2026, 6, 1),
    end: DateTime(2026, 8, 31),
  );

  List<PersonalTransaction> rows(int n,
          {int categories = 3, bool tags = true}) =>
      [
        for (int i = 0; i < n; i++)
          PersonalTransaction(
            id: '$i',
            amount: 1234567.5,
            date:
                '2026-0${6 + (i ~/ 3) % 3}-${(i % 28 + 1).toString().padLeft(2, '0')}',
            timeHour: i % 24,
            timeMinute: i % 60,
            flow: i % 5 == 0 ? MoneyFlow.income : MoneyFlow.expense,
            category: i % 5 == 0 ? 'salary' : 'c${i % categories}',
            subcategory: tags ? 'tag${i % 4}' : '',
            note: 'বাজার - চাল + তেল + শিম, a long description that ellipsises',
          ),
      ];

  Future<void> pumpPage(
    WidgetTester tester,
    PersonalReport report,
    ReportPageSpec spec,
    int pageCount,
  ) async {
    tester.view.physicalSize = const Size(595 * 2, 842 * 2);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(GetMaterialApp(
      translations: AppTranslations(),
      locale: const Locale('en', 'US'),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReportPage(
            report: report,
            spec: spec,
            pageCount: pageCount,
            ownerName: 'Mostafiz',
            ownerPhone: '01711111111',
            generatedAt: DateTime(2026, 8, 30, 14, 5),
            tagNames: const {'tag0': 'বাজার', 'tag1': 'Restaurant'},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('a full page of rows fits without the summary', (tester) async {
    final PersonalReport report = PersonalReport.of(
      ReportFilter(range: range),
      rows(ReportLayout.rowsPerPage * 2),
    );
    final List<ReportPageSpec> pages = ReportPages.plan(report);
    expect(pages.first.rows.length, ReportLayout.rowsPerPage);

    await pumpPage(tester, report, pages.first, pages.length);
    expect(find.text('Continued on next page…'), findsOneWidget);
    expect(find.text('Page 1 of ${pages.length}'), findsOneWidget);
  });

  testWidgets('the fullest last page still holds the summary', (tester) async {
    // Grow the report until the planner just stops fitting the summary on
    // the last page, then draw the biggest page it did accept.
    late PersonalReport report;
    late List<ReportPageSpec> pages;
    for (int n = 1; n < ReportLayout.rowsPerPage; n++) {
      final PersonalReport candidate = PersonalReport.of(
          ReportFilter(range: range, category: 'c0'),
          rows(n * 5, categories: 3),
          subcategories: const [
            Subcategory(id: 'tag0', parent: 'c0', name: 'বাজার'),
            Subcategory(id: 'tag1', parent: 'c0', name: 'Restaurant'),
          ]);
      final List<ReportPageSpec> plan = ReportPages.plan(candidate);
      if (plan.last.rows.isEmpty) break;
      report = candidate;
      pages = plan;
    }
    expect(pages.last.summary, isTrue);
    expect(pages.last.rows, isNotEmpty);

    await pumpPage(tester, report, pages.last, pages.length);
    expect(find.text('Total income'), findsOneWidget);
    expect(find.text('By sub-category'), findsOneWidget);
    expect(find.text('Month by month'), findsOneWidget);
    expect(find.text('Continued on next page…'), findsNothing);
  });

  testWidgets('a summary-only page with every table at its cap fits',
      (tester) async {
    final PersonalReport report = PersonalReport.of(
      ReportFilter(range: range),
      rows(ReportLayout.rowsPerPage, categories: 30),
    );
    final List<ReportPageSpec> pages = ReportPages.plan(report);
    expect(pages.last.rows, isEmpty);
    expect(pages.last.summary, isTrue);
    // Thirty categories plus a month table cannot both be at the cap on
    // one page: the category table gives up rows, and says so.
    final SummaryRows summary = ReportPages.summaryRows(report);
    expect(summary.categories, lessThanOrEqualTo(ReportLayout.maxSummaryRows));
    expect(summary.categories, greaterThan(SummaryRows.minRows));
    expect(summary.months, 3);

    await pumpPage(tester, report, pages.last, pages.length);
    expect(find.text('By category'), findsOneWidget);
    expect(
        find.text(
            '+ ${report.byCategory.length - (summary.categories - 1)} more'),
        findsOneWidget);
    expect(find.text('Prepared for'.toUpperCase()), findsOneWidget);
  });

  testWidgets('an empty report is one page that says so', (tester) async {
    final PersonalReport report =
        PersonalReport.of(ReportFilter(range: range), const []);
    final List<ReportPageSpec> pages = ReportPages.plan(report);

    await pumpPage(tester, report, pages.single, 1);
    expect(find.text('Nothing matches this selection.'), findsOneWidget);
    expect(find.text('Page 1 of 1'), findsOneWidget);
  });
}
