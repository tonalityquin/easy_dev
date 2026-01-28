import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/bill/bill_state.dart';

class MinorInputBillSection extends StatelessWidget {
  final String? selectedBill;

  final String selectedBillType;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String> onTypeChanged;

  final TextEditingController? countTypeController;

  const MinorInputBillSection({
    super.key,
    required this.selectedBill,
    required this.selectedBillType,
    required this.onChanged,
    required this.onTypeChanged,
    this.countTypeController,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final billState = context.watch<BillState>();
    final isLoading = billState.isLoading;
    final generalBills = billState.generalBills;

    final normalizedType = (selectedBillType == '고정') ? '변동' : selectedBillType;

    final isGeneral = normalizedType == '변동';
    final isMonthly = normalizedType == '정기';

    final filteredBills = generalBills;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '정산 유형',
          style: (tt.titleMedium ?? const TextStyle(fontSize: 18)).copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12.0),
        Row(
          children: [
            _buildTypeButton(
              context: context,
              label: '변동',
              isSelected: isGeneral,
              onTap: () => onTypeChanged('변동'),
            ),
            const SizedBox(width: 8),
            _buildTypeButton(
              context: context,
              label: '정기',
              isSelected: isMonthly,
              onTap: () => onTypeChanged('정기'),
            ),
          ],
        ),
        const SizedBox(height: 12.0),
        if (isMonthly) ...[
          TextField(
            controller: countTypeController,
            readOnly: true,
            enabled: false,
            decoration: InputDecoration(
              labelText: '정기 - 호실/구분(=countType)',
              hintText: '예: 1901호',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.9)),
              ),
              filled: true,
              fillColor: cs.surfaceContainerLow,
              labelStyle: TextStyle(color: cs.onSurfaceVariant),
              hintStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(0.9)),
            ),
          ),
        ] else ...[
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
                  '$normalizedType 정산 유형이 없습니다.',
                  style: TextStyle(color: cs.onSurfaceVariant),
                ),
              ),
            )
          else
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                side: BorderSide(color: cs.outlineVariant),
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
                    final tt2 = Theme.of(context).textTheme;

                    return DraggableScrollableSheet(
                      initialChildSize: 0.5,
                      minChildSize: 0.3,
                      maxChildSize: 0.9,
                      builder: (context, scrollController) {
                        return Container(
                          decoration: BoxDecoration(
                            color: cs2.surface,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            border: Border(
                              top: BorderSide(color: cs2.outlineVariant.withOpacity(0.85)),
                            ),
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
                                '$normalizedType 정산 선택',
                                style: (tt2.titleMedium ?? const TextStyle(fontSize: 18)).copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs2.onSurface,
                                ),
                              ),
                              const SizedBox(height: 24),
                              ...filteredBills.map((bill) {
                                final countType = (bill).countType;

                                return ListTile(
                                  title: Text(
                                    countType,
                                    style: TextStyle(color: cs2.onSurface),
                                  ),
                                  trailing: countType == selectedBill
                                      ? Icon(Icons.check, color: cs2.primary)
                                      : null,
                                  onTap: () {
                                    Navigator.pop(context);
                                    onChanged(countType);
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
                  Icon(Icons.arrow_drop_down, color: cs.onSurfaceVariant),
                ],
              ),
            ),
        ],
      ],
    );
  }

  Widget _buildTypeButton({
    required BuildContext context,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final cs = Theme.of(context).colorScheme;

    final bg = isSelected ? cs.primary : cs.surface;
    final fg = isSelected ? cs.onPrimary : cs.onSurface;
    final border = isSelected ? cs.primary : cs.outlineVariant;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            border: Border.all(color: border, width: 1.2),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
      ),
    );
  }
}
