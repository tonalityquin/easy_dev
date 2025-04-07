import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // 날짜 포맷용

import '../../utils/fee_calculator.dart'; // 요금 계산 유틸을 직접 사용하는 경우

class DepartureSettlementConfirmDialog extends StatelessWidget {
  final int entryTimeInSeconds;
  final int basicStandard;
  final int basicAmount;
  final int addStandard;
  final int addAmount;

  const DepartureSettlementConfirmDialog({
    super.key,
    required this.entryTimeInSeconds,
    required this.basicStandard,
    required this.basicAmount,
    required this.addStandard,
    required this.addAmount,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final currentTimeInSeconds = now.toUtc().millisecondsSinceEpoch ~/ 1000;
    final formattedNow = DateFormat('yyyy-MM-dd HH:mm:ss').format(now);

    final fee = calculateParkingFee(
      entryTimeInSeconds: entryTimeInSeconds,
      currentTimeInSeconds: currentTimeInSeconds,
      basicStandard: basicStandard,
      basicAmount: basicAmount,
      addStandard: addStandard,
      addAmount: addAmount,
    ).round();

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: const [
          Icon(Icons.attach_money, color: Colors.green, size: 28),
          SizedBox(width: 8),
          Text('정산 확인', style: TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '출차 시각: $formattedNow',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            '예상 정산 금액: ₩$fee',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          const Text(
            '정말로 지금 정산을 완료하시겠습니까?\n정산하지 않으면 요금이 계속 증가합니다.',
            style: TextStyle(fontSize: 14),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.spaceEvenly,
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, null), // 출차 취소
          child: const Text('출차 취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false), // 정산 안함
          child: const Text('아니오'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true), // 정산함
          child: const Text('예'),
        ),
      ],
    );
  }
}
