import 'package:cloud_firestore/cloud_firestore.dart';
import '../../expense/model/expense_model.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../controller/meal_controller.dart';
import 'announcement_history_screen.dart';

class MealScreen extends GetView<MealController> {
  const MealScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Controller is provided via MealBinding

    return Scaffold(
      appBar: CustomAppBar(
        title: 'meal'.tr,
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showAnnouncementBottomSheet(context),
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.campaign, color: Colors.white),
      ),
      body: GetBuilder<MealController>(
        builder: (controller) {
          return RefreshIndicator(
            onRefresh: () async {
              await controller.fetchMeals();
              await controller.fetchMonthlyStats();
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              child: Column(
                children: [
                  _buildAnnouncement(context),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: _buildQuickStatCard(
                            context,
                            title: "today_total".tr,
                            count: controller.getTodayTotal(),
                            color: Colors.blue,
                            icon: Icons.today,
                            onInfoPressed: () {
                              final now = DateTime.now();
                              String dateKey =
                                  '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
                              _showMealBreakdownDialog(context, "today".tr, dateKey);
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildQuickStatCard(
                            context,
                            title: "tomorrow_total".tr,
                            count: controller.getTomorrowTotal(),
                            color: Colors.orange,
                            icon: Icons.event,
                            onInfoPressed: () {
                              final tomorrow =
                                  DateTime.now().add(const Duration(days: 1));
                              String dateKey =
                                  '${tomorrow.year}-${tomorrow.month.toString().padLeft(2, '0')}-${tomorrow.day.toString().padLeft(2, '0')}';
                              _showMealBreakdownDialog(
                                  context, "tomorrow".tr, dateKey);
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.all(16),
                    padding: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: TableCalendar(
                      firstDay: controller.firstDay,
                      lastDay: controller.lastDay,
                      focusedDay: controller.focusedDay,
                      availableGestures: AvailableGestures.none,
                      selectedDayPredicate: (day) =>
                          isSameDay(controller.selectedDay, day),
                      onDaySelected: controller.onDaySelected,
                      onPageChanged: controller.onPageChanged,
                      headerStyle: HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        titleTextStyle: Theme.of(context).textTheme.titleLarge!,
                      ),
                      calendarStyle: CalendarStyle(
                        todayDecoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        selectedDecoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary,
                          shape: BoxShape.circle,
                        ),
                        defaultTextStyle:
                            Theme.of(context).textTheme.bodyMedium!,
                        weekendTextStyle: Theme.of(context)
                            .textTheme
                            .bodyMedium!
                            .copyWith(color: Colors.red),
                      ),
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, date, events) {
                          String dateKey =
                              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

                          if (!controller.dailyMeals.containsKey(dateKey)) {
                            return const SizedBox.shrink();
                          }

                          int count = controller.dailyMeals[dateKey]!;

                          Color bgColor;
                          Color textColor;

                          if (count == 0) {
                            bgColor = Colors.red.withOpacity(0.2);
                            textColor = Colors.red.shade400;
                          } else if (count == 1) {
                            bgColor = Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.2);
                            textColor = Theme.of(context).colorScheme.primary;
                          } else {
                            bgColor = Colors.amber.withOpacity(0.2);
                            textColor = Colors.amber.shade400;
                          }

                          return Positioned(
                            bottom: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (controller.canAddBulkMeal) ...[
                          SizedBox(
                            width: double.infinity,
                            height: 50,
                            child: ElevatedButton(
                              onPressed: controller.isLoading
                                  ? null
                                  : () => controller.addBulkMeal(),
                              style: ElevatedButton.styleFrom(
                                backgroundColor:
                                    Theme.of(context).colorScheme.primary,
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: controller.isLoading
                                  ? const SizedBox(
                                      height: 20,
                                      width: 20,
                                      child: CircularProgressIndicator(
                                          color: Colors.white, strokeWidth: 2),
                                    )
                                  : Text('add_bulk_meal'.tr,
                                      style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Text(
                          'monthly_summary'.tr,
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryCard(
                          context,
                          title: 'total_monthly_stats'.tr,
                          count: controller.totalMealCount,
                          expense: controller.totalMonthlyExpense,
                          otherExpense: controller.totalOtherExpense,
                          rate: controller.avgMealRate,
                          otherRate: controller.totalOtherExpense, // For total card, we show the total other expense as the rate placeholder or similar
                          color: Colors.indigo,
                          icon: Icons.restaurant,
                          isTotal: true,
                        ),
                        const SizedBox(height: 12),
                        _buildSummaryCard(
                          context,
                          title: 'my_meals'.tr,
                          count: controller.myMealCount,
                          expense: controller.myMonthlyExpense,
                          otherExpense: controller.myOtherExpense,
                          rate: controller.avgMealRate,
                          otherRate: controller.otherCostPerPerson,
                          color: Colors.teal,
                          icon: Icons.person,
                          onCountPressed: () => _showUserCalendarBottomSheet(context, {
                            'name': 'me_you'.tr,
                            'count': controller.myMealCount,
                            'daily_meals': controller.dailyMeals,
                            'expenses': controller.myExpenses,
                            'expense': controller.myMonthlyExpense,
                            'other_expense': controller.myOtherExpense,
                          }),
                        ),
                        const SizedBox(height: 12),
                        ...controller.otherUsersMeals
                            .asMap()
                            .entries
                            .map((entry) {
                          final colors = [
                            Colors.orange,
                            Colors.purple,
                            Colors.pink,
                            Colors.blue,
                            Colors.amber
                          ];
                          final color = colors[entry.key % colors.length];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildSummaryCard(
                              context,
                              title: entry.value['name'] ?? 'unknown'.tr,
                              count: entry.value['count'] as int,
                              expense: entry.value['expense'] as double? ?? 0.0,
                              otherExpense: entry.value['other_expense'] as double? ?? 0.0,
                              rate: controller.avgMealRate,
                              otherRate: controller.otherCostPerPerson,
                              color: color,
                              icon: Icons.person_outline,
                              onCountPressed: () =>
                                  _showUserCalendarBottomSheet(context, entry.value),
                            ),
                          );
                        }),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildQuickStatCard(
    BuildContext context, {
    required String title,
    required int count,
    required Color color,
    required IconData icon,
    VoidCallback? onInfoPressed,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 14),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
        border: Border.all(color: color.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 9,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
          if (onInfoPressed != null)
            GestureDetector(
              onTap: onInfoPressed,
              child: Icon(
                Icons.info_outline,
                size: 16,
                color: color.withOpacity(0.6),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSmallSummaryCard(BuildContext context, String title, int count,
      MaterialColor color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.shade100),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color.shade600, size: 20),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w500,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: TextStyle(
                fontSize: 24,
                color: color.shade800,
                fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(
      BuildContext context, String label, String value, Color color,
      {bool isBalance = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.6),
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
              fontSize: isBalance ? 15 : 16,
              color: color,
              fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(
    BuildContext context, {
    required String title,
    required int count,
    required double expense,
    double otherExpense = 0.0,
    required double rate,
    required double otherRate,
    required MaterialColor color,
    required IconData icon,
    bool isTotal = false,
    VoidCallback? onCountPressed,
  }) {
    double mealCost = count * rate;
    double totalCost = mealCost + otherRate;
    double totalPaid = expense + otherExpense;
    double balance = totalPaid - totalCost;
    
    String balanceLabel = balance >= 0 ? 'will_get'.tr : 'to_give'.tr;
    String balanceValue = '৳${balance.abs().toStringAsFixed(2)}';
    Color balanceColor = balance >= 0 ? Colors.teal : Colors.red;

    return GestureDetector(
      onTap: onCountPressed,
      child: Container(
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 20,
              offset: const Offset(0, 10),
            )
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 6, color: color),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: -0.2,
                                ),
                          ),
                          if (!isTotal)
                            Text(
                              'member_stats'.tr,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.5),
                                  ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        'meals_count'.trParams({'count': count.toString()}),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(height: 1),
                const SizedBox(height: 20),
                
                // Expenses row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildInfoColumn(context, 'meal_paid'.tr,
                        '৳${expense.toStringAsFixed(1)}', Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87),
                    _buildInfoColumn(context, 'other_paid'.tr,
                        '৳${otherExpense.toStringAsFixed(1)}', Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87),
                    if (isTotal)
                      _buildInfoColumn(context, 'meal_rate'.tr,
                          '৳${rate.toStringAsFixed(2)}', color)
                    else
                      _buildInfoColumn(context, 'meal_cost'.tr,
                          '৳${mealCost.toStringAsFixed(1)}', Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87),
                  ],
                ),
                const SizedBox(height: 16),
                
                // Costs row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    if (isTotal) ...[
                       _buildInfoColumn(context, 'other_rate'.tr,
                          '৳${otherRate.toStringAsFixed(2)}', color),
                       const SizedBox(width: 20),
                       _buildInfoColumn(context, 'total_users'.tr,
                          '${controller.userCount}', Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87),
                    ] else ...[
                       _buildInfoColumn(context, 'other_cost'.tr,
                          '৳${otherRate.toStringAsFixed(1)}', Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            balanceLabel,
                            style: TextStyle(
                              color: balanceColor,
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            balanceValue,
                            style: TextStyle(
                              color: balanceColor,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
   );
  }

  Widget _buildAnnouncement(BuildContext context) {
    if (controller.announcements.isEmpty) {
      return const SizedBox.shrink();
    }

    final latest = controller.announcements.first;
    final text = latest['text'] ?? '';
    final userName = latest['user_name'] ?? 'unknown'.tr;
    final updatedAt = latest['updatedAt'];

    DateTime? date;
    if (updatedAt is Timestamp) {
      date = updatedAt.toDate();
    } else if (updatedAt is String) {
      date = DateTime.parse(updatedAt);
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.campaign, color: Colors.amber, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (date != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.amber,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat('dd MMM, hh:mm a').format(date!),
                              style: TextStyle(
                                fontSize: 11,
                                color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.7),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    Text(
                      text,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black87,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (controller.announcements.length > 1) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => Get.to(() => const AnnouncementHistoryScreen()),
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(
                  'see_more'.tr,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.amber,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _showAnnouncementBottomSheet(BuildContext context) {
    // We don't need to populate the controller with existing text anymore 
    // since every submission is a NEW announcement.
    controller.announcementController.clear();

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'announcement'.tr,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 24),
            CustomTextField(
              controller: controller.announcementController,
              hintText: 'enter_announcement'.tr,
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => controller.submitAnnouncement(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  'submit'.tr,
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Colors.white),
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
      isScrollControlled: true,
    );
  }

  Widget _buildSheetBadge(BuildContext context, String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  void _showUserCalendarBottomSheet(
      BuildContext context, Map<String, dynamic> user) {
    final Map<String, int> userDailyMeals =
        Map<String, int>.from(user['daily_meals'] ?? {});
    final String userName = user['name'] ?? 'User';
    final List<ExpenseModel> userExpenses =
        List<ExpenseModel>.from(user['expenses'] ?? []);

    Get.bottomSheet(
      Container(
        padding: const EdgeInsets.only(top: 24),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.65,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'summary_of'.trParams({'name': userName}),
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildSheetBadge(
                    context,
                    'meals_count'.trParams({'count': (user['count'] ?? 0).toString()}),
                    Colors.blue,
                  ),
                  const SizedBox(width: 8),
                  _buildSheetBadge(
                    context,
                    'meal_paid_val'.trParams({'val': (user['expense'] as num? ?? 0).toStringAsFixed(1)}),
                    Colors.teal,
                  ),
                  const SizedBox(width: 8),
                  _buildSheetBadge(
                    context,
                    'other_paid_val'.trParams({'val': (user['other_expense'] as num? ?? 0).toStringAsFixed(1)}),
                    Colors.orange,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    TableCalendar(
                      firstDay: controller.firstDay,
                      lastDay: controller.lastDay,
                      focusedDay: controller.focusedDay,
                      availableGestures: AvailableGestures.none,
                      headerStyle: HeaderStyle(
                        formatButtonVisible: false,
                        titleCentered: true,
                        leftChevronVisible: false,
                        rightChevronVisible: false,
                        titleTextStyle:
                            Theme.of(context).textTheme.titleMedium!,
                      ),
                      calendarStyle: CalendarStyle(
                        todayDecoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withOpacity(0.3),
                          shape: BoxShape.circle,
                        ),
                        defaultTextStyle:
                            Theme.of(context).textTheme.bodyMedium!,
                      ),
                      calendarBuilders: CalendarBuilders(
                        markerBuilder: (context, date, events) {
                          String dateKey =
                              '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

                          if (!userDailyMeals.containsKey(dateKey)) {
                            return const SizedBox.shrink();
                          }

                          int count = userDailyMeals[dateKey]!;

                          Color bgColor;
                          Color textColor;

                          if (count == 0) {
                            bgColor = Colors.red.shade100;
                            textColor = Colors.red.shade800;
                          } else if (count == 1) {
                            bgColor = Theme.of(context)
                                .colorScheme
                                .primary
                                .withOpacity(0.1);
                            textColor = Theme.of(context).colorScheme.primary;
                          } else {
                            bgColor = Colors.amber.shade100;
                            textColor = Colors.amber.shade900;
                          }

                          return Positioned(
                            bottom: 2,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: bgColor,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: textColor,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Divider(),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Icon(Icons.receipt_long_outlined,
                              color: Colors.amber.shade900),
                          const SizedBox(width: 12),
                          Text(
                            "expenses_breakdown".tr,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
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
                            Icon(Icons.money_off,
                                size: 48, color: Colors.grey.shade300),
                            const SizedBox(height: 8),
                            Text(
                              "no_expenses_recorded".tr,
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: userExpenses.length,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final item = userExpenses[index];
                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: item.type == 'expense'
                                        ? Colors.blue.shade50
                                        : Colors.orange.shade50,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    item.type == 'expense'
                                        ? Icons.shopping_cart_outlined
                                        : Icons.miscellaneous_services_outlined,
                                    color: item.type == 'expense'
                                        ? Colors.blue.shade700
                                        : Colors.orange.shade700,
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
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      Text(
                                        "${DateFormat('dd MMM').format(item.date)} • ${item.type.toUpperCase()}",
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Text(
                                  "৳${item.amount.toStringAsFixed(1)}",
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15,
                                    color: Colors.red,
                                  ),
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

  void _showMealBreakdownDialog(
      BuildContext context, String title, String dateKey) {
    // Get all members from controller stats to ensure we show those with 0 meals too
    // Combine current user and other users
    final List<Map<String, dynamic>> allMembers = [
      {'name': 'me_you'.tr, 'count': controller.dailyMeals[dateKey] ?? 0},
      ...controller.otherUsersMeals.map((u) {
        // Find their count for this specific day in userDailyMeals
        final dayMeals = controller.userDailyMeals[dateKey] ?? [];
        final userMeal = dayMeals.firstWhere(
            (m) => m['name'] == u['name'],
            orElse: () => {'count': 0});
        return {
          'name': u['name'],
          'count': userMeal['count'],
        };
      }),
    ];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('breakdown_title'.trParams({'title': title})),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: allMembers.length,
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              final member = allMembers[index];
              final count = member['count'] as int;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(member['name'] ?? 'Unknown',
                    style: const TextStyle(fontSize: 14)),
                trailing: Text(
                  count > 0 ? 'meals_count'.trParams({'count': count.toString()}) : 'no_meal'.tr,
                  style: TextStyle(
                    fontSize: 14,
                    color: count > 0 ? Colors.teal : Colors.red,
                    fontWeight: count > 0 ? FontWeight.bold : FontWeight.normal,
                  ),
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
