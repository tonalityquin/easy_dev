import 'package:flutter/material.dart';

class TripleInputLocationField extends StatelessWidget {
  final TextEditingController controller;
  final bool readOnly;
  final double widthFactor;

  const TripleInputLocationField({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.widthFactor = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final screenWidth = MediaQuery.of(context).size.width;

    final hasValue = controller.text.trim().isNotEmpty;

    final valueStyle = (textTheme.titleMedium ?? const TextStyle(fontSize: 18)).copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w900,
      color: hasValue ? cs.onSurface : cs.onSurfaceVariant,
    );

    return SizedBox(
      width: screenWidth * widthFactor,
      child: TextField(
        controller: controller,
        readOnly: true, // 기존 유지(외부에서 선택)
        textAlign: TextAlign.center,
        style: valueStyle,
        decoration: InputDecoration(
          hintText: hasValue ? null : '미지정',
          hintStyle: valueStyle.copyWith(
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
          // ✅ 기존: Underline black 하드코딩 → outlineVariant 기반
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.95), width: 2.0),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: cs.primary.withOpacity(0.85), width: 2.2),
          ),
        ),
      ),
    );
  }
}
