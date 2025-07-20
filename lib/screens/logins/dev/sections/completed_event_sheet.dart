import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import 'calendar_logic.dart';

Future<void> showCompletedEventSheet({
  required BuildContext context,
  required Map<DateTime, List<calendar.Event>> eventsByDay,
  required String calendarId,
  required void Function(Map<DateTime, List<calendar.Event>>) onEventsDeleted,
}) async {
  // 100% 진행된 이벤트만 추출
  final seenIds = <String>{};
  final completedEvents =
  eventsByDay.values.expand((list) => list).where((event) => _getProgress(event.description) == 100).where((event) {
    final id = event.id;
    if (id == null || seenIds.contains(id)) return false;
    seenIds.add(id);
    return true;
  }).toList();

  if (completedEvents.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('완료된 할 일이 없습니다.')),
    );
    return;
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.7,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('완료된 할 일 목록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: completedEvents.length,
                  itemBuilder: (context, index) {
                    final e = completedEvents[index];
                    return ListTile(
                      title: Text(e.summary ?? '무제'),
                      subtitle: Text(e.description ?? ''),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.delete),
                  label: const Text('비우기'),
                  onPressed: () async {
                    final confirm = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('삭제 확인'),
                        content: const Text('완료된 할 일들을 모두 삭제하시겠습니까?'),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('취소'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            child: const Text('삭제'),
                          ),
                        ],
                      ),
                    );

                    if (confirm != true) return;

                    final client = await getAuthClient(write: true);
                    final calendarApi = calendar.CalendarApi(client);
                    for (var e in completedEvents) {
                      if (e.id != null) {
                        await calendarApi.events.delete(calendarId, e.id!);
                      }
                    }

                    final updated = await loadEventsForMonth(
                      month: DateTime.now(),
                      filterStates: {},
                    );
                    onEventsDeleted(updated);

                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('완료된 할 일을 모두 삭제했습니다.')),
                    );
                  },
                ),
              ),
              const SizedBox(height: 80), // ✅ 추가된 여백
            ],
          ),
        ),
      );
    },
  );
}

/// 내부에서 쓰는 진행률 추출 함수
int _getProgress(String? desc) {
  final match = RegExp(r'progress:(\d{1,3})').firstMatch(desc ?? '');
  if (match != null) {
    return int.tryParse(match.group(1) ?? '')?.clamp(0, 100) ?? 0;
  }
  return 0;
}
