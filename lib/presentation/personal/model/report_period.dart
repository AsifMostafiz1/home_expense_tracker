import 'package:flutter/material.dart';

/// The runs of days a report can be asked for. [custom] is whatever the
/// calendar returned, and has no range of its own.
enum ReportPeriod {
  thisMonth,
  lastMonth,
  threeMonths,
  sixMonths,
  thisYear,
  lastYear,
  allTime,
  custom;

  String get labelKey {
    switch (this) {
      case ReportPeriod.thisMonth:
        return 'period_this_month';
      case ReportPeriod.lastMonth:
        return 'period_last_month';
      case ReportPeriod.threeMonths:
        return 'period_three_months';
      case ReportPeriod.sixMonths:
        return 'period_six_months';
      case ReportPeriod.thisYear:
        return 'period_this_year';
      case ReportPeriod.lastYear:
        return 'period_last_year';
      case ReportPeriod.allTime:
        return 'period_all_time';
      case ReportPeriod.custom:
        return 'period_custom';
    }
  }

  /// The days this stands for, as of [now]. The open-ended ones stop at
  /// today: a report is of what has happened. [allTime] starts on
  /// [earliest] — the ledger's first day, which only the caller knows — and
  /// on today when there is none, so an empty ledger asks for an empty day
  /// rather than the year 2000.
  DateTimeRange? rangeOn(DateTime now, {DateTime? earliest}) {
    final DateTime today = DateUtils.dateOnly(now);
    switch (this) {
      case ReportPeriod.thisMonth:
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1), end: today);
      case ReportPeriod.lastMonth:
        return DateTimeRange(
          start: DateTime(now.year, now.month - 1, 1),
          end: DateTime(now.year, now.month, 0),
        );
      case ReportPeriod.threeMonths:
        return DateTimeRange(
            start: DateTime(now.year, now.month - 2, 1), end: today);
      case ReportPeriod.sixMonths:
        return DateTimeRange(
            start: DateTime(now.year, now.month - 5, 1), end: today);
      case ReportPeriod.thisYear:
        return DateTimeRange(start: DateTime(now.year, 1, 1), end: today);
      case ReportPeriod.lastYear:
        return DateTimeRange(
          start: DateTime(now.year - 1, 1, 1),
          end: DateTime(now.year - 1, 12, 31),
        );
      case ReportPeriod.allTime:
        final DateTime start =
            earliest == null ? today : DateUtils.dateOnly(earliest);
        return DateTimeRange(
            start: start.isAfter(today) ? today : start, end: today);
      case ReportPeriod.custom:
        return null;
    }
  }
}
