import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/hiding_fab.dart';
import '../../../utils/app_ui.dart';
import '../controller/task_controller.dart';
import '../model/task_digest.dart';
import '../model/task_model.dart';
import '../widgets/task_editor_sheet.dart';
import '../widgets/task_labels.dart';
import '../widgets/task_progress_ring.dart';
import '../widgets/task_skeleton.dart';
import '../widgets/task_tile.dart';

/// A member's own list, whole.
///
/// The day at the top — how far through it they are — and under it
/// everything open, sorted into what is late, what is today, what is
/// tomorrow, what is further off and what has no day at all. A second view
/// holds what is finished. Nothing here is shared with the house.
///
/// [highlightTaskId] is the task a tapped reminder was about: the list
/// scrolls to it and lights it up for a moment, so the eye lands on the one
/// thing the tap was for.
class TaskScreen extends StatefulWidget {
  final String? highlightTaskId;

  const TaskScreen({super.key, this.highlightTaskId});

  @override
  State<TaskScreen> createState() => _TaskScreenState();
}

class _TaskScreenState extends State<TaskScreen> {
  /// The row the reminder pointed at, while it is still lit.
  String? _highlight;

  /// Set once the list has scrolled to that row — done once, not on every
  /// rebuild the stream causes.
  bool _scrolledToHighlight = false;

  final Map<String, GlobalKey> _rowKeys = {};

  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _highlight = widget.highlightTaskId;
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  GlobalKey _keyFor(String id) => _rowKeys.putIfAbsent(id, () => GlobalKey());

  /// Brings the row a reminder was about into view.
  ///
  /// The list builds only what is on screen, so a row further down has no
  /// element yet and nothing to scroll to. The page is walked a viewport at
  /// a time until the row is built or the end is reached, and the highlight
  /// starts its fade only once the row is actually in front of the reader.
  void _scrollToHighlight(TaskController c) {
    final String? id = _highlight;
    if (id == null || _scrolledToHighlight || c.isLoading) return;
    _scrolledToHighlight = true;

    if (!c.tasks.any((task) => task.id == id)) {
      // Finished and cleared, or deleted, before the tap: the list itself is
      // still the right place to land.
      _highlight = null;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => _seek(id, 0));
  }

