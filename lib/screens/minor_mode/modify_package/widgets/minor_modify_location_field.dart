import 'package:flutter/material.dart';

class MinorModifyLocationField extends StatelessWidget {
  final TextEditingController controller;

  /// ✅ 실제로 readOnly를 제어하도록 반영
  final bool readOnly;

  /// 화면 폭 대비 비율
  final double widthFactor;

  const MinorModifyLocationField({
    super.key,
    required this.controller,
    this.readOnly = true,
    this.widthFactor = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final screenWidth = MediaQuery.of(context).size.width;
    final text = controller.text.trim();
    final isEmpty = text.isEmpty;

    final Color valueColor = isEmpty ? cs.outline : cs.onSurface;
    final Color underlineColor =
    readOnly ? cs.outlineVariant.withOpacity(0.9) : cs.primary.withOpacity(0.9);

    return SizedBox(
      width: screenWidth * widthFactor,
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        enabled: true, // ✅ readOnly여도 enabled는 유지(선택/복사 UX)
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w800,
          color: valueColor,
        ),
        decoration: InputDecoration(
          hintText: isEmpty ? '미지정' : null,
          hintStyle: theme.textTheme.bodyLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: cs.outline,
          ),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: underlineColor, width: 2.0),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: underlineColor, width: 2.2),
          ),
        ),
      ),
    );
  }
}
