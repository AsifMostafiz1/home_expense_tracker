import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/timezone.dart' as tz;

import '../presentation/task/model/task_model.dart';
import '../utils/app_constant.dart';

/// The alarms behind a member's task reminders.
///
/// A reminder is a notification handed to the OS in advance — not a push, and
/// not a background job. A push would need a server to remember the hour; the
/// meal reminder's job wakes the app to read fresh names, which a task never
/// needs: its title is fixed when it is written. So the OS holds one alarm
/// per reminder and draws the notification itself, whether or not the app is
/// running, and rebuilds the lot after a reboot through the receivers the
/// manifest declares.
///
/// **Reconciled, not sent.** Nothing here is called when a task is saved.
/// Instead, every snapshot of the member's list — the one the controller is
/// already listening to — is handed to [reconcile], which brings the OS's
/// alarms into line with it: arming what is missing, replacing what changed,
/// cancelling what is done, deleted or past. That one rule covers every case
/// that would otherwise each need its own code path — an edit that moves the
/// hour, a task finished early, a delete, a reminder set on another phone
/// signed into the same account, a launch after a reinstall — and it is
/// idempotent, so running it twice costs two reads of the pending list and
/// changes nothing.
///
/// Each alarm carries a fingerprint of what it was armed with, so a snapshot
/// that changed nothing about a task leaves its alarm alone rather than
/// re-arming it — which would reset the OS's own bookkeeping every time a
/// neighbouring task was touched.
class TaskReminderService {
  TaskReminderService._();

  /// What every reminder's payload says it is; what the router opens the
  /// list for, and what [reconcile] recognises its own alarms by among
  /// everything else the app may have pending.
  static const String payloadType = 'task_reminder';

