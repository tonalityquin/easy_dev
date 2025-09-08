import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'cooperation_Calendar_pages/sections/calendar_filter_chips.dart';
import 'cooperation_Calendar_pages/sections/calendar_event_card.dart';
import 'cooperation_Calendar_pages/utils/calendar_logic.dart';
import 'cooperation_Calendar_pages/utils/calendar_utils.dart';

class CooperationCalendar extends StatefulWidget {
  final String calendarId;

  const CooperationCalendar({
    super.key,
    required this.calendarId,
  });

  @override
  State<CooperationCalendar> createState() => _CooperationCalendarState();
}

class _CooperationCalendarState extends State<CooperationCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<calendar.Event>> _eventsByDay = {};
  Map<String, bool> _filterStates = {};

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

          CalendarFilterChips(
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

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(8),
              itemCount: _getEventsForDay(_selectedDay ?? _focusedDay).length,
              itemBuilder: (context, index) {
                final event = _getEventsForDay(_selectedDay ?? _focusedDay)[index];
                return CalendarEventCard(event: event);
              },
            ),
          )
        ],
      ),

      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 48, right: 16),
        child: FloatingActionButton.extended(
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
      ),
    );
  }
}
