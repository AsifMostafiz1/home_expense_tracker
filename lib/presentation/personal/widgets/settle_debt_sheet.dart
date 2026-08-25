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

/// Settles what is outstanding with one person — the whole of it, or as much
/// of it as changed hands today.
///
/// Nothing new in the ledger: this writes the same [DebtEntry] the two
/// buttons at the bottom of an account write, in the direction that brings
/// the balance towards zero. What it saves anybody is the arithmetic — the
/// figure is already in the box, and the line under it says where the account
/// lands once this is saved.
Future<void> showSettleDebtSheet(
  BuildContext context, {
  required PersonBalance person,
}) {
  return Get.bottomSheet(
    _SettleDebtSheet(person: person),
    isScrollControlled: true,
  );
}

class _SettleDebtSheet extends StatefulWidget {
  final PersonBalance person;

  const _SettleDebtSheet({required this.person});

  @override
  State<_SettleDebtSheet> createState() => _SettleDebtSheetState();
}

class _SettleDebtSheetState extends State<_SettleDebtSheet> {
  /// What is still open with them, always positive.
  late final double _outstanding = widget.person.balance.abs();

  /// True when the member is the one who took the loan, so this is a payment
  /// going out. The entry has to run the other way to the balance, which is
  /// the whole reason the direction is not asked for here.
  bool get _payingOut => widget.person.owesMe;

  DebtFlow get _flow => _payingOut ? DebtFlow.got : DebtFlow.gave;

  MaterialColor get _accent => _payingOut ? Colors.deepOrange : Colors.green;

  late final TextEditingController _amount =
      TextEditingController(text: _plain(_outstanding));
  late final TextEditingController _note =
      TextEditingController(text: 'repayment_note'.tr);

  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.fromDateTime(DateTime.now());

  String? _amountError;

  /// Whole taka without a trailing `.0` — what somebody would have typed.
  static String _plain(double amount) => amount == amount.roundToDouble()
      ? amount.toStringAsFixed(0)
      : amount.toStringAsFixed(2);

  double get _typed => double.tryParse(_amount.text.trim()) ?? 0;

  @override
  void dispose() {
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

  Future<void> _pickTime() async {
    final TimeOfDay? picked =
        await showTimePicker(context: context, initialTime: _time);
    if (picked != null) setState(() => _time = picked);
  }

  Future<void> _save() async {
    final double amount = _typed;

    setState(() {
      if (amount <= 0) {
        _amountError = 'enter_an_amount'.tr;
      } else if (amount > _outstanding + 0.005) {
        // More than is owed would not settle the account, it would open one
        // the other way — which is a plain entry, not a repayment.
        _amountError = 'settle_over_outstanding'.tr;
      } else {
        _amountError = null;
      }
    });
    if (_amountError != null) return;

    final bool saved = await Get.find<PersonalController>().saveDebtEntry(
      personName: widget.person.name,
      personPhone: widget.person.phone,
      flow: _flow,
      amount: amount,
      note: _note.text,
      date: _date,
      time: _time,
    );

    if (saved) closeOverlayRoute();
  }

  @override
  Widget build(BuildContext context) {
    // No keyboard inset here — Get.bottomSheet already pads its own route by
    // `viewInsets.bottom`.
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
              _payingOut ? 'settle_pay_back'.tr : 'settle_collect'.tr,
              style: Theme.of(context)
                  .textTheme
                  .titleLarge
                  ?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              (_payingOut ? 'settle_pay_back_hint' : 'settle_collect_hint')
                  .trParams({'name': widget.person.name}),
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: AppUi.muted(context),
              ),
            ),
            const SizedBox(height: 16),
            _buildOutstandingRow(context),
            const SizedBox(height: 16),
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
              onChanged: (_) => setState(() => _amountError = null),
            ),
            const SizedBox(height: 10),
            _buildRemainingLine(context),
            const SizedBox(height: 16),
            _buildDateTimeRow(context),
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
                text: _payingOut ? 'settle_pay_back'.tr : 'settle_collect'.tr,
                height: 52,
                borderRadius: 14,
                color: _accent.shade600,
                isLoading: c.isSaving,
                onPressed: _save,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What is open, and a one-tap way back to all of it after somebody has
  /// typed over the box.
  Widget _buildOutstandingRow(BuildContext context) {
    final bool isFull = (_typed - _outstanding).abs() < 0.005;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppUi.tint(context, _accent),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _accent.withOpacity(0.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'settle_outstanding'.tr,
                  style: TextStyle(fontSize: 11, color: AppUi.muted(context)),
                ),
                const SizedBox(height: 3),
                Text(
                  AppUi.amount(_outstanding),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: AppUi.accent(context, _accent),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: isFull
                ? null
                : () => setState(() {
                      _amount.text = _plain(_outstanding);
                      _amountError = null;
                    }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isFull
                    ? Colors.transparent
                    : Theme.of(context).cardColor,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isFull
                      ? Colors.transparent
                      : AppUi.accent(context, _accent).withOpacity(0.4),
                ),
              ),
              child: Text(
                isFull ? 'settle_in_full'.tr : 'settle_pay_full'.tr,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isFull
                      ? AppUi.muted(context)
                      : AppUi.accent(context, _accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Where the account lands once this is saved — the arithmetic somebody
  /// would otherwise do in their head before pressing the button.
  Widget _buildRemainingLine(BuildContext context) {
    final double amount = _typed;
    if (amount <= 0 || amount > _outstanding + 0.005) {
      return const SizedBox.shrink();
    }

    final double left = _outstanding - amount;
    final bool clears = left.abs() < 0.005;

    return Row(
      children: [
        Icon(
          clears
              ? Icons.check_circle_outline_rounded
              : Icons.trending_down_rounded,
          size: 14,
          color: AppUi.muted(context),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            clears
                ? 'settle_clears_account'.tr
                : 'settle_remaining'.trParams({'amount': AppUi.amount(left)}),
            style: TextStyle(fontSize: 11.5, color: AppUi.muted(context)),
          ),
        ),
      ],
    );
  }

  Widget _buildDateTimeRow(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _pickerField(
            context,
            icon: Icons.calendar_today_rounded,
            label: DateFormat('dd MMM, yyyy').format(_date),
            onTap: _pickDate,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _pickerField(
            context,
            icon: Icons.access_time_rounded,
            label: _time.format(context),
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
            Icon(icon, size: 16, color: AppUi.accent(context, _accent)),
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
