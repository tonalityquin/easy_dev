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
import 'calendar_package/completed_events_sheet.dart'; // ✅ 완료 목록 바텀시트
import 'calendar_package/board_kanban_view.dart'; // ✅ 보드(오늘/이번주/나중에/완료) 페이지

// ────────────────────────────────────────────────────────────
// Company Calendar 팔레트(카드와 동일한 톤)
// base: #43A047, dark: #2E7D32, light: #A5D6A7, fg: white
// ────────────────────────────────────────────────────────────
class _CalColors {
  static const base = Color(0xFF43A047);
  static const dark = Color(0xFF2E7D32);
  static const light = Color(0xFFA5D6A7);
  static const fg = Color(0xFFFFFFFF);
}

///
/// 회사 달력 페이지
/// - asBottomSheet=true 로 표시하면 “핸드폰 최상단까지 올라오는” 전체 화면 바텀시트 형태로 렌더링됩니다.
/// - [CompanyCalendarPage.showAsBottomSheet] 헬퍼로 간편 호출 가능.
///
class CompanyCalendarPage extends StatefulWidget {
  const CompanyCalendarPage({
    super.key,
    this.asBottomSheet = false,
  });

  /// true 이면 Scaffold AppBar 대신 시트 헤더(핸들/닫기 버튼)를 사용하고,
  /// 바닥에 FAB Row를 고정한 전체 높이 바텀시트 UI로 렌더링합니다.
  final bool asBottomSheet;

  /// 전체 화면 바텀시트로 열기(권장)
  static Future<T?> showAsBottomSheet<T>(BuildContext context) {
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,           // ⬅️ 키보드/전체 높이 제어
      useSafeArea: true,                  // ⬅️ 노치/상단 안전영역 고려
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black54,
      builder: (sheetCtx) {
        // 키보드가 올라올 때를 대비하여 viewInsets 반영
        final insets = MediaQuery.of(sheetCtx).viewInsets;
        return Padding(
          padding: EdgeInsets.only(bottom: insets.bottom),
          child: const _FullHeightBottomSheetFrame(
            child: CompanyCalendarPage(asBottomSheet: true),
          ),
        );
      },
    );
  }

  @override
  State<CompanyCalendarPage> createState() => _CompanyCalendarPageState();
}

class _CompanyCalendarPageState extends State<CompanyCalendarPage> {
  final _idCtrl = TextEditingController();
  static const _kLastCalendarIdKey = 'company_last_calendar_id';
  bool _autoTried = false;

  final PageController _pageController = PageController(initialPage: 0);
  int _viewIndex = 0; // 0: 캘린더, 1: 목록, 2: 보드

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
    final model = context.watch<CalendarModel>();

    final Widget pageBody = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // 안내 배너 (리팩토링 + 팔레트 적용)
          const _InfoBanner(),
          const SizedBox(height: 12),

