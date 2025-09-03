import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import '../utils/service_calendar_logic.dart';

class CalendarFilterChips extends StatelessWidget {
  final Map<String, bool> filterStates;
  final Map<DateTime, List<calendar.Event>> eventsByDay;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(String key, bool selected) onFilterChanged;
  final void Function(Map<DateTime, List<calendar.Event>>) updateEvents;

  const CalendarFilterChips({
    super.key,
    required this.filterStates,
    required this.eventsByDay,
    required this.focusedDay,
    required this.selectedDay,
    required this.onFilterChanged,
    required this.updateEvents,
  });

  int _getProgress(String? desc) {
    final match = RegExp(r'progress:(\d{1,3})').firstMatch(desc ?? '');
    if (match != null) {
      return int.tryParse(match.group(1) ?? '')?.clamp(0, 100) ?? 0;
    }
    return 0;
  }

  DateTime normalizeDate(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  Widget build(BuildContext context) {
    if (filterStates.isEmpty) return const SizedBox();

    final chips = filterStates.entries.map((entry) {
      final summary = entry.key;

      final matchedEvents = eventsByDay.values
          .expand((list) => list)
          .where((e) => e.summary == summary)
          .toList();

      if (matchedEvents.isEmpty) return const SizedBox();

      final first = matchedEvents.first;
      final progress = _getProgress(first.description);

      if (progress == 100) return const SizedBox();

      final startUtc = first.start?.date;
      final endUtc = first.end?.date;

      final start = startUtc != null
          ? DateTime(startUtc.year, startUtc.month, startUtc.day)
          : null;

      final end = endUtc != null
          ? DateTime(endUtc.year, endUtc.month, endUtc.day).subtract(const Duration(days: 1))
          : null;

      String label = summary;
      if (start != null && end != null) {
        label += " (${start.month}/${start.day}~${end.month}/${end.day}, $progress%)";
      }

      return FilterChip(
        label: Text(
          label,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        selected: entry.value,
        selectedColor: Colors.deepPurple.shade50,
        backgroundColor: Colors.white,
        checkmarkColor: Colors.deepPurple,
        side: BorderSide(
          color: entry.value ? Colors.deepPurple : Colors.grey.shade300,
          width: 1.2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        onSelected: (selected) async {
          onFilterChanged(summary, selected);
          await saveFilterStates(filterStates);

          if (selected && selectedDay != null) {
            final normalizedSelected = normalizeDate(selectedDay!);
            final selectedDateEvents = eventsByDay[normalizedSelected] ?? [];
            final target = selectedDateEvents
                .where((e) => e.summary == summary)
                .toList()
                .firstOrNull;

            if (target != null) {
              await editEvent(
                context: context,
                event: target,
                focusedDay: focusedDay,
                updateEvents: updateEvents,
                filterStates: filterStates,
              );
            }
          }
        },
      );
    }).whereType<Widget>().toList();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Wrap(
        spacing: 10,
        children: chips,
      ),
    );
  }
}
