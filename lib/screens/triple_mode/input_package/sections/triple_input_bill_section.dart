import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/bill/bill_state.dart';

class TripleInputBillSection extends StatelessWidget {
  final String? selectedBill;

  final String selectedBillType;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String> onTypeChanged;

  final TextEditingController? countTypeController;

  const TripleInputBillSection({
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

    final billState = context.watch<BillState>();
    final isLoading = billState.isLoading;
    final generalBills = billState.generalBills;

    final normalizedType = (selectedBillType == '고정') ? '변동' : selectedBillType;

    final isGeneral = normalizedType == '변동';
    final isMonthly = normalizedType == '정기';

    // 변동은 generalBills만 사용(기존 유지)
    final filteredBills = generalBills;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '정산 유형',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12.0),

        // 타입 토글
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
                borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.65)),
              ),
              filled: true,
              fillColor: cs.surfaceContainerLow,
              labelStyle: TextStyle(color: cs.onSurfaceVariant),
              hintStyle: TextStyle(color: cs.onSurfaceVariant),
            ),
          ),
        ] else ...[
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
                  '$normalizedType 정산 유형이 없습니다.',
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
              ).copyWith(
                overlayColor: MaterialStateProperty.resolveWith<Color?>(
                      (states) => states.contains(MaterialState.pressed)
                      ? cs.outlineVariant.withOpacity(0.12)
                      : null,
                ),
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
                          decoration: BoxDecoration(
                            color: cs.surface,
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                            border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
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
                                    color: cs.outlineVariant.withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                              Text(
                                '$normalizedType 정산 선택',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w900,
                                  color: cs.onSurface,
                                ),
                              ),
                              const SizedBox(height: 24),
                              ...filteredBills.map((bill) {
                                final countType = bill.countType;

                                return ListTile(
                                  title: Text(
                                    countType,
                                    style: TextStyle(color: cs.onSurface),
                                  ),
                                  trailing: countType == selectedBill
                                      ? Icon(Icons.check, color: cs.primary)
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
    final side = BorderSide(
      color: isSelected ? cs.primary.withOpacity(0.65) : cs.outlineVariant.withOpacity(0.85),
      width: 1.2,
    );

    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: bg,
              border: Border.fromBorderSide(side),
              borderRadius: BorderRadius.circular(10),
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
      ),
    );
  }
}
