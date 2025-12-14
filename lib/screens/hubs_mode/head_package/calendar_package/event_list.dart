// lib/screens/head_package/calendar_package/event_list.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

class EventList extends StatelessWidget {
  const EventList({
    super.key,
    required this.events,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleProgress,
    required this.progressOf,
  });

  final List<gcal.Event> events;
  final void Function(BuildContext, gcal.Event) onEdit;
  final void Function(BuildContext, gcal.Event) onDelete;
  final Future<void> Function(BuildContext, gcal.Event, bool) onToggleProgress;
  final int Function(gcal.Event) progressOf;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(child: Text('이벤트가 없습니다.'));
    }

    final fmtDate = DateFormat('yyyy-MM-dd (EEE)');
    final fmtDateTime = DateFormat('yyyy-MM-dd (EEE) HH:mm');

    return ListView.separated(
      itemCount: events.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = events[i];

        final isAllDay = (e.start?.date != null) && (e.start?.dateTime == null);
        final startUtc = e.start?.dateTime;
        final startLocal = (startUtc != null) ? startUtc.toLocal() : e.start?.date;

        final when = (startLocal != null)
            ? (isAllDay ? fmtDate.format(startLocal) : fmtDateTime.format(startLocal))
            : '(시작 시간 미정)';

        final done = progressOf(e) == 100;

        return ListTile(
          leading: Checkbox(
            value: done,
            onChanged: (v) => onToggleProgress(context, e, v ?? false),
          ),
          title: Text(
            (e.summary?.trim().isNotEmpty == true) ? e.summary!.trim() : '(제목 없음)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: done ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
          ),
          subtitle: Text(
            when,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          // ▶︎ 탭하면 "보기(읽기 전용) 시트"를 띄움 (수정 아이콘으로만 편집 진입)
          onTap: () => _showEventViewSheet(
            context,
            e,
            onEdit: onEdit,
            onDelete: onDelete,
            onToggleProgress: onToggleProgress,
            progressOf: progressOf,
          ),
          // onLongPress: () => _showEventViewSheet(context, e, ...),

          // ▶︎ 우측 액션: 편집/삭제
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '수정',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => onEdit(context, e),
              ),
              IconButton(
                tooltip: '삭제',
                icon: const Icon(Icons.delete_outline),
                onPressed: () => onDelete(context, e),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 읽기 전용 상세 보기 시트 - 화면 높이의 90% + 배경 흰색
Future<void> _showEventViewSheet(
    BuildContext context,
    gcal.Event e, {
      required void Function(BuildContext, gcal.Event) onEdit,
      required void Function(BuildContext, gcal.Event) onDelete,
      required Future<void> Function(BuildContext, gcal.Event, bool) onToggleProgress,
      required int Function(gcal.Event) progressOf,
    }) async {
  final isAllDay = e.start?.date != null && e.start?.dateTime == null;
  final localStart = e.start?.dateTime?.toLocal();
  final localEnd = e.end?.dateTime?.toLocal();
  final title = (e.summary?.trim().isNotEmpty == true) ? e.summary!.trim() : '(제목 없음)';
  final location = e.location?.trim();
  final desc = e.description?.trim();
  final done = progressOf(e) == 100;

  String whenText() {
    if (isAllDay && e.start?.date != null) {
      final d = e.start!.date!;
      return '종일 • ${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    }
    if (localStart == null) return '(시간 정보 없음)';
    final fmtDate = DateFormat('yyyy-MM-dd (EEE)');
    String hhmm(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

    if (localEnd != null) {
      final sameDay = localStart.year == localEnd.year &&
          localStart.month == localEnd.month &&
          localStart.day == localEnd.day;
      final dateStr = fmtDate.format(localStart);
      final timeStr = sameDay
          ? '${hhmm(localStart)}–${hhmm(localEnd)}'
          : '${hhmm(localStart)} → ${fmtDate.format(localEnd)} ${hhmm(localEnd)}';
      return '$dateStr • $timeStr';
    }
    return '${fmtDate.format(localStart)} • ${hhmm(localStart)}';
  }

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    backgroundColor: Colors.white, // ✅ 시트 배경 흰색
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) {
      return FractionallySizedBox(
        heightFactor: 0.9, // ✅ 항상 화면 높이의 90%
        child: Material(
          color: Colors.white,
          surfaceTintColor: Colors.transparent, // ✅ M3 틴트 제거
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 헤더: 제목 + 액션(수정)
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: '수정',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () {
                            Navigator.of(context).pop();
                            onEdit(context, e);
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // 진행 상태/시간
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(done ? Icons.check_circle : Icons.radio_button_unchecked, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(whenText(), style: const TextStyle(fontSize: 14)),
                        ),
                      ],
                    ),

                    if (location != null && location.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.place_outlined, size: 18),
                          const SizedBox(width: 8),
                          Expanded(child: Text(location, style: const TextStyle(fontSize: 14))),
                        ],
                      ),
                    ],

                    if (desc != null && desc.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      const Text('메모', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(desc, style: const TextStyle(fontSize: 14)),
                    ],

                    const SizedBox(height: 16),

                    // 하단 버튼: 완료 토글 / 수정 / 삭제
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: Icon(done ? Icons.undo_rounded : Icons.done_rounded),
                            label: Text(done ? '미완료로' : '완료하기'),
                            onPressed: () async {
                              Navigator.of(context).pop();
                              await onToggleProgress(context, e, !done);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('수정'),
                            onPressed: () {
                              Navigator.of(context).pop();
                              onEdit(context, e);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('삭제'),
                            onPressed: () {
                              Navigator.of(context).pop();
                              onDelete(context, e);
                            },
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
