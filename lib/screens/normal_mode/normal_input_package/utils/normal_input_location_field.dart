import 'package:flutter/material.dart';

class NormalInputLocationField extends StatelessWidget {
  final TextEditingController controller;
  final bool readOnly;
  final double widthFactor;

  const NormalInputLocationField({
    super.key,
    required this.controller,
    this.readOnly = false,
    this.widthFactor = 0.7,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.of(context).size.width;
    return SizedBox(
      width: screenWidth * widthFactor,
      child: TextField(
        controller: controller,
        readOnly: true,
        textAlign: TextAlign.center,
        style: theme.bodyLarge?.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.bold,
          color: controller.text.isEmpty ? Colors.grey : Colors.black,
        ),
        decoration: InputDecoration(
          hintText: controller.text.isEmpty ? '미지정' : null,
          hintStyle: theme.bodyLarge?.copyWith(
            fontSize: 18,
            color: Colors.grey,
          ),
          enabledBorder: const UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.black, width: 2.0),
          ),
        ),
      ),
    );
  }
}
