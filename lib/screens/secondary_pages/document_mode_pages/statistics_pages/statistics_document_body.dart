import 'package:flutter/material.dart';

import '../../../../states/calendar/statistics_calendar_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../widgets/dialog/calendar/statistics_view_dialog.dart';

class StatisticsDocumentBody extends StatelessWidget {
  final StatisticsCalendarState calendar;
  final VoidCallback onDateSelected;
  final VoidCallback refresh;

  const StatisticsDocumentBody({
    super.key,
    required this.calendar,
    required this.onDateSelected,
    required this.refresh,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('필드 통계 열람 달력', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildMonthNavigation(),
            _buildDayHeaders(),
            _buildDateGrid(context),
            const SizedBox(height: 16),
            _buildOpenButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthNavigation() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_left),
            onPressed: () {
              calendar.moveToPreviousMonth();
              refresh();
            },
          ),
          Text(
            calendar.formattedMonth,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_right),
            onPressed: () {
              calendar.moveToNextMonth();
              refresh();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDayHeaders() {
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: days
            .map((day) => Expanded(
          child: Container(
            margin: const EdgeInsets.all(4),
            alignment: Alignment.center,
            child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold)),
          ),
        ))
            .toList(),
      ),
    );
  }

  Widget _buildDateGrid(BuildContext context) {
    final firstDay = DateTime(calendar.currentMonth.year, calendar.currentMonth.month, 1);
    final firstWeekday = firstDay.weekday % 7;
    final daysInMonth = DateTime(calendar.currentMonth.year, calendar.currentMonth.month + 1, 0).day;
    final totalGridItems = firstWeekday + daysInMonth;

    return GridView.count(
      shrinkWrap: true,
      crossAxisCount: 7,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(8),
      children: List.generate(totalGridItems, (index) {
        if (index < firstWeekday) return const SizedBox();

        final day = index - firstWeekday + 1;
        final currentDate = DateTime(calendar.currentMonth.year, calendar.currentMonth.month, day);
        final isSelected = calendar.isSelected(currentDate);

        return GestureDetector(
          onTap: () {
            calendar.selectDate(currentDate);
            onDateSelected();

            if (calendar.selectedDates.isEmpty) {
              showSelectedSnackbar(context, '선택이 해제되었습니다');
            } else {
              showSelectedSnackbar(context, '선택된 날짜: ${calendar.formatDate(currentDate)}');
            }

            refresh();
          },
          child: Container(
            margin: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: isSelected ? Colors.indigo : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              '$day',
              style: TextStyle(
                color: isSelected ? Colors.white : Colors.black,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildOpenButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: () {
          showDialog(
            context: context,
            builder: (_) => const StatisticsViewDialog(),
          );
        },
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.indigo,
          foregroundColor: Colors.white,
        ),
        child: const Text('열람'),
      ),
    );
  }
}
