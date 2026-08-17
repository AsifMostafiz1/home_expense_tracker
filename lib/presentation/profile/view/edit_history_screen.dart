import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_snackbar.dart';
import '../../../common/widgets/profile_avatar.dart';
import '../../../utils/app_enums.dart';
import '../../../utils/app_ui.dart';
import '../../auth/model/user_model.dart';
import '../controller/profile_controller.dart';
import '../model/edit_log_model.dart';
import '../widgets/edit_history_skeleton.dart';

/// ---------------------------------------------------------------------------
/// Edit history.
///
/// A day-grouped timeline of every change an admin made on someone else's
/// behalf. The bar on top narrows it by period, member and kind of change;
/// the list below is pull-to-refresh, with a skeleton on first read and an
/// error state with retry when that read fails.
/// ---------------------------------------------------------------------------

/// Palette used to give every member a stable, recognisable accent color.
const List<MaterialColor> _memberColors = [
  Colors.amber,
  Colors.teal,
  Colors.indigo,
  Colors.pink,
  Colors.orange,
  Colors.purple,
];

MaterialColor _colorForMember(String name) =>
    _memberColors[name.hashCode.abs() % _memberColors.length];

/// How each kind of change is drawn: rail icon, tint and chip label.
class _TypeStyle {
  final MaterialColor color;
  final IconData icon;
  final String label;

  const _TypeStyle(this.color, this.icon, this.label);

  static _TypeStyle of(String type) {
    switch (type) {
      case 'meal':
        return _TypeStyle(Colors.teal, Icons.restaurant_rounded, 'meal'.tr);
      case 'expense':
        return _TypeStyle(
            Colors.blue, Icons.receipt_long_rounded, 'expense'.tr);
      case 'role':
        return _TypeStyle(
            Colors.deepPurple, Icons.admin_panel_settings_rounded, 'role'.tr);
      case 'member':
        return _TypeStyle(
            Colors.orange, Icons.person_remove_rounded, 'member'.tr);
      default:
        return _TypeStyle(
          Colors.blueGrey,
          Icons.edit_rounded,
          type.isEmpty
              ? 'unknown'.tr
              : type[0].toUpperCase() + type.substring(1),
        );
    }
  }
}

/// `2 → 3` pulled out of a description such as "Meal count changed from 2 to
/// 3 …" or "… amount 500.0 -> 650.0", so the change reads at a glance.
class _Delta {
  final String from;
  final String to;

  const _Delta(this.from, this.to);

  // Numbers only, so a description that merely contains the words "from"
  // and "to" (an expense named "Bus from Dhaka to Sylhet") is left alone.
  static final RegExp _arrow = RegExp(r'(৳?[\d.,]+)\s*->\s*(৳?[\d.,]+)');
  static final RegExp _fromTo =
      RegExp(r'\bfrom\s+(৳?[\d.,]+)\s+to\s+(৳?[\d.,]+)');

  static _Delta? parse(String description) {
    final Match? m =
        _arrow.firstMatch(description) ?? _fromTo.firstMatch(description);
    if (m == null) return null;
    final String from = _trim(m.group(1)!);
    final String to = _trim(m.group(2)!);
    if (from.isEmpty || to.isEmpty) return null;
    return _Delta(from, to);
  }

  /// Drops a trailing `.0` and any punctuation the sentence carried along.
  static String _trim(String raw) {
    String s = raw.replaceAll(RegExp(r'[,.;:]+$'), '');
    if (RegExp(r'^-?\d+\.0+$').hasMatch(s)) s = s.split('.').first;
    return s;
  }
}

class EditHistoryScreen extends StatefulWidget {
  const EditHistoryScreen({super.key});

  @override
  State<EditHistoryScreen> createState() => _EditHistoryScreenState();
}

class _EditHistoryScreenState extends State<EditHistoryScreen> {
  ProfileController get controller => Get.find<ProfileController>();

