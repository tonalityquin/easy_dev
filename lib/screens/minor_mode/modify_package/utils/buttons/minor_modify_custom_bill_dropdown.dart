import 'package:flutter/material.dart';

class MinorModifyCustomBillDropdown extends StatelessWidget {
  final List<String> items;
  final String? selectedValue;
  final void Function(String?)? onChanged;

  const MinorModifyCustomBillDropdown({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final normalizedItems =
    items.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

    // ✅ selectedValue가 items에 없으면 null로 처리(드롭다운 예외 방지)
    final String? normalizedSelected = (selectedValue ?? '').trim();
    final String? safeSelected = normalizedItems.contains(normalizedSelected)
        ? normalizedSelected
        : null;

    final bool disabled = onChanged == null || normalizedItems.isEmpty;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: '정산 유형 선택',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        errorText: safeSelected == null ? '정산 유형을 선택해주세요' : null,
        filled: true,
        fillColor: cs.surfaceVariant.withOpacity(0.35),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safeSelected,
          isExpanded: true,
          icon: Icon(Icons.keyboard_arrow_down, color: cs.outline),
          onChanged: disabled ? null : onChanged,
          items: normalizedItems.map((item) {
            return DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: const TextStyle(fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
