import 'package:flutter/material.dart';

class DoubleModifyLocationField extends StatelessWidget {
  final TextEditingController controller;
  final bool readOnly;
  final double widthFactor;

  const DoubleModifyLocationField({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.widthFactor = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;

    final isEmpty = controller.text.trim().isEmpty;

    return SizedBox(
      width: screenWidth * widthFactor,
      child: TextField(
        controller: controller,
        readOnly: true, // 기존 동작 유지(이 위젯은 표시용)
        textAlign: TextAlign.center,
        style: theme.bodyLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: isEmpty ? cs.onSurfaceVariant : cs.onSurface,
        ),
        decoration: InputDecoration(
          hintText: isEmpty ? '미지정' : null,
          hintStyle: theme.bodyLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: cs.onSurfaceVariant,
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: cs.onSurface, width: 2.0),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: cs.primary, width: 2.2),
          ),
        ),
      ),
    );
  }
}
