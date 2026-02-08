// lib/screens/head_package/calendar_package/event_editor_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

@immutable
class _EditorTokens {
  const _EditorTokens({
    required this.accent,
    required this.onAccent,
    required this.accentContainer,
    required this.onAccentContainer,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.divider,
    required this.scrim,
    required this.handle,
    required this.fieldFill,
    required this.fieldBorder,
    required this.cardTint,
  });

  final Color accent;
  final Color onAccent;

  final Color accentContainer;
  final Color onAccentContainer;

  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;

  final Color divider;
  final Color scrim;
  final Color handle;

  final Color fieldFill;
  final Color fieldBorder;

  final Color cardTint;

  factory _EditorTokens.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final accent = cs.primary;

    return _EditorTokens(
      accent: accent,
      onAccent: cs.onPrimary,
      accentContainer: cs.primaryContainer,
      onAccentContainer: cs.onPrimaryContainer,
      surface: cs.surface,
      onSurface: cs.onSurface,
      onSurfaceVariant: cs.onSurfaceVariant,
      divider: cs.outlineVariant,
      scrim: cs.scrim,
      handle: cs.onSurfaceVariant.withOpacity(0.42),
      fieldFill: Color.alphaBlend(accent.withOpacity(0.10), cs.surface),
      fieldBorder: cs.outlineVariant.withOpacity(0.75),
      cardTint: Color.alphaBlend(accent.withOpacity(0.08), cs.surface),
    );
  }
}

/// ✅ 하단 고정 버튼바 높이(대략치) + 여유를 위한 예약 값
const double _kEditorBottomActionBarReserve = 96.0;

/// 호출 헬퍼
Future<EditResult?> showEventEditorBottomSheet(
    BuildContext context, {
      required String title,
      required String initialSummary,
      required DateTime initialStart,
      required DateTime initialEnd,
      String initialDescription = '',
      bool initialAllDay = true, // 항상 종일 (시그니처 유지)
      String? initialColorId,
      int initialProgress = 0, // 0 또는 100
      bool isEditMode = false, // 편집 모드
      List<EventTemplate>? templates, // 동적 템플릿
    }) {
  final t = _EditorTokens.of(context);

  return showModalBottomSheet<EditResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: t.scrim.withOpacity(0.60),
    builder: (_) => EventEditorBottomSheet(
      title: title,
      initialSummary: initialSummary,
      initialStart: initialStart,
      initialEnd: initialEnd,
      initialDescription: initialDescription,
      initialAllDay: initialAllDay,
      initialColorId: initialColorId,
      initialProgress: initialProgress,
      isEditMode: isEditMode,
      templates: templates,
    ),
  );
}

/// 바텀시트 본체
class EventEditorBottomSheet extends StatefulWidget {
  const EventEditorBottomSheet({
    super.key,
    required this.title,
    required this.initialSummary,
    required this.initialStart,
    required this.initialEnd,
    this.initialDescription = '',
    this.initialAllDay = true,
    this.initialColorId,
    this.initialProgress = 0,
    this.isEditMode = false,
    this.templates,
  });

  final String title;
  final String initialSummary;
  final String initialDescription;
  final DateTime initialStart;
  final DateTime initialEnd;
  final bool initialAllDay;
  final String? initialColorId;
  final int initialProgress;
  final bool isEditMode;
  final List<EventTemplate>? templates;

  @override
  State<EventEditorBottomSheet> createState() => _EventEditorBottomSheetState();
}

