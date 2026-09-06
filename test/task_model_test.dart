import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/presentation/task/controller/task_controller.dart';
import 'package:demo_project/presentation/task/model/task_digest.dart';
import 'package:demo_project/presentation/task/model/task_model.dart';
import 'package:demo_project/services/task_reminder_service.dart';

/// The arithmetic behind the task list: when a task is due, when its
/// reminder goes off, which pile it lands in, and what a finished repeating
/// task turns into. Everything else in the feature talks to Firestore or the
/// OS; these are the parts that can be wrong on their own.
void main() {
  planTests();

  // A Saturday afternoon. Every "now" below is read against it.
  final DateTime now = DateTime(2026, 9, 5, 14, 30);

  TaskModel task({
    String id = 't1',
    String title = 'Pay the electricity bill',
    String date = '',
    TimeOfDay? time,
    int? reminder,
    TaskRepeat repeat = TaskRepeat.none,
    TaskPriority priority = TaskPriority.normal,
    bool done = false,
    DateTime? doneAt,
    DateTime? createdAt,
  }) {
    return TaskModel(
      id: id,
      ownerPhone: '01700000000',
      title: title,
      date: date,
      hasTime: time != null,
      timeHour: time?.hour ?? 0,
      timeMinute: time?.minute ?? 0,
      reminderMinutes: reminder,
      repeat: repeat,
      priority: priority,
      done: done,
      doneAt: doneAt,
      createdAt: createdAt,
    );
  }

  group('when a task is due', () {
    test('a task with an hour is due at that hour', () {
      final TaskModel t = task(
          date: '2026-09-05', time: const TimeOfDay(hour: 17, minute: 0));
      expect(t.dueAt, DateTime(2026, 9, 5, 17, 0));
      expect(t.reminderAnchor, DateTime(2026, 9, 5, 17, 0));
    });

    test('a task with only a day is due at the end of it', () {
      final TaskModel t = task(date: '2026-09-05');
      expect(t.dueAt, DateTime(2026, 9, 5, 23, 59, 59));
      // ...but is reminded about in the morning.
      expect(t.reminderAnchor, DateTime(2026, 9, 5, 9, 0));
    });

    test('a task with no day is due never', () {
      final TaskModel t = task();
      expect(t.dueAt, isNull);
      expect(t.reminderAt, isNull);
      expect(t.isOverdue(now), isFalse);
      expect(t.isUpcoming(now), isFalse);
    });

    test('is late once the hour has passed, and not before', () {
      expect(
        task(date: '2026-09-05', time: const TimeOfDay(hour: 14, minute: 0))
            .isOverdue(now),
        isTrue,
      );
      expect(
        task(date: '2026-09-05', time: const TimeOfDay(hour: 15, minute: 0))
            .isOverdue(now),
        isFalse,
      );
    });

    /// The whole day is still ahead of a task that names no hour on it.
    test('a day-only task is not late until the day is over', () {
      expect(task(date: '2026-09-05').isOverdue(now), isFalse);
      expect(task(date: '2026-09-04').isOverdue(now), isTrue);
    });

    test('a finished task is never late', () {
      expect(task(date: '2026-09-01', done: true).isOverdue(now), isFalse);
    });

    /// The server stamp is null until the write is acknowledged, so the day
    /// the device wrote down has to carry the answer on its own.
    test('a task finished offline still counts for the day it was done', () {
      const TaskModel pending = TaskModel(
        id: 'p',
        title: 'Offline',
        date: '2026-09-01',
        done: true,
        doneDate: '2026-09-05',
      );
      expect(pending.wasDoneOn(DateTime(2026, 9, 5)), isTrue);
      expect(pending.wasDoneOn(DateTime(2026, 9, 4)), isFalse);
      // The written day wins over a stamp that disagrees with it.
      final TaskModel both = TaskModel(
        id: 'b',
        title: 'Both',
        done: true,
        doneDate: '2026-09-05',
        doneAt: DateTime(2026, 9, 6, 0, 30),
      );
      expect(both.wasDoneOn(DateTime(2026, 9, 5)), isTrue);
    });
  });

  group('when the reminder goes off', () {
    test('an hour before a timed task', () {
      final TaskModel t = task(
        date: '2026-09-05',
        time: const TimeOfDay(hour: 17, minute: 0),
        reminder: 60,
      );
      expect(t.reminderAt, DateTime(2026, 9, 5, 16, 0));
    });

    test('at the time itself for an offset of zero', () {
      final TaskModel t = task(
        date: '2026-09-05',
        time: const TimeOfDay(hour: 17, minute: 0),
        reminder: 0,
      );
      expect(t.reminderAt, DateTime(2026, 9, 5, 17, 0));
    });

    test('the evening before, for a day-only task reminded a day ahead', () {
      final TaskModel t = task(
          date: '2026-09-05', reminder: TaskModel.eveningBeforeOffset);
      expect(t.reminderAt, DateTime(2026, 9, 4, 20, 0));
    });

    test('a day before a timed task crosses the month boundary', () {
      final TaskModel t = task(
        date: '2026-10-01',
        time: const TimeOfDay(hour: 8, minute: 0),
        reminder: 1440,
      );
      expect(t.reminderAt, DateTime(2026, 9, 30, 8, 0));
    });

    test('there is none without a day, whatever the offset says', () {
      expect(task(reminder: 60).reminderAt, isNull);
      expect(task(reminder: 60).hasReminder, isFalse);
    });
  });

  group('the reminder notification', () {
    test('says how far off the task is and when it falls', () {
      final TaskModel t = task(
        date: '2026-09-05',
        time: const TimeOfDay(hour: 17, minute: 0),
        reminder: 60,
      );
      expect(TaskReminderText.body(t, bengali: false), 'In 1 hour — 5:00 PM');
      expect(TaskReminderText.body(t, bengali: true), '1 ঘণ্টা পর — 5:00 PM');
    });

    test('counts minutes under an hour and hours under a day', () {
      final TaskModel quarter = task(
        date: '2026-09-05',
        time: const TimeOfDay(hour: 17, minute: 0),
        reminder: 15,
      );
      expect(TaskReminderText.body(quarter, bengali: false),
          'In 15 minutes — 5:00 PM');

      final TaskModel two = task(
        date: '2026-09-05',
        time: const TimeOfDay(hour: 17, minute: 0),
        reminder: 120,
      );
      expect(TaskReminderText.body(two, bengali: false), 'In 2 hours — 5:00 PM');
    });

    /// Fired the day before, the reminder cannot just say the hour — it has
    /// to say which day the hour is on.
    test('names the day when it fires on a different one', () {
      final TaskModel t = task(
        date: '2026-09-05',
        time: const TimeOfDay(hour: 17, minute: 0),
        reminder: 1440,
      );
      expect(TaskReminderText.body(t, bengali: false),
          'Tomorrow — Sat 5 Sep, 5:00 PM');
      // The day and month names follow the language; the clock does not.
      expect(TaskReminderText.body(t, bengali: true),
          'আগামীকাল — শনি 5 সেপ্ট, 5:00 PM');
    });

    test('says "due now" at the moment itself', () {
      final TaskModel t = task(
        date: '2026-09-05',
        time: const TimeOfDay(hour: 17, minute: 0),
        reminder: 0,
      );
      expect(TaskReminderText.body(t, bengali: false), 'Due now — 5:00 PM');
    });

    test('a day-only task is worded by the day, not the clock', () {
      expect(
        TaskReminderText.body(task(date: '2026-09-05', reminder: 0),
            bengali: false),
        'Due today',
      );
      expect(
        TaskReminderText.body(
            task(date: '2026-09-05', reminder: TaskModel.eveningBeforeOffset),
            bengali: false),
        'Due tomorrow',
      );
      expect(
        TaskReminderText.body(
            task(date: '2026-09-05', reminder: TaskModel.eveningBeforeOffset),
            bengali: true),
        'আগামীকাল করার কথা',
      );
    });

    /// The fingerprint is what decides whether an armed alarm is left alone,
    /// so it has to move with everything the notification is made of — and
    /// with nothing else.
    test('the fingerprint moves with the moment, the words and the language',
        () {
      final TaskModel a = task(
        date: '2026-09-05',
        time: const TimeOfDay(hour: 17, minute: 0),
        reminder: 60,
      );
      final String base =
          TaskReminderText.fingerprint(a, a.reminderAt!, bengali: false);

      expect(TaskReminderText.fingerprint(a, a.reminderAt!, bengali: false),
          base);
      expect(TaskReminderText.fingerprint(a, a.reminderAt!, bengali: true),
          isNot(base));

      final TaskModel renamed = a.copyWith(title: 'Pay the gas bill');
      expect(
          TaskReminderText.fingerprint(renamed, renamed.reminderAt!,
              bengali: false),
          isNot(base));

      final TaskModel moved = a.copyWith(timeHour: 18);
      expect(
          TaskReminderText.fingerprint(moved, moved.reminderAt!,
              bengali: false),
          isNot(base));

      // A note is not on the notification, so it must not re-arm the alarm.
      final TaskModel annotated = a.copyWith(note: 'Meter 4821');
      expect(
          TaskReminderText.fingerprint(annotated, annotated.reminderAt!,
              bengali: false),
          base);
    });

    test('the alarm id is stable and out of the low range', () {
      final TaskModel a = task(id: 'abc123');
      expect(a.notificationId, task(id: 'abc123').notificationId);
      expect(a.notificationId, isNot(task(id: 'abc124').notificationId));
      expect(a.notificationId, greaterThanOrEqualTo(100000));
    });
  });

  group('a finished repeating task', () {
    test('a daily task comes back tomorrow', () {
      final TaskModel t = task(date: '2026-09-05', repeat: TaskRepeat.daily);
      expect(t.nextOccurrence(now), DateTime(2026, 9, 6));
    });

    /// Finished three days late, it is owed tomorrow — not three days ago.
    test('a daily task finished late comes back tomorrow, not in the past', () {
      final TaskModel t = task(date: '2026-09-02', repeat: TaskRepeat.daily);
      expect(t.nextOccurrence(now), DateTime(2026, 9, 6));
    });

    test('a daily task finished early comes back the day after its own day',
        () {
      final TaskModel t = task(date: '2026-09-08', repeat: TaskRepeat.daily);
      expect(t.nextOccurrence(now), DateTime(2026, 9, 9));
    });

    test('a weekly task keeps its weekday', () {
      final TaskModel t = task(date: '2026-09-05', repeat: TaskRepeat.weekly);
      expect(t.nextOccurrence(now), DateTime(2026, 9, 12));
      // Two weeks late: the next Saturday after today.
      final TaskModel late = task(date: '2026-08-22', repeat: TaskRepeat.weekly);
      expect(late.nextOccurrence(now), DateTime(2026, 9, 12));
    });

    test('a monthly task keeps its day of the month', () {
      final TaskModel t = task(date: '2026-09-05', repeat: TaskRepeat.monthly);
      expect(t.nextOccurrence(now), DateTime(2026, 10, 5));
      // The 30th of a 31-day month stays the 30th, not the last day.
      final TaskModel thirtieth =
          task(date: '2026-08-30', repeat: TaskRepeat.monthly);
      expect(thirtieth.nextOccurrence(now), DateTime(2026, 9, 30));
      expect(thirtieth.nextOccurrence(DateTime(2026, 10, 1)), DateTime(2026, 10, 30));
    });

    /// The 31st has to land somewhere in a month with 30 days, and then get
    /// back to the 31st when there is one — not stay clamped forever.
    test('a monthly task on the 31st clamps and recovers', () {
      final TaskModel t = task(
        date: '2026-01-31',
        repeat: TaskRepeat.monthly,
      );
      expect(t.nextOccurrence(DateTime(2026, 1, 31)), DateTime(2026, 2, 28));
      // Owed since January, finished in March: the next 31st after today.
      expect(t.nextOccurrence(DateTime(2026, 3, 15)), DateTime(2026, 3, 31));
      expect(t.nextOccurrence(DateTime(2026, 4, 1)), DateTime(2026, 4, 30));
    });

    /// The chain the app actually walks: each copy is a new document dated
    /// to the clamped day, and has to remember where the schedule began.
    test('a monthly chain clamped in February finds the 31st again in March',
        () {
      final TaskModel january = task(
        id: 'jan',
        date: '2026-01-31',
        repeat: TaskRepeat.monthly,
      ).copyWith(repeatDay: 31);
      final TaskModel february = january.successor(DateTime(2026, 1, 31))!;
      expect(february.date, '2026-02-28');
      expect(february.repeatDay, 31);

      final TaskModel march =
          february.copyWith(id: 'feb').successor(DateTime(2026, 2, 28))!;
      expect(march.date, '2026-03-31');

      final TaskModel april =
          march.copyWith(id: 'mar').successor(DateTime(2026, 3, 31))!;
      expect(april.date, '2026-04-30');
      expect(april.repeatDay, 31);
    });

    /// An older document with no anchor day falls back to its own date.
    test('a monthly task with no recorded day uses the day it carries', () {
      final TaskModel t = task(date: '2026-09-05', repeat: TaskRepeat.monthly);
      expect(t.repeatDay, 0);
      expect(t.successor(now)!.repeatDay, 5);
    });

    test('a one-off has no next occurrence', () {
      expect(task(date: '2026-09-05').nextOccurrence(now), isNull);
      expect(task(date: '2026-09-05').successor(now), isNull);
    });

    test('the successor is the same task, open, on the next day', () {
      final TaskModel t = task(
        id: 'orig',
        date: '2026-09-05',
        time: const TimeOfDay(hour: 8, minute: 30),
        reminder: 30,
        repeat: TaskRepeat.daily,
        priority: TaskPriority.high,
      );
      final TaskModel next = t.successor(now)!;
      expect(next.id, '');
      expect(next.date, '2026-09-06');
      expect(next.hasTime, isTrue);
      expect(next.timeHour, 8);
      expect(next.timeMinute, 30);
      expect(next.reminderMinutes, 30);
      expect(next.followUpMinutes, t.followUpMinutes);
      expect(next.repeat, TaskRepeat.daily);
      expect(next.priority, TaskPriority.high);
      expect(next.done, isFalse);
      expect(next.spawnedFrom, 'orig');
      expect(next.title, t.title);
    });
  });

  group('the piles the screens show', () {
    final List<TaskModel> list = [
      // Today: one done in the morning, one at 4 (still ahead), one at 1
      // (missed), one with no hour.
      task(id: 'done', date: '2026-09-05',
          time: const TimeOfDay(hour: 9, minute: 0), done: true,
          doneAt: DateTime(2026, 9, 5, 9, 5)),
      task(id: 'four', date: '2026-09-05',
          time: const TimeOfDay(hour: 16, minute: 0)),
      task(id: 'one', date: '2026-09-05',
          time: const TimeOfDay(hour: 13, minute: 0)),
      task(id: 'allday', date: '2026-09-05'),
      // Yesterday, never done.
      task(id: 'yesterday', date: '2026-09-04'),
      // Tomorrow, and next week.
      task(id: 'tomorrow', date: '2026-09-06'),
      task(id: 'nextweek', date: '2026-09-12'),
      task(id: 'nextweek2', date: '2026-09-12',
          time: const TimeOfDay(hour: 10, minute: 0)),
      // No day.
      task(id: 'someday'),
      // Finished last week; caught up an old one today.
      task(id: 'oldone', date: '2026-08-30', done: true,
          doneAt: DateTime(2026, 8, 30, 20, 0)),
      task(id: 'caughtup', date: '2026-09-01', done: true,
          doneAt: DateTime(2026, 9, 5, 11, 0)),
    ];

    final TaskDigest digest = TaskDigest.of(list, now: now);

    test('today holds everything dated today, finished or not, in day order',
        () {
      expect(digest.today.map((t) => t.id), ['done', 'one', 'four', 'allday']);
      expect(digest.todayTotal, 4);
      expect(digest.todayDone, 1);
      expect(digest.todayOpen, 3);
      expect(digest.todayProgress, 0.25);
      expect(digest.allDoneToday, isFalse);
    });

    test('overdue holds yesterday and the missed hour, oldest first', () {
      expect(digest.overdue.map((t) => t.id), ['yesterday', 'one']);
      // Only the one from before today is news the today list does not show.
      expect(digest.overdueBeforeToday, 1);
      expect(digest.overdueEarlier.map((t) => t.id), ['yesterday']);
    });

    test('today splits into what is open and what is done', () {
      expect(digest.todayOpenList.map((t) => t.id), ['one', 'four', 'allday']);
      expect(digest.todayDoneList.map((t) => t.id), ['done']);
    });

    test('tomorrow, later and someday are kept apart', () {
      expect(digest.tomorrow.map((t) => t.id), ['tomorrow']);
      // Timed before untimed within a day.
      expect(digest.later.map((t) => t.id), ['nextweek2', 'nextweek']);
      expect(digest.someday.map((t) => t.id), ['someday']);
      expect(digest.laterByDay.length, 1);
      expect(digest.laterByDay.first.key, DateTime(2026, 9, 12));
    });

    test('completed is newest first, and today\'s catch-up counts for today',
        () {
      expect(digest.completed.map((t) => t.id), ['caughtup', 'done', 'oldone']);
      expect(digest.doneToday.map((t) => t.id), ['caughtup', 'done']);
    });

    test('open count adds up across the piles', () {
      // yesterday + (one, four, allday) + tomorrow + 2 later + someday
      expect(digest.openCount, 8);
      expect(digest.hasSomethingForToday, isTrue);
    });

    test('an empty list has nothing for today and an empty ring', () {
      final TaskDigest empty = TaskDigest.of(const [], now: now);
      expect(empty.hasSomethingForToday, isFalse);
      expect(empty.todayProgress, 0);
      expect(empty.allDoneToday, isFalse);
    });

    /// A day already finished is not worth an interruption.
    test('a day whose tasks are all done has nothing to raise a sheet for',
        () {
      final TaskDigest finished = TaskDigest.of([
        task(id: 'a', date: '2026-09-05', done: true,
            doneAt: DateTime(2026, 9, 5, 8, 0)),
      ], now: now);
      expect(finished.allDoneToday, isTrue);
      expect(finished.hasSomethingForToday, isFalse);
    });

    test('only open tasks with a reminder still ahead are armed', () {
      final TaskDigest armed = TaskDigest.of([
        task(id: 'ahead', date: '2026-09-05',
            time: const TimeOfDay(hour: 16, minute: 0), reminder: 30),
        task(id: 'passed', date: '2026-09-05',
            time: const TimeOfDay(hour: 14, minute: 45), reminder: 30),
        task(id: 'finished', date: '2026-09-06',
            time: const TimeOfDay(hour: 9, minute: 0), reminder: 30,
            done: true, doneAt: now),
        task(id: 'silent', date: '2026-09-06'),
      ], now: now);
      expect(armed.armed.map((t) => t.id), ['ahead']);
    });
  });

  group('ordering', () {
    test('dated before undated, sooner before later, timed before all-day',
        () {
      final List<TaskModel> list = [
        task(id: 'someday'),
        task(id: 'late-day', date: '2026-09-07'),
        task(id: 'early-day', date: '2026-09-06'),
        task(id: 'early-time', date: '2026-09-06',
            time: const TimeOfDay(hour: 8, minute: 0)),
      ]..sort(TaskModel.compare);
      expect(list.map((t) => t.id),
          ['early-time', 'early-day', 'late-day', 'someday']);
    });

    test('priority breaks a tie, high first', () {
      final List<TaskModel> list = [
        task(id: 'low', date: '2026-09-06', priority: TaskPriority.low),
        task(id: 'high', date: '2026-09-06', priority: TaskPriority.high),
        task(id: 'normal', date: '2026-09-06'),
      ]..sort(TaskModel.compare);
      expect(list.map((t) => t.id), ['high', 'normal', 'low']);
    });
  });

  group('reading a document', () {
    test('an older negative "no reminder" reads as none', () {
      final TaskModel t = TaskModel.fromMap('x', {
        'title': 'Old shape',
        'date': '2026-09-05',
        'reminder_minutes': -1,
      });
      expect(t.reminderMinutes, isNull);
      expect(t.hasReminder, isFalse);
    });

    test('unknown priority and repeat fall back rather than throwing', () {
      final TaskModel t = TaskModel.fromMap('x', {
        'title': 'Odd',
        'priority': 'urgent',
        'repeat': 'fortnightly',
      });
      expect(t.priority, TaskPriority.normal);
      expect(t.repeat, TaskRepeat.none);
    });

    test('round-trips through toMap', () {
      final TaskModel t = task(
        date: '2026-09-05',
        time: const TimeOfDay(hour: 17, minute: 0),
        reminder: 60,
        repeat: TaskRepeat.weekly,
        priority: TaskPriority.high,
      ).copyWith(repeatDay: 5, followUpMinutes: 30);
      final TaskModel back = TaskModel.fromMap(t.id, t.toMap());
      expect(back.repeatDay, 5);
      expect(back.followUpMinutes, 30);
      expect(back.title, t.title);
      expect(back.date, t.date);
      expect(back.hasTime, isTrue);
      expect(back.timeHour, 17);
      expect(back.reminderMinutes, 60);
      expect(back.repeat, TaskRepeat.weekly);
      expect(back.priority, TaskPriority.high);
      expect(back.done, isFalse);
    });
  });
}

