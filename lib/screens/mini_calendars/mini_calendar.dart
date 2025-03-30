import 'package:flutter/material.dart';
import '../../utils/show_snackbar.dart'; // 실제 경로에 맞게 수정

class MiniCalendarPage extends StatefulWidget {
  const MiniCalendarPage({super.key});

  @override
  State<MiniCalendarPage> createState() => _MiniCalendarPageState();
}

class _MiniCalendarPageState extends State<MiniCalendarPage> {
  DateTime _currentMonth = DateTime(DateTime.now().year, DateTime.now().month);
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now(); // ✅ 오늘 날짜 자동 선택
  }

  String get _monthLabel => "${_currentMonth.year}년 ${_currentMonth.month}월";

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        centerTitle: true,
        title: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 4),
            Text(
              " 달력 기능 테스트 페이지 ",
              style: TextStyle(color: Colors.grey, fontSize: 16),
            ),
            SizedBox(width: 4),
          ],
        ),
      ),
      body: Column(
        children: [
          _buildMonthNavigation(),
          _buildDayHeaders(context),
          _buildDateGrid(),
        ],
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
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1);
              });
            },
          ),
          Text(
            _monthLabel,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_right),
            onPressed: () {
              setState(() {
                _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1);
              });
            },
          ),
        ],
      ),
    );
  }

  // 📅 요일 헤더: 날짜 셀과 너비 맞춤 + 간격 조절
  Widget _buildDayHeaders(BuildContext context) {
    const days = ['일', '월', '화', '수', '목', '금', '토'];
    final double cellWidth = (MediaQuery.of(context).size.width - 8 * 2 - 4 * 2 * 7) / 7;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.start,
        children: days.map((day) {
          return Container(
            width: cellWidth,
            margin: const EdgeInsets.all(4), // 각 요일 간 살짝 여백
            alignment: Alignment.center,
            child: Text(
              day,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildDateGrid() {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final firstWeekday = firstDay.weekday % 7; // Sunday = 0
    final daysInMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 0).day;
    final totalGridItems = firstWeekday + daysInMonth;

    return Expanded(
      child: GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(8),
        children: List.generate(totalGridItems, (index) {
          if (index < firstWeekday) {
            return const SizedBox(); // 빈 칸
          }

          final day = index - firstWeekday + 1;
          final currentDate = DateTime(_currentMonth.year, _currentMonth.month, day);
          final isSelected = _selectedDate != null &&
              _selectedDate!.year == currentDate.year &&
              _selectedDate!.month == currentDate.month &&
              _selectedDate!.day == currentDate.day;

          return GestureDetector(
            onTap: () {
              setState(() {
                _selectedDate = currentDate;
              });
              showSnackbar(context, '선택된 날짜: ${_formatDate(currentDate)}');
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
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.year}년 ${date.month}월 ${date.day}일';
  }
}
