import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../controller/meal_controller.dart';

class MealScreen extends GetView<MealController> {
  const MealScreen({super.key});

  @override
  Widget build(BuildContext context) {
    Get.put(MealController());

    return Scaffold(
      appBar: const CustomAppBar(
        title: 'Meal Calendar',
      ),
      backgroundColor: Colors.grey[50],
      body: SingleChildScrollView(
        child: Column(
          children: [
          Container(
            margin: const EdgeInsets.all(16),
            padding: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Obx(() {
              // Track dailyMeals to trigger rebuild when data is loaded
              // ignore: unused_local_variable
              final tracker = controller.dailyMeals.length;
              
              return TableCalendar(
                firstDay: controller.firstDay,
                lastDay: controller.lastDay,
                focusedDay: controller.focusedDay.value,
                selectedDayPredicate: (day) => isSameDay(controller.selectedDay.value, day),
                onDaySelected: controller.onDaySelected,
              onPageChanged: controller.onPageChanged,
              headerStyle: const HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
              ),
              calendarStyle: CalendarStyle(
                todayDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                  shape: BoxShape.circle,
                ),
                selectedDecoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
              calendarBuilders: CalendarBuilders(
                markerBuilder: (context, date, events) {
                  String dateKey = '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
                  
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
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
            );
          }),
          ),
          Obx(() {
              // Ensure we track monthly stats
              final _ = controller.isFetchingStats.value;
              
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (controller.canAddBulkMeal) ...[
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: () => controller.addBulkMeal(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: Obx(() => controller.isLoading.value 
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                              )
                            : const Text('Add bulk Meal', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                    
                    const Text(
                      'Monthly Summary',
                      style: TextStyle(
                        fontSize: 18, 
                        fontWeight: FontWeight.bold, 
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _buildSummaryCard(
                      'My Meals', 
                      controller.myMealCount.value, 
                      Colors.teal, 
                      Icons.person,
                    ),
                    const SizedBox(height: 12),
                    ...controller.otherUsersMeals.asMap().entries.map((entry) {
                      final colors = [Colors.orange, Colors.purple, Colors.pink, Colors.blue, Colors.amber];
                      final color = colors[entry.key % colors.length];
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildSummaryCard(
                          entry.value['name'] ?? 'Unknown', 
                          entry.value['count'] as int, 
                          color, 
                          Icons.person_outline,
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                    _buildSummaryCard(
                      'Total Monthly Meals', 
                      controller.totalMealCount.value, 
                      Colors.indigo, 
                      Icons.restaurant,
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              );
            }),
        ],
        ),
      ),
    );
  }

  Widget _buildSmallSummaryCard(String title, int count, MaterialColor color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
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
            style: const TextStyle(fontSize: 13, color: Colors.black54, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          Text(
            '$count',
            style: TextStyle(fontSize: 24, color: color.shade800, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String title, int count, MaterialColor color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
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
      child: Row(
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
                  style: const TextStyle(fontSize: 14, color: Colors.black54, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 4),
                Text(
                  '$count',
                  style: TextStyle(fontSize: 28, color: color.shade800, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
