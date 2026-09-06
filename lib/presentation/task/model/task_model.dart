import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// How much a task matters, as three steps. Nothing is computed from it: it
/// colours the row and breaks ties in the ordering, and that is all.
enum TaskPriority {
  low,
  normal,
  high;

  static TaskPriority of(String? raw) {
    switch (raw) {
      case 'low':
        return TaskPriority.low;
      case 'high':
        return TaskPriority.high;
      default:
        return TaskPriority.normal;
    }
  }

  /// High first: the number that sorts two tasks due at the same moment.
  int get weight {
    switch (this) {
      case TaskPriority.high:
        return 0;
      case TaskPriority.normal:
        return 1;
      case TaskPriority.low:
        return 2;
    }
  }
}

/// How a task comes back once it is done. [none] is the ordinary one-off;
/// the other three are what "my regular tasks" means — the same task on a
/// schedule, finished today and waiting again on the next day it is due.
enum TaskRepeat {
  none,
  daily,
  weekly,
  monthly;

  static TaskRepeat of(String? raw) {
    switch (raw) {
      case 'daily':
        return TaskRepeat.daily;
      case 'weekly':
        return TaskRepeat.weekly;
      case 'monthly':
        return TaskRepeat.monthly;
      default:
        return TaskRepeat.none;
    }
  }

  bool get repeats => this != TaskRepeat.none;
}

/// One thing a member has to do.
///
/// Personal by construction, the way the ledger is: every document carries
/// the owner's phone and is only ever read back filtered by it. Nothing here
/// is shared with the house.
///
/// The date and the time are optional, and separately so. A task can be a
/// bare line with no day attached (something for "someday"), a day with no
/// hour (pay the bill on the 5th), or a day and an hour (the meeting at
/// four). Each of those reads and sorts differently, and the reminder means
/// something different against each — see [dueAt] and [reminderAt].
///
/// A repeating task is one document per occurrence. Finishing today's copy
/// writes the next one — see [nextOccurrence] — so every list here treats a
/// document as a single dated thing and never has to unroll a schedule, and
/// what was done on which day stays on record.
class TaskModel {
  final String id;
  final String ownerPhone;
  final String title;
  final String note;

  /// The day it is due, as `yyyy-MM-dd` — the same shape the meals and the
  /// personal ledger keep, so "today" is a string comparison. Empty for a
  /// task with no day.
  final String date;

  /// Whether [timeHour]:[timeMinute] mean anything. Kept as its own flag
  /// rather than a sentinel hour, because midnight is a real time.
  final bool hasTime;
  final int timeHour;
  final int timeMinute;

  /// How many minutes before the task the reminder goes off, or null for no
  /// reminder. Zero is "at the time itself". Measured against
  /// [reminderAnchor], which for a task with no hour is the morning of the
  /// day — see [allDayReminderHour].
  final int? reminderMinutes;

  /// How many minutes after the task's hour a second word goes out if it is
  /// still not done, or null for none. Only a task with an hour has a moment
  /// to be late against, so it means nothing without [hasTime]. The first
  /// reminder says "it is coming"; this one says "it has gone and you have
  /// not ticked it" — for the person who heard the first and forgot anyway.
  final int? followUpMinutes;

  final TaskPriority priority;
  final TaskRepeat repeat;

  /// For a monthly task, the day of the month it was first set on — 1..31,
  /// or 0 for a task that does not repeat monthly. A monthly task clamped to
  /// the 28th in February has to find its way back to the 31st in March, and
  /// once it is a new document dated the 28th its own date can no longer say
  /// where it started. This can.
  final int repeatDay;

  final bool done;
  final DateTime? doneAt;

  /// The local day it was finished on, `yyyy-MM-dd`, written by the device
  /// that ticked it off. Kept beside the server stamp because the stamp is
  /// null until the write is acknowledged — a task finished on the bus with
  /// no signal still has to count towards today's figure right away.
  final String doneDate;

  /// The occurrence this one was written from when that one was finished —
  /// empty for anything typed in by hand. What lets an undo take the
  /// follow-on copy back out again, so a mis-tap does not leave two of
  /// tomorrow's task standing.
  final String spawnedFrom;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Written on this device and not acknowledged by the server yet.
  final bool pending;

