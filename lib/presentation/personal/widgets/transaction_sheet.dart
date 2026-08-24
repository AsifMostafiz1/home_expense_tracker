import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../common/widgets/confirm_dialog.dart';
import '../../../common/widgets/custom_button.dart';
import '../../../common/widgets/custom_text_field.dart';
import '../../../utils/app_ui.dart';
import '../controller/personal_controller.dart';
import '../model/personal_category.dart';
import '../model/personal_transaction.dart';

/// Records money earned or money spent.
///
/// One sheet for both sides: which side it is changes the accent, the
/// categories and the wording, and nothing else. Switching between them
/// mid-entry keeps the amount and the note — they belong to the entry, not to
/// the direction.
Future<void> showTransactionSheet(
  BuildContext context, {
  PersonalTransaction? entry,
  MoneyFlow flow = MoneyFlow.expense,
}) {
  return Get.bottomSheet(
    _TransactionSheet(
      entry: entry,
      initialFlow: entry?.flow ?? flow,
      initialDate:
          _defaultDayIn(Get.find<PersonalController>().selectedMonth),
    ),
    isScrollControlled: true,
  );
}

/// The day a new entry starts on, given the month being looked at.
///
/// Today while that is this month — somebody adding as they go means now. Any
/// other month and today is not even in it, so the entry would file itself
/// into a month the screen is not showing: the 1st of the month on screen is
/// what was meant. A month not yet reached has no day that has happened, so
/// it falls back to today, which is also the furthest the picker will go.
DateTime _defaultDayIn(DateTime month) {
  final DateTime now = DateTime.now();
  if (month.year == now.year && month.month == now.month) return now;

  final DateTime first = DateTime(month.year, month.month, 1);
  return first.isAfter(now) ? now : first;
}

class _TransactionSheet extends StatefulWidget {
  final PersonalTransaction? entry;
  final MoneyFlow initialFlow;

  /// Where a new entry's date starts. An entry being edited ignores it and
  /// keeps its own day.
  final DateTime initialDate;

  const _TransactionSheet({
    this.entry,
    required this.initialFlow,
    required this.initialDate,
  });

  @override
  State<_TransactionSheet> createState() => _TransactionSheetState();
}

class _TransactionSheetState extends State<_TransactionSheet> {
  late MoneyFlow _flow = widget.initialFlow;
  late final TextEditingController _amount =
      TextEditingController(text: _initialAmount);
  late final TextEditingController _note =
      TextEditingController(text: widget.entry?.note ?? '');

  late String _category = widget.entry?.category ??
      PersonalCategory.forIncome(_flow == MoneyFlow.income).first.key;

  late DateTime _date = widget.entry?.day ?? widget.initialDate;
  late TimeOfDay _time =
      widget.entry?.time ?? TimeOfDay.fromDateTime(DateTime.now());

  String? _amountError;

  bool get _isEditing => widget.entry != null;

