import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CommonField extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback? onTap;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final String labelText;
  final TextStyle? labelStyle;
  final String? hintText;
  final TextStyle? hintStyle;
  final int maxLength;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;

  const CommonField({
    super.key,
    required this.controller,
    required this.maxLength,
    required this.keyboardType,
    required this.inputFormatters,
    this.onTap,
    this.onChanged,
    this.readOnly = false,
    this.labelText = '',
    this.labelStyle,
    this.hintText,
    this.hintStyle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;

    return SizedBox(
      width: _getWidth(context),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textAlign: TextAlign.center,
        inputFormatters: [
          LengthLimitingTextInputFormatter(maxLength),
          ...inputFormatters,
        ],
        readOnly: readOnly,
        decoration: InputDecoration(
          labelText: labelText,
          labelStyle: labelStyle ??
              theme.bodyLarge?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
          hintText: hintText,
          hintStyle: hintStyle ??
              theme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
          contentPadding: const EdgeInsets.only(top: 20.0),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.black, width: 2.0),
          ),
          focusedBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.blue, width: 2.0),
          ),
        ),
        style: theme.bodyLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        onTap: () {
          if (onTap != null) {
            onTap!();
          }
          if (controller.text.isNotEmpty) {
            controller.clear();
          }
        },
        onChanged: onChanged,
      ),
    );
  }

  double _getWidth(BuildContext context) {
    if (maxLength == 1) return 70;
    if (maxLength == 2) return MediaQuery.of(context).size.width * 0.25;
    if (maxLength == 3) return 100;
    if (maxLength == 4) return MediaQuery.of(context).size.width * 0.4;
    return MediaQuery.of(context).size.width * 0.5;
  }
}
