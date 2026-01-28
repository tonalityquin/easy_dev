import 'package:flutter/material.dart';

class MinorInputCustomBillDropdown extends StatelessWidget {
  final List<String> items;
  final String? selectedValue;
  final void Function(String?)? onChanged;

  const MinorInputCustomBillDropdown({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bool hasError = selectedValue == null;

    OutlineInputBorder border(Color color, {double width = 1.2}) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return InputDecorator(
      decoration: InputDecoration(
        labelText: '정산 유형 선택',
        labelStyle: TextStyle(color: cs.onSurfaceVariant),
        border: border(cs.outlineVariant),
        enabledBorder: border(cs.outlineVariant),
        focusedBorder: border(cs.primary, width: 1.6),
        errorBorder: border(cs.error, width: 1.6),
        focusedErrorBorder: border(cs.error, width: 1.8),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        errorText: hasError ? '정산 유형을 선택해주세요' : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedValue,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: cs.onSurfaceVariant),
          dropdownColor: cs.surface,
          onChanged: onChanged,
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
