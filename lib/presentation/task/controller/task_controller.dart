import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show TimeOfDay;
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../common/widgets/custom_snackbar.dart';
import '../../../services/connectivity_service.dart';
import '../../../services/notification_permission_service.dart';
import '../../../services/task_reminder_service.dart';
import '../../../utils/app_constant.dart';
import '../../../utils/app_enums.dart';
import '../model/task_digest.dart';
import '../model/task_model.dart';
import '../repository/task_repository.dart';
import '../widgets/task_labels.dart';

/// A member's own to-do list — what they have to do, when, and whether they
/// want to be told about it beforehand.
///
/// Private by construction, the way the personal ledger is: every read is
/// filtered by the signed-in phone and every write carries it. Nothing here
/// touches the house.
///
/// The list is a stream rather than a fetch, and held whole. Two things read
/// off it every time it moves: the piles the screens show — see [digest] —
/// and the alarms the OS is holding, which are brought into line with the
/// list on every snapshot rather than touched when a task is saved. See
/// `TaskReminderService` for why that is the simpler rule.
class TaskController extends GetxController implements GetxService {
  final TaskRepository repository;

  TaskController({required this.repository});

  bool isLoading = true;
  bool isSaving = false;
  String errorMessage = '';

  String userPhone = '';

  List<TaskModel> tasks = [];

  /// Whether the main list is showing what is finished rather than what is
  /// open — the screen's one switch.
  bool showCompleted = false;

  /// Whether this phone will ring reminders on the exact minute — see
  /// `TaskReminderService.exactAlarmsAllowed`. True until Android says
  /// otherwise, so nothing nags before the answer is in.
  bool exactAlarmsAllowed = true;

  /// Whether the OS will show this app's notifications at all. False is the
  /// one thing a reminder cannot get round, so the list says so out loud.
  bool notificationsEnabled = true;

  bool isSendingTest = false;

  /// Snapshots arrive in bursts — the local echo, then the server's, then a
  /// metadata-only one — and each would otherwise read the pending list.
  Timer? _reconcileDebounce;

  /// Ticks in flight, by task id. A second tap on the same ring before the
  /// local echo has redrawn the row would otherwise run the completion
  /// twice — and write two of tomorrow's task for a repeating one.
  final Set<String> _toggling = {};

  /// Once a minute, so a row due at two o'clock turns late at two o'clock
  /// while the screen sits open, rather than at the next snapshot.
  Timer? _minute;

  /// The last first-snapshot wait — what the home screen's prompt queue
  /// waits on instead of polling [isLoading].
  Completer<void>? _firstSnapshot;

  Future<void> get tasksReady => (_firstSnapshot ??= Completer<void>()).future;

  /// True once the list has arrived at least once. A read that never landed
  /// leaves every pile looking empty, and nothing should act on that.
  bool hasLoaded = false;

  StreamSubscription<List<TaskModel>>? _subscription;

  /// Fires at the next midnight, so an app left open overnight regroups its
  /// list on its own — see [_armMidnight].
  Timer? _midnight;

  /// The offset picked last time a timed task was given a reminder, or null
  /// for never — what the editor starts from.
  int? lastReminderOffset;

  /// Whether the "allow exact alarms" strip has been closed on this device.
  bool exactAlarmHintDismissed = false;

  TaskDigest? _digest;
  DateTime? _digestAt;

  /// How old a digest may be before a read rebuilds it: the piles only move
  /// on the minute, and a screen asks for this several times per build.
  static const Duration _digestLife = Duration(seconds: 30);

  /// The list sorted into today, overdue, upcoming and the rest.
  ///
  /// Recomputed when the list moves, when the day does — an app left open
  /// past midnight must not go on calling yesterday "today" — and once the
  /// last reading is old enough that a task may have fallen due since. Cached
  /// in between.
  TaskDigest get digest {
    final DateTime now = DateTime.now();
    final DateTime? at = _digestAt;
    final bool stale = at == null ||
        now.difference(at) > _digestLife ||
        TaskModel.keyOf(at) != TaskModel.keyOf(now);
    if (_digest == null || stale) {
      _digest = TaskDigest.of(tasks, now: now);
      _digestAt = now;
    }
    return _digest!;
  }

  /// The language the reminders are worded in — the one the app is showing.
  String get languageCode => Get.locale?.languageCode ?? 'en';

