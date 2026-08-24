import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import '../model/personal_summary.dart';

/// Six months of money in and out, side by side.
///
/// Drawn rather than pulled in from a charting package: two bars a month and
/// a baseline is the whole picture, and a hand-drawn one takes the app's own
/// colors and text styles instead of fighting a library's.
///
/// Tapping a month reads it out underneath — bars answer "which month was
/// heavy", but the actual taka is what anybody asks next, and a chart nobody
/// can interrogate is decoration.
///
/// Folded away to start with. History is the thing you go looking for, not
/// the thing you came for, and this month's own figures sit right above it —
/// so the chart earns its 200 pixels only once it is asked for. Folded, it
/// still answers the six-month totals: a section that collapses to a bare
/// title is one nobody bothers opening again.
///
/// Open or shut is the caller's to hold. This widget is rebuilt and thrown
/// away as the list scrolls, and a fold that forgot itself every time it left
/// the screen would be worse than no fold at all.
class MoneyTrendChart extends StatefulWidget {
  final List<MonthMoney> months;

  /// The month the rest of the screen is showing — drawn brighter than the
  /// ones on either side of it while nothing is picked.
  final DateTime focused;

  final bool expanded;
  final VoidCallback onToggle;

  const MoneyTrendChart({
    super.key,
    required this.months,
    required this.focused,
    required this.expanded,
    required this.onToggle,
  });

  static const Color income = Color(0xFF2E9E6B);
  static const Color expense = Color(0xFFE2603F);

  @override
  State<MoneyTrendChart> createState() => _MoneyTrendChartState();
}

class _MoneyTrendChartState extends State<MoneyTrendChart> {
  /// Which column the user tapped, if any.
  int? _selected;

  @override
  void didUpdateWidget(MoneyTrendChart old) {
    super.didUpdateWidget(old);
    // A month switch or a new entry redraws the six columns; a selection
    // pointing at a column that may no longer mean the same thing goes.
    if (old.focused != widget.focused ||
        old.months.length != widget.months.length) {
      _selected = null;
    }
  }

  void _handleTap(Offset position, double width) {
    if (widget.months.isEmpty || width <= 0) return;

    final int index = (position.dx / (width / widget.months.length))
        .floor()
        .clamp(0, widget.months.length - 1);

    // Tapping the open column again closes it.
    setState(() => _selected = _selected == index ? null : index);
  }

  bool get _empty => widget.months.every((month) => month.isEmpty);

  double get _sixMonthIncome =>
      widget.months.fold<double>(0, (sum, month) => sum + month.income);

