import 'package:flutter/material.dart';

/// 결과를 담는 모델
class BillResult {
  final String paymentMethod;
  final int lockedFee;

  BillResult(this.paymentMethod, this.lockedFee);
}

/// 호출 함수
Future<BillResult?> showOnTapBillingTypeBottomSheet({
  required BuildContext context,
  required int entryTimeInSeconds,
  required int currentTimeInSeconds,
  required int basicStandard,
  required int basicAmount,
  required int addStandard,
  required int addAmount,
}) async {
  return await showModalBottomSheet<BillResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => OnTapBillingTypeBottomSheet(
      entryTimeInSeconds: entryTimeInSeconds,
      currentTimeInSeconds: currentTimeInSeconds,
      basicStandard: basicStandard,
      basicAmount: basicAmount,
      addStandard: addStandard,
      addAmount: addAmount,
    ),
  );
}

class OnTapBillingTypeBottomSheet extends StatefulWidget {
  final int entryTimeInSeconds;
  final int currentTimeInSeconds;
  final int basicStandard;
  final int basicAmount;
  final int addStandard;
  final int addAmount;

  const OnTapBillingTypeBottomSheet({
    super.key,
    required this.entryTimeInSeconds,
    required this.currentTimeInSeconds,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
  });

  @override
  State<OnTapBillingTypeBottomSheet> createState() => _OnTapBillingTypeBottomSheetState();
}

class _OnTapBillingTypeBottomSheetState extends State<OnTapBillingTypeBottomSheet> {
  String _selected = '계좌';

  int calculateFee() {
    final parkedSeconds = widget.currentTimeInSeconds - widget.entryTimeInSeconds;
    final basicSec = widget.basicStandard * 60;
    final addSec = widget.addStandard * 60;

    if (parkedSeconds <= basicSec) {
      return widget.basicAmount;
    } else {
      final extraTime = parkedSeconds - basicSec;
      final extraUnits = (extraTime / addSec).ceil();
      return widget.basicAmount + extraUnits * widget.addAmount;
    }
  }

  @override
  Widget build(BuildContext context) {
    final lockedFee = calculateFee();

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
                  const SizedBox(height: 8),
                  DropdownButton<String>(
                    value: _selected,
                    isExpanded: true,
                    onChanged: (value) {
                      if (value != null) {
                        setState(() {
                          _selected = value;
                        });
                      }
                    },
                    items: ['계좌', '카드', '현금'].map((type) {
                      return DropdownMenuItem(
                        value: type,
                        child: Text(type),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 20),
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
                          Navigator.of(context).pop(BillResult(_selected, lockedFee));
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
