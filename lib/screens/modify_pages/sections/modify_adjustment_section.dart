import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/adjustment/adjustment_state.dart';
import '../utils/buttons/modify_custom_adjustment_dropdown.dart';

class ModifyAdjustmentSection extends StatelessWidget {
  final String? selectedAdjustment;
  final ValueChanged<String?> onChanged;

  const ModifyAdjustmentSection({
    super.key,
    required this.selectedAdjustment,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final adjustmentState = context.watch<AdjustmentState>();
    final adjustmentList = adjustmentState.adjustments;
    final isLoading = adjustmentState.isLoading;

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
        else if (adjustmentList.isEmpty)
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
          ModifyCustomAdjustmentDropdown(
            items: adjustmentList.map((adj) => adj.countType).toList(),
            selectedValue: selectedAdjustment,
            onChanged: onChanged,
          ),
      ],
    );
  }
}
