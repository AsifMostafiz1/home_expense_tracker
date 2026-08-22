import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';

import '../../../common/widgets/connection_banner.dart';
import '../../../utils/app_ui.dart';
import '../controller/monthly_stats_controller.dart';
import '../model/month_cost_summary.dart';
import '../view/monthly_stats_screen.dart';

/// The strip across the top of the home screen that says what this month comes
/// to for whoever is signed in, and leads to the statement behind the figure.
///
/// It sits where the offline strip sits and behaves the same way: it takes
/// over the status bar area while it is up, and hands that padding back to the
/// page underneath as it leaves — the two are driven off one animation, so the
/// tab's own app bar slides rather than jumps. Wrapping the tab body from the
/// dashboard puts it above all four app bars without any of them knowing about
/// it, and keeps it off the statistics screen its own button leads to.
///
/// It is the same space the offline strip uses, so the two are never up
/// together: this one stands down while that one is showing and comes back
/// once it has gone — see [ConnectionBanner.isShowing].
///
/// A reminder, nothing more. It goes as soon as the admin marks the month
/// collected, never appears for a month with nothing left to pay, and never
/// appears for an admin at all — see [MonthlyStatsController.dueThisMonth].
class DueBanner extends StatefulWidget {
  final Widget child;

  const DueBanner({super.key, required this.child});

  @override
  State<DueBanner> createState() => _DueBannerState();
}

class _DueBannerState extends State<DueBanner> {
  /// What the strip says. Kept while it animates out, so the figure does not
  /// vanish before the strip has gone.
  _DueContent? _content;

  @override
  Widget build(BuildContext context) {
    final MediaQueryData media = MediaQuery.of(context);
    final double statusBar = media.padding.top;

    return ValueListenableBuilder<bool>(
      valueListenable: ConnectionBanner.isShowing,
      builder: (context, connectionShowing, _) {
        return GetBuilder<MonthlyStatsController>(
          // The controller updates on every keystroke in the bill form; the
          // strip only cares about the figure it is showing.
          filter: _filterKey,
          builder: (c) => _banner(c, media, statusBar, connectionShowing),
        );
      },
    );
  }

  Widget _banner(
    MonthlyStatsController c,
    MediaQueryData media,
    double statusBar,
    bool connectionShowing,
  ) {
    final _DueContent? due = _read(c);
    if (due != null) _content = due;

    // The figure is remembered either way, so standing down for the offline
    // strip costs nothing: this slides back in with the same amount on it the
    // moment that one leaves.
    final bool show = due != null && !connectionShowing;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: show ? 1 : 0),
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      child: widget.child,
      builder: (context, t, child) {
        return Column(
          children: [
            if (t > 0 && _content != null)
              ClipRect(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  heightFactor: t,
                  child: _DueStrip(content: _content!, topInset: statusBar),
                ),
              ),
            Expanded(
              // The strip owns the status bar area while it is up; the tab
              // gets its top padding back in step with the strip leaving.
              child: MediaQuery(
                data: media.copyWith(
                  padding: media.padding.copyWith(top: statusBar * (1 - t)),
                  viewPadding:
                      media.viewPadding.copyWith(top: statusBar * (1 - t)),
                ),
                child: child!,
              ),
            ),
          ],
        );
      },
    );
  }

  /// This month's outstanding amount, with the two figures the hint needs, or
  /// null when there is nothing to remind anybody about.
  _DueContent? _read(MonthlyStatsController c) {
    final double? due = c.dueThisMonth;
    final MonthCostSummary? summary = c.myMonthSummary;
    final MemberCostSummary? mine = c.myCost;
    if (due == null || summary == null || mine == null) return null;

    return _DueContent(
      amount: due,
      month: summary.month,
      mealMonth: summary.mealMonth,
      mealCount: mine.mealCount,
    );
  }

  static String _filterKey(MonthlyStatsController c) {
    final double? due = c.dueThisMonth;
    if (due == null) return '';
    return '${due.toStringAsFixed(2)}|${c.myCost?.mealCount}';
  }
}

/// The figures on the strip for one month.
class _DueContent {
  final double amount;
  final DateTime month;
  final DateTime mealMonth;
  final int mealCount;

  const _DueContent({
    required this.amount,
    required this.month,
    required this.mealMonth,
    required this.mealCount,
  });
}

class _DueStrip extends StatelessWidget {
  final _DueContent content;
  final double topInset;

  const _DueStrip({required this.content, required this.topInset});

  @override
  Widget build(BuildContext context) {
    final bool dark = AppUi.isDark(context);

    // The offline strip's warm amber, cut the same way for light and dark, so
    // the two notices are one thing the user learns to read rather than two.
    final Color background =
        dark ? const Color(0xFF3B2A12) : const Color(0xFFFFF1DE);
    final Color title =
        dark ? const Color(0xFFFFD79A) : const Color(0xFF7A3E00);
    final Color body = dark ? const Color(0xFFE6BF83) : const Color(0xFF8C5A1E);
    final Color bubble =
        dark ? const Color(0x33FFC46B) : const Color(0xFFFFD9A8);

    // The strip covers the status bar, so it — not the tab below — decides how
    // the clock and battery icons are drawn over it.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      ),
      child: Material(
        color: background,
        child: InkWell(
          // The whole strip is the way through, not just the chevron — the
          // figure is what people reach for.
          onTap: _openStatement,
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(16, topInset + 10, 12, 12),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: title.withOpacity(dark ? 0.18 : 0.14),
                  width: 1,
                ),
              ),
            ),
            child: SafeArea(
              top: false,
              bottom: false,
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    alignment: Alignment.center,
                    decoration:
                        BoxDecoration(color: bubble, shape: BoxShape.circle),
                    child: Icon(Icons.receipt_long_rounded,
                        size: 18, color: title),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'due_banner_title'.trParams({
                            'amount': AppUi.amount(content.amount),
                            'month': AppUi.monthLabel(content.month),
                          }),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.1,
                            color: title,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'your_share_hint'.trParams({
                            'meals': '${content.mealCount}',
                            'month': AppUi.monthLabel(content.mealMonth),
                          }),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            fontWeight: FontWeight.w500,
                            color: body,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Tooltip(
                    message: 'more_info'.tr,
                    child: Container(
                      width: 34,
                      height: 34,
                      alignment: Alignment.center,
                      decoration:
                          BoxDecoration(color: bubble, shape: BoxShape.circle),
                      child: Icon(Icons.arrow_forward_rounded,
                          size: 18, color: title),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Through to the statement the figure came from. The saved months there
  /// carry a figure each, which the strip alone never needed — see
  /// [MonthlyStatsController.ensureHistory].
  void _openStatement() {
    if (!Get.isRegistered<MonthlyStatsController>()) return;
    Get.find<MonthlyStatsController>().ensureHistory();
    Get.to(() => const MonthlyStatsScreen());
  }
}
