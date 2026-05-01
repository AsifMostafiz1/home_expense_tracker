import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../controller/meal_controller.dart';

class MealScreen extends GetView<MealController> {
  const MealScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Controller is provided via MealBinding

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Meal Calendar',
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showShoppingListBottomSheet(context),
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.shopping_cart, color: Colors.white),
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
                            title: "Today's Total",
                            count: controller.getTodayTotal(),
                            color: Colors.blue,
                            icon: Icons.today,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _buildQuickStatCard(
                            context,
                            title: "Tomorrow's Total",
                            count: controller.getTomorrowTotal(),
                            color: Colors.orange,
                            icon: Icons.event,
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
                            textColor =
                                Colors.amber.shade900; // Yellowish color
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
                                  : const Text('Add bulk Meal',
                                      style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold)),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                        Text(
                          'Monthly Summary',
                          style:
                              Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 16),
                        _buildSummaryCard(
                          context,
                          title: 'Total Monthly Stats',
                          count: controller.totalMealCount,
                          expense: controller.totalMonthlyExpense,
                          rate: controller.avgMealRate,
                          color: Colors.indigo,
                          icon: Icons.restaurant,
                          isTotal: true,
                        ),
                        const SizedBox(height: 12),
                        _buildSummaryCard(
                          context,
                          title: 'My Meals',
                          count: controller.myMealCount,
                          expense: controller.myMonthlyExpense,
                          rate: controller.avgMealRate,
                          color: Colors.teal,
                          icon: Icons.person,
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
                              title: entry.value['name'] ?? 'Unknown',
                              count: entry.value['count'] as int,
                              expense: entry.value['expense'] as double? ?? 0.0,
                              rate: controller.avgMealRate,
                              color: color,
                              icon: Icons.person_outline,
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
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
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
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w500,
                        fontSize: 10,
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
              ],
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
                color: Colors.grey.shade600,
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
    required double rate,
    required MaterialColor color,
    required IconData icon,
    bool isTotal = false,
  }) {
    double cost = count * rate;
    double balance = expense - cost;
    String balanceLabel = balance >= 0 ? 'WILL GET' : 'TO GIVE';
    String balanceValue = '৳${balance.abs().toStringAsFixed(2)}';
    Color balanceColor = balance >= 0 ? Colors.teal : Colors.red;

    return Container(
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
          // Subtle side accent
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 6, color: color.shade400),
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
                        color: color.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(icon, color: color.shade600, size: 24),
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
                              'Member Stats',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: Colors.grey.shade500,
                                  ),
                            ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: color.shade600,
                        borderRadius: BorderRadius.circular(30),
                      ),
                      child: Text(
                        '$count Meals',
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
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _buildInfoColumn(context, 'EXPENSE',
                        '৳${expense.toStringAsFixed(1)}', Colors.black87),
                    if (isTotal)
                      _buildInfoColumn(context, 'AVG RATE',
                          '৳${rate.toStringAsFixed(2)}', color.shade700)
                    else ...[
                      _buildInfoColumn(context, 'COST',
                          '৳${cost.toStringAsFixed(1)}', Colors.black87),
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
    );
  }

  Widget _buildAnnouncement(BuildContext context) {
    if (controller.isShoppingListDismissed ||
        controller.shoppingListText == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.amber.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.amber.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.amber.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          )
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.amber.shade100,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.campaign, color: Colors.amber, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (controller.shoppingListUpdatedAt != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      'Updated: ${DateFormat('dd MMM, hh:mm a').format(controller.shoppingListUpdatedAt!)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                Text(
                  controller.shoppingListText!,
                  style: const TextStyle(
                    color: Colors.black87,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => controller.dismissShoppingList(),
            icon: Icon(Icons.close, color: Colors.grey.shade600, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  void _showShoppingListBottomSheet(BuildContext context) {
    if (controller.shoppingListText != null) {
      controller.shoppingListController.text = controller.shoppingListText!;
    }

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
              'List of item to Buy',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 24),
            CustomTextField(
              controller: controller.shoppingListController,
              hintText: 'Enter items to buy...',
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => controller.submitShoppingList(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Submit',
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
}
