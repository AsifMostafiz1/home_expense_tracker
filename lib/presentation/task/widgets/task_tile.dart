import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import '../model/task_model.dart';
import 'task_check.dart';
import 'task_labels.dart';

/// One task, as a row.
///
/// The same row everywhere a task is listed: the list itself, the day's sheet
/// on the home screen, the finished view. [compact] is the sheet's version —
/// no note, no menu, tighter — so a morning's list fits in a sheet without
/// each row asking for the space a card gets.
///
/// The tick is the row's own control; a tap anywhere else is [onTap], which
/// the list uses to open the editor and the sheet leaves unset.
class TaskTile extends StatelessWidget {
  final TaskModel task;
  final VoidCallback onToggle;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Whether the row is being pointed at — the one a reminder was tapped for.
  /// Drawn with the app's tint and a stronger edge while true.
  final bool highlighted;

  final bool compact;

  /// The clock the row reads "late" and "today" against. The list passes the
  /// digest's, so every row on it agrees with the sections above it.
  final DateTime? now;

  const TaskTile({
    super.key,
    required this.task,
    required this.onToggle,
    this.onTap,
    this.onLongPress,
    this.highlighted = false,
    this.compact = false,
    this.now,
  });

  @override
  Widget build(BuildContext context) {
    final DateTime clock = now ?? DateTime.now();
    final Color primary = Theme.of(context).colorScheme.primary;
    final MaterialColor tone = TaskLabels.priorityColor(context, task.priority);
    final Color accent = task.done
        ? AppUi.muted(context)
        : AppUi.accent(context, tone);

    // A timed task whose hour has gone today is late by minutes rather than
    // by days: it keeps its place on the day's list and its time turns red,
    // instead of being moved somewhere that means "earlier days".
    final bool late = task.isOverdue(clock);
    final bool soon = !task.done &&
        task.hasTime &&
        !late &&
        task.dueAt != null &&
        task.dueAt!.difference(clock) <= const Duration(hours: 1);

    final Color titleColor =
        task.done ? AppUi.muted(context) : AppUi.body(context);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
      decoration: BoxDecoration(
        color: highlighted
            ? AppUi.tint(context, primary)
            : (compact ? Colors.transparent : Theme.of(context).cardColor),
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        border: compact
            ? null
            : Border.all(
                color: highlighted
                    ? primary.withOpacity(0.45)
                    : AppUi.hairline(context),
              ),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(4, 4, 12, 4)
                : const EdgeInsets.fromLTRB(6, 8, 14, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                TaskCheck(
                  done: task.done,
                  accent: accent,
                  onTap: onToggle,
                  size: compact ? 24 : 26,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 250),
                        style: TextStyle(
                          fontSize: compact ? 14 : 14.5,
                          height: 1.3,
                          fontWeight: FontWeight.w600,
                          color: titleColor,
                          decoration: task.done
                              ? TextDecoration.lineThrough
                              : TextDecoration.none,
                          decorationColor: titleColor,
                        ),
                        child: Text(
                          task.title,
                          maxLines: compact ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (!compact && task.hasNote) ...[
                        const SizedBox(height: 3),
                        Text(
                          task.note,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.35,
                            color: AppUi.muted(context),
                          ),
                        ),
                      ],
                      if (_hasMeta) ...[
                        SizedBox(height: compact ? 3 : 6),
                        _meta(context, clock, late: late, soon: soon),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  bool get _hasMeta =>
      task.hasDate ||
      task.hasReminder ||
      task.hasFollowUp ||
      task.repeat.repeats ||
      task.pending ||
      task.priority == TaskPriority.high;

  /// The small print under the title: when, whether a bell is set, whether it
  /// comes round again, whether it has reached the server yet.
  Widget _meta(
    BuildContext context,
    DateTime clock, {
    required bool late,
    required bool soon,
  }) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final Color muted = AppUi.muted(context);
    final Color timeColor = task.done
        ? muted
        : late
            ? AppUi.accent(context, Colors.red)
            : soon
                ? primary
                : muted;

    final List<Widget> chips = [];

    if (task.hasDate) {
      chips.add(_iconText(
        context,
        icon: task.hasTime ? Icons.schedule_rounded : Icons.today_rounded,
        text: TaskLabels.due(task, now: clock),
        color: timeColor,
        bold: late || soon,
      ));
    }

    if (task.hasReminder && !task.done) {
      final DateTime? at = task.reminderAt;
      final bool passed = at != null && !at.isAfter(clock);
      chips.add(Icon(
        passed
            ? Icons.notifications_off_outlined
            : Icons.notifications_active_outlined,
        size: 13,
        color: passed ? muted.withOpacity(0.6) : muted,
      ));
    }

    if (task.hasFollowUp && !task.done) {
      // Asks again after the hour if still open — see TaskModel.followUpMinutes.
      chips.add(Icon(Icons.update_rounded, size: 13, color: muted));
    }

    if (task.repeat.repeats) {
      chips.add(_iconText(
        context,
        icon: Icons.repeat_rounded,
        text: compact ? '' : TaskLabels.repeat(task.repeat),
        color: muted,
      ));
    }

    if (task.priority == TaskPriority.high && !task.done) {
      chips.add(_microChip(
        context,
        Colors.red,
        Icons.keyboard_double_arrow_up_rounded,
        'priority_high'.tr,
      ));
    }

    if (task.pending) {
      chips.add(_microChip(
        context,
        Colors.orange,
        Icons.cloud_upload_outlined,
        'not_synced'.tr,
      ));
    }

    return Wrap(
      spacing: 10,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: chips,
    );
  }

  Widget _iconText(
    BuildContext context, {
    required IconData icon,
    required String text,
    required Color color,
    bool bold = false,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color),
        if (text.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ],
    );
  }

  /// The house's small-caps chip — the shape the "not synced" mark has
  /// everywhere else in the app.
  Widget _microChip(
    BuildContext context,
    MaterialColor tone,
    IconData icon,
    String text,
  ) {
    final Color fg = AppUi.accent(context, tone);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppUi.tint(context, tone),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: fg),
          const SizedBox(width: 3),
          Text(
            text.toUpperCase(),
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.3,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}
