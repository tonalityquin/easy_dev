import 'package:flutter/material.dart';

class OfflineInputBillSection extends StatelessWidget {
  // 기존 API 유지(호출부 영향 방지). 현재 로직에서는 사용하지 않음.
  final String? selectedBill;
  final String selectedBillType;
  final ValueChanged<String?> onChanged;
  final ValueChanged<String> onTypeChanged;
  final TextEditingController? countTypeController;

  const OfflineInputBillSection({
    super.key,
    required this.selectedBill,
    required this.selectedBillType,
    required this.onChanged,
    required this.onTypeChanged,
    this.countTypeController,
  });

  @override
  Widget build(BuildContext context) {
    final isGeneral = selectedBillType == '변동';
    final isFixed = selectedBillType == '고정';
    final isMonthly = selectedBillType == '정기';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '정산 유형',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12.0),
        Row(
          children: [
            _buildTypeButton(
              label: '변동',
              isSelected: isGeneral,
              onTap: () => onTypeChanged('변동'),
            ),
            const SizedBox(width: 8),
            _buildTypeButton(
              label: '고정',
              isSelected: isFixed,
              onTap: () => onTypeChanged('고정'),
            ),
            const SizedBox(width: 8),
            _buildTypeButton(
              label: '정기',
              isSelected: isMonthly,
              onTap: () => onTypeChanged('정기'),
            ),
          ],
        ),
        const SizedBox(height: 12.0),

        // ⬇️ 요청 사항: 안내 텍스트만 표시
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Center(
            child: Text(
              '지점 별 정산 유형을 선택하는 공간입니다.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTypeButton({
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? Colors.black : Colors.white,
            border: Border.all(color: Colors.black),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: isSelected ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
