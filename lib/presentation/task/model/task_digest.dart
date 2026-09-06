import 'task_model.dart';

/// A member's tasks, sorted into the piles the screens show.
///
/// Worked out from the whole list in memory and from one clock reading, so
/// the same instant decides every pile — a task cannot be both "today" and
/// "overdue" because two getters looked at the clock a second apart. Pure,
/// and built without Flutter or Firestore, so it can be tested on its own.
class TaskDigest {
  /// Open tasks whose moment has passed — an hour that has gone, or a day
  /// that has ended. Oldest first, so the longest-owed is at the top.
  final List<TaskModel> overdue;

  /// Everything dated today, finished or not, in the order of the day.
  final List<TaskModel> today;

  /// Open tasks dated tomorrow.
  final List<TaskModel> tomorrow;

  /// Open tasks dated after tomorrow, soonest first.
  final List<TaskModel> later;

  /// Open tasks with no day at all.
  final List<TaskModel> someday;

  /// Finished tasks, most recently finished first. Today's finished tasks
  /// are in here *and* in [today] — the summary reads them there, the
  /// completed list reads them here.
  final List<TaskModel> completed;

  /// Finished on the day the digest was taken, whichever day they were due:
  /// an overdue task caught up on today counts towards today.
  final List<TaskModel> doneToday;

  final DateTime now;

  const TaskDigest._({
    required this.overdue,
    required this.today,
    required this.tomorrow,
    required this.later,
    required this.someday,
    required this.completed,
    required this.doneToday,
    required this.now,
  });

  factory TaskDigest.of(List<TaskModel> tasks, {DateTime? now}) {
    final DateTime clock = now ?? DateTime.now();
    final DateTime todayDay = TaskModel.dayOf(clock);
    final DateTime tomorrowDay =
        DateTime(todayDay.year, todayDay.month, todayDay.day + 1);

    final List<TaskModel> overdue = [];
    final List<TaskModel> today = [];
    final List<TaskModel> tomorrow = [];
    final List<TaskModel> later = [];
    final List<TaskModel> someday = [];
    final List<TaskModel> completed = [];
    final List<TaskModel> doneToday = [];

    for (final TaskModel task in tasks) {
      if (task.done) {
        completed.add(task);
        if (task.wasDoneOn(todayDay)) doneToday.add(task);
        if (task.isOn(todayDay)) today.add(task);
        continue;
      }

      if (task.isOn(todayDay)) {
        today.add(task);
        // A timed task earlier today is late as well as today's: it shows in
        // both, the way a missed appointment is still on the day's list.
        if (task.isOverdue(clock)) overdue.add(task);
        continue;
      }

      if (task.isOverdue(clock)) {
        overdue.add(task);
        continue;
      }

      if (!task.hasDate) {
        someday.add(task);
      } else if (task.isOn(tomorrowDay)) {
        tomorrow.add(task);
      } else {
        later.add(task);
      }
    }

    overdue.sort(TaskModel.compare);
    today.sort(TaskModel.compare);
    tomorrow.sort(TaskModel.compare);
    later.sort(TaskModel.compare);
    someday.sort(TaskModel.compare);
    completed.sort(_byFinished);
    doneToday.sort(_byFinished);

    return TaskDigest._(
      overdue: overdue,
      today: today,
      tomorrow: tomorrow,
      later: later,
      someday: someday,
      completed: completed,
      doneToday: doneToday,
      now: clock,
    );
  }

  static int _byFinished(TaskModel a, TaskModel b) {
    final DateTime? da = a.doneAt;
    final DateTime? db = b.doneAt;
    if (da != null && db != null) {
      final int byDone = db.compareTo(da);
      if (byDone != 0) return byDone;
    } else if (da != null || db != null) {
      // A finished task whose stamp has not landed yet reads as the newest.
      return da == null ? -1 : 1;
    }
    return TaskModel.compare(a, b);
  }

  /// ------------------------------------------------------------ the summary

  /// How many tasks today holds, finished or not.
  int get todayTotal => today.length;

  /// How many of today's tasks are finished.
  int get todayDone => today.where((task) => task.done).length;

  int get todayOpen => todayTotal - todayDone;

  /// Open tasks that were due before today — the ones today's list does not
  /// already show. A timed task late by minutes stays on today's list with
  /// its time in red; this is for what is late by days.
  List<TaskModel> get overdueEarlier {
    final DateTime today = TaskModel.dayOf(now);
    return overdue.where((task) => !task.isOn(today)).toList(growable: false);
  }

  int get overdueBeforeToday => overdueEarlier.length;

  /// Today's list, split: what is still to do, and what is finished.
  List<TaskModel> get todayOpenList =>
      today.where((task) => !task.done).toList(growable: false);

  List<TaskModel> get todayDoneList =>
      today.where((task) => task.done).toList(growable: false);

  /// Today's share finished, 0..1. Zero with nothing on the list, so a ring
  /// drawn from it stays empty rather than dividing by nothing.
  double get todayProgress => todayTotal == 0 ? 0 : todayDone / todayTotal;

  bool get allDoneToday => todayTotal > 0 && todayDone == todayTotal;

  /// Whether there is anything worth putting in front of somebody this
  /// morning: something still open on today's list, or something left over
  /// from before. A day whose tasks were all finished ahead of time is not
  /// worth an interruption.
  bool get hasSomethingForToday => todayOpen > 0 || overdueBeforeToday > 0;

  /// Every open task, in the order the main list shows: overdue first, then
  /// the day, then what is ahead, then the undated ones.
  int get openCount =>
      overdueBeforeToday + todayOpen + tomorrow.length + later.length + someday.length;

  /// Open tasks with a reminder or a follow-up still ahead of the clock —
  /// what the OS is holding alarms for.
  List<TaskModel> get armed => [
        for (final TaskModel task in [
          ...overdue,
          ...today,
          ...tomorrow,
          ...later,
        ])
          if (!task.done &&
              ((task.reminderAt?.isAfter(now) ?? false) ||
                  (task.followUpAt?.isAfter(now) ?? false)))
            task,
      ];

  /// [later], grouped by day in date order, for the section headers.
  List<MapEntry<DateTime, List<TaskModel>>> get laterByDay {
    final Map<String, List<TaskModel>> byKey = {};
    for (final TaskModel task in later) {
      byKey.putIfAbsent(task.date, () => []).add(task);
    }
    final List<String> keys = byKey.keys.toList()..sort();
    return [
      for (final String key in keys)
        MapEntry(DateTime.parse(key), byKey[key]!),
    ];
  }
}
