import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;

import '../../../dev/debug/debug_api_logger.dart';

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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (events.isEmpty) {
      return Center(
        child: Text(
          '이벤트가 없습니다.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
          ),
        ),
      );
    }

    final fmtDate = DateFormat('yyyy-MM-dd (EEE)');
    final fmtDateTime = DateFormat('yyyy-MM-dd (EEE) HH:mm');

    return ListView.separated(
      itemCount: events.length,
      separatorBuilder: (_, __) => Divider(
        height: 1,
        color: cs.outlineVariant.withOpacity(0.6),
      ),
      itemBuilder: (context, i) {
        final e = events[i];

        final isAllDay = (e.start?.date != null) && (e.start?.dateTime == null);
        final startUtc = e.start?.dateTime;
        final startLocal =
            (startUtc != null) ? startUtc.toLocal() : e.start?.date;

        final when = (startLocal != null)
            ? (isAllDay
                ? fmtDate.format(startLocal)
                : fmtDateTime.format(startLocal))
            : '(시작 시간 미정)';

        final done = progressOf(e) == 100;
        final title = (e.summary?.trim().isNotEmpty == true)
            ? e.summary!.trim()
            : '(제목 없음)';

        return ListTile(
          leading: Theme(
            data: theme.copyWith(
              checkboxTheme: theme.checkboxTheme.copyWith(
                fillColor: WidgetStateProperty.resolveWith<Color?>((states) {
                  if (states.contains(WidgetState.selected)) return cs.primary;
                  return cs.onSurfaceVariant.withOpacity(0.25);
                }),
                checkColor: WidgetStateProperty.all<Color>(cs.onPrimary),
              ),
            ),
            child: Checkbox(
              value: done,
              onChanged: (v) async {
                await _safeToggleProgress(
                    context, e, v ?? false, onToggleProgress);
              },
            ),
          ),
          title: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: done
                ? theme.textTheme.bodyLarge?.copyWith(
                    decoration: TextDecoration.lineThrough,
                    color: cs.onSurfaceVariant,
                  )
                : theme.textTheme.bodyLarge?.copyWith(
                    color: cs.onSurface,
                  ),
          ),
          subtitle: Text(
            when,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
          onTap: () => _showEventViewSheet(
            context,
            e,
            onEdit: onEdit,
            onDelete: onDelete,
            onToggleProgress: onToggleProgress,
            progressOf: progressOf,
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '수정',
                icon: Icon(Icons.edit_outlined, color: cs.primary),
                onPressed: () => _safeEdit(context, e, onEdit),
              ),
              IconButton(
                tooltip: '삭제',
                icon: Icon(Icons.delete_outline, color: cs.error),
                onPressed: () => _safeDelete(context, e, onDelete),
              ),
            ],
          ),
        );
      },
    );
  }
}

const String _tCal = 'calendar';
const String _tCalUi = 'calendar/ui';
const String _tCalEventList = 'calendar/event_list';
const String _tCalSheet = 'calendar/event_sheet';
const String _tCalAction = 'calendar/action';

Future<void> _logApiError({
  required String tag,
  required String message,
  required Object error,
  Map<String, dynamic>? extra,
  List<String>? tags,
}) async {
  try {
    await DebugApiLogger().log(
      <String, dynamic>{
        'tag': tag,
        'message': message,
        'error': error.toString(),
        if (extra != null) 'extra': extra,
      },
      level: 'error',
      tags: tags,
    );
  } catch (_) {}
}

Map<String, dynamic> _eventCtx(gcal.Event e) {
  final title = (e.summary ?? '').trim();
  return <String, dynamic>{
    'eventId': e.id ?? '',
    'summaryLen': title.length,
    'hasLocation': (e.location ?? '').trim().isNotEmpty,
    'hasDescription': (e.description ?? '').trim().isNotEmpty,
    'isAllDay': (e.start?.date != null) && (e.start?.dateTime == null),
  };
}

