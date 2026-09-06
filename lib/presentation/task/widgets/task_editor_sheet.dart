import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../utils/app_ui.dart';
import '../controller/task_controller.dart';
import '../model/task_model.dart';
import 'task_labels.dart';

/// Writes one task — new, or [task] again.
///
/// The title is the only thing asked for. Everything under it is there to be
/// added when it helps and skipped when it does not: a day, an hour on that
/// day, a reminder measured from it, how it comes round again, how much it
/// matters. The sheet keeps those in the order a person thinks of them, and
/// each row only appears once the row above has given it something to mean —
/// no reminder chips without a day, no time without a day.
///
/// [initialDay] is where a new task's day starts; null leaves it undated.
Future<void> showTaskEditorSheet(
  BuildContext context, {
  TaskModel? task,
  DateTime? initialDay,
}) {
  return Get.bottomSheet(
    _TaskEditorSheet(task: task, initialDay: initialDay),
    isScrollControlled: true,
  );
}

class _TaskEditorSheet extends StatefulWidget {
  final TaskModel? task;
  final DateTime? initialDay;

  const _TaskEditorSheet({this.task, this.initialDay});

  @override
  State<_TaskEditorSheet> createState() => _TaskEditorSheetState();
}

class _TaskEditorSheetState extends State<_TaskEditorSheet> {
  late final TextEditingController _title =
      TextEditingController(text: widget.task?.title ?? '');
  late final TextEditingController _note =
      TextEditingController(text: widget.task?.note ?? '');

  late DateTime? _day = widget.task != null
      ? widget.task!.day
      : (widget.initialDay == null
          ? null
          : TaskModel.dayOf(widget.initialDay!));

  late TimeOfDay? _time =
      (widget.task?.hasTime ?? false) ? widget.task!.time : null;

  late int? _reminder = widget.task?.reminderMinutes;

  /// Half an hour for a new task; whatever an existing one carries, including
  /// none. Only saved once there is an hour for it to follow.
  late int? _followUp = widget.task != null
      ? widget.task!.followUpMinutes
      : TaskModel.defaultFollowUpMinutes;

  late TaskPriority _priority = widget.task?.priority ?? TaskPriority.normal;
  late TaskRepeat _repeat = widget.task?.repeat ?? TaskRepeat.none;

  String? _titleError;

  bool get _isEditing => widget.task != null;

