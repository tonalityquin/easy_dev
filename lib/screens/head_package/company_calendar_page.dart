// lib/screens/head_package/company_calendar_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_package/calendar_model.dart';
import 'calendar_package/event_editor_bottom_sheet.dart'; // ★ BottomSheet 버전 사용

class CompanyCalendarPage extends StatefulWidget {
  const CompanyCalendarPage({super.key});

  @override
  State<CompanyCalendarPage> createState() => _CompanyCalendarPageState();
}

class _CompanyCalendarPageState extends State<CompanyCalendarPage> {
  final _idCtrl = TextEditingController();
  static const _kLastCalendarIdKey = 'last_calendar_id';
  bool _autoTried = false; // 자동 로드 1회만 시도

  @override
  void initState() {
    super.initState();
    // Provider가 빌드된 뒤에 자동 로드 시도
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoload());
  }

  @override
  void dispose() {
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryAutoload() async {
    if (_autoTried) return;
    _autoTried = true;

    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getString(_kLastCalendarIdKey);
    if (lastId == null || lastId.trim().isEmpty) return;

    // 입력창에도 반영
    _idCtrl.text = lastId;

    // 자동 불러오기
    final model = context.read<CalendarModel>();
    await model.load(newCalendarId: lastId);

    // 불러오기 성공 시(에러 없을 때) 정규화된 ID로 보정 저장
    if (mounted && model.error == null && model.calendarId.isNotEmpty) {
      _idCtrl.text = model.calendarId;
      await prefs.setString(_kLastCalendarIdKey, model.calendarId);
    }
  }

  Future<void> _saveLastCalendarId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLastCalendarIdKey, id);
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
        onPressed: () => _openCreateSheet(context),
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
                    // 성공 시 정규화된 ID를 저장(다음 실행 때 자동 불러오기용)
                    if (mounted &&
                        model.error == null &&
                        model.calendarId.isNotEmpty) {
                      _idCtrl.text = model.calendarId;
                      await _saveLastCalendarId(model.calendarId);
                    }
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
                onEdit: _openEditSheet,
                onDelete: _confirmDelete,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateSheet(BuildContext context) async {
    final model = context.read<CalendarModel>();
    if (model.calendarId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 캘린더를 불러오세요.')),
      );
      return;
    }
    final now = DateTime.now();
    final created = await showEventEditorBottomSheet(
      context,
      title: '이벤트 생성',
      initialSummary: '',
      initialStart: now,
      initialEnd: now.add(const Duration(hours: 1)),
      // initialColorId: null,
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

  Future<void> _openEditSheet(BuildContext context, gcal.Event e) async {
    final model = context.read<CalendarModel>();
    final start = (e.start?.dateTime != null
        ? e.start!.dateTime!.toLocal()
        : e.start?.date) ??
        DateTime.now();
    final end = (e.end?.dateTime != null
        ? e.end!.dateTime!.toLocal()
        : e.end?.date) ??
        start.add(const Duration(hours: 1));
    final isAllDay = e.start?.date != null;

    final edited = await showEventEditorBottomSheet(
      context,
      title: '이벤트 수정',
      initialSummary: e.summary ?? '',
      initialDescription: e.description ?? '',
      initialStart: start,
      initialEnd: end,
      initialAllDay: isAllDay,
      initialColorId: e.colorId, // ★ 기존 색상 미리 선택
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

    final fmtDate = DateFormat('yyyy-MM-dd (EEE)');
    final fmtDateTime = DateFormat('yyyy-MM-dd (EEE) HH:mm');

    return ListView.separated(
      itemCount: events.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = events[i];

        final isAllDay =
            (e.start?.date != null) && (e.start?.dateTime == null);

        final startUtc = e.start?.dateTime;
        final startLocal =
        (startUtc != null) ? startUtc.toLocal() : e.start?.date;

        final when = (startLocal != null)
            ? (isAllDay ? fmtDate.format(startLocal) : fmtDateTime.format(startLocal))
            : '(시작 시간 미정)';

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
