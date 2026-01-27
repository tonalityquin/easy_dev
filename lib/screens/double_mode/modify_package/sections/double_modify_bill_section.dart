import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/bill/bill_state.dart';
import '../../../../models/bill_model.dart';
import '../../../../models/regular_bill_model.dart';

class DoubleModifyBillSection extends StatelessWidget {
  final String? selectedBill;
  final String selectedBillType;
  final ValueChanged<dynamic> onChanged;

  /// 타입 토글 UI 삭제로 인해 호출되지 않지만, 기존 시그니처 호환을 위해 유지
  final ValueChanged<String> onTypeChanged;

  const DoubleModifyBillSection({
    super.key,
    required this.selectedBill,
    required this.selectedBillType,
    required this.onChanged,
    required this.onTypeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final billState = context.watch<BillState>();
    final isLoading = billState.isLoading;
    final generalBills = billState.generalBills;
    final regularBills = billState.regularBills;

    final isGeneral = selectedBillType == '변동';
    final filteredBills = isGeneral ? generalBills : regularBills;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '정산 유형',
          style: TextStyle(
            fontSize: 18.0,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12.0),

        if (isLoading)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
            ),
          )
        else if (filteredBills.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Text(
                '${isGeneral ? '변동' : '고정'} 정산 유형이 없습니다.',
                style: TextStyle(color: cs.onSurfaceVariant),
              ),
            ),
          )
        else
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
              backgroundColor: cs.surface,
              foregroundColor: cs.onSurface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (_) {
                  final cs2 = Theme.of(context).colorScheme;

                  return DraggableScrollableSheet(
                    initialChildSize: 0.5,
                    minChildSize: 0.3,
                    maxChildSize: 0.9,
                    builder: (context, scrollController) {
                      return Container(
                        decoration: BoxDecoration(
                          color: cs2.surface,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                          border: Border.all(color: cs2.outlineVariant.withOpacity(0.85)),
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
                                  color: cs2.outlineVariant.withOpacity(0.9),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Text(
                              '${isGeneral ? '변동' : '고정'} 정산 선택',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                                color: cs2.onSurface,
                              ),
                            ),
                            const SizedBox(height: 24),

                            ...filteredBills.map((bill) {
                              final countType = isGeneral
                                  ? (bill as BillModel).countType
                                  : (bill as RegularBillModel).countType;

                              final selected = countType == selectedBill;

                              return ListTile(
                                title: Text(
                                  countType,
                                  style: TextStyle(
                                    color: cs2.onSurface,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                trailing: selected
                                    ? Icon(Icons.check, color: cs2.tertiary)
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
                Text(
                  selectedBill ?? '정산 선택',
                  style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w800),
                ),
                Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
              ],
            ),
          ),
      ],
    );
  }
}
