import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'sections/tablet_calendar_filter_chips.dart';
import 'sections/tablet_calendar_event_card.dart';
import 'sections/tablet_completed_event_sheet.dart';
import 'utils/tablet_calendar_logic.dart';
import 'utils/tablet_calendar_utils.dart';

/// 개인용 Google Calendar 연동 월간 캘린더 화면
class TabletPersonalCalendar extends StatefulWidget {
  const TabletPersonalCalendar({super.key});

  @override
  State<TabletPersonalCalendar> createState() => _TabletPersonalCalendarState();
}

class _TabletPersonalCalendarState extends State<TabletPersonalCalendar> {
  DateTime _focusedDay = DateTime.now(); // 현재 포커스된 달
  DateTime? _selectedDay; // 사용자가 선택한 날짜
  Map<DateTime, List<calendar.Event>> _eventsByDay = {}; // 날짜별 이벤트 맵
  Map<String, bool> _filterStates = {}; // 이벤트 제목 필터링 상태

  @override
  void initState() {
    super.initState();

    // post-frame에서 초기화하여 안정성 확보
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final loaded = await loadFilterStates();
        setState(() => _filterStates = loaded);

        final events = await loadEventsForMonth(
          month: _focusedDay,
          filterStates: loaded,
        );
        setState(() => _eventsByDay = events);
      } catch (e, stack) {
        print('🚨 초기화 오류: $e');
        print(stack);
      }
    });
  }

  /// 선택한 날짜의 필터된 이벤트 목록 반환
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
        actions: [
          IconButton(
            icon: const Icon(Icons.check_circle_outline),
            tooltip: '완료된 할 일 보기',
            onPressed: () async {
              await showTabletCompletedEventSheet(
                context: context,
                eventsByDay: _eventsByDay,
                calendarId: calendarId,
                onEventsDeleted: (updated) {
                  setState(() => _eventsByDay = updated);
                },
              );
            },
          ),
        ],
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
                );
                setState(() => _eventsByDay = events);
              } catch (e) {
                print('🚨 페이지 변경 오류: $e');
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
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 48),
        child: FloatingActionButton(
          onPressed: () async {
            await addEvent(
              context: context,
              focusedDay: _focusedDay,
              updateEvents: (updated) => setState(() => _eventsByDay = updated),
              filterStates: _filterStates,
            );
          },
          backgroundColor: Colors.white,
          foregroundColor: Theme.of(context).colorScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(
              color: Theme.of(context).colorScheme.primary,
              width: 1.2,
            ),
          ),
          elevation: 4,
          tooltip: '일정 추가',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
