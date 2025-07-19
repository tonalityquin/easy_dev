import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:table_calendar/table_calendar.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';
import 'dart:async';
import 'event_editor.dart';

class MonthlyGanttCalendar extends StatefulWidget {
  const MonthlyGanttCalendar({super.key});

  @override
  State<MonthlyGanttCalendar> createState() => _MonthlyGanttCalendarState();
}

class _MonthlyGanttCalendarState extends State<MonthlyGanttCalendar> {
  final String calendarId = 'surge1868@gmail.com';
  final String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  Map<DateTime, List<calendar.Event>> _eventsByDay = {};
  Map<String, bool> _filterStates = {};

  @override
  void initState() {
    super.initState();
    _loadFilterStates().then((_) {
      _loadEventsForMonth(_focusedDay);
    });
  }

  Future<AutoRefreshingAuthClient> getAuthClient({bool write = false}) async {
    final jsonString = await rootBundle.loadString(serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonString);
    final scopes = write ? [calendar.CalendarApi.calendarScope] : [calendar.CalendarApi.calendarReadonlyScope];
    return await clientViaServiceAccount(credentials, scopes);
  }

  Future<void> _loadEventsForMonth(DateTime month) async {
    final firstDay = DateTime(month.year, month.month, 1);
    final lastDay = DateTime(month.year, month.month + 1, 0);

    try {
      final client = await getAuthClient();
      final calendarApi = calendar.CalendarApi(client);
      final result = await calendarApi.events.list(
        calendarId,
        timeMin: firstDay.toUtc(),
        timeMax: lastDay.add(const Duration(days: 1)).toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );

      final items = result.items ?? [];
      final eventsMap = <DateTime, List<calendar.Event>>{};

      for (var event in items) {
        final title = event.summary ?? '무제';
        _filterStates.putIfAbsent(title, () => false);

        final start = event.start?.date?.toLocal();
        final end = event.end?.date != null ? event.end!.date!.toLocal().subtract(const Duration(days: 1)) : null;

        if (start != null && end != null) {
          for (DateTime date = start; !date.isAfter(end); date = date.add(const Duration(days: 1))) {
            eventsMap.putIfAbsent(date, () => []).add(event);
          }
        }
      }

      setState(() {
        _eventsByDay = eventsMap;
        _filterStates = Map.from(_filterStates);
      });
    } catch (e) {
      print("이벤트 로딩 실패: $e");
    }
  }

  List<calendar.Event> _getEventsForDay(DateTime day) {
    final raw = _eventsByDay[DateTime(day.year, day.month, day.day)] ?? [];
    return raw.where((e) => _filterStates[e.summary ?? '무제'] == true).toList();
  }

  int _getProgress(String? desc) {
    final match = RegExp(r'progress:(\d{1,3})').firstMatch(desc ?? '');
    if (match != null) {
      return int.tryParse(match.group(1) ?? '')?.clamp(0, 100) ?? 0;
    }
    return 0;
  }

