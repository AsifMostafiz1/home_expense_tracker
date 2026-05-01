import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../common/widgets/custom_app_bar.dart';
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
                        defaultTextStyle: Theme.of(context).textTheme.bodyMedium!,
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
                          } else if (count >= 2) {
                            bgColor = Colors.orange.shade100;
                            textColor = Colors.orange.shade800;
                          } else {
                            bgColor = Colors.teal.shade100;
                            textColor = Colors.teal.shade800;
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
                          style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                              expense:
                                  entry.value['expense'] as double? ?? 0.0,
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
                fontSize: 24, color: color.shade800, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoColumn(BuildContext context, String label, String value,
      Color color, {bool isBalance = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
              fontSize: isBalance ? 13 : 14,
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
    String balanceLabel = balance >= 0 ? 'Will Get' : 'To Give';
    String balanceValue = '৳${balance.abs().toStringAsFixed(2)}';
    Color balanceColor =
        balance >= 0 ? Colors.teal.shade700 : Colors.red.shade700;

    return Container(
      padding: const EdgeInsets.all(20),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color.shade600, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Meals: $count',
                      style: TextStyle(
                          fontSize: 18,
                          color: color.shade800,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildInfoColumn(context, 'Expense',
                  '৳${expense.toStringAsFixed(2)}', color.shade800),
              if (isTotal)
                _buildInfoColumn(context, 'Avg Rate',
                    '৳${rate.toStringAsFixed(2)}', color.shade800)
              else ...[
                _buildInfoColumn(context, 'Cost', '৳${cost.toStringAsFixed(2)}',
                    color.shade800),
                _buildInfoColumn(context, balanceLabel, balanceValue,
                    balanceColor, isBalance: true),
              ]
            ],
          ),
        ],
      ),
    );
  }
}
