import 'package:flutter/material.dart';

class ParkingStatusBottomSheet extends StatelessWidget {
  final int totalCapacity;
  final int occupiedCount;
  final ScrollController scrollController;

  const ParkingStatusBottomSheet({
    super.key,
    required this.totalCapacity,
    required this.occupiedCount,
    required this.scrollController,
  });

  @override
  Widget build(BuildContext context) {
    final double usageRatio =
    totalCapacity == 0 ? 0 : occupiedCount / totalCapacity;
    final String usagePercent = (usageRatio * 100).toStringAsFixed(1);

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: ListView(
        controller: scrollController,
        children: [
          // 🟪 Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // 🟦 제목
          const Text(
            '📊 현재 주차 현황',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),

          // 🔹 요약 텍스트
          Text(
            '총 $totalCapacity대 중 $occupiedCount대 주차됨',
            style: const TextStyle(fontSize: 16),
            textAlign: TextAlign.center,
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
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
