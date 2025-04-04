import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/calendar/statistics_selected_date_state.dart';

class StatisticsViewDialog extends StatelessWidget {
  const StatisticsViewDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final selectedDates = context.watch<StatisticsSelectedDateState>().selectedDates;

    String formattedDates = selectedDates.isNotEmpty
        ? selectedDates
        .map((date) => '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}')
        .join(', ')
        : '선택된 날짜 없음';

    return CupertinoAlertDialog(
      title: const Text('열람 정보', style: TextStyle(fontWeight: FontWeight.bold)),
      content: Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Column(
          children: [
            _buildRow('선택 날짜', formattedDates, isDimmed: selectedDates.isEmpty),
            const SizedBox(height: 8),
            _buildRow('입차 합계', ''),
            const SizedBox(height: 8),
            _buildRow('출차 합계', ''),
            const SizedBox(height: 8),
            _buildRow('정산 합계', ''),
          ],
        ),
      ),
      actions: [
        CupertinoDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('닫기'),
        ),
      ],
    );
  }

  Widget _buildRow(String label, String value, {bool isDimmed = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.right,
            style: TextStyle(
              color: isDimmed ? CupertinoColors.systemGrey : CupertinoColors.label,
            ),
          ),
        ),
      ],
    );
  }
}
