import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/presentation/personal/model/personal_report.dart';
import 'package:demo_project/presentation/personal/model/personal_transaction.dart';
import 'package:demo_project/presentation/personal/model/report_pages.dart';
import 'package:demo_project/presentation/personal/model/report_period.dart';
import 'package:demo_project/presentation/personal/model/subcategory.dart';

void main() {
  const List<Subcategory> subs = [
    Subcategory(id: 'bazar', parent: 'food', name: 'Groceries'),
    Subcategory(id: 'resto', parent: 'food', name: 'Restaurant'),
    Subcategory(id: 'bus', parent: 'transport', name: 'Bus'),
  ];

  const List<PersonalTransaction> ledger = [
    // July
    PersonalTransaction(
        id: '1',
        amount: 500,
        date: '2026-07-30',
        category: 'food',
        subcategory: 'bazar',
        timeHour: 9),
    // August
    PersonalTransaction(
        id: '2',
        amount: 300,
        date: '2026-08-02',
        category: 'food',
        subcategory: 'bazar'),
    PersonalTransaction(
        id: '3',
        amount: 120,
        date: '2026-08-02',
        category: 'food',
        subcategory: 'resto',
        timeHour: 20),
    PersonalTransaction(
        id: '4', amount: 80, date: '2026-08-05', category: 'food'),
    PersonalTransaction(
        id: '5',
        amount: 60,
        date: '2026-08-05',
        category: 'food',
        subcategory: 'gone'),
    PersonalTransaction(
        id: '6',
        amount: 200,
        date: '2026-08-10',
        category: 'transport',
        subcategory: 'bus'),
    PersonalTransaction(
        id: '7',
        amount: 50000,
        date: '2026-08-01',
        category: 'salary',
        flow: MoneyFlow.income),
    // September, outside every range below
    PersonalTransaction(
        id: '8', amount: 999, date: '2026-09-01', category: 'food'),
  ];

  final DateTimeRange august = DateTimeRange(
    start: DateTime(2026, 8, 1),
    end: DateTime(2026, 8, 31),
  );

  group('PersonalReport', () {
    test('both sides and a range cut the ledger, oldest first', () {
      final PersonalReport report = PersonalReport.of(
          ReportFilter(range: august), ledger,
          subcategories: subs);

      expect(report.entries.map((e) => e.id), ['7', '2', '3', '4', '5', '6']);
      expect(report.count, 6);
      expect(report.incomeTotal, 50000);
      expect(report.expenseTotal, 760);
      expect(report.balance, 49240);

      // Every category's share, biggest first, with its count.
      expect(
          report.byCategory.map((c) => c.key), ['salary', 'food', 'transport']);
      expect(report.byCategory[1].amount, 560);
      expect(report.byCategory[1].count, 4);
      expect(report.bySubcategory, isEmpty);
      expect(report.byMonth, isEmpty);
    });

    test('one side keeps only its own rows', () {
      final PersonalReport expense = PersonalReport.of(
          ReportFilter(range: august, flow: MoneyFlow.expense), ledger);
      expect(expense.entries.map((e) => e.id), ['2', '3', '4', '5', '6']);
      expect(expense.incomeTotal, 0);
      expect(expense.balance, -760);

      final PersonalReport income = PersonalReport.of(
          ReportFilter(range: august, flow: MoneyFlow.income), ledger);
      expect(income.entries.map((e) => e.id), ['7']);
    });

    test('a category shows its tags, with the untagged as one bucket', () {
      final PersonalReport report = PersonalReport.of(
        ReportFilter(range: august, categories: {'food'}),
        ledger,
        subcategories: subs,
      );

      expect(report.expenseTotal, 560);
      expect(report.byCategory, isEmpty);
      // A tag that no longer exists counts as no tag.
      expect(report.bySubcategory.map((b) => b.key),
          ['bazar', ReportFilter.untaggedIn('food'), 'resto']);
      expect(report.bySubcategory[1].amount, 140);
      expect(report.bySubcategory[1].count, 2);
      expect(report.bySubcategory.first.label, 'Groceries');
    });

    test('a tag narrows to its own rows, and untagged to the rest', () {
      final PersonalReport tagged = PersonalReport.of(
        ReportFilter(
            range: august,
            categories: {'food'},
            tags: {
              'food': {'resto'}
            }),
        ledger,
        subcategories: subs,
      );
      expect(tagged.entries.map((e) => e.id), ['3']);
      // The one tag asked for is still a bucket; a summary table of a
      // single row is what the page itself leaves out.
      expect(tagged.bySubcategory.map((b) => b.key), ['resto']);

      final PersonalReport untagged = PersonalReport.of(
        ReportFilter(
            range: august,
            categories: {'food'},
            tags: {
              'food': {ReportFilter.untagged}
            }),
        ledger,
        subcategories: subs,
      );
      expect(untagged.entries.map((e) => e.id), ['4', '5']);
    });

    test('a range across months is also told month by month', () {
      final PersonalReport report = PersonalReport.of(
        ReportFilter(
          flow: MoneyFlow.expense,
          range: DateTimeRange(
              start: DateTime(2026, 7, 1), end: DateTime(2026, 8, 31)),
        ),
        ledger,
      );

      expect(report.expenseTotal, 1260);
      expect(report.byMonth.map((b) => b.key), ['2026-07', '2026-08']);
      expect(report.byMonth.first.amount, 500);
      expect(report.byMonth.last.count, 5);
    });

    test('the range edges are honoured by day, not by clock', () {
      final PersonalReport slice = PersonalReport.of(
        ReportFilter(
          range: DateTimeRange(
              start: DateTime(2026, 8, 2, 23), end: DateTime(2026, 8, 5, 1)),
        ),
        ledger,
      );
      expect(slice.entries.map((e) => e.id), ['2', '3', '4', '5']);
    });

    test('several categories each keep their own tags', () {
      final PersonalReport report = PersonalReport.of(
        ReportFilter(
          range: august,
          categories: {'food', 'transport'},
          // Food narrowed to one tag, transport left whole: the narrowing
          // is the category's own and reaches no further.
          tags: {
            'food': {'resto'}
          },
        ),
        ledger,
        subcategories: subs,
      );

      expect(report.entries.map((e) => e.id), ['3', '6']);
      expect(report.expenseTotal, 320);
      // Two categories, so their shares are told as well as their tags —
      // and a tag row says which category it belongs to through its parent.
      expect(report.byCategory.map((b) => b.key), ['transport', 'food']);
      expect(report.bySubcategory.map((b) => b.key), ['bus', 'resto']);
      expect(report.bySubcategory.first.parent, 'transport');
    });

    test('untagged is counted per category, never pooled', () {
      final PersonalReport report = PersonalReport.of(
        ReportFilter(
          range: august,
          categories: {'food', 'salary'},
          // Neither category has the other's tags, so both untagged rows
          // are kept — under keys of their own.
          tags: {
            'food': {ReportFilter.untagged},
            'salary': {ReportFilter.untagged},
          },
        ),
        ledger,
        subcategories: subs,
      );

      expect(report.entries.map((e) => e.id), ['7', '4', '5']);
      expect(
          report.bySubcategory.map((b) => b.key),
          [ReportFilter.untaggedIn('salary'), ReportFilter.untaggedIn('food')]);
      expect(report.bySubcategory.last.count, 2);
    });

    test('changing side or category drops what sat inside it', () {
      final ReportFilter deep = ReportFilter(
        range: august,
        flow: MoneyFlow.expense,
        categories: {'food', 'transport'},
        tags: {
          'food': {'resto'},
          'transport': {'bus'},
        },
      );

      // A dropped category takes its tags with it; the ones that stayed
      // keep theirs.
      final ReportFilter narrowed = deep.withCategories({'transport'});
      expect(narrowed.tags.keys, ['transport']);
      expect(narrowed.tagsOf('food'), isEmpty);

      expect(deep.withFlow(null).categories, isEmpty);
      expect(deep.withFlow(null).tags, isEmpty);

      // Emptying one category's tags is "all of them" again, not a filter
      // that matches nothing.
      expect(deep.withTags('food', const {}).tags.keys, ['transport']);
      expect(deep.withTags('food', {'bazar'}).tagsOf('food'), {'bazar'});
      // A category that is not in the report cannot carry tags.
      expect(deep.withTags('rent', {'x'}).tagsOf('rent'), isEmpty);

      expect(deep.withRange(august).tagsOf('food'), {'resto'});
      expect(deep.hasTags, isTrue);
      expect(deep.spansMonths, isFalse);
    });
  });

  group('ReportPeriod', () {
    final DateTime now = DateTime(2026, 8, 30, 14, 5);

    test('the presets are the runs of days they say', () {
      DateTimeRange r(ReportPeriod p) => p.rangeOn(now)!;

      expect(r(ReportPeriod.thisMonth).start, DateTime(2026, 8, 1));
      expect(r(ReportPeriod.thisMonth).end, DateTime(2026, 8, 30));
      expect(r(ReportPeriod.lastMonth).start, DateTime(2026, 7, 1));
      expect(r(ReportPeriod.lastMonth).end, DateTime(2026, 7, 31));
      expect(r(ReportPeriod.threeMonths).start, DateTime(2026, 6, 1));
      expect(r(ReportPeriod.sixMonths).start, DateTime(2026, 3, 1));
      expect(r(ReportPeriod.thisYear).start, DateTime(2026, 1, 1));
      expect(r(ReportPeriod.lastYear).start, DateTime(2025, 1, 1));
      expect(r(ReportPeriod.lastYear).end, DateTime(2025, 12, 31));
      expect(ReportPeriod.custom.rangeOn(now), isNull);
    });

    test('all time runs from the first entry to today, never backwards', () {
      final DateTimeRange whole = ReportPeriod.allTime
          .rangeOn(now, earliest: DateTime(2024, 3, 17, 9, 30))!;
      expect(whole.start, DateTime(2024, 3, 17));
      expect(whole.end, DateTime(2026, 8, 30));

      // No ledger yet: today alone, not the dawn of time.
      final DateTimeRange none = ReportPeriod.allTime.rangeOn(now)!;
      expect(none.start, DateTime(2026, 8, 30));
      expect(none.end, DateTime(2026, 8, 30));

      // A first entry dated after today (a house copy into next month)
      // does not turn the range inside out.
      final DateTimeRange ahead =
          ReportPeriod.allTime.rangeOn(now, earliest: DateTime(2026, 9, 2))!;
      expect(ahead.start, DateTime(2026, 8, 30));
    });

    test('January looks back into the year before', () {
      final DateTime january = DateTime(2026, 1, 15);
      expect(ReportPeriod.lastMonth.rangeOn(january)!.start,
          DateTime(2025, 12, 1));
      expect(
          ReportPeriod.lastMonth.rangeOn(january)!.end, DateTime(2025, 12, 31));
      expect(
          ReportPeriod.sixMonths.rangeOn(january)!.start, DateTime(2025, 8, 1));
    });
  });

  group('ReportPages', () {
    PersonalReport reportOf(int rows) => PersonalReport.of(
          ReportFilter(range: august, flow: MoneyFlow.expense),
          [
            for (int i = 0; i < rows; i++)
              PersonalTransaction(
                id: '$i',
                amount: 10,
                date: '2026-08-${(i % 28 + 1).toString().padLeft(2, '0')}',
                category: i.isEven ? 'food' : 'transport',
              ),
          ],
        );

    test('the layout leaves a whole number of rows on a page', () {
      expect(ReportLayout.rowsPerPage, greaterThan(20));
      expect(ReportLayout.rowsPerPage * ReportLayout.rowHeight,
          lessThanOrEqualTo(ReportLayout.rowsArea));
    });

    test('a short report is one page with the summary at its foot', () {
      final List<ReportPageSpec> pages = ReportPages.plan(reportOf(10));
      expect(pages.length, 1);
      expect(pages.single.rows.length, 10);
      expect(pages.single.summary, isTrue);
    });

    test('an empty report is still a page, summary included', () {
      final List<ReportPageSpec> pages = ReportPages.plan(reportOf(0));
      expect(pages.length, 1);
      expect(pages.single.rows, isEmpty);
      expect(pages.single.summary, isTrue);
    });

    test('a full page pushes the summary onto a page of its own', () {
      final int perPage = ReportLayout.rowsPerPage;
      final List<ReportPageSpec> pages = ReportPages.plan(reportOf(perPage));
      expect(pages.length, 2);
      expect(pages.first.rows.length, perPage);
      expect(pages.first.summary, isFalse);
      expect(pages.last.rows, isEmpty);
      expect(pages.last.summary, isTrue);
      expect(pages.last.number, 2);
    });

    test('rows spill in page-sized chunks, numbered in order', () {
      final int perPage = ReportLayout.rowsPerPage;
      final List<ReportPageSpec> pages =
          ReportPages.plan(reportOf(perPage * 2 + 3));
      expect(pages.map((p) => p.rows.length), [perPage, perPage, 3]);
      expect(pages.map((p) => p.number), [1, 2, 3]);
      expect(pages.last.summary, isTrue);
    });

    test('a summary that would outgrow a page gives up rows, longest first',
        () {
      // Two tables at the cap cannot share a page; the longer is cut until
      // the pair fits, and neither is cut below the least that is a table.
      final SummaryRows rows =
          SummaryRows.of(categories: 40, tags: 0, months: 36);
      expect(rows.height, lessThanOrEqualTo(ReportLayout.summaryPageArea));
      expect(rows.categories + rows.months, greaterThan(SummaryRows.minRows));
      expect(rows.categories, lessThanOrEqualTo(ReportLayout.maxSummaryRows));
      expect(rows.months, lessThanOrEqualTo(ReportLayout.maxSummaryRows));
      expect(SummaryRows.of(categories: 3, tags: 0, months: 0).categories, 3);
      expect(
          SummaryRows.of(categories: 1, tags: 1, months: 1).height,
          ReportLayout.blockGap * 2 +
              ReportLayout.totalsHeight +
              ReportLayout.ownerFooterHeight);
    });

    test('summary tables with one row are left out, long ones capped', () {
      final PersonalReport two = reportOf(4);
      expect(ReportPages.summaryRows(two).categories, 2);

      final PersonalReport one = PersonalReport.of(
          ReportFilter(range: august, flow: MoneyFlow.expense), const [
        PersonalTransaction(
            id: 'a', amount: 1, date: '2026-08-01', category: 'food'),
        PersonalTransaction(
            id: 'b', amount: 1, date: '2026-08-02', category: 'food'),
      ]);
      expect(ReportPages.summaryRows(one).categories, 0);

      final PersonalReport many = PersonalReport.of(
          ReportFilter(range: august, flow: MoneyFlow.expense), [
        for (int i = 0; i < 30; i++)
          PersonalTransaction(
              id: '$i', amount: 1, date: '2026-08-01', category: 'c$i'),
      ]);
      expect(ReportPages.summaryRows(many).categories,
          ReportLayout.maxSummaryRows);
    });
  });
}