  /// Its own channel, like the meal reminder: a personal alarm is exactly
  /// the notification somebody wants to give its own sound to, or silence on
  /// its own, and Android only offers that per channel.
  static const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'task_reminder_channel',
    'Task reminders',
    description: 'Reminders for the tasks you set a time for.',
    importance: Importance.high,
  );

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Reconciles run one after another, never side by side: two snapshots a
  /// moment apart would otherwise both read the same pending list and both
  /// decide to arm the same alarm.
  static Future<void> _queue = Future<void>.value();

  static bool _channelReady = false;

  /// Whether this process has yet re-armed everything once.
  ///
  /// On Android the pending list is the plugin's own record of what it was
  /// asked to schedule, not what the alarm service is holding — and the two
  /// part ways when the app is force-stopped, by the user or by a battery
  /// manager: the system drops every alarm the app had, the record does not
  /// notice. So the first pass of every process arms every wanted alarm
  /// again regardless of what the record says. Same ids, so nothing doubles;
  /// at most [maxArmed] calls, once.
  static bool _rearmed = false;

  /// How far ahead a reminder has to be to be worth arming — see
  /// [_reconcile].
  static const Duration _leadTime = Duration(seconds: 5);

  /// The most alarms held at once — under the sixty-four iOS allows.
  static const int maxArmed = 60;

  /// Brings the OS's alarms into line with [tasks] — see the class note.
  ///
  /// [bengali] decides the wording on the notification, fixed now because
  /// nothing runs when it fires. Returns once the alarms are set; a failure
  /// on one alarm is logged and the rest still go through.
  static Future<void> reconcile(
    List<TaskModel> tasks, {
    required bool bengali,
    DateTime? now,
  }) {
    if (kIsWeb) return Future<void>.value();
    return _queue = _queue
        .then((_) => _reconcile(tasks, bengali: bengali, now: now))
        .catchError((Object e) =>
            debugPrint('TaskReminder: reconcile failed — $e'));
  }

  static Future<void> _reconcile(
    List<TaskModel> tasks, {
    required bool bengali,
    DateTime? now,
  }) async {
    final DateTime clock = now ?? DateTime.now();

    // What should be armed — see [select].
    final List<TaskAlarm> selected = select(tasks, now: clock);
    if (selected.length == maxArmed) {
      debugPrint('TaskReminder: alarms beyond the $maxArmed nearest are '
          'left for a later pass');
    }

    // Exact where allowed, rough otherwise — decided once per pass, and part
    // of every fingerprint below, so a permission granted since re-arms
    // every rough alarm as an exact one.
    final AndroidScheduleMode mode =
        selected.isEmpty ? AndroidScheduleMode.inexactAllowWhileIdle : await _scheduleMode();

    final Map<int, _Planned> wanted = {
      for (final TaskAlarm alarm in selected)
        alarm.id: _Planned(alarm: alarm, bengali: bengali, mode: mode),
    };

    // What is armed: everything of ours the OS is holding, by id.
    final Map<int, String> pendingFingerprints = {};
    try {
      final List<PendingNotificationRequest> pending =
          await _plugin.pendingNotificationRequests();
      for (final PendingNotificationRequest request in pending) {
        final Map<String, dynamic>? payload = _decode(request.payload);
        if (payload == null || payload['type'] != payloadType) continue;
        if (request.id == testNotificationId) continue;
        pendingFingerprints[request.id] =
            (payload['fingerprint'] ?? '').toString();
      }
    } catch (e) {
      // A list that cannot be read is treated as empty: every wanted alarm
      // is armed again, which replaces whatever was there under the same id.
      debugPrint('TaskReminder: pending list unreadable — $e');
    }

    final TaskReminderPlan plan = TaskReminderPlan.diff(
      wanted: {
        for (final MapEntry<int, _Planned> e in wanted.entries)
          e.key: e.value.fingerprint,
      },
      pending: pendingFingerprints,
      rearmAll: !_rearmed,
    );
    _rearmed = true;

    // Down: alarms for tasks that are finished, gone, or no longer want one.
    for (final int id in plan.toCancel) {
      try {
        await _plugin.cancel(id);
      } catch (e) {
        debugPrint('TaskReminder: could not cancel $id — $e');
      }
    }

    if (plan.toSchedule.isEmpty) return;
    await _ensureChannel();

    // Up: whatever is missing or has changed since it was armed.
    for (final int id in plan.toSchedule) {
      final _Planned planned = wanted[id]!;
      try {
        await _schedule(id, planned, mode);
      } on PlatformException catch (e) {
        // The switch was flipped between the check above and this call, or
        // the check answered for a different Android than the one running.
        // A rough alarm is still an alarm; refused outright it would be none.
        if (e.code == 'exact_alarms_not_permitted' &&
            mode != AndroidScheduleMode.inexactAllowWhileIdle) {
          try {
            await _schedule(
                id, planned, AndroidScheduleMode.inexactAllowWhileIdle);
          } catch (e) {
            debugPrint(
                'TaskReminder: could not arm "${planned.task.title}" — $e');
          }
        } else {
          debugPrint('TaskReminder: could not arm "${planned.task.title}" — $e');
        }
      } catch (e) {
        debugPrint('TaskReminder: could not arm "${planned.task.title}" — $e');
      }
    }

    if (kDebugMode) {
      try {
        final int count = (await _plugin.pendingNotificationRequests()).length;
        debugPrint('TaskReminder: ${plan.toSchedule.length} armed, '
            '${plan.toCancel.length} cancelled, $count pending');
      } catch (_) {}
    }
  }

  /// The alarms that should be held right now: for every open task, its
  /// reminder and its follow-up, whichever are still ahead — a little ahead,
  /// since the plugin refuses a moment already gone and one a few seconds
  /// off would be gone by the time the call lands — soonest first, and no
  /// more than [maxArmed] of them. iOS holds sixty-four pending notifications
  /// per app and drops the rest without a word; the window rolls forward on
  /// later passes as the nearest ones fire.
  static List<TaskAlarm> select(List<TaskModel> tasks, {required DateTime now}) {
    final DateTime horizon = now.add(_leadTime);
    final List<TaskAlarm> picked = [];
    for (final TaskModel task in tasks) {
      if (task.done || task.id.isEmpty) continue;
      final DateTime? reminder = task.reminderAt;
      if (reminder != null && reminder.isAfter(horizon)) {
        picked.add(TaskAlarm(task, reminder, TaskAlarmKind.reminder));
      }
      final DateTime? followUp = task.followUpAt;
      if (followUp != null && followUp.isAfter(horizon)) {
        picked.add(TaskAlarm(task, followUp, TaskAlarmKind.followUp));
      }
    }
    picked.sort((a, b) => a.at.compareTo(b.at));
    if (picked.length > maxArmed) picked.length = maxArmed;
    return picked;
  }

  static Future<void> _schedule(
    int id,
    _Planned plan,
    AndroidScheduleMode mode,
  ) async {
    plan.mode = mode;
    final String body = TaskReminderText.bodyFor(plan.alarm, bengali: plan.bengali);

    await _plugin.zonedSchedule(
      id,
      plan.task.title,
      body,
      // As an instant in UTC rather than a wall-clock time in a named zone:
      // the plugin wants a zoned date, and the moment is already known to the
      // millisecond. Naming the device's zone would mean shipping the whole
      // zone database for one lookup, and a one-shot alarm gains nothing from
      // it — only a repeating rule across a clock change would, and none is
      // asked for here.
      tz.TZDateTime.from(plan.at, tz.UTC),
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: '@drawable/ic_notification',
          color: const Color(AppConstant.notificationAccent),
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
          styleInformation:
              BigTextStyleInformation(body, contentTitle: plan.task.title),
        ),
        // The default interruption level: "time sensitive" needs an
        // entitlement this app does not carry, and iOS would only quietly
        // downgrade it.
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: mode,
      payload: jsonEncode({
        'type': payloadType,
        'taskId': plan.task.id,
        'kind': plan.alarm.kind.name,
        'fingerprint': plan.fingerprint,
      }),
    );
    debugPrint('TaskReminder: armed ${plan.alarm.kind.name} for '
        '"${plan.task.title}" at ${plan.at}');
  }

  /// Exact where the device allows it, and the nearest the OS will give
  /// otherwise. Android 12 grants the exact-alarm permission on install; 13
  /// and 14 hand it to the user as a switch, off by default on 14 — and a
  /// reminder that arrives within the following few minutes is still a
  /// reminder, where a refused schedule call is none at all.
  static Future<AndroidScheduleMode> _scheduleMode() async {
    if (await exactAlarmsAllowed()) return AndroidScheduleMode.exactAllowWhileIdle;
    return AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// A reminder ten seconds from now, through the very path the real ones
  /// take — channel, permission, receivers and all. What a member presses to
  /// find out whether this phone will ring before trusting a six o'clock one.
  static Future<void> sendTest({required bool bengali}) async {
    if (kIsWeb) return;
    await _ensureChannel();
    final DateTime at = DateTime.now().add(const Duration(seconds: 10));
    final String title = bengali ? 'MessBook রিমাইন্ডার কাজ করছে' : 'MessBook reminders work';
    final String body = bengali
        ? 'আপনার কাজের রিমাইন্ডার এভাবেই আসবে।'
        : 'This is how a task reminder will arrive.';
    await _plugin.zonedSchedule(
      testNotificationId,
      title,
      body,
      tz.TZDateTime.from(at, tz.UTC),
      NotificationDetails(
        android: AndroidNotificationDetails(
          channel.id,
          channel.name,
          channelDescription: channel.description,
          icon: '@drawable/ic_notification',
          color: const Color(AppConstant.notificationAccent),
          importance: Importance.high,
          priority: Priority.high,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      androidScheduleMode: await _scheduleMode(),
      payload: jsonEncode({'type': payloadType, 'taskId': ''}),
    );
  }

  /// Fixed, and outside the range task ids land in: a second test replaces
  /// the first rather than stacking beside it, and [reconcile] never mistakes
  /// it for a task's alarm — see the guard there.
  static const int testNotificationId = 20251;

  /// Whether the OS will show this app's notifications at all — the switch a
  /// reminder cannot work around. True on the web and anywhere the answer
  /// cannot be read, so nothing nags without cause.
  static Future<bool> notificationsEnabled() async {
    if (kIsWeb) return true;
    try {
      if (Platform.isAndroid) {
        final bool? enabled = await _plugin
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.areNotificationsEnabled();
        return enabled ?? true;
      }
      if (Platform.isIOS) {
        // iOS accepts the schedule call and then quietly drops the
        // notification when the permission was refused, so it has to be
        // asked here rather than found out at the hour.
        final NotificationsEnabledOptions? options = await _plugin
            .resolvePlatformSpecificImplementation<
                IOSFlutterLocalNotificationsPlugin>()
            ?.checkPermissions();
        return options?.isEnabled ?? true;
      }
      return true;
    } catch (e) {
      debugPrint('TaskReminder: notification check failed — $e');
      return true;
    }
  }

  /// Whether this device will fire reminders at the exact minute. Always true
  /// away from Android, which has no such switch.
  static Future<bool> exactAlarmsAllowed() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? allowed = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.canScheduleExactNotifications();
      return allowed ?? true;
    } catch (e) {
      debugPrint('TaskReminder: exact-alarm check failed — $e');
      return true;
    }
  }

  /// Opens the system page where the exact-alarm switch lives, and answers
  /// with where the switch ended up. Android only; a no-op elsewhere.
  static Future<bool> requestExactAlarms() async {
    if (kIsWeb || !Platform.isAndroid) return true;
    try {
      final bool? granted = await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestExactAlarmsPermission();
      return granted ?? await exactAlarmsAllowed();
    } catch (e) {
      debugPrint('TaskReminder: exact-alarm request failed — $e');
      return false;
    }
  }

  /// Takes every task reminder off the device. Signing out lands here, and so
  /// does an account being removed: the alarms belong to the list, and the
  /// list has left the phone. Nothing else the app has pending is touched.
  static Future<void> cancelAll() {
    if (kIsWeb) return Future<void>.value();
    return _queue = _queue.then((_) async {
      try {
        final List<PendingNotificationRequest> pending =
            await _plugin.pendingNotificationRequests();
        for (final PendingNotificationRequest request in pending) {
          final Map<String, dynamic>? payload = _decode(request.payload);
          if (payload == null || payload['type'] != payloadType) continue;
          await _plugin.cancel(request.id);
        }
        debugPrint('TaskReminder: all reminders cancelled');
      } catch (e) {
        debugPrint('TaskReminder: cancelAll failed — $e');
      }
    });
  }

  static Future<void> _ensureChannel() async {
    if (_channelReady) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(channel);
      _channelReady = true;
    } catch (e) {
      debugPrint('TaskReminder: channel not created — $e');
    }
  }

  static Map<String, dynamic>? _decode(String? payload) {
    if (payload == null || payload.isEmpty) return null;
    try {
      final Object? decoded = jsonDecode(payload);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return null;
  }
}

