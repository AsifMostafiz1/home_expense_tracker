import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/personal_category.dart';
import '../model/subcategory.dart';
import 'subcategory_editor_sheet.dart';

/// One category's subcategories as a list the member can rearrange — the
/// same room the categories get, one door deeper.
///
/// Every row drags by its handle and opens its editor on a tap: unlike the
/// category list there is nothing fixed here, the starter set included. The
/// way to make another sits at the bottom.
Future<void> showSubcategoryManagerSheet(
  BuildContext context, {
  required String parent,
}) {
  return Get.bottomSheet(
    _SubcategoryManagerSheet(parent: parent),
    isScrollControlled: true,
  );
}

class _SubcategoryManagerSheet extends StatelessWidget {
  final String parent;

  const _SubcategoryManagerSheet({required this.parent});

  MaterialColor get _color => PersonalCategory.of(parent).color;

  void _reorder(List<Subcategory> subs, int from, int to) {
    if (to > from) to -= 1;
    final List<String> ids = subs.map((sub) => sub.id).toList();
    ids.insert(to, ids.removeAt(from));
    Get.find<PersonalController>()
        .arrangeSubcategories(parent: parent, ids: ids);
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
          Row(
            children: [
              Expanded(
                child: Text(
                  'manage_subcategories'.tr,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ),
              // Whose subcategories these are, said in its colour — the
              // same badge the editor sheet wears.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: AppUi.tint(context, _color),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PersonalCategory.of(parent).icon,
                        size: 13, color: AppUi.accent(context, _color)),
                    const SizedBox(width: 5),
                    Text(
                      PersonalCategory.of(parent).label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppUi.accent(context, _color),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'drag_to_reorder_subs'.tr,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.4,
              color: AppUi.muted(context),
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: GetBuilder<PersonalController>(
              builder: (c) {
                final List<Subcategory> subs = c.subcategoriesOf(parent);

                return ReorderableListView(
                  shrinkWrap: true,
                  buildDefaultDragHandles: false,
                  onReorder: (from, to) => _reorder(subs, from, to),
                  children: [
                    for (int index = 0; index < subs.length; index++)
                      _row(context, subs[index], index),
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

  Widget _row(BuildContext context, Subcategory sub, int index) {
    return Container(
      key: ValueKey(sub.id),
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
              onTap: () => showSubcategorySheet(
                context,
                parent: parent,
                existing: sub,
              ),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 0, 8),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: AppUi.tint(context, _color),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(Icons.sell_outlined,
                          size: 16, color: AppUi.accent(context, _color)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        sub.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: AppUi.body(context),
                        ),
                      ),
                    ),
                    Icon(Icons.edit_rounded,
                        size: 15,
                        color: AppUi.muted(context).withOpacity(0.9)),
                  ],
                ),
              ),
            ),
          ),
          // The handle, and only the handle, starts a drag — the row's tap
          // is already the way to the editor.
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
      onTap: () => showSubcategorySheet(context, parent: parent),
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
              'new_subcategory'.tr,
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
