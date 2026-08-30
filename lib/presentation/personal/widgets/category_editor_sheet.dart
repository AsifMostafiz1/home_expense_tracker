import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/custom_category.dart';

/// What the editor closed with, so the picker underneath can follow: select
/// the category that was just made or renamed, or step off one that is gone.
class CategoryEditorResult {
  /// The key of the saved category. Null when nothing was written.
  final String? savedKey;

  final bool deleted;

  const CategoryEditorResult({this.savedKey, this.deleted = false});
}

/// Makes or reworks one of the member's own categories.
///
/// Only theirs: the fixed list never reaches this sheet. A new one opens
/// empty on the side the picker was showing; an existing one opens filled in,
/// with the delete at the bottom — where its entries go is said before
/// anything is removed.
Future<CategoryEditorResult?> showCategoryEditorSheet(
  BuildContext context, {
  required bool income,
  CustomCategory? existing,
}) {
  return Get.bottomSheet<CategoryEditorResult>(
    _CategoryEditorSheet(income: income, existing: existing),
    isScrollControlled: true,
  );
}

class _CategoryEditorSheet extends StatefulWidget {
  final bool income;
  final CustomCategory? existing;

  const _CategoryEditorSheet({required this.income, this.existing});

  @override
  State<_CategoryEditorSheet> createState() => _CategoryEditorSheetState();
}

class _CategoryEditorSheetState extends State<_CategoryEditorSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.existing?.name ?? '');

  late String _iconKey = () {
    final String key = widget.existing?.iconKey ?? '';
    return CustomCategory.icons.containsKey(key) ? key : 'label';
  }();

  late String _colorKey = () {
    final String key = widget.existing?.colorKey ?? '';
    return CustomCategory.colors.containsKey(key) ? key : 'blue';
  }();

  String? _nameError;

  bool get _isEditing => widget.existing != null;

  MaterialColor get _color =>
      CustomCategory.colors[_colorKey] ?? Colors.blueGrey;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'enter_category_name'.tr);
      return;
    }

    final String? key = await Get.find<PersonalController>().saveCategory(
      existing: widget.existing,
      income: widget.income,
      name: _name.text,
      iconKey: _iconKey,
      colorKey: _colorKey,
    );

    if (key != null && mounted) {
      Navigator.of(context).pop(CategoryEditorResult(savedKey: key));
    }
  }

  void _confirmDelete() {
    final CustomCategory category = widget.existing!;
    showConfirmDialog(
      title: 'delete_category'.tr,
      message: 'delete_category_message'
          .trParams({'name': category.name}),
      confirmText: 'delete'.tr,
      onConfirm: () async {
        final bool deleted =
            await Get.find<PersonalController>().deleteCategory(category);
        if (deleted && mounted) {
          Navigator.of(context).pop(const CategoryEditorResult(deleted: true));
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
            Text(
              _isEditing ? 'edit_category'.tr : 'new_category'.tr,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _name,
              labelText: 'category_name'.tr,
              hintText: 'category_name_hint'.tr,
              prefixIcon: CustomCategory.icons[_iconKey],
              errorText: _nameError,
              maxLength: 30,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_nameError != null) {
                  setState(() => _nameError = null);
                }
              },
            ),
            const SizedBox(height: 18),
            _sectionLabel(context, 'choose_icon'.tr),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final MapEntry<String, IconData> entry
                    in CustomCategory.icons.entries)
                  _iconOption(context, entry.key, entry.value),
              ],
            ),
            const SizedBox(height: 18),
            _sectionLabel(context, 'choose_color'.tr),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final MapEntry<String, MaterialColor> entry
                    in CustomCategory.colors.entries)
                  _colorOption(context, entry.key, entry.value),
              ],
            ),
            const SizedBox(height: 22),
            GetBuilder<PersonalController>(
              builder: (c) => CustomButton(
                text: _isEditing ? 'save_changes'.tr : 'add_category'.tr,
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
                    'delete_category'.tr,
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

  Widget _sectionLabel(BuildContext context, String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.bold,
        color:
            Theme.of(context).textTheme.titleSmall?.color?.withOpacity(0.8),
      ),
    );
  }

  Widget _iconOption(BuildContext context, String key, IconData icon) {
    final bool selected = _iconKey == key;
    final Color accent = AppUi.accent(context, _color);

    return GestureDetector(
      onTap: () => setState(() => _iconKey = key),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: selected
              ? AppUi.tint(context, _color)
              : AppUi.neutralSurface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent.withOpacity(0.6) : AppUi.hairline(context),
          ),
        ),
        child: Icon(icon,
            size: 20, color: selected ? accent : AppUi.muted(context)),
      ),
    );
  }

  Widget _colorOption(BuildContext context, String key, MaterialColor color) {
    final bool selected = _colorKey == key;

    return GestureDetector(
      onTap: () => setState(() => _colorKey = key),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: AppUi.tint(context, color),
          border: Border.all(
            color: selected
                ? AppUi.accent(context, color)
                : AppUi.hairline(context),
            width: selected ? 2 : 1,
          ),
        ),
        child: Center(
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppUi.accent(context, color),
            ),
          ),
        ),
      ),
    );
  }
}
