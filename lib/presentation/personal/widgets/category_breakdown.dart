import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import '../model/personal_category.dart';
import '../model/personal_summary.dart';

/// Where a month's money went, biggest first.
///
/// A list rather than a pie: five rows with their share written out answer
/// "what am I spending on" faster than a circle anyone has to decode, and it
/// reads the same at any width.
class CategoryBreakdown extends StatefulWidget {
  final List<CategoryTotal> totals;
  final double total;
  final String title;

  /// Colours the total in the heading. Null leaves it in the body colour —
  /// the month passes the side's own hue, so the two cards are told apart
  /// before either is read.
  final MaterialColor? tone;

  /// How many rows the card opens with. The rest are a tap away rather than
  /// gone: the head of the list is the answer to "what am I spending on",
  /// and the tail is still somebody's money.
  final int max;

  /// Opens the rows behind a bar. Without it the list is inert, which is what
  /// the dues screen wants and the month does not.
  final ValueChanged<CategoryTotal>? onTap;

  const CategoryBreakdown({
    super.key,
    required this.totals,
    required this.total,
    required this.title,
    this.tone,
    this.max = 5,
    this.onTap,
  });

  @override
  State<CategoryBreakdown> createState() => _CategoryBreakdownState();
}

class _CategoryBreakdownState extends State<CategoryBreakdown> {
  /// Whether the tail below [CategoryBreakdown.max] is showing.
  ///
  /// Folded to begin with, and it stays however it was left for the rest of
  /// the visit — walking to another month is not a reason to fold a list
  /// somebody opened. A pull-to-refresh is: the screen keys these cards on
  /// its reset token, which throws this away with everything else that visit
  /// had set.
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final List<CategoryTotal> totals = widget.totals;
    final double total = widget.total;
    final String title = widget.title;
    final MaterialColor? tone = widget.tone;

    if (totals.isEmpty) return const SizedBox.shrink();

    final bool overflows = totals.length > widget.max;
    final List<CategoryTotal> shown = overflows && !_expanded
        ? totals.take(widget.max).toList()
        : totals;
    final int hidden = totals.length - shown.length;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title on the left, what it all came to on the right. Every row
          // below is a share of this figure, and a percentage with nothing to
          // be a percentage *of* is half a sentence — the month's own total
          // was one card further up, which is a scroll away from the question
          // it answers. It is the whole total, not the visible rows added up:
          // when the tail is cut the shares still refer to this.
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                AppUi.amount(total),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                  color: tone == null
                      ? AppUi.body(context)
                      : AppUi.accent(context, tone),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          for (final CategoryTotal entry in shown) ...[
            if (widget.onTap == null)
              _buildRow(context, entry)
            else
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => widget.onTap!(entry),
                  borderRadius: BorderRadius.circular(12),
                  // The row is inset rather than padded so the ripple reaches
                  // past the text without the bar moving in from the edge.
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _buildRow(context, entry),
                  ),
                ),
              ),
            const SizedBox(height: 12),
          ],
          // The tail, and the way to it. It was a grey line of text before,
          // which said the rows existed without saying they could be had —
          // the colour and the chevron are what make it an offer, and the
          // same control folds them back.
          if (overflows)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => setState(() => _expanded = !_expanded),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(4, 6, 8, 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _expanded
                            ? 'show_fewer'.tr
                            : 'and_more_categories'
                                .trParams({'count': '$hidden'}),
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _expanded
                            ? Icons.expand_less_rounded
                            : Icons.expand_more_rounded,
                        size: 17,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, CategoryTotal entry) {
    final PersonalCategory category = PersonalCategory.of(entry.category);
    final double share = entry.share(widget.total);
    final Color accent = AppUi.accent(context, category.color);

    return Row(
      children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppUi.tint(context, category.color),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(category.icon, size: 17, color: accent),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      category.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppUi.body(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppUi.amount(entry.amount),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: AppUi.body(context),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 38,
                    child: Text(
                      '${(share * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
                    ),
                  ),
                  if (widget.onTap != null)
                    Icon(Icons.chevron_right_rounded,
                        size: 16, color: AppUi.muted(context)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: share.clamp(0.0, 1.0),
                  minHeight: 5,
                  backgroundColor: AppUi.tint(context, category.color),
                  valueColor: AlwaysStoppedAnimation<Color>(accent),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
