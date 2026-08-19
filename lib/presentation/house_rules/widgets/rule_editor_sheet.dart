import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../utils/app_ui.dart';
import '../controller/house_rules_controller.dart';
import '../model/house_rule_model.dart';

/// Writes one rule, in both languages at once.
///
/// Both fields are on the same sheet on purpose: a rule that exists in only
/// one language is a rule half the house cannot read, so there is no path
/// here that saves one without the other.
Future<void> showRuleEditorSheet(BuildContext context, {HouseRuleModel? rule}) {
  return Get.bottomSheet(
    _RuleEditorSheet(rule: rule),
    isScrollControlled: true,
  );
}

class _RuleEditorSheet extends StatefulWidget {
  final HouseRuleModel? rule;

  const _RuleEditorSheet({this.rule});

  @override
  State<_RuleEditorSheet> createState() => _RuleEditorSheetState();
}

class _RuleEditorSheetState extends State<_RuleEditorSheet> {
  late final TextEditingController _english =
      TextEditingController(text: widget.rule?.textEn ?? '');
  late final TextEditingController _bangla =
      TextEditingController(text: widget.rule?.textBn ?? '');

  String? _englishError;
  String? _banglaError;

  bool get _isEditing => widget.rule != null;

  @override
  void dispose() {
    _english.dispose();
    _bangla.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String en = _english.text.trim();
    final String bn = _bangla.text.trim();

    setState(() {
      _englishError = en.isEmpty ? 'rule_english_required'.tr : null;
      _banglaError = bn.isEmpty ? 'rule_bangla_required'.tr : null;
    });
    if (_englishError != null || _banglaError != null) return;

    final bool saved = await Get.find<HouseRulesController>().saveRule(
      existing: widget.rule,
      textEn: en,
      textBn: bn,
    );

    if (saved) closeOverlayRoute();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
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
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppUi.muted(context).withOpacity(0.35),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            Text(
              _isEditing ? 'edit_rule'.tr : 'add_rule'.tr,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'rule_editor_hint'.tr,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppUi.muted(context),
              ),
            ),
            const SizedBox(height: 20),
            CustomTextField(
              controller: _english,
              labelText: 'rule_in_english'.tr,
              hintText: 'rule_english_placeholder'.tr,
              prefixIcon: Icons.translate_rounded,
              errorText: _englishError,
              maxLines: 3,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (_englishError != null) {
                  setState(() => _englishError = null);
                }
              },
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _bangla,
              labelText: 'rule_in_bangla'.tr,
              hintText: 'rule_bangla_placeholder'.tr,
              prefixIcon: Icons.translate_rounded,
              errorText: _banglaError,
              maxLines: 3,
              maxLength: 300,
              onChanged: (_) {
                if (_banglaError != null) {
                  setState(() => _banglaError = null);
                }
              },
            ),
            const SizedBox(height: 24),
            GetBuilder<HouseRulesController>(
              builder: (c) => CustomButton(
                text: _isEditing ? 'save_changes'.tr : 'add_rule'.tr,
                height: 52,
                borderRadius: 14,
                isLoading: c.isSaving,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
