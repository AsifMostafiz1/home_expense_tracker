import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../common/widgets/hiding_fab.dart';
import '../../expense/controller/expense_controller.dart';
import '../../expense/model/expense_model.dart';
import '../../expense/widgets/expense_bottom_sheet.dart';
import '../../../utils/app_ui.dart';
import '../controller/meal_controller.dart';
import 'announcement_history_screen.dart';

/// ---------------------------------------------------------------------------
/// Small design helpers shared by every section of this screen so spacing,
/// elevation and tinting stay consistent in both light and dark themes.
/// ---------------------------------------------------------------------------

const List<String> _monthKeys = [
  'jan', 'feb', 'mar', 'apr', 'may', 'jun',
  'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
];

String _monthLabel(DateTime date) =>
    '${_monthKeys[date.month - 1].tr} ${date.year}';

String _dateKeyOf(DateTime date) =>
    '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

/// Background tint of a colored accent that stays readable in both themes.
Color _tint(BuildContext context, Color color) =>
    color.withOpacity(_isDark(context) ? 0.20 : 0.10);

/// Foreground version of an accent color, lightened for dark surfaces.
Color _accentOn(BuildContext context, MaterialColor color) =>
    _isDark(context) ? color.shade300 : color.shade700;

Color _bodyColor(BuildContext context) =>
    Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87;

Color _mutedColor(BuildContext context) =>
    (Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey)
        .withOpacity(0.65);

Color _neutralSurface(BuildContext context) =>
    _isDark(context) ? Colors.white.withOpacity(0.04) : Colors.grey.shade50;

Color _hairline(BuildContext context) =>
    Theme.of(context).dividerColor.withOpacity(_isDark(context) ? 0.8 : 1);

List<BoxShadow> _softShadow(BuildContext context) => [
      BoxShadow(
        color: Colors.black.withOpacity(_isDark(context) ? 0.28 : 0.05),
        blurRadius: 18,
        offset: const Offset(0, 8),
      ),
    ];

/// Same balance formula the member cards have always used:
/// what you paid  −  what you consumed.
double _balanceOf({
  required int count,
  required double expense,
  required double otherExpense,
  required double rate,
  required double otherRate,
}) =>
    (expense + otherExpense) - (count * rate + otherRate);

String _initialsOf(String name) {
  final parts = name
      .trim()
      .split(RegExp(r'\s+'))
      .where((p) => p.isNotEmpty && RegExp(r'[\wঀ-৿]').hasMatch(p))
      .toList();
  if (parts.isEmpty) return '?';
  if (parts.length == 1) return parts.first.characters.first.toUpperCase();
  return (parts[0].characters.first + parts[1].characters.first).toUpperCase();
}

