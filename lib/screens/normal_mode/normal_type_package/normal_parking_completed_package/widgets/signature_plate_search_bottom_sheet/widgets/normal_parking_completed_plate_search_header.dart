import 'package:flutter/material.dart';

class NormalParkingCompletedPlateSearchHeader extends StatelessWidget {
  // ✅ 요청 팔레트 (BlueGrey)
  static const Color _base = Color(0xFF546E7A); // BlueGrey 600

  const NormalParkingCompletedPlateSearchHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.directions_car, color: _base),
            const SizedBox(width: 8),
            const Text(
              '번호판 검색',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          '차량 번호 4자리로 “입차 완료” 상태를 빠르게 찾습니다.',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Colors.black54,
          ),
        ),
      ],
    );
  }
}
