import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';

class GoogleCalendar extends StatefulWidget {
  final String selectedArea;

  const GoogleCalendar({super.key, required this.selectedArea});

  @override
  State<GoogleCalendar> createState() => _GoogleCalendarState();
}

class _GoogleCalendarState extends State<GoogleCalendar> {
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
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
    _loadAllEvents().then((_) => _loadEventsForDay(_selectedDay!));
  }

  Future<AutoRefreshingAuthClient> getAuthClient({bool write = false}) async {
    final jsonString = await rootBundle.loadString(serviceAccountPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonString);
    final scopes = write ? [calendar.CalendarApi.calendarScope] : [calendar.CalendarApi.calendarReadonlyScope];
    return await clientViaServiceAccount(credentials, scopes);
  }

  Future<void> _loadAllEvents() async {
    try {
      final client = await getAuthClient();
      final calendarApi = calendar.CalendarApi(client);

      final now = DateTime.now();
      final start = DateTime(now.year, 1, 1).toUtc();
      final end = DateTime(now.year, 12, 31).toUtc();

      final result = await calendarApi.events.list(
        calendarId,
        timeMin: start,
        timeMax: end,
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

      setState(() {
        _allEvents = eventMap;
      });
    } catch (e) {
      print('모든 일정 로딩 실패: $e');
    }
  }

  Future<void> _loadEventsForDay(DateTime day) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final key = DateTime(day.year, day.month, day.day);
      setState(() {
        _events = _allEvents[key] ?? [];
      });
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _addOrEditEvent({calendar.Event? existing}) async {
    final titleController = TextEditingController(text: existing?.summary ?? '');
    final rawDesc = existing?.description ?? '';
    final isDone = rawDesc.contains('✔️DONE');
    final descText = rawDesc.replaceAll('✔️DONE', '').trim();
    final descriptionController = TextEditingController(text: descText);
    bool done = isDone;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // 배경을 투명하게 설정
      builder: (context) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white, // ✅ 흰색 배경 지정
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
            left: 16,
            right: 16,
            top: 24,
          ),
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              return Wrap(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 16),
                      decoration: BoxDecoration(
                        color: Colors.grey[400],
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  Text(
                    existing == null ? '일정 추가' : '일정 수정',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: '제목'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: '설명'),
                    minLines: 2,
                    maxLines: 4,
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    title: const Text('완료됨'),
                    value: done,
                    onChanged: (value) {
                      setDialogState(() => done = value ?? false);
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (existing != null)
                        TextButton(
                          onPressed: () async {
                            Navigator.pop(context);
                            await _deleteEvent(existing.id!);
                          },
                          child: const Text('삭제', style: TextStyle(color: Colors.red)),
                        ),
                      const Spacer(),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('취소'),
                      ),
                      ElevatedButton(
                        onPressed: () async {
                          if (titleController.text.trim().isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('제목을 입력해주세요')),
                            );
                            return;
                          }

                          Navigator.pop(context);
                          String finalDesc = descriptionController.text.trim();
                          if (done) {
                            finalDesc = '${finalDesc.isEmpty ? '' : '$finalDesc\n'}✔️DONE';
                          }

                          await _saveEvent(titleController.text, finalDesc, existing);
                        },
                        child: Text(existing == null ? '추가' : '수정'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _saveEvent(String title, String description, calendar.Event? existing) async {
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

    try {
      if (existing == null) {
        await calendarApi.events.insert(event, calendarId);
      } else {
        await calendarApi.events.update(event, calendarId, existing.id!);
      }
      await _loadAllEvents();
      await _loadEventsForDay(date);
    } catch (e) {
      print('일정 저장 실패: $e');
    }
  }

  Future<void> _toggleDone(calendar.Event event) async {
    final isDone = event.description?.contains('✔️DONE') ?? false;
    String desc = (event.description ?? '').replaceAll('✔️DONE', '').trim();

    if (!isDone) {
      desc = (desc.isEmpty ? '' : '$desc\n') + '✔️DONE';
    }

    await _saveEvent(event.summary ?? '제목 없음', desc, event);
  }

  Future<void> _deleteEvent(String eventId) async {
    final client = await getAuthClient(write: true);
    final calendarApi = calendar.CalendarApi(client);

    try {
      await calendarApi.events.delete(calendarId, eventId);
      await _loadAllEvents();
      await _loadEventsForDay(_selectedDay ?? DateTime.now());
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
      body: Column(
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
            eventLoader: (day) => _allEvents[DateTime(day.year, day.month, day.day)] ?? [],
            calendarBuilders: CalendarBuilders(
              markerBuilder: (context, date, events) {
                if (events.isEmpty) return const SizedBox();

                final allDone = events.every((e) => e is calendar.Event && (e.description ?? '').contains('✔️DONE'));

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
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _events.isEmpty
                    ? const Center(child: Text("일정이 없습니다."))
                    : ListView.builder(
                        itemCount: _events.length,
                        itemBuilder: (context, index) {
                          final event = _events[index];
                          final isDone = event.description?.contains('✔️DONE') ?? false;
                          final description = event.description?.replaceAll('✔️DONE', '').trim();

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
                                const Text('종일 일정'),
                                if (description != null && description.isNotEmpty)
                                  Text('설명: $description', style: const TextStyle(fontSize: 13)),
                              ],
                            ),
                            onTap: () => _addOrEditEvent(existing: event),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _addOrEditEvent(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
