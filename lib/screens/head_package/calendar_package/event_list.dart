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
            e.summary ?? '(제목 없음)',
            style: done ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
          ),
          subtitle: Text(when),
          onTap: () => onEdit(context, e),
          trailing: IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => onDelete(context, e),
          ),
        );
      },
    );
  }
}