  const TaskModel({
    this.id = '',
    this.ownerPhone = '',
    this.title = '',
    this.note = '',
    this.date = '',
    this.hasTime = false,
    this.timeHour = 0,
    this.timeMinute = 0,
    this.reminderMinutes,
    this.followUpMinutes,
    this.priority = TaskPriority.normal,
    this.repeat = TaskRepeat.none,
    this.repeatDay = 0,
    this.done = false,
    this.doneAt,
    this.doneDate = '',
    this.spawnedFrom = '',
    this.createdAt,
    this.updatedAt,
    this.pending = false,
  });

  /// The hour a task with a day but no time is reminded at — and counts as
  /// "due" at, for the wording of the reminder. Nine in the morning: late
  /// enough to be awake for, early enough that the day is still ahead.
  static const int allDayReminderHour = 9;

  /// The offsets the editor offers for a task with an hour, in minutes.
  static const List<int> timedReminderOffsets = [0, 5, 10, 15, 30, 60, 120, 1440];

  /// The offsets offered for a task with a day but no hour: the morning of
  /// the day itself, or the evening before it — eight o'clock, thirteen hours
  /// ahead of the nine o'clock anchor, when tomorrow is being thought about.
  static const List<int> allDayReminderOffsets = [0, eveningBeforeOffset];

  /// Nine in the morning back to eight the evening before, in minutes.
  static const int eveningBeforeOffset = 13 * 60;

  /// How long after the hour the follow-up waits, as the editor offers it.
  static const List<int> followUpOffsets = [10, 15, 30, 60, 120, 180];

  /// What a new timed task starts with: half an hour — long enough that a
  /// task finished a few minutes late is not nagged about, short enough that
  /// a forgotten one is still worth doing when the word comes.
  static const int defaultFollowUpMinutes = 30;

  bool get hasDate => date.isNotEmpty;

  bool get hasReminder => reminderMinutes != null && hasDate;

  bool get hasFollowUp => followUpMinutes != null && hasDate && hasTime;

  bool get hasNote => note.trim().isNotEmpty;

  /// The day, or null for a task with no date. Midnight, local time.
  DateTime? get day {
    if (!hasDate) return null;
    final DateTime? parsed = DateTime.tryParse(date);
    if (parsed == null) return null;
    return DateTime(parsed.year, parsed.month, parsed.day);
  }

  TimeOfDay get time => TimeOfDay(hour: timeHour, minute: timeMinute);

  /// The moment the task is due, for ordering and for deciding when it is
  /// late. A task with an hour is due at that hour; one with only a day is
  /// due at the end of it — nothing is late until the day is over. Null for
  /// a task with no date.
  DateTime? get dueAt {
    final DateTime? d = day;
    if (d == null) return null;
    if (hasTime) return DateTime(d.year, d.month, d.day, timeHour, timeMinute);
    return DateTime(d.year, d.month, d.day, 23, 59, 59);
  }

  /// What the reminder offset is measured from: the hour itself, or nine in
  /// the morning for a task that has none.
  DateTime? get reminderAnchor {
    final DateTime? d = day;
    if (d == null) return null;
    if (hasTime) return DateTime(d.year, d.month, d.day, timeHour, timeMinute);
    return DateTime(d.year, d.month, d.day, allDayReminderHour);
  }

  /// When the reminder goes off, or null for none.
  DateTime? get reminderAt {
    final int? minutes = reminderMinutes;
    final DateTime? anchor = reminderAnchor;
    if (minutes == null || anchor == null) return null;
    return anchor.subtract(Duration(minutes: minutes));
  }

  /// When the follow-up goes off — the hour plus [followUpMinutes] — or null
  /// for a task with none, or with no hour to be late against.
  DateTime? get followUpAt {
    final int? minutes = followUpMinutes;
    if (minutes == null || !hasTime) return null;
    final DateTime? due = dueAt;
    if (due == null) return null;
    return due.add(Duration(minutes: minutes));
  }

  /// Minutes since midnight, for sorting within a day. A task with no hour
  /// sorts after every task that has one — the day's fixed appointments
  /// first, then the things to fit around them.
  int get minuteOfDay => hasTime ? timeHour * 60 + timeMinute : 24 * 60;

  /// `yyyy-MM-dd` for [date], the way every dated document in the app keys
  /// its day.
  static String keyOf(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  static DateTime dayOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);

  bool isOn(DateTime day) => hasDate && date == keyOf(day);

  /// Whether the task is due today, by the clock handed in.
  bool isToday(DateTime now) => isOn(now);

  /// Past due and still open. A task with an hour is late once the hour has
  /// gone; one with only a day is late once the day has.
  bool isOverdue(DateTime now) {
    if (done) return false;
    final DateTime? due = dueAt;
    if (due == null) return false;
    return due.isBefore(now);
  }

