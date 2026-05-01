import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../controller/expense_controller.dart';
import '../model/expense_model.dart';

class ExpenseBottomSheet extends GetView<ExpenseController> {
  final ExpenseModel? item;

  const ExpenseBottomSheet({super.key, this.item});

  @override
  Widget build(BuildContext context) {
    return GetBuilder<ExpenseController>(
      builder: (controller) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
            ),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item == null ? 'Add new Expense' : 'Update Expense',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 24),

                // Date and Time Row
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          DateTime now = DateTime.now();
                          DateTime firstDate = DateTime(now.year, now.month, 1);
                          DateTime lastDate = DateTime(now.year, now.month + 1, 0);

                          DateTime initialDate = controller.selectedDate;
                          if (initialDate.isBefore(firstDate)) initialDate = firstDate;
                          if (initialDate.isAfter(lastDate)) initialDate = lastDate;

                          DateTime? picked = await showDatePicker(
                            context: context,
                            initialDate: initialDate,
                            firstDate: firstDate,
                            lastDate: lastDate,
                          );
                          if (picked != null) {
                            controller.updateSelectedDate(picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.calendar_today,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('dd MMM, yyyy')
                                    .format(controller.selectedDate),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () async {
                          TimeOfDay? picked = await showTimePicker(
                            context: context,
                            initialTime: controller.selectedTime,
                          );
                          if (picked != null) {
                            controller.updateSelectedTime(picked);
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          decoration: BoxDecoration(
                            color: Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.access_time,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary),
                              const SizedBox(width: 8),
                              Text(
                                controller.selectedTime.format(context),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                TextField(
                  controller: controller.amountController,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  decoration: InputDecoration(
                    hintText: 'Amount',
                    errorText: controller.amountError,
                    prefixIcon: const Icon(Icons.attach_money),
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller.descriptionController,
                  decoration: InputDecoration(
                    hintText: 'Description (Optional)',
                    prefixIcon: const Icon(Icons.receipt_long),
                    filled: true,
                    fillColor: Theme.of(context).scaffoldBackgroundColor,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Theme.of(context).dividerColor),
                    ),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: controller.isLoading
                        ? null
                        : () => controller.submitExpense(expenseId: item?.id),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: controller.isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(item == null ? 'Add' : 'Update',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }
}
