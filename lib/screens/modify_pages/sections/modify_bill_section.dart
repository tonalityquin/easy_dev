import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/bill/bill_state.dart';
import '../utils/buttons/modify_custom_bill_dropdown.dart';

class ModifyBillSection extends StatelessWidget {
  final String? selectedBill;
  final ValueChanged<String?> onChanged;

  const ModifyBillSection({
    super.key,
    required this.selectedBill,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final billState = context.watch<BillState>();
    final billList = billState.bills;
    final isLoading = billState.isLoading;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '정산 유형',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8.0),
        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (billList.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                '설정된 정산 유형이 없어 무료입니다.',
                style: TextStyle(color: Colors.green),
                textAlign: TextAlign.center,
              ),
            ),
          )
        else
          ModifyCustomBillDropdown(
            items: billList.map((bill) => bill.countType).toList(),
            selectedValue: selectedBill,
            onChanged: onChanged,
          ),
      ],
    );
  }
}
