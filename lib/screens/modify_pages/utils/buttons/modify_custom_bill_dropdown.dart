import 'package:flutter/material.dart';

class ModifyCustomBillDropdown extends StatelessWidget {
  final List<String> items; // ✅ countType 문자열 리스트
  final String? selectedValue; // ✅ 선택된 countType (String)
  final void Function(String?)? onChanged; // ✅ 문자열 선택 콜백

  const ModifyCustomBillDropdown({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: '정산 유형 선택',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        errorText: selectedValue == null ? '정산 유형을 선택해주세요' : null,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedValue, // ✅ 반드시 countType 문자열
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down),
          onChanged: onChanged,
          items: items.map((item) {
            return DropdownMenuItem<String>(
              value: item, // ✅ 각 아이템도 문자열
              child: Text(
                item,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
