import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/debt_entry.dart';

/// Records money handed to somebody, or taken from them.
///
/// A repayment is entered here too, as a row the other way round — that is
/// what keeps a person's account a plain running total instead of a set of
/// loans to open and close by hand.
Future<void> showDebtEntrySheet(
  BuildContext context, {
  DebtEntry? entry,
  String? personName,
  String? personPhone,
  DebtFlow flow = DebtFlow.gave,
}) {
  return Get.bottomSheet(
    _DebtEntrySheet(
      entry: entry,
      lockedName: entry?.personName ?? personName,
      lockedPhone: entry?.personPhone ?? personPhone,
      initialFlow: entry?.flow ?? flow,
    ),
    isScrollControlled: true,
  );
}

class _DebtEntrySheet extends StatefulWidget {
  final DebtEntry? entry;
  final String? lockedName;
  final String? lockedPhone;
  final DebtFlow initialFlow;

  const _DebtEntrySheet({
    this.entry,
    this.lockedName,
    this.lockedPhone,
    required this.initialFlow,
  });

  @override
  State<_DebtEntrySheet> createState() => _DebtEntrySheetState();
}

class _DebtEntrySheetState extends State<_DebtEntrySheet> {
  late DebtFlow _flow = widget.initialFlow;

  late final TextEditingController _name =
      TextEditingController(text: widget.lockedName ?? '');
  late final TextEditingController _phone =
      TextEditingController(text: widget.lockedPhone ?? '');
  late final TextEditingController _amount =
      TextEditingController(text: _initialAmount);
  late final TextEditingController _note =
      TextEditingController(text: widget.entry?.note ?? '');

  late DateTime _date = widget.entry?.day ?? DateTime.now();

  String? _nameError;
  String? _amountError;

  bool get _isEditing => widget.entry != null;

  /// Opened from inside somebody's account: the person is settled, and only
  /// the entry is in question.
  bool get _personFixed =>
      (widget.lockedName ?? '').trim().isNotEmpty;

  String get _initialAmount {
    final double? amount = widget.entry?.amount;
    if (amount == null || amount == 0) return '';
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toString();
  }

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    final String name = _name.text.trim();
    final double amount = double.tryParse(_amount.text.trim()) ?? 0;

    setState(() {
      _nameError = name.isEmpty ? 'enter_a_name'.tr : null;
      _amountError = amount <= 0 ? 'enter_an_amount'.tr : null;
    });
    if (_nameError != null || _amountError != null) return;

    final bool saved = await Get.find<PersonalController>().saveDebtEntry(
      existing: widget.entry,
      personName: name,
      personPhone: _phone.text.trim(),
      flow: _flow,
      amount: amount,
      note: _note.text,
      date: _date,
    );

    if (saved) closeOverlayRoute();
  }

  @override
  Widget build(BuildContext context) {
    final bool gave = _flow == DebtFlow.gave;
    final MaterialColor accent = gave ? Colors.green : Colors.deepOrange;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
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
                _isEditing ? 'edit_entry'.tr : 'add_due_entry'.tr,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 6),
              Text(
                'due_entry_hint'.tr,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: AppUi.muted(context),
                ),
              ),
              const SizedBox(height: 16),
              _buildFlowToggle(context),
              const SizedBox(height: 18),
              if (!_personFixed) ...[
                CustomTextField(
                  controller: _name,
                  labelText: 'person_name'.tr,
                  hintText: 'person_name_hint'.tr,
                  prefixIcon: Icons.person_outline_rounded,
                  errorText: _nameError,
                  maxLength: 60,
                  textCapitalization: TextCapitalization.words,
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                  },
                ),
                if (Get.find<PersonalController>().knownPeople.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  _buildKnownPeople(context),
                ],
                const SizedBox(height: 16),
                CustomTextField(
                  controller: _phone,
                  labelText: 'phone_optional'.tr,
                  hintText: '01XXXXXXXXX',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  maxLength: 20,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9+\- ]')),
                  ],
                ),
                const SizedBox(height: 16),
              ],
              CustomTextField(
                controller: _amount,
                labelText: 'amount'.tr,
                hintText: '0',
                prefixIcon: Icons.currency_exchange_rounded,
                errorText: _amountError,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                onChanged: (_) {
                  if (_amountError != null) {
                    setState(() => _amountError = null);
                  }
                },
              ),
              const SizedBox(height: 16),
              _buildDateField(context, accent),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _note,
                labelText: 'note_optional'.tr,
                hintText: 'due_note_hint'.tr,
                prefixIcon: Icons.notes_rounded,
                maxLines: 2,
                maxLength: 140,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 22),
              GetBuilder<PersonalController>(
                builder: (c) => CustomButton(
                  text: _isEditing ? 'save_changes'.tr : 'add_entry'.tr,
                  height: 52,
                  borderRadius: 14,
                  color: accent.shade600,
                  isLoading: c.isSaving,
                  onPressed: _save,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFlowToggle(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppUi.neutralSurface(context),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppUi.hairline(context)),
      ),
      child: Row(
        children: [
          _flowOption(context, DebtFlow.gave, 'i_gave'.tr,
              Icons.call_made_rounded, Colors.green),
          _flowOption(context, DebtFlow.got, 'i_got'.tr,
              Icons.call_received_rounded, Colors.deepOrange),
        ],
      ),
    );
  }

  Widget _flowOption(
    BuildContext context,
    DebtFlow flow,
    String label,
    IconData icon,
    MaterialColor color,
  ) {
    final bool selected = _flow == flow;

    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _flow = flow),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected ? AppUi.tint(context, color) : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(
              color: selected ? color.withOpacity(0.5) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 17,
                  color: selected
                      ? AppUi.accent(context, color)
                      : AppUi.muted(context)),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    color: selected
                        ? AppUi.accent(context, color)
                        : AppUi.muted(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Names already in the ledger, so a second entry for the same person lands
  /// in the same account instead of starting another one.
  Widget _buildKnownPeople(BuildContext context) {
    final List<String> names =
        Get.find<PersonalController>().knownPeople.take(8).toList();

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final String name in names)
          GestureDetector(
            onTap: () {
              _name.text = name;
              setState(() => _nameError = null);
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
              decoration: BoxDecoration(
                color: AppUi.neutralSurface(context),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: AppUi.hairline(context)),
              ),
              child: Text(
                name,
                style: TextStyle(fontSize: 12, color: AppUi.body(context)),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildDateField(BuildContext context, MaterialColor accent) {
    return InkWell(
      onTap: _pickDate,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
        decoration: BoxDecoration(
          color: AppUi.neutralSurface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppUi.hairline(context)),
        ),
        child: Row(
          children: [
            Icon(Icons.calendar_today_rounded,
                size: 17, color: AppUi.accent(context, accent)),
            const SizedBox(width: 12),
            Text(
              DateFormat('dd MMM, yyyy').format(_date),
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppUi.body(context),
              ),
            ),
            const Spacer(),
            Text(
              'change'.tr,
              style: TextStyle(fontSize: 12, color: AppUi.muted(context)),
            ),
          ],
        ),
      ),
    );
  }
}