  String get _initialAmount {
    final double? amount = widget.entry?.amount;
    if (amount == null || amount == 0) return '';
    // Whole taka is the common case; the decimals only show when there are any.
    return amount == amount.roundToDouble()
        ? amount.toStringAsFixed(0)
        : amount.toString();
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  void _switchFlow(MoneyFlow flow) {
    if (_flow == flow) return;
    setState(() {
      _flow = flow;
      // The categories differ per side, so the old pick cannot stand.
      _category = PersonalCategory.forIncome(flow == MoneyFlow.income).first.key;
    });
  }

  Future<void> _pickDate() async {
    final DateTime now = DateTime.now();
    final DateTime first = DateTime(now.year - 3);

    // The picker asserts on a start it would not let you choose, and the day
    // on the form can sit outside the window — an entry copied from the house
    // screen can be dated into next month.
    DateTime start = _date;
    if (start.isBefore(first)) start = first;
    if (start.isAfter(now)) start = now;

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: start,
      firstDate: first,
      // Money is recorded after it moves, so tomorrow is not on offer.
      lastDate: now,
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final TimeOfDay? picked =
        await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final double amount = double.tryParse(_amount.text.trim()) ?? 0;
    if (amount <= 0) {
      setState(() => _amountError = 'enter_an_amount'.tr);
      return;
    }

    final bool saved =
        await Get.find<PersonalController>().saveTransaction(
      existing: widget.entry,
      flow: _flow,
      amount: amount,
      category: _category,
      note: _note.text,
      date: _date,
      time: _time,
    );

    if (saved) closeOverlayRoute();
  }

  @override
  Widget build(BuildContext context) {
    final bool isIncome = _flow == MoneyFlow.income;
    final MaterialColor accent = isIncome ? Colors.green : Colors.deepOrange;

    // No keyboard inset here. Get.bottomSheet already pads its own route by
    // `viewInsets.bottom`, so adding it again lifts the sheet a second
    // keyboard-height off the bottom and leaves a gap between the two — the
    // same trap the announcement sheet documents.
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
              _isEditing ? 'edit_entry'.tr : 'add_entry'.tr,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _buildFlowToggle(context),
            const SizedBox(height: 18),
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
            const SizedBox(height: 18),
            Text(
              'category'.tr,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.color
                    ?.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 10),
            _buildCategories(context, isIncome),
            const SizedBox(height: 18),
            _buildDateTimeRow(context, accent),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _note,
              labelText: 'note_optional'.tr,
              hintText: 'note_hint'.tr,
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
    );
  }

  /// The two sides, as one control — which way the money went is the first
  /// thing to decide and the one that changes everything below it.
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
          _flowOption(context, MoneyFlow.expense, 'expense_word'.tr,
              Icons.south_west_rounded, Colors.deepOrange),
          _flowOption(context, MoneyFlow.income, 'income'.tr,
              Icons.north_east_rounded, Colors.green),
        ],
      ),
    );
  }

  Widget _flowOption(
    BuildContext context,
    MoneyFlow flow,
    String label,
    IconData icon,
    MaterialColor color,
  ) {
    final bool selected = _flow == flow;

    return Expanded(
      child: GestureDetector(
        onTap: () => _switchFlow(flow),
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.symmetric(vertical: 11),
          decoration: BoxDecoration(
            color: selected
                ? AppUi.tint(context, color)
                : Colors.transparent,
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
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected
                      ? AppUi.accent(context, color)
                      : AppUi.muted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCategories(BuildContext context, bool isIncome) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final PersonalCategory category
            in PersonalCategory.forIncome(isIncome))
          _categoryChip(context, category),
      ],
    );
  }

  Widget _categoryChip(BuildContext context, PersonalCategory category) {
    final bool selected = _category == category.key;
    final Color accent = AppUi.accent(context, category.color);

    return GestureDetector(
      onTap: () => setState(() => _category = category.key),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? AppUi.tint(context, category.color)
              : AppUi.neutralSurface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent.withOpacity(0.6) : AppUi.hairline(context),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(category.icon,
                size: 15, color: selected ? accent : AppUi.muted(context)),
            const SizedBox(width: 7),
            Text(
              category.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                color: selected ? accent : AppUi.body(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Calendar and clock side by side, the way the house expense sheet asks
  /// for them — an entry typed in the evening for something bought at noon is
  /// the normal case, not the exception.
  Widget _buildDateTimeRow(BuildContext context, MaterialColor accent) {
    return Row(
      children: [
        Expanded(
          child: _pickerField(
            context,
            icon: Icons.calendar_today_rounded,
            label: DateFormat('dd MMM, yyyy').format(_date),
            accent: accent,
            onTap: _pickDate,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _pickerField(
            context,
            icon: Icons.access_time_rounded,
            label: _time.format(context),
            accent: accent,
            onTap: _pickTime,
          ),
        ),
      ],
    );
  }

  Widget _pickerField(
    BuildContext context, {
    required IconData icon,
    required String label,
    required MaterialColor accent,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
        decoration: BoxDecoration(
          color: AppUi.neutralSurface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppUi.hairline(context)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: AppUi.accent(context, accent)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  color: AppUi.body(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
