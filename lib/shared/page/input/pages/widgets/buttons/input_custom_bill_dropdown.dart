import 'package:flutter/material.dart';

import '../../../../../../design_system/prompt_ui/prompt_ui_theme.dart';

class InputCustomBillDropdown extends StatelessWidget {
  final List<String> items;
  final String? selectedValue;
  final void Function(String?)? onChanged;

  const InputCustomBillDropdown({
    super.key,
    required this.items,
    required this.selectedValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return DropdownButtonFormField<String>(
      value: selectedValue,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: '정산 유형 선택',
        prefixIcon: const Icon(Icons.receipt_long_rounded),
        errorText: selectedValue == null ? '정산 유형을 선택해주세요' : null,
      ),
      dropdownColor: tokens.surfaceRaised,
      icon: Icon(Icons.keyboard_arrow_down_rounded, color: tokens.iconSecondary),
      onChanged: onChanged,
      items: items
          .map(
            (item) => DropdownMenuItem<String>(
              value: item,
              child: Text(
                item,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textPrimary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
          )
          .toList(),
    );
  }
}
