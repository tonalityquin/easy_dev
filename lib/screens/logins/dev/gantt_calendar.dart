import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'event_editor.dart';

class GanttCalendar extends StatefulWidget {
  const GanttCalendar({super.key});

  @override
  State<GanttCalendar> createState() => _GanttCalendarState();
}

class _GanttCalendarState extends State<GanttCalendar> {
  final String calendarId = 'surge1868@gmail.com';
  final String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  DateTime weekStart = DateTime.now().subtract(Duration(days: DateTime.now().weekday - 1));
  DateTime weekEnd = DateTime.now().add(Duration(days: 7 - DateTime.now().weekday));

  List<calendar.Event> _events = [];

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  Future<AutoRefreshingAuthClient> getAuthClient({bool write = false}) async {
    final jsonString = await rootBundle.loadString(serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonString);
    final scopes = write ? [calendar.CalendarApi.calendarScope] : [calendar.CalendarApi.calendarReadonlyScope];
    return await clientViaServiceAccount(credentials, scopes);
  }

  Future<void> _loadEvents() async {
    try {
      final client = await getAuthClient();
      final calendarApi = calendar.CalendarApi(client);

      final result = await calendarApi.events.list(
        calendarId,
        timeMin: weekStart.toUtc(),
        timeMax: weekEnd.toUtc(),
        singleEvents: true,
        orderBy: 'startTime',
      );

      setState(() {
        _events = result.items ?? [];
      });
    } catch (e) {
      print('이벤트 로딩 실패: $e');
    }
  }

  Future<void> _addEvent() async {
    final result = await showEventEditorBottomSheet(context: context);
    if (result != null) {
      final client = await getAuthClient(write: true);
      final calendarApi = calendar.CalendarApi(client);

      final newEvent = calendar.Event()
        ..summary = result.title
        ..start = calendar.EventDateTime(date: DateTime.utc(result.start.year, result.start.month, result.start.day))
        ..end = calendar.EventDateTime(date: DateTime.utc(result.end.year, result.end.month, result.end.day));

      await calendarApi.events.insert(newEvent, calendarId);
      await _loadEvents();
    }
  }

  Future<void> _editEvent(calendar.Event event) async {
    final start = event.start?.date?.toLocal() ?? DateTime.now();
    final end = event.end?.date?.toLocal() ?? start.add(const Duration(days: 1));

    final result = await showEventEditorBottomSheet(
      context: context,
      initialTitle: event.summary,
      initialStart: start,
      initialEnd: end,
    );

    if (result != null) {
      final client = await getAuthClient(write: true);
      final calendarApi = calendar.CalendarApi(client);

      event.summary = result.title;
      event.start = calendar.EventDateTime(date: DateTime.utc(result.start.year, result.start.month, result.start.day));
      event.end = calendar.EventDateTime(date: DateTime.utc(result.end.year, result.end.month, result.end.day));

      await calendarApi.events.update(event, calendarId, event.id!);
      await _loadEvents();
    }
  }

  Future<void> _deleteEvent(calendar.Event event) async {
    final client = await getAuthClient(write: true);
    final calendarApi = calendar.CalendarApi(client);

    await calendarApi.events.delete(calendarId, event.id!);
    await _loadEvents();
  }

  @override
  Widget build(BuildContext context) {
    final days = List.generate(7, (i) => weekStart.add(Duration(days: i)));

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: Text(
          '캘린더',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
      ),
      body: Column(
        children: [
          Row(
            children: days
                .map((d) => Expanded(
                      child: Center(
                          child: Text("${d.month}/${d.day}", style: const TextStyle(fontWeight: FontWeight.bold))),
                    ))
                .toList(),
          ),
          const Divider(),
          Expanded(
            child: ListView.builder(
              itemCount: _events.length,
              itemBuilder: (context, index) {
                final event = _events[index];
                final start = event.start?.date?.toLocal();
                final end = event.end?.date?.toLocal();
                if (start == null || end == null) return const SizedBox();

                int startOffset = start.difference(weekStart).inDays.clamp(0, 6);
                int length = end.difference(start).inDays.clamp(1, 7 - startOffset);

                return GestureDetector(
                  onTap: () => _editEvent(event),
                  onLongPress: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text("삭제 확인"),
                        content: const Text("이 일정을 삭제할까요?"),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("취소")),
                          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("삭제")),
                        ],
                      ),
                    );
                    if (confirm == true) await _deleteEvent(event);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: List.generate(7, (i) {
                        if (i >= startOffset && i < startOffset + length) {
                          return Expanded(
                            child: Container(
                              height: 24,
                              color: Colors.blue,
                              alignment: Alignment.center,
                              child: Text(
                                index == i ? (event.summary ?? '제목') : '',
                                style: const TextStyle(fontSize: 12, color: Colors.white),
                              ),
                            ),
                          );
                        } else {
                          return const Expanded(child: SizedBox());
                        }
                      }),
                    ),
                  ),
                );
              },
            ),
          )
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addEvent,
        backgroundColor: Theme.of(context).colorScheme.primary,
        child: const Icon(Icons.add),
      ),
    );
  }
}
