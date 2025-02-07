import 'package:flutter/material.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바

class Calendar extends StatefulWidget {
  const Calendar({Key? key}) : super(key: key);

  @override
  _CalendarState createState() => _CalendarState();
}

class _CalendarState extends State<Calendar> {
  bool isKanbanMode = false; // 🔄 현재 화면 모드 (false: Calendar, true: Kanban)

  DateTime _selectedDate = DateTime.now(); // 현재 선택된 날짜
  late DateTime _firstDayOfMonth; // 이번 달의 첫 번째 날
  late int _daysInMonth; // 이번 달의 총 일수
  late int _startingWeekday; // 이번 달이 시작하는 요일 (0: 일요일 ~ 6: 토요일)

  @override
  void initState() {
    super.initState();
    _updateCalendar();
  }

  /// 🗓 현재 월의 정보 업데이트
  void _updateCalendar() {
    _firstDayOfMonth = DateTime(_selectedDate.year, _selectedDate.month, 1);
    _daysInMonth = DateTime(_selectedDate.year, _selectedDate.month + 1, 0).day;
    _startingWeekday = _firstDayOfMonth.weekday % 7; // 0: 일요일 ~ 6: 토요일
  }

  /// 🔄 이전 달 보기
  void _previousMonth() {
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month - 1, 1);
      _updateCalendar();
    });
  }

  /// 🔄 다음 달 보기
  void _nextMonth() {
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
      _updateCalendar();
    });
  }

  /// 🔄 화면 모드 전환 (캘린더 ↔ 칸반)
  void _toggleMode() {
    setState(() {
      isKanbanMode = !isKanbanMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryRoleNavigation(),
      body: isKanbanMode ? _buildKanbanBoard() : _buildCalendar(), // 🔄 현재 모드에 따라 화면 변경
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: [
          Icons.add,
          isKanbanMode ? Icons.today_outlined : Icons.developer_board, // 🔄 현재 모드에 따라 아이콘 변경
          Icons.delete,
        ],
        onIconTapped: (index) {
          if (index == 1) {
            _toggleMode(); // 캘린더 ↔ 칸반 전환
          }
        },
      ),
    );
  }

  /// 📅 캘린더 화면 UI
  Widget _buildCalendar() {
    return Column(
      children: [
        /// 📅 월 변경 네비게이션
        Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(icon: const Icon(Icons.arrow_back), onPressed: _previousMonth),
              Text("${_selectedDate.year}년 ${_selectedDate.month}월",
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              IconButton(icon: const Icon(Icons.arrow_forward), onPressed: _nextMonth),
            ],
          ),
        ),

        /// 📅 요일 헤더
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 7,
          children: ["일", "월", "화", "수", "목", "금", "토"]
              .map((day) => Center(child: Text(day, style: const TextStyle(fontWeight: FontWeight.bold))))
              .toList(),
        ),

        /// 📅 날짜 GridView
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.2,
            ),
            itemCount: _daysInMonth + _startingWeekday,
            itemBuilder: (context, index) {
              if (index < _startingWeekday) {
                return const SizedBox(); // 공백 채우기
              }

              int day = index - _startingWeekday + 1;
              bool isSelected = (_selectedDate.day == day &&
                  _selectedDate.month == DateTime.now().month &&
                  _selectedDate.year == DateTime.now().year);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedDate = DateTime(_selectedDate.year, _selectedDate.month, day);
                  });
                },
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.blue : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      "$day",
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: isSelected ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  /// 🏗 Kanban Board UI (기본적인 틀만 구현)
  Widget _buildKanbanBoard() {
    return Row(
      children: [
        _buildKanbanColumn("To Do", Colors.red),
        _buildKanbanColumn("In Progress", Colors.orange),
        _buildKanbanColumn("Done", Colors.green),
      ],
    );
  }

  /// 📌 Kanban Board의 개별 컬럼 위젯
  Widget _buildKanbanColumn(String title, Color color) {
    return Expanded(
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            color: color,
            child: Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
            ),
          ),
          Expanded(
            child: Container(
              color: color.withOpacity(0.2),
              child: Center(child: Text("No tasks yet", style: TextStyle(color: color))),
            ),
          ),
        ],
      ),
    );
  }
}
