import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'fee_calculator.dart';

class BillResult {
  final String paymentMethod;
  final int lockedFee;
  final FeeMode feeMode;
  final int adjustment;
  final String? reason;

  BillResult({
    required this.paymentMethod,
    required this.lockedFee,
    required this.feeMode,
    required this.adjustment,
    this.reason,
  });
}

Future<BillResult?> showOnTapBillingBottomSheet({
  required BuildContext context,
  required int entryTimeInSeconds,
  required int currentTimeInSeconds,
  required int basicStandard,
  required int basicAmount,
  required int addStandard,
  required int addAmount,
  required String billingType,
  int? regularAmount,
  int? regularDurationHours,
}) {
  return showModalBottomSheet<BillResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => BillingBottomSheet(
      entryTimeInSeconds: entryTimeInSeconds,
      currentTimeInSeconds: currentTimeInSeconds,
      basicStandard: basicStandard,
      basicAmount: basicAmount,
      addStandard: addStandard,
      addAmount: addAmount,
      billingType: billingType,
      regularAmount: regularAmount,
      regularDurationHours: regularDurationHours,
    ),
  );
}

class BillingBottomSheet extends StatefulWidget {
  final int entryTimeInSeconds;
  final int currentTimeInSeconds;
  final int basicStandard;
  final int basicAmount;
  final int addStandard;
  final int addAmount;
  final String billingType;
  final int? regularAmount;
  final int? regularDurationHours;

  const BillingBottomSheet({
    super.key,
    required this.entryTimeInSeconds,
    required this.currentTimeInSeconds,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
    required this.billingType,
    this.regularAmount,
    this.regularDurationHours,
  });

  @override
  State<BillingBottomSheet> createState() => _BillingBottomSheetState();
}

class _BillingBottomSheetState extends State<BillingBottomSheet> {
  final List<String> paymentOptions = ['계좌', '카드', '현금'];
  final List<String> modeLabels = ['일반', '할증', '할인'];

  int _selectedPaymentIndex = 0;
  FeeMode _feeMode = FeeMode.normal;
  int _userAdjustment = 0;
  String? _inputReason;

  final TextEditingController _amountController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  final formatCurrency = NumberFormat("#,###", "ko_KR");
  final formatDate = DateFormat("yyyy-MM-dd HH시 mm분");

  String get _selectedPayment => paymentOptions[_selectedPaymentIndex];

  bool get isRegular => widget.billingType.contains('월 주차') || widget.billingType.contains('정기');

  int _calculateBaseFee() {
    if (isRegular) return widget.regularAmount ?? 0;
    return calculateFee(
      entryTimeInSeconds: widget.entryTimeInSeconds,
      currentTimeInSeconds: widget.currentTimeInSeconds,
      basicStandard: widget.basicStandard,
      basicAmount: widget.basicAmount,
      addStandard: widget.addStandard,
      addAmount: widget.addAmount,
      userAdjustment: 0,
      mode: FeeMode.normal,
    );
  }

  int _getLockedFee() {
    return calculateFee(
      entryTimeInSeconds: widget.entryTimeInSeconds,
      currentTimeInSeconds: widget.currentTimeInSeconds,
      basicStandard: widget.basicStandard,
      basicAmount: widget.basicAmount,
      addStandard: widget.addStandard,
      addAmount: widget.addAmount,
      userAdjustment: _userAdjustment,
      mode: _feeMode,
      billingType: widget.billingType,
      regularAmount: widget.regularAmount,
    );
  }

  String _formatMinutesToHourMinute(int totalMinutes) {
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    return '$hours시 $minutes분';
  }

  String _getFormattedParkedTime() {
    final totalMinutes = ((widget.currentTimeInSeconds - widget.entryTimeInSeconds) / 60).ceil();
    return _formatMinutesToHourMinute(totalMinutes);
  }

  String _getFormattedEntryTime() {
    final entry = DateTime.fromMillisecondsSinceEpoch(widget.entryTimeInSeconds * 1000);
    return formatDate.format(entry);
  }

