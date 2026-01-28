import 'package:flutter/material.dart';

class MinorInputLocationField extends StatelessWidget {
  final TextEditingController controller;
  final bool readOnly;
  final double widthFactor;

  const MinorInputLocationField({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.widthFactor = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final screenWidth = MediaQuery.of(context).size.width;
    final bool isEmpty = controller.text.trim().isEmpty;

    final textStyle = (tt.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: isEmpty ? cs.onSurfaceVariant : cs.onSurface,
    );

    final hintStyle = (tt.bodyLarge ?? const TextStyle()).copyWith(
      fontSize: 18,
      fontWeight: FontWeight.bold,
      color: cs.onSurfaceVariant,
    );

    return SizedBox(
      width: screenWidth * widthFactor,
      child: TextField(
        controller: controller,
        readOnly: readOnly,
        textAlign: TextAlign.center,
        style: textStyle,
        decoration: InputDecoration(
          hintText: isEmpty ? '미지정' : null,
          hintStyle: hintStyle,
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: cs.outline, width: 2.0),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: cs.primary, width: 2.2),
          ),
        ),
      ),
    );
  }
}
