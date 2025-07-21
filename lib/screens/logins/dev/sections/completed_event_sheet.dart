import 'package:flutter/material.dart';
import 'package:googleapis/calendar/v3.dart' as calendar;
import '../utils/calendar_logic.dart';

/// 완료된 이벤트(진행률 100%)를 보여주는 바텀시트를 표시하고,
/// 사용자가 요청 시 해당 이벤트들을 삭제함
Future<void> showCompletedEventSheet({
  required BuildContext context,
  required Map<DateTime, List<calendar.Event>> eventsByDay,
  required String calendarId,
  required void Function(Map<DateTime, List<calendar.Event>>) onEventsDeleted,
}) async {
  // 이벤트 목록에서 중복 없이 진행률 100%인 항목만 필터링
  final seenIds = <String>{};
  final completedEvents = eventsByDay.values
      .expand((list) => list)
      .where((event) => _getProgress(event.description) == 100)
      .where((event) {
    final id = event.id;
    if (id == null || seenIds.contains(id)) return false;
    seenIds.add(id);
    return true;
  }).toList();

  // 완료된 항목이 없을 경우 안내 메시지 표시
  if (completedEvents.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('완료된 할 일이 없습니다.')),
    );
    return;
  }

  // 완료된 이벤트 바텀시트 표시
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
              // 제목
              const Text('완료된 할 일 목록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),

              // 완료된 이벤트 목록
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

              // 삭제 버튼 (우측 정렬)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  icon: const Icon(Icons.delete),
                  label: const Text('비우기'),
                  onPressed: () async {
                    // 삭제 확인 다이얼로그 표시
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

                    // Google Calendar API를 통해 이벤트 삭제 수행
                    final client = await getAuthClient(write: true);
                    final calendarApi = calendar.CalendarApi(client);
                    for (var e in completedEvents) {
                      if (e.id != null) {
                        await calendarApi.events.delete(calendarId, e.id!);
                      }
                    }

                    // 삭제 후 최신 이벤트 목록 불러와서 UI 갱신
                    final updated = await loadEventsForMonth(
                      month: DateTime.now(),
                      filterStates: {},
                    );
                    onEventsDeleted(updated);

                    // 바텀시트 닫기
                    Navigator.pop(context);

                    // 삭제 완료 안내
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('완료된 할 일을 모두 삭제했습니다.')),
                    );
                  },
                ),
              ),
              const SizedBox(height: 80), // 하단 여유 공간 확보
            ],
          ),
        ),
      );
    },
  );
}

/// description 문자열에서 진행률(progress)을 추출하여 정수(0~100)로 반환
int _getProgress(String? desc) {
  final match = RegExp(r'progress:(\d{1,3})').firstMatch(desc ?? '');
  if (match != null) {
    return int.tryParse(match.group(1) ?? '')?.clamp(0, 100) ?? 0;
  }
  return 0;
}
