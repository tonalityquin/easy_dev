import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';

import 'widget/event_editor_bottom_sheet.dart';

class GoogleCalendar extends StatefulWidget {
  final String selectedArea;

  const GoogleCalendar({super.key, required this.selectedArea});

  @override
  State<GoogleCalendar> createState() => _GoogleCalendarState();
}

class _GoogleCalendarState extends State<GoogleCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  DateTime? _loadedStart;
  DateTime? _loadedEnd;
  List<calendar.Event> _events = [];
  Map<DateTime, List<calendar.Event>> _allEvents = {};
  bool _isLoading = false;

  final String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';
  late final String calendarId;

  final Map<String, String> calendarMap = {
    'belivus': '057a6dc84afa3ba3a28ef0f21f8c298100290f4192bcca55a55a83097d56d7fe@group.calendar.google.com',
    'pelican': '4ad4d982312d0b885144406cf7197d536ae7dfc36b52736c6bce726bec19c562@group.calendar.google.com',
  };

  @override
  void initState() {
    super.initState();
    calendarId = calendarMap[widget.selectedArea] ?? calendarMap['belivus']!;
    _selectedDay = _focusedDay;
    _loadAndDisplayEvents(_focusedDay);
  }

  Future<AutoRefreshingAuthClient> getAuthClient({bool write = false}) async {
    final jsonString = await rootBundle.loadString(serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonString);
    final scopes = write ? [calendar.CalendarApi.calendarScope] : [calendar.CalendarApi.calendarReadonlyScope];
    return await clientViaServiceAccount(credentials, scopes);
  }

  DateTime getMonthStart(DateTime day) => DateTime(day.year, day.month - 1, 1);
  DateTime getMonthEnd(DateTime day) => DateTime(day.year, day.month + 2, 0);

  Future<void> _loadAndDisplayEvents(DateTime forMonth) async {
    final start = getMonthStart(forMonth);
    final end = getMonthEnd(forMonth);

    // 같은 범위를 중복 요청하지 않도록 방지
    if (_loadedStart == start && _loadedEnd == end) {
      _loadEventsForDay(_selectedDay ?? forMonth);
      return;
    }

    setState(() => _isLoading = true);

    try {
      final client = await getAuthClient();
      final calendarApi = calendar.CalendarApi(client);

      final result = await calendarApi.events.list(
        calendarId,
        timeMin: start.toUtc(),
        timeMax: end.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );

      final items = result.items ?? [];
      final Map<DateTime, List<calendar.Event>> eventMap = {};

      for (var event in items) {
        final localDate = (event.start?.dateTime ?? event.start?.date)?.toLocal();
        if (localDate != null) {
          final key = DateTime(localDate.year, localDate.month, localDate.day);
          eventMap.putIfAbsent(key, () => []).add(event);
        }
      }

      _loadedStart = start;
      _loadedEnd = end;

      setState(() {
        _allEvents = eventMap;
      });

      await _loadEventsForDay(_selectedDay ?? forMonth);
    } catch (e) {
      print('일정 로딩 실패: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadEventsForDay(DateTime day) async {
    if (!mounted) return;
    setState(() {
      _events = _allEvents[DateTime(day.year, day.month, day.day)] ?? [];
    });
  }

  Future<void> _addOrEditEvent({calendar.Event? existing}) async {
    final title = existing?.summary ?? '';
    final desc = existing?.description?.trim() ?? '';
    final done = existing?.extendedProperties?.private?['done'] == 'true';

    final result = await showEventEditorBottomSheet(
      context: context,
      initialTitle: title,
      initialDescription: desc,
      initialDone: done,
      isEdit: existing != null,
      onDelete: existing != null ? () async => await _deleteEvent(existing.id!) : null,
    );

    if (result != null) {
      await _saveEvent(result.title, result.description, result.done, existing);
    }
  }

  Future<void> _saveEvent(String title, String description, bool done, calendar.Event? existing) async {
    final client = await getAuthClient(write: true);
    final calendarApi = calendar.CalendarApi(client);
    final date = _selectedDay ?? DateTime.now();
    final event = existing ?? calendar.Event();

    event.summary = title;
    event.description = description;
    event.start = calendar.EventDateTime(
      date: DateTime.utc(date.year, date.month, date.day),
      timeZone: "UTC",
    );
    event.end = calendar.EventDateTime(
      date: DateTime.utc(date.year, date.month, date.day + 1),
      timeZone: "UTC",
    );

    event.extendedProperties ??= calendar.EventExtendedProperties();
    event.extendedProperties!.private = {'done': done.toString()};

    try {
      if (existing == null) {
        await calendarApi.events.insert(event, calendarId);
      } else {
        await calendarApi.events.update(event, calendarId, existing.id!);
      }
      await _loadAndDisplayEvents(_focusedDay);
    } catch (e) {
      print('일정 저장 실패: $e');
    }
  }

  Future<void> _toggleDone(calendar.Event event) async {
    final isDone = event.extendedProperties?.private?['done'] == 'true';
    final description = event.description ?? '';
    await _saveEvent(event.summary ?? '제목 없음', description, !isDone, event);
  }

  Future<void> _deleteEvent(String eventId) async {
    final client = await getAuthClient(write: true);
    final calendarApi = calendar.CalendarApi(client);
    try {
      await calendarApi.events.delete(calendarId, eventId);
      await _loadAndDisplayEvents(_focusedDay);
    } catch (e) {
      print('일정 삭제 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '${widget.selectedArea} 캘린더',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.only(bottom: 80),
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020, 1, 1),
            lastDay: DateTime.utc(2030, 12, 31),
            focusedDay: _focusedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selectedDay, focusedDay) {
              setState(() {
                _selectedDay = selectedDay;
                _focusedDay = focusedDay;
              });
              _loadEventsForDay(selectedDay);
            },
            onPageChanged: (focusedDay) {
              _focusedDay = focusedDay;
              _loadAndDisplayEvents(focusedDay);
            },
            eventLoader: (day) => _allEvents[DateTime(day.year, day.month, day.day)] ?? [],
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                if (events.isEmpty) return const SizedBox();
                final allDone =
                events.every((e) => e is calendar.Event && e.extendedProperties?.private?['done'] == 'true');
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(bottom: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: allDone ? Colors.green : Colors.red,
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(),
          if (_events.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: Text("일정이 없습니다.")),
            )
          else
            ..._events.map((event) {
              final isDone = event.extendedProperties?.private?['done'] == 'true';
              final description = event.description?.trim() ?? '';
              final startTime = event.start?.dateTime?.toLocal();
              final isAllDay = event.start?.date != null;

              final timeLabel = isAllDay
                  ? '종일 일정'
                  : (startTime != null
                  ? '${startTime.hour.toString().padLeft(2, '0')}:${startTime.minute.toString().padLeft(2, '0')}'
                  : '');

              return ListTile(
                title: Text(
                  event.summary ?? '제목 없음',
                  style: TextStyle(
                    decoration: isDone ? TextDecoration.lineThrough : null,
                  ),
                ),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (timeLabel.isNotEmpty)
                      Text(timeLabel, style: const TextStyle(fontSize: 13, color: Colors.grey)),
                    if (description.isNotEmpty)
                      Text(
                        '설명: $description',
                        style: const TextStyle(fontSize: 13),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ),
                trailing: Checkbox(
                  value: isDone,
                  onChanged: (_) => _toggleDone(event),
                ),
                onTap: () => _addOrEditEvent(existing: event),
              );
            }),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditEvent(),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        elevation: 4,
        tooltip: '일정 추가',
        child: const Icon(Icons.add),
      ),
    );
  }
}