          // 입력 + 버튼 (리팩토링 + 팔레트 적용)
          _CalendarIdSection(
            controller: _idCtrl,
            locked: _idLocked,
            loading: model.loading,
            onToggleLock: () => setState(() => _idLocked = !_idLocked),
            onClear: () => setState(() => _idCtrl.clear() ),
            onLoad: () async {
              FocusScope.of(context).unfocus();
              await context.read<CalendarModel>().load(newCalendarId: _idCtrl.text);
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
            Text(
              model.error!,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],

          const SizedBox(height: 8),

          // 본문: 좌우 스와이프 전환 (보드 페이지도 유지)
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
                // 2) 보드(오늘/이번주/나중에/완료) — 페이지에서도 사용 가능(유지)
                BoardKanbanView(
                  allEvents: model.events,
                  progressOf: (e) => _extractProgress(e.description),
                  onToggleProgress: _toggleProgress,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // ✅ asBottomSheet 여부에 따라 서로 다른 스캐폴드로 감싼다.
    if (!widget.asBottomSheet) {
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

        // ✅ Dev와 동일: 왼쪽 '보드', 오른쪽 '새 이벤트' (두 버튼 통일 디자인)
        floatingActionButton: _buildFabRow(context),

        body: pageBody,
      );
    }

    // ====== 전체 화면 바텀시트 모드 ======
    return _SheetScaffold(
      title: '회사 달력',
      onClose: () => Navigator.of(context).maybePop(),
      trailingActions: [
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
      body: pageBody,
      fab: _buildFabRow(context),
      fabLift: _fabLift,
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

  /// ✅ Dev와 동일한 FAB Row: 왼쪽 '보드' + 오른쪽 '새 이벤트'
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

  /// ✅ Dev와 동일: 보드 바텀시트 오픈 (회사용 BoardKanbanView 사용)
  Future<void> _openBoardSheet() async {
    final pageContext = context; // Provider 읽을 상위 컨텍스트 고정

    final model = pageContext.read<CalendarModel>();
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
            child: BoardKanbanView(
              allEvents: model.events,
              progressOf: (e) => _extractProgress(e.description),
              // ✅ 내부 위젯 context가 아닌 pageContext로 토글 로직 연결
              onToggleProgress: (c, e, done) => _toggleProgress(pageContext, e, done),
            ),
          ),
        );
      },
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
      isEditMode: true, // ✅ 편집 모드: 탭 전환에도 원본 미리보기 유지
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

  Future<void> _toggleProgress(
      BuildContext context,
      gcal.Event e,
      bool done,
      ) async {
    final model = context.read<CalendarModel>();

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
}

// ===== “전체 화면” 바텀시트 프레임 =====
// - showModalBottomSheet 의 builder에서 바로 사용.
// - 상/하 SafeArea, 둥근 모서리, 배경 투명 + 그림자 포함.
class _FullHeightBottomSheetFrame extends StatelessWidget {
  const _FullHeightBottomSheetFrame({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 1.0, // ⬅️ 최상단까지
      widthFactor: 1.0,
      child: SafeArea(
        // 상단까지 차오르되 노치/상태바는 피함
        top: true,
        bottom: true,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          child: DecoratedBox(
            decoration: const BoxDecoration(boxShadow: [
              BoxShadow(
                blurRadius: 24,
                spreadRadius: 8,
                color: Color(0x33000000),
                offset: Offset(0, 8),
              ),
            ]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Material(
                color: Colors.white,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ===== 바텀시트용 “페이지” 스캐폴드 =====
// - AppBar 대체(핸들 + 타이틀 + 닫기 버튼)
// - body + 하단 FAB Row(중앙 부근 떠 있는 버튼들)
class _SheetScaffold extends StatelessWidget {
  const _SheetScaffold({
    required this.title,
    required this.onClose,
    required this.body,
    this.trailingActions,
    this.fab,
    this.fabLift = 24.0,
  });

  final String title;
  final VoidCallback onClose;
  final List<Widget>? trailingActions;
  final Widget body;
  final Widget? fab;
  final double fabLift;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // 본문
        Column(
          children: [
            const SizedBox(height: 8),
            // 상단 핸들
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            // 헤더(타이틀/닫기)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (trailingActions != null) ...trailingActions!,
                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // 본문 스크롤
            Expanded(child: body),
            const SizedBox(height: 64), // FAB Row 공간 확보
          ],
        ),

        // FAB Row (하단 중앙)
        if (fab != null)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: false,
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Transform.translate(
                  offset: Offset(0, -fabLift),
                  child: fab!,
                ),
              ),
            ),
          ),
      ],
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Icon(Icons.info_outline_rounded, color: _CalColors.fg, size: 22),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              '이벤트 완료는 보드에서,\n이벤트 수정 및 삭제와 상세 보기는 목록에서',
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
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: _CalColors.fg),
      )
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
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _CalColors.base, width: 1.2),
                ),
                suffixIcon: SizedBox(
                  // 잠금만 있을 때는 48, 두 아이콘이면 96으로 자동 조정
                  width: locked ? 48 : 96,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: locked ? '잠금 해제' : '잠금',
                        onPressed: onToggleLock,
                        icon: Icon(locked ? Icons.lock : Icons.lock_open, color: _CalColors.dark),
                        // ▼ 기본 48→40으로 컴팩트
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
