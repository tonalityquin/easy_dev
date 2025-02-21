/// Goal.
// 일자 별 - 입차, 출차, 매출(금액, 납부 방법) - 달력의 날짜를 눌러서 확인
// 요일 별 - 입차, 출차, 매출(금액, 납부 방법) - 달력의 요일을 눌러서 확인
// 시간대 별 - 입차, 출차
// 월 별 - 입차, 출차, 매출(금액, 납부 방법)

// 직원 별 - 입차, 출차 통계

/// MiniNavigation Funciton
/// Appbar
// 'Secondary_role_navigation' - 오피스, 필드, 통계 등 모드 선택
/// Body
// calendar
// Function
// onTap
// - 요일
// - 일자

/// Bottom
// Left ; graph
// Middle ; calendar(V)
/// Middle ; calendar
/// right ;

import 'package:flutter/material.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart'; // 상단 내비게이션 바
import '../../../widgets/navigation/secondary_mini_navigation.dart'; // 하단 내비게이션 바

class CalendarTypeStatistics extends StatefulWidget {
  const CalendarTypeStatistics({Key? key}) : super(key: key);

  @override
  _CalendarState createState() => _CalendarState();
}

class _CalendarState extends State<CalendarTypeStatistics> {
  DateTime _selectedDate = DateTime.now(); // 현재 선택된 날짜
  int? selectedWeekday; // 선택된 요일 (0: 일요일 ~ 6: 토요일)
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
      selectedWeekday = null; // 요일 선택 초기화
      _updateCalendar();
    });
  }

  /// 🔄 다음 달 보기
  void _nextMonth() {
    setState(() {
      _selectedDate = DateTime(_selectedDate.year, _selectedDate.month + 1, 1);
      selectedWeekday = null; // 요일 선택 초기화
      _updateCalendar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const SecondaryRoleNavigation(),
      body: _buildCalendar(), // 📅 캘린더 화면
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: [
          Icons.add,
          Icons.calendar_today, // 🗓 캘린더 아이콘 유지
          Icons.delete,
        ],
        onIconTapped: (index) {
          // 버튼 기능 정의 (현재 기능 없음)
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

        /// 📅 요일 헤더 (클릭 가능하도록 변경)
        GridView.count(
          shrinkWrap: true,
          crossAxisCount: 7,
          children: ["일", "월", "화", "수", "목", "금", "토"].asMap().entries.map((entry) {
            int index = entry.key;
            String day = entry.value;
            bool isSelected = selectedWeekday == index; // 선택된 요일인지 확인

            return GestureDetector(
              onTap: () {
                setState(() {
                  selectedWeekday = index; // 선택된 요일 변경
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue : Colors.transparent, // 선택된 요일 강조
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    day,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? Colors.white
                          : (index == 0 ? Colors.red : (index == 6 ? Colors.blue : Colors.black)), // 일요일 빨강, 토요일 파랑
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),

        /// 📅 날짜 GridView (클릭 가능)
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
                    selectedWeekday = null; // 날짜 선택 시 요일 선택 초기화
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
}