Future<void> _safeEdit(
  BuildContext context,
  gcal.Event e,
  void Function(BuildContext, gcal.Event) onEdit,
) async {
  try {
    onEdit(context, e);
  } catch (err) {
    await _logApiError(
      tag: 'EventList._safeEdit',
      message: '이벤트 편집 핸들러(onEdit) 실행 실패',
      error: err,
      extra: _eventCtx(e),
      tags: const <String>[_tCal, _tCalUi, _tCalEventList, _tCalAction],
    );
  }
}

Future<void> _safeDelete(
  BuildContext context,
  gcal.Event e,
  void Function(BuildContext, gcal.Event) onDelete,
) async {
  try {
    onDelete(context, e);
  } catch (err) {
    await _logApiError(
      tag: 'EventList._safeDelete',
      message: '이벤트 삭제 핸들러(onDelete) 실행 실패',
      error: err,
      extra: _eventCtx(e),
      tags: const <String>[_tCal, _tCalUi, _tCalEventList, _tCalAction],
    );
  }
}

Future<void> _safeToggleProgress(
  BuildContext context,
  gcal.Event e,
  bool done,
  Future<void> Function(BuildContext, gcal.Event, bool) onToggleProgress,
) async {
  try {
    await onToggleProgress(context, e, done);
  } catch (err) {
    await _logApiError(
      tag: 'EventList._safeToggleProgress',
      message: '진행 상태 토글(onToggleProgress) 실패',
      error: err,
      extra: <String, dynamic>{
        ..._eventCtx(e),
        'targetDone': done,
      },
      tags: const <String>[_tCal, _tCalUi, _tCalEventList, _tCalAction],
    );
  }
}

Future<void> _showEventViewSheet(
  BuildContext context,
  gcal.Event e, {
  required void Function(BuildContext, gcal.Event) onEdit,
  required void Function(BuildContext, gcal.Event) onDelete,
  required Future<void> Function(BuildContext, gcal.Event, bool)
      onToggleProgress,
  required int Function(gcal.Event) progressOf,
}) async {
  final isAllDay = e.start?.date != null && e.start?.dateTime == null;
  final localStart = e.start?.dateTime?.toLocal();
  final localEnd = e.end?.dateTime?.toLocal();
  final title =
      (e.summary?.trim().isNotEmpty == true) ? e.summary!.trim() : '(제목 없음)';
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
    String hhmm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

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

  try {
    final rootTheme = Theme.of(context);
    final cs = rootTheme.colorScheme;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      backgroundColor: cs.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final cs = theme.colorScheme;

        return FractionallySizedBox(
          heightFactor: 0.9,
          child: Material(
            color: cs.surface,
            surfaceTintColor: Colors.transparent,
            child: SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 12,
                  bottom: 16 + MediaQuery.of(sheetContext).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: cs.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: '수정',
                            icon: Icon(Icons.edit_outlined, color: cs.primary),
                            onPressed: () {
                              Navigator.of(sheetContext).pop();
                              _safeEdit(context, e, onEdit);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            done
                                ? Icons.check_circle
                                : Icons.radio_button_unchecked,
                            size: 18,
                            color: done ? cs.primary : cs.onSurfaceVariant,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              whenText(),
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: cs.onSurface),
                            ),
                          ),
                        ],
                      ),
                      if (location != null && location.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.place_outlined,
                                size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                location,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: cs.onSurface),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (desc != null && desc.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text('메모',
                            style: theme.textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(desc,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: cs.onSurface)),
                      ],
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: Icon(done
                                  ? Icons.undo_rounded
                                  : Icons.done_rounded),
                              label: Text(done ? '미완료로' : '완료하기'),
                              onPressed: () async {
                                Navigator.of(sheetContext).pop();
                                await _safeToggleProgress(
                                    context, e, !done, onToggleProgress);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('수정'),
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                _safeEdit(context, e, onEdit);
                              },
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                foregroundColor: cs.error,
                              ),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('삭제'),
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                _safeDelete(context, e, onDelete);
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
  } catch (err) {
    await _logApiError(
      tag: 'EventList._showEventViewSheet',
      message: '이벤트 상세 시트 표시(showModalBottomSheet) 실패',
      error: err,
      extra: _eventCtx(e),
      tags: const <String>[_tCal, _tCalUi, _tCalSheet],
    );
  }
}
