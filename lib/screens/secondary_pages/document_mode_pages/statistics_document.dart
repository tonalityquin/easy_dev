import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/calendar/statistics_calendar_state.dart';
import '../../../states/calendar/statistics_selected_date_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../../../widgets/dialog/calendar/statistics_view_dialog.dart'; // ✅ 다이얼로그 임포트

class StatisticsDocument extends StatefulWidget {
  const StatisticsDocument({super.key});

  @override
  State<StatisticsDocument> createState() => _StatisticsDocumentState();
}

class _StatisticsDocumentState extends State<StatisticsDocument> {
  late StatisticsCalendarState calendar;

  @override
  void initState() {
    super.initState();
    calendar = StatisticsCalendarState();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('통계 달력'),
        centerTitle: true,
        backgroundColor: Colors.indigo,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildMonthNavigation(),
            _buildDayHeaders(),
            _buildDateGrid(),
            const SizedBox(height: 16),
            _buildOpenButton(context), // ✅ 열람 버튼 추가
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
            onPressed: () => setState(() => calendar.moveToPreviousMonth()),
          ),
          Text(
            calendar.formattedMonth,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_right),
            onPressed: () => setState(() => calendar.moveToNextMonth()),
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
        children: days.map((day) {
          return Expanded(
            child: Container(
              margin: const EdgeInsets.all(4),
              alignment: Alignment.center,
              child: Text(
                day,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateGrid() {
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
            setState(() {
              if (isSelected) {
                calendar.selectDate(currentDate); // 내부에서 toggle 되도록 이미 구현됨
              } else {
                calendar.selectDate(currentDate);
              }

              // 선택된 목록 전체를 상태에 반영
              context.read<StatisticsSelectedDateState>().setSelectedDates(calendar.selectedDates);

              if (calendar.selectedDates.isEmpty) {
                showSelectedSnackbar(context, '선택이 해제되었습니다');
              } else {
                showSelectedSnackbar(
                  context,
                  '선택된 날짜: ${calendar.formatDate(currentDate)}',
                );
              }
            });
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
            builder: (_) => const StatisticsViewDialog(), // ✅ 팝업 열기
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
