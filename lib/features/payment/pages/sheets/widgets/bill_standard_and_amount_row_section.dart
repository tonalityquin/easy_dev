import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BillStandardAndAmountRowSection extends StatelessWidget {
  final String? selectedValue;
  final List<String> options;
  final Function(String?) onChanged;

  final TextEditingController amountController;
  final String standardLabel;
  final String amountLabel;

  
  final List<TextInputFormatter>? amountInputFormatters;

  const BillStandardAndAmountRowSection({
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
