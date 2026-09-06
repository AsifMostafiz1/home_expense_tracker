import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/info_prompt_sheet.dart';
import '../../../utils/app_ui.dart';
import '../controller/task_controller.dart';
import '../model/task_digest.dart';
import '../model/task_model.dart';
import '../view/task_screen.dart';
import 'task_editor_sheet.dart';
import 'task_labels.dart';
import 'task_progress_ring.dart';
import 'task_tile.dart';

/// What became of the ask — the home screen queues its prompts on this.
enum TodayTasksPromptResult {
  /// Nothing open on today's list and nothing left over, the sheet was up a
  /// moment ago, or the list could not be read.
  notNeeded,

  /// The sheet was shown, and closed one way or another.
  shown,
}

/// The morning's list, raised on the home screen.
///
/// The one ask in the launch queue that is the member's own: what they wrote
/// down for today, what is left from before, and how far through it they
/// are. Everything on it is live — a task ticked here is ticked everywhere,
/// and the ring moves as it happens — so the sheet is a place to work from,
/// not a poster to dismiss.
///
/// It comes up every time the app is opened while something on today's list
/// is still open, or something is left over from before — the owner's
/// wish, and the point of writing a task down: to be reminded of it until
/// it is done. Closing it puts it away for this visit only. It stays quiet
/// on a day with nothing open and nothing overdue — a finished day is not
/// worth an interruption — and on a return from the background a few
/// minutes later, which is the same visit continuing rather than a new one;
/// see [resumeAfter].
class TodayTasksPrompt {
  const TodayTasksPrompt._();

  static bool _showing = false;

  /// When the sheet last went up, or null for not yet this process.
  static DateTime? _lastShownAt;

  /// How long the app has to have been away before coming back counts as a
  /// fresh visit worth the sheet again. Answering a message and coming
  /// straight back is not one; a phone left in a pocket for the afternoon
  /// is. Midnight passing counts on its own — see `HomePrompts.runOnResume`.
  static const Duration resumeAfter = Duration(minutes: 10);

  /// Shows the sheet when today has something left on it. Safe to call on
  /// every launch and every resume — it decides for itself whether there is
  /// anything to do. [onResume] asks it to hold off while the last showing
  /// is still recent: a launch always counts as a new visit, a resume only
  /// after [resumeAfter].
  static Future<TodayTasksPromptResult> maybeShow({bool onResume = false}) async {
    if (_showing) return TodayTasksPromptResult.notNeeded;

    if (onResume) {
      final DateTime? last = _lastShownAt;
      if (last != null && DateTime.now().difference(last) < resumeAfter) {
        return TodayTasksPromptResult.notNeeded;
      }
    }

    final TaskController? controller = _controller();
    if (controller == null) return TodayTasksPromptResult.notNeeded;

    // The listener is already running from the home screen; this waits on
    // its first answer rather than firing a read of its own. Bounded, since
    // it holds up every prompt queued behind it. Firestore answers from its
    // local copy with no connection, so an offline morning still gets its
    // list.
    await controller.tasksReady.timeout(_wait, onTimeout: () {});

    // A read that never landed leaves every pile looking empty.
    if (!controller.hasLoaded) return TodayTasksPromptResult.notNeeded;
    if (controller.userPhone.isEmpty) return TodayTasksPromptResult.notNeeded;

    final TaskDigest digest = controller.digest;
    if (!digest.hasSomethingForToday) return TodayTasksPromptResult.notNeeded;

    if (Get.context == null) return TodayTasksPromptResult.notNeeded;

    _lastShownAt = DateTime.now();
    _showing = true;
    try {
      final bool? open = await showInfoPromptSheet<bool>(
        GetBuilder<TaskController>(
          builder: (c) => _TodayTasksSheet(controller: c),
        ),
      );
      if (open == true) {
        Get.to(() => const TaskScreen());
      }
      return TodayTasksPromptResult.shown;
    } finally {
      _showing = false;
    }
  }

  static const Duration _wait = Duration(seconds: 6);

  /// The controller is registered lazily, so the first caller builds it —
  /// which also starts the live listener for the session.
  static TaskController? _controller() {
    try {
      return Get.find<TaskController>();
    } catch (e) {
      debugPrint('Tasks: controller unavailable — $e');
      return null;
    }
  }
}

class _TodayTasksSheet extends StatefulWidget {
  final TaskController controller;

  const _TodayTasksSheet({required this.controller});

  @override
  State<_TodayTasksSheet> createState() => _TodayTasksSheetState();
}

class _TodayTasksSheetState extends State<_TodayTasksSheet> {
  /// The rows as they stood when the sheet opened, in that order. Ticking one
  /// must not reshuffle the list under the finger, so the order is fixed here
  /// and only each row's state is read live.
  late final List<String> _order = _initialOrder();

