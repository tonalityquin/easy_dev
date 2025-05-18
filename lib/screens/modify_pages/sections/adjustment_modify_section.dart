import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:easydev/states/adjustment/adjustment_state.dart';
import 'package:easydev/models/adjustment_model.dart';
import 'package:easydev/utils/button/custom_adjustment_dropdown.dart';
import 'package:easydev/enums/plate_type.dart';

class AdjustmentModifySection extends StatelessWidget {
  final PlateType collectionKey;
  final String? selectedAdjustment;
  final ValueChanged<String?> onChanged;
  final Future<bool> Function() onRefresh;
  final ValueChanged<AdjustmentModel> onAutoFill;

  const AdjustmentModifySection({
    super.key,
    required this.collectionKey,
    required this.selectedAdjustment,
    required this.onChanged,
    required this.onRefresh,
    required this.onAutoFill,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '정산 유형',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
        ),
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
                child: Text(
                  '정산 유형 정보를 불러오지 못했습니다.',
                  style: TextStyle(color: Colors.red),
                ),
              );
            }

            final adjustmentList = context.watch<AdjustmentState>().adjustments;

            if (adjustmentList.isEmpty) {
              return const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  '등록된 정산 유형이 없습니다.',
                  style: TextStyle(color: Colors.green),
                ),
              );
            }

            final dropdownItems = adjustmentList.map((adj) => adj.countType).toList();

            return CustomAdjustmentDropdown(
              items: dropdownItems,
              selectedValue: selectedAdjustment,
              onChanged: collectionKey == PlateType.departureCompleted
                  ? null
                  : (newValue) {
                final adjustment = adjustmentList.firstWhere(
                      (adj) => adj.countType == newValue,
                  orElse: () => AdjustmentModel(
                    id: 'empty',
                    countType: '',
                    area: '',
                    basicStandard: 0,
                    basicAmount: 0,
                    addStandard: 0,
                    addAmount: 0,
                  ),
                );

                onChanged(newValue);
                if (adjustment.countType.isNotEmpty) {
                  onAutoFill(adjustment);
                }
              },
            );
          },
        ),
      ],
    );
  }
}
