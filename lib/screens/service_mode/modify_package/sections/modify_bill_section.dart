import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/bill/bill_state.dart';
import '../../../../models/bill_model.dart';
import '../../../../models/regular_bill_model.dart';

class ModifyBillSection extends StatelessWidget {
  final String? selectedBill;
  final String selectedBillType;
  final ValueChanged<dynamic> onChanged;

  /// 정기 버튼 제거로 인해 외부에서 전달되더라도 사용하지 않음(호환 유지용)
  final ValueChanged<String> onTypeChanged;

  const ModifyBillSection({
    super.key,
    required this.selectedBill,
    required this.selectedBillType,
    required this.onChanged,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final billState = context.watch<BillState>();
    final isLoading = billState.isLoading;
    final generalBills = billState.generalBills;
    final regularBills = billState.regularBills;

    // ✅ 정기 버튼 제거: 타입 변경 UI 없음 → 현재 타입 기준으로만 리스트 구성
    final bool isGeneral = selectedBillType == '변동';
    final filteredBills = isGeneral ? generalBills : regularBills;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '정산 유형',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12.0),

        // ✅ 정기/변동 타입 버튼 삭제

        if (isLoading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (filteredBills.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                '${isGeneral ? '변동' : '정기'} 정산 유형이 없습니다.',
                style: const TextStyle(color: Colors.grey),
              ),
            ),
          )
        else
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              side: const BorderSide(color: Colors.black),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) {
                  return DraggableScrollableSheet(
                    initialChildSize: 0.5,
                    minChildSize: 0.3,
                    maxChildSize: 0.9,
                    builder: (context, scrollController) {
                      return Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        padding: const EdgeInsets.all(16),
                        child: ListView(
                          controller: scrollController,
                          children: [
                            Center(
                              child: Container(
                                width: 40,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 16),
                                decoration: BoxDecoration(
                                  color: Colors.grey,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Text(
                              '${isGeneral ? '변동' : '정기'} 정산 선택',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 24),

                            ...filteredBills.map((bill) {
                              final countType = isGeneral
                                  ? (bill as BillModel).countType
                                  : (bill as RegularBillModel).countType;

                              return ListTile(
                                title: Text(countType),
                                trailing: countType == selectedBill
                                    ? const Icon(Icons.check, color: Colors.green)
                                    : null,
                                onTap: () {
                                  Navigator.pop(context);
                                  onChanged(bill);
                                },
                              );
                            }),
                          ],
                        ),
                      );
                    },
                  );
                },
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(selectedBill ?? '정산 선택'),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
      ],
    );
  }
}
