import 'package:flutter/material.dart';

class TripleModifyCustomBillDropdown extends StatelessWidget {
  final List<String> items;
  final String? selectedValue;
  final void Function(String?)? onChanged;

  const TripleModifyCustomBillDropdown({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final borderRadius = BorderRadius.circular(12);

    OutlineInputBorder border(Color c) => OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: BorderSide(color: c, width: 1.1),
    );

    return InputDecorator(
      decoration: InputDecoration(
        labelText: '정산 유형 선택',
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        errorText: selectedValue == null ? '정산 유형을 선택해주세요' : null,
        filled: true,
        fillColor: cs.surface,
        enabledBorder: border(cs.outlineVariant.withOpacity(0.85)),
        focusedBorder: border(cs.primary.withOpacity(0.85)),
        errorBorder: border(cs.error.withOpacity(0.85)),
        focusedErrorBorder: border(cs.error.withOpacity(0.95)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedValue,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: cs.onSurfaceVariant),
          onChanged: onChanged,
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
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
