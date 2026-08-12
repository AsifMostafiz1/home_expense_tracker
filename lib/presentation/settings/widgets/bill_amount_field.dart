import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../utils/app_ui.dart';

/// The one money input the bill form uses.
///
/// Two shapes, same rules: [hero] is the headline field a section is built
/// around (the rent total), the default is the compact field that sits at the
/// end of a labelled row. Both keep the taka sign in the field itself, so the
/// number is never read without its unit.
class BillAmountField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String? errorText;
  final bool hero;
  final bool enabled;
  final double width;

  const BillAmountField({
    super.key,
    required this.controller,
    this.onChanged,
    this.errorText,
    this.hero = false,
    this.enabled = true,
    this.width = 116,
  });

  @override
  Widget build(BuildContext context) {
    final Color primary = Theme.of(context).colorScheme.primary;
    final bool hasError = errorText != null && errorText!.isNotEmpty;

    final Widget field = TextField(
      controller: controller,
      enabled: enabled,
      onChanged: onChanged,
      textAlign: hero ? TextAlign.left : TextAlign.right,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      style: TextStyle(
        fontSize: hero ? 22 : 15,
        fontWeight: FontWeight.bold,
        letterSpacing: -0.3,
        color: AppUi.body(context),
      ),
      decoration: InputDecoration(
        isDense: true,
        hintText: '0',
        hintStyle: TextStyle(
          fontSize: hero ? 22 : 15,
          fontWeight: FontWeight.bold,
          color: AppUi.muted(context).withOpacity(0.5),
        ),
        prefixText: '৳ ',
        prefixStyle: TextStyle(
          fontSize: hero ? 20 : 14,
          fontWeight: FontWeight.w600,
          color: AppUi.muted(context),
        ),
        filled: true,
        fillColor: AppUi.neutralSurface(context),
        contentPadding: hero
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 16)
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        border: _border(context, AppUi.hairline(context)),
        enabledBorder: _border(
          context,
          hasError ? Colors.red.shade300 : AppUi.hairline(context),
        ),
        focusedBorder: _border(context, hasError ? Colors.red : primary,
            width: hasError ? 1 : 1.4),
        disabledBorder: _border(context, AppUi.hairline(context)),
      ),
    );

    final Widget sized = hero ? field : SizedBox(width: width, child: field);

    if (!hasError) return sized;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        sized,
        const SizedBox(height: 6),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, size: 14, color: Colors.red.shade400),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                errorText!,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: Colors.red.shade400,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  OutlineInputBorder _border(BuildContext context, Color color,
          {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
}