/// The half of the reminder service that decides rather than talks to the
/// OS: which tasks should hold an alarm, and what one pass has to arm or
/// take down.
void planTests() {
  final DateTime now = DateTime(2026, 9, 5, 14, 30);

  group('a reminder whose moment has gone', () {
    TaskModel at(int hour, int offset) => TaskModel(
          id: 'x',
          title: 'x',
          date: '2026-09-05',
          hasTime: true,
          timeHour: hour,
          reminderMinutes: offset,
        );

    test('is moved to the hour itself while that is still ahead', () {
      // Due at three, "an hour before" would have rung at two — gone.
      final TaskModel fixed = TaskController.withLiveReminder(at(15, 60), now);
      expect(fixed.reminderMinutes, 0);
      expect(fixed.reminderAt, DateTime(2026, 9, 5, 15, 0));
    });

    test('is dropped once the hour itself has gone too', () {
      final TaskModel fixed = TaskController.withLiveReminder(at(14, 0), now);
      expect(fixed.reminderMinutes, isNull);
    });

    test('is left alone while it is still ahead', () {
      final TaskModel fixed = TaskController.withLiveReminder(at(17, 60), now);
      expect(fixed.reminderMinutes, 60);
    });

    /// The follow-on copy of a daily task ticked after its hour would carry
    /// a "day before" reminder that has already passed for tomorrow's copy.
    test('applies to the copy a finished repeating task leaves behind', () {
      final TaskModel daily = TaskModel(
        id: 'd',
        title: 'd',
        date: '2026-09-05',
        hasTime: true,
        timeHour: 14,
        reminderMinutes: 1440,
        repeat: TaskRepeat.daily,
      );
      final TaskModel next = TaskController.withLiveReminder(
          daily.successor(now)!, now);
      expect(next.date, '2026-09-06');
      // Tomorrow at two is still ahead; the reminder moves there.
      expect(next.reminderMinutes, 0);
    });
  });

  group('whether a follow-on copy has been touched', () {
    test('a copy the server has not stamped yet is untouched', () {
      expect(const TaskModel(id: 'a', title: 'a').isUntouchedSince, isTrue);
    });

    test('equal stamps mean untouched, a later update means touched', () {
      final DateTime t = DateTime(2026, 9, 5, 10, 0);
      final TaskModel fresh = TaskModel.fromMap('a', {
        'title': 'a',
        'createdAt': Timestamp.fromDate(t),
        'updatedAt': Timestamp.fromDate(t),
      });
      expect(fresh.isUntouchedSince, isTrue);
      final TaskModel edited = TaskModel.fromMap('a', {
        'title': 'a',
        'createdAt': Timestamp.fromDate(t),
        'updatedAt': Timestamp.fromDate(t.add(const Duration(minutes: 5))),
      });
      expect(edited.isUntouchedSince, isFalse);
    });
  });

  TaskModel timed(String id, DateTime at, {bool done = false, int offset = 0}) {
    return TaskModel(
      id: id,
      title: id,
      date: TaskModel.keyOf(at),
      hasTime: true,
      timeHour: at.hour,
      timeMinute: at.minute,
      reminderMinutes: offset,
      done: done,
    );
  }

  group('which reminders are armed', () {
    test('only open tasks with a reminder still ahead, soonest first', () {
      final List<TaskAlarm> picked = TaskReminderService.select([
        timed('later', DateTime(2026, 9, 6, 9, 0)),
        timed('soon', DateTime(2026, 9, 5, 16, 0)),
        timed('passed', DateTime(2026, 9, 5, 14, 0)),
        timed('finished', DateTime(2026, 9, 5, 18, 0), done: true),
        const TaskModel(id: 'silent', title: 'No reminder', date: '2026-09-06'),
        // Written a moment ago and not yet echoed back with an id: nothing
        // to file an alarm under until it is.
        const TaskModel(id: '', title: 'No id yet', date: '2026-09-06',
            reminderMinutes: 0),
      ], now: now);
      expect(picked.map((a) => a.task.id), ['soon', 'later']);
      expect(picked.every((a) => a.kind == TaskAlarmKind.reminder), isTrue);
    });

    /// The follow-up is a second alarm on the same task, after the hour, and
    /// only while the task is open with an hour to be late against.
    test('a follow-up is armed after the hour, beside the reminder', () {
      final TaskModel t = TaskModel(
        id: 'bill',
        title: 'Bill',
        date: '2026-09-05',
        hasTime: true,
        timeHour: 16,
        reminderMinutes: 30,
        followUpMinutes: 30,
      );
      final List<TaskAlarm> picked = TaskReminderService.select([t], now: now);
      expect(picked.map((a) => a.kind),
          [TaskAlarmKind.reminder, TaskAlarmKind.followUp]);
      expect(picked[0].at, DateTime(2026, 9, 5, 15, 30));
      expect(picked[1].at, DateTime(2026, 9, 5, 16, 30));
      expect(picked[0].id, isNot(picked[1].id));
      expect(picked[1].id, t.followUpNotificationId);

      // The hour has gone but the follow-up has not: only that one stands.
      final List<TaskAlarm> late = TaskReminderService.select([t],
          now: DateTime(2026, 9, 5, 16, 10));
      expect(late.map((a) => a.kind), [TaskAlarmKind.followUp]);

      // No hour, no follow-up — whatever the field says.
      final TaskModel allDay = t.copyWith(hasTime: false);
      expect(allDay.followUpAt, isNull);
      expect(allDay.hasFollowUp, isFalse);
      expect(TaskReminderService.select([allDay], now: now), isEmpty);
    });

    test('the follow-up says the task is still open and when it was due', () {
      final TaskModel t = TaskModel(
        id: 'bill',
        title: 'Bill',
        date: '2026-09-05',
        hasTime: true,
        timeHour: 16,
        followUpMinutes: 30,
      );
      expect(TaskReminderText.followUpBody(t, bengali: false),
          'Still not done — was due 4:00 PM');
      expect(TaskReminderText.followUpBody(t, bengali: true),
          'এখনও হয়নি — 4:00 PM-এ করার কথা ছিল');
      // Late enough to cross midnight: the day is named.
      final TaskModel night = t.copyWith(timeHour: 23, followUpMinutes: 120);
      expect(TaskReminderText.followUpBody(night, bengali: false),
          'Still not done — was due Sat 5 Sep, 11:00 PM');
      // The two alarms of one task never share a fingerprint.
      final TaskAlarm a = TaskAlarm(t, t.reminderAt ?? t.dueAt!, TaskAlarmKind.reminder);
      final TaskAlarm b = TaskAlarm(t, t.followUpAt!, TaskAlarmKind.followUp);
      expect(TaskReminderText.fingerprintFor(a, bengali: false),
          isNot(TaskReminderText.fingerprintFor(b, bengali: false)));
    });

    /// A moment a second or two away is gone by the time the OS is asked.
    /// Tasks keep whole minutes, so the clock is what carries the seconds.
    test('leaves out a moment inside the lead time', () {
      final DateTime almost = DateTime(2026, 9, 5, 14, 29, 57);
      final List<TaskAlarm> picked = TaskReminderService.select([
        timed('three-seconds', DateTime(2026, 9, 5, 14, 30)),
        timed('next-minute', DateTime(2026, 9, 5, 14, 31)),
      ], now: almost);
      expect(picked.map((a) => a.task.id), ['next-minute']);
    });

    test('holds no more than the cap, keeping the nearest', () {
      final List<TaskModel> many = [
        for (int i = 0; i < 80; i++)
          timed('t$i', DateTime(2026, 9, 6, 8, 0).add(Duration(minutes: 80 - i))),
      ];
      final List<TaskAlarm> picked = TaskReminderService.select(many, now: now);
      expect(picked.length, TaskReminderService.maxArmed);
      // The nearest is the one with the smallest offset — the last in the
      // list as built.
      expect(picked.first.task.id, 't79');
      expect(picked.last.task.id, 't20');
    });
  });

  group('what one pass does', () {
    test('arms what is missing and leaves what is unchanged', () {
      final TaskReminderPlan plan = TaskReminderPlan.diff(
        wanted: {1: 'a', 2: 'b'},
        pending: {1: 'a'},
      );
      expect(plan.toSchedule, {2});
      expect(plan.toCancel, isEmpty);
    });

    test('re-arms what changed shape', () {
      final TaskReminderPlan plan = TaskReminderPlan.diff(
        wanted: {1: 'a2'},
        pending: {1: 'a1'},
      );
      expect(plan.toSchedule, {1});
      expect(plan.toCancel, isEmpty);
    });

    test('takes down what is no longer wanted', () {
      final TaskReminderPlan plan = TaskReminderPlan.diff(
        wanted: {},
        pending: {1: 'a', 2: 'b'},
      );
      expect(plan.toCancel, {1, 2});
      expect(plan.toSchedule, isEmpty);
    });

    /// The first pass of a process trusts nothing the record says about what
    /// is armed — a force-stop empties the alarms and leaves the record as it
    /// was — but still takes down what the record shows is unwanted.
    test('a re-arm pass schedules everything wanted and cancels the rest', () {
      final TaskReminderPlan plan = TaskReminderPlan.diff(
        wanted: {1: 'a', 2: 'b'},
        pending: {1: 'a', 3: 'c'},
        rearmAll: true,
      );
      expect(plan.toSchedule, {1, 2});
      expect(plan.toCancel, {3});
    });

    /// A list that could not be read arms everything again — same ids, so
    /// the OS replaces rather than doubles.
    test('an empty pending list arms everything wanted', () {
      final TaskReminderPlan plan = TaskReminderPlan.diff(
        wanted: {1: 'a', 2: 'b'},
        pending: {},
      );
      expect(plan.toSchedule, {1, 2});
      expect(plan.toCancel, isEmpty);
    });
  });
}
