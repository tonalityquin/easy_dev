// lib/screens/head_package/company_calendar_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// import 'package:intl/intl.dart'; // ❌ 미사용이라 제거
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:shared_preferences/shared_preferences.dart';

import 'calendar_package/calendar_model.dart';
import 'calendar_package/event_editor_bottom_sheet.dart';
import 'calendar_package/event_list.dart';
import 'calendar_package/month_calendar_view.dart';
import 'calendar_package/completed_events_sheet.dart'; // ✅ 추가

class CompanyCalendarPage extends StatefulWidget {
  const CompanyCalendarPage({super.key});

  @override
  State<CompanyCalendarPage> createState() => _CompanyCalendarPageState();
}

class _CompanyCalendarPageState extends State<CompanyCalendarPage> {
  final _idCtrl = TextEditingController();
  static const _kLastCalendarIdKey = 'last_calendar_id';
  bool _autoTried = false;

  final PageController _pageController = PageController(initialPage: 0);
  int _viewIndex = 0; // 0: 캘린더, 1: 목록

  // 🔒 캘린더 ID 입력 보호(잠금) 토글 — 기본값: 잠금 활성화
  bool _idLocked = true;

  // ✅ FAB 살짝 올리기(px)
  static const double _fabLift = 24.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryAutoload());
  }

  @override
  void dispose() {
    _pageController.dispose();
    _idCtrl.dispose();
    super.dispose();
  }

  Future<void> _tryAutoload() async {
    if (_autoTried) return;
    _autoTried = true;
    final prefs = await SharedPreferences.getInstance();
    final lastId = prefs.getString(_kLastCalendarIdKey);
    if (lastId == null || lastId.trim().isEmpty) return;

    _idCtrl.text = lastId;
    final model = context.read<CalendarModel>();
    await model.load(newCalendarId: lastId);

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
        backgroundColor: Colors.white, // ✅ 흰 배경
        foregroundColor: Colors.black87, // ✅ 검은 글자/아이콘
        surfaceTintColor: Colors.white, // ✅ 머티리얼3 틴트도 흰색으로
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
        actions: [
          IconButton(
            tooltip: '완료된 이벤트 보기',
            icon: const Icon(Icons.done_all),
            onPressed: () => openCompletedEventsSheet(
              context: context,
              allEvents: model.events,
              onEdit: _openEditSheet, // 리스트 탭 시 수정 시트 열기(선택)
            ),
          ),
        ],
      ),

      // ✅ FAB를 하단 중앙으로 이동
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,

      // ✅ 확장형 FAB 적용 (살짝 위로 올림)
      floatingActionButton: _buildCreateFab(context),

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
                '캘린더 ID 또는 URL을 입력 후 불러오기를 누르세요. (예: someone@gmail.com)\n'
                    '좌우로 스와이프하면 캘린더 ↔ 목록 뷰를 전환합니다.',
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
                // ✅ 잠금/지우기 기능 포함한 입력 필드
                Expanded(
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _idCtrl,
                    builder: (context, value, _) {
                      return TextField(
                        controller: _idCtrl,
                        readOnly:
                        _idLocked, // 🔒 잠금 시 편집 불가(복사는 가능 / 길게 눌러 복사 가능)
                        decoration: InputDecoration(
                          labelText: '캘린더 ID 또는 URL',
                          hintText: '예: someone@gmail.com 또는 Google Calendar URL',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // 🔒 잠금 토글
                              IconButton(
                                tooltip: _idLocked ? '잠금 해제' : '잠금',
                                icon: Icon(
                                  _idLocked ? Icons.lock : Icons.lock_open,
                                ),
                                onPressed: () =>
                                    setState(() => _idLocked = !_idLocked),
                              ),
                              // ✕ 전체 지우기 (잠금 해제 + 내용 있을 때만 표시)
                              if (value.text.isNotEmpty && !_idLocked)
                                IconButton(
                                  tooltip: '지우기',
                                  icon: const Icon(Icons.clear),
                                  onPressed: () =>
                                      setState(() => _idCtrl.clear()),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: model.loading
                      ? null
                      : () async {
                    FocusScope.of(context).unfocus();
                    await context
                        .read<CalendarModel>()
                        .load(newCalendarId: _idCtrl.text);
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
                style:
                TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],

            const SizedBox(height: 8),

            // 본문: 좌우 스와이프 전환
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _viewIndex = i),
                children: [
                  // 0) 캘린더 뷰(기본)
                  MonthCalendarView(
                    allEvents: model.events,
                    progressOf: (e) => _extractProgress(e.description),
                    onEdit: _openEditSheet,
                    onDelete: _confirmDelete,
                    onToggleProgress: _toggleProgress,
                    onMonthRequested: (monthStart, monthEnd) async {
                      await context.read<CalendarModel>().loadRange(
                        timeMin: monthStart,
                        timeMax: monthEnd,
                      );
                    },
                  ),
                  // 1) 목록(Agenda)
                  EventList(
                    events: model.events,
                    onEdit: _openEditSheet,
                    onDelete: _confirmDelete,
                    onToggleProgress: _toggleProgress,
                    progressOf: (e) => _extractProgress(e.description),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// ✅ 하단 중앙 확장형 FAB (Transform으로 살짝 위로 올림)
  Widget _buildCreateFab(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -_fabLift),
      child: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: FloatingActionButton.extended(
          heroTag: 'createEventFab',
          tooltip: '새 이벤트 만들기',
          onPressed: () => _openCreateSheet(context),
          icon: const Icon(Icons.add),
          label: const Text('새 이벤트'),
          backgroundColor: Colors.white,
          foregroundColor: Colors.black87,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: Colors.black.withOpacity(0.08)),
          ),
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

    DateTime now = DateTime.now();
    if (_viewIndex == 0) {
      now = DateTime(now.year, now.month, now.day);
    }

    final created = await showEventEditorBottomSheet(
      context,
      title: '이벤트 생성',
      initialSummary: '',
      initialStart: now,
      initialEnd: now.add(const Duration(hours: 1)),
      initialProgress: 0,
    );
    if (created == null) return;

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
    final start = (e.start?.dateTime != null
        ? e.start!.dateTime!.toLocal()
        : e.start?.date) ??
        DateTime.now();
    final end = (e.end?.dateTime != null
        ? e.end!.dateTime!.toLocal()
        : e.end?.date) ??
        start.add(const Duration(hours: 1));
    final isAllDay = e.start?.date != null;

    final initialProgress = _extractProgress(e.description);

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

  Future<void> _toggleProgress(
      BuildContext context,
      gcal.Event e,
      bool done,
      ) async {
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