  bool get _isSubmitEnabled {
    if (_feeMode == FeeMode.normal) return true;
    return _amountController.text.isNotEmpty && _reasonController.text.trim().isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    final baseFee = _calculateBaseFee();
    final lockedFee = _getLockedFee();

    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, scrollController) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: ListView(
                controller: scrollController,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Row(
                    children: [
                      Icon(Icons.receipt_long, color: Colors.green),
                      SizedBox(width: 8),
                      Text('정산 정보 확인', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Card(
                    elevation: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: isRegular
                            ? [
                                const Text('정기 주차 정보', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                _buildInfoRow('정기 유형', widget.billingType),
                                if (widget.regularAmount != null)
                                  _buildInfoRow('정기 요금', '₩${formatCurrency.format(widget.regularAmount)}'),
                                if (widget.regularDurationHours != null)
                                  _buildInfoRow('정기권 시간', '${widget.regularDurationHours}시간'),
                                _buildInfoRow('입차 시간', _getFormattedEntryTime()),
                                _buildInfoRow('주차 시간', _getFormattedParkedTime()),
                              ]
                            : [
                                const Text('요금 기준', style: TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                _buildInfoRow('입차 시간', _getFormattedEntryTime()),
                                _buildInfoRow('기본 시간', _formatMinutesToHourMinute(widget.basicStandard)),
                                _buildInfoRow('기본 금액', '₩${formatCurrency.format(widget.basicAmount)}'),
                                _buildInfoRow('추가 시간', _formatMinutesToHourMinute(widget.addStandard)),
                                _buildInfoRow('추가 금액', '₩${formatCurrency.format(widget.addAmount)}'),
                                _buildInfoRow('주차 시간', _getFormattedParkedTime()),
                                _buildInfoRow('요금 모드 적용 전 금액', '₩${formatCurrency.format(baseFee)}'),
                              ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text("지불 방법", style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(paymentOptions.length, (index) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ElevatedButton(
                            onPressed: () => setState(() => _selectedPaymentIndex = index),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _selectedPaymentIndex == index ? Colors.green : Colors.grey.shade200,
                              foregroundColor: _selectedPaymentIndex == index ? Colors.white : Colors.black87,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text(paymentOptions[index], style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 24),
                  const Text("요금 모드", style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 8),
                  Row(
                    children: List.generate(FeeMode.values.length, (index) {
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: ElevatedButton(
                            onPressed: () {
                              setState(() {
                                _feeMode = FeeMode.values[index];
                                _userAdjustment = 0;
                                _inputReason = null;
                                _amountController.clear();
                                _reasonController.clear();
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _feeMode == FeeMode.values[index] ? Colors.green : Colors.grey.shade200,
                              foregroundColor: _feeMode == FeeMode.values[index] ? Colors.white : Colors.black87,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text(modeLabels[index], style: const TextStyle(fontSize: 16)),
                          ),
                        ),
                      );
                    }),
                  ),
                  if (_feeMode != FeeMode.normal) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: _amountController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: InputDecoration(
                        labelText: _feeMode == FeeMode.plus ? '할증 금액 입력' : '할인 금액 입력',
                        border: const OutlineInputBorder(),
                        suffixText: '₩',
                      ),
                      onChanged: (value) {
                        setState(() {
                          _userAdjustment = int.tryParse(value) ?? 0;
                        });
                      },
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _reasonController,
                      decoration: const InputDecoration(
                        labelText: '사유를 입력하세요',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.edit_note),
                      ),
                      onChanged: (value) {
                        setState(() {
                          _inputReason = value.trim();
                        });
                      },
                    ),
                  ],
                  const SizedBox(height: 24),
                  Text(
                    '예상 정산 금액: ₩${formatCurrency.format(lockedFee)}',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton(
                        onPressed: _isSubmitEnabled
                            ? () {
                                Navigator.of(context).pop(
                                  BillResult(
                                    paymentMethod: _selectedPayment,
                                    lockedFee: lockedFee,
                                    feeMode: _feeMode,
                                    adjustment: _userAdjustment,
                                    reason: _feeMode == FeeMode.normal ? null : _inputReason,
                                  ),
                                );
                              }
                            : null,
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        child: const Text('확인'),
                      ),
                      const SizedBox(width: 16),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('취소', style: TextStyle(fontSize: 16)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 14, color: Colors.black54)),
          Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}