  List<String> _initialOrder() {
    final TaskDigest digest = widget.controller.digest;
    final List<TaskModel> rows = [
      // Left over from earlier days first — the longest owed at the top.
      ...digest.overdueEarlier,
      // Then the day itself, open before done.
      ...digest.todayOpenList,
      ...digest.todayDoneList,
    ];
    return rows.map((task) => task.id).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final TaskController c = widget.controller;
    final TaskDigest digest = c.digest;
    final Color primary = Theme.of(context).colorScheme.primary;

    final Map<String, TaskModel> byId = {
      for (final TaskModel task in c.tasks) task.id: task,
    };
    final List<TaskModel> rows = [
      for (final String id in _order)
        if (byId[id] != null) byId[id]!,
    ];

    final bool allDone = digest.allDoneToday && digest.overdueBeforeToday == 0;
    final MaterialColor ringTone = allDone ? Colors.green : Colors.deepPurple;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.82,
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppUi.hairline(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _header(context, digest, allDone: allDone, tone: ringTone),
            const SizedBox(height: 16),
            if (rows.isEmpty)
              _emptyLine(context)
            else
              Flexible(
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).cardColor,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: AppUi.hairline(context)),
                  ),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 6),
                    itemCount: rows.length,
                    separatorBuilder: (_, __) => Padding(
                      padding: const EdgeInsets.only(left: 44, right: 8),
                      child: Divider(height: 1, color: AppUi.hairline(context)),
                    ),
                    itemBuilder: (context, index) {
                      final TaskModel task = rows[index];
                      return TaskTile(
                        task: task,
                        compact: true,
                        now: digest.now,
                        onToggle: () => c.toggleDone(task),
                        onTap: () => showTaskEditorSheet(context, task: task),
                      );
                    },
                  ),
                ),
              ),
            const SizedBox(height: 18),
            CustomButton(
              text: 'open_my_tasks'.tr,
              height: 50,
              borderRadius: 14,
              onPressed: () => Navigator.of(context).pop(true),
            ),
            const SizedBox(height: 2),
            Row(
              children: [
                Expanded(
                  child: TextButton.icon(
                    onPressed: () async {
                      // The sheet gives way to the editor; the list is a tap
                      // away if they want it back.
                      closeOverlayRoute();
                      await Future.delayed(const Duration(milliseconds: 250));
                      if (Get.context != null) {
                        showTaskEditorSheet(Get.context!);
                      }
                    },
                    icon: Icon(Icons.add_rounded, size: 18, color: primary),
                    label: Text('add_task'.tr,
                        style: TextStyle(
                            color: primary, fontWeight: FontWeight.w600)),
                  ),
                ),
                Expanded(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(
                      'later'.tr,
                      style: TextStyle(color: AppUi.muted(context)),
                    ),
                  ),
                ),
              ],
            ),
            if (digest.overdueBeforeToday > 0 && digest.todayTotal > 0) ...[
              const SizedBox(height: 2),
              Center(
                child: Text(
                  'overdue_from_earlier'
                      .trParams({'count': '${digest.overdueBeforeToday}'}),
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppUi.accent(context, Colors.red),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// The day, how far through it is, and the ring that says so.
  Widget _header(
    BuildContext context,
    TaskDigest digest, {
    required bool allDone,
    required MaterialColor tone,
  }) {
    final DateTime now = digest.now;
    final String weekday =
        TaskLabels.fullWeekday(now);
    final String dateLine = '$weekday, ${now.day} ${AppUi.monthLabel(now)}';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'todays_tasks'.tr,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppUi.body(context),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                dateLine,
                style: TextStyle(fontSize: 13, color: AppUi.muted(context)),
              ),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                child: allDone
                    ? _pill(
                        context,
                        key: const ValueKey('done'),
                        tone: Colors.green,
                        icon: Icons.check_circle_rounded,
                        text: 'tasks_all_done'.tr,
                      )
                    : Text(
                        key: const ValueKey('progress'),
                        digest.todayTotal == 0
                            ? 'tasks_overdue_count'
                                .trParams({'count': '${digest.overdueBeforeToday}'})
                            : 'tasks_progress'.trParams({
                                'done': '${digest.todayDone}',
                                'total': '${digest.todayTotal}',
                              }),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppUi.body(context),
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 14),
        TaskProgressRing(
          value: digest.todayProgress,
          size: 64,
          stroke: 6,
          track: AppUi.hairline(context),
          arc: AppUi.accent(context, tone),
          child: allDone
              ? Icon(Icons.check_rounded,
                  size: 24, color: AppUi.accent(context, Colors.green))
              : Text(
                  '${digest.todayDone}/${digest.todayTotal}',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: AppUi.body(context),
                  ),
                ),
        ),
      ],
    );
  }

  Widget _pill(
    BuildContext context, {
    required Key key,
    required MaterialColor tone,
    required IconData icon,
    required String text,
  }) {
    final Color fg = AppUi.accent(context, tone);
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppUi.tint(context, tone),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  /// Only reachable if every row on the list was deleted while the sheet sat
  /// open — the sheet is not raised for an empty day.
  Widget _emptyLine(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          'tasks_none_today'.tr,
          style: TextStyle(fontSize: 13, color: AppUi.muted(context)),
        ),
      ),
    );
  }
}