  @override
  void initState() {
    super.initState();
    // After the first frame: kicking a controller update off inside initState
    // would mark the profile page's builder dirty mid-build.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => controller.ensureEditLogsLoaded());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: CustomAppBar(title: 'edit_history'.tr),
      body: GetBuilder<ProfileController>(
        builder: (c) {
          final bool failed = !c.editLogsLoaded && c.editLogsError.isNotEmpty;
          return Column(
            children: [
              if (c.editLogsLoaded) _FilterBar(controller: c),
              Expanded(
                child: failed
                    ? _buildErrorState(context, c)
                    : !c.editLogsLoaded
                        ? const EditHistorySkeleton()
                        : RefreshIndicator(
                            color: Theme.of(context).colorScheme.primary,
                            onRefresh: c.refreshEditLogs,
                            child: c.editLogs.isEmpty
                                ? _buildEmptyState(context, c)
                                : _Timeline(controller: c),
                          ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, ProfileController c) {
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: c.loadEditLogs,
      child: _CenteredState(
        icon: Icons.cloud_off_rounded,
        color: Colors.red,
        title: 'failed_load_edit_history'.tr,
        hint: 'check_connection'.tr,
        action: TextButton.icon(
          onPressed: c.loadEditLogs,
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: Text('retry'.tr),
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, ProfileController c) {
    // Nothing has ever been logged, versus nothing survives the filters —
    // the second one gets a way out.
    if (c.allEditLogs.isEmpty) {
      return _CenteredState(
        icon: Icons.history_rounded,
        color: Colors.blueGrey,
        title: 'no_edit_history'.tr,
        hint: 'edit_history_hint'.tr,
      );
    }
    return _CenteredState(
      icon: Icons.filter_alt_off_rounded,
      color: Colors.orange,
      title: 'no_matching_edits'.tr,
      hint: 'try_widening_filters'.tr,
      action: OutlinedButton.icon(
        onPressed: c.showAllTime,
        style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.primary,
          side: BorderSide(
              color: Theme.of(context).colorScheme.primary.withOpacity(0.5)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        ),
        icon: const Icon(Icons.all_inclusive_rounded, size: 18),
        label: Text('show_all_time'.tr,
            style: const TextStyle(fontWeight: FontWeight.w700)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter bar
// ---------------------------------------------------------------------------

class _FilterBar extends StatelessWidget {
  final ProfileController controller;

  const _FilterBar({required this.controller});

  @override
  Widget build(BuildContext context) {
    final ProfileController c = controller;
    final bool periodNarrowed = c.filterPeriod != EditLogPeriod.thisMonth;
    final List<String> types = c.presentTypes;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
        boxShadow: AppUi.softShadow(context),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                flex: 5,
                child: _SelectorChip(
                  icon: Icons.calendar_today_rounded,
                  label: _periodLabel(c),
                  isActive: periodNarrowed,
                  onTap: () => _showPeriodSheet(context, c),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 4,
                child: _SelectorChip(
                  icon: Icons.person_search_rounded,
                  label: c.filterTargetUser?.name ?? 'all_users'.tr,
                  isActive: c.filterTargetUser != null,
                  onTap: () => _showUserSheet(context, c),
                ),
              ),
              // Reset only appears once something is narrowed, so the row
              // does not carry a dead button in the default state.
              AnimatedSize(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: c.hasActiveFilters
                    ? Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: _ResetButton(onTap: c.clearFilters),
                      )
                    : const SizedBox.shrink(),
              ),
            ],
          ),
          if (types.length > 1) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 34,
              child: ListView(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                children: [
                  _TypeChip(
                    label: 'all'.tr,
                    icon: Icons.apps_rounded,
                    color: Theme.of(context).colorScheme.primary,
                    count: c.countForType(null),
                    isSelected: c.filterType == null,
                    onTap: () => c.setTypeFilter(null),
                  ),
                  for (final String type in types) ...[
                    const SizedBox(width: 8),
                    Builder(builder: (context) {
                      final _TypeStyle style = _TypeStyle.of(type);
                      return _TypeChip(
                        label: style.label,
                        icon: style.icon,
                        color: AppUi.accent(context, style.color),
                        count: c.countForType(type),
                        isSelected: c.filterType == type,
                        onTap: () =>
                            c.setTypeFilter(c.filterType == type ? null : type),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _periodLabel(ProfileController c) {
    switch (c.filterPeriod) {
      case EditLogPeriod.thisMonth:
        return 'this_month'.tr;
      case EditLogPeriod.lastMonth:
        return 'last_month'.tr;
      case EditLogPeriod.last7Days:
        return 'last_7_days'.tr;
      case EditLogPeriod.allTime:
        return 'all_time'.tr;
      case EditLogPeriod.custom:
        return _rangeLabel(c.filterStartDate, c.filterEndDate);
    }
  }

  static String _rangeLabel(DateTime? start, DateTime? end) {
    final DateFormat f = DateFormat('dd MMM');
    if (start != null && end != null) {
      return '${f.format(start)} – ${f.format(end)}';
    }
    if (start != null) return 'from_date'.trParams({'date': f.format(start)});
    if (end != null) return 'until_date'.trParams({'date': f.format(end)});
    return 'all_time'.tr;
  }

  // ---- Period sheet -------------------------------------------------------

  void _showPeriodSheet(BuildContext context, ProfileController c) {
    _showSheet(
      context,
      title: 'select_period'.tr,
      children: [
        for (final EditLogPeriod p in const [
          EditLogPeriod.thisMonth,
          EditLogPeriod.lastMonth,
          EditLogPeriod.last7Days,
          EditLogPeriod.allTime,
        ])
          _SheetRow(
            leading: Icon(_periodIcon(p), size: 20),
            title: _presetLabel(p),
            isSelected: c.filterPeriod == p,
            onTap: () {
              closeOverlayRoute();
              c.setPeriod(p);
            },
          ),
        Divider(height: 1, color: AppUi.hairline(context)),
        _SheetRow(
          leading: const Icon(Icons.date_range_rounded, size: 20),
          title: 'custom_range'.tr,
          subtitle: c.filterPeriod == EditLogPeriod.custom
              ? _rangeLabel(c.filterStartDate, c.filterEndDate)
              : null,
          isSelected: c.filterPeriod == EditLogPeriod.custom,
          trailingChevron: true,
          onTap: () {
            closeOverlayRoute();
            _pickCustomRange(context, c);
          },
        ),
      ],
    );
  }

  static IconData _periodIcon(EditLogPeriod p) {
    switch (p) {
      case EditLogPeriod.thisMonth:
        return Icons.calendar_month_rounded;
      case EditLogPeriod.lastMonth:
        return Icons.history_rounded;
      case EditLogPeriod.last7Days:
        return Icons.view_week_rounded;
      case EditLogPeriod.allTime:
        return Icons.all_inclusive_rounded;
      case EditLogPeriod.custom:
        return Icons.date_range_rounded;
    }
  }

  static String _presetLabel(EditLogPeriod p) {
    switch (p) {
      case EditLogPeriod.thisMonth:
        return 'this_month'.tr;
      case EditLogPeriod.lastMonth:
        return 'last_month'.tr;
      case EditLogPeriod.last7Days:
        return 'last_7_days'.tr;
      case EditLogPeriod.allTime:
        return 'all_time'.tr;
      case EditLogPeriod.custom:
        return 'custom_range'.tr;
    }
  }

  Future<void> _pickCustomRange(
      BuildContext context, ProfileController c) async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime first = DateTime(2020);

    // The picker asserts the initial range sits inside [first, today]; the
    // "this month" preset runs to the end of the month, so clamp it.
    DateTimeRange? initial;
    if (c.filterStartDate != null && c.filterEndDate != null) {
      DateTime end = c.filterEndDate!.isAfter(today) ? today : c.filterEndDate!;
      DateTime start =
          c.filterStartDate!.isBefore(first) ? first : c.filterStartDate!;
      if (start.isAfter(end)) start = end;
      initial = DateTimeRange(start: start, end: end);
    }

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: today,
      initialDateRange: initial,
      helpText: 'select_period'.tr.toUpperCase(),
      saveText: 'apply'.tr,
      builder: (context, child) {
        // Keep the app's brightness — a forced light scheme on a dark theme
        // makes the calendar unreadable.
        final ThemeData theme = Theme.of(context);
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: theme.colorScheme.primary,
              onPrimary: Colors.white,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) c.setDateFilter(picked.start, picked.end);
  }

  // ---- Member sheet -------------------------------------------------------

  void _showUserSheet(BuildContext context, ProfileController c) {
    _showSheet(
      context,
      title: 'filter_by_user'.tr,
      children: [
        _SheetRow(
          leading: Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: AppUi.tint(context, Theme.of(context).colorScheme.primary),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.groups_rounded,
                size: 18, color: Theme.of(context).colorScheme.primary),
          ),
          title: 'all_users'.tr,
          isSelected: c.filterTargetUser == null,
          onTap: () {
            closeOverlayRoute();
            c.setUserFilter(null);
          },
        ),
        for (final UserModel user in c.availableUsers)
          Builder(builder: (context) {
            final MaterialColor color = _colorForMember(user.name);
            return _SheetRow(
              leading: ProfileAvatar(
                name: user.name,
                phone: user.phone,
                imageUrl: user.profileImage,
                size: 34,
                background: AppUi.tint(context, color),
                foreground: AppUi.accent(context, color),
                borderColor: color.withOpacity(0.4),
                fontSize: 12,
              ),
              title: user.name,
              subtitle: user.phone,
              isSelected: c.filterTargetUser?.phone == user.phone,
              onTap: () {
                closeOverlayRoute();
                c.setUserFilter(user);
              },
            );
          }),
      ],
    );
  }

  void _showSheet(
    BuildContext context, {
    required String title,
    required List<Widget> children,
  }) {
    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SafeArea(
          top: false,
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
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: AppUi.body(context),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: AppUi.hairline(context)),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  children: children,
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }
}

class _SelectorChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _SelectorChip({
    required this.icon,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final Color fg = isActive ? primary : AppUi.body(context);

    return Material(
      color: isActive
          ? AppUi.tint(context, primary)
          : AppUi.neutralSurface(context),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color:
                  isActive ? primary.withOpacity(0.6) : AppUi.hairline(context),
              width: 1.2,
            ),
          ),
          child: Row(
            children: [
              Icon(icon,
                  size: 16, color: isActive ? primary : AppUi.muted(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: fg,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded,
                  size: 18, color: isActive ? primary : AppUi.muted(context)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResetButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ResetButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'reset_filters'.tr,
      child: Material(
        color: AppUi.tint(context, Colors.red),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: 42,
            height: 42,
            child: Icon(Icons.filter_alt_off_rounded,
                size: 19, color: AppUi.accent(context, Colors.red)),
          ),
        ),
      ),
    );
  }
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.color,
    required this.count,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color fg = isSelected ? color : AppUi.body(context).withOpacity(0.75);

    return Material(
      color: isSelected
          ? AppUi.tint(context, color)
          : AppUi.neutralSurface(context),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected
                  ? color.withOpacity(0.55)
                  : AppUi.hairline(context),
              width: 1.2,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
                  color: fg,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? color.withOpacity(AppUi.isDark(context) ? 0.35 : 0.18)
                      : AppUi.hairline(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                    color: fg,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetRow extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final bool isSelected;
  final bool trailingChevron;
  final VoidCallback onTap;

  const _SheetRow({
    required this.leading,
    required this.title,
    this.subtitle,
    required this.isSelected,
    this.trailingChevron = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;

    return Material(
      color: isSelected ? AppUi.tint(context, primary) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              IconTheme(
                data: IconThemeData(
                    color: isSelected ? primary : AppUi.muted(context)),
                child: SizedBox(width: 34, child: Center(child: leading)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            isSelected ? FontWeight.w800 : FontWeight.w600,
                        color: isSelected ? primary : AppUi.body(context),
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12, color: AppUi.muted(context)),
                      ),
                    ],
                  ],
                ),
              ),
              if (isSelected)
                Icon(Icons.check_circle_rounded, color: primary, size: 20)
              else if (trailingChevron)
                Icon(Icons.chevron_right_rounded,
                    color: AppUi.muted(context), size: 22),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Timeline
// ---------------------------------------------------------------------------

/// A group of entries that share the same calendar day.
class _DayGroup {
  final String label;
  final List<EditLogModel> items;

  _DayGroup(this.label, this.items);
}

class _Timeline extends StatelessWidget {
  final ProfileController controller;

  const _Timeline({required this.controller});

  List<_DayGroup> _groupByDay(List<EditLogModel> logs) {
    final List<_DayGroup> groups = [];
    final Map<String, _DayGroup> index = {};
    for (final EditLogModel log in logs) {
      final String key = DateFormat('yyyy-MM-dd').format(log.createdAt);
      _DayGroup? group = index[key];
      if (group == null) {
        group = _DayGroup(AppUi.dayLabel(log.createdAt), []);
        index[key] = group;
        groups.add(group);
      }
      group.items.add(log);
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    // Flatten "count line, day header, entries…" into one lazily built list.
    final List<Object> rows = [_Summary(count: controller.editLogs.length)];
    for (final _DayGroup group in _groupByDay(controller.editLogs)) {
      rows.add(group.label);
      rows.addAll(group.items);
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final Object row = rows[index];
        if (row is Widget) return row;
        if (row is String) return _DayHeader(label: row);

        final EditLogModel log = row as EditLogModel;
        final bool isLastOfDay =
            index == rows.length - 1 || rows[index + 1] is! EditLogModel;
        return _EntryTile(
          log: log,
          isLastOfDay: isLastOfDay,
          // Any admin may remove any entry; members only read.
          onDelete: controller.isAdminUser
              ? () => _confirmDelete(context, log)
              : null,
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, EditLogModel log) {
    showConfirmDialog(
      title: 'delete_edit_log'.tr,
      message: 'confirm_delete_edit_log'.tr,
      detail: log.description,
      confirmText: 'delete'.tr,
      onConfirm: () => controller.deleteEditLog(log),
    );
  }
}

class _Summary extends StatelessWidget {
  final int count;

  const _Summary({required this.count});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 2, 0),
      child: Text(
        count == 1
            ? 'one_change'.tr
            : 'changes_count'.trParams({'count': '$count'}),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
          color: AppUi.muted(context),
        ),
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  final String label;

  const _DayHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppUi.isDark(context)
                  ? Colors.white.withOpacity(0.06)
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppUi.hairline(context)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_today_rounded,
                    size: 12, color: AppUi.muted(context)),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: AppUi.body(context).withOpacity(0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(child: Divider(color: AppUi.hairline(context), height: 1)),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final EditLogModel log;
  final bool isLastOfDay;

  /// Set only for admins; null hides the delete affordance.
  final VoidCallback? onDelete;

  const _EntryTile({
    required this.log,
    required this.isLastOfDay,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final _TypeStyle style = _TypeStyle.of(log.type);
    final Color accent = AppUi.accent(context, style.color);
    final MaterialColor targetColor = _colorForMember(log.targetUserName);
    final _Delta? delta = _Delta.parse(log.description);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Timeline rail: what kind of change, and a connector to the next.
          Column(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppUi.tint(context, style.color),
                  shape: BoxShape.circle,
                  border: Border.all(color: style.color.withOpacity(0.45)),
                ),
                child: Icon(style.icon, size: 18, color: accent),
              ),
              if (!isLastOfDay)
                Expanded(
                  child: Container(width: 2, color: AppUi.hairline(context)),
                ),
            ],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLastOfDay ? 4 : 16),
              child: Material(
                color: Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onLongPress: () {
                    Clipboard.setData(ClipboardData(text: log.description));
                    CustomSnackbar.show(
                        type: SnackbarType.success, message: 'copied'.tr);
                  },
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppUi.hairline(context)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black
                              .withOpacity(AppUi.isDark(context) ? 0.25 : 0.04),
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _header(context, style, accent, targetColor),
                        const SizedBox(height: 10),
                        Text(
                          log.description,
                          style: TextStyle(
                            fontSize: 14,
                            height: 1.45,
                            fontWeight: FontWeight.w500,
                            color: AppUi.body(context),
                          ),
                        ),
                        if (delta != null) ...[
                          const SizedBox(height: 10),
                          _DeltaPill(delta: delta, color: style.color),
                        ],
                        const SizedBox(height: 12),
                        Divider(height: 1, color: AppUi.hairline(context)),
                        const SizedBox(height: 10),
                        _footer(context),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Who was affected, what kind of change, and when.
  Widget _header(BuildContext context, _TypeStyle style, Color accent,
      MaterialColor targetColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        ProfileAvatar(
          name: log.targetUserName,
          phone: log.targetUserPhone,
          size: 36,
          background: AppUi.tint(context, targetColor),
          foreground: AppUi.accent(context, targetColor),
          borderColor: targetColor.withOpacity(0.4),
          fontSize: 12,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                log.targetUserName.isEmpty ? 'unknown'.tr : log.targetUserName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  color: AppUi.body(context),
                ),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppUi.tint(context, style.color),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      style.label.toUpperCase(),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              DateFormat('hh:mm a').format(log.createdAt),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: AppUi.muted(context),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              DateFormat('dd MMM').format(log.createdAt),
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w500,
                color: AppUi.muted(context).withOpacity(0.8),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Which admin did it.
  Widget _footer(BuildContext context) {
    final MaterialColor adminColor = _colorForMember(log.adminName);
    return Row(
      children: [
        ProfileAvatar(
          name: log.adminName,
          phone: log.adminPhone,
          size: 20,
          background: AppUi.tint(context, adminColor),
          foreground: AppUi.accent(context, adminColor),
          fontSize: 8,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'changed_by'.trParams({
              'name': log.adminName.isEmpty ? 'unknown'.tr : log.adminName,
            }),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: AppUi.muted(context),
            ),
          ),
        ),
        if (onDelete != null)
          Tooltip(
            message: 'delete_edit_log'.tr,
            child: Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: onDelete,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: AppUi.accent(context, Colors.red).withOpacity(0.85),
                  ),
                ),
              ),
            ),
          )
        else
          Icon(Icons.verified_user_outlined,
              size: 13, color: AppUi.muted(context).withOpacity(0.7)),
      ],
    );
  }
}

/// `2 → 3`, old value struck through, new one in the type's accent.
class _DeltaPill extends StatelessWidget {
  final _Delta delta;
  final MaterialColor color;

  const _DeltaPill({required this.delta, required this.color});

  @override
  Widget build(BuildContext context) {
    final Color accent = AppUi.accent(context, color);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppUi.neutralSurface(context),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            delta.from,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppUi.muted(context),
              decoration: TextDecoration.lineThrough,
              decorationColor: AppUi.muted(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Icon(Icons.arrow_forward_rounded, size: 14, color: accent),
          ),
          Text(
            delta.to,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w900,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty / error states
// ---------------------------------------------------------------------------

/// A centred icon-title-hint block that still scrolls, so pull-to-refresh
/// keeps working when there is nothing to list.
class _CenteredState extends StatelessWidget {
  final IconData icon;
  final MaterialColor color;
  final String title;
  final String hint;
  final Widget? action;

  const _CenteredState({
    required this.icon,
    required this.color,
    required this.title,
    required this.hint,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: AppUi.tint(context, color),
                    shape: BoxShape.circle,
                  ),
                  child:
                      Icon(icon, size: 52, color: AppUi.accent(context, color)),
                ),
                const SizedBox(height: 22),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppUi.body(context).withOpacity(0.85),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hint,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: AppUi.muted(context),
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: 18),
                  action!,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
