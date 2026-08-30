import 'package:flutter/material.dart';

import 'personal_category.dart';
import 'personal_transaction.dart';
import 'subcategory.dart';

/// What the report is asked for.
///
/// A run of days, one side of the ledger or both, and optionally a set of
/// categories with — inside each of them, separately — a set of tags. The
/// range is inclusive at both ends and compared by day, never by clock — an
/// entry at 11pm on the last day is in.
class ReportFilter {
  final DateTimeRange range;

  /// One side, or null for both.
  final MoneyFlow? flow;

  /// The category keys the report is cut to; empty for every category.
  final Set<String> categories;

  /// Per category, which tags inside it survive: subcategory ids, and
  /// [untagged] for the rows carrying none. Kept per category rather than in
  /// one flat set because a tag only means anything under its own parent —
  /// "bazar" in food and "bazar" in shopping are two different narrowings,
  /// and untagged food is not untagged transport.
  ///
  /// A category this map holds nothing for — or an empty set for — keeps all
  /// of its rows. Keys outside [categories] are ignored.
  final Map<String, Set<String>> tags;

  const ReportFilter({
    required this.range,
    this.flow,
    this.categories = const {},
    this.tags = const {},
  });

  /// The rows of a category that carry no tag — or a tag that no longer
  /// exists, or one belonging to another category, which to the reader is
  /// the same thing.
  static const String untagged = '__untagged__';

  /// One category's untagged rows, as a bucket key. With several categories
  /// in a report their untagged rows are several shares, not one, so the
  /// bucket carries the category it came from inside its key.
  static String untaggedIn(String category) => '$untagged:$category';

  static bool isUntagged(String key) =>
      key == untagged || key.startsWith('$untagged:');

  bool get bothSides => flow == null;

  bool get hasCategory => categories.isNotEmpty;

  /// The tags kept inside one category; empty means every tag of it.
  Set<String> tagsOf(String category) => tags[category] ?? const {};

  /// Whether any category at all has been narrowed to some of its tags.
  bool get hasTags => tags.values.any((picked) => picked.isNotEmpty);

  /// Whether the range runs across more than one calendar month.
  bool get spansMonths =>
      PersonalTransaction.monthKeyOf(range.start) !=
      PersonalTransaction.monthKeyOf(range.end);

  /// Switching side drops the categories and their tags: they may belong to
  /// the other side's list.
  ReportFilter withFlow(MoneyFlow? flow) =>
      ReportFilter(range: range, flow: flow);

  /// A new set of categories keeps the tags of the ones that stayed; a
  /// dropped category takes its own tags with it, so re-adding it later
  /// starts from all of them rather than from a narrowing nobody can see.
  ReportFilter withCategories(Set<String> keys) => ReportFilter(
        range: range,
        flow: flow,
        categories: keys,
        tags: {
          for (final MapEntry<String, Set<String>> tag in tags.entries)
            if (keys.contains(tag.key) && tag.value.isNotEmpty)
              tag.key: tag.value,
        },
      );

  /// One category's tags, replaced. An empty pick is no narrowing at all, so
  /// it is dropped rather than stored, and a category that is not selected
  /// cannot carry tags.
  ReportFilter withTags(String category, Set<String> picked) => ReportFilter(
        range: range,
        flow: flow,
        categories: categories,
        tags: {
          for (final MapEntry<String, Set<String>> tag in tags.entries)
            if (tag.key != category) tag.key: tag.value,
          if (picked.isNotEmpty && categories.contains(category))
            category: picked,
        },
      );

  ReportFilter withRange(DateTimeRange range) => ReportFilter(
      range: range, flow: flow, categories: categories, tags: tags);
}

/// One named share of a report — a category's, a tag's, or a month's.
class ReportBucket {
  /// A category key, a subcategory id, an untagged key (see
  /// [ReportFilter.untaggedIn]), or a `yyyy-MM` month key.
  final String key;

  /// A tag's name. Categories and months are named by the reader from the
  /// key — one through translation, the other through the calendar.
  final String label;

  /// The category a tag bucket sits in; empty on the others. A report of
  /// several categories shows their tags in one table, and two categories
  /// may each have a tag of the same name — this is what tells them apart.
  final String parent;

  final double amount;
  final int count;

  const ReportBucket(
    this.key,
    this.label,
    this.amount,
    this.count, {
    this.parent = '',
  });
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

  /// Every category's share, biggest first. Empty when exactly one category
  /// is asked for — there is only one, and the totals already say it.
  final List<ReportBucket> byCategory;

  /// The chosen categories' tags, biggest first, with each category's
  /// untagged rows as a bucket of their own. Empty unless some category is
  /// set: across the whole ledger this table would only repeat the one
  /// above it, at several times the length.
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

    final Map<String, Subcategory> tags = {
      for (final Subcategory sub in subcategories) sub.id: sub,
    };

    /// A row's tag, but only where it belongs: an id from another category —
    /// or one that no longer exists — is as good as no tag at all.
    String tagOf(PersonalTransaction entry) {
      final Subcategory? tag = tags[entry.subcategory];
      return tag != null && tag.parent == categoryOf(entry)
          ? tag.id
          : ReportFilter.untagged;
    }

    /// The same tag as a bucket key, kept apart from the other categories'.
    String tagKeyOf(PersonalTransaction entry) {
      final String tag = tagOf(entry);
      return tag == ReportFilter.untagged
          ? ReportFilter.untaggedIn(categoryOf(entry))
          : tag;
    }

    final List<PersonalTransaction> entries = [];
    for (final PersonalTransaction entry in all) {
      if (filter.flow != null && entry.flow != filter.flow) continue;
      if (entry.date.compareTo(from) < 0 || entry.date.compareTo(to) > 0) {
        continue;
      }
      if (filter.hasCategory) {
        final String category = categoryOf(entry);
        if (!filter.categories.contains(category)) continue;
        // Each category is narrowed on its own tags, or not at all.
        final Set<String> kept = filter.tagsOf(category);
        if (kept.isNotEmpty && !kept.contains(tagOf(entry))) continue;
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
      String Function(PersonalTransaction)? parentOf,
      bool sortByAmount = true,
    }) {
      final Map<String, double> sums = {};
      final Map<String, int> counts = {};
      final Map<String, String> parents = {};
      for (final PersonalTransaction entry in entries) {
        final String key = keyOf(entry);
        sums[key] = (sums[key] ?? 0) + entry.amount;
        counts[key] = (counts[key] ?? 0) + 1;
        if (parentOf != null) parents[key] ??= parentOf(entry);
      }
      final List<ReportBucket> buckets = [
        for (final MapEntry<String, double> e in sums.entries)
          ReportBucket(
            e.key,
            labelOf?.call(e.key) ?? '',
            e.value,
            counts[e.key] ?? 0,
            parent: parents[e.key] ?? '',
          ),
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
      byCategory:
          filter.categories.length == 1 ? const [] : bucketsBy(categoryOf),
      bySubcategory: filter.hasCategory
          ? bucketsBy(
              tagKeyOf,
              labelOf: (key) => tags[key]?.name ?? '',
              parentOf: categoryOf,
            )
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