/// The two things a task can ring for.
enum TaskAlarmKind {
  /// Ahead of the hour: "this is coming".
  reminder,

  /// After the hour, while the task is still open: "this has gone by and is
  /// not ticked".
  followUp,
}

/// One alarm a task asks for — which task, which of its two moments, and
/// when that moment falls.
class TaskAlarm {
  final TaskModel task;
  final DateTime at;
  final TaskAlarmKind kind;

  const TaskAlarm(this.task, this.at, this.kind);

  /// The id it is filed with the OS under — one per kind per task.
  int get id => kind == TaskAlarmKind.reminder
      ? task.notificationId
      : task.followUpNotificationId;
}

/// One alarm as it should stand: what it is for, and the language the text
/// will be in.
class _Planned {
  final TaskAlarm alarm;
  final bool bengali;

  /// How the OS is asked to hold it. Rewritten if the exact call is refused
  /// and the alarm goes in rough instead, so the fingerprint says what was
  /// actually armed.
  AndroidScheduleMode mode;

  _Planned({required this.alarm, required this.bengali, required this.mode});

  TaskModel get task => alarm.task;

  DateTime get at => alarm.at;

  /// Everything the notification is built from, and how it was armed.
  /// Unchanged fingerprint, unchanged alarm.
  String get fingerprint =>
      '${TaskReminderText.fingerprintFor(alarm, bengali: bengali)}|${mode.name}';
}

