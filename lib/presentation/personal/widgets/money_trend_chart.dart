import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import '../model/personal_summary.dart';

/// Six months of money in and out, side by side.
///
/// Drawn rather than pulled in from a charting package: two bars a month and
/// a baseline is the whole picture, and a hand-drawn one takes the app's own
/// colors and text styles instead of fighting a library's.
class MoneyTrendChart extends StatelessWidget {
  final List<MonthMoney> months;

  /// The month the rest of the screen is showing — drawn brighter than the
  /// ones on either side of it.
  final DateTime focused;

  const MoneyTrendChart({
    super.key,
    required this.months,
    required this.focused,
  });

  static const Color _income = Color(0xFF2E9E6B);
  static const Color _expense = Color(0xFFE2603F);

  @override
  Widget build(BuildContext context) {
    final bool empty = months.every((month) => month.isEmpty);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'last_six_months'.tr,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context),
                  ),
                ),
              ),
              _legendDot(context, _income, 'income'.tr),
              const SizedBox(width: 12),
              _legendDot(context, _expense, 'expense_word'.tr),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: 148,
            child: empty
                ? Center(
                    child: Text(
                      'nothing_to_chart'.tr,
                      style: TextStyle(fontSize: 12, color: AppUi.muted(context)),
                    ),
                  )
                : CustomPaint(
                    size: Size.infinite,
                    painter: _TrendPainter(
                      months: months,
                      focused: focused,
                      income: _income,
                      expense: _expense,
                      grid: AppUi.hairline(context),
                      label: AppUi.muted(context),
                      focusedLabel: AppUi.body(context),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _legendDot(BuildContext context, Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
        ),
      ],
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<MonthMoney> months;
  final DateTime focused;
  final Color income;
  final Color expense;
  final Color grid;
  final Color label;
  final Color focusedLabel;

  _TrendPainter({
    required this.months,
    required this.focused,
    required this.income,
    required this.expense,
    required this.grid,
    required this.label,
    required this.focusedLabel,
  });

  static const double _labelStrip = 20;
  static const double _barWidth = 11;
  static const double _barGap = 4;

  @override
  void paint(Canvas canvas, Size size) {
    if (months.isEmpty) return;

    final double chartHeight = size.height - _labelStrip;
    if (chartHeight <= 0) return;

    // Everything is drawn against the tallest single bar in view, so the
    // shape of a quiet month is still readable next to a heavy one.
    double peak = 0;
    for (final MonthMoney month in months) {
      if (month.peak > peak) peak = month.peak;
    }
    if (peak <= 0) return;

    final Paint gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;

    // Three lines: the baseline, and halfway and full height as quiet
    // reference marks.
    for (int i = 0; i <= 2; i++) {
      final double y = chartHeight - (chartHeight * i / 2);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final double slot = size.width / months.length;
    const double pairWidth = _barWidth * 2 + _barGap;

    for (int i = 0; i < months.length; i++) {
      final MonthMoney month = months[i];
      final double centre = slot * i + slot / 2;
      final double left = centre - pairWidth / 2;
      final bool isFocused = month.month.year == focused.year &&
          month.month.month == focused.month;

      _bar(canvas, left, chartHeight, month.income, peak, income, isFocused);
      _bar(canvas, left + _barWidth + _barGap, chartHeight, month.expense,
          peak, expense, isFocused);

      _monthLabel(canvas, centre, chartHeight, month.month, isFocused);
    }
  }

  void _bar(
    Canvas canvas,
    double left,
    double chartHeight,
    double value,
    double peak,
    Color color,
    bool isFocused,
  ) {
    if (value <= 0) return;

    // A month with a token amount in it still gets a visible stub, so "some"
    // never looks like "none".
    final double height =
        (chartHeight * (value / peak)).clamp(3.0, chartHeight);

    final RRect bar = RRect.fromRectAndCorners(
      Rect.fromLTWH(left, chartHeight - height, _barWidth, height),
      topLeft: const Radius.circular(4),
      topRight: const Radius.circular(4),
    );

    canvas.drawRRect(
      bar,
      Paint()..color = isFocused ? color : color.withOpacity(0.35),
    );
  }

  void _monthLabel(
    Canvas canvas,
    double centre,
    double chartHeight,
    DateTime month,
    bool isFocused,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: AppUi.shortMonth(month),
        style: TextStyle(
          fontSize: 10,
          fontWeight: isFocused ? FontWeight.w900 : FontWeight.w500,
          color: isFocused ? focusedLabel : label,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    painter.paint(
      canvas,
      Offset(centre - painter.width / 2, chartHeight + 6),
    );
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.months != months ||
      old.focused != focused ||
      old.income != income ||
      old.expense != expense ||
      old.label != label;
}