  /// Due after today.
  bool isUpcoming(DateTime now) {
    final DateTime? d = day;
    if (d == null) return false;
    return d.isAfter(dayOf(now));
  }

  /// Finished on [day] — what the day's summary counts as done, whichever
  /// day the task was due. The device's own day first; the server stamp
  /// stands in for a document written before the day was recorded.
  bool wasDoneOn(DateTime day) {
    if (!done) return false;
    if (doneDate.isNotEmpty) return doneDate == keyOf(day);
    final DateTime? at = doneAt;
    if (at == null) return false;
    return keyOf(at) == keyOf(day);
  }

  /// The day this task comes round again after being finished, or null for
  /// one that does not repeat.
  ///
  /// Counted forward from the task's own day, and pushed past [today] if
  /// need be: a daily task finished three days late comes back tomorrow, not
  /// two days ago. Monthly keeps the day of the month and clamps to a
  /// shorter one — the 31st becomes the 28th in February rather than
  /// slipping into March.
  DateTime? nextOccurrence(DateTime today) {
    if (!repeat.repeats) return null;
    DateTime from = day ?? dayOf(today);
    final DateTime floor = dayOf(today);

    DateTime step(DateTime d, int count) {
      switch (repeat) {
        case TaskRepeat.daily:
          return DateTime(d.year, d.month, d.day + count);
        case TaskRepeat.weekly:
          return DateTime(d.year, d.month, d.day + 7 * count);
        case TaskRepeat.monthly:
          // The day the schedule was set on, not the day this copy happens
          // to carry — see [repeatDay].
          final int wanted = repeatDay > 0 ? repeatDay : (day ?? d).day;
          final int months = d.year * 12 + d.month - 1 + count;
          final int year = months ~/ 12;
          final int month = months % 12 + 1;
          final int lastDay = DateTime(year, month + 1, 0).day;
          return DateTime(year, month, wanted < lastDay ? wanted : lastDay);
        case TaskRepeat.none:
          return d;
      }
    }

    // Bounded: a task dated years back could otherwise be stepped forward
    // one day at a time for thousands of turns.
    int count = 1;
    DateTime next = step(from, count);
    while (!next.isAfter(floor) && count < 5000) {
      count++;
      next = step(from, count);
    }
    return next;
  }

  /// The copy that stands in for this task after it is finished — the same
  /// task, dated to the next day it is due, open again. Null for a one-off.
  TaskModel? successor(DateTime today) {
    final DateTime? next = nextOccurrence(today);
    if (next == null) return null;
    return TaskModel(
      ownerPhone: ownerPhone,
      title: title,
      note: note,
      date: keyOf(next),
      hasTime: hasTime,
      timeHour: timeHour,
      timeMinute: timeMinute,
      reminderMinutes: reminderMinutes,
      followUpMinutes: followUpMinutes,
      priority: priority,
      repeat: repeat,
      // Carried verbatim, so the whole chain remembers the day it began on.
      repeatDay: repeat == TaskRepeat.monthly
          ? (repeatDay > 0 ? repeatDay : (day?.day ?? 0))
          : 0,
      spawnedFrom: id,
    );
  }

  /// Whether the follow-on copy a completion wrote is still exactly as it was
  /// written. Both stamps land in the same batch, so they are equal until an
  /// edit moves the second one; a copy the server has not acknowledged yet
  /// has neither, and is untouched by definition.
  bool get isUntouchedSince {
    if (createdAt == null && updatedAt == null) return true;
    if (createdAt == null || updatedAt == null) return false;
    return createdAt == updatedAt;
  }

  /// The id the reminder is filed with the OS under. Derived from the
  /// document id alone, so the same task on any launch — or any of the
  /// member's devices — arms and cancels the same alarm. FNV-1a over the id,
  /// kept out of the low range the other notifications use.
  int get notificationId => _alarmId(id);

  /// The follow-up's own id — a second alarm for the same task, so it is
  /// hashed from a second name rather than placed next to the first, where it
  /// could land on another task's.
  int get followUpNotificationId => _alarmId('$id:follow_up');

