// 파일 위치: input_pages/sections/adjustment_section.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/adjustment/adjustment_state.dart';
import '../../../utils/button/custom_adjustment_dropdown.dart';

class AdjustmentSection extends StatelessWidget {
  final String? selectedAdjustment;
  final ValueChanged<String?> onChanged;
  final Future<bool> Function() onRefresh;

  const AdjustmentSection({
    super.key,
    required this.selectedAdjustment,
    required this.onChanged,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('정산 유형', style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8.0),
        FutureBuilder<bool>(
          future: onRefresh().timeout(const Duration(seconds: 3), onTimeout: () => false),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              );
            }
            if (!snapshot.hasData || snapshot.data == false) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(
                  child: Text(
                    '설정된 정산 유형이 없어 무료입니다.',
                    style: TextStyle(color: Colors.green),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }

            final adjustmentState = context.watch<AdjustmentState>();
            final adjustmentList = adjustmentState.adjustments;
            if (adjustmentList.isEmpty) {
              return const Text('등록된 정산 유형이 없습니다.');
            }

            final dropdownItems = adjustmentList.map((adj) => adj.countType).toList();

            return CustomAdjustmentDropdown(
              items: dropdownItems,
              selectedValue: selectedAdjustment,
              onChanged: onChanged,
            );
          },
        ),
      ],
    );
  }
}
