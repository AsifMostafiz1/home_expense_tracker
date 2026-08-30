import 'personal_report.dart';
import 'personal_transaction.dart';

/// The measurements a report page is drawn to, in points of an A4 sheet.
///
/// Kept beside the pagination rather than in the widget so the two cannot
/// drift: the planner counts rows with these numbers, and the page paints
/// rows at exactly these heights. Change one here and both follow.
class ReportLayout {
  ReportLayout._();

  static const double pageWidth = 595;
  static const double pageHeight = 842;
  static const double margin = 28;

  static const double contentWidth = pageWidth - 2 * margin;
  static const double contentHeight = pageHeight - 2 * margin;

  static const double headerHeight = 78;
  static const double filterStripHeight = 24;
  static const double tableHeaderHeight = 22;
  static const double rowHeight = 22;
  static const double footerHeight = 30;
  static const double gap = 8;

  /// What is left for rows once the fixed furniture is on the page.
  static const double rowsArea = contentHeight -
      headerHeight -
      gap -
      filterStripHeight -
      gap -
      tableHeaderHeight -
      footerHeight -
      gap;

  static int get rowsPerPage => rowsArea ~/ rowHeight;

  static const double totalsHeight = 64;
  static const double blockGap = 12;
  static const double summaryTitleHeight = 26;
  static const double summaryRowHeight = 20;
  static const double ownerFooterHeight = 44;

  /// Summary tables longer than this are cut even when there is room — the
  /// tail of a long list is noise on paper.
  static const int maxSummaryRows = 20;

  /// The most a summary may take on a page of its own: the rows area, plus
  /// the table header that page does not draw.
  static const double summaryPageArea = rowsArea + tableHeaderHeight;

  static double summaryTableHeight(int rows) =>
      rows == 0 ? 0 : blockGap + summaryTitleHeight + rows * summaryRowHeight;
}

/// One page of the report: which rows it carries, and whether the closing
/// summary sits at its foot.
class ReportPageSpec {
  final int number;
  final List<PersonalTransaction> rows;
  final bool summary;

  const ReportPageSpec({
    required this.number,
    required this.rows,
    required this.summary,
  });
}

/// Cuts a report into pages, deterministically, from the layout numbers.
///
/// Rows fill each page to its count; the summary goes at the foot of the
/// last page when there is room for it there, and on a page of its own
/// when there is not — never squeezed, never split.
class ReportPages {
  ReportPages._();

  /// How many rows each summary table gets — see [SummaryRows].
  static SummaryRows summaryRows(PersonalReport report) => SummaryRows.of(
        categories: report.byCategory.length,
        tags: report.bySubcategory.length,
        months: report.byMonth.length,
      );

  static double summaryHeight(PersonalReport report) =>
      summaryRows(report).height;

  static List<ReportPageSpec> plan(PersonalReport report) {
    final int perPage = ReportLayout.rowsPerPage;
    final List<List<PersonalTransaction>> chunks = [];
    for (int i = 0; i < report.entries.length; i += perPage) {
      chunks.add(report.entries
          .sublist(i, (i + perPage).clamp(0, report.entries.length)));
    }
    // An empty report is still a page: the table shows one row saying so.
    if (chunks.isEmpty) chunks.add(const []);

    final int lastRows = chunks.last.isEmpty ? 1 : chunks.last.length;
    final double free =
        ReportLayout.rowsArea - lastRows * ReportLayout.rowHeight;
    final bool fits = summaryHeight(report) <= free;

    final List<ReportPageSpec> pages = [
      for (int i = 0; i < chunks.length; i++)
        ReportPageSpec(
          number: i + 1,
          rows: chunks[i],
          summary: fits && i == chunks.length - 1,
        ),
    ];
    if (!fits) {
      pages.add(ReportPageSpec(
          number: pages.length + 1, rows: const [], summary: true));
    }
    return pages;
  }
}

/// The rows each summary table is given, cut to fit a page.
///
/// A table with one row says nothing the totals do not, so it is left
/// out. Beyond that, each is capped, and when the three together would
/// still outgrow a page of their own the longest gives up rows first —
/// the same way a printed appendix is trimmed, never split.
class SummaryRows {
  final int categories;
  final int tags;
  final int months;

  const SummaryRows({this.categories = 0, this.tags = 0, this.months = 0});

  /// Rows below this a table will not be cut to: two rows with a "more"
  /// line under them is the least that is still a table.
  static const int minRows = 2;

  double get height =>
      ReportLayout.blockGap +
      ReportLayout.totalsHeight +
      ReportLayout.summaryTableHeight(categories) +
      ReportLayout.summaryTableHeight(tags) +
      ReportLayout.summaryTableHeight(months) +
      ReportLayout.blockGap +
      ReportLayout.ownerFooterHeight;

  static int _cap(int length) => length > 1
      ? (length > ReportLayout.maxSummaryRows
          ? ReportLayout.maxSummaryRows
          : length)
      : 0;

  static SummaryRows of({
    required int categories,
    required int tags,
    required int months,
  }) {
    int c = _cap(categories);
    int t = _cap(tags);
    int m = _cap(months);

    SummaryRows rows() => SummaryRows(categories: c, tags: t, months: m);

    while (rows().height > ReportLayout.summaryPageArea) {
      // The longest table gives up a row; stop if none can spare one.
      if (c >= t && c >= m && c > minRows) {
        c--;
      } else if (t >= m && t > minRows) {
        t--;
      } else if (m > minRows) {
        m--;
      } else {
        break;
      }
    }
    return rows();
  }
}
