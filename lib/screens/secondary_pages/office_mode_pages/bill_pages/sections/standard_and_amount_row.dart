import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class StandardAndAmountRow extends StatelessWidget {
  final String? selectedValue;
  final List<String> options;
  final Function(String?) onChanged;

  final TextEditingController amountController;
  final String standardLabel;
  final String amountLabel;

  /// 숫자 입력 제한 등 포맷터 주입 (미지정 시 기본으로 digitsOnly 적용)
  final List<TextInputFormatter>? amountInputFormatters;

  const StandardAndAmountRow({
    super.key,
    required this.selectedValue,
    required this.options,
    required this.onChanged,
    required this.amountController,
    required this.standardLabel,
    required this.amountLabel,
    this.amountInputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: selectedValue,
            decoration: InputDecoration(
              labelText: standardLabel,
              border: const OutlineInputBorder(),
            ),
            items: options
                .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                .toList(),
            onChanged: onChanged,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            // 기본값: digitsOnly
            inputFormatters:
            amountInputFormatters ?? [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: amountLabel,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
      ],
    );
  }
}