  static int _alarmId(String name) {
    int hash = 0x811C9DC5;
    for (final int unit in name.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return 100000 + (hash & 0x3FFFFFFF);
  }

  factory TaskModel.fromMap(
    String id,
    Map<String, dynamic> map, {
    bool pending = false,
  }) {
    final Object? reminder = map['reminder_minutes'];
    final Object? followUp = map['follow_up_minutes'];
    return TaskModel(
      id: id,
      ownerPhone: (map['owner_phone'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      note: (map['note'] ?? '').toString(),
      date: (map['date'] ?? '').toString(),
      hasTime: map['has_time'] == true,
      timeHour: (map['time_hour'] as num?)?.toInt() ?? 0,
      timeMinute: (map['time_minute'] as num?)?.toInt() ?? 0,
      // A negative number is an older shape of "none"; read it as such
      // rather than arming a reminder in the past.
      reminderMinutes:
          reminder is num && reminder >= 0 ? reminder.toInt() : null,
      followUpMinutes:
          followUp is num && followUp > 0 ? followUp.toInt() : null,
      priority: TaskPriority.of(map['priority']?.toString()),
      repeat: TaskRepeat.of(map['repeat']?.toString()),
      repeatDay: (map['repeat_day'] as num?)?.toInt() ?? 0,
      done: map['done'] == true,
      doneAt: (map['done_at'] as Timestamp?)?.toDate(),
      doneDate: (map['done_date'] ?? '').toString(),
      spawnedFrom: (map['spawned_from'] ?? '').toString(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (map['updatedAt'] as Timestamp?)?.toDate(),
      pending: pending,
    );
  }

  /// The stored fields only — the timestamps are stamped by the repository,
  /// which is the one place that may decide them.
  Map<String, dynamic> toMap() => {
        'owner_phone': ownerPhone,
        'title': title,
        'note': note,
        'date': date,
        'has_time': hasTime,
        'time_hour': timeHour,
        'time_minute': timeMinute,
        'reminder_minutes': reminderMinutes,
        'follow_up_minutes': followUpMinutes,
        'priority': priority.name,
        'repeat': repeat.name,
        'repeat_day': repeatDay,
        'done': done,
        'spawned_from': spawnedFrom,
      };

  TaskModel copyWith({
    String? id,
    String? title,
    String? note,
    String? date,
    bool? hasTime,
    int? timeHour,
    int? timeMinute,
    int? reminderMinutes,
    bool clearReminder = false,
    int? followUpMinutes,
    bool clearFollowUp = false,
    TaskPriority? priority,
    TaskRepeat? repeat,
    int? repeatDay,
    bool? done,
    DateTime? doneAt,
    bool clearDoneAt = false,
    String? doneDate,
    String? spawnedFrom,
    bool? pending,
  }) {
    return TaskModel(
      id: id ?? this.id,
      ownerPhone: ownerPhone,
      title: title ?? this.title,
      note: note ?? this.note,
      date: date ?? this.date,
      hasTime: hasTime ?? this.hasTime,
      timeHour: timeHour ?? this.timeHour,
      timeMinute: timeMinute ?? this.timeMinute,
      reminderMinutes:
          clearReminder ? null : (reminderMinutes ?? this.reminderMinutes),
      followUpMinutes:
          clearFollowUp ? null : (followUpMinutes ?? this.followUpMinutes),
      priority: priority ?? this.priority,
      repeat: repeat ?? this.repeat,
      repeatDay: repeatDay ?? this.repeatDay,
      done: done ?? this.done,
      doneAt: clearDoneAt ? null : (doneAt ?? this.doneAt),
      doneDate: clearDoneAt ? '' : (doneDate ?? this.doneDate),
      spawnedFrom: spawnedFrom ?? this.spawnedFrom,
      createdAt: createdAt,
      updatedAt: updatedAt,
      pending: pending ?? this.pending,
    );
  }

  /// The order the lists show: what is due soonest first, a task with no
  /// hour after the day's timed ones, priority breaking ties, and the id
  /// last so the order stops shuffling between rebuilds. Undated tasks sort
  /// after every dated one.
  static int compare(TaskModel a, TaskModel b) {
    if (a.hasDate != b.hasDate) return a.hasDate ? -1 : 1;
    if (a.hasDate) {
      final int byDate = a.date.compareTo(b.date);
      if (byDate != 0) return byDate;
      final int byMinute = a.minuteOfDay.compareTo(b.minuteOfDay);
      if (byMinute != 0) return byMinute;
    }
    final int byPriority = a.priority.weight.compareTo(b.priority.weight);
    if (byPriority != 0) return byPriority;
    final DateTime? ca = a.createdAt;
    final DateTime? cb = b.createdAt;
    if (ca != null && cb != null) {
      final int byCreated = ca.compareTo(cb);
      if (byCreated != 0) return byCreated;
    }
    return a.id.compareTo(b.id);
  }
}
