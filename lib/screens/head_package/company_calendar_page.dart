import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'calendar_package/calendar_model.dart';
import 'calendar_package/event_editor_dialog.dart'; // 프로젝트 경로에 맞추세요

class CompanyCalendarPage extends StatefulWidget {
  const CompanyCalendarPage({super.key});

  @override
  State<CompanyCalendarPage> createState() => _CompanyCalendarPageState();
}

class _CompanyCalendarPageState extends State<CompanyCalendarPage> {
  final _idCtrl = TextEditingController();

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final model = context.watch<CalendarModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('회사 달력'),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _openCreateDialog(context),
        child: const Icon(Icons.add),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // 안내 배너
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withOpacity(.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '캘린더 ID 또는 URL을 입력 후 불러오기를 누르세요. (예: someone@gmail.com)',
                style: text.bodyMedium?.copyWith(
                  color: cs.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),

            // 입력 + 버튼
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _idCtrl,
                    decoration: const InputDecoration(
                      labelText: '캘린더 ID 또는 URL',
                      hintText: '예: someone@gmail.com 또는 Google Calendar URL',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: model.loading
                      ? null
                      : () async {
                    FocusScope.of(context).unfocus();
                    await context.read<CalendarModel>().load(
                      newCalendarId: _idCtrl.text,
                    );
                  },
                  icon: const Icon(Icons.download),
                  label: const Text('불러오기'),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (model.loading) const LinearProgressIndicator(),
            if (model.error != null) ...[
              const SizedBox(height: 8),
              Text(
                model.error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],

            const SizedBox(height: 8),
            Expanded(
              child: _EventList(
                events: model.events,
                onEdit: _openEditDialog,
                onDelete: _confirmDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateDialog(BuildContext context) async {
    final model = context.read<CalendarModel>();
    if (model.calendarId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 캘린더를 불러오세요.')),
      );
      return;
    }
    final now = DateTime.now();
    final created = await showDialog<EditResult>(
      context: context,
      builder: (_) => EventEditorDialog(
        title: '이벤트 생성',
        initialSummary: '',
        initialStart: now,
        initialEnd: now.add(const Duration(hours: 1)),
        // initialColorId: null, // 필요시 기본 선택 색상 강제
      ),
    );
    if (created == null) return;

    await model.create(
      summary: created.summary,
      description: created.description,
      start: created.start,
      end: created.end,
      allDay: created.allDay,
      colorId: created.colorId, // ★ 선택 색상 전달
    );
  }

  Future<void> _openEditDialog(BuildContext context, gcal.Event e) async {
    final model = context.read<CalendarModel>();
    final start =
        (e.start?.dateTime != null ? e.start!.dateTime!.toLocal() : e.start?.date) ?? DateTime.now();
    final end = (e.end?.dateTime != null ? e.end!.dateTime!.toLocal() : e.end?.date) ??
        start.add(const Duration(hours: 1));
    final isAllDay = e.start?.date != null;

    final edited = await showDialog<EditResult>(
      context: context,
      builder: (_) => EventEditorDialog(
        title: '이벤트 수정',
        initialSummary: e.summary ?? '',
        initialDescription: e.description ?? '',
        initialStart: start,
        initialEnd: end,
        initialAllDay: isAllDay,
        initialColorId: e.colorId, // ★ 기존 색상 미리 선택
      ),
    );
    if (edited == null) return;

    await model.update(
      eventId: e.id!,
      summary: edited.summary,
      description: edited.description,
      start: edited.start,
      end: edited.end,
      allDay: edited.allDay,
      colorId: edited.colorId, // ★ 선택 색상 전달
    );
  }

  Future<void> _confirmDelete(BuildContext context, gcal.Event e) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('삭제'),
        content: Text('이벤트를 삭제할까요?\n"${e.summary ?? '(제목 없음)'}"'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await context.read<CalendarModel>().delete(eventId: e.id!);
    }
  }
}

class _EventList extends StatelessWidget {
  const _EventList({
    required this.events,
    required this.onEdit,
    required this.onDelete,
  });

  final List<gcal.Event> events;
  final void Function(BuildContext, gcal.Event) onEdit;
  final void Function(BuildContext, gcal.Event) onDelete;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(child: Text('이벤트가 없습니다.'));
    }
    final fmtDate = DateFormat('yyyy-MM-dd (EEE) HH:mm');
    return ListView.separated(
      itemCount: events.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = events[i];
        final startUtc = e.start?.dateTime;
        final startLocal = (startUtc != null) ? startUtc.toLocal() : e.start?.date; // ★ 로컬로 변환
        final when = (startLocal != null) ? fmtDate.format(startLocal) : '(시작 시간 미정)';
        return ListTile(
          leading: const Icon(Icons.event),
          title: Text(e.summary ?? '(제목 없음)'),
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
