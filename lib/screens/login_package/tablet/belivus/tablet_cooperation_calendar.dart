import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'tablet_completed_task_page.dart';
import 'cooperation_Calendar_pages/sections/tablet_calendar_filter_chips.dart';
import 'cooperation_Calendar_pages/sections/tablet_calendar_event_card.dart';
import 'cooperation_Calendar_pages/utils/tablet_calendar_logic.dart';
import 'cooperation_Calendar_pages/utils/tablet_calendar_utils.dart';

/// 개인용 Google Calendar 연동 월간 캘린더 화면
class TabletCooperationCalendar extends StatefulWidget {
  final String calendarId;

  const TabletCooperationCalendar({
    super.key,
    required this.calendarId,
  });

  @override
  State<TabletCooperationCalendar> createState() => _TabletCooperationCalendarState();
}

class _TabletCooperationCalendarState extends State<TabletCooperationCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<calendar.Event>> _eventsByDay = {};
  Map<String, bool> _filterStates = {};
  bool _isFabOpen = false;

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final loaded = await loadFilterStates();
        if (!mounted) return;
        setState(() => _filterStates = loaded);

        final events = await loadEventsForMonth(
          month: _focusedDay,
          filterStates: loaded,
          calendarId: widget.calendarId,
        );
        if (!mounted) return;
        setState(() => _eventsByDay = events);
      } catch (e) {
        debugPrint('🚨 초기화 오류: $e');
      }
    });
  }

  List<calendar.Event> _getEventsForDay(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    final raw = _eventsByDay[normalized] ?? [];
    return raw.where((e) => _filterStates[e.summary?.trim() ?? '무제'] == true).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text('월간 간트 캘린더', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          /// 📅 캘린더 위젯
          TableCalendar(
            firstDay: DateTime(2020),
            lastDay: DateTime(2030),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                if (isSameDay(_selectedDay, selectedDay)) {
                  _selectedDay = null;
                } else {
                  _selectedDay = selectedDay;
                }
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) async {
              _focusedDay = focusedDay;
              try {
                final events = await loadEventsForMonth(
                  month: focusedDay,
                  filterStates: _filterStates,
                  calendarId: widget.calendarId,
                );
                setState(() => _eventsByDay = events);
              } catch (e) {
                debugPrint('🚨 페이지 변경 오류: $e');
              }
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, _) {
                final normalized = DateTime(day.year, day.month, day.day);
                final dailyEvents = (_eventsByDay[normalized] ?? [])
                    .where((e) => _filterStates[e.summary?.trim() ?? '무제'] == true)
                    .toList();
                return Column(
                  children: dailyEvents.take(3).map(buildEventMarker).toList(),
                );
              },
            ),
          ),

          const Divider(),

          /// 🔘 필터 Chip 목록
          TabletCalendarFilterChips(
            calendarId: widget.calendarId,
            filterStates: _filterStates,
            eventsByDay: _eventsByDay,
            focusedDay: _focusedDay,
            selectedDay: _selectedDay,
            onFilterChanged: (key, selected) {
              setState(() => _filterStates[key] = selected);
            },
            updateEvents: (updated) {
              setState(() => _eventsByDay = updated);
            },
          ),

          /// 📋 일정 카드 리스트
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _getEventsForDay(_selectedDay ?? _focusedDay).length,
              itemBuilder: (context, index) {
                final event = _getEventsForDay(_selectedDay ?? _focusedDay)[index];
                return TabletCalendarEventCard(event: event);
              },
            ),
          )
        ],
      ),

      /// ➕ 일정 추가 버튼
      // ➕ 일정 추가 버튼
      // floatingActionButton 전체 대체
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 48, right: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (_isFabOpen) ...[
              // 일정 추가 버튼
              FloatingActionButton.extended(
                heroTag: 'addEventBtn',
                onPressed: () async {
                  await addEvent(
                    context: context,
                    focusedDay: _focusedDay,
                    updateEvents: (updated) => setState(() => _eventsByDay = updated),
                    filterStates: _filterStates,
                    calendarId: widget.calendarId,
                  );
                },
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                icon: const Icon(Icons.add),
                label: const Text('일정 추가', style: TextStyle(fontWeight: FontWeight.bold)),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 4,
              ),
              const SizedBox(height: 12),

              // 완료된 할 일
              FloatingActionButton.extended(
                heroTag: 'completedTasksBtn',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => TabletCompletedTaskPage(calendarId: widget.calendarId),
                    ),
                  );
                },
                backgroundColor: Colors.white,
                foregroundColor: Colors.black87,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('완료된 할 일'),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              const SizedBox(height: 12),
            ],

            // 메인 토글 버튼
            FloatingActionButton(
              heroTag: 'toggleFab',
              onPressed: () {
                setState(() => _isFabOpen = !_isFabOpen);
              },
              backgroundColor: Colors.white,
              child: AnimatedRotation(
                duration: const Duration(milliseconds: 200),
                turns: _isFabOpen ? 0.125 : 0, // +90도 회전 애니메이션
                child: const Icon(Icons.menu),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
