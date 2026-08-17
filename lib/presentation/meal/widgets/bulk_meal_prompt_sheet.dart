import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/info_prompt_sheet.dart';
import '../../../utils/app_ui.dart';
import '../controller/meal_controller.dart';

/// What became of the ask — the home screen queues its prompts on this.
enum BulkMealPromptResult {
  /// The month was already filled in, or there was nothing to go on.
  notNeeded,

  /// Closed without filling the month in.
  dismissed,

  /// The month was written from the sheet.
  added,
}

/// The ask that opens the current month.
///
/// Nothing else in the meal screen works until the month exists — single-day
/// edits are refused, and the totals read as zero — so this comes up on every
/// launch that finds the month empty. Nothing is remembered between launches
/// on purpose: unlike the profile picture, saying "not now" here leaves real
/// work outstanding.
class BulkMealPrompt {
  const BulkMealPrompt._();

  /// Shows the sheet when the current month has no meals in it yet.
  static Future<BulkMealPromptResult> maybeShow() async {
    if (!Get.isRegistered<MealController>()) return BulkMealPromptResult.notNeeded;
    final MealController controller = Get.find<MealController>();

    // The screen starts its own read on the way in; wait for that one rather
    // than firing a second.
    await controller.mealsReady;

    // A read that never landed leaves every month looking empty.
    if (!controller.hasLoadedMeals) return BulkMealPromptResult.notNeeded;
    if (controller.hasCurrentMonthMeals) return BulkMealPromptResult.notNeeded;
    if (Get.context == null) return BulkMealPromptResult.notNeeded;

    final DateTime month = DateTime.now();
    final bool? added = await showInfoPromptSheet<bool>(
      GetBuilder<MealController>(
        builder: (controller) => _sheet(controller, month),
      ),
    );

    return added == true
        ? BulkMealPromptResult.added
        : BulkMealPromptResult.dismissed;
  }

  static Widget _sheet(MealController controller, DateTime month) {
    return Builder(
      builder: (context) {
        final Color primary = Theme.of(context).colorScheme.primary;

        return InfoPromptSheet(
          badge: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: AppUi.tint(context, primary),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome_rounded, size: 34, color: primary),
          ),
          title: 'bulk_meal_prompt_title'
              .trParams({'month': AppUi.monthLabel(month)}),
          message: 'bulk_meal_prompt_message'.tr,
          points: [
            InfoPromptPoint(
                Icons.event_repeat_rounded, 'bulk_meal_point_defaults'.tr),
            InfoPromptPoint(
                Icons.edit_calendar_outlined, 'bulk_meal_point_edit'.tr),
            InfoPromptPoint(
                Icons.lock_outline_rounded, 'bulk_meal_point_locked'.tr),
          ],
          actionLabel: 'add_bulk_meal'.tr,
          isLoading: controller.isLoading,
          onAction: () async {
            // Closes only once the batch has landed — a failure leaves the
            // sheet up, with the error snackbar over it, so the user can
            // simply tap again.
            if (await controller.addBulkMeal(month: month)) {
              Get.back(result: true);
            }
          },
          dismissLabel: 'not_now'.tr,
          onDismiss: () => Get.back(result: false),
        );
      },
    );
  }
}
