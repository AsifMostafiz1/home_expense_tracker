import 'package:flutter/material.dart';

import 'personal_category.dart';
import 'personal_transaction.dart';
import 'subcategory.dart';

/// What the report is asked for.
///
/// A run of days, one side of the ledger or both, and optionally one
/// category and one tag inside it. The range is inclusive at both ends and
/// compared by day, never by clock — an entry at 11pm on the last day is in.
class ReportFilter {
  final DateTimeRange range;

  /// One side, or null for both.
  final MoneyFlow? flow;

  /// A category key, or empty for every category.
  final String category;

  /// A subcategory id, [untagged] for the rows with no tag, or empty for
  /// all of them. Only means anything with a [category] set.
  final String subcategory;

  const ReportFilter({
    required this.range,
    this.flow,
    this.category = '',
    this.subcategory = '',
  });

  /// The rows of a category that carry no tag — or a tag that no longer
  /// exists, which to the reader is the same thing.
  static const String untagged = '__untagged__';

  bool get bothSides => flow == null;

  bool get hasCategory => category.isNotEmpty;

  /// Whether the range runs across more than one calendar month.
  bool get spansMonths =>
      PersonalTransaction.monthKeyOf(range.start) !=
      PersonalTransaction.monthKeyOf(range.end);

  /// Switching side drops the category and the tag: they may belong to the
  /// other side's list. Switching category drops the tag for the same
  /// reason — the same rule the entry sheet follows.
  ReportFilter withFlow(MoneyFlow? flow) =>
      ReportFilter(range: range, flow: flow);

  ReportFilter withCategory(String key) =>
      ReportFilter(range: range, flow: flow, category: key);

  ReportFilter withSubcategory(String id) => ReportFilter(
      range: range, flow: flow, category: category, subcategory: id);

  ReportFilter withRange(DateTimeRange range) => ReportFilter(
      range: range, flow: flow, category: category, subcategory: subcategory);
}

/// One named share of a report — a category's, a tag's, or a month's.
class ReportBucket {
  /// A category key, a subcategory id, [ReportFilter.untagged], or a
  /// `yyyy-MM` month key.
  final String key;

  /// A tag's name. Categories and months are named by the reader from the
  /// key — one through translation, the other through the calendar.
  final String label;

  final double amount;
  final int count;

  const ReportBucket(this.key, this.label, this.amount, this.count);
}

/// The ledger cut the way a [ReportFilter] asks, with every figure the
/// report draws worked out once, here, rather than in the pages.
///
/// Built from the whole in-memory ledger — the same fold the month screen
/// does, over a range instead of a month.
class PersonalReport {
  final ReportFilter filter;

  /// What survived the filter, oldest first — the order a printed report
  /// is read in.
  final List<PersonalTransaction> entries;

  final double incomeTotal;
  final double expenseTotal;

  /// Every category's share, biggest first. Empty when a category is set —
  /// there is only one.
  final List<ReportBucket> byCategory;

  /// The set category's tags, biggest first, with the untagged rows as one
  /// bucket of their own. Empty unless a category is set and no tag is.
  final List<ReportBucket> bySubcategory;

  /// Month by month, oldest first. Empty unless the range spans months.
  final List<ReportBucket> byMonth;

  const PersonalReport({
    required this.filter,
    required this.entries,
    required this.incomeTotal,
    required this.expenseTotal,
    required this.byCategory,
    required this.bySubcategory,
    required this.byMonth,
  });

  int get count => entries.length;

  bool get isEmpty => entries.isEmpty;

  double get balance => incomeTotal - expenseTotal;

  static PersonalReport of(
    ReportFilter filter,
    Iterable<PersonalTransaction> all, {
    List<Subcategory> subcategories = const [],
  }) {
    final String from = PersonalTransaction.keyOf(filter.range.start);
    final String to = PersonalTransaction.keyOf(filter.range.end);

    // The tags that exist inside the set category; anything else a row
    // carries is as good as no tag.
    final Map<String, Subcategory> tags = {
      for (final Subcategory sub in subcategories)
        if (sub.parent == filter.category) sub.id: sub,
    };
    String tagOf(PersonalTransaction entry) =>
        tags.containsKey(entry.subcategory)
            ? entry.subcategory
            : ReportFilter.untagged;

    final List<PersonalTransaction> entries = [];
    for (final PersonalTransaction entry in all) {
      if (filter.flow != null && entry.flow != filter.flow) continue;
      if (entry.date.compareTo(from) < 0 || entry.date.compareTo(to) > 0) {
        continue;
      }
      if (filter.hasCategory) {
        if (categoryOf(entry) != filter.category) continue;
        if (filter.subcategory.isNotEmpty &&
            tagOf(entry) != filter.subcategory) {
          continue;
        }
      }
      entries.add(entry);
    }
    entries.sort((a, b) {
      final int byDate = a.date.compareTo(b.date);
      return byDate != 0 ? byDate : a.minuteOfDay.compareTo(b.minuteOfDay);
    });

    double income = 0;
    double expense = 0;
    for (final PersonalTransaction entry in entries) {
      if (entry.isIncome) {
        income += entry.amount;
      } else {
        expense += entry.amount;
      }
    }

    List<ReportBucket> bucketsBy(
      String Function(PersonalTransaction) keyOf, {
      String Function(String key)? labelOf,
      bool sortByAmount = true,
    }) {
      final Map<String, double> sums = {};
      final Map<String, int> counts = {};
      for (final PersonalTransaction entry in entries) {
        final String key = keyOf(entry);
        sums[key] = (sums[key] ?? 0) + entry.amount;
        counts[key] = (counts[key] ?? 0) + 1;
      }
      final List<ReportBucket> buckets = [
        for (final MapEntry<String, double> e in sums.entries)
          ReportBucket(
              e.key, labelOf?.call(e.key) ?? '', e.value, counts[e.key] ?? 0),
      ];
      if (sortByAmount) {
        buckets.sort((a, b) => b.amount.compareTo(a.amount));
      } else {
        buckets.sort((a, b) => a.key.compareTo(b.key));
      }
      return buckets;
    }

    return PersonalReport(
      filter: filter,
      entries: List<PersonalTransaction>.unmodifiable(entries),
      incomeTotal: income,
      expenseTotal: expense,
      byCategory: filter.hasCategory ? const [] : bucketsBy(categoryOf),
      bySubcategory: filter.hasCategory && filter.subcategory.isEmpty
          ? bucketsBy(tagOf, labelOf: (key) => tags[key]?.name ?? '')
          : const [],
      byMonth: filter.spansMonths
          ? bucketsBy((entry) => entry.monthKey, sortByAmount: false)
          : const [],
    );
  }

  /// An entry saved before a category was picked has none; it is counted
  /// under the same bucket the month's breakdown counts it in.
  static String categoryOf(PersonalTransaction entry) =>
      entry.category.isEmpty ? PersonalCategory.unknown.key : entry.category;
}
