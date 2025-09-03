import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import '../utils/calendar_logic.dart';

/// 일정 요약(summary) 기준으로 필터링 가능한 Chip UI를 제공하는 위젯
class CalendarFilterChips extends StatelessWidget {
  final String calendarId; // 🔄 추가됨
  final Map<String, bool> filterStates;
  final Map<DateTime, List<calendar.Event>> eventsByDay;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(String key, bool selected) onFilterChanged;
  final void Function(Map<DateTime, List<calendar.Event>>) updateEvents;

  const CalendarFilterChips({
    super.key,
    required this.calendarId, // 🔄 추가됨
    required this.filterStates,
    required this.eventsByDay,
    required this.focusedDay,
    required this.selectedDay,
    required this.onFilterChanged,
    required this.updateEvents,
  });

  /// description에서 progress 값 추출
  int _getProgress(String? desc) {
    final match = RegExp(r'progress:(\d{1,3})').firstMatch(desc ?? '');
    if (match != null) {
      return int.tryParse(match.group(1) ?? '')?.clamp(0, 100) ?? 0;
    }
    return 0;
  }

  /// 날짜 정규화 헬퍼
  DateTime normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    if (filterStates.isEmpty) return const SizedBox();

    final chips = filterStates.entries
        .map((entry) {
          final summary = entry.key;

          final matchedEvents = eventsByDay.values.expand((list) => list).where((e) => e.summary == summary).toList();

          if (matchedEvents.isEmpty) return const SizedBox();

          final first = matchedEvents.first;
          final progress = _getProgress(first.description);

          // ✅ 진행률이 100%인 이벤트는 Chip 숨김
          if (progress == 100) return const SizedBox();

          final startUtc = first.start?.date;
          final endUtc = first.end?.date;

          final start = startUtc != null ? DateTime(startUtc.year, startUtc.month, startUtc.day) : null;

          final end =
              endUtc != null ? DateTime(endUtc.year, endUtc.month, endUtc.day).subtract(const Duration(days: 1)) : null;

          String label = summary;
          if (start != null && end != null) {
            label += " (${start.month}/${start.day}~${end.month}/${end.day}, $progress%)";
          }

          return FilterChip(
            label: Text(label),
            selected: entry.value,
            onSelected: (selected) async {
              onFilterChanged(summary, selected);
              await saveFilterStates(filterStates);

              if (selected && selectedDay != null) {
                final normalizedSelected = normalizeDate(selectedDay!);

                final selectedDateEvents = eventsByDay[normalizedSelected] ?? [];

                final target = selectedDateEvents.where((e) => e.summary == summary).toList().firstOrNull;

                if (target != null) {
                  await editEvent(
                    context: context,
                    event: target,
                    focusedDay: focusedDay,
                    updateEvents: updateEvents,
                    filterStates: filterStates,
                    calendarId: calendarId, // 🔄 calendarId 전달됨
                  );
                }
              }
            },
          );
        })
        .whereType<Widget>()
        .toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Wrap(
        spacing: 8,
        children: chips.map((chip) {
          return Theme(
            data: Theme.of(context).copyWith(
              chipTheme: ChipThemeData(
                backgroundColor: Colors.grey[100]!,
                selectedColor: Colors.deepPurple.shade100,
                disabledColor: Colors.grey.shade300,
                labelStyle: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500),
                selectedShadowColor: Colors.deepPurple,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: const BorderSide(color: Colors.black),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              ),
            ),
            child: chip,
          );
        }).toList(),
      ),
    );
  }
}
