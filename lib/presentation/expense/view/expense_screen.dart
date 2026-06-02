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

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: CustomAppBar(
          title: 'expense'.tr,
          bottom: TabBar(
            onTap: (index) => controller.setMonthIndex(index),
            tabs: [
              Tab(text: 'current_month'.tr),
              Tab(text: 'next_month'.tr),
            ],
            indicatorColor: Theme.of(context).colorScheme.primary,
            labelColor: Theme.of(context).colorScheme.primary,
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
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
                        'monthly_expense'.trParams({'month': controller.selectedMonthName}),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.5,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '৳${controller.displayTotal.toStringAsFixed(1)}',
                                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              Text(
                                'total_paid'.tr,
                                style: const TextStyle(color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              _buildCardStat(context, 'meal'.tr, controller.mealTotal),
                              const SizedBox(height: 4),
                              _buildCardStat(context, 'others'.tr, controller.othersTotal),
                            ],
                          ),
                        ],
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
                            'no_expenses_found'.trParams({'month': controller.selectedMonthName}),
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
                                        'total'.tr + ': $displayTotal',
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
                                                color: Colors.red.withOpacity(0.1),
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
                                            subtitle: Row(
                                              children: [
                                                Text(
                                                  formattedTime,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall,
                                                ),
                                                const SizedBox(width: 8),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: item.type == 'expense' ? Colors.blue.withOpacity(0.1) : Colors.orange.withOpacity(0.1),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    item.type.toUpperCase(),
                                                    style: TextStyle(
                                                      fontSize: 8,
                                                      fontWeight: FontWeight.bold,
                                                      color: item.type == 'expense' ? Colors.blue.shade400 : Colors.orange.shade400,
                                                    ),
                                                  ),
                                                ),
                                              ],
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
                                                    PopupMenuItem(
                                                      value: 'update',
                                                      child: Text('update'.tr),
                                                    ),
                                                    PopupMenuItem(
                                                      value: 'delete',
                                                      child: Text('delete'.tr),
                                                    ),
                                                  ],
                                                  icon: Icon(Icons.more_vert,
                                                      color: Theme.of(context).textTheme.bodySmall?.color),
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
    ),
  );
}

  Widget _buildCardStat(BuildContext context, String label, double amount) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          '৳${amount.toStringAsFixed(1)}',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  void _showDeleteConfirmation(BuildContext context, ExpenseModel item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('delete_expense'.tr),
        content: Text('confirm_delete'.tr),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: Text('cancel'.tr),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              controller.deleteExpense(item);
            },
            child: Text('delete'.tr, style: const TextStyle(color: Colors.red)),
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
      controller.selectedType = item.type;
      controller.update(); // Manual update to reflect changes in UI
    } else {
      controller.clearForm();
    }

    Get.bottomSheet(
      ExpenseBottomSheet(item: item),
      isScrollControlled: true,
    );
  }
}

