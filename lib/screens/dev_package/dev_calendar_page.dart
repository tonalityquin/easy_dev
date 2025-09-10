// lib/screens/dev_package/dev_calendar_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:shared_preferences/shared_preferences.dart';

import 'dev_calendar_package/dev_calendar_model.dart';
import 'dev_calendar_package/dev_event_editor_bottom_sheet.dart';
import 'dev_calendar_package/dev_event_list.dart';
import 'dev_calendar_package/dev_month_calendar_view.dart';
import 'dev_calendar_package/dev_completed_events_sheet.dart';
import 'dev_calendar_package/dev_board_kanban_view.dart'; // ✅ 보드 뷰

// ────────────────────────────────────────────────────────────
// Dev Calendar 팔레트 (개발 카드와 동일 톤)
// base: #6A1B9A, dark: #4A148C, light: #CE93D8, fg: white
// ────────────────────────────────────────────────────────────
class _CalColors {
  static const base = Color(0xFF6A1B9A);
  static const dark = Color(0xFF4A148C);
  static const light = Color(0xFFCE93D8);
  static const fg = Color(0xFFFFFFFF);
}

class DevCalendarPage extends StatefulWidget {
  const DevCalendarPage({super.key});

  @override
  State<DevCalendarPage> createState() => _DevCalendarPageState();
}

class _DevCalendarPageState extends State<DevCalendarPage> {
  final _idCtrl = TextEditingController();

  // 🔑 dev 전용 키 (head와 충돌 방지)
  static const _kLastCalendarIdKey = 'dev_last_calendar_id';

  bool _autoTried = false;

  final PageController _pageController = PageController(initialPage: 0);
  int _viewIndex = 0; // 0: 캘린더, 1: 목록