String _friendlyDateTime(DateTime date) {
  final now = DateTime.now();
  final day = DateTime(date.year, date.month, date.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  final time = DateFormat('hh:mm a').format(date);
  if (diff == 0) return '${'today'.tr}, $time';
  if (diff == 1) return '${'yesterday'.tr}, $time';
  return '${DateFormat('dd MMM').format(date)}, $time';
}

class MealScreen extends GetView<MealController> {
  const MealScreen({super.key});

  static const List<MaterialColor> _memberColors = [
    Colors.orange,
    Colors.purple,
    Colors.pink,
    Colors.blue,
    Colors.amber,
  ];

  @override
  Widget build(BuildContext context) {
    // Controller is provided via MealBinding

    return HidingFab(
      icon: Icons.campaign_rounded,
      tooltip: 'announcement'.tr,
      onPressed: () => _showAnnouncementBottomSheet(context),
      builder: (context, fab) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        appBar: CustomAppBar(
          title: 'meal'.tr,
          actions: [
            IconButton(
              tooltip: 'announcement_history'.tr,
              icon: const Icon(Icons.history_rounded, size: 22),
              onPressed: () => Get.to(() => const AnnouncementHistoryScreen()),
            ),
            const SizedBox(width: 8),
          ],
        ),
        floatingActionButton: fab,
        body: GetBuilder<MealController>(
          builder: (controller) {
            final bool isFirstLoad = controller.isFetchingStats &&
                controller.totalMealCount == 0 &&
                controller.otherUsersMeals.isEmpty;

            return RefreshIndicator(
              color: Theme.of(context).colorScheme.primary,
              onRefresh: () async {
                await controller.fetchMeals(background: true);
                await controller.fetchMonthlyStats(background: true);
                await controller.fetchAnnouncement();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    _buildAnnouncement(context),
                    _buildQuickStats(context),
                    _buildCalendarCard(context),
                    _buildBulkMealCard(context),
                    _buildSummarySection(context, isLoading: isFirstLoad),
                    // Breathing room so the FAB never covers the last card.
                    const SizedBox(height: 96),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  /// ----------------------------------------------------------- quick stats

  Widget _buildQuickStats(BuildContext context) {
    final now = DateTime.now();
    final tomorrow = now.add(const Duration(days: 1));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Expanded(
            child: _buildQuickStatCard(
              context,
              title: 'today_total'.tr,
              count: controller.getTodayTotal(),
              color: Colors.blue,
              icon: Icons.wb_sunny_rounded,
              onTap: () => _showMealBreakdownDialog(
                  context, 'today'.tr, _dateKeyOf(now)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildQuickStatCard(
              context,
              title: 'tomorrow_total'.tr,
              count: controller.getTomorrowTotal(),
              color: Colors.orange,
              icon: Icons.event_rounded,
              onTap: () => _showMealBreakdownDialog(
                  context, 'tomorrow'.tr, _dateKeyOf(tomorrow)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStatCard(
    BuildContext context, {
    required String title,
    required int count,
    required MaterialColor color,
    required IconData icon,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Theme.of(context).cardColor,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: color.withOpacity(0.20)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(7),
                    decoration: BoxDecoration(
                      color: _tint(context, color),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: _accentOn(context, color), size: 16),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _mutedColor(context),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 26,
                      height: 1,
                      fontWeight: FontWeight.bold,
                      color: _accentOn(context, color),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 2),
                    child: Text(
                      'meals'.tr,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: _mutedColor(context),
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (onTap != null)
                    Icon(Icons.chevron_right_rounded,
                        size: 18, color: _mutedColor(context)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// -------------------------------------------------------------- calendar

  Widget _buildCalendarCard(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final today = DateTime.now();
    final startOfToday = DateTime(today.year, today.month, today.day);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _hairline(context)),
        boxShadow: _softShadow(context),
      ),
      child: Column(
        children: [
          Padding(
            // Bottom gap keeps the last row's day numbers and count badges
            // off the divider below.
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
            child: TableCalendar(
              firstDay: controller.firstDay,
              lastDay: controller.lastDay,
              focusedDay: controller.focusedDay,
              availableGestures: AvailableGestures.none,
              rowHeight: 46,
              daysOfWeekHeight: 28,
              selectedDayPredicate: (day) =>
                  isSameDay(controller.selectedDay, day),
              onDaySelected: controller.onDaySelected,
              onPageChanged: controller.onPageChanged,
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                headerPadding: const EdgeInsets.symmetric(vertical: 10),
                leftChevronIcon: Icon(Icons.chevron_left_rounded,
                    color: _bodyColor(context), size: 26),
                rightChevronIcon: Icon(Icons.chevron_right_rounded,
                    color: _bodyColor(context), size: 26),
                titleTextStyle: Theme.of(context).textTheme.titleMedium!,
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: _mutedColor(context),
                ),
                weekendStyle: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Colors.red.withOpacity(0.7),
                ),
              ),
              calendarStyle: CalendarStyle(
                cellMargin: const EdgeInsets.all(4),
                todayDecoration: BoxDecoration(
                  color: primary.withOpacity(0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: primary, width: 1.4),
                ),
                todayTextStyle: TextStyle(
                  color: _isDark(context) ? Colors.white : primary,
                  fontWeight: FontWeight.bold,
                ),
                selectedDecoration: BoxDecoration(
                  color: primary,
                  shape: BoxShape.circle,
                ),
                defaultTextStyle: Theme.of(context).textTheme.bodyMedium!,
                weekendTextStyle: Theme.of(context)
                    .textTheme
                    .bodyMedium!
                    .copyWith(color: Colors.red),
                outsideTextStyle: TextStyle(
                  color: _mutedColor(context).withOpacity(0.35),
                ),
                disabledTextStyle: TextStyle(
                  color: _mutedColor(context).withOpacity(0.55),
                ),
                markersMaxCount: 1,
              ),
              calendarBuilders: CalendarBuilders(
                headerTitleBuilder: (context, day) => Center(
                  child: Text(
                    _monthLabel(day),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                // Past days can't be edited (the controller blocks them), so
                // dim them — but keep their meal markers fully visible.
                defaultBuilder: (context, day, focusedDay) {
                  if (!DateTime(day.year, day.month, day.day)
                      .isBefore(startOfToday)) {
                    return null; // keep the package's default rendering
                  }
                  final bool isWeekend = day.weekday == DateTime.saturday ||
                      day.weekday == DateTime.sunday;
                  return Container(
                    margin: const EdgeInsets.all(4),
                    alignment: Alignment.center,
                    child: Text(
                      '${day.day}',
                      style: TextStyle(
                        fontSize: 14,
                        color: (isWeekend ? Colors.red : _bodyColor(context))
                            .withOpacity(0.40),
                      ),
                    ),
                  );
                },
                markerBuilder: (context, date, events) {
                  final String dateKey = _dateKeyOf(date);
                  if (!controller.dailyMeals.containsKey(dateKey)) {
                    return const SizedBox.shrink();
                  }
                  return Positioned(
                    bottom: 1,
                    child: _mealMarker(context, controller.dailyMeals[dateKey]!),
                  );
                },
              ),
            ),
          ),
          Divider(height: 1, color: _hairline(context)),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _legendItem(context, Colors.red, 'no_meal'.tr),
                    _legendItem(context, primary, 'one_meal'.tr, useRaw: true),
                    _legendItem(context, Colors.amber, 'two_plus_meals'.tr),
                  ],
                ),
                const SizedBox(height: 12),
                // Until the month has been filled in, a tap is refused — so
                // the line says that instead of inviting one.
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      controller.canEditDays
                          ? Icons.touch_app_outlined
                          : Icons.lock_outline_rounded,
                      size: 14,
                      color: _mutedColor(context),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        controller.canEditDays
                            ? 'tap_day_to_update'.tr
                            : 'add_bulk_meal_first'.tr,
                        style: TextStyle(
                          fontSize: 11,
                          color: _mutedColor(context),
                          fontWeight: FontWeight.w500,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The little count badge under each calendar day.
  /// 0 → red · 1 → primary · 2+ → amber (unchanged rules, cleaner look).
  Widget _mealMarker(BuildContext context, int count) {
    final Color accent = count == 0
        ? Colors.red
        : count == 1
            ? Theme.of(context).colorScheme.primary
            : Colors.amber;
    final Color fg = count == 0
        ? (_isDark(context) ? Colors.red.shade300 : Colors.red.shade600)
        : count == 1
            ? Theme.of(context).colorScheme.primary
            : (_isDark(context) ? Colors.amber.shade300 : Colors.amber.shade800);

    return Container(
      constraints: const BoxConstraints(minWidth: 16),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: _tint(context, accent),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withOpacity(0.35)),
      ),
      child: Text(
        '$count',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 9,
          height: 1.2,
          color: fg,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _legendItem(BuildContext context, Color color, String label,
      {bool useRaw = false}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: _tint(context, color),
            shape: BoxShape.circle,
            border: Border.all(color: color.withOpacity(0.6), width: 1.4),
          ),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: _mutedColor(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  /// ------------------------------------------------------------ bulk meals

  Widget _buildBulkMealCard(BuildContext context) {
    if (!controller.canAddBulkMeal) return const SizedBox.shrink();
    final primary = Theme.of(context).colorScheme.primary;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _tint(context, primary),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: primary.withOpacity(0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: primary.withOpacity(0.20),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_awesome_rounded,
                    color: primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${'add_bulk_meal'.tr} · ${_monthLabel(controller.focusedDay)}',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'bulk_meal_hint'.tr,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: _mutedColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          CustomButton(
            text: 'add_bulk_meal'.tr,
            height: 48,
            isLoading: controller.isLoading,
            onPressed: () => controller.addBulkMeal(),
          ),
        ],
      ),
    );
  }

  /// --------------------------------------------------------------- summary

  Widget _buildSummarySection(BuildContext context, {required bool isLoading}) {
    final int memberCount = controller.otherUsersMeals.length + 1;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'monthly_summary'.tr,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _monthLabel(controller.focusedDay),
                      style: TextStyle(
                        fontSize: 12,
                        color: _mutedColor(context),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _neutralSurface(context),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _hairline(context)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.people_alt_rounded,
                        size: 13, color: _mutedColor(context)),
                    const SizedBox(width: 5),
                    Text(
                      '$memberCount',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _bodyColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (isLoading) ...[
            const _CardSkeleton(),
            const SizedBox(height: 12),
            const _CardSkeleton(),
            const SizedBox(height: 12),
            const _CardSkeleton(),
          ] else ...[
            _buildTotalCard(context),
            const SizedBox(height: 12),
            _buildMemberCard(
              context,
              title: 'my_meals'.tr,
              count: controller.myMealCount,
              expense: controller.myMonthlyExpense,
              otherExpense: controller.myOtherExpense,
              rate: controller.avgMealRate,
              otherRate: controller.otherCostPerPerson,
              color: Colors.teal,
              isMe: true,
              onTap: () => _showUserCalendarBottomSheet(context, {
                'name': 'me_you'.tr,
                'count': controller.myMealCount,
                'daily_meals': controller.dailyMeals,
                'expenses': controller.myExpenses,
                'expense': controller.myMonthlyExpense,
                'other_expense': controller.myOtherExpense,
              }),
            ),
            ...controller.otherUsersMeals.asMap().entries.map((entry) {
              final color = _memberColors[entry.key % _memberColors.length];
              return Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _buildMemberCard(
                  context,
                  title: entry.value['name'] ?? 'unknown'.tr,
                  count: entry.value['count'] as int,
                  expense: entry.value['expense'] as double? ?? 0.0,
                  otherExpense: entry.value['other_expense'] as double? ?? 0.0,
                  rate: controller.avgMealRate,
                  otherRate: controller.otherCostPerPerson,
                  color: color,
                  onTap: () =>
                      _showUserCalendarBottomSheet(context, entry.value),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildTotalCard(BuildContext context) {
    const MaterialColor color = Colors.indigo;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: color.withOpacity(0.25)),
        boxShadow: _softShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            color: _tint(context, color),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: color.withOpacity(_isDark(context) ? 0.35 : 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.restaurant_rounded,
                      color: _accentOn(context, color), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'total_monthly_stats'.tr,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                        ),
                  ),
                ),
                _countChip(context, controller.totalMealCount, color),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              children: [
                Row(
                  children: [
                    _statTile(context,
                        label: 'meal_paid'.tr,
                        value:
                            '৳${controller.totalMonthlyExpense.toStringAsFixed(1)}'),
                    _statTile(context,
                        label: 'other_paid'.tr,
                        value:
                            '৳${controller.totalOtherExpense.toStringAsFixed(1)}'),
                    _statTile(context,
                        label: 'total_users'.tr,
                        value: '${controller.userCount}'),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _neutralSurface(context),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _hairline(context)),
                  ),
                  child: Row(
                    children: [
                      _statTile(context,
                          label: 'meal_rate'.tr,
                          value:
                              '৳${controller.avgMealRate.toStringAsFixed(2)}',
                          valueColor: _accentOn(context, color)),
                      _statTile(context,
                          label: 'other_rate'.tr,
                          value:
                              '৳${controller.otherCostPerPerson.toStringAsFixed(2)}',
                          valueColor: _accentOn(context, color)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(
    BuildContext context, {
    required String title,
    required int count,
    required double expense,
    required double otherExpense,
    required double rate,
    required double otherRate,
    required MaterialColor color,
    bool isMe = false,
    VoidCallback? onTap,
  }) {
    final double mealCost = count * rate;
    final double balance = _balanceOf(
      count: count,
      expense: expense,
      otherExpense: otherExpense,
      rate: rate,
      otherRate: otherRate,
    );
    final bool willGet = balance >= 0;
    final MaterialColor balanceColor = willGet ? Colors.teal : Colors.red;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _hairline(context)),
        boxShadow: _softShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            children: [
              // ------------------------------------------------------- who
              //
              // The member's color washes the whole band. That reads as a
              // deliberate header, where the old 5px slab down the left edge
              // read as a stray bar fighting the rounded corner.
              Container(
                color: _tint(context, color),
                padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
                child: Row(
                  children: [
                    _avatar(context, title, color,
                        isMe: isMe,
                        size: 38,
                        background: Theme.of(context).cardColor),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.2,
                          color: _bodyColor(context),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    _countChip(context, count, color, onTinted: true),
                    if (onTap != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Icon(Icons.chevron_right_rounded,
                            size: 20, color: _mutedColor(context)),
                      ),
                  ],
                ),
              ),

              // ------------------------------------------------ the answer
              //
              // The balance is the only figure anyone opens this card for, so
              // it gets the size. Previously it sat last, in the same weight
              // as the four numbers it is derived from.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            willGet ? 'will_get'.tr : 'to_give'.tr,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                              color: _mutedColor(context),
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              AppUi.amount(balance.abs()),
                              style: TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -1.2,
                                height: 1.05,
                                color: _accentOn(context, balanceColor),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _tint(context, balanceColor),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        willGet
                            ? Icons.trending_up_rounded
                            : Icons.trending_down_rounded,
                        size: 19,
                        color: _accentOn(context, balanceColor),
                      ),
                    ),
                  ],
                ),
              ),

              // ----------------------------------------------- the working
              //
              // Four supporting figures on one line, so the card no longer
              // spends a 2x2 grid's worth of height on secondary detail.
              Container(
                decoration: BoxDecoration(
                  color: _neutralSurface(context),
                  border: Border(top: BorderSide(color: _hairline(context))),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
                child: Row(
                  children: [
                    _ledgerStat(context, 'meal_paid'.tr, expense),
                    _ledgerDivider(context),
                    _ledgerStat(context, 'other_paid'.tr, otherExpense),
                    _ledgerDivider(context),
                    _ledgerStat(context, 'meal_cost'.tr, mealCost),
                    _ledgerDivider(context),
                    _ledgerStat(context, 'other_cost'.tr, otherRate),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One figure in the member card's bottom strip.
  Widget _ledgerStat(BuildContext context, String label, double value) {
    final bool isZero = value.abs() < 0.005;

    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                AppUi.amount(value),
                maxLines: 1,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.3,
                  // A zero is not news. Letting it sit back keeps the eye on
                  // the figures in the row that actually moved.
                  color: isZero ? _mutedColor(context) : _bodyColor(context),
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w600,
                color: _mutedColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ledgerDivider(BuildContext context) => Container(
        width: 1,
        height: 26,
        color: _hairline(context),
      );

  Widget _statTile(
    BuildContext context, {
    required String label,
    required String value,
    Color? valueColor,
  }) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: _mutedColor(context),
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              color: valueColor ?? _bodyColor(context),
              fontWeight: FontWeight.bold,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// The meal count.
  ///
  /// [onTinted] is for chips sitting on a band already washed in [color] — a
  /// solid fill would disappear into it, so the chip inverts instead.
  Widget _countChip(
    BuildContext context,
    int count,
    MaterialColor color, {
    bool onTinted = false,
  }) {
    final Color foreground =
        onTinted ? _accentOn(context, color) : Colors.white;

    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: onTinted ? 10 : 12, vertical: onTinted ? 5 : 6),
      decoration: BoxDecoration(
        color: onTinted ? Theme.of(context).cardColor : color,
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (onTinted) ...[
            Icon(Icons.restaurant_rounded, size: 11, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            'meals_count'.trParams({'count': count.toString()}),
            style: TextStyle(
              color: foreground,
              fontSize: onTinted ? 11 : 12,
              fontWeight: onTinted ? FontWeight.w800 : FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(
    BuildContext context,
    String name,
    MaterialColor color, {
    bool isMe = false,
    double size = 42,
    Color? background,
  }) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background ?? _tint(context, color),
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.35), width: 1.5),
      ),
      child: isMe
          ? Icon(Icons.person_rounded,
              color: _accentOn(context, color), size: size * 0.5)
          : Text(
              _initialsOf(name),
              style: TextStyle(
                color: _accentOn(context, color),
                fontSize: size * 0.34,
                fontWeight: FontWeight.bold,
              ),
            ),
    );
  }

  /// ---------------------------------------------------------- announcement

  Widget _buildAnnouncement(BuildContext context) {
    final latest = controller.visibleAnnouncement;
    if (latest == null) {
      return const SizedBox.shrink();
    }

    final text = latest['text'] ?? '';
    final userName = latest['user_name'] ?? 'unknown'.tr;
    final updatedAt = latest['updatedAt'];

    DateTime? date;
    if (updatedAt is Timestamp) {
      date = updatedAt.toDate();
    } else if (updatedAt is String) {
      date = DateTime.parse(updatedAt);
    }

    final String? id = latest['id'] as String?;
    final Color primary = Theme.of(context).colorScheme.primary;
    final Color accent = _isDark(context)
        ? Color.lerp(primary, Colors.white, 0.35)!
        : Color.lerp(primary, Colors.black, 0.20)!;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Material(
        color: _tint(context, primary),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => Get.to(() => const AnnouncementHistoryScreen()),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: primary.withOpacity(0.35)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color:
                            primary.withOpacity(_isDark(context) ? 0.30 : 0.25),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.campaign_rounded,
                          color: accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  userName,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: accent,
                                    fontWeight: FontWeight.w900,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (date != null) ...[
                                const SizedBox(width: 8),
                                Text(
                                  _friendlyDateTime(date),
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: _mutedColor(context),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.35,
                              color: _bodyColor(context),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Hides the card until a newer announcement arrives.
                    Material(
                      color: Colors.transparent,
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        onTap: controller.dismissAnnouncement,
                        child: Tooltip(
                          message: 'close'.tr,
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: _mutedColor(context),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    if (id != null)
                      _resolveButton(context, id: id, primary: primary),
                    const Spacer(),
                    Text(
                      controller.announcements.length > 1
                          ? '${'see_more'.tr} (${controller.announcements.length})'
                          : 'see_more'.tr,
                      style: TextStyle(
                        fontSize: 12,
                        color: accent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward_rounded, size: 14, color: accent),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Marks the announcement done for the whole household — the flag is stored
  /// on the server, so the card leaves every member's meal screen.
  Widget _resolveButton(
    BuildContext context, {
    required String id,
    required Color primary,
  }) {
    return Material(
      color: primary,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _confirmResolveAnnouncement(context, id),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 14, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                'resolve'.tr,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmResolveAnnouncement(BuildContext context, String id) {
    showConfirmDialog(
      title: 'resolve_announcement'.tr,
      message: 'confirm_resolve_announcement'.tr,
      confirmText: 'resolve'.tr,
      confirmColor: Theme.of(context).colorScheme.primary,
      onConfirm: () => controller.resolveAnnouncement(id),
    );
  }

  void _showAnnouncementBottomSheet(BuildContext context) {
    // Every submission creates a NEW announcement, so always start empty.
    controller.announcementController.clear();

    Get.bottomSheet(
      Builder(
        builder: (sheetContext) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            ),
            child: SafeArea(
              top: false,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _sheetHandle(context),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: _tint(context, Colors.amber),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(Icons.campaign_rounded,
                                    color: _accentOn(context, Colors.amber),
                                    size: 22),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  'announcement'.tr,
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleLarge
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              IconButton(
                                onPressed: () =>
                                    Navigator.of(sheetContext).pop(),
                                icon: Icon(Icons.close_rounded,
                                    color: _mutedColor(context)),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          CustomTextField(
                            controller: controller.announcementController,
                            hintText: 'enter_announcement'.tr,
                            maxLines: 4,
                          ),
                          const SizedBox(height: 20),
                          GetBuilder<MealController>(
                            builder: (c) => CustomButton(
                              text: 'submit'.tr,
                              isLoading: c.isLoading,
                              onPressed: () => c.submitAnnouncement(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
      isScrollControlled: true,
    );
  }

  /// ----------------------------------------------------------------- sheets

  Widget _sheetHandle(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          width: 44,
          height: 4,
          decoration: BoxDecoration(
            color: _mutedColor(context).withOpacity(0.35),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
      ),
    );
  }

  Widget _buildSheetBadge(
      BuildContext context, String text, MaterialColor color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: _tint(context, color),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.30)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: _accentOn(context, color),
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  void _showExpenseBottomSheet(BuildContext context, {ExpenseModel? item}) {
    if (Get.isRegistered<ExpenseController>()) {
      final expController = Get.find<ExpenseController>();
      if (item != null) {
        expController.amountController.text = item.amount.toString();
        expController.descriptionController.text = item.description;
        expController.selectedDate = item.date;
        expController.selectedTime = item.time;
        expController.selectedType = item.type;
        expController.update(); // Manual update to reflect changes in UI
      } else {
        expController.clearForm();
      }
      Get.bottomSheet(
        ExpenseBottomSheet(item: item),
        isScrollControlled: true,
      );
    }
  }

  void _showUserCalendarBottomSheet(
      BuildContext context, Map<String, dynamic> user) {
    final Map<String, int> userDailyMeals =
        Map<String, int>.from(user['daily_meals'] ?? {});
    final String userName = user['name'] ?? 'User';
    final List<ExpenseModel> userExpenses =
        List<ExpenseModel>.from(user['expenses'] ?? []);
    final bool isMe = userName == 'me_you'.tr;
    final bool canAdminEdit = controller.isAdminUser && !isMe;
    final MaterialColor accent = isMe ? Colors.teal : Colors.indigo;

    Get.bottomSheet(
      Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _sheetHandle(context),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
              child: Row(
                children: [
                  _avatar(context, userName, accent, isMe: isMe, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'summary_of'.trParams({'name': userName}),
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          _monthLabel(controller.focusedDay),
                          style: TextStyle(
                            fontSize: 12,
                            color: _mutedColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: closeOverlayRoute,
                    icon: Icon(Icons.close_rounded,
                        color: _mutedColor(context)),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _buildSheetBadge(
                    context,
                    'meals_count'
                        .trParams({'count': (user['count'] ?? 0).toString()}),
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildSheetBadge(
                    context,
                    'meal_paid_val'.trParams({
                      'val': (user['expense'] as num? ?? 0).toStringAsFixed(1)
                    }),
                    Colors.teal,
                  ),
                  const SizedBox(width: 8),
                  _buildSheetBadge(
                    context,
                    'other_paid_val'.trParams({
                      'val':
                          (user['other_expense'] as num? ?? 0).toStringAsFixed(1)
                    }),
                    Colors.orange,
                  ),
                ],
              ),
            ),
            if (canAdminEdit)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _tint(context, Colors.blue),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.blue.withOpacity(0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.admin_panel_settings_rounded,
                          size: 16, color: _accentOn(context, Colors.blue)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'admin_edit_hint'.trParams({'name': userName}),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: _accentOn(context, Colors.blue),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TableCalendar(
                      firstDay: controller.firstDay,
                      lastDay: controller.lastDay,
                      focusedDay: controller.focusedDay,
                      rowHeight: 44,
                      daysOfWeekHeight: 26,
                      availableGestures: canAdminEdit
                          ? AvailableGestures.all
                          : AvailableGestures.none,
                      onDaySelected: canAdminEdit
                          ? (selected, focused) {
                              controller.showAdminUpdateMealBottomSheet(
                                  selected, userName, user['phone']);
                            }
                          : null,
                      headerStyle: HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        leftChevronVisible: false,
                        rightChevronVisible: false,
                        headerPadding: const EdgeInsets.only(bottom: 8),
                        titleTextStyle:
                            Theme.of(context).textTheme.titleMedium!,
                      ),
                      daysOfWeekStyle: DaysOfWeekStyle(
                        weekdayStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _mutedColor(context),
                        ),
                        weekendStyle: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: Colors.red.withOpacity(0.7),
                        ),
                      ),
                      calendarStyle: CalendarStyle(
                        cellMargin: const EdgeInsets.all(4),
                        todayDecoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.15),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Theme.of(context).colorScheme.primary,
                              width: 1.4),
                        ),
                        todayTextStyle: TextStyle(
                          color: _isDark(context)
                              ? Colors.white
                              : Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                        defaultTextStyle:
                            Theme.of(context).textTheme.bodyMedium!,
                        outsideTextStyle: TextStyle(
                          color: _mutedColor(context).withOpacity(0.35),
                        ),
                        markersMaxCount: 1,
                      ),
                      calendarBuilders: CalendarBuilders(
                        headerTitleBuilder: (context, day) => Center(
                          child: Text(
                            _monthLabel(day),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        markerBuilder: (context, date, events) {
                          final String dateKey = _dateKeyOf(date);
                          if (!userDailyMeals.containsKey(dateKey)) {
                            return const SizedBox.shrink();
                          }
                          return Positioned(
                            bottom: 1,
                            child:
                                _mealMarker(context, userDailyMeals[dateKey]!),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 8),
                    Divider(height: 1, color: _hairline(context)),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long_rounded,
                              size: 20, color: _accentOn(context, Colors.amber)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'expenses_breakdown'.tr,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.bold),
                            ),
                          ),
                          if (userExpenses.isNotEmpty)
                            Text(
                              '${userExpenses.length}',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                                color: _mutedColor(context),
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (userExpenses.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 32),
                        child: Column(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: _neutralSurface(context),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(Icons.receipt_long_outlined,
                                  size: 32, color: _mutedColor(context)),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'no_expenses_recorded'.tr,
                              style: TextStyle(
                                  color: _mutedColor(context), fontSize: 13),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: userExpenses.length,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final item = userExpenses[index];
                          final bool isMealExpense = item.type == 'expense';
                          final MaterialColor typeColor =
                              isMealExpense ? Colors.blue : Colors.orange;

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: _neutralSurface(context),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: _hairline(context)),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(9),
                                  decoration: BoxDecoration(
                                    color: _tint(context, typeColor),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Icon(
                                    isMealExpense
                                        ? Icons.shopping_cart_outlined
                                        : Icons.miscellaneous_services_outlined,
                                    color: _accentOn(context, typeColor),
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.description,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                          color: _bodyColor(context),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(
                                            DateFormat('dd MMM')
                                                .format(item.date),
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: _mutedColor(context),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Container(
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 6,
                                                    vertical: 2),
                                            decoration: BoxDecoration(
                                              color: _tint(context, typeColor),
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                            ),
                                            child: Text(
                                              item.type.toUpperCase(),
                                              style: TextStyle(
                                                fontSize: 8,
                                                fontWeight: FontWeight.bold,
                                                color: _accentOn(
                                                    context, typeColor),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  '৳${item.amount.toStringAsFixed(1)}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: Colors.red,
                                  ),
                                ),
                                if (canAdminEdit)
                                  PopupMenuButton<String>(
                                    icon: Icon(Icons.more_vert,
                                        size: 20, color: _mutedColor(context)),
                                    onSelected: (value) {
                                      if (value == 'update') {
                                        _showExpenseBottomSheet(context,
                                            item: item);
                                      } else if (value == 'delete') {
                                        _confirmDeleteExpense(
                                            context, item, userName);
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      PopupMenuItem(
                                          value: 'update',
                                          child: Text('update'.tr)),
                                      PopupMenuItem(
                                          value: 'delete',
                                          child: Text('delete'.tr,
                                              style: const TextStyle(
                                                  color: Colors.red))),
                                    ],
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  void _confirmDeleteExpense(
      BuildContext context, ExpenseModel item, String userName) {
    showConfirmDialog(
      title: 'delete_expense'.tr,
      message: 'confirm_delete_expense_for'.trParams({'name': userName}),
      detail: item.description,
      confirmText: 'delete'.tr,
      onConfirm: () {
        if (Get.isRegistered<ExpenseController>()) {
          Get.find<ExpenseController>().deleteExpense(item);
        }
      },
    );
  }

  void _showMealBreakdownDialog(
      BuildContext context, String title, String dateKey) {
    // Show every member for the day, including those with 0 meals.
    final List<Map<String, dynamic>> allMembers = [
      {'name': 'me_you'.tr, 'count': controller.dailyMeals[dateKey] ?? 0},
      ...controller.otherUsersMeals.map((u) {
        final dayMeals = controller.userDailyMeals[dateKey] ?? [];
        final userMeal = dayMeals.firstWhere((m) => m['name'] == u['name'],
            orElse: () => {'count': 0});
        return {
          'name': u['name'],
          'count': userMeal['count'],
        };
      }),
    ];

    final int dayTotal = allMembers.fold<int>(
        0, (running, m) => running + ((m['count'] as int?) ?? 0));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
        contentPadding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: _tint(context, Colors.blue),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.pie_chart_rounded,
                  size: 18, color: _accentOn(context, Colors.blue)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'breakdown_title'.trParams({'title': title}),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'meals_count'.trParams({'count': dayTotal.toString()}),
                    style: TextStyle(
                        fontSize: 12, color: _mutedColor(context)),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: allMembers.length,
            separatorBuilder: (context, index) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final member = allMembers[index];
              final count = member['count'] as int;
              final String name = member['name'] ?? 'unknown'.tr;
              final bool hasMeal = count > 0;
              final MaterialColor color = hasMeal ? Colors.teal : Colors.red;

              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: _neutralSurface(context),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _hairline(context)),
                ),
                child: Row(
                  children: [
                    _avatar(context, name, index == 0 ? Colors.teal : Colors.blue,
                        isMe: index == 0, size: 32),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _bodyColor(context),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      hasMeal
                          ? 'meals_count'.trParams({'count': count.toString()})
                          : 'no_meal'.tr,
                      style: TextStyle(
                        fontSize: 13,
                        color: _accentOn(context, color),
                        fontWeight:
                            hasMeal ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('close'.tr),
          ),
        ],
      ),
    );
  }
}

/// ---------------------------------------------------------------------------
/// Loading placeholders — a gentle pulse beats an empty screen or a spinner
/// that hides the layout the user is about to see.
/// ---------------------------------------------------------------------------

class _PulseBox extends StatefulWidget {
  final double? width;
  final double height;
  final double radius;

  const _PulseBox({this.width, this.height = 14, this.radius = 8});

  @override
  State<_PulseBox> createState() => _PulseBoxState();
}

class _PulseBoxState extends State<_PulseBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = _isDark(context) ? Colors.white : Colors.black;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 0.8).animate(
        CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
      ),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: base.withOpacity(0.10),
          borderRadius: BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

class _CardSkeleton extends StatelessWidget {
  const _CardSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _hairline(context)),
      ),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _PulseBox(width: 42, height: 42, radius: 21),
              SizedBox(width: 12),
              Expanded(child: _PulseBox(height: 16)),
              SizedBox(width: 12),
              _PulseBox(width: 64, height: 24, radius: 12),
            ],
          ),
          SizedBox(height: 20),
          Row(
            children: [
              Expanded(child: _PulseBox(height: 12)),
              SizedBox(width: 16),
              Expanded(child: _PulseBox(height: 12)),
            ],
          ),
          SizedBox(height: 14),
          _PulseBox(height: 40, radius: 14),
        ],
      ),
    );
  }
}
