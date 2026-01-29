// lib/screens/secondary_package/office_mode_package/monthly_management_package/monthly_payment_bottom_sheet.dart
import 'package:flutter/material.dart';

import 'monthly_plate_controller.dart';
import 'sections/monthly_payment_section.dart';

/// ✅ 결제 전용 바텀시트
/// - “수정 모드에서 결제 탭으로 전환” 방식이 아니라
///   “결제 버튼 → 별도 시트로 독립 진입” 방식
class MonthlyPaymentBottomSheet extends StatefulWidget {
  final MonthlyPlateController controller;

  const MonthlyPaymentBottomSheet({
    super.key,
    required this.controller,
  });

  @override
  State<MonthlyPaymentBottomSheet> createState() => _MonthlyPaymentBottomSheetState();
}

class _MonthlyPaymentBottomSheetState extends State<MonthlyPaymentBottomSheet> {
  static const String _screenTag = 'monthly payment';

  // 11시 라벨
  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: cs.onSurfaceVariant.withOpacity(.72),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return IgnorePointer(
      child: Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.only(left: 4, top: 4),
          child: Semantics(
            label: 'screen_tag: $_screenTag',
            child: Text(_screenTag, style: style),
          ),
        ),
      ),
    );
  }

  Widget _buildPaymentSummaryCard(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final c = widget.controller;

    final plate = c.buildPlateNumber();

    final countType = (c.nameController?.text.trim().isNotEmpty ?? false) ? c.nameController!.text.trim() : '-';

    final regularType = (c.selectedRegularType?.trim().isNotEmpty ?? false) ? c.selectedRegularType!.trim() : '-';

    final amount = (c.amountController?.text.trim().isNotEmpty ?? false) ? c.amountController!.text.trim() : '-';

    final duration = (c.durationController?.text.trim().isNotEmpty ?? false) ? c.durationController!.text.trim() : '-';

    final periodUnit = c.selectedPeriodUnit;

    final startDate = c.startDateController?.text.trim() ?? '';
    final endDate = c.endDateController?.text.trim() ?? '';

    Widget kv(String k, String v) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(
              k,
              style: text.bodySmall?.copyWith(
                color: cs.onSurfaceVariant.withOpacity(.78),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.06),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withOpacity(.65),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                ),
                child: Icon(Icons.directions_car_outlined, color: cs.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '결제 대상 정보',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(.70),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.70)),
                ),
                child: Text(
                  '읽기 전용',
                  style: text.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurfaceVariant.withOpacity(.85),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          kv('번호판', plate),
          kv('지역', c.dropdownValue),
          kv('정산 이름', countType),
          kv('주차 타입', regularType),
          kv('금액', amount),
          kv('기간', '$duration $periodUnit'),
          kv('시작/종료', '$startDate ~ $endDate'),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // 키보드 여백 반영 + 최상단까지 차오르도록 높이 고정
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;
    final effectiveHeight = screenHeight - bottomInset;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: effectiveHeight,
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                  boxShadow: [
                    BoxShadow(
                      color: cs.shadow.withOpacity(.10),
                      blurRadius: 12,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Drag handle
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 16),
                        decoration: BoxDecoration(
                          color: cs.outlineVariant.withOpacity(.60),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),

                    // 헤더
                    Row(
                      children: [
                        Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withOpacity(.65),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                          ),
                          child: Icon(Icons.payments_outlined, color: cs.primary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            '결제',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '닫기',
                          onPressed: () {
                            final nav = Navigator.of(context, rootNavigator: true);
                            if (nav.canPop()) nav.pop();
                          },
                          icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPaymentSummaryCard(context),
                            const SizedBox(height: 16),
                            MonthlyPaymentSection(
                              controller: widget.controller,
                              onExtendedChanged: (val) {
                                // 요약 카드에는 직접 영향 없지만 상태 정합성 위해 반영
                                setState(() {
                                  widget.controller.isExtended = val ?? false;
                                });
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              _buildScreenTag(context),
            ],
          ),
        ),
      ),
    );
  }
}