class _EventEditorBottomSheetState extends State<EventEditorBottomSheet>
    with SingleTickerProviderStateMixin {
  late final TextEditingController _summary;
  late final TextEditingController _desc;

  late DateTime _start;
  late DateTime _end;
  static const bool _allDay = true;

  String? _colorId;
  late int _progress;

  late final List<EventTemplate> _templates;
  late final TabController _tabController;

  late final PageController _tabsPageController;
  int _headerPage = 0;

  int get _currentTabIndex => _tabController.index;
  int get _currentPage => _currentTabIndex ~/ 2;
  int get _pageCount => (_templates.length + 1) ~/ 2;

  static const Map<String, Color> _eventColors = {
    "1": Color(0xFF7986CB),
    "2": Color(0xFF33B679),
    "3": Color(0xFF8E24AA),
    "4": Color(0xFFE67C73),
    "5": Color(0xFFF6BF26),
    "6": Color(0xFFF4511E),
    "7": Color(0xFF039BE5),
    "8": Color(0xFF616161),
    "9": Color(0xFF3F51B5),
    "10": Color(0xFF0B8043),
    "11": Color(0xFFD50000),
  };

  DateTime _toLocalDateOnly(DateTime dt) {
    final l = dt.toLocal();
    return DateTime(l.year, l.month, l.day);
  }

  @override
  void initState() {
    super.initState();

    _summary = TextEditingController(text: widget.initialSummary);
    _desc = TextEditingController(text: widget.initialDescription);

    _start = _toLocalDateOnly(widget.initialStart);
    _end = _toLocalDateOnly(widget.initialEnd);
    if (!_end.isAfter(_start)) _end = _start.add(const Duration(days: 1));

    _colorId = widget.initialColorId;
    _progress = (widget.initialProgress == 100) ? 100 : 0;

    _templates = widget.templates ??
        [
          ApplyTemplate(),
          HireTemplate(),
          CheckInTemplate(),
          FreeTemplate(
            initialTitle: widget.initialSummary,
            initialBody: widget.initialDescription,
          ),
        ];

    int initialIndex;
    if (widget.isEditMode) {
      initialIndex = _templates.indexWhere((t) => t.id == 'free');
      if (initialIndex < 0) initialIndex = 0;
    } else {
      final s = widget.initialSummary;
      int idx = -1;
      if (s.contains('입사')) {
        idx = _templates.indexWhere((t) => t.id == 'hire');
      } else if (s.contains('지원')) {
        idx = _templates.indexWhere((t) => t.id == 'apply');
      } else if (s.contains('출근')) {
        idx = _templates.indexWhere((t) => t.id == 'checkin');
      } else {
        idx = _templates.indexWhere((t) => t.id == 'free');
      }
      initialIndex = idx >= 0 ? idx : 0;
    }

    _tabController = TabController(
      length: _templates.length,
      vsync: this,
      initialIndex: initialIndex.clamp(0, _templates.length - 1),
    );

    _headerPage = _currentPage;
    _tabsPageController = PageController(initialPage: _headerPage);

    _tabController.addListener(() {
      if (!mounted) return;

      final page = _currentPage;
      if (_tabsPageController.hasClients) {
        final current =
            _tabsPageController.page?.round() ?? _tabsPageController.initialPage;
        if (current != page) {
          _tabsPageController.animateToPage(
            page,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
      if (_headerPage != page) setState(() => _headerPage = page);

      if (!widget.isEditMode) {
        _rebuildTemplate();
      } else {
        setState(() {});
      }
    });

    if (!widget.isEditMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildTemplate());
    }
  }

  @override
  void dispose() {
    _summary.dispose();
    _desc.dispose();
    _tabController.dispose();
    _tabsPageController.dispose();
    for (final t in _templates) {
      t.dispose();
    }
    super.dispose();
  }

  void _rebuildTemplate() {
    final idx = _tabController.index;
    if (idx >= 0 && idx < _templates.length) {
      _templates[idx].computePreview(_summary, _desc);
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _EditorTokens.of(context);
    final viewInsets = MediaQuery.of(context).viewInsets;
    final fmtDate = DateFormat('yyyy-MM-dd');

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 1.0,
          minChildSize: 0.5,
          maxChildSize: 1.0,
          builder: (context, scrollController) {
            final tt = _EditorTokens.of(context);

            return Container(
              decoration: BoxDecoration(
                color: tt.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: tt.handle,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // 헤더
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: tt.onSurface,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '닫기',
                          icon: Icon(Icons.close_rounded, color: tt.onSurface),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),

                  // ===== 상단 고정 영역 =====
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.isEditMode) ...[
                          Text(
                            '원본 내용',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: tt.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _ReadOnlyCard(
                            summary: widget.initialSummary,
                            description: widget.initialDescription,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          widget.isEditMode ? '새 내용 미리보기' : '미리보기',
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: tt.onSurface,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 8),

                        // ✅ 미리보기 필드들도 테마 필 적용
                        _PreviewField(
                          label: '제목',
                          controller: _summary,
                        ),
                        const SizedBox(height: 8),
                        _PreviewField(
                          label: '설명',
                          controller: _desc,
                          minLines: 3,
                          maxLines: 6,
                        ),
                      ],
                    ),
                  ),
                  Divider(height: 1, color: tt.divider),

                  // ===== 스크롤 영역 =====
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        16 + _kEditorBottomActionBarReserve,
                      ),
                      children: [
                        // 날짜(종일)
                        Row(
                          children: [
                            Expanded(
                              child: _DateField(
                                label: '시작 날짜',
                                valueText: fmtDate.format(_start),
                                onPick: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _start,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                    builder: (ctx, child) {
                                      final th = Theme.of(ctx);
                                      return Theme(
                                        data: th.copyWith(
                                          colorScheme: th.colorScheme.copyWith(
                                            primary: t.accent,
                                            onPrimary: t.onAccent,
                                          ),
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (picked == null) return;
                                  _start = DateTime(picked.year, picked.month, picked.day);
                                  if (!_end.isAfter(_start)) _end = _start.add(const Duration(days: 1));
                                  setState(() {});
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: _DateField(
                                label: '종료 날짜(포함 안 됨)',
                                valueText: fmtDate.format(_end),
                                onPick: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _end,
                                    firstDate: DateTime(2000),
                                    lastDate: DateTime(2100),
                                    builder: (ctx, child) {
                                      final th = Theme.of(ctx);
                                      return Theme(
                                        data: th.copyWith(
                                          colorScheme: th.colorScheme.copyWith(
                                            primary: t.accent,
                                            onPrimary: t.onAccent,
                                          ),
                                        ),
                                        child: child!,
                                      );
                                    },
                                  );
                                  if (picked == null) return;
                                  _end = DateTime(picked.year, picked.month, picked.day);
                                  if (!_end.isAfter(_start)) _end = _start.add(const Duration(days: 1));
                                  setState(() {});
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),

                        // 색상
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '이벤트 색상',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: tt.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _ColorPicker(
                          palette: _eventColors,
                          selectedId: _colorId,
                          onSelected: (id) => setState(() => _colorId = id),
                        ),
                        const SizedBox(height: 16),

                        // 진행도 (0/100만)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '진행도',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: tt.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('0%'),
                              selected: _progress == 0,
                              selectedColor: tt.accentContainer,
                              backgroundColor: tt.cardTint,
                              checkmarkColor: tt.onAccentContainer,
                              labelStyle: TextStyle(
                                color: _progress == 0 ? tt.onAccentContainer : tt.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                              onSelected: (_) => setState(() => _progress = 0),
                            ),
                            ChoiceChip(
                              label: const Text('100%'),
                              selected: _progress == 100,
                              selectedColor: tt.accentContainer,
                              backgroundColor: tt.cardTint,
                              checkmarkColor: tt.onAccentContainer,
                              labelStyle: TextStyle(
                                color: _progress == 100 ? tt.onAccentContainer : tt.onSurfaceVariant,
                                fontWeight: FontWeight.w800,
                              ),
                              onSelected: (_) => setState(() => _progress = 100),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // === 2개씩 가로 스와이프 가능한 탭 헤더 + 폼 ===
                        Column(
                          children: [
                            DecoratedBox(
                              decoration: BoxDecoration(
                                border: Border(bottom: BorderSide(color: tt.divider)),
                              ),
                              child: SizedBox(
                                height: 46,
                                child: PageView.builder(
                                  controller: _tabsPageController,
                                  onPageChanged: (p) => setState(() => _headerPage = p),
                                  itemCount: _pageCount,
                                  itemBuilder: (context, page) {
                                    final left = page * 2;
                                    final right = left + 1;
                                    return Row(
                                      children: [
                                        Expanded(
                                          child: _UnderlineTab(
                                            label: _templates[left].label,
                                            selected: _currentTabIndex == left,
                                            onTap: () => _tabController.animateTo(left),
                                          ),
                                        ),
                                        if (right < _templates.length)
                                          Expanded(
                                            child: _UnderlineTab(
                                              label: _templates[right].label,
                                              selected: _currentTabIndex == right,
                                              onTap: () => _tabController.animateTo(right),
                                            ),
                                          )
                                        else
                                          const Expanded(child: SizedBox.shrink()),
                                      ],
                                    );
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),

                            _templates[_currentTabIndex].buildForm(context, _rebuildTemplate),

                            const SizedBox(height: 8),
                            _PageDots(
                              count: _pageCount,
                              current: _headerPage,
                              onDotTap: (p) => _tabsPageController.animateToPage(
                                p,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOut,
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '※ 종일 이벤트는 종료가 “다음날 0시”로 해석됩니다.',
                            style: TextStyle(fontSize: 12, color: tt.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                  // 하단 고정 액션바
                  Divider(height: 1, color: tt.divider),
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: tt.onSurface,
                              side: BorderSide(color: tt.divider.withOpacity(0.85)),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () => Navigator.pop(context),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: tt.accent,
                              foregroundColor: tt.onAccent,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: () {
                              if (_summary.text.trim().isEmpty) return;
                              Navigator.pop(
                                context,
                                EditResult(
                                  summary: _summary.text.trim(),
                                  description: _desc.text.trim(),
                                  start: _start,
                                  end: _end,
                                  allDay: _allDay,
                                  colorId: _colorId,
                                  progress: _progress,
                                ),
                              );
                            },
                            child: const Text('저장'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ====== 템플릿 인터페이스 & 구현들 ======

abstract class EventTemplate {
  String get id;
  String get label;
  Widget buildForm(BuildContext context, VoidCallback onChanged);
  void computePreview(TextEditingController summary, TextEditingController desc);
  void dispose();
}

class ApplyTemplate implements EventTemplate {
  final worker = TextEditingController();
  final region = TextEditingController();
  final name = TextEditingController();
  final reason = TextEditingController();
  final time = TextEditingController();

  @override
  String get id => 'apply';
  @override
  String get label => '지원';

  @override
  Widget buildForm(BuildContext context, VoidCallback onChanged) {
    return Column(children: [
      _LabeledField(label: '업무자', controller: worker, onChanged: (_) => onChanged()),
      _LabeledField(label: '지역', controller: region, onChanged: (_) => onChanged()),
      _LabeledField(label: '이름', controller: name, onChanged: (_) => onChanged()),
      _LabeledField(label: '사유', controller: reason, onChanged: (_) => onChanged()),
      _LabeledField(
        label: '시간',
        controller: time,
        hint: '예: 10:00~12:00',
        onChanged: (_) => onChanged(),
      ),
    ]);
  }

  @override
  void computePreview(TextEditingController summary, TextEditingController desc) {
    final t = [
      if (region.text.trim().isNotEmpty) region.text.trim(),
      if (name.text.trim().isNotEmpty) name.text.trim(),
      if (worker.text.trim().isNotEmpty) worker.text.trim(),
      '지원',
    ].join(' ').trim();

    final lines = <String>[];
    if (reason.text.trim().isNotEmpty) lines.add('사유: ${reason.text.trim()}');
    if (time.text.trim().isNotEmpty) lines.add('시간: ${time.text.trim()}');

    summary.text = t.isEmpty ? '지원' : t;
    desc.text = lines.join('\n');
  }

  @override
  void dispose() {
    worker.dispose();
    region.dispose();
    name.dispose();
    reason.dispose();
    time.dispose();
  }
}

class HireTemplate implements EventTemplate {
  final region = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  final gmail = TextEditingController();
  final bank = TextEditingController();
  final accountNo = TextEditingController();
  final salary = TextEditingController();
  final contractType = TextEditingController();

  final workStartDateText = TextEditingController();
  final firstEndDateText = TextEditingController();

  DateTime? workStartDate;
  DateTime? firstEndDate;

  @override
  String get id => 'hire';
  @override
  String get label => '입사';

  DateTime? _tryParseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 8) return null;
    final y = int.tryParse(digits.substring(0, 4));
    final m = int.tryParse(digits.substring(4, 6));
    final d = int.tryParse(digits.substring(6, 8));
    if (y == null || m == null || d == null) return null;
    try {
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget buildForm(BuildContext context, VoidCallback onChanged) {
    return Column(children: [
      _LabeledField(label: '지역', controller: region, onChanged: (_) => onChanged()),
      _LabeledField(label: '이름', controller: name, onChanged: (_) => onChanged()),
      _LabeledField(
        label: '전화번호',
        controller: phone,
        keyboardType: TextInputType.phone,
        onChanged: (_) => onChanged(),
      ),
      _LabeledField(
        label: '지메일',
        controller: gmail,
        keyboardType: TextInputType.emailAddress,
        hint: '예: name@gmail.com',
        onChanged: (_) => onChanged(),
      ),
      _LabeledField(label: '은행계좌', controller: bank, hint: '예: 우리은행', onChanged: (_) => onChanged()),
      _LabeledField(
        label: '계좌번호',
        controller: accountNo,
        keyboardType: TextInputType.number,
        onChanged: (_) => onChanged(),
      ),
      _LabeledField(
        label: '총 급여',
        controller: salary,
        hint: '예: 3,000,000원',
        keyboardType: TextInputType.number,
        onChanged: (_) => onChanged(),
      ),
      _LabeledField(
        label: '계약 형태',
        controller: contractType,
        hint: '예: 정규직/계약직',
        onChanged: (_) => onChanged(),
      ),
      _LabeledField(
        label: '근무 시작일',
        controller: workStartDateText,
        hint: '예: 2025-03-15 또는 20250315',
        keyboardType: TextInputType.number,
        onChanged: (_) {
          workStartDate = _tryParseDate(workStartDateText.text);
          onChanged();
        },
      ),
      _LabeledField(
        label: '첫 계약 종료일',
        controller: firstEndDateText,
        hint: '예: 2025-09-14 또는 20250914',
        keyboardType: TextInputType.number,
        onChanged: (_) {
          firstEndDate = _tryParseDate(firstEndDateText.text);
          onChanged();
        },
      ),
    ]);
  }

  @override
  void computePreview(TextEditingController summary, TextEditingController desc) {
    final fmt = DateFormat('yyyy-MM-dd');
    final t = [
      if (region.text.trim().isNotEmpty) region.text.trim(),
      if (name.text.trim().isNotEmpty) name.text.trim(),
      '입사',
    ].join(' ').trim();

    final lines = <String>[];
    void add(String k, String v) {
      if (v.trim().isNotEmpty) lines.add('$k: ${v.trim()}');
    }

    add('전화번호', phone.text);
    add('지메일', gmail.text);
    add('은행계좌', bank.text);
    add('계좌번호', accountNo.text);
    add('총 급여', salary.text);
    add('계약 형태', contractType.text);
    if (workStartDate != null) lines.add('근무 시작일: ${fmt.format(workStartDate!)}');
    if (firstEndDate != null) lines.add('첫 계약 종료일: ${fmt.format(firstEndDate!)}');

    summary.text = t.isEmpty ? '입사' : t;
    desc.text = lines.join('\n');
  }

  @override
  void dispose() {
    region.dispose();
    name.dispose();
    phone.dispose();
    gmail.dispose();
    bank.dispose();
    accountNo.dispose();
    salary.dispose();
    contractType.dispose();
    workStartDateText.dispose();
    firstEndDateText.dispose();
  }
}

class CheckInTemplate implements EventTemplate {
  final name = TextEditingController();
  final contractAmount = TextEditingController();
  final contractType = TextEditingController();
  final requestedDocs = TextEditingController();
  final workDateText = TextEditingController();
  DateTime? workDate;

  @override
  String get id => 'checkin';
  @override
  String get label => '출근';

  DateTime? _tryParseDate(String raw) {
    final s = raw.trim();
    if (s.isEmpty) return null;
    final digits = s.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length != 8) return null;
    final y = int.tryParse(digits.substring(0, 4));
    final m = int.tryParse(digits.substring(4, 6));
    final d = int.tryParse(digits.substring(6, 8));
    if (y == null || m == null || d == null) return null;
    try {
      return DateTime(y, m, d);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget buildForm(BuildContext context, VoidCallback onChanged) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Column(children: [
      _LabeledField(label: '이름', controller: name, onChanged: (_) => onChanged()),
      _LabeledField(
        label: '출근일',
        controller: workDateText,
        hint: '예: 2025-03-15 또는 20250315',
        keyboardType: TextInputType.number,
        onChanged: (_) {
          workDate = _tryParseDate(workDateText.text);
          onChanged();
        },
      ),
      _LabeledField(
        label: '계약액',
        controller: contractAmount,
        hint: '예: 3,000,000원',
        keyboardType: TextInputType.number,
        onChanged: (_) => onChanged(),
      ),
      _LabeledField(
        label: '계약 형태',
        controller: contractType,
        hint: '예: 정규직/계약직',
        onChanged: (_) => onChanged(),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: requestedDocs,
          minLines: 2,
          maxLines: 6,
          textInputAction: TextInputAction.newline,
          onChanged: (_) => onChanged(),
          scrollPadding: EdgeInsets.only(
            bottom: bottomInset + _kEditorBottomActionBarReserve + 24,
          ),
          decoration: const InputDecoration(
            labelText: '요청 문서',
            hintText: '쉼표(,) 또는 줄바꿈으로 구분해 입력',
            isDense: true,
          ),
        ),
      ),
    ]);
  }

  @override
  void computePreview(TextEditingController summary, TextEditingController desc) {
    final fmt = DateFormat('yyyy-MM-dd');

    final t = [
      if (name.text.trim().isNotEmpty) name.text.trim(),
      '출근',
    ].join(' ').trim();

    final lines = <String>[];
    if (workDate != null) lines.add('출근일: ${fmt.format(workDate!)}');
    if (contractAmount.text.trim().isNotEmpty) lines.add('계약액: ${contractAmount.text.trim()}');
    if (contractType.text.trim().isNotEmpty) lines.add('계약 형태: ${contractType.text.trim()}');

    final docs = requestedDocs.text
        .split(RegExp(r'[,\n]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (docs.isNotEmpty) {
      lines.add('요청 문서:');
      lines.addAll(docs.map((d) => '- $d'));
    }

    summary.text = t.isEmpty ? '출근' : t;
    desc.text = lines.join('\n');
  }

  @override
  void dispose() {
    name.dispose();
    contractAmount.dispose();
    contractType.dispose();
    requestedDocs.dispose();
    workDateText.dispose();
  }
}

class FreeTemplate implements EventTemplate {
  final TextEditingController title = TextEditingController();
  final TextEditingController body = TextEditingController();

  FreeTemplate({String? initialTitle, String? initialBody}) {
    if (initialTitle != null) title.text = initialTitle;
    if (initialBody != null) body.text = initialBody;
  }

  @override
  String get id => 'free';
  @override
  String get label => '자율';

  @override
  Widget buildForm(BuildContext context, VoidCallback onChanged) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Column(children: [
      _LabeledField(
        label: '제목',
        controller: title,
        hint: '자유롭게 제목을 입력하세요',
        onChanged: (_) => onChanged(),
      ),
      Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          controller: body,
          onChanged: (_) => onChanged(),
          minLines: 3,
          maxLines: 8,
          textInputAction: TextInputAction.newline,
          scrollPadding: EdgeInsets.only(
            bottom: bottomInset + _kEditorBottomActionBarReserve + 24,
          ),
          decoration: const InputDecoration(
            labelText: '설명',
            hintText: '자유롭게 설명을 입력하세요',
            isDense: true,
          ),
        ),
      ),
    ]);
  }

  @override
  void computePreview(TextEditingController summary, TextEditingController desc) {
    summary.text = title.text.trim();
    desc.text = body.text;
  }

  @override
  void dispose() {
    title.dispose();
    body.dispose();
  }
}

// ====== 보조 위젯들 / DTO ======

class _PreviewField extends StatelessWidget {
  const _PreviewField({
    required this.label,
    required this.controller,
    this.minLines = 1,
    this.maxLines = 1,
  });

  final String label;
  final TextEditingController controller;
  final int minLines;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final t = _EditorTokens.of(context);

    return TextField(
      controller: controller,
      readOnly: true,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: t.fieldFill,
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: t.accent, width: 1.2),
        ),
      ),
    );
  }
}

class _ReadOnlyCard extends StatelessWidget {
  const _ReadOnlyCard({required this.summary, required this.description});

  final String summary;
  final String description;

  @override
  Widget build(BuildContext context) {
    final t = _EditorTokens.of(context);

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: t.cardTint,
        border: Border.all(color: t.divider),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary, style: TextStyle(fontWeight: FontWeight.w800, color: t.onSurface)),
          if (description.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: TextStyle(color: t.onSurfaceVariant, height: 1.3),
            ),
          ],
        ],
      ),
    );
  }
}

class _LabeledField extends StatelessWidget {
  const _LabeledField({
    required this.label,
    required this.controller,
    this.hint,
    this.keyboardType,
    this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String? hint;
  final TextInputType? keyboardType;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final t = _EditorTokens.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.next,
        onChanged: onChanged,
        scrollPadding: EdgeInsets.only(
          bottom: bottomInset + _kEditorBottomActionBarReserve + 24,
        ),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          filled: true,
          fillColor: t.fieldFill,
          isDense: true,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: t.fieldBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: t.accent, width: 1.2),
          ),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.valueText,
    required this.onPick,
  });

  final String label;
  final String valueText;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    final t = _EditorTokens.of(context);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label, style: TextStyle(color: t.onSurface, fontWeight: FontWeight.w700)),
      subtitle: Text(valueText, style: TextStyle(color: t.onSurfaceVariant)),
      trailing: Icon(Icons.edit_calendar_rounded, color: t.accent),
      onTap: onPick,
    );
  }
}

class _ColorPicker extends StatelessWidget {
  const _ColorPicker({
    required this.palette,
    required this.selectedId,
    required this.onSelected,
  });

  final Map<String, Color> palette;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final t = _EditorTokens.of(context);
    final entries = palette.entries.toList();

    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _ColorDot(
          color: t.surface,
          borderColor: t.divider,
          isSelected: selectedId == null,
          label: '없음',
          onTap: () => onSelected(null),
        ),
        for (final e in entries)
          _ColorDot(
            color: e.value,
            borderColor: t.divider.withOpacity(0.6),
            isSelected: selectedId == e.key,
            label: e.key,
            onTap: () => onSelected(e.key),
          ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    this.borderColor,
    required this.isSelected,
    required this.label,
    required this.onTap,
  });

  final Color color;
  final Color? borderColor;
  final bool isSelected;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = _EditorTokens.of(context);
    final isLight = color.computeLuminance() > 0.6;
    final checkColor = isLight ? Colors.black : Colors.white;

    final dot = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor ?? t.divider, width: 1),
      ),
      child: isSelected ? Icon(Icons.check, size: 18, color: checkColor) : null,
    );

    return InkWell(
      onTap: onTap,
      customBorder: const CircleBorder(),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          dot,
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: t.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// ★ TabBar 느낌의 '언더라인' 탭(2개씩 표시용)
class _UnderlineTab extends StatelessWidget {
  const _UnderlineTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = _EditorTokens.of(context);

    return InkWell(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Center(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? t.accent : t.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 2,
            color: selected ? t.accent : Colors.transparent,
          ),
        ],
      ),
    );
  }
}

/// ★ 헤더 페이지 인디케이터
class _PageDots extends StatelessWidget {
  const _PageDots({
    required this.count,
    required this.current,
    this.onDotTap,
  });

  final int count;
  final int current;
  final ValueChanged<int>? onDotTap;

  @override
  Widget build(BuildContext context) {
    final t = _EditorTokens.of(context);
    if (count <= 1) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(count, (i) {
        final selected = i == current;
        return GestureDetector(
          onTap: onDotTap == null ? null : () => onDotTap!(i),
          child: Container(
            width: selected ? 10 : 8,
            height: selected ? 10 : 8,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: selected ? t.accent : t.divider.withOpacity(0.55),
            ),
          ),
        );
      }),
    );
  }
}

/// 바텀시트에서 반환되는 결과 DTO
class EditResult {
  EditResult({
    required this.summary,
    this.description,
    required this.start,
    required this.end,
    this.allDay = true,
    this.colorId,
    this.progress = 0,
  });

  final String summary;
  final String? description;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? colorId;
  final int progress;
}
