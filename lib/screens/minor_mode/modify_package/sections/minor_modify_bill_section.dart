import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/bill/bill_state.dart';
import '../../../../models/bill_model.dart';
import '../../../../models/regular_bill_model.dart';

class MinorModifyBillSection extends StatelessWidget {
  final String? selectedBill;
  final String selectedBillType;
  final ValueChanged<dynamic> onChanged;

  /// 타입 토글 UI 삭제로 인해 호출되지 않지만, 기존 시그니처 호환을 위해 유지
  final ValueChanged<String> onTypeChanged;

  const MinorModifyBillSection({
    super.key,
    required this.selectedBill,
    required this.selectedBillType,
    required this.onChanged,
    required this.onTypeChanged,
  });

  bool _isGeneralType(String t) => t.trim() == '변동';
  String _normalizedTypeLabel(String t) => _isGeneralType(t) ? '변동' : '고정';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final billState = context.watch<BillState>();
    final isLoading = billState.isLoading;

    final generalBills = billState.generalBills;
    final regularBills = billState.regularBills;

    final isGeneral = _isGeneralType(selectedBillType);
    final filteredBills = isGeneral ? generalBills : regularBills;

    final labelType = _normalizedTypeLabel(selectedBillType);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '정산 유형',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 12),

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
                '$labelType 정산 유형이 없습니다.',
                style: TextStyle(color: cs.outline),
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
              elevation: 0,
            ),
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                isScrollControlled: true,
                useSafeArea: true,
                backgroundColor: Colors.transparent,
                builder: (_) {
                  return DraggableScrollableSheet(
                    initialChildSize: 0.55,
                    minChildSize: 0.35,
                    maxChildSize: 0.92,
                    builder: (context, scrollController) {
                      return Container(
                        decoration: BoxDecoration(
                          color: cs.surface,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
                        ),
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                        child: Column(
                          children: [
                            Center(
                              child: Container(
                                width: 44,
                                height: 4,
                                margin: const EdgeInsets.only(bottom: 10),
                                decoration: BoxDecoration(
                                  color: cs.outlineVariant.withOpacity(0.75),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    '$labelType 정산 선택',
                                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: '닫기',
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: Icon(Icons.close, color: cs.outline),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: ListView(
                                controller: scrollController,
                                children: [
                                  ...filteredBills.map((bill) {
                                    final countType = isGeneral
                                        ? (bill as BillModel).countType
                                        : (bill as RegularBillModel).countType;

                                    final isSelected = (countType == (selectedBill ?? '').trim());

                                    return ListTile(
                                      title: Text(
                                        countType,
                                        style: const TextStyle(fontWeight: FontWeight.w800),
                                      ),
                                      trailing: isSelected
                                          ? Icon(Icons.check_circle, color: cs.primary)
                                          : null,
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        onChanged(bill);
                                      },
                                    );
                                  }),
                                ],
                              ),
                            ),
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
                Flexible(
                  child: Text(
                    (selectedBill ?? '정산 선택').trim().isEmpty ? '정산 선택' : (selectedBill ?? '').trim(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.arrow_drop_down),
              ],
            ),
          ),
      ],
    );
  }
}
