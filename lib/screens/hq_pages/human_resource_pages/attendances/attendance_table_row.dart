import 'package:flutter/material.dart';
import '../../../../models/user_model.dart';

class AttendanceTableRow extends StatelessWidget {
  final UserModel user;
  final int rowIndex;
  final int? selectedRow;
  final int? selectedCol;
  final Map<String, Map<int, String>> cellData;
  final void Function(int rowIndex, int colIndex, String rowKey) onCellTapped;

  const AttendanceTableRow({
    super.key,
    required this.user,
    required this.rowIndex,
    required this.selectedRow,
    required this.selectedCol,
    required this.cellData,
    required this.onCellTapped,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildRow(isCheckIn: true),
        _buildRow(isCheckIn: false),
      ],
    );
  }

  Widget _buildRow({required bool isCheckIn}) {
    final label = isCheckIn ? '출근' : '퇴근';
    final logicalRowIndex = rowIndex * 2 + (isCheckIn ? 0 : 1);
    final rowKey = isCheckIn ? user.id : '${user.id}_out';

    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: List.generate(34, (colIndex) {
          if (colIndex == 0) {
            // 이름 셀
            return _buildCell(
              text: user.name,
              isHeader: true,
              width: 80,
            );
          }
          if (colIndex == 1) {
            // 출근/퇴근 라벨 셀
            return _buildCell(
              text: label,
              isHeader: false,
              width: 60,
            );
          }
          if (colIndex == 33) {
            // 사인란
            return _buildCell(
              text: '',
              isHeader: false,
              width: 120,
            );
          }

          final day = colIndex - 1;
          final value = cellData[rowKey]?[day] ?? '';
          final isSelected = selectedRow == logicalRowIndex && selectedCol == colIndex;

          return _buildCell(
            text: value,
            isHeader: false,
            isSelected: isSelected,
            onTap: () => onCellTapped(logicalRowIndex, colIndex, rowKey),
          );
        }),
      ),
    );
  }

  Widget _buildCell({
    required String text,
    required bool isHeader,
    bool isSelected = false,
    VoidCallback? onTap,
    double width = 60,
  }) {
    final backgroundColor = isHeader
        ? Colors.grey.shade200
        : text.contains('03:00')
        ? Colors.yellow.shade100
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
          textAlign: TextAlign.center,
          style: TextStyle(
            fontWeight: isHeader ? FontWeight.bold : FontWeight.normal,
            fontSize: 13,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