/// The words on a task reminder.
///
/// Written out here rather than through GetX translations, the way the meal
/// reminder's summary is: the text is composed when the alarm is armed and
/// has to stay the same string whatever the app does afterwards, and a test
/// can read it without a `GetMaterialApp` in the way.
class TaskReminderText {
  const TaskReminderText._();

  /// What the notification says under the title, for either kind of alarm.
  static String bodyFor(TaskAlarm alarm, {required bool bengali}) =>
      alarm.kind == TaskAlarmKind.reminder
          ? body(alarm.task, bengali: bengali)
          : followUpBody(alarm.task, bengali: bengali);

  /// The second word, after the hour has gone: that it is still open, and
  /// when it was meant to be done — `Still not done — was due 5:00 PM`.
  static String followUpBody(TaskModel task, {required bool bengali}) {
    final DateTime? due = task.dueAt;
    final DateTime? at = task.followUpAt;
    if (due == null || at == null) {
      return bengali ? 'এখনও হয়নি' : 'Still not done';
    }
    final String when = _whenBetween(due, at, bengali: bengali);
    return bengali ? 'এখনও হয়নি — $when-এ করার কথা ছিল' : 'Still not done — was due $when';
  }

  /// What the notification says under the title: how far off the task is and
  /// when it falls, as read at the moment the reminder fires.
  static String body(TaskModel task, {required bool bengali}) {
    final int minutes = task.reminderMinutes ?? 0;
    final String when = _when(task, bengali: bengali);

    if (!task.hasTime) {
      // A task with a day and no hour: the reminder is the morning of, or
      // the evening before, and "in 15 minutes" would mean nothing. Which
      // day it names is read off where the alarm falls, not off the offset.
      final DateTime? due = task.reminderAnchor;
      final DateTime? at = task.reminderAt;
      final bool sameDay =
          due != null && at != null && TaskModel.keyOf(due) == TaskModel.keyOf(at);
      if (!sameDay) {
        return bengali ? 'আগামীকাল করার কথা' : 'Due tomorrow';
      }
      return bengali ? 'আজ করার কথা' : 'Due today';
    }

    String lead;
    if (minutes <= 0) {
      lead = bengali ? 'এখনই' : 'Due now';
    } else if (minutes < 60) {
      lead = bengali ? '$minutes মিনিট পর' : 'In $minutes minutes';
    } else if (minutes < 1440) {
      final int hours = minutes ~/ 60;
      lead = bengali
          ? '$hours ঘণ্টা পর'
          : 'In $hours ${hours == 1 ? 'hour' : 'hours'}';
    } else {
      lead = bengali ? 'আগামীকাল' : 'Tomorrow';
    }
    return '$lead — $when';
  }

