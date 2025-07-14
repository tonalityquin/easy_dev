import 'package:flutter/material.dart';
import '../../../../models/user_model.dart';

class BreakTableRow extends StatelessWidget {
  final UserModel user;
  final String label; // "시작" 또는 "종료"
  final int rowIndex;
  final String rowKey; // 예: userId
  final bool isStart; // true면 시작 셀, false면 종료 셀
  final Set<String> selectedCells;
  final Map<String, Map<int, String>> cellData;
  final void Function(int rowIndex, int colIndex, String rowKey) onCellTapped;

  const BreakTableRow({
    super.key,
    required this.user,
    required this.label,
    required this.rowIndex,
    required this.rowKey,
    required this.selectedCells,
    required this.cellData,
    required this.onCellTapped,
    this.isStart = true,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: List.generate(34, (colIndex) {
          // 0번째 열: 사용자 이름
          if (colIndex == 0) {
            return _buildCell(
              text: user.name,
              isHeader: isStart,
              isSelected: false,
            );
          }

          // 1번째 열: "시작"/"종료"
          if (colIndex == 1) {
            return _buildCell(
              text: label,
              isHeader: false,
              isSelected: false,
            );
          }

          // 33번째 열: 사인란
          if (colIndex == 33) {
            return _buildCell(
              text: '',
              isHeader: false,
              isSelected: false,
              width: 120,
            );
          }

          // 본문 셀
          final day = colIndex - 1; // 2~32 → day 1~31
          final key = '$rowKey:$day';
          final text = cellData[rowKey]?[day] ?? '';
          final isSelected = selectedCells.contains(key);

          return _buildCell(
            text: text,
            isHeader: false,
            isSelected: isSelected,
            onTap: isStart
                ? () => onCellTapped(rowIndex, colIndex, rowKey)
                : null, // 종료 셀은 선택 불가
          );
        }),
      ),
    );
  }

  Widget _buildCell({
    required String text,
    required bool isHeader,
    required bool isSelected,
    VoidCallback? onTap,
    double width = 60,
  }) {
    final backgroundColor = isHeader
        ? Colors.grey.shade200
        : isSelected
        ? Colors.lightBlue.shade100
        : Colors.white;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: 40,
        alignment: Alignment.center,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          color: backgroundColor,
        ),
        child: Text(
          text,
          style: TextStyle(
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
            height: 1.3,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
