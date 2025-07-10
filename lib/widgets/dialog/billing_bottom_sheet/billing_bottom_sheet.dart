import 'package:flutter/material.dart';
import 'fee_calculator.dart'; // enum FeeMode, calculateFee 정의된 파일

/// 요금 정산 결과 모델
class BillResult {
  final String paymentMethod;
  final int lockedFee;

  BillResult(this.paymentMethod, this.lockedFee);
}

/// 바텀시트 호출 함수
Future<BillResult?> showOnTapBillingBottomSheet({
  required BuildContext context,
  required int entryTimeInSeconds,
  required int currentTimeInSeconds,
  required int basicStandard,
  required int basicAmount,
  required int addStandard,
  required int addAmount,
  FeeMode feeMode = FeeMode.normal,
  int userAdjustment = 0,
}) async {
  return await showModalBottomSheet<BillResult>(
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
      feeMode: feeMode,
      userAdjustment: userAdjustment,
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
  final FeeMode feeMode;
  final int userAdjustment;

  const BillingBottomSheet({
    super.key,
    required this.entryTimeInSeconds,
    required this.currentTimeInSeconds,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
    this.feeMode = FeeMode.normal,
    this.userAdjustment = 0,
  });

  @override
  State<BillingBottomSheet> createState() => _BillingBottomSheetState();
}

class _BillingBottomSheetState extends State<BillingBottomSheet> {
  final List<String> paymentOptions = ['계좌', '카드', '현금'];
  int _selectedIndex = 0;

  String get _selectedPayment => paymentOptions[_selectedIndex];

  int _getLockedFee() {
    return calculateFee(
      entryTimeInSeconds: widget.entryTimeInSeconds,
      currentTimeInSeconds: widget.currentTimeInSeconds,
      basicStandard: widget.basicStandard,
      basicAmount: widget.basicAmount,
      addStandard: widget.addStandard,
      addAmount: widget.addAmount,
      userAdjustment: widget.userAdjustment,
      mode: widget.feeMode,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lockedFee = _getLockedFee();

    return SafeArea(
      child: Material(
        color: Colors.transparent,
        child: DraggableScrollableSheet(
          initialChildSize: 0.5,
          minChildSize: 0.4,
          maxChildSize: 0.85,
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
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Row(
                    children: const [
                      Icon(Icons.attach_money_rounded, color: Colors.green),
                      SizedBox(width: 8),
                      Text(
                        '정산 정보 확인',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  const Text("지불 방법을 선택하세요", style: TextStyle(fontSize: 16)),
                  const SizedBox(height: 12),

                  /// ✅ ToggleButtons 지불방식 선택 UI
                  ToggleButtons(
                    isSelected: List.generate(
                        paymentOptions.length, (index) => index == _selectedIndex),
                    onPressed: (index) {
                      setState(() {
                        _selectedIndex = index;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    selectedColor: Colors.white,
                    fillColor: Colors.green,
                    textStyle: const TextStyle(fontSize: 16),
                    children: paymentOptions.map((text) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(text),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    '예상 정산 금액: ₩$lockedFee',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 32),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FilledButton(
                        onPressed: () {
                          Navigator.of(context).pop(
                            BillResult(_selectedPayment, lockedFee),
                          );
                        },
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
                  )
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
