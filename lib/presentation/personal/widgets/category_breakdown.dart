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
class CategoryBreakdown extends StatelessWidget {
  final List<CategoryTotal> totals;
  final double total;
  final String title;

  /// Longer lists are cut here — the tail of a spending month is noise.
  final int max;

  /// Opens the rows behind a bar. Without it the list is inert, which is what
  /// the dues screen wants and the month does not.
  final ValueChanged<CategoryTotal>? onTap;

  const CategoryBreakdown({
    super.key,
    required this.totals,
    required this.total,
    required this.title,
    this.max = 5,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (totals.isEmpty) return const SizedBox.shrink();

    final List<CategoryTotal> shown = totals.take(max).toList();
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
          Text(
            title,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.bold,
              color: AppUi.body(context),
            ),
          ),
          const SizedBox(height: 14),
          for (final CategoryTotal entry in shown) ...[
            if (onTap == null)
              _buildRow(context, entry)
            else
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onTap!(entry),
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
          if (hidden > 0)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                'and_more_categories'.trParams({'count': '$hidden'}),
                style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRow(BuildContext context, CategoryTotal entry) {
    final PersonalCategory category = PersonalCategory.of(entry.category);
    final double share = entry.share(total);
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
                  if (onTap != null)
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
