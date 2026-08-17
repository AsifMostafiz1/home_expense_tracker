import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../common/widgets/avatar_picker.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/image_viewer_screen.dart';
import '../../../utils/app_ui.dart';
import '../controller/expense_controller.dart';
import '../model/expense_model.dart';

class ExpenseBottomSheet extends GetView<ExpenseController> {
  final ExpenseModel? item;

  const ExpenseBottomSheet({super.key, this.item});

  /// Optional throughout: most entries are typed from memory and never get a
  /// picture, so this is an empty slot to fill rather than a field to clear.
  Widget _buildReceiptField(BuildContext context, ExpenseController controller) {
    final Color primary = Theme.of(context).colorScheme.primary;

    void openPicker() => showPhotoSourceSheet(
          context,
          onPick: controller.pickReceipt,
          onRemove:
              controller.hasReceipt ? controller.removeReceiptImage : null,
        );

    if (!controller.hasReceipt) {
      return InkWell(
        onTap: openPicker,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppUi.hairline(context)),
          ),
          child: Row(
            children: [
              Icon(Icons.add_a_photo_outlined, size: 20, color: primary),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'add_receipt_photo'.tr,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppUi.body(context),
                  ),
                ),
              ),
              Text(
                'optional'.tr,
                style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
              ),
            ],
          ),
        ),
      );
    }

    final File? picked = controller.pickedReceipt;
    final String? url = controller.existingReceiptUrl;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Row(
        children: [
          // Tapping the thumbnail opens the receipt full screen — the point of
          // keeping one is being able to read it.
          GestureDetector(
            onTap: () => Get.to(() => ImageViewerScreen(
                  imageFile: picked,
                  imageUrl: picked == null ? url : null,
                  title: 'receipt'.tr,
                )),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: picked != null
                  ? Image.file(picked, width: 54, height: 54, fit: BoxFit.cover)
                  : Image.network(
                      url!,
                      width: 54,
                      height: 54,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        width: 54,
                        height: 54,
                        color: AppUi.tint(context, Colors.grey),
                        child: Icon(Icons.broken_image_outlined,
                            size: 20, color: AppUi.muted(context)),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'receipt'.tr,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppUi.body(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  picked == null
                      ? 'tap_to_view'.tr
                      : controller.receiptWaitingUpload
                          ? 'receipt_waiting_upload'.tr
                          : 'not_saved_yet'.tr,
                  style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'change_photo'.tr,
            icon: Icon(Icons.edit_outlined, size: 18, color: primary),
            onPressed: openPicker,
          ),
          IconButton(
            tooltip: 'remove_photo'.tr,
            icon: Icon(Icons.close_rounded,
                size: 18, color: Theme.of(context).colorScheme.error),
            onPressed: controller.removeReceiptImage,
          ),
        ],
      ),
    );
  }

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
                  item == null ? 'add_new_expense'.tr : 'update_expense'.tr,
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
                          DateTime lastDate = DateTime(now.year, now.month + 2, 0); // End of next month

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
                Text('expense_type'.tr, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => controller.setExpenseType('expense'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: controller.selectedType == 'expense' 
                                ? Theme.of(context).colorScheme.primary 
                                : Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: controller.selectedType == 'expense' 
                                  ? Theme.of(context).colorScheme.primary 
                                  : Theme.of(context).dividerColor
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'expense'.tr,
                            style: TextStyle(
                              color: controller.selectedType == 'expense' ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                              fontWeight: FontWeight.bold
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: InkWell(
                        onTap: () => controller.setExpenseType('others'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: controller.selectedType == 'others' 
                                ? Theme.of(context).colorScheme.primary 
                                : Theme.of(context).scaffoldBackgroundColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: controller.selectedType == 'others' 
                                  ? Theme.of(context).colorScheme.primary 
                                  : Theme.of(context).dividerColor
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            'others'.tr,
                            style: TextStyle(
                              color: controller.selectedType == 'others' ? Colors.white : Theme.of(context).textTheme.bodyLarge?.color,
                              fontWeight: FontWeight.bold
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),
                CustomTextField(
                  controller: controller.amountController,
                  hintText: 'amount'.tr,
                  errorText: controller.amountError,
                  prefixIcon: Icons.attach_money,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: controller.descriptionController,
                  hintText: 'description'.tr,
                  prefixIcon: Icons.receipt_long,
                ),
                const SizedBox(height: 20),
                _buildReceiptField(context, controller),
                const SizedBox(height: 32),
                CustomButton(
                  text: item == null ? 'add'.tr : 'update'.tr,
                  isLoading: controller.isLoading,
                  onPressed: () => controller.submitExpense(existingExpense: item),
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
