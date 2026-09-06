import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../utils/app_ui.dart';
import '../model/task_model.dart';

/// The words and colours every task widget shares, so a chip on the editor
/// and the same chip on a row read identically.
class TaskLabels {
  const TaskLabels._();

  /// `Today` / `Tomorrow` / `Yesterday` / `Sat, 12 Sep` — the day a task is
  /// due, worded from wherever the clock stands.
  static String day(DateTime day, {DateTime? now}) {
    final DateTime today = TaskModel.dayOf(now ?? DateTime.now());
    final int diff = TaskModel.dayOf(day).difference(today).inDays;
    if (diff == 0) return 'today'.tr;
    if (diff == 1) return 'tomorrow'.tr;
    if (diff == -1) return 'yesterday'.tr;
    final String weekday = _weekdayKeys[day.weekday - 1].tr;
    final String month = _shortMonthKeys[day.month - 1].tr;
    final String base = '$weekday, ${day.day} $month';
    return day.year == today.year ? base : '$base ${day.year}';
  }

  /// A relative day word as it reads inside a sentence: `today` rather than
  /// `Today`. Only Latin text has a case to lower; Bangla comes back as is.
  static String inSentence(String label) {
    if (label.isEmpty) return label;
    final int first = label.codeUnitAt(0);
    if (first >= 0x41 && first <= 0x5A) {
      return label[0].toLowerCase() + label.substring(1);
    }
    return label;
  }

  /// `Saturday`, in the app's language.
  static String fullWeekday(DateTime day) =>
      _fullWeekdayKeys[day.weekday - 1].tr;

  /// `5:00 PM`.
  static String time(TaskModel task) => task.hasTime
      ? DateFormat('h:mm a').format(DateTime(2000, 1, 1, task.timeHour, task.timeMinute))
      : '';

  /// The one line under a title: `Today, 5:00 PM`, `Tomorrow`, `Sat, 12 Sep`
  /// — or nothing for a task with no day.
  static String due(TaskModel task, {DateTime? now}) {
    final DateTime? d = task.day;
    if (d == null) return '';
    final String label = day(d, now: now);
    return task.hasTime ? '$label, ${time(task)}' : label;
  }

  /// How the reminder offset reads on a chip: `At the time`, `15 min before`,
  /// `1 hr before`, `1 day before` — or, for a task with no hour, `Morning
  /// of` and `Morning before`.
  static String reminder(int minutes, {required bool hasTime}) {
    if (!hasTime) {
      return minutes > 0 ? 'remind_evening_before'.tr : 'remind_morning_of'.tr;
    }
    if (minutes <= 0) return 'remind_at_time'.tr;
    if (minutes < 60) return 'remind_minutes_before'.trParams({'count': '$minutes'});
    if (minutes < 1440) {
      return 'remind_hours_before'.trParams({'count': '${minutes ~/ 60}'});
    }
    return 'remind_day_before'.tr;
  }

  /// How the follow-up delay reads on a chip: `30 min after`, `1 hr after`.
  static String followUp(int minutes) {
    if (minutes < 60) {
      return 'follow_up_after_minutes'.trParams({'count': '$minutes'});
    }
    return 'follow_up_after_hours'.trParams({'count': '${minutes ~/ 60}'});
  }

  static String priority(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.low:
        return 'priority_low'.tr;
      case TaskPriority.normal:
        return 'priority_normal'.tr;
      case TaskPriority.high:
        return 'priority_high'.tr;
    }
  }

  static String repeat(TaskRepeat repeat) {
    switch (repeat) {
      case TaskRepeat.none:
        return 'repeat_none'.tr;
      case TaskRepeat.daily:
        return 'repeat_daily'.tr;
      case TaskRepeat.weekly:
        return 'repeat_weekly'.tr;
      case TaskRepeat.monthly:
        return 'repeat_monthly'.tr;
    }
  }

  /// The accent a priority is drawn in. Normal borrows the app's own colour
  /// so an ordinary task looks like the rest of the app, and only the two
  /// ends of the scale stand out.
  static MaterialColor priorityColor(BuildContext context, TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return Colors.red;
      case TaskPriority.low:
        return Colors.blueGrey;
      case TaskPriority.normal:
        return Colors.deepPurple;
    }
  }

  static Color priorityAccent(BuildContext context, TaskPriority priority) =>
      AppUi.accent(context, priorityColor(context, priority));

  static const List<String> _weekdayKeys = [
    'weekday_mon',
    'weekday_tue',
    'weekday_wed',
    'weekday_thu',
    'weekday_fri',
    'weekday_sat',
    'weekday_sun',
  ];

  static const List<String> _fullWeekdayKeys = [
    'weekday_full_mon',
    'weekday_full_tue',
    'weekday_full_wed',
    'weekday_full_thu',
    'weekday_full_fri',
    'weekday_full_sat',
    'weekday_full_sun',
  ];

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
}
