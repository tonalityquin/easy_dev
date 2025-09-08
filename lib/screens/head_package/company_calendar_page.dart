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

  // === 뷰 전환(PageView) ===
  // ✅ 0: 캘린더, 1: 목록(Agenda) 로 변경
  final PageController _pageController = PageController(initialPage: 0);
  int _viewIndex = 0; // 0: 캘린더, 1: 목록(Agenda)

  @override
  void initState() {
    super.initState();
    // Provider가 빌드된 뒤에 자동 로드 시도
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
        actions: [
          // 현재 뷰 표시/전환 버튼
          IconButton(
            tooltip: _viewIndex == 0 ? '목록 보기' : '캘린더 보기',
            icon: Icon(_viewIndex == 0 ? Icons.view_list : Icons.calendar_month),
            onPressed: () {
              final next = _viewIndex == 0 ? 1 : 0;
              _pageController.animateToPage(
                next,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            },
          ),
        ],
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
                '캘린더 ID 또는 URL을 입력 후 불러오기를 누르세요. (예: someone@gmail.com)\n'
                    '좌우로 스와이프하면 목록 ↔ 캘린더 뷰를 전환합니다.',
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

            // === 본문: 좌우 스와이프 전환 ===
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _viewIndex = i),
                children: [
                  // ✅ 0) 캘린더 뷰 (기본)
                  _MonthCalendarView(
                    allEvents: model.events,
                    progressOf: (e) => _extractProgress(e.description),
                    onEdit: _openEditSheet,
                    onDelete: _confirmDelete,
                    onToggleProgress: _toggleProgress,
                    // 보이는 월 범위가 바뀔 때마다 해당 월 데이터를 로드
                    onMonthRequested: (monthStart, monthEnd) async {
                      await context.read<CalendarModel>().loadRange(
                        timeMin: monthStart,
                        timeMax: monthEnd,
                      );
                    },
                  ),

                  // ✅ 1) 목록(Agenda)
                  _EventList(
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

  Future<void> _openCreateSheet(BuildContext context) async {
    final model = context.read<CalendarModel>();
    if (model.calendarId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 캘린더를 불러오세요.')),
      );
      return;
    }

    // 현재 뷰에 따라 기본 시작/종료 설정
    DateTime now = DateTime.now();
    // ✅ 캘린더 뷰(0)일 때 자정 기준으로 생성 시작
    if (_viewIndex == 0) {
      now = DateTime(now.year, now.month, now.day);
    }

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
    final descWithProgress = _setProgressTag(created.description, created.progress);

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

    final descWithProgress = _setProgressTag(edited.description, edited.progress);

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

// =====================
// 목록(Agenda) 리스트
// =====================
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
            ? (isAllDay
            ? fmtDate.format(startLocal)
            : fmtDateTime.format(startLocal))
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

// =====================
// 캘린더(월) — 진행도 색상 dot/숫자 + 날짜 탭 시 읽기 전용 BottomSheet
// =====================
class _MonthCalendarView extends StatefulWidget {
  const _MonthCalendarView({
    required this.allEvents,
    required this.progressOf,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleProgress,
    this.onMonthRequested, // 보이는 월 범위를 부모에 요청
  });

  final List<gcal.Event> allEvents;
  final int Function(gcal.Event) progressOf;
  final void Function(BuildContext, gcal.Event) onEdit; // (읽기 전용 시트에서는 사용 안 함)
  final void Function(BuildContext, gcal.Event) onDelete; // (읽기 전용 시트에서는 사용 안 함)
  final Future<void> Function(BuildContext, gcal.Event, bool)
  onToggleProgress; // (읽기 전용 시트에서는 사용 안 함)

  // 현재 보이는 월의 [월초, 다음 달 1일) 범위 로드를 부모에 요청
  final Future<void> Function(DateTime monthStart, DateTime monthEnd)?
  onMonthRequested;

  @override
  State<_MonthCalendarView> createState() => _MonthCalendarViewState();
}

class _MonthCalendarViewState extends State<_MonthCalendarView> {
  late DateTime _visibleMonth; // 해당 월의 1일
  DateTime? _selectedDay; // 탭 하이라이트

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _visibleMonth = DateTime(now.year, now.month, 1);

    // 첫 빌드 직후 현재 보이는 달 범위 로드 요청
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _notifyMonthRequested());
  }

  void _notifyMonthRequested() {
    if (widget.onMonthRequested == null) return;
    final start = DateTime(_visibleMonth.year, _visibleMonth.month, 1);
    final end = DateTime(start.year, start.month + 1, 1); // 다음 달 1일(Exclusive)
    widget.onMonthRequested!(start, end);
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // month grid에 채워 넣을 날짜 42칸(6주)
  List<DateTime> _daysInGrid(DateTime month) {
    final first = DateTime(month.year, month.month, 1);
    final weekday = first.weekday % 7; // Sun=0, Mon=1,... (Flutter는 Mon=1~Sun=7)
    final start = first.subtract(Duration(days: weekday)); // 그리드 시작(일요일)
    return List.generate(42, (i) => DateTime(start.year, start.month, start.day + i));
  }

  DateTime? _eventStartLocal(gcal.Event e) {
    final dt = e.start?.dateTime?.toLocal();
    final d = e.start?.date;
    return dt ?? d;
  }

  bool _eventOccursOn(gcal.Event e, DateTime day) {
    // 종일 이벤트: [start.date, end.date) 구간
    if (e.start?.date != null && e.end?.date != null) {
      final s = DateTime(e.start!.date!.year, e.start!.date!.month, e.start!.date!.day);
      final ed = DateTime(e.end!.date!.year, e.end!.date!.month, e.end!.date!.day);
      return !day.isBefore(s) && day.isBefore(ed);
    }
    // 시간 이벤트: 시작~끝 사이 날짜 포함
    final start = e.start?.dateTime?.toLocal();
    final end = e.end?.dateTime?.toLocal();
    if (start != null) {
      final sd = DateTime(start.year, start.month, start.day);
      if (_isSameDay(sd, day)) return true;
      if (end != null) {
        final ed = DateTime(end.year, end.month, end.day);
        return !day.isBefore(sd) && !day.isAfter(ed);
      }
    }
    return false;
  }

  List<gcal.Event> _eventsOnDay(DateTime day) {
    final list = widget.allEvents.where((e) => _eventOccursOn(e, day)).toList();

    // 시작 시간 기준 정렬 (종일/시간제)
    list.sort((a, b) {
      final sa = _eventStartLocal(a) ?? DateTime(1900);
      final sb = _eventStartLocal(b) ?? DateTime(1900);
      return sa.compareTo(sb);
    });

    return list;
  }

  int _eventCountOnDay(DateTime day) => _eventsOnDay(day).length;

  Future<void> _openDaySheet(BuildContext context, DateTime day) async {
    final events = _eventsOnDay(day);
    final fmtDay = DateFormat('yyyy-MM-dd (EEE)');
    final fmtTime = DateFormat('HH:mm');

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      builder: (_) {
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, controller) {
            return Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12, borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            fmtDay.format(day),
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: events.isEmpty
                        ? const Center(child: Text('이 날짜에 이벤트가 없습니다.'))
                        : ListView.separated(
                      controller: controller,
                      itemCount: events.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final e = events[i];
                        final isAllDay = (e.start?.date != null) && (e.start?.dateTime == null);
                        String whenText;
                        if (isAllDay) {
                          whenText = '종일';
                        } else {
                          final st = e.start?.dateTime?.toLocal();
                          final ed = e.end?.dateTime?.toLocal();
                          if (st != null && ed != null) {
                            whenText = '${fmtTime.format(st)} ~ ${fmtTime.format(ed)}';
                          } else if (st != null) {
                            whenText = fmtTime.format(st);
                          } else {
                            whenText = '(시간 미정)';
                          }
                        }
                        final done = widget.progressOf(e) == 100;

                        return ListTile(
                          leading: done
                              ? const Icon(Icons.check_circle, size: 20)
                              : const Icon(Icons.radio_button_unchecked, size: 20),
                          title: Text(
                            e.summary ?? '(제목 없음)',
                            style: done
                                ? const TextStyle(decoration: TextDecoration.lineThrough)
                                : null,
                          ),
                          subtitle: Text(whenText),
                          // 읽기 전용: onTap 없음 / 편집/삭제/토글 X
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final days = _daysInGrid(_visibleMonth);
    final monthLabel = DateFormat('yyyy년 M월').format(_visibleMonth);
    final isLight = Theme.of(context).brightness == Brightness.light;

    return Column(
      children: [
        // ==== 월 헤더 ====
        Row(
          children: [
            IconButton(
              tooltip: '이전 달',
              icon: const Icon(Icons.chevron_left),
              onPressed: () {
                setState(() {
                  _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month - 1, 1);
                });
                _notifyMonthRequested(); // 월 변경 시 로드 요청
              },
            ),
            Expanded(
              child: Center(
                child: Text(
                  monthLabel,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
            IconButton(
              tooltip: '다음 달',
              icon: const Icon(Icons.chevron_right),
              onPressed: () {
                setState(() {
                  _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + 1, 1);
                });
                _notifyMonthRequested(); // 월 변경 시 로드 요청
              },
            ),
          ],
        ),
        const SizedBox(height: 4),

        // ==== 요일 헤더 ====
        Row(
          children: const [
            _DowCell('일'),
            _DowCell('월'),
            _DowCell('화'),
            _DowCell('수'),
            _DowCell('목'),
            _DowCell('금'),
            _DowCell('토'),
          ],
        ),
        const SizedBox(height: 4),

        // ==== 월 그리드 ====
        AspectRatio(
          aspectRatio: 7 / 6, // 7열 6행
          child: GridView.builder(
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.zero,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
            ),
            itemCount: days.length,
            itemBuilder: (context, i) {
              final d = days[i];
              final inMonth = d.month == _visibleMonth.month;
              final isToday = _isSameDay(d, DateTime.now());
              final isSelected = _selectedDay != null && _isSameDay(d, _selectedDay!);

              // 해당 날짜의 이벤트 및 개수
              final eventsOfDay = _eventsOnDay(d);
              final cnt = eventsOfDay.length;

              final bg = isSelected
                  ? Theme.of(context).colorScheme.primary.withOpacity(isLight ? .12 : .22)
                  : Colors.transparent;

              final fg = inMonth
                  ? (isSelected ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface)
                  : Colors.grey;

              return InkWell(
                onTap: () {
                  setState(() => _selectedDay = d);
                  _openDaySheet(context, d); // 날짜 탭 → 읽기 전용 BottomSheet
                },
                child: Container(
                  margin: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: bg,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Stack(
                    children: [
                      // 날짜 + 오늘 점 (좌측 상단)
                      Positioned(
                        top: 4,
                        left: 6,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('${d.day}', style: TextStyle(fontSize: 12, color: fg)),
                            if (isToday)
                              Padding(
                                padding: const EdgeInsets.only(left: 4),
                                child: Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),

                      // 진행도에 따른 dot 표시 (우측 하단)
                      if (cnt > 0)
                        Positioned(
                          right: 6,
                          bottom: 4,
                          child: Row(
                            children: [
                              ...eventsOfDay.take(3).map((e) {
                                final p = widget.progressOf(e);
                                final color = (p == 100) ? Colors.red : Colors.black;
                                return Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: color,
                                    ),
                                  ),
                                );
                              }),
                              if (cnt > 3)
                                Padding(
                                  padding: const EdgeInsets.only(left: 4),
                                  child: Text(
                                    '+${cnt - 3}',
                                    style: TextStyle(
                                      fontSize: 9,
                                      height: 1.0,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurface
                                          .withOpacity(0.6),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // 선택일 하단 목록/텍스트는 제거 (요구사항: bottomSheet로 열람)
      ],
    );
  }
}

class _DowCell extends StatelessWidget {
  const _DowCell(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    final isSun = label == '일';
    final isSat = label == '토';
    final color = isSun
        ? Colors.redAccent
        : (isSat ? Colors.blueAccent : Theme.of(context).colorScheme.onSurface.withOpacity(.7));
    return Expanded(
      child: Center(
        child: Text(label, style: TextStyle(fontSize: 12, color: color)),
      ),
    );
  }
}
