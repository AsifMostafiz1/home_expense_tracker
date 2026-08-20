import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

/// ---------------------------------------------------------------------------
/// Shared surface tokens.
///
/// Spacing, tinting and elevation rules that keep every card in the app
/// looking like it came from the same set. The meal and announcement screens
/// still carry private copies of these; they can be migrated onto this file
/// without any visual change.
/// ---------------------------------------------------------------------------
class AppUi {
  const AppUi._();

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Background wash of a colored accent that stays readable in both themes.
  static Color tint(BuildContext context, Color color) =>
      color.withOpacity(isDark(context) ? 0.20 : 0.10);

  /// Foreground version of an accent color, lightened for dark surfaces.
  static Color accent(BuildContext context, MaterialColor color) =>
      isDark(context) ? color.shade300 : color.shade700;

  static Color body(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87;

  static Color muted(BuildContext context) =>
      (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey)
          .withOpacity(0.65);

  static Color neutralSurface(BuildContext context) =>
      isDark(context) ? Colors.white.withOpacity(0.04) : Colors.grey.shade50;

  static Color hairline(BuildContext context) =>
      Theme.of(context).dividerColor.withOpacity(isDark(context) ? 0.8 : 1);

  static List<BoxShadow> softShadow(BuildContext context) => [
        BoxShadow(
          color: Colors.black.withOpacity(isDark(context) ? 0.28 : 0.05),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];

  /// `Today` / `Yesterday` / `12 August, 2026` — dates people actually read.
  static String dayLabel(DateTime date) {
    final DateTime now = DateTime.now();
    final DateTime day = DateTime(date.year, date.month, date.day);
    final DateTime today = DateTime(now.year, now.month, now.day);
    final int diff = today.difference(day).inDays;

    if (diff == 0) return 'today'.tr;
    if (diff == 1) return 'yesterday'.tr;
    return DateFormat('dd MMMM, yyyy').format(date);
  }

  /// One money format for the whole app, so totals never render as `1250.0`
  /// in one place and `৳1250.0` in another.
  static String money(double amount) => '৳${amount.toStringAsFixed(1)}';

  /// `৳12,000` / `৳1,050.25` — grouped, and only as precise as it needs to be.
  /// House bills run into five figures, where [money]'s fixed decimal is noise.
  static String amount(double value) =>
      '৳${NumberFormat('#,##0.##').format(value)}';

  static const List<String> _monthKeys = [
    'month_jan',
    'month_feb',
    'month_mar',
    'month_apr',
    'month_may',
    'month_jun',
    'month_jul',
    'month_aug',
    'month_sep',
    'month_oct',
    'month_nov',
    'month_dec',
  ];

  /// `August 2026`, in the app's language — `DateFormat` would always answer
  /// in English here, since only the app's own strings are translated.
  static String monthLabel(DateTime month) =>
      '${_monthKeys[month.month - 1].tr} ${month.year}';

  static const List<String> _shortMonthKeys = [
    'mon_jan',
    'mon_feb',
    'mon_mar',
    'mon_apr',
    'mon_may',
    'mon_jun',
    'mon_jul',
    'mon_aug',
    'mon_sep',
    'mon_oct',
    'mon_nov',
    'mon_dec',
  ];

  /// `Aug` — for axis labels and anywhere else the full name would not fit.
  static String shortMonth(DateTime month) =>
      _shortMonthKeys[month.month - 1].tr;
}
