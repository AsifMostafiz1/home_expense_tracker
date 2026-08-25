import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../common/widgets/custom_text_field.dart';
import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/debt_entry.dart';

/// Changes the name an account is kept under.
///
/// A dialog rather than a sheet: there is one field and one decision, and the
/// account being renamed should stay visible behind it.
///
/// Returns the key the account is grouped under afterwards — a new one when
/// the person has no phone, since the key is folded out of the name — or null
/// when nothing was written. The caller has to take that key up: a screen
/// still holding the old one is looking at an account that no longer exists.
Future<String?> showRenamePersonDialog(
  BuildContext context, {
  required PersonBalance person,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _RenamePersonDialog(person: person),
  );
}

class _RenamePersonDialog extends StatefulWidget {
  final PersonBalance person;

  const _RenamePersonDialog({required this.person});

  @override
  State<_RenamePersonDialog> createState() => _RenamePersonDialogState();
}

class _RenamePersonDialogState extends State<_RenamePersonDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.person.name);

  String? _error;

  @override
  void initState() {
    super.initState();
    // The old name is there to be read and corrected, not retyped — so it
    // opens selected, and the first key replaces it for anyone who meant to
    // start over.
    _name.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _name.text.length,
    );
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    setState(() => _error = name.isEmpty ? 'enter_a_name'.tr : null);
    if (_error != null) return;

    final String? key = await Get.find<PersonalController>()
        .renamePerson(widget.person, name);

    // Null is a refusal the controller has already explained — the name is
    // taken, or the write failed. The dialog stays open on what was typed so
    // it can be changed rather than typed again.
    if (key == null || !mounted) return;
    Navigator.of(context).pop(key);
  }

  @override
  Widget build(BuildContext context) {
    return GetBuilder<PersonalController>(
      builder: (c) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text('rename_person'.tr),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CustomTextField(
                controller: _name,
                autofocus: true,
                hintText: 'person_name_hint'.tr,
                prefixIcon: Icons.person_outline_rounded,
                errorText: _error,
                textCapitalization: TextCapitalization.words,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              const SizedBox(height: 12),
              Text(
                // The history is not a list of one name repeated for show —
                // every row carries it, and the rename reaches all of them.
                // Worth saying, because it is the part that is not obvious.
                'rename_person_note'.tr,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: AppUi.muted(context),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed:
                  c.isSaving ? null : () => Navigator.of(context).pop(),
              child: Text('cancel'.tr),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              // Nothing to tap while the batch is in flight — a second tap
              // would write the same name over an account already renamed.
              onPressed: c.isSaving ? null : _save,
              child: c.isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text('save'.tr),
            ),
          ],
        );
      },
    );
  }
}