  double get _sixMonthExpense =>
      widget.months.fold<double>(0, (sum, month) => sum + month.expense);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      // The height glides; what is inside is swapped rather than cross-faded,
      // so a shut card costs nothing to lay out and the chart is only built
      // once it is actually on screen.
      clipBehavior: Clip.antiAlias,
      child: AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        alignment: Alignment.topCenter,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(context),
            if (widget.expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 16, 12),
                child: _buildChart(context),
              ),
          ],
        ),
      ),
    );
  }

  /// The whole strip is the target, not just the chevron — a 20-pixel arrow
  /// is a poor thing to ask a thumb to find.
  Widget _buildHeader(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onToggle,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'last_six_months'.tr,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.bold,
                        color: AppUi.body(context),
                      ),
                    ),
                    const SizedBox(height: 6),
                    // Shut, this is what the card is for; open, it is the
                    // chart's legend. Either way it is the same two dots
                    // against the same two words.
                    widget.expanded
                        ? _buildLegend(context)
                        : _buildFoldedTotals(context),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Tooltip(
                message: (widget.expanded ? 'hide_chart' : 'show_chart').tr,
                child: AnimatedRotation(
                  turns: widget.expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 22,
                    color: AppUi.muted(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What the six months came to, for a card nobody has opened.
  Widget _buildFoldedTotals(BuildContext context) {
    if (_empty) {
      return Text(
        'nothing_to_chart'.tr,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
      );
    }

    return Wrap(
      spacing: 14,
      runSpacing: 4,
      children: [
        _readoutValue(
            context, 'income'.tr, _sixMonthIncome, MoneyTrendChart.income),
        _readoutValue(context, 'expense_word'.tr, _sixMonthExpense,
            MoneyTrendChart.expense),
      ],
    );
  }

  Widget _buildLegend(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: [
        _legendDot(context, MoneyTrendChart.income, 'income'.tr),
        _legendDot(context, MoneyTrendChart.expense, 'expense_word'.tr),
      ],
    );
  }

  Widget _buildChart(BuildContext context) {
    final MonthMoney? picked =
        _selected == null ? null : widget.months[_selected!];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 148,
          child: _empty
              ? Center(
                  child: Text(
                    'nothing_to_chart'.tr,
                    style: TextStyle(fontSize: 12, color: AppUi.muted(context)),
                  ),
                )
              : LayoutBuilder(
                  builder: (context, constraints) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) =>
                        _handleTap(details.localPosition, constraints.maxWidth),
                    child: CustomPaint(
                      size: Size.infinite,
                      painter: _TrendPainter(
                        months: widget.months,
                        focused: widget.focused,
                        selected: _selected,
                        income: MoneyTrendChart.income,
                        expense: MoneyTrendChart.expense,
                        grid: AppUi.hairline(context),
                        label: AppUi.muted(context),
                        focusedLabel: AppUi.body(context),
                      ),
                    ),
                  ),
                ),
        ),
        if (!_empty) ...[
          const SizedBox(height: 10),
          picked == null ? _buildHint(context) : _buildReadout(context, picked),
        ],
      ],
    );
  }

  /// Tapping a chart is not obvious enough to leave unsaid.
  Widget _buildHint(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.touch_app_outlined, size: 13, color: AppUi.muted(context)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'tap_a_month'.tr,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
          ),
        ),
      ],
    );
  }

  /// What the tapped column is worth, on both sides.
  Widget _buildReadout(BuildContext context, MonthMoney month) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: AppUi.neutralSurface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppUi.monthLabel(month.month),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 14,
                  runSpacing: 4,
                  children: [
                    _readoutValue(context, 'income'.tr, month.income,
                        MoneyTrendChart.income),
                    _readoutValue(context, 'expense_word'.tr, month.expense,
                        MoneyTrendChart.expense),
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _selected = null),
            icon: const Icon(Icons.close_rounded, size: 16),
            color: AppUi.muted(context),
            visualDensity: VisualDensity.compact,
            splashRadius: 16,
            tooltip: 'close'.tr,
          ),
        ],
      ),
    );
  }

  Widget _readoutValue(
    BuildContext context,
    String label,
    double amount,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ',
          style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
        ),
        Text(
          AppUi.amount(amount),
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: AppUi.body(context),
          ),
        ),
      ],
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

  /// The tapped column, when there is one — it takes the highlight over the
  /// month the screen happens to be showing.
  final int? selected;

  final Color income;
  final Color expense;
  final Color grid;
  final Color label;
  final Color focusedLabel;

  _TrendPainter({
    required this.months,
    required this.focused,
    required this.selected,
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

      // With a column open it owns the highlight; with none, the month the
      // screen is showing keeps it.
      final bool lit = selected == null
          ? (month.month.year == focused.year &&
              month.month.month == focused.month)
          : selected == i;

      if (selected == i) {
        // A quiet plate behind the picked column, so the readout below is
        // visibly about this one.
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            Rect.fromLTWH(centre - slot / 2 + 2, 0, slot - 4, chartHeight),
            const Radius.circular(8),
          ),
          Paint()..color = grid.withOpacity(0.45),
        );
      }

      _bar(canvas, left, chartHeight, month.income, peak, income, lit);
      _bar(canvas, left + _barWidth + _barGap, chartHeight, month.expense,
          peak, expense, lit);

      _monthLabel(canvas, centre, chartHeight, month.month, lit);
    }
  }

  void _bar(
    Canvas canvas,
    double left,
    double chartHeight,
    double value,
    double peak,
    Color color,
    bool lit,
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
      Paint()..color = lit ? color : color.withOpacity(0.35),
    );
  }

  void _monthLabel(
    Canvas canvas,
    double centre,
    double chartHeight,
    DateTime month,
    bool lit,
  ) {
    final TextPainter painter = TextPainter(
      text: TextSpan(
        text: AppUi.shortMonth(month),
        style: TextStyle(
          fontSize: 10,
          fontWeight: lit ? FontWeight.w900 : FontWeight.w500,
          color: lit ? focusedLabel : label,
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
      old.selected != selected ||
      old.income != income ||
      old.expense != expense ||
      old.label != label;
}