  bool get _isOffline =>
      Get.isRegistered<ConnectivityService>() &&
      Get.find<ConnectivityService>().isOffline;

  @override
  void onInit() {
    super.onInit();
    _start();
  }

  @override
  void onClose() {
    _subscription?.cancel();
    _midnight?.cancel();
    _minute?.cancel();
    _reconcileDebounce?.cancel();
    super.onClose();
  }

  Future<void> _start() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    userPhone = prefs.getString(AppConstant.keyUserPhone) ?? '';
    exactAlarmHintDismissed =
        prefs.getBool(AppConstant.keyExactAlarmHintDismissed) ?? false;

    if (userPhone.isEmpty) {
      isLoading = false;
      _completeFirstSnapshot();
      update();
      return;
    }

    lastReminderOffset =
        prefs.getInt(AppConstant.keyTaskLastReminder(userPhone));

    unawaited(_readExactAlarms());
    _armMidnight();
    _minute = Timer.periodic(const Duration(minutes: 1), (_) => refreshDigest());
    _watch();
  }

  /// Wakes the controller a moment after midnight to move the day along.
  /// Re-armed from its own callback, so it keeps going for as long as the
  /// controller lives. A second of grace, so the clock has surely turned.
  void _armMidnight() {
    _midnight?.cancel();
    final DateTime now = DateTime.now();
    final DateTime next = DateTime(now.year, now.month, now.day + 1, 0, 0, 1);
    _midnight = Timer(next.difference(now), () {
      refreshDigest();
      _armMidnight();
    });
  }

  Future<void> _rememberReminderOffset(int minutes) async {
    lastReminderOffset = minutes;
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setInt(AppConstant.keyTaskLastReminder(userPhone), minutes);
    } catch (e) {
      debugPrint('Tasks: could not remember the reminder offset — $e');
    }
  }

  /// Closes the exact-alarm strip for good on this device.
  Future<void> dismissExactAlarmHint() async {
    exactAlarmHintDismissed = true;
    update();
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setBool(AppConstant.keyExactAlarmHintDismissed, true);
    } catch (e) {
      debugPrint('Tasks: could not remember the dismissed hint — $e');
    }
  }

  /// Whether the list should carry the strip that offers exact alarms: only
  /// on a phone that has refused them, only once a reminder exists to be
  /// late, and only until the strip has been closed.
  bool get showExactAlarmHint =>
      !exactAlarmsAllowed &&
      !exactAlarmHintDismissed &&
      digest.armed.isNotEmpty;

  void _watch() {
    _subscription?.cancel();
    _subscription = repository.watchTasks(userPhone).listen(
      (list) {
        tasks = list;
        _digest = null;
        isLoading = false;
        hasLoaded = true;
        errorMessage = '';
        _completeFirstSnapshot();
        update();
        _scheduleReconcile();
      },
      onError: (Object error) {
        debugPrint('Error listening to tasks: $error');
        isLoading = false;
        errorMessage = error.toString();
        _completeFirstSnapshot();
        update();
      },
    );
  }

  void _completeFirstSnapshot() {
    final Completer<void> completer = _firstSnapshot ??= Completer<void>();
    if (!completer.isCompleted) completer.complete();
  }

  /// Pull-to-refresh. The stream already keeps the list current, so this
  /// re-attaches it — which is what recovers a listener that fell over while
  /// the connection was gone — and gives the connectivity probe a nudge.
  Future<void> refreshTasks() async {
    _watch();
    unawaited(_readExactAlarms());
    if (Get.isRegistered<ConnectivityService>()) {
      unawaited(Get.find<ConnectivityService>().probe());
    }
  }

  /// The day may have turned while the app was away; the piles are re-read
  /// from the same list. Cheap, so the home screen calls it on every resume.
  void refreshDigest() {
    _digest = null;
    update();
  }

  void setShowCompleted(bool value) {
    if (showCompleted == value) return;
    showCompleted = value;
    update();
  }

  /// Coming back to an app that was left open: the day may have turned, the
  /// switches in the system settings may have been flipped, and another
  /// device may have moved things while this one was away — the stream
  /// covers the last, this covers the rest.
  void onResumed() {
    refreshDigest();
    unawaited(_readExactAlarms());
    _scheduleReconcile();
  }

  Future<void> _readExactAlarms() async {
    final bool allowed = await TaskReminderService.exactAlarmsAllowed();
    final bool enabled = await TaskReminderService.notificationsEnabled();
    if (allowed == exactAlarmsAllowed && enabled == notificationsEnabled) return;
    exactAlarmsAllowed = allowed;
    notificationsEnabled = enabled;
    update();
  }

  void _scheduleReconcile() {
    _reconcileDebounce?.cancel();
    _reconcileDebounce = Timer(const Duration(milliseconds: 300), () {
      unawaited(_reconcileReminders());
    });
  }

  /// Re-arms every reminder with the words of the language the app is now
  /// in. The wording is part of what an alarm is compared against, so the
  /// ordinary reconcile does the work; this only asks for one now.
  void rescheduleReminders() => _scheduleReconcile();

  /// A reminder ten seconds out, so the member can see one land on this very
  /// phone before trusting the real ones to.
  Future<void> sendTestReminder() async {
    if (isSendingTest) return;
    try {
      isSendingTest = true;
      update();
      await TaskReminderService.sendTest(bengali: languageCode == 'bn');
      CustomSnackbar.show(
          type: SnackbarType.success, message: 'test_reminder_sent'.tr);
    } catch (e) {
      debugPrint('Tasks: test reminder failed — $e');
      CustomSnackbar.show(
          type: SnackbarType.error, message: 'failed_test_reminder'.tr);
    } finally {
      isSendingTest = false;
      update();
    }
  }

  /// Opens the system switch for exact alarms and re-reads it on the way
  /// back — and re-arms every reminder, so the ones set while the switch was
  /// off move from "roughly then" to "then".
  Future<void> requestExactAlarms() async {
    exactAlarmsAllowed = await TaskReminderService.requestExactAlarms();
    update();
    // The mode is part of what an alarm is compared against, so the ordinary
    // reconcile re-arms every rough alarm as an exact one.
    if (exactAlarmsAllowed) await _reconcileReminders();
  }

  /// Only once the list has actually arrived: an empty list that is merely
  /// not loaded yet — or one whose listener failed — would read as "nothing
  /// wanted" and take down every alarm the phone holds.
  Future<void> _reconcileReminders() {
    if (!hasLoaded) return Future<void>.value();
    return TaskReminderService.reconcile(tasks, bengali: languageCode == 'bn');
  }

  /// Takes the account's controller down, if it has been built.
  ///
  /// The session is ending — sign-out, or an account removed from under it.
  /// Its listener has to be stopped *before* the alarms are cancelled: a
  /// snapshot landing after the cancel would arm them all over again. The
  /// registration itself stays, so the next account on this phone gets a
  /// fresh controller reading its own phone from preferences.
  static Future<void> shutDown() async {
    if (!Get.isRegistered<TaskController>() || Get.isPrepared<TaskController>()) {
      return;
    }
    try {
      await Get.delete<TaskController>(force: true);
    } catch (e) {
      debugPrint('Tasks: could not shut the controller down — $e');
    }
  }

  /// ------------------------------------------------------------------ writes

  /// Adds a task, or rewrites [existing] when one is passed.
  ///
  /// [day] null means no date; [time] null means no hour. A reminder is only
  /// kept when there is a day for it to be measured from — the editor hides
  /// the option otherwise, and this is the second line of defence.
  Future<bool> saveTask({
    TaskModel? existing,
    required String title,
    String note = '',
    DateTime? day,
    TimeOfDay? time,
    int? reminderMinutes,
    int? followUpMinutes,
    TaskPriority priority = TaskPriority.normal,
    TaskRepeat repeat = TaskRepeat.none,
  }) async {
    // One save at a time: a second submit while the first waits on the
    // server would write the same task twice.
    if (isSaving) return false;

    final String trimmed = title.trim();
    if (trimmed.isEmpty) {
      CustomSnackbar.show(type: SnackbarType.error, message: 'task_title_required'.tr);
      return false;
    }
    if (userPhone.isEmpty) {
      CustomSnackbar.show(type: SnackbarType.error, message: 'failed_save_task'.tr);
      return false;
    }

    final bool hasDate = day != null;
    final bool hasTime = hasDate && time != null;

    // Without a day there is nothing to remind against; without an hour only
    // the two day-shaped offsets mean anything. Anything else is coerced to
    // the nearer of them rather than dropped — the wish for a reminder stands.
    int? reminder = hasDate ? reminderMinutes : null;
    if (reminder != null &&
        !hasTime &&
        !TaskModel.allDayReminderOffsets.contains(reminder)) {
      reminder = reminder >= TaskModel.eveningBeforeOffset
          ? TaskModel.eveningBeforeOffset
          : 0;
    }
    // The follow-up is measured from the hour, so a task with no hour has
    // nothing for it to wait after.
    final int? followUp =
        hasTime && followUpMinutes != null && followUpMinutes > 0
            ? followUpMinutes
            : null;
    // A repeat needs a day to count from.
    final TaskRepeat effectiveRepeat = hasDate ? repeat : TaskRepeat.none;

    TaskModel task = TaskModel(
      id: existing?.id ?? '',
      ownerPhone: userPhone,
      title: trimmed,
      note: note.trim(),
      date: hasDate ? TaskModel.keyOf(day) : '',
      hasTime: hasTime,
      timeHour: hasTime ? time.hour : 0,
      timeMinute: hasTime ? time.minute : 0,
      reminderMinutes: reminder,
      followUpMinutes: followUp,
      priority: priority,
      repeat: effectiveRepeat,
      // The day of the month the schedule is set on — kept, because the
      // copies that follow may be clamped into shorter months and still have
      // to find their way back. An edit that moves a monthly task to another
      // day of the month is setting a new schedule.
      repeatDay: effectiveRepeat == TaskRepeat.monthly && hasDate
          ? (existing != null &&
                  existing.repeat == TaskRepeat.monthly &&
                  existing.date == TaskModel.keyOf(day) &&
                  existing.repeatDay > 0
              ? existing.repeatDay
              : day.day)
          : 0,
      done: existing?.done ?? false,
      doneAt: existing?.doneAt,
      doneDate: existing?.doneDate ?? '',
      spawnedFrom: existing?.spawnedFrom ?? '',
    );

    task = withLiveReminder(task, DateTime.now());

    try {
      isSaving = true;
      update();

      final bool offline = _isOffline;
      await repository.saveTask(task);
      if (hasTime && reminderMinutes != null) {
        unawaited(_rememberReminderOffset(reminderMinutes));
      }

      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline
            ? 'task_saved_offline'.tr
            : (existing == null ? 'task_added'.tr : 'task_saved'.tr),
      );

      // A reminder is only worth setting on a phone that will show it. Asked
      // after the save rather than before: the task is kept either way, and
      // the system dialog should land on the list, not on a half-filled form.
      if (task.reminderAt != null || task.followUpAt != null) {
        unawaited(NotificationPermissionService().ensurePermission());
      }
      return true;
    } catch (e) {
      debugPrint('Error saving task: $e');
      CustomSnackbar.show(type: SnackbarType.error, message: 'failed_save_task'.tr);
      return false;
    } finally {
      isSaving = false;
      update();
    }
  }

  /// A reminder for a moment already gone is not a reminder. Moved to the
  /// time itself while that is still ahead — somebody who asked for an hour's
  /// warning on a task forty minutes away still wants to be told — and dropped
  /// otherwise. Never written as it stands: the OS refuses a past alarm, and a
  /// bell on the row would promise something that cannot ring. Every path that
  /// writes a dated task goes through here — a save, a move, the follow-on
  /// copy of a finished repeating task.
  static TaskModel withLiveReminder(TaskModel task, DateTime now) {
    final DateTime? reminderAt = task.reminderAt;
    if (reminderAt == null || reminderAt.isAfter(now) || task.done) return task;
    final DateTime? anchor = task.reminderAnchor;
    if (anchor != null && anchor.isAfter(now) && task.hasTime) {
      return task.copyWith(reminderMinutes: 0);
    }
    return task.copyWith(clearReminder: true);
  }

  /// Ticks a task off, or un-ticks it.
  ///
  /// Finishing a repeating task writes the next occurrence in the same batch,
  /// dated to the next day it is due — see [TaskModel.nextOccurrence]. Opening
  /// it again takes that copy back out, so long as nobody has touched it: a
  /// mis-tap must not leave two of tomorrow's task standing, and an undo must
  /// not throw away a note somebody has since written on the copy.
  Future<void> toggleDone(TaskModel task) async {
    // A tick already on its way for this task: the second tap is the same
    // tap, not a request for a second completion.
    if (!_toggling.add(task.id)) return;

    final bool offline = _isOffline;

    try {
      if (!task.done) {
        final DateTime now = DateTime.now();
        final TaskModel? spawned = task.successor(now);
        final TaskModel? next =
            spawned == null ? null : withLiveReminder(spawned, now);
        await repository.complete(
          task,
          doneDate: TaskModel.keyOf(now),
          successor: next,
        );

        if (next != null) {
          CustomSnackbar.show(
            type: SnackbarType.success,
            message: 'task_done_next_on'.trParams({
              'date': _dayLabel(next.day!),
            }),
          );
        } else if (offline) {
          CustomSnackbar.show(type: SnackbarType.info, message: 'task_saved_offline'.tr);
        }
        return;
      }

      // The copy is only taken back out while it is exactly as the tick wrote
      // it. Edited, moved, or already finished, it has become the member's
      // own and stays.
      final TaskModel? spawned = tasks.firstWhereOrNull((t) =>
          t.spawnedFrom == task.id && !t.done && t.isUntouchedSince);
      await repository.reopen(task, successorId: spawned?.id);
    } catch (e) {
      debugPrint('Error toggling task: $e');
      CustomSnackbar.show(type: SnackbarType.error, message: 'failed_save_task'.tr);
    } finally {
      _toggling.remove(task.id);
    }
  }

  /// Moves an open task to [day], keeping its hour and its reminder offset —
  /// what "tomorrow" on an overdue task does.
  Future<void> moveTo(TaskModel task, DateTime day) async {
    try {
      await repository.saveTask(withLiveReminder(
        task.copyWith(date: TaskModel.keyOf(day)),
        DateTime.now(),
      ));
      CustomSnackbar.show(
        type: SnackbarType.success,
        message: 'task_moved_to'.trParams({'date': _dayLabel(day)}),
      );
    } catch (e) {
      debugPrint('Error moving task: $e');
      CustomSnackbar.show(type: SnackbarType.error, message: 'failed_save_task'.tr);
    }
  }

  /// Removes a task. The row leaves the list from the stream — Firestore
  /// reports its own local delete straight away, connection or not.
  Future<void> deleteTask(TaskModel task) async {
    final bool offline = _isOffline;
    try {
      await repository.deleteTask(task.id);
      CustomSnackbar.show(
        type: offline ? SnackbarType.info : SnackbarType.success,
        message: offline ? 'task_saved_offline'.tr : 'task_deleted'.tr,
      );
    } catch (e) {
      debugPrint('Error deleting task: $e');
      CustomSnackbar.show(type: SnackbarType.error, message: 'failed_delete_task'.tr);
    }
  }

  /// Clears the finished list in one go.
  Future<void> clearCompleted() async {
    final List<String> ids =
        digest.completed.map((task) => task.id).toList(growable: false);
    if (ids.isEmpty) return;
    try {
      await repository.deleteAll(ids);
      CustomSnackbar.show(
        type: SnackbarType.success,
        message: ids.length == 1
            ? 'completed_cleared_one'.tr
            : 'completed_cleared'.trParams({'count': '${ids.length}'}),
      );
    } catch (e) {
      debugPrint('Error clearing completed tasks: $e');
      CustomSnackbar.show(type: SnackbarType.error, message: 'failed_delete_task'.tr);
    }
  }

  /// `today`, `tomorrow`, or the date — for the snackbars above, where the
  /// word sits inside a sentence rather than at the head of a label.
  static String _dayLabel(DateTime day) {
    final DateTime today = TaskModel.dayOf(DateTime.now());
    final int diff = TaskModel.dayOf(day).difference(today).inDays;
    if (diff == 0) return TaskLabels.inSentence('today'.tr);
    if (diff == 1) return TaskLabels.inSentence('tomorrow'.tr);
    return '${day.day} ${_monthKeys[day.month - 1].tr}';
  }

  static const List<String> _monthKeys = [
    'mon_jan', 'mon_feb', 'mon_mar', 'mon_apr', 'mon_may', 'mon_jun',
    'mon_jul', 'mon_aug', 'mon_sep', 'mon_oct', 'mon_nov', 'mon_dec',
  ];
}
