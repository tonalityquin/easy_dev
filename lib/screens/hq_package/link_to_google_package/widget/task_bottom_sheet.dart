import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'package:googleapis_auth/auth_io.dart';

Future<bool?> showEditTaskBottomSheet({
  required BuildContext context,
  required calendar.Event event,
  required String calendarId,
  required Future<void> Function() reloadEvents,
  required Future<AutoRefreshingAuthClient> Function({bool write}) getAuthClient,
}) async {
  final titleController = TextEditingController(text: event.summary ?? '');
  final isDone = event.description?.contains('✔️DONE') ?? false;
  final descText = (event.description ?? '').replaceAll('✔️DONE', '').trim();
  final descriptionController = TextEditingController(text: descText);
  bool done = isDone;
  DateTime selectedDate = event.start?.dateTime?.toLocal() ?? event.start?.date?.toLocal() ?? DateTime.now();

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 24,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
        ),
        child: StatefulBuilder(
          builder: (context, setState) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('할 일 수정', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  TextField(
                    controller: titleController,
                    decoration: const InputDecoration(labelText: '제목'),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: '설명'),
                    maxLines: 2,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: done,
                        onChanged: (value) {
                          setState(() => done = value ?? false);
                        },
                      ),
                      const Text('완료됨'),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.calendar_today),
                      const SizedBox(width: 8),
                      Text(
                        "${selectedDate.year}-${selectedDate.month.toString().padLeft(2, '0')}-${selectedDate.day.toString().padLeft(2, '0')}",
                      ),
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setState(() => selectedDate = picked);
                          }
                        },
                        child: const Text('날짜 선택'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final deleted = await _deleteEvent(
                              event.id!,
                              calendarId,
                              getAuthClient,
                            );
                            if (deleted) {
                              await reloadEvents();
                              Navigator.pop(context, true);
                            }
                          },
                          icon: const Icon(Icons.delete, color: Colors.red),
                          label: const Text('삭제', style: TextStyle(color: Colors.red)),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            String finalDesc = descriptionController.text.trim();
                            if (done) {
                              finalDesc = '${finalDesc.isEmpty ? '' : '$finalDesc\n'}✔️DONE';
                            }

                            final updatedEvent = calendar.Event()
                              ..summary = titleController.text
                              ..description = finalDesc
                              ..start = calendar.EventDateTime(
                                date: DateTime.utc(
                                  selectedDate.year,
                                  selectedDate.month,
                                  selectedDate.day,
                                ),
                              )
                              ..end = calendar.EventDateTime(
                                date: DateTime.utc(
                                  selectedDate.year,
                                  selectedDate.month,
                                  selectedDate.day + 1,
                                ),
                              );

                            try {
                              final client = await getAuthClient(write: true);
                              final calendarApi = calendar.CalendarApi(client);
                              await calendarApi.events.update(updatedEvent, calendarId, event.id!);
                              await reloadEvents();
                              Navigator.pop(context, true);
                            } catch (e) {
                              debugPrint('이벤트 수정 실패: $e');
                            }
                          },
                          child: const Text('저장'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 80),
                ],
              ),
            );
          },
        ),
      );
    },
  );

  return result;
}
Future<bool> _deleteEvent(
    String eventId,
    String calendarId,
    Future<AutoRefreshingAuthClient> Function({bool write}) getAuthClient,
    ) async {
  try {
    final client = await getAuthClient(write: true);
    final calendarApi = calendar.CalendarApi(client);
    await calendarApi.events.delete(calendarId, eventId);
    return true;
  } catch (e) {
    debugPrint('이벤트 삭제 실패: $e');
    return false;
  }
}