  void _seek(String id, int attempt) {
    if (!mounted) return;
    final BuildContext? target = _rowKeys[id]?.currentContext;
    if (target != null) {
      Scrollable.ensureVisible(
        target,
        alignment: 0.3,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      _fadeHighlight();
      return;
    }

    if (!_scroll.hasClients || attempt > 40) {
      _fadeHighlight();
      return;
    }
    final ScrollPosition position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent) {
      _fadeHighlight();
      return;
    }
    position.jumpTo(
      (position.pixels + position.viewportDimension)
          .clamp(0.0, position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _seek(id, attempt + 1));
  }

  /// Lit long enough to be seen, then an ordinary row again.
  void _fadeHighlight() {
    Future.delayed(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _highlight = null);
    });
  }

  /// Keys for rows that have left the list are let go of, so a long-lived
  /// screen does not hold one for every task ever shown on it.
  void _pruneKeys(TaskController c) {
    if (_rowKeys.length <= c.tasks.length) return;
    final Set<String> live = c.tasks.map((task) => task.id).toSet();
    _rowKeys.removeWhere((id, _) => !live.contains(id));
  }

  @override
  Widget build(BuildContext context) {
    return HidingFab(
      icon: Icons.add_rounded,
      tooltip: 'add_task'.tr,
      onPressed: () => showTaskEditorSheet(context),
      builder: (context, fab) => GetBuilder<TaskController>(
        builder: (c) {
          _pruneKeys(c);
          _scrollToHighlight(c);
          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            appBar: CustomAppBar(
              title: 'my_tasks'.tr,
              actions: [_menu(context, c), const SizedBox(width: 6)],
            ),
            floatingActionButton: fab,
            body: RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: c.refreshTasks,
              child: _body(context, c),
            ),
          );
        },
      ),
    );
  }

  Widget _menu(BuildContext context, TaskController c) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert_rounded, color: AppUi.body(context)),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      onSelected: (value) {
        switch (value) {
          case 'test':
            c.sendTestReminder();
            break;
          case 'clear':
            _confirmClearCompleted(context, c);
            break;
        }
      },
      itemBuilder: (_) => [
        if (!kIsWeb)
          PopupMenuItem<String>(
            value: 'test',
            child: Row(
              children: [
                Icon(Icons.notifications_active_outlined,
                    size: 19, color: AppUi.muted(context)),
                const SizedBox(width: 12),
                Text('test_reminder'.tr),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'clear',
          enabled: c.digest.completed.isNotEmpty,
          child: Row(
            children: [
              Icon(Icons.delete_sweep_outlined,
                  size: 19, color: Colors.red.shade400),
              const SizedBox(width: 12),
              Text('clear_completed'.tr,
                  style: TextStyle(color: Colors.red.shade400)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _body(BuildContext context, TaskController c) {
    if (c.isLoading) return const TaskSkeleton();

    if (c.errorMessage.isNotEmpty && c.tasks.isEmpty) {
      return _errorState(context, c);
    }

    if (c.tasks.isEmpty) return _firstRunState(context);

    final TaskDigest digest = c.digest;

    return ListView(
      controller: _scroll,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
      children: [
        _summaryCard(context, c, digest),
        const SizedBox(height: 16),
        _viewToggle(context, c, digest),
        if (!kIsWeb && (!c.notificationsEnabled || c.showExactAlarmHint)) ...[
          const SizedBox(height: 14),
          _healthStrip(context, c),
        ],
        const SizedBox(height: 20),
        if (c.showCompleted)
          ..._completedView(context, c, digest)
        else
          ..._openView(context, c, digest),
      ],
    );
  }

  /// ----------------------------------------------------------------- header

  /// The day, as a figure: done over total, a ring, and whatever is worth
  /// saying beside it — what is late, what is next.
  Widget _summaryCard(
      BuildContext context, TaskController c, TaskDigest digest) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool allDone = digest.allDoneToday;
    final bool nothingToday = digest.todayTotal == 0;
    final DateTime now = digest.now;

    final List<Color> gradient = allDone
        ? [Colors.green.shade600, Colors.green.shade400]
        : [primary, primary.withOpacity(0.72)];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: gradient.first.withOpacity(0.30),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.today_rounded,
                        size: 15, color: Colors.white70),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${TaskLabels.fullWeekday(now)}, ${now.day} ${AppUi.monthLabel(now)}'
                            .toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                          color: Colors.white70,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (nothingToday)
                  Text(
                    'tasks_none_today'.tr,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.2,
                    ),
                  )
                else
                  Text(
                    '${digest.todayDone} / ${digest.todayTotal}',
                    style: const TextStyle(
                      fontSize: 34,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      height: 1.1,
                      letterSpacing: -0.5,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  nothingToday
                      ? _nextUpLine(digest)
                      : allDone
                          ? 'tasks_all_done'.tr
                          : 'tasks_progress'.trParams({
                              'done': '${digest.todayDone}',
                              'total': '${digest.todayTotal}',
                            }),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70,
                    height: 1.35,
                  ),
                ),
                if (digest.overdueBeforeToday > 0 || digest.openCount > 0) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (digest.overdueBeforeToday > 0)
                        _pill(
                          Icons.history_rounded,
                          'tasks_overdue_count'.trParams(
                              {'count': '${digest.overdueBeforeToday}'}),
                        ),
                      _pill(
                        Icons.radio_button_unchecked_rounded,
                        'open_tasks_count'
                            .trParams({'count': '${digest.openCount}'}),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          TaskProgressRing(
            value: digest.todayProgress,
            size: 78,
            stroke: 7,
            track: Colors.white.withOpacity(0.22),
            arc: Colors.white,
            child: allDone
                ? const Icon(Icons.check_rounded, size: 30, color: Colors.white)
                : nothingToday
                    ? const Icon(Icons.wb_sunny_outlined,
                        size: 26, color: Colors.white)
                    : Text(
                        '${digest.todayDone}/${digest.todayTotal}',
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  /// What is coming, when today holds nothing — so an empty day never reads
  /// as a dead end.
  String _nextUpLine(TaskDigest digest) {
    final List<TaskModel> ahead = [...digest.tomorrow, ...digest.later];
    if (ahead.isEmpty) return 'tasks_none_today_hint'.tr;
    final TaskModel next = ahead.first;
    return 'next_up'.trParams({
      'title': next.title,
      'when': TaskLabels.due(next, now: digest.now),
    });
  }

  Widget _pill(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// ------------------------------------------------------------ view toggle

  Widget _viewToggle(
      BuildContext context, TaskController c, TaskDigest digest) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppUi.neutralSurface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Row(
        children: [
          _viewOption(
            context,
            selected: !c.showCompleted,
            icon: Icons.radio_button_unchecked_rounded,
            label: 'view_open'.tr,
            count: digest.openCount,
            onTap: () => c.setShowCompleted(false),
          ),
          _viewOption(
            context,
            selected: c.showCompleted,
            icon: Icons.task_alt_rounded,
            label: 'view_done'.tr,
            count: digest.completed.length,
            onTap: () => c.setShowCompleted(true),
          ),
        ],
      ),
    );
  }

  Widget _viewOption(
    BuildContext context, {
    required bool selected,
    required IconData icon,
    required String label,
    required int count,
    required VoidCallback onTap,
  }) {
    const MaterialColor tone = Colors.deepPurple;
    final Color fg =
        selected ? AppUi.accent(context, tone) : AppUi.muted(context);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppUi.tint(context, tone) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? tone.withOpacity(0.5) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: fg,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: fg.withOpacity(0.8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ----------------------------------------------------------- health strip

  /// The two things that can keep a reminder from ringing, said out loud with
  /// the one tap that fixes each: notifications turned off for the app, and
  /// exact alarms refused. Neither is a dialog; both sit where the list is.
  Widget _healthStrip(BuildContext context, TaskController c) {
    final bool blocked = !c.notificationsEnabled;
    final MaterialColor tone = blocked ? Colors.red : Colors.orange;
    final Color fg = AppUi.accent(context, tone);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
      decoration: BoxDecoration(
        color: AppUi.tint(context, tone),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: tone.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            blocked
                ? Icons.notifications_off_rounded
                : Icons.timer_off_outlined,
            size: 18,
            color: fg,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  blocked
                      ? 'notifications_off_hint'.tr
                      : 'exact_alarms_hint'.tr,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: fg,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 34),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: blocked ? openAppSettings : c.requestExactAlarms,
                    child: Text(
                      blocked ? 'open_settings'.tr : 'allow_exact_alarms'.tr,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (!blocked)
            IconButton(
              tooltip: 'close'.tr,
              onPressed: c.dismissExactAlarmHint,
              icon: Icon(Icons.close_rounded, size: 18, color: fg),
            ),
        ],
      ),
    );
  }

  /// -------------------------------------------------------------- open view

  List<Widget> _openView(
      BuildContext context, TaskController c, TaskDigest digest) {
    final List<TaskModel> overdue = digest.overdueEarlier;

    if (digest.openCount == 0) {
      return [
        _inlineEmpty(
          context,
          icon: Icons.celebration_rounded,
          tone: Colors.green,
          title: 'all_caught_up'.tr,
          hint: 'all_caught_up_hint'.tr,
        ),
      ];
    }

    return [
      if (overdue.isNotEmpty)
        ..._section(
          context,
          c,
          digest,
          label: 'section_overdue'.tr,
          tasks: overdue,
          tone: Colors.red,
          quickMove: true,
        ),
      if (digest.today.isNotEmpty)
        ..._section(
          context,
          c,
          digest,
          label: 'today'.tr,
          tasks: digest.today,
        ),
      if (digest.tomorrow.isNotEmpty)
        ..._section(
          context,
          c,
          digest,
          label: 'tomorrow'.tr,
          tasks: digest.tomorrow,
        ),
      for (final MapEntry<DateTime, List<TaskModel>> day in digest.laterByDay)
        ..._section(
          context,
          c,
          digest,
          label: TaskLabels.day(day.key, now: digest.now),
          tasks: day.value,
        ),
      if (digest.someday.isNotEmpty)
        ..._section(
          context,
          c,
          digest,
          label: 'section_someday'.tr,
          tasks: digest.someday,
        ),
    ];
  }

  /// --------------------------------------------------------- completed view

  List<Widget> _completedView(
      BuildContext context, TaskController c, TaskDigest digest) {
    if (digest.completed.isEmpty) {
      return [
        _inlineEmpty(
          context,
          icon: Icons.check_circle_outline_rounded,
          tone: Colors.teal,
          title: 'no_completed_tasks'.tr,
          hint: 'no_completed_tasks_hint'.tr,
        ),
      ];
    }

    // Grouped by the day they were finished, newest day first.
    final Map<String, List<TaskModel>> byDay = {};
    for (final TaskModel task in digest.completed) {
      final DateTime? at = task.doneAt;
      final String key = task.doneDate.isNotEmpty
          ? task.doneDate
          : at != null
              ? TaskModel.keyOf(at)
              : TaskModel.keyOf(digest.now);
      byDay.putIfAbsent(key, () => []).add(task);
    }
    final List<String> keys = byDay.keys.toList()
      ..sort((a, b) => b.compareTo(a));

    return [
      for (final String key in keys)
        ..._section(
          context,
          c,
          digest,
          label: AppUi.dayLabel(DateTime.parse(key)),
          tasks: byDay[key]!,
        ),
    ];
  }

  /// --------------------------------------------------------------- sections

  List<Widget> _section(
    BuildContext context,
    TaskController c,
    TaskDigest digest, {
    required String label,
    required List<TaskModel> tasks,
    MaterialColor? tone,
    bool quickMove = false,
  }) {
    final Color labelColor =
        tone == null ? Colors.grey.shade500 : AppUi.accent(context, tone);

    return [
      Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.1,
                  color: labelColor,
                ),
              ),
            ),
            Text(
              '${tasks.length}',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.bold,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
      for (final TaskModel task in tasks)
        Padding(
          key: _keyFor(task.id),
          padding: const EdgeInsets.only(bottom: 10),
          child: _row(context, c, digest, task, quickMove: quickMove),
        ),
      const SizedBox(height: 12),
    ];
  }

  /// One task, swipeable: right to tick, left to delete. Both are on the
  /// row's own key, so a row that moves sections as the stream redraws never
  /// carries another's gesture with it.
  Widget _row(
    BuildContext context,
    TaskController c,
    TaskDigest digest,
    TaskModel task, {
    required bool quickMove,
  }) {
    return Dismissible(
      key: ValueKey<String>('dismiss_${task.id}'),
      background: _swipeBackground(
        context,
        alignment: Alignment.centerLeft,
        tone: task.done ? Colors.amber : Colors.green,
        icon: task.done ? Icons.undo_rounded : Icons.check_rounded,
      ),
      secondaryBackground: _swipeBackground(
        context,
        alignment: Alignment.centerRight,
        tone: Colors.red,
        icon: Icons.delete_outline_rounded,
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          HapticFeedback.lightImpact();
          c.toggleDone(task);
          // The row stays and animates; the stream moves it.
          return false;
        }
        _confirmDelete(context, c, task);
        return false;
      },
      child: Column(
        children: [
          TaskTile(
            task: task,
            now: digest.now,
            highlighted: task.id == _highlight,
            onToggle: () => c.toggleDone(task),
            onTap: () => showTaskEditorSheet(context, task: task),
            onLongPress: () => _showRowMenu(context, c, task),
          ),
          if (quickMove) _quickMoveRow(context, c, task),
        ],
      ),
    );
  }

  /// One tap to bring a late task forward — no dialog, no editor.
  Widget _quickMoveRow(BuildContext context, TaskController c, TaskModel task) {
    final Color primary = Theme.of(context).colorScheme.primary;
    return Align(
      alignment: Alignment.centerRight,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, right: 4),
        child: TextButton.icon(
          style: TextButton.styleFrom(
            foregroundColor: primary,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => c.moveTo(task, TaskModel.dayOf(DateTime.now())),
          icon: const Icon(Icons.arrow_forward_rounded, size: 15),
          label: Text(
            'move_to_today'.tr,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
  }

  Widget _swipeBackground(
    BuildContext context, {
    required Alignment alignment,
    required MaterialColor tone,
    required IconData icon,
  }) {
    return Container(
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 22),
      decoration: BoxDecoration(
        color: AppUi.tint(context, tone),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Icon(icon, color: AppUi.accent(context, tone)),
    );
  }

  void _showRowMenu(BuildContext context, TaskController c, TaskModel task) {
    final DateTime today = TaskModel.dayOf(DateTime.now());
    final DateTime tomorrow = DateTime(today.year, today.month, today.day + 1);

    // Scroll-controlled, and capped like every other sheet in the app: five
    // rows and a two-line title outgrow the default sheet on a small phone,
    // and the last row — delete — is the one that must never be cut off.
    Get.bottomSheet(
      Container(
        constraints: AppUi.sheetConstraints(context),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    width: 44,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppUi.muted(context).withOpacity(0.35),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text(
                    task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppUi.body(context),
                    ),
                  ),
                ),
                Divider(height: 1, color: AppUi.hairline(context)),
                ListTile(
                  leading: Icon(
                    task.done
                        ? Icons.undo_rounded
                        : Icons.check_circle_outline_rounded,
                    color: AppUi.muted(context),
                  ),
                  title: Text(task.done ? 'mark_not_done'.tr : 'mark_done'.tr),
                  onTap: () {
                    closeOverlayRoute();
                    c.toggleDone(task);
                  },
                ),
                ListTile(
                  leading:
                      Icon(Icons.edit_outlined, color: AppUi.muted(context)),
                  title: Text('edit_task'.tr),
                  onTap: () {
                    closeOverlayRoute();
                    showTaskEditorSheet(context, task: task);
                  },
                ),
                if (!task.done) ...[
                  if (!task.isOn(today))
                    ListTile(
                      leading: Icon(Icons.today_rounded,
                          color: AppUi.muted(context)),
                      title: Text('move_to_today'.tr),
                      onTap: () {
                        closeOverlayRoute();
                        c.moveTo(task, today);
                      },
                    ),
                  if (!task.isOn(tomorrow))
                    ListTile(
                      leading: Icon(Icons.event_rounded,
                          color: AppUi.muted(context)),
                      title: Text('move_to_tomorrow'.tr),
                      onTap: () {
                        closeOverlayRoute();
                        c.moveTo(task, tomorrow);
                      },
                    ),
                ],
                ListTile(
                  leading: Icon(Icons.delete_outline_rounded,
                      color: Colors.red.shade400),
                  title: Text('delete_task'.tr,
                      style: TextStyle(color: Colors.red.shade400)),
                  onTap: () {
                    closeOverlayRoute();
                    _confirmDelete(context, c, task);
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  void _confirmDelete(BuildContext context, TaskController c, TaskModel task) {
    showConfirmDialog(
      title: 'delete_task'.tr,
      message: task.repeat.repeats && !task.done
          ? 'confirm_delete_repeating_task'.tr
          : 'confirm_delete_task'.tr,
      detail: task.title,
      confirmText: 'delete'.tr,
      onConfirm: () => c.deleteTask(task),
    );
  }

  void _confirmClearCompleted(BuildContext context, TaskController c) {
    showConfirmDialog(
      title: 'clear_completed'.tr,
      message: 'confirm_clear_completed'.tr,
      confirmText: 'delete'.tr,
      onConfirm: c.clearCompleted,
    );
  }

  /// ------------------------------------------------------------------ states

  /// An empty pile inside a list that still has a header — a short card,
  /// not a whole-screen state.
  Widget _inlineEmpty(
    BuildContext context, {
    required IconData icon,
    required MaterialColor tone,
    required String title,
    required String hint,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppUi.tint(context, tone),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 32, color: AppUi.accent(context, tone)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: AppUi.body(context).withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            hint,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: AppUi.muted(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _firstRunState(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: AppUi.tint(context, Colors.indigo),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.task_alt_rounded,
                      size: 44, color: AppUi.accent(context, Colors.indigo)),
                ),
                const SizedBox(height: 22),
                Text(
                  'no_tasks_yet'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context).withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'no_tasks_hint'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppUi.muted(context),
                  ),
                ),
                const SizedBox(height: 24),
                CustomButton(
                  text: 'add_first_task'.tr,
                  height: 50,
                  borderRadius: 14,
                  onPressed: () => showTaskEditorSheet(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _errorState(BuildContext context, TaskController c) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: AppUi.tint(context, Colors.red),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.cloud_off_rounded,
                      size: 44, color: AppUi.accent(context, Colors.red)),
                ),
                const SizedBox(height: 22),
                Text(
                  'failed_load_tasks'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context).withOpacity(0.75),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'check_connection'.tr,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppUi.muted(context),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton.icon(
                  onPressed: c.refreshTasks,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: Text('retry'.tr),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
