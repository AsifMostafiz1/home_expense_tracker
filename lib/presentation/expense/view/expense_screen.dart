import 'package:flutter/material.dart';
import 'package:get/get.dart';
import '../../../common/widgets/custom_app_bar.dart';
import '../controller/expense_controller.dart';
import '../model/expense_model.dart';
import '../widgets/expense_bottom_sheet.dart';

class ExpenseScreen extends GetView<ExpenseController> {
  const ExpenseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // Controller is provided via ExpenseBinding

    return Scaffold(
      appBar: const CustomAppBar(title: 'Expense'),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          controller.clearForm();
          _showExpenseBottomSheet(context);
        },
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: GetBuilder<ExpenseController>(
        builder: (controller) {
          if (controller.isLoading && controller.expenses.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return RefreshIndicator(
            onRefresh: () => controller.fetchExpenses(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                // Current Month Total Card
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.primary.withOpacity(0.75),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.3),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  width: double.infinity,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Current Month Expense',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '\$${controller.currentMonthTotal.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ),
                ),

                // Expenses List
                controller.groupedExpenses.isEmpty
                    ? SizedBox(
                        height: 200,
                        child: Center(
                          child: Text(
                            'No expenses found for this month',
                            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: Theme.of(context).hintColor,
                                ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 16),
                        itemCount: controller.groupedExpenses.keys.length,
                        itemBuilder: (context, index) {
                          String dateKey =
                              controller.groupedExpenses.keys.elementAt(index);
                          List<ExpenseModel> items =
                              controller.groupedExpenses[dateKey]!;

                          double totalAmount = items.fold(0, (sum, item) {
                            return sum + item.amount;
                          });

                          double displayTotal = totalAmount.abs();

                          return Container(
                            margin: const EdgeInsets.only(bottom: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Group Header
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 8),
                                  child: Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        dateKey,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      Text(
                                        'Total: $displayTotal',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),

                                // Group Items
                                Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).cardColor,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.03),
                                        blurRadius: 10,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    children: items.asMap().entries.map((entry) {
                                      int idx = entry.key;
                                      ExpenseModel item = entry.value;
                                      bool isLast = idx == items.length - 1;

                                      String formattedTime =
                                          item.time.format(context);

                                      return Column(
                                        children: [
                                          ListTile(
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 16, vertical: 4),
                                            leading: Container(
                                              padding: const EdgeInsets.all(8),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50,
                                                shape: BoxShape.circle,
                                              ),
                                              child: const Icon(
                                                Icons.remove,
                                                color: Colors.red,
                                                size: 16,
                                              ),
                                            ),
                                            title: Text(
                                              item.description,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
                                            subtitle: Text(
                                              formattedTime,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                            trailing: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  '${item.amount}',
                                                  style: const TextStyle(
                                                    fontSize: 16,
                                                    fontWeight: FontWeight.bold,
                                                    color: Colors.red,
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                PopupMenuButton<String>(
                                                  onSelected: (value) {
                                                    if (value == 'update') {
                                                      _showExpenseBottomSheet(
                                                          context,
                                                          item: item);
                                                    } else if (value ==
                                                        'delete') {
                                                      _showDeleteConfirmation(
                                                          context, item);
                                                    }
                                                  },
                                                  itemBuilder: (context) => [
                                                    const PopupMenuItem(
                                                      value: 'update',
                                                      child: Text('Update'),
                                                    ),
                                                    const PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text('Delete'),
                                                    ),
                                                  ],
                                                  icon: const Icon(Icons.more_vert,
                                                      color: Colors.black54),
                                                ),
                                              ],
                                            ),
                                          ),
                                          if (!isLast)
                                            const Divider(
                                                height: 1,
                                                indent: 16,
                                                endIndent: 16),
                                        ],
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, ExpenseModel item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Expense'),
        content: const Text('Are you sure you want to delete this item?'),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              controller.deleteExpense(item.id);
            },
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _showExpenseBottomSheet(BuildContext context, {ExpenseModel? item}) {
    if (item != null) {
      controller.amountController.text = item.amount.toString();
      controller.descriptionController.text = item.description;
      controller.selectedDate = item.date;
      controller.selectedTime = item.time;
      controller.update(); // Manual update to reflect date/time change in UI
    } else {
      controller.clearForm();
    }

    Get.bottomSheet(
      ExpenseBottomSheet(item: item),
      isScrollControlled: true,
    );
  }
}

