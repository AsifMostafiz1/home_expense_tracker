import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/custom_category.dart';
import '../model/personal_category.dart';
import 'category_editor_sheet.dart';

/// One side of the picker as a list the member can rearrange.
///
/// Dragging is the whole point, so every row has a handle — the fixed
/// categories move like the rest, they just cannot be opened. A custom row
/// opens its editor on a tap, and the way to make another sits at the
/// bottom, after the last thing it would follow.
Future<void> showCategoryManagerSheet(
  BuildContext context, {
  required bool income,
}) {
  return Get.bottomSheet(
    _CategoryManagerSheet(income: income),
    isScrollControlled: true,
  );
}

class _CategoryManagerSheet extends StatelessWidget {
  final bool income;

  const _CategoryManagerSheet({required this.income});

  void _reorder(List<PersonalCategory> categories, int from, int to) {
    if (to > from) to -= 1;
    final List<String> keys =
        categories.map((category) => category.key).toList();
    keys.insert(to, keys.removeAt(from));
    Get.find<PersonalController>()
        .arrangeCategories(income: income, keys: keys);
  }

  Future<void> _edit(BuildContext context, PersonalCategory category) async {
    final CustomCategory? existing = Get.find<PersonalController>()
        .customCategories
        .firstWhereOrNull((custom) => custom.id == category.key);
    if (existing == null) return;
    await showCategoryEditorSheet(context,
        income: income, existing: existing);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.72,
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: AppUi.muted(context).withOpacity(0.35),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ),
          Text(
            'manage_categories'.tr,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            'drag_to_reorder'.tr,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppUi.muted(context),
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: GetBuilder<PersonalController>(
              builder: (_) {
                final List<PersonalCategory> categories =
                    PersonalCategory.pickerFor(income);

                return ReorderableListView(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  onReorder: (from, to) => _reorder(categories, from, to),
                  children: [
                    for (int index = 0; index < categories.length; index++)
                      _row(context, categories[index], index),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 8),
          _addRow(context),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, PersonalCategory category, int index) {
    final Color accent = AppUi.accent(context, category.color);

    return Container(
      key: ValueKey(category.key),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppUi.neutralSurface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: category.isCustom
                  ? () => _edit(context, category)
                  : null,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppUi.tint(context, category.color),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(category.icon, size: 18, color: accent),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        category.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppUi.body(context),
                        ),
                      ),
                    ),
                    Icon(
                      category.isCustom
                          ? Icons.edit_rounded
                          : Icons.lock_outline_rounded,
                      size: 15,
                      color: AppUi.muted(context)
                          .withOpacity(category.isCustom ? 0.9 : 0.45),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // The handle, and only the handle, starts a drag — a row that
          // dragged from anywhere could not also be tapped to edit.
          ReorderableDragStartListener(
            index: index,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 19,
                color: AppUi.muted(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _addRow(BuildContext context) {
    return InkWell(
      onTap: () => showCategoryEditorSheet(context, income: income),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppUi.hairline(context)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.add_rounded, size: 17, color: AppUi.muted(context)),
            const SizedBox(width: 7),
            Text(
              'new_category'.tr,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppUi.body(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
