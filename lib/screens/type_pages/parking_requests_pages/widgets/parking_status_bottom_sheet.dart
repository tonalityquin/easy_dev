import 'package:flutter/material.dart';

class ParkingStatusBottomSheet extends StatelessWidget {
  final int totalCapacity;
  final int occupiedCount;

  const ParkingStatusBottomSheet({
    super.key,
    required this.totalCapacity,
    required this.occupiedCount,
  });

  @override
  Widget build(BuildContext context) {
    final double usageRatio = totalCapacity == 0 ? 0 : occupiedCount / totalCapacity;
    final String usagePercent = (usageRatio * 100).toStringAsFixed(1);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 🟪 Drag handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.grey[400],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // 🟦 제목
          const Text(
            '📊 현재 주차 현황',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),

          // 🔹 요약 텍스트
          Text(
            '총 $totalCapacity대 중 $occupiedCount대 주차됨',
            style: const TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 8),

          // 🔹 진행 바
          LinearProgressIndicator(
            value: usageRatio,
            backgroundColor: Colors.grey[300],
            valueColor: AlwaysStoppedAnimation<Color>(
              usageRatio >= 0.8 ? Colors.red : Colors.blueAccent,
            ),
            minHeight: 8,
          ),
          const SizedBox(height: 12),

          // 🔹 퍼센트 강조 텍스트
          Text(
            '$usagePercent% 사용 중',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }
}
