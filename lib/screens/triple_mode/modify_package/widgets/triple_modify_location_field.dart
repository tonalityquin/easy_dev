import 'package:flutter/material.dart';

class TripleModifyLocationField extends StatelessWidget {
  final TextEditingController controller;
  final bool readOnly;
  final double widthFactor;

  const TripleModifyLocationField({
    super.key,
    required this.controller,
    this.readOnly = true,
    this.widthFactor = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;

    final hasValue = controller.text.trim().isNotEmpty;

    return SizedBox(
      width: screenWidth * widthFactor,
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        textAlign: TextAlign.center,
        style: theme.bodyLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w900,
          color: hasValue ? cs.onSurface : cs.onSurfaceVariant,
        ),
        decoration: InputDecoration(
          hintText: hasValue ? null : '미지정',
          hintStyle: theme.bodyLarge?.copyWith(
            fontSize: 18,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: cs.onSurfaceVariant.withOpacity(0.85), width: 2.0),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: cs.primary, width: 2.2),
          ),
        ),
      ),
    );
  }
}
