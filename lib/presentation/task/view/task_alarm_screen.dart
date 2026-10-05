import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../services/task_reminder_service.dart';
import '../controller/task_controller.dart';
import '../model/task_model.dart';

/// A task alarm, ringing — what a tap on one, or its full-screen intent over
/// the lock screen, opens.
///
/// The sound is the notification's, not this screen's: it keeps going until
/// the notification is taken down, which every button here does. So there
/// is nothing to play or stop on this side, and the alarm rings the same
/// whether this screen ever opened or not.
///
/// [data] is the alarm's payload — see `TaskReminderService._alarmPayload`.
class TaskAlarmScreen extends StatefulWidget {
  final Map<String, dynamic> data;

  const TaskAlarmScreen({super.key, required this.data});

  /// Whether one is up, so a second tap on the same alarm does not stack a
  /// second screen on the first.
  static bool isOpen = false;

  @override
  State<TaskAlarmScreen> createState() => _TaskAlarmScreenState();
}

class _TaskAlarmScreenState extends State<TaskAlarmScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  late final Timer _clock;
  DateTime _now = DateTime.now();
  bool _busy = false;

  int? get _notificationId => int.tryParse('${widget.data['nid']}');

  String get _taskId => (widget.data['taskId'] ?? '').toString();

  /// The task as the list has it now — null for the test alarm, a task
  /// finished on another phone, or a list that has not arrived yet.
  TaskModel? get _task {
    if (_taskId.isEmpty || !Get.isRegistered<TaskController>()) return null;
    return Get.find<TaskController>()
        .tasks
        .firstWhereOrNull((t) => t.id == _taskId && !t.done);
  }

  @override
  void initState() {
    super.initState();
    TaskAlarmScreen.isOpen = true;
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    TaskAlarmScreen.isOpen = false;
    _clock.cancel();
    _pulse.dispose();
    // However the screen goes, the lock screen goes back to the lock.
    unawaited(TaskReminderService.releaseLockScreen());
    super.dispose();
  }

  Future<void> _finish(Future<void> Function()? then) async {
    if (_busy) return;
    setState(() => _busy = true);
    final int? id = _notificationId;
    if (id != null) await TaskReminderService.stopAlarm(id);
    try {
      await then?.call();
    } catch (e) {
      debugPrint('TaskAlarm: action failed — $e');
    }
    if (mounted) Get.back();
  }

  void _stop() => _finish(null);

  void _snooze() =>
      _finish(() => TaskReminderService.snooze(jsonEncode(widget.data)));

  void _markDone(TaskModel task) =>
      _finish(() => Get.find<TaskController>().toggleDone(task));

  @override
  Widget build(BuildContext context) {
    final String title = (widget.data['title'] ?? '').toString();
    final String body = (widget.data['body'] ?? '').toString();
    final TaskModel? task = _task;
    const Color bg = Color(0xFF0F1B2D);
    const Color accent = Color(0xFFFF8A3D);

    return PopScope(
      // Back is stop, the way it is on the clock's alarm: leaving the screen
      // with the phone still ringing would only send the member hunting for
      // the notification.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _stop();
      },
      child: Scaffold(
        backgroundColor: bg,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
            child: Column(
              children: [
                Text(
                  DateFormat('h:mm').format(_now),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 64,
                    fontWeight: FontWeight.w300,
                    height: 1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  DateFormat('a').format(_now),
                  style: const TextStyle(color: Colors.white70, fontSize: 16),
                ),
                const Spacer(),
                ScaleTransition(
                  scale: Tween<double>(begin: 0.9, end: 1.08).animate(
                      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
                  child: Container(
                    width: 124,
                    height: 124,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accent.withOpacity(0.16),
                      border: Border.all(color: accent.withOpacity(0.5), width: 2),
                    ),
                    child: const Icon(Icons.alarm_rounded,
                        size: 60, color: accent),
                  ),
                ),
                const SizedBox(height: 32),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                    height: 1.25,
                  ),
                ),
                if (body.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white70, fontSize: 15, height: 1.4),
                  ),
                ],
                const Spacer(),
                if (task != null) ...[
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : () => _markDone(task),
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: Text('alarm_mark_done'.tr),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: const BorderSide(color: Colors.white38),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        textStyle: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 58,
                        child: TextButton.icon(
                          onPressed: _busy ? null : _snooze,
                          icon: const Icon(Icons.snooze_rounded),
                          label: Text('alarm_snooze'.tr),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.white,
                            backgroundColor: Colors.white.withOpacity(0.1),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            textStyle: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: SizedBox(
                        height: 58,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _stop,
                          icon: const Icon(Icons.alarm_off_rounded),
                          label: Text('alarm_stop'.tr),
                          style: FilledButton.styleFrom(
                            backgroundColor: accent,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                            textStyle: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
