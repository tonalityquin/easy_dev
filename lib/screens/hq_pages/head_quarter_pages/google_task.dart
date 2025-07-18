import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';

import 'task_bottom_sheet.dart';

class TaskListFromCalendar extends StatefulWidget {
  final String selectedArea;

  const TaskListFromCalendar({super.key, required this.selectedArea});

  @override
  State<TaskListFromCalendar> createState() => _TaskListFromCalendarState();
}

class _TaskListFromCalendarState extends State<TaskListFromCalendar> {
  final String serviceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  List<calendar.Event> _taskEvents = [];
  bool _isLoading = false;

  DateTime? _loadedStart;
  DateTime? _loadedEnd;

  /// ✅ selectedArea에 따라 calendarId 반환
  String get calendarId {
    switch (widget.selectedArea) {
      case 'pelican':
        return '4ad4d982312d0b885144406cf7197d536ae7dfc36b52736c6bce726bec19c562@group.calendar.google.com';
      case 'belivus':
      default:
        return '057a6dc84afa3ba3a28ef0f21f8c298100290f4192bcca55a55a83097d56d7fe@group.calendar.google.com';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadTasksFromCalendar();
  }

  Future<AutoRefreshingAuthClient> getAuthClient({bool write = false}) async {
    final jsonString = await rootBundle.loadString(serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonString);
    final scopes = write
        ? [calendar.CalendarApi.calendarScope]
        : [calendar.CalendarApi.calendarReadonlyScope];
    return await clientViaServiceAccount(credentials, scopes);
  }

  /// ✅ 월 단위 범위 설정 (이전, 현재, 다음)
  DateTime get _rangeStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month - 1, 1);
  }

  DateTime get _rangeEnd {
    final now = DateTime.now();
    final nextMonth = DateTime(now.year, now.month + 2, 1);
    return DateTime(nextMonth.year, nextMonth.month, 0, 23, 59, 59);
  }

  Future<void> _loadTasksFromCalendar() async {
    final start = _rangeStart;
    final end = _rangeEnd;

    if (_loadedStart == start && _loadedEnd == end) return;

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

      final events = result.items ?? [];

      events.sort((a, b) {
        final aTime = a.start?.dateTime ?? a.start?.date ?? DateTime.now().toUtc();
        final bTime = b.start?.dateTime ?? b.start?.date ?? DateTime.now().toUtc();
        return aTime.compareTo(bTime);
      });

      setState(() {
        _taskEvents = events;
        _loadedStart = start;
        _loadedEnd = end;
      });
    } catch (e) {
      print('할 일 로딩 오류: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleDone(calendar.Event event) async {
    final isDone = event.description?.contains('✔️DONE') ?? false;
    String newDescription = (event.description ?? '').replaceAll('✔️DONE', '').trim();

    if (!isDone) {
      newDescription = '${newDescription.isEmpty ? '' : '$newDescription\n'}✔️DONE';
    }

    final updatedEvent = calendar.Event()
      ..summary = event.summary
      ..description = newDescription
      ..start = event.start
      ..end = event.end;

    try {
      final client = await getAuthClient(write: true);
      final calendarApi = calendar.CalendarApi(client);
      await calendarApi.events.update(updatedEvent, calendarId, event.id!);
      await _loadTasksFromCalendar();
    } catch (e) {
      print('완료 상태 업데이트 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('캘린더 할 일 목록'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _taskEvents.isEmpty
          ? const Center(child: Text('할 일이 없습니다.'))
          : ListView.builder(
        itemCount: _taskEvents.length,
        itemBuilder: (context, index) {
          final event = _taskEvents[index];
          final isDone = event.description?.contains('✔️DONE') ?? false;
          final description = event.description?.replaceAll('✔️DONE', '').trim();

          final dateTime = event.start?.dateTime ?? event.start?.date;
          final localDate = dateTime?.toLocal();
          final formattedDate = localDate != null
              ? "${localDate.year}-${localDate.month.toString().padLeft(2, '0')}-${localDate.day.toString().padLeft(2, '0')}"
              : '날짜 없음';

          return ListTile(
            leading: Checkbox(
              value: isDone,
              onChanged: (_) => _toggleDone(event),
            ),
            title: Text(
              event.summary ?? '제목 없음',
              style: TextStyle(
                decoration: isDone ? TextDecoration.lineThrough : null,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('날짜: $formattedDate'),
                if (description != null && description.isNotEmpty)
                  Text('설명: $description', style: const TextStyle(fontSize: 14)),
              ],
            ),
            onTap: () => showEditTaskBottomSheet(
              context: context,
              event: event,
              calendarId: calendarId,
              getAuthClient: getAuthClient,
              reloadEvents: _loadTasksFromCalendar,
            ),
          );
        },
      ),
    );
  }
}