  // 🔒 캘린더 ID 입력 보호(잠금) — 기본값 잠금
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
    final model = context.read<DevCalendarModel>();
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
  static final RegExp _progressTag = RegExp(r'\[\s*progress\s*:\s*(0|100)\s*\]', caseSensitive: false);

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
    final model = context.watch<DevCalendarModel>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('개발 달력'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        surfaceTintColor: Colors.white,
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
              onEdit: _openEditSheet,
            ),
          ),
        ],
      ),

      // ✅ 버튼 영역: 왼쪽 '보드' + 오른쪽 '새 이벤트' (두 버튼 디자인 통일)
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: _buildFabRow(context),

      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const _InfoBanner(),
            const SizedBox(height: 12),

            _CalendarIdSection(
              controller: _idCtrl,
              locked: _idLocked,
              loading: model.loading,
              onToggleLock: () => setState(() => _idLocked = !_idLocked),
              onClear: () => setState(() => _idCtrl.clear()),
              onLoad: () async {
                FocusScope.of(context).unfocus();
                await context.read<DevCalendarModel>().load(newCalendarId: _idCtrl.text);
                if (mounted && model.error == null && model.calendarId.isNotEmpty) {
                  _idCtrl.text = model.calendarId;
                  await _saveLastCalendarId(model.calendarId);
                }
              },
            ),
            const SizedBox(height: 12),

            if (model.loading) const LinearProgressIndicator(color: _CalColors.base),
            if (model.error != null) ...[
              const SizedBox(height: 8),
              Text(model.error!, style: const TextStyle(color: Colors.redAccent)),
            ],
            const SizedBox(height: 8),

            // 본문: 좌우 스와이프 (0: 캘린더, 1: 목록)
            Expanded(
              child: PageView(
                controller: _pageController,
                onPageChanged: (i) => setState(() => _viewIndex = i),
                children: [
                  // 0) 캘린더
                  DevMonthCalendarView(
                    allEvents: model.events,
                    progressOf: (e) => _extractProgress(e.description),
                    onEdit: _openEditSheet,
                    onDelete: _confirmDelete,
                    onToggleProgress: _toggleProgress,
                    onMonthRequested: (monthStart, monthEnd) async {
                      await context.read<DevCalendarModel>().loadRange(
                            timeMin: monthStart,
                            timeMax: monthEnd,
                          );
                    },
                  ),
                  // 1) 목록
                  DevEventList(
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

  /// ──────────────────────────────────────────────────────────
  /// 공통 pill 스타일 버튼 (Outlined)
  /// ──────────────────────────────────────────────────────────
  Widget _pillButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
  }) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 20),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        side: BorderSide(color: Colors.black.withOpacity(0.12)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
  }

  /// ✅ 버튼 Row: 왼쪽 '보드' + 오른쪽 '새 이벤트'
  /// 두 버튼 모두 _pillButton으로 디자인 통일
  Widget _buildFabRow(BuildContext context) {
    return Transform.translate(
      offset: const Offset(0, -_fabLift),
      child: SafeArea(
        minimum: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _pillButton(
              icon: Icons.view_kanban_rounded,
              label: '보드',
              onPressed: _openBoardSheet,
            ),
            const SizedBox(width: 8),
            _pillButton(
              icon: Icons.add,
              label: '새 이벤트',
              onPressed: () => _openCreateSheet(context),
            ),
          ],
        ),
      ),
    );
  }

  // DevCalendarPage 내에 이 함수만 바꿔 넣으세요.
  Future<void> _openBoardSheet() async {
    // ✅ 바텀시트/보드 내부 위젯 컨텍스트가 아니라,
    //    페이지의 컨텍스트를 캡처해서 Provider를 읽게 만든다.
    final pageContext = context;

    final model = pageContext.read<DevCalendarModel>();
    if (model.calendarId.isEmpty) {
      ScaffoldMessenger.of(pageContext).showSnackBar(
        const SnackBar(content: Text('먼저 캘린더를 불러오세요.')),
      );
      return;
    }

    await showModalBottomSheet<void>(
      context: pageContext,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetCtx) {
        return FractionallySizedBox(
          heightFactor: 0.92,
          child: _BoardSheetScaffold(
            child: DevBoardKanbanView(
              allEvents: model.events,
              progressOf: (e) => _extractProgress(e.description),

              // ✅ 보드의 내부 context(c)가 아니라 pageContext로 래핑
              onEdit: (c, e) => _openEditSheet(pageContext, e),
              onDelete: (c, e) => _confirmDelete(pageContext, e),
              onToggleProgress: (c, e, done) => _toggleProgress(pageContext, e, done),
              onMove: (c, e, bucket) => _moveToBucket(pageContext, e, bucket),

              initialPage: 0,
            ),
          ),
        );
      },
    );
  }

  Future<void> _openCreateSheet(BuildContext context) async {
    final model = context.read<DevCalendarModel>();
    if (model.calendarId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('먼저 캘린더를 불러오세요.')));
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
    final model = context.read<DevCalendarModel>();
    final start = (e.start?.dateTime != null ? e.start!.dateTime!.toLocal() : e.start?.date) ?? DateTime.now();
    final end =
        (e.end?.dateTime != null ? e.end!.dateTime!.toLocal() : e.end?.date) ?? start.add(const Duration(hours: 1));
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
      isEditMode: true,
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
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('취소')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('삭제')),
        ],
      ),
    );
    if (ok == true) {
      await context.read<DevCalendarModel>().delete(eventId: e.id!);
    }
  }

  Future<void> _toggleProgress(BuildContext context, gcal.Event e, bool done) async {
    final model = context.read<DevCalendarModel>();

    final start = (e.start?.dateTime != null ? e.start!.dateTime!.toLocal() : e.start?.date) ?? DateTime.now();
    final end =
        (e.end?.dateTime != null ? e.end!.dateTime!.toLocal() : e.end?.date) ?? start.add(const Duration(hours: 1));
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

  /// ✅ 드래그/메뉴 이동 시 날짜/진행도 보정
  Future<void> _moveToBucket(BuildContext context, gcal.Event e, BoardBucket target) async {
    final model = context.read<DevCalendarModel>();

    final now = DateTime.now();
    final start0 = (e.start?.dateTime != null ? e.start!.dateTime!.toLocal() : e.start?.date) ?? now;
    final end0 = (e.end?.dateTime != null ? e.end!.dateTime!.toLocal() : e.end?.date) ??
        (e.start?.dateTime != null ? start0.add(const Duration(hours: 1)) : start0.add(const Duration(days: 1)));
    final isAllDay = e.start?.date != null;
    final dur = end0.difference(start0);

    DateTime _roundUp30(DateTime t) {
      final add = (t.minute % 30 == 0) ? 0 : (30 - (t.minute % 30));
      final base = DateTime(t.year, t.month, t.day, t.hour, t.minute);
      return base.add(Duration(minutes: add));
    }

    DateTime nextWeekday(DateTime t) {
      final wd = t.weekday; // 월=1, ... 일=7
      final add = (wd >= 5) ? (8 - wd) : 1; // 금/토/일이면 다음 월, 아니면 +1일
      return DateTime(t.year, t.month, t.day).add(Duration(days: add));
    }

    DateTime nextMonday(DateTime t) {
      final wd = t.weekday; // 월=1
      final add = (8 - wd) % 7;
      final d = DateTime(t.year, t.month, t.day).add(Duration(days: add == 0 ? 7 : add));
      return d;
    }

    DateTime newStart;
    DateTime newEnd;
    int newProgress;

    switch (target) {
      case BoardBucket.done:
        newStart = start0;
        newEnd = end0;
        newProgress = 100;
        break;

      case BoardBucket.today:
        if (isAllDay) {
          final d0 = DateTime(now.year, now.month, now.day);
          newStart = d0;
          newEnd = d0.add(dur.inDays > 0 ? Duration(days: dur.inDays) : const Duration(days: 1));
        } else {
          final base = _roundUp30(now).add(const Duration(minutes: 30));
          newStart = DateTime(base.year, base.month, base.day, base.hour, base.minute);
          newEnd = newStart.add(dur.inMinutes > 0 ? dur : const Duration(hours: 1));
        }
        newProgress = 0;
        break;

      case BoardBucket.thisWeek:
        if (isAllDay) {
          final d = nextWeekday(now);
          newStart = DateTime(d.year, d.month, d.day);
          newEnd = newStart.add(dur.inDays > 0 ? Duration(days: dur.inDays) : const Duration(days: 1));
        } else {
          final d = nextWeekday(now);
          newStart = DateTime(d.year, d.month, d.day, 10, 0);
          newEnd = newStart.add(dur.inMinutes > 0 ? dur : const Duration(hours: 1));
        }
        newProgress = 0;
        break;

      case BoardBucket.later:
        if (isAllDay) {
          final d = nextMonday(now);
          newStart = DateTime(d.year, d.month, d.day);
          newEnd = newStart.add(dur.inDays > 0 ? Duration(days: dur.inDays) : const Duration(days: 1));
        } else {
          final d = nextMonday(now);
          newStart = DateTime(d.year, d.month, d.day, 9, 0);
          newEnd = newStart.add(dur.inMinutes > 0 ? dur : const Duration(hours: 1));
        }
        newProgress = 0;
        break;
    }

    final newDesc = _setProgressTag(e.description, newProgress);

    await model.update(
      eventId: e.id!,
      summary: e.summary ?? '',
      description: newDesc,
      start: newStart,
      end: newEnd,
      allDay: isAllDay,
      colorId: e.colorId,
    );
  }
}

