// lib/screens/head_package/company_calendar_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_package/calendar_model.dart';
import 'calendar_package/event_editor_bottom_sheet.dart'; // BottomSheet 버전 사용

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

  // ===== progress 태그 도우미 =====
  // 공백/대소문자 허용: [ progress : 100 ] 도 인식
  static final RegExp _progressTag =
  RegExp(r'\[\s*progress\s*:\s*(0|100)\s*\]', caseSensitive: false);

  int _extractProgress(String? description) {
    if (description == null) return 0;
    final m = _progressTag.firstMatch(description);
    if (m == null) return 0;
    final v = int.tryParse(m.group(1) ?? '0') ?? 0;
    return v == 100 ? 100 : 0;
  }

  String _setProgressTag(String? description, int progress) {
    final val = (progress == 100) ? 100 : 0;
    final base = (description ?? '').trimRight();

    if (_progressTag.hasMatch(base)) {
      // 여러 개가 있더라도 모두 최신 값으로 맞춤
      return base.replaceAllMapped(_progressTag, (_) => '[progress:$val]');
    }
    if (base.isEmpty) return '[progress:$val]';
    return '$base\n[progress:$val]';
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
                    // 성공 시 정규화된 ID 저장
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
                onToggleProgress: _toggleProgress, // 체크박스 토글
                progressOf: (e) => _extractProgress(e.description),
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
      initialProgress: 0, // 기본 0
    );
    if (created == null) return;

    // description에 진행도 태그 주입
    final descWithProgress =
    _setProgressTag(created.description, created.progress);

    await model.create(
      summary: created.summary,
      description: descWithProgress,
      start: created.start,
      end: created.end,
      allDay: created.allDay,
      colorId: created.colorId,
    );
  }

  Future<void> _openEditSheet(BuildContext context, gcal.Event e) async {
    final model = context.read<CalendarModel>();
    final start =
        (e.start?.dateTime != null ? e.start!.dateTime!.toLocal() : e.start?.date) ??
            DateTime.now();
    final end =
        (e.end?.dateTime != null ? e.end!.dateTime!.toLocal() : e.end?.date) ??
            start.add(const Duration(hours: 1));
    final isAllDay = e.start?.date != null;

    final initialProgress = _extractProgress(e.description); // 기존 진행도

    final edited = await showEventEditorBottomSheet(
      context,
      title: '이벤트 수정',
      initialSummary: e.summary ?? '',
      initialDescription: e.description ?? '',
      initialStart: start,
      initialEnd: end,
      initialAllDay: isAllDay,
      initialColorId: e.colorId,
      initialProgress: initialProgress,
    );
    if (edited == null) return;

    final descWithProgress =
    _setProgressTag(edited.description, edited.progress);

    await model.update(
      eventId: e.id!,
      summary: edited.summary,
      description: descWithProgress,
      start: edited.start,
      end: edited.end,
      allDay: edited.allDay,
      colorId: edited.colorId,
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

  // 체크박스 토글 → 진행도 0/100 업데이트
  Future<void> _toggleProgress(
      BuildContext context, gcal.Event e, bool done) async {
    final model = context.read<CalendarModel>();

    final start =
        (e.start?.dateTime != null ? e.start!.dateTime!.toLocal() : e.start?.date) ??
            DateTime.now();
    final end =
        (e.end?.dateTime != null ? e.end!.dateTime!.toLocal() : e.end?.date) ??
            start.add(const Duration(hours: 1));
    final isAllDay = e.start?.date != null;

    final newProgress = done ? 100 : 0;
    final newDesc = _setProgressTag(e.description, newProgress);

    await model.update(
      eventId: e.id!,
      summary: e.summary ?? '',
      description: newDesc,
      start: start,
      end: end,
      allDay: isAllDay,
      colorId: e.colorId,
    );
  }
}

class _EventList extends StatelessWidget {
  const _EventList({
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

        final isAllDay =
            (e.start?.date != null) && (e.start?.dateTime == null);

        final startUtc = e.start?.dateTime;
        final startLocal =
        (startUtc != null) ? startUtc.toLocal() : e.start?.date;

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
            style: done
                ? const TextStyle(decoration: TextDecoration.lineThrough)
                : null,
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
