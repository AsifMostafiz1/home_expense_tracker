import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../model/personal_category.dart';
import '../model/personal_report.dart';
import '../model/personal_summary.dart';
import '../model/personal_transaction.dart';
import '../model/report_pages.dart';

/// One A4 page of the report, drawn as widgets.
///
/// Widgets rather than a PDF library's text: the PDF engines available to
/// Dart lay glyphs out one by one, and Bangla — its vowel signs before
/// their consonant, its conjuncts — comes out wrong. Flutter's own text
/// engine gets it right, so the page is painted here at A4 proportions and
/// photographed into the PDF afterwards.
///
/// Sized in points ([ReportLayout]) and drawn in fixed colours: paper is
/// white whatever the app's theme, and the row heights the planner counted
/// on must not move with the phone's text size.
class ReportPage extends StatelessWidget {
  final PersonalReport report;
  final ReportPageSpec spec;
  final int pageCount;
  final String ownerName;
  final String ownerPhone;
  final DateTime generatedAt;

  /// Tag names by id, for the category column.
  final Map<String, String> tagNames;

  const ReportPage({
    super.key,
    required this.report,
    required this.spec,
    required this.pageCount,
    required this.ownerName,
    required this.ownerPhone,
    required this.generatedAt,
    required this.tagNames,
  });

  static const Color _ink = Color(0xFF1F2430);
  static const Color _muted = Color(0xFF6B7280);
  static const Color _hairline = Color(0xFFE5E7EB);
  static const Color _fill = Color(0xFFF3F4F6);
  static const Color _income = Color(0xFF2E7D32);
  static const Color _expense = Color(0xFFC62828);

  static final NumberFormat _money = NumberFormat('#,##0.##');

  static String amount(double value) => _money.format(value);

  bool get _isLast => spec.number == pageCount;

  @override
  Widget build(BuildContext context) {
    final Color accent = Theme.of(context).colorScheme.primary;

    return MediaQuery.withNoTextScaling(
      child: Material(
        color: Colors.white,
        child: SizedBox(
          width: ReportLayout.pageWidth,
          height: ReportLayout.pageHeight,
          child: Padding(
            padding: const EdgeInsets.all(ReportLayout.margin),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _header(context, accent),
                const SizedBox(height: ReportLayout.gap),
                _filterStrip(context),
                const SizedBox(height: ReportLayout.gap),
                if (spec.rows.isNotEmpty || spec.number == 1) ...[
                  _tableHeader(context),
                  if (spec.rows.isEmpty)
                    _emptyRow(context)
                  else
                    for (final PersonalTransaction entry in spec.rows)
                      _row(context, entry),
                ],
                // The summary follows the rows straight away, and whatever
                // the page has left over sits under it — a closing block
                // pushed to the foot of an otherwise empty page reads as a
                // page that forgot something.
                if (spec.summary) _summary(context, accent),
                const Spacer(),
                const SizedBox(height: ReportLayout.gap),
                _footer(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ----------------------------------------------------------------- header

  Widget _header(BuildContext context, Color accent) {
    return SizedBox(
      height: ReportLayout.headerHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(Icons.account_balance_wallet_rounded,
                    size: 24, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'app_name'.tr,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: _ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'report_tagline'.tr,
                      style: const TextStyle(fontSize: 9, color: _muted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'report_word'.tr.toUpperCase(),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                      color: accent,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'generated_on'.trParams({
                      'date':
                          DateFormat('d MMM yyyy, h:mm a').format(generatedAt),
                    }),
                    style: const TextStyle(fontSize: 8.5, color: _muted),
                  ),
                ],
              ),
            ],
          ),
          const Spacer(),
          Container(height: 1.5, color: accent.withOpacity(0.35)),
        ],
      ),
    );
  }

  /// What the report is of, in one line — the period, the side, and the
  /// category and tag when set. The reader has no chips to look at.
  Widget _filterStrip(BuildContext context) {
    final ReportFilter filter = report.filter;
    final List<String> parts = [
      '${'period_label'.tr}: ${_rangeLabel(filter.range)}',
      '${'report_type'.tr}: ${filter.flow == null ? 'report_type_all'.tr : (filter.flow == MoneyFlow.income ? 'income'.tr : 'expense_word'.tr)}',
      if (filter.hasCategory)
        '${'col_category'.tr}: ${PersonalCategory.of(filter.category).label}',
      if (filter.subcategory == ReportFilter.untagged)
        '${'subcategory_label'.tr}: ${'untagged'.tr}'
      else if (filter.subcategory.isNotEmpty)
        '${'subcategory_label'.tr}: ${tagNames[filter.subcategory] ?? ''}',
    ];

    return Container(
      height: ReportLayout.filterStripHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        parts.join('   ·   '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 8.5,
          fontWeight: FontWeight.w600,
          color: _ink,
        ),
      ),
    );
  }

