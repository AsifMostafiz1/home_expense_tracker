import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/personal_category.dart';
import '../model/subcategory.dart';

/// What the editor closed with, so the row underneath can follow: select the
/// subcategory that was just made, or step off one that is gone.
class SubcategoryEditorResult {
  /// The id of the saved subcategory. Null when nothing was written.
  final String? savedId;

  final bool deleted;

  const SubcategoryEditorResult({this.savedId, this.deleted = false});
}

/// Makes or reworks one subcategory — the same sheet the categories use,
/// with everything a subcategory does not have left out: no icon, no colour,
/// just the name. It wears its parent category's colour instead.
Future<SubcategoryEditorResult?> showSubcategorySheet(
  BuildContext context, {
  required String parent,
  Subcategory? existing,
}) {
  return Get.bottomSheet<SubcategoryEditorResult>(
    _SubcategorySheet(parent: parent, existing: existing),
    isScrollControlled: true,
  );
}

class _SubcategorySheet extends StatefulWidget {
  final String parent;
  final Subcategory? existing;

  const _SubcategorySheet({required this.parent, this.existing});

  @override
  State<_SubcategorySheet> createState() => _SubcategorySheetState();
}

class _SubcategorySheetState extends State<_SubcategorySheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');

  String? _nameError;

  bool get _isEditing => widget.existing != null;

  MaterialColor get _color => PersonalCategory.of(widget.parent).color;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'enter_subcategory_name'.tr);
      return;
    }

    final String? id = await Get.find<PersonalController>().saveSubcategory(
      existing: widget.existing,
      parent: widget.parent,
      name: _name.text,
    );

    // Null is a refusal the controller has already explained — the sheet
    // stays open on what was typed so it can be changed, not retyped.
    if (id != null && mounted) {
      Navigator.of(context).pop(SubcategoryEditorResult(savedId: id));
    }
  }

  void _confirmDelete() {
    final Subcategory subcategory = widget.existing!;
    showConfirmDialog(
      title: 'delete_subcategory'.tr,
      message:
          'delete_subcategory_message'.trParams({'name': subcategory.name}),
      confirmText: 'delete'.tr,
      onConfirm: () async {
        final bool deleted = await Get.find<PersonalController>()
            .deleteSubcategory(subcategory);
        if (deleted && mounted) {
          Navigator.of(context)
              .pop(const SubcategoryEditorResult(deleted: true));
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SingleChildScrollView(
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
                    _isEditing
                        ? 'edit_subcategory'.tr
                        : 'new_subcategory'.tr,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                // Which category this cut belongs to, said in its colour —
                // the sheet covers the picker that would otherwise say it.
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
                      Icon(PersonalCategory.of(widget.parent).icon,
                          size: 13, color: AppUi.accent(context, _color)),
                      const SizedBox(width: 5),
                      Text(
                        PersonalCategory.of(widget.parent).label,
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
            const SizedBox(height: 16),
            CustomTextField(
              controller: _name,
              autofocus: true,
              labelText: 'subcategory_name'.tr,
              hintText: 'subcategory_name_hint'.tr,
              prefixIcon: Icons.sell_outlined,
              errorText: _nameError,
              maxLength: 30,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
            ),
            const SizedBox(height: 22),
            GetBuilder<PersonalController>(
              builder: (c) => CustomButton(
                text: _isEditing ? 'save_changes'.tr : 'add_subcategory_button'.tr,
                height: 52,
                borderRadius: 14,
                color: _color.shade600,
                isLoading: c.isSaving,
                onPressed: _save,
              ),
            ),
            if (_isEditing) ...[
              const SizedBox(height: 6),
              Center(
                child: TextButton.icon(
                  onPressed: _confirmDelete,
                  icon: const Icon(Icons.delete_outline_rounded,
                      size: 18, color: Colors.red),
                  label: Text(
                    'delete_subcategory'.tr,
                    style: const TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 13.5,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
