import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

class AttendanceCell extends StatefulWidget {
  const AttendanceCell({super.key});

  @override
  State<AttendanceCell> createState() => _AttendanceCellState();
}

class _AttendanceCellState extends State<AttendanceCell> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '출석 캘린더',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: SingleChildScrollView( // ✅ 오버플로우 방지
        padding: const EdgeInsets.all(16.0),
        child: TableCalendar(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: _focusedDay,
          rowHeight: 80, // ✅ 셀 높이 확보
          selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
          onDaySelected: (selectedDay, focusedDay) {
            setState(() {
              _selectedDay = selectedDay;
              _focusedDay = focusedDay;
            });
          },
          calendarStyle: const CalendarStyle(
            outsideDaysVisible: true,
            isTodayHighlighted: false,
            cellMargin: EdgeInsets.all(4),
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
          ),
          calendarBuilders: CalendarBuilders(
            defaultBuilder: (context, day, focusedDay) {
              final isSelected = isSameDay(day, _selectedDay);
              final isToday = isSameDay(day, DateTime.now());

              return Container(
                margin: const EdgeInsets.all(4.0),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.orange.withOpacity(0.3)
                      : isToday
                      ? Colors.blueAccent.withOpacity(0.2)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${day.day}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text('00:00', style: TextStyle(fontSize: 10)),
                    const Text('00:00', style: TextStyle(fontSize: 10)),
                  ],
                ),
              );
            },
            todayBuilder: (context, day, focusedDay) {
              return Container(
                margin: const EdgeInsets.all(4.0),
                decoration: BoxDecoration(
                  color: Colors.blueAccent.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${day.day}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text('00:00', style: TextStyle(fontSize: 10)),
                    const Text('00:00', style: TextStyle(fontSize: 10)),
                  ],
                ),
              );
            },
            selectedBuilder: (context, day, focusedDay) {
              return Container(
                margin: const EdgeInsets.all(4.0),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(10.0),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '${day.day}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    const Text('00:00', style: TextStyle(fontSize: 10)),
                    const Text('00:00', style: TextStyle(fontSize: 10)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
