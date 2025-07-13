import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';
import 'package:flutter/services.dart';

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

  Future<void> _loadTasksFromCalendar() async {
    setState(() => _isLoading = true);

    try {
      final client = await getAuthClient();
      final calendarApi = calendar.CalendarApi(client);

      final now = DateTime.now().toUtc();
      final oneYearLater = now.add(const Duration(days: 365)).toUtc();

      final result = await calendarApi.events.list(
        calendarId,
        timeMin: now,
        timeMax: oneYearLater,
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

  Future<void> _editEvent(calendar.Event event) async {
    final titleController = TextEditingController(text: event.summary ?? '');
    final isDone = event.description?.contains('✔️DONE') ?? false;
    final descText = (event.description ?? '').replaceAll('✔️DONE', '').trim();
    final descriptionController = TextEditingController(text: descText);
    bool done = isDone;

    DateTime selectedDate = event.start?.dateTime?.toLocal() ?? event.start?.date?.toLocal() ?? DateTime.now();

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('할 일 수정'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: '제목'),
              ),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(labelText: '설명'),
                maxLines: 2,
              ),
              Row(
                children: [
                  Checkbox(
                    value: done,
                    onChanged: (value) {
                      setDialogState(() => done = value ?? false);
                    },
                  ),
                  const Text('완료됨'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(Icons.calendar_today),
                  const SizedBox(width: 8),
                  Text(
                      "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}"),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) {
                        setDialogState(() => selectedDate = picked);
                      }
                    },
                    child: const Text('날짜 선택'),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('취소'),
            ),
            ElevatedButton(
              onPressed: () async {
                String finalDesc = descriptionController.text.trim();
                if (done) {
                  finalDesc = (finalDesc.isEmpty ? '' : '$finalDesc\n') + '✔️DONE';
                }

                final updatedEvent = calendar.Event()
                  ..summary = titleController.text
                  ..description = finalDesc
                  ..start = calendar.EventDateTime(
                      date: DateTime.utc(selectedDate.year, selectedDate.month, selectedDate.day))
                  ..end = calendar.EventDateTime(
                      date: DateTime.utc(selectedDate.year, selectedDate.month, selectedDate.day)
                          .add(const Duration(days: 1)));

                try {
                  final client = await getAuthClient(write: true);
                  final calendarApi = calendar.CalendarApi(client);
                  await calendarApi.events.update(updatedEvent, calendarId, event.id!);
                  Navigator.pop(context);
                  await _loadTasksFromCalendar();
                } catch (e) {
                  print('이벤트 수정 실패: $e');
                }
              },
              child: const Text('저장'),
            ),
          ],
        ),
      ),
    );
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
            onTap: () => _editEvent(event),
          );
        },
      ),
    );
  }
}
