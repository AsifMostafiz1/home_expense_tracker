import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CustomTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final String? labelText;
  final IconData? prefixIcon;
  final Widget? suffixIcon;
  final bool obscureText;
  final TextInputType keyboardType;
  final int maxLines;
  final String? errorText;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final void Function(String)? onChanged;
  final bool readOnly;
  final VoidCallback? onTap;
  final TextCapitalization textCapitalization;

  /// Opens the keyboard as soon as the field is built — for a dialog or sheet
  /// whose only job is this one field.
  final bool autofocus;

  /// What the keyboard's action key does, and what happens when it is
  /// pressed — a form whose one required field is this can save from it.
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  const CustomTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.labelText,
    this.prefixIcon,
    this.suffixIcon,
    this.obscureText = false,
    this.keyboardType = TextInputType.text,
    this.maxLines = 1,
    this.errorText,
    this.inputFormatters,
    this.maxLength,
    this.onChanged,
    this.readOnly = false,
    this.onTap,
    this.textCapitalization = TextCapitalization.none,
    this.autofocus = false,
    this.textInputAction,
    this.onSubmitted,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (labelText != null) ...[
          Text(
            labelText!,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Theme.of(context).textTheme.titleSmall?.color?.withOpacity(0.8),
            ),
          ),
          const SizedBox(height: 8),
        ],
        TextFormField(
          controller: controller,
          autofocus: autofocus,
          obscureText: obscureText,
          keyboardType: keyboardType,
          maxLines: maxLines,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          onChanged: onChanged,
          readOnly: readOnly,
          onTap: onTap,
          textCapitalization: textCapitalization,
          textInputAction: textInputAction,
          onFieldSubmitted: onSubmitted,
          style: TextStyle(
            fontSize: 15,
            color: readOnly ? Colors.grey : null,
          ),
          decoration: InputDecoration(
            hintText: hintText,
            hintStyle: TextStyle(
              color: Theme.of(context).textTheme.bodySmall?.color?.withOpacity(0.4),
              fontSize: 14,
            ),
            prefixIcon: prefixIcon != null 
                ? Icon(prefixIcon, size: 20, color: readOnly ? Colors.grey.shade600 : Theme.of(context).colorScheme.primary) 
                : null,
            suffixIcon: suffixIcon,
            counterText: "",
            filled: true,
            fillColor: readOnly 
                ? (Theme.of(context).brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade100)
                : Theme.of(context).cardColor,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white24 
                    : Colors.grey.shade300, 
                width: 1
              ),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).brightness == Brightness.dark 
                    ? Colors.white24 
                    : Colors.grey.shade300, 
                width: 1
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: readOnly ? Colors.transparent : Theme.of(context).colorScheme.primary, 
                width: 1
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red, width: 1),
            ),
            errorText: errorText,
          ),
        ),
      ],
    );
  }
}
