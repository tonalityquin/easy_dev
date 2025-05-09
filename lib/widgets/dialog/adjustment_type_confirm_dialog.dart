import 'package:flutter/material.dart';

/// 결과를 담는 모델
class AdjustmentResult {
  final String paymentMethod;
  final int lockedFee;

  AdjustmentResult(this.paymentMethod, this.lockedFee);
}

/// 다이얼로그 호출 함수
Future<AdjustmentResult?> showAdjustmentTypeConfirmDialog({
  required BuildContext context,
  required int entryTimeInSeconds,
  required int currentTimeInSeconds,
  required int basicStandard,
  required int basicAmount,
  required int addStandard,
  required int addAmount,
}) async {
  return showDialog<AdjustmentResult>(
    context: context,
    builder: (context) => AdjustmentTypeConfirmDialog(
      entryTimeInSeconds: entryTimeInSeconds,
      currentTimeInSeconds: currentTimeInSeconds,
      basicStandard: basicStandard,
      basicAmount: basicAmount,
      addStandard: addStandard,
      addAmount: addAmount,
    ),
  );
}

/// 정산 다이얼로그
class AdjustmentTypeConfirmDialog extends StatefulWidget {
  final int entryTimeInSeconds;
  final int currentTimeInSeconds;
  final int basicStandard;
  final int basicAmount;
  final int addStandard;
  final int addAmount;

  const AdjustmentTypeConfirmDialog({
    super.key,
    required this.entryTimeInSeconds,
    required this.currentTimeInSeconds,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
  });

  @override
  State<AdjustmentTypeConfirmDialog> createState() => _AdjustmentTypeConfirmDialogState();
}

class _AdjustmentTypeConfirmDialogState extends State<AdjustmentTypeConfirmDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  String _selected = '계좌';

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// 주차 요금 계산 함수
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

    return Center(
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.attach_money_rounded, color: Colors.green, size: 28),
              SizedBox(width: 8),
              Text('정산 정보 확인', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                items: ['계좌', '카드', '현금'].map((type) => DropdownMenuItem(value: type, child: Text(type))).toList(),
              ),
              const SizedBox(height: 16),
              Text(
                '예상 정산 금액: ₩$lockedFee',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(AdjustmentResult(_selected, lockedFee));
              },
              style: FilledButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                minimumSize: const Size(120, 48),
                textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('확인'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: const Text('취소', style: TextStyle(fontSize: 16)),
            ),
          ],
        ),
      ),
    );
  }
}