  TaskController get _controller => Get.find<TaskController>();

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    super.dispose();
  }

  /// ------------------------------------------------------------ the draft

  /// The task as the form has it right now — what the preview line reads
  /// from, and what is saved.
  TaskModel get _draft {
    final DateTime? d = _day;
    final TimeOfDay? t = d == null ? null : _time;
    return TaskModel(
      id: widget.task?.id ?? '',
      title: _title.text,
      note: _note.text,
      date: d == null ? '' : TaskModel.keyOf(d),
      hasTime: t != null,
      timeHour: t?.hour ?? 0,
      timeMinute: t?.minute ?? 0,
      reminderMinutes: d == null ? null : _reminder,
      followUpMinutes: t == null ? null : _followUp,
      priority: _priority,
      repeat: d == null ? TaskRepeat.none : _repeat,
    );
  }

  DateTime get _today => TaskModel.dayOf(DateTime.now());

  DateTime get _tomorrow =>
      DateTime(_today.year, _today.month, _today.day + 1);

  bool _sameDay(DateTime? a, DateTime b) =>
      a != null && a.year == b.year && a.month == b.month && a.day == b.day;

  /// The reminder offsets that mean something for the day and hour as set.
  List<int> get _reminderOptions => _time == null
      ? TaskModel.allDayReminderOffsets
      : TaskModel.timedReminderOffsets;

  void _setDay(DateTime? day) {
    setState(() {
      _day = day;
      if (day == null) {
        // Nothing to hang an hour, a reminder or a schedule on.
        _time = null;
      }
    });
  }

  void _setTime(TimeOfDay? time) {
    setState(() {
      final bool hadTime = _time != null;
      _time = time;
      if (time == null) {
        // The timed offsets are meaningless against a day with no hour; the
        // wish for a reminder is kept, moved to the morning of the day.
        if (_reminder != null && !TaskModel.allDayReminderOffsets.contains(_reminder)) {
          _reminder = 0;
        }
      } else if (!hadTime && !kIsWeb) {
        // An hour was just set. A day-shaped offset does not fit it, and
        // somebody who bothers to set an hour usually wants to be told: start
        // from what they picked last time, or the hour itself. Not on the
        // web, where the chips that could take it off again are not shown.
        if (_reminder == null || !TaskModel.timedReminderOffsets.contains(_reminder)) {
          final int? last = _controller.lastReminderOffset;
          _reminder = last != null && TaskModel.timedReminderOffsets.contains(last)
              ? last
              : 0;
        }
      }
    });
  }

  Future<void> _pickDate() async {
    final DateTime start = _day ?? _today;
    // A year back, so a task can be dated to when it was actually due; three
    // years on, for the rent-and-renewals kind of planning.
    final DateTime first = DateTime(_today.year - 1, _today.month, _today.day);
    final DateTime last = DateTime(_today.year + 3, _today.month, _today.day);

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: start.isBefore(first)
          ? first
          : (start.isAfter(last) ? last : start),
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) _setDay(TaskModel.dayOf(picked));
  }

  Future<void> _pickTime() async {
    // The next whole hour, so the picker opens somewhere ahead of now.
    final DateTime now = DateTime.now();
    final TimeOfDay initial = _time ??
        TimeOfDay(hour: (now.hour + 1) % 24, minute: 0);
    final TimeOfDay? picked =
        await showTimePicker(context: context, initialTime: initial);
    if (picked != null) _setTime(picked);
  }

  Future<void> _save() async {
    // The keyboard's Done key is not disabled while the button spins the way
    // the button is; a second press mid-save must not write a second task.
    if (_controller.isSaving) return;

    final String title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _titleError = 'task_title_required'.tr);
      return;
    }

    final bool saved = await _controller.saveTask(
      existing: widget.task,
      title: title,
      note: _note.text,
      day: _day,
      time: _day == null ? null : _time,
      reminderMinutes: _day == null ? null : _reminder,
      followUpMinutes: _day == null || _time == null ? null : _followUp,
      priority: _priority,
      repeat: _repeat,
    );
    if (saved) closeOverlayRoute();
  }

  void _confirmDelete() {
    final TaskModel task = widget.task!;
    showConfirmDialog(
      title: 'delete_task'.tr,
      message: task.repeat.repeats
          ? 'confirm_delete_repeating_task'.tr
          : 'confirm_delete_task'.tr,
      detail: task.title,
      confirmText: 'delete'.tr,
      onConfirm: () {
        closeOverlayRoute();
        _controller.deleteTask(task);
      },
    );
  }

  /// ------------------------------------------------------------------ build

  @override
  Widget build(BuildContext context) {
    // No keyboard inset here. Get.bottomSheet already pads its own route by
    // `viewInsets.bottom`, so adding it again lifts the sheet a second
    // keyboard-height off the bottom — the trap the transaction sheet notes.
    return Container(
      constraints: BoxConstraints(
        // Taller than the app's usual cap: this form has more rows than most,
        // and the keyboard takes the bottom of what is left.
        maxHeight: MediaQuery.of(context).size.height * 0.88,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 44,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: AppUi.muted(context).withOpacity(0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _isEditing ? 'edit_task'.tr : 'new_task'.tr,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                if (_isEditing)
                  IconButton(
                    tooltip: 'delete_task'.tr,
                    onPressed: _confirmDelete,
                    icon: Icon(Icons.delete_outline_rounded,
                        color: Colors.red.shade400),
                  ),
              ],
            ),
            if (!_isEditing) ...[
              const SizedBox(height: 4),
              Text(
                'task_editor_hint'.tr,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: AppUi.muted(context),
                ),
              ),
            ],
            const SizedBox(height: 18),
            CustomTextField(
              controller: _title,
              hintText: 'task_title_hint'.tr,
              labelText: 'task_title'.tr,
              prefixIcon: Icons.task_alt_rounded,
              errorText: _titleError,
              maxLength: 120,
              autofocus: !_isEditing,
              textCapitalization: TextCapitalization.sentences,
              // The fastest capture there is: open, type, press Done.
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
              onChanged: (_) {
                if (_titleError != null) setState(() => _titleError = null);
              },
            ),
            const SizedBox(height: 18),
            _label(context, 'when_label'.tr),
            const SizedBox(height: 10),
            _dayChips(context),
            const SizedBox(height: 10),
            _dateTimeRow(context),
            if (_day != null) ...[
              const SizedBox(height: 18),
              _reminderSection(context),
              if (_time != null && !kIsWeb) ...[
                const SizedBox(height: 18),
                _followUpSection(context),
              ],
              const SizedBox(height: 18),
              _label(context, 'repeat'.tr),
              const SizedBox(height: 10),
              _repeatChips(context),
            ],
            const SizedBox(height: 18),
            _label(context, 'priority'.tr),
            const SizedBox(height: 10),
            _priorityToggle(context),
            const SizedBox(height: 18),
            CustomTextField(
              controller: _note,
              labelText: 'task_note_optional'.tr,
              hintText: 'task_note_hint'.tr,
              prefixIcon: Icons.notes_rounded,
              maxLines: 2,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
            ),
            const SizedBox(height: 22),
            GetBuilder<TaskController>(
              builder: (c) => CustomButton(
                text: _isEditing ? 'save_changes'.tr : 'add_task'.tr,
                height: 52,
                borderRadius: 14,
                isLoading: c.isSaving,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color: Theme.of(context).textTheme.titleSmall?.color?.withOpacity(0.8),
      ),
    );
  }

  /// ---------------------------------------------------------------- the day

  /// Today, tomorrow, no date — the three answers that cover most tasks,
  /// each one tap. Anything else goes through the calendar below.
  Widget _dayChips(BuildContext context) {
    final bool isToday = _sameDay(_day, _today);
    final bool isTomorrow = _sameDay(_day, _tomorrow);
    final bool other = _day != null && !isToday && !isTomorrow;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _chip(context, 'today'.tr, isToday, () => _setDay(_today),
            icon: Icons.today_rounded),
        _chip(context, 'tomorrow'.tr, isTomorrow, () => _setDay(_tomorrow),
            icon: Icons.event_rounded),
        _chip(
          context,
          other ? TaskLabels.day(_day!) : 'pick_date'.tr,
          other,
          _pickDate,
          icon: Icons.calendar_month_rounded,
        ),
        _chip(context, 'no_date'.tr, _day == null, () => _setDay(null),
            icon: Icons.event_busy_rounded, tone: Colors.blueGrey),
      ],
    );
  }

  /// The calendar, and the clock beside it. The clock is a slot to fill — it
  /// reads "add time" until it holds one, and clears with a tap on its cross.
  Widget _dateTimeRow(BuildContext context) {
    final bool enabled = _day != null;
    final Color muted = AppUi.muted(context);

    return Row(
      children: [
        Expanded(
          child: _pickerField(
            context,
            icon: Icons.calendar_today_rounded,
            label: _day == null ? 'no_date'.tr : TaskLabels.day(_day!),
            enabled: enabled,
            onTap: _pickDate,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _pickerField(
            context,
            icon: _time == null
                ? Icons.add_alarm_rounded
                : Icons.access_time_rounded,
            label: _time == null
                ? 'add_time'.tr
                : _time!.format(context),
            enabled: enabled,
            muted: _time == null,
            onTap: enabled ? _pickTime : _pickDate,
            trailing: _time == null
                ? null
                : InkWell(
                    onTap: () => _setTime(null),
                    borderRadius: BorderRadius.circular(10),
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(Icons.close_rounded, size: 16, color: muted),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _pickerField(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool enabled = true,
    bool muted = false,
    Widget? trailing,
  }) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final Color text = !enabled || muted
        ? AppUi.muted(context)
        : AppUi.body(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: AppUi.neutralSurface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppUi.hairline(context)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: enabled ? primary : AppUi.muted(context)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: text,
                ),
              ),
            ),
            if (trailing != null) trailing,
          ],
        ),
      ),
    );
  }

  /// ----------------------------------------------------------- the reminder

  Widget _reminderSection(BuildContext context) {
    final TaskModel draft = _draft;
    final DateTime now = DateTime.now();
    final DateTime? at = draft.reminderAt;
    final bool passed = at != null && !at.isAfter(now);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            _label(context, 'remind_me'.tr),
            const Spacer(),
            if (kIsWeb)
              Text(
                'reminders_need_phone'.tr,
                style: TextStyle(fontSize: 11.5, color: AppUi.muted(context)),
              ),
          ],
        ),
        const SizedBox(height: 10),
        // One line, scrolled sideways: eight chips do not fit a phone and a
        // wrap of them would push the form down two rows. Not on the web at
        // all — a browser tab holds no alarms, and chips that did nothing
        // would be a promise the app cannot keep there.
        if (!kIsWeb)
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip(context, 'no_reminder'.tr, _reminder == null,
                  () => setState(() => _reminder = null),
                  icon: Icons.notifications_off_outlined,
                  tone: Colors.blueGrey),
              for (final int minutes in _reminderOptions) ...[
                const SizedBox(width: 8),
                _chip(
                  context,
                  TaskLabels.reminder(minutes, hasTime: _time != null),
                  _reminder == minutes,
                  () => setState(() => _reminder = minutes),
                  // A moment already gone is shown but not offered.
                  disabled: _momentPassed(minutes, now),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _reminder == null || at == null
              ? const SizedBox(height: 16, key: ValueKey('none'))
              : Row(
                  key: ValueKey('$at$passed'),
                  children: [
                    Icon(
                      passed
                          ? Icons.warning_amber_rounded
                          : Icons.notifications_active_outlined,
                      size: 13,
                      color: passed
                          ? AppUi.accent(context, Colors.orange)
                          : AppUi.muted(context),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        passed
                            ? 'reminder_time_passed'.tr
                            : 'reminder_will_ring'.trParams({
                                'when': _whenLabel(context, at),
                              }),
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: passed ? FontWeight.w600 : FontWeight.w500,
                          color: passed
                              ? AppUi.accent(context, Colors.orange)
                              : AppUi.muted(context),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  /// ----------------------------------------------------------- the follow-up

  /// The second word, for a task with an hour: how long after it to ask
  /// again if the box is still empty. Off is a choice, not the default — the
  /// owner asked for half an hour to be the starting point.
  Widget _followUpSection(BuildContext context) {
    final TaskModel draft = _draft;
    final DateTime? at = draft.followUpAt;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(context, 'follow_up_label'.tr),
        const SizedBox(height: 10),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _chip(context, 'follow_up_off'.tr, _followUp == null,
                  () => setState(() => _followUp = null),
                  icon: Icons.notifications_paused_outlined,
                  tone: Colors.blueGrey),
              for (final int minutes in TaskModel.followUpOffsets) ...[
                const SizedBox(width: 8),
                _chip(
                  context,
                  TaskLabels.followUp(minutes),
                  _followUp == minutes,
                  () => setState(() => _followUp = minutes),
                  tone: Colors.orange,
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _followUp == null || at == null
              ? const SizedBox(height: 16, key: ValueKey('off'))
              : Row(
                  key: ValueKey('follow$at'),
                  children: [
                    Icon(Icons.update_rounded,
                        size: 13, color: AppUi.muted(context)),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'follow_up_preview'.trParams({
                          'time': TimeOfDay.fromDateTime(at).format(context),
                        }),
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          fontWeight: FontWeight.w500,
                          color: AppUi.muted(context),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }

  bool _momentPassed(int minutes, DateTime now) {
    final DateTime? anchor = _draft.reminderAnchor;
    if (anchor == null) return false;
    return !anchor.subtract(Duration(minutes: minutes)).isAfter(now);
  }

  /// `today, 4:00 PM` / `tomorrow, 8:00 PM` — inside "Rings …", so the day
  /// word reads as part of the sentence.
  String _whenLabel(BuildContext context, DateTime at) {
    final String day = TaskLabels.inSentence(TaskLabels.day(at));
    final String time = TimeOfDay.fromDateTime(at).format(context);
    return '$day, $time';
  }

  /// ------------------------------------------------------------- the repeat

  Widget _repeatChips(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final TaskRepeat repeat in TaskRepeat.values)
          _chip(
            context,
            TaskLabels.repeat(repeat),
            _repeat == repeat,
            () => setState(() => _repeat = repeat),
            icon: repeat.repeats ? Icons.repeat_rounded : null,
            tone: Colors.teal,
          ),
      ],
    );
  }

  /// ----------------------------------------------------------- the priority

  /// Three steps as one control — the transaction sheet's toggle, with each
  /// step drawn in the colour its tasks carry on the list.
  Widget _priorityToggle(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppUi.neutralSurface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Row(
        children: [
          for (final TaskPriority priority in [
            TaskPriority.low,
            TaskPriority.normal,
            TaskPriority.high,
          ])
            _priorityOption(context, priority),
        ],
      ),
    );
  }

  Widget _priorityOption(BuildContext context, TaskPriority priority) {
    final bool selected = _priority == priority;
    final MaterialColor color = TaskLabels.priorityColor(context, priority);
    final IconData icon;
    switch (priority) {
      case TaskPriority.low:
        icon = Icons.keyboard_arrow_down_rounded;
        break;
      case TaskPriority.normal:
        icon = Icons.remove_rounded;
        break;
      case TaskPriority.high:
        icon = Icons.keyboard_double_arrow_up_rounded;
        break;
    }

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _priority = priority),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
          decoration: BoxDecoration(
            color: selected ? AppUi.tint(context, color) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? color.withOpacity(0.5) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 17,
                  color: selected
                      ? AppUi.accent(context, color)
                      : AppUi.muted(context)),
              const SizedBox(width: 4),
              // Flexible, because a third of a narrow phone is not much and
              // the Bangla word for "normal" is longer than the English one.
              Flexible(
                child: Text(
                  TaskLabels.priority(priority),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected
                        ? AppUi.accent(context, color)
                        : AppUi.muted(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ------------------------------------------------------------------ chips

  /// The house's selectable pill — the subcategory chip's shape.
  Widget _chip(
    BuildContext context,
    String label,
    bool selected,
    VoidCallback onTap, {
    IconData? icon,
    MaterialColor tone = Colors.deepPurple,
    bool disabled = false,
  }) {
    final Color accent = AppUi.accent(context, tone);
    final Color fg = disabled
        ? AppUi.muted(context).withOpacity(0.5)
        : selected
            ? accent
            : AppUi.body(context);

    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: selected && !disabled
              ? AppUi.tint(context, tone)
              : AppUi.neutralSurface(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected && !disabled
                ? accent.withOpacity(0.6)
                : disabled
                    ? Colors.transparent
                    : AppUi.hairline(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: selected && !disabled ? accent : AppUi.muted(context)),
              const SizedBox(width: 6),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: fg,
                decoration: disabled ? TextDecoration.lineThrough : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