  static String _rangeLabel(DateTimeRange range) =>
      '${DateFormat('d MMM yyyy').format(range.start)} – '
      '${DateFormat('d MMM yyyy').format(range.end)}';

  /// ------------------------------------------------------------------ table

  static const double _dateWidth = 62;
  static const double _timeWidth = 58;
  static const double _categoryWidth = 122;
  static const double _amountWidth = 76;

  Widget _tableHeader(BuildContext context) {
    TextStyle style = const TextStyle(
      fontSize: 8,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.6,
      color: _ink,
    );
    Widget cell(String text, double? width,
        {TextAlign align = TextAlign.left}) {
      final Widget child =
          Text(text.toUpperCase(), textAlign: align, maxLines: 1, style: style);
      return width == null
          ? Expanded(child: child)
          : SizedBox(width: width, child: child);
    }

    return Container(
      height: ReportLayout.tableHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: _fill,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Row(
        children: [
          cell('col_date'.tr, _dateWidth),
          cell('col_time'.tr, _timeWidth),
          cell('col_description'.tr, null),
          cell('col_category'.tr, _categoryWidth),
          cell('col_amount'.tr, _amountWidth, align: TextAlign.right),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, PersonalTransaction entry) {
    final PersonalCategory category = PersonalCategory.of(entry.category);
    final String? tag = tagNames[entry.subcategory];
    final bool income = entry.isIncome;

    const TextStyle body = TextStyle(fontSize: 8.5, color: _ink);
    const TextStyle dim = TextStyle(fontSize: 8.5, color: _muted);

    return Container(
      height: ReportLayout.rowHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _hairline, width: 0.8)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: _dateWidth,
            child: Text(DateFormat('dd MMM yy').format(entry.day),
                maxLines: 1, style: dim),
          ),
          SizedBox(
            width: _timeWidth,
            child: Text(entry.time.format(context), maxLines: 1, style: dim),
          ),
          Expanded(
            child: Text(
              entry.note.isEmpty ? category.label : entry.note,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: body,
            ),
          ),
          SizedBox(
            width: _categoryWidth,
            child: Text(
              tag == null ? category.label : '${category.label} · $tag',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: dim,
            ),
          ),
          SizedBox(
            width: _amountWidth,
            child: Text(
              '${income ? '+' : ''}${amount(entry.amount)}',
              textAlign: TextAlign.right,
              maxLines: 1,
              style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: income ? _income : _expense,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyRow(BuildContext context) {
    return Container(
      height: ReportLayout.rowHeight,
      alignment: Alignment.center,
      child: Text(
        'report_empty'.tr,
        style: const TextStyle(fontSize: 8.5, color: _muted),
      ),
    );
  }

  /// ---------------------------------------------------------------- summary

  /// The tables first, the totals after: the reader walks the parts before
  /// being handed the sum, the way a bill lists its lines above the total.
  Widget _summary(BuildContext context, Color accent) {
    final SummaryRows rows = ReportPages.summaryRows(report);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (rows.categories > 0)
          _summaryTable(
            context,
            title: 'by_category'.tr,
            buckets: report.byCategory,
            labelOf: (b) => PersonalCategory.of(b.key).label,
            rows: rows.categories,
          ),
        if (rows.tags > 0)
          _summaryTable(
            context,
            title: 'by_subcategory'.tr,
            buckets: report.bySubcategory,
            labelOf: (b) =>
                b.key == ReportFilter.untagged ? 'untagged'.tr : b.label,
            rows: rows.tags,
          ),
        if (rows.months > 0)
          _summaryTable(
            context,
            title: 'month_by_month'.tr,
            buckets: report.byMonth,
            labelOf: (b) {
              final DateTime? month = MonthMoney.monthFromKey(b.key);
              return month == null
                  ? b.key
                  : DateFormat('MMMM yyyy').format(month);
            },
            rows: rows.months,
          ),
        // Every table opens with its own gap, so the totals carry the one
        // gap that keeps the planner's sum exact whether or not there are
        // tables above them.
        const SizedBox(height: ReportLayout.blockGap),
        _totals(context, accent),
        const SizedBox(height: ReportLayout.blockGap),
        _ownerFooter(context, accent),
      ],
    );
  }

  /// The two sides, and only the two: what came in and what went out is
  /// the whole of what a report is asked; the difference is arithmetic the
  /// reader can do and would rather not be told.
  Widget _totals(BuildContext context, Color accent) {
    Widget cell(String label, double value, Color color) {
      return Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label,
                maxLines: 1,
                style: const TextStyle(fontSize: 9, color: _muted)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                amount(value),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      height: ReportLayout.totalsHeight,
      decoration: BoxDecoration(
        color: accent.withOpacity(0.07),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          cell('total_income'.tr, report.incomeTotal, _income),
          Container(width: 1, height: 34, color: accent.withOpacity(0.2)),
          cell('total_expense'.tr, report.expenseTotal, _expense),
        ],
      ),
    );
  }

  Widget _summaryTable(
    BuildContext context, {
    required String title,
    required List<ReportBucket> buckets,
    required String Function(ReportBucket) labelOf,
    required int rows,
  }) {
    // A cut table spends its last row saying how much was cut.
    final bool cut = buckets.length > rows;
    final List<ReportBucket> shown =
        buckets.take(cut ? rows - 1 : rows).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: ReportLayout.blockGap),
        SizedBox(
          height: ReportLayout.summaryTitleHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: _ink,
                  ),
                ),
              ),
              SizedBox(
                width: 60,
                child: Text('col_entries'.tr.toUpperCase(),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 7.5,
                        fontWeight: FontWeight.w800,
                        color: _muted)),
              ),
              SizedBox(
                width: _amountWidth,
                child: Text('col_amount'.tr.toUpperCase(),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                        fontSize: 7.5,
                        fontWeight: FontWeight.w800,
                        color: _muted)),
              ),
            ],
          ),
        ),
        for (final ReportBucket bucket in shown)
          Container(
            height: ReportLayout.summaryRowHeight,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _hairline, width: 0.8)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    labelOf(bucket),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 8.5, color: _ink),
                  ),
                ),
                SizedBox(
                  width: 60,
                  child: Text('${bucket.count}',
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontSize: 8.5, color: _muted)),
                ),
                SizedBox(
                  width: _amountWidth,
                  child: Text(
                    amount(bucket.amount),
                    textAlign: TextAlign.right,
                    style: const TextStyle(
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      color: _ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        if (cut)
          Container(
            height: ReportLayout.summaryRowHeight,
            alignment: Alignment.centerLeft,
            child: Text(
              'and_more_rows'
                  .trParams({'count': '${buckets.length - shown.length}'}),
              style: const TextStyle(
                  fontSize: 8.5, fontStyle: FontStyle.italic, color: _muted),
            ),
          ),
      ],
    );
  }

  Widget _ownerFooter(BuildContext context, Color accent) {
    return SizedBox(
      height: ReportLayout.ownerFooterHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Text('prepared_for'.tr.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 7.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.6,
                        color: _muted)),
                const SizedBox(height: 2),
                Text(
                  ownerName.isEmpty ? ownerPhone : ownerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700, color: _ink),
                ),
                if (ownerName.isNotEmpty && ownerPhone.isNotEmpty)
                  Text(ownerPhone,
                      style: const TextStyle(fontSize: 8.5, color: _muted)),
              ],
            ),
          ),
          Text(
            '${'report_word'.tr} · ${'app_name'.tr}',
            style: TextStyle(
                fontSize: 8.5,
                fontWeight: FontWeight.w700,
                color: accent.withOpacity(0.8)),
          ),
        ],
      ),
    );
  }

  /// ----------------------------------------------------------------- footer

  Widget _footer(BuildContext context) {
    return SizedBox(
      height: ReportLayout.footerHeight,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Text(
              _isLast ? '' : 'continued_next_page'.tr,
              style: const TextStyle(
                  fontSize: 8, fontStyle: FontStyle.italic, color: _muted),
            ),
          ),
          Text(
            'page_of'.trParams({'n': '${spec.number}', 'm': '$pageCount'}),
            style: const TextStyle(fontSize: 8, color: _muted),
          ),
        ],
      ),
    );
  }
}