// ===== 바텀시트용 보드 래퍼(상단 핸들/닫기 버튼 포함) =====
class _BoardSheetScaffold extends StatelessWidget {
  const _BoardSheetScaffold({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Material(
          elevation: 2,
          clipBehavior: Clip.antiAlias,
          borderRadius: BorderRadius.circular(16),
          color: Colors.white,
          child: Column(
            children: [
              const SizedBox(height: 8),
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                dense: true,
                title: const Text('보드', style: TextStyle(fontWeight: FontWeight.w800)),
                trailing: IconButton(
                  tooltip: '닫기',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              const Divider(height: 1),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== 디자인 리팩토링 보조 위젯 =====

class _InfoBanner extends StatelessWidget {
  const _InfoBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _CalColors.light.withOpacity(.95),
            _CalColors.base.withOpacity(.85),
          ],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _CalColors.dark.withOpacity(.18)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, color: _CalColors.fg, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '캘린더 ID 또는 URL을 입력 후 불러오기를 누르세요. (예: someone@gmail.com)\n'
              '좌우 스와이프: 캘린더 ↔ 목록,  하단 좌측 "보드" 버튼: 칸반 보드(스와이프로 컬럼 전환).',
              style: TextStyle(
                color: _CalColors.fg,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CalendarIdSection extends StatelessWidget {
  const _CalendarIdSection({
    required this.controller,
    required this.locked,
    required this.loading,
    required this.onToggleLock,
    required this.onClear,
    required this.onLoad,
  });

  final TextEditingController controller;
  final bool locked;
  final bool loading;
  final VoidCallback onToggleLock;
  final VoidCallback onClear;
  final Future<void> Function() onLoad;

  @override
  Widget build(BuildContext context) {
    final btn = FilledButton.icon(
      style: FilledButton.styleFrom(
        backgroundColor: _CalColors.base,
        foregroundColor: _CalColors.fg,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onPressed: loading ? null : onLoad,
      icon: loading
          ? const SizedBox(
              width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: _CalColors.fg))
          : const Icon(Icons.download_rounded),
      label: const Text('불러오기'),
    );

    return LayoutBuilder(
      builder: (context, cons) {
        final narrow = cons.maxWidth < 560;

        final field = ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            return TextField(
              controller: controller,
              readOnly: locked,
              decoration: InputDecoration(
                labelText: '캘린더 ID 또는 URL',
                hintText: '예: someone@gmail.com 또는 Google Calendar URL',
                prefixIcon: const Icon(Icons.link_rounded, color: _CalColors.base),
                filled: true,
                fillColor: _CalColors.light.withOpacity(.20),
                isDense: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _CalColors.base.withOpacity(.25)),
                ),
                focusedBorder: const OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                  borderSide: BorderSide(color: _CalColors.base, width: 1.2),
                ),
                suffixIcon: SizedBox(
                  width: locked ? 48 : 96,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: locked ? '잠금 해제' : '잠금',
                        onPressed: onToggleLock,
                        icon: Icon(locked ? Icons.lock : Icons.lock_open, color: _CalColors.dark),
                        iconSize: 20,
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                      ),
                      if (value.text.isNotEmpty && !locked)
                        IconButton(
                          tooltip: '지우기',
                          onPressed: onClear,
                          icon: const Icon(Icons.clear, color: _CalColors.dark),
                          iconSize: 20,
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );

        if (narrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: btn),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: field),
            const SizedBox(width: 10),
            btn,
          ],
        );
      },
    );
  }
}
