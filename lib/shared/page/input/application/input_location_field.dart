import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

class InputLocationField extends StatelessWidget {
  final TextEditingController controller;
  final bool readOnly;
  final double widthFactor;

  const InputLocationField({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.widthFactor = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    return SizedBox(
      width: screenWidth * widthFactor,
      child: TextField(
        controller: controller,
        readOnly: true,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              color: controller.text.trim().isEmpty
                  ? tokens.textSecondary
                  : tokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
        decoration: const InputDecoration(
          labelText: '선택된 주차 구역',
          prefixIcon: Icon(Icons.local_parking_rounded),
        ),
      ),
    );
  }
}