  Widget _buildEventMarker(calendar.Event event) {
    final progress = _getProgress(event.description);
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 1),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.indigo,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${event.summary ?? ''} (${progress}%)',
        style: const TextStyle(fontSize: 10, color: Colors.white),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Future<void> _saveFilterStates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = jsonEncode(_filterStates);
    await prefs.setString('filterStates', jsonString);
  }

  Future<void> _loadFilterStates() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonString = prefs.getString('filterStates');
    if (jsonString != null) {
      final Map<String, dynamic> decoded = jsonDecode(jsonString);
      _filterStates = decoded.map((key, value) => MapEntry(key, value as bool));
    }
  }

  Future<void> _addEvent() async {
    final result = await showEventEditorBottomSheet(context: context);
    if (result == null) return;

    try {
      final client = await getAuthClient(write: true);
      final calendarApi = calendar.CalendarApi(client);

      final newEvent = calendar.Event()
        ..summary = result.title
        ..description = result.description
        ..start = calendar.EventDateTime(date: DateTime.utc(result.start.year, result.start.month, result.start.day))
        ..end = calendar.EventDateTime(date: DateTime.utc(result.end.year, result.end.month, result.end.day));

      await calendarApi.events.insert(newEvent, calendarId);
      await _loadEventsForMonth(_focusedDay);
    } catch (e) {
      print('이벤트 추가 실패: $e');
    }
  }

  Future<void> _editEvent(calendar.Event event) async {
    final start = event.start?.date?.toLocal() ?? DateTime.now();
    final end = event.end?.date?.toLocal() ?? start.add(const Duration(days: 1));

    final checklist = parseChecklistFromDescription(event.description);

    final result = await showEventEditorBottomSheet(
      context: context,
      initialTitle: event.summary,
      initialStart: start,
      initialEnd: end,
      initialChecklist: checklist,
    );

    if (result == null) return;

    final client = await getAuthClient(write: true);
    final calendarApi = calendar.CalendarApi(client);

    if (result.deleted) {
      // ✅ 삭제 처리 추가
      if (event.id != null) {
        await calendarApi.events.delete(calendarId, event.id!);
        await _loadEventsForMonth(_focusedDay);
      }
      return;
    }

    // ✅ 수정 처리
    event.summary = result.title;
    event.description = result.description;
    event.start = calendar.EventDateTime(date: DateTime.utc(result.start.year, result.start.month, result.start.day));
    event.end = calendar.EventDateTime(date: DateTime.utc(result.end.year, result.end.month, result.end.day));

    await calendarApi.events.update(event, calendarId, event.id!);
    await _loadEventsForMonth(_focusedDay);
  }

  List<ChecklistItem> parseChecklistFromDescription(String? description) {
    if (description == null) return [];
    final lines = description.split('\n').where((line) => line.startsWith('- [')).toList();
    return lines.map((line) {
      final checked = line.contains('- [x]');
      final text = line.replaceFirst(RegExp(r'- \[[ x]\]'), '').trim();
      return ChecklistItem(text: text, checked: checked);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
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
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
              _loadEventsForMonth(focusedDay);
            },
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, day, _) {
                final dailyEvents = (_eventsByDay[DateTime(day.year, day.month, day.day)] ?? [])
                    .where((e) => _filterStates[e.summary ?? '무제'] == true)
                    .toList();
                return Column(
                  children: dailyEvents.take(3).map(_buildEventMarker).toList(),
                );
              },
            ),
          ),
          const Divider(),
          if (_filterStates.isNotEmpty)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Wrap(
                spacing: 8,
                children: _filterStates.entries
                    .map((entry) {
                      final summary = entry.key;
                      final matchedEvents =
                          _eventsByDay.values.expand((list) => list).where((e) => e.summary == summary).toList();

                      if (matchedEvents.isEmpty) return const SizedBox();

                      final first = matchedEvents.first;
                      final start = first.start?.date?.toLocal();
                      DateTime? end;
                      if (first.end?.date != null) {
                        end = first.end!.date!.toLocal().subtract(const Duration(days: 1));
                      }

                      String label = summary;
                      if (start != null && end != null) {
                        label +=
                            " (${start.month}/${start.day}~${end.month}/${end.day}, ${_getProgress(first.description)}%)";
                      }

                      return FilterChip(
                        label: Text(label),
                        selected: entry.value,
                        onSelected: (selected) async {
                          setState(() {
                            _filterStates[summary] = selected;
                          });
                          await _saveFilterStates(); // 추가됨

                          if (selected && _selectedDay != null) {
                            final eventsOnDay = _getEventsForDay(_selectedDay!);
                            final target = eventsOnDay.where((e) => e.summary == summary).toList().firstOrNull;
                            if (target != null) {
                              await _editEvent(target);
                            }
                          }
                        },
                      );
                    })
                    .whereType<Widget>()
                    .toList(),
              ),
            ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(8),
              children: _getEventsForDay(_selectedDay ?? _focusedDay).map((event) {
                final progress = _getProgress(event.description);
                return Card(
                  child: ListTile(
                    title: Text(event.summary ?? ''),
                    subtitle: Text('진행률: $progress%'),
                    trailing: const Icon(Icons.check_circle_outline),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 48),
        child: FloatingActionButton(
          onPressed: _addEvent,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          elevation: 4,
          tooltip: '일정 추가',
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}
