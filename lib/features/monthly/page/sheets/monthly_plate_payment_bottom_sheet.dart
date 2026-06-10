import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../application/monthly_date_range_calculator.dart';
import '../../controllers/monthly_plate_controller.dart';
import '../../domain/monthly_parking_options.dart';
import 'widgets/monthly_payment_section.dart';

const _payInk = Color(0xFF101828);
const _payMuted = Color(0xFF667085);
const _payCanvas = Color(0xFFF3F6FA);
const _payPanel = Color(0xFFFFFFFF);
const _payLine = Color(0xFFD8DEE8);
const _payBlue = Color(0xFF2563EB);
const _payGreen = Color(0xFF059669);

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
  String _won(String value) {
    final amount = int.tryParse(value.trim());
    if (amount == null) return value.trim().isEmpty ? '-' : value;
    return '₩${NumberFormat.decimalPattern('ko_KR').format(amount)}';
  }

  Widget _summaryCard() {
    final c = widget.controller;
    final plate = c.buildPlateNumber();
    final countType = (c.nameController?.text.trim().isNotEmpty ?? false) ? c.nameController!.text.trim() : '-';
    final regularType = (c.selectedRegularType?.trim().isNotEmpty ?? false) ? c.selectedRegularType!.trim() : '-';
    c.ensurePaymentAmountDefault();
    final amount = c.paymentAmountController.text.trim().isNotEmpty ? c.paymentAmountController.text.trim() : '-';
    final durationValue = int.tryParse(c.durationController?.text.trim() ?? '') ?? 0;
    final duration = durationValue > 0
        ? MonthlyParkingOptions.durationLabel(
            regularType: c.selectedRegularType,
            duration: durationValue,
            periodUnit: c.selectedPeriodUnit,
          )
        : '-';
    final startDate = c.startDateController?.text.trim() ?? '';
    final endDate = c.endDateController?.text.trim() ?? '';
    final nextStart = c.previewExtendedStartDate();
    final nextEnd = c.previewExtendedEndDate();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _payPanel,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _payLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _payInk,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.receipt_long_outlined, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plate,
                      style: const TextStyle(
                        color: _payInk,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                        letterSpacing: -.3,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$countType · $regularType',
                      style: const TextStyle(color: _payMuted, fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _payBlue.withOpacity(.18)),
                ),
                child: const Text(
                  '결제 대상',
                  style: TextStyle(color: _payBlue, fontWeight: FontWeight.w900, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _payInk,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '이번 결제 금액',
                  style: TextStyle(color: Color(0xFFB8C2D6), fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  _won(amount),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 28),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          _PayKv(label: '현재 기간', value: '$startDate ~ $endDate'),
          _PayKv(label: '기간 단위', value: duration),
          _PayKv(label: '번호판 지역', value: c.dropdownValue),
          if (c.isExtended && nextStart != null && nextEnd != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _payGreen.withOpacity(.22)),
              ),
              child: Text(
                '연장 후 기간: ${MonthlyDateRangeCalculator.format(nextStart)} ~ ${MonthlyDateRangeCalculator.format(nextEnd)}',
                style: const TextStyle(color: _payGreen, fontWeight: FontWeight.w900),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: SizedBox(
          height: screenHeight - bottomInset,
          child: Container(
            decoration: const BoxDecoration(
              color: _payCanvas,
              borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              border: Border(top: BorderSide(color: _payLine)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBD5E1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: _payBlue,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.payments_outlined, color: Colors.white),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '결제 처리',
                              style: TextStyle(color: _payInk, fontWeight: FontWeight.w900, fontSize: 20),
                            ),
                            SizedBox(height: 3),
                            Text(
                              '결제 저장과 기간 연장을 한 번에 처리합니다.',
                              style: TextStyle(color: _payMuted, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () {
                          final nav = Navigator.of(context, rootNavigator: true);
                          if (nav.canPop()) nav.pop();
                        },
                        icon: const Icon(Icons.close, color: _payMuted),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _summaryCard(),
                        const SizedBox(height: 14),
                        MonthlyPaymentSection(
                          controller: widget.controller,
                          onPaymentAmountChanged: () => setState(() {}),
                          onExtendedChanged: (val) {
                            setState(() => widget.controller.isExtended = val ?? false);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PayKv extends StatelessWidget {
  const _PayKv({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(color: _payMuted, fontWeight: FontWeight.w800),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(color: _payInk, fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}