  /// `5:00 PM` for a task due the day the reminder fires, `Sat 6 Sep, 5:00 PM`
  /// — or `শনি 6 সেপ্ট, 5:00 PM` — for any other day. The digits stay
  /// Western, as they do everywhere else the app prints a clock; the day and
  /// month names follow the language, since `DateFormat` only knows English
  /// here.
  static String _when(TaskModel task, {required bool bengali}) {
    final DateTime? due = task.reminderAnchor;
    final DateTime? at = task.reminderAt;
    if (due == null || at == null) return '';
    return _whenBetween(due, at, bengali: bengali);
  }

  /// [due] as read from [at]: the clock alone on the same day, the day as
  /// well on any other.
  static String _whenBetween(DateTime due, DateTime at, {required bool bengali}) {
    final String time = DateFormat('h:mm a').format(due);
    if (TaskModel.keyOf(due) == TaskModel.keyOf(at)) return time;
    if (bengali) {
      return '${_bnWeekdays[due.weekday - 1]} ${due.day} '
          '${_bnMonths[due.month - 1]}, $time';
    }
    return '${DateFormat('EEE d MMM').format(due)}, $time';
  }

  static const List<String> _bnWeekdays = [
    'সোম', 'মঙ্গল', 'বুধ', 'বৃহঃ', 'শুক্র', 'শনি', 'রবি',
  ];

  static const List<String> _bnMonths = [
    'জানু', 'ফেব্রু', 'মার্চ', 'এপ্রিল', 'মে', 'জুন',
    'জুলাই', 'আগস্ট', 'সেপ্ট', 'অক্টো', 'নভে', 'ডিসে',
  ];

  /// What an armed alarm is compared against on the next reconcile. The
  /// moment, the words, and the language — anything that would change what
  /// the OS shows.
  static String fingerprintFor(TaskAlarm alarm, {required bool bengali}) =>
      '${alarm.kind.name}|${alarm.at.millisecondsSinceEpoch}|'
      '${bengali ? 'bn' : 'en'}|${alarm.task.title}|'
      '${bodyFor(alarm, bengali: bengali)}';

  /// The reminder's fingerprint — see [fingerprintFor].
  static String fingerprint(TaskModel task, DateTime at, {required bool bengali}) =>
      fingerprintFor(TaskAlarm(task, at, TaskAlarmKind.reminder), bengali: bengali);
}

/// What one pass over the alarms has to do — the pure heart of
/// [TaskReminderService.reconcile], kept apart from the plugin so it can be
/// tested on its own.
class TaskReminderPlan {
  /// Alarms the OS holds that are no longer wanted.
  final Set<int> toCancel;

  /// Alarms wanted that the OS does not hold, or holds in an older shape.
  final Set<int> toSchedule;

  const TaskReminderPlan({required this.toCancel, required this.toSchedule});

  /// [wanted] and [pending] are both id → fingerprint. An id in both with the
  /// same fingerprint is left exactly as it is: arming it again would reset
  /// the OS's own bookkeeping for nothing. With [rearmAll], every wanted id
  /// is armed whatever the pending list says — for a record that cannot be
  /// trusted to match the alarms, see `TaskReminderService._rearmed` — while
  /// cancellations still follow the record.
  static TaskReminderPlan diff({
    required Map<int, String> wanted,
    required Map<int, String> pending,
    bool rearmAll = false,
  }) {
    final Set<int> toCancel = {
      for (final int id in pending.keys)
        if (!wanted.containsKey(id)) id,
    };
    final Set<int> toSchedule = {
      for (final MapEntry<int, String> e in wanted.entries)
        if (rearmAll || pending[e.key] != e.value) e.key,
    };
    return TaskReminderPlan(toCancel: toCancel, toSchedule: toSchedule);
  }
}
