import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// ✅ 하단 고정 버튼바 높이(대략치) + 여유를 위한 예약 값
/// - SafeArea + 버튼 높이 + 패딩을 고려해 충분히 크게 잡습니다.
/// - ListView bottom padding 및 TextField scrollPadding에 같이 사용합니다.
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
      List<EventTemplate>? templates, // ★ 탭 확장/삭제를 위한 동적 템플릿
    }) {
  return showModalBottomSheet<EditResult>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
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
    this.initialAllDay = true, // 항상 종일
    this.initialColorId, // 선택 색상(없으면 null)
    this.initialProgress = 0, // 0 또는 100
    this.isEditMode = false, // 편집 모드
    this.templates, // 동적 템플릿
  });

  final String title;
  final String initialSummary;
  final String initialDescription;
  final DateTime initialStart;
  final DateTime initialEnd;
  final bool initialAllDay;
  final String? initialColorId; // Google Calendar event colorId ("1"~"11") 또는 null
  final int initialProgress; // 0 또는 100
  final bool isEditMode;
  final List<EventTemplate>? templates;

  @override
  State<EventEditorBottomSheet> createState() => _EventEditorBottomSheetState();
}

class _EventEditorBottomSheetState extends State<EventEditorBottomSheet>
    with SingleTickerProviderStateMixin {
  // 공통(자동/자율 생성 대상)
  late final TextEditingController _summary; // 제목(미리보기 & 결과)
  late final TextEditingController _desc; // 설명(미리보기 & 결과)

  // 이벤트 자체(종일)
  late DateTime _start; // yyyy-MM-dd만 사용
  late DateTime _end; // yyyy-MM-dd만 사용
  static const bool _allDay = true; // 정책상 항상 종일

  // 색상
  String? _colorId;

  // 진행도(0 또는 100)
  late int _progress;

  // 템플릿/탭
  late final List<EventTemplate> _templates;
  late final TabController _tabController;

  // ★ 2개씩 묶어 넘기는 헤더용 PageView
  late final PageController _tabsPageController;
  int _headerPage = 0; // 현재 헤더 페이지(2개 단위)

  // 헬퍼
  int get _currentTabIndex => _tabController.index;
  int get _currentPage => _currentTabIndex ~/ 2;
  int get _pageCount => (_templates.length + 1) ~/ 2;

  // Google Calendar event colorId 팔레트
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
    if (!_end.isAfter(_start)) {
      _end = _start.add(const Duration(days: 1));
    }

    _colorId = widget.initialColorId;
    _progress = (widget.initialProgress == 100) ? 100 : 0; // 0/100만 허용

    // ★ 템플릿 세트 구성(외부 주입 없으면 기본 세트) — 출근 탭 포함
    _templates = widget.templates ??
        [
          ApplyTemplate(),
          HireTemplate(),
          CheckInTemplate(), // ★ 출근
          FreeTemplate(
            initialTitle: widget.initialSummary,
            initialBody: widget.initialDescription,
          ),
        ];

    // 시작 탭: 편집모드면 free, 생성모드면 키워드로 추론(입사/지원/출근 없으면 free)
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
        idx = _templates.indexWhere((t) => t.id == 'checkin'); // ★ 출근
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

    // ★ 헤더 PageView 초기 페이지를 현재 탭의 '2개 묶음' 페이지로 설정
    _headerPage = _currentPage;
    _tabsPageController = PageController(initialPage: _headerPage);

    // 탭 전환 시: 헤더 PageView도 해당 페이지로 맞추고, 미리보기 재생성(생성 모드만)
    _tabController.addListener(() {
      if (!mounted) return;

      final page = _currentPage;
      if (_tabsPageController.hasClients) {
        final current = _tabsPageController.page?.round() ?? _tabsPageController.initialPage;
        if (current != page) {
          _tabsPageController.animateToPage(
            page,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOut,
          );
        }
      }
      if (_headerPage != page) {
        setState(() => _headerPage = page);
      }

      if (!widget.isEditMode) {
        _rebuildTemplate(); // 내부에서 setState() 처리
      } else {
        setState(() {}); // 폼만 갱신
      }
    });

    // 생성 모드에서는 첫 진입 시에도 미리보기 생성
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
    final viewInsets = MediaQuery.of(context).viewInsets;
    final fmtDate = DateFormat('yyyy-MM-dd');

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        // ✅ 키보드가 올라오면 시트 전체를 위로 밀어 올림(하단 고정 바도 함께 올라가서 키보드에 가리지 않게 됨)
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 1.0, // ★ 처음부터 끝까지
          minChildSize: 0.5,
          maxChildSize: 1.0, // ★ 최댓값도 끝까지
          builder: (context, scrollController) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  const SizedBox(height: 8),
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 8),

                  // 헤더
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
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
                        // 편집 모드에서 원본 미리보기 표시
                        if (widget.isEditMode) ...[
                          Text('원본 내용', style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          _ReadOnlyCard(
                            summary: widget.initialSummary,
                            description: widget.initialDescription,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                          widget.isEditMode ? '새 내용 미리보기' : '미리보기',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _summary,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: '제목',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _desc,
                          readOnly: true,
                          minLines: 3,
                          maxLines: 6,
                          decoration: const InputDecoration(
                            labelText: '설명',
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),

                  // ===== 스크롤 영역 =====
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      // ✅ 하단 고정 버튼바(취소/저장) 영역만큼 bottom padding을 확보
                      //    -> 마지막 입력칸/컨텐츠가 버튼 뒤로 숨어서 터치 불가가 되는 문제를 방지
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
                                  );
                                  if (picked == null) return;
                                  _start = DateTime(picked.year, picked.month, picked.day);
                                  if (!_end.isAfter(_start)) {
                                    _end = _start.add(const Duration(days: 1));
                                  }
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
                                  );
                                  if (picked == null) return;
                                  _end = DateTime(picked.year, picked.month, picked.day);
                                  if (!_end.isAfter(_start)) {
                                    _end = _start.add(const Duration(days: 1));
                                  }
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
                          child: Text('이벤트 색상', style: Theme.of(context).textTheme.bodyMedium),
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
                          child: Text('진행도', style: Theme.of(context).textTheme.bodyMedium),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('0%'),
                              selected: _progress == 0,
                              onSelected: (_) => setState(() => _progress = 0),
                            ),
                            ChoiceChip(
                              label: const Text('100%'),
                              selected: _progress == 100,
                              onSelected: (_) => setState(() => _progress = 100),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // === 2개씩 가로 스와이프 가능한 탭 헤더 + 폼 ===
                        Column(
                          children: [
                            // 2개씩 보여주는 헤더 (가로 스와이프)
                            DecoratedBox(
                              decoration: const BoxDecoration(
                                border: Border(bottom: BorderSide(color: Colors.black12)),
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

                            // 현재 선택된 템플릿의 폼
                            _templates[_currentTabIndex].buildForm(context, _rebuildTemplate),

                            const SizedBox(height: 8),

                            // 페이지 인디케이터
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
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '※ 종일 이벤트는 종료가 “다음날 0시”로 해석됩니다.',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ),

                        const SizedBox(height: 8),
                      ],
                    ),
                  ),

                  // ✅ 하단 고정 액션바(취소/저장) — SafeArea로 홈 인디케이터/제스처 바 회피
                  const Divider(height: 1),
                  SafeArea(
                    top: false,
                    minimum: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('취소'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
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

/// 각 탭을 데이터/로직 단위로 독립시키는 추상 클래스
abstract class EventTemplate {
  String get id; // 내부 아이디 (예: 'apply', 'hire', 'free', 'checkin')
  String get label; // 탭 라벨 (예: '지원', '입사', '출근', '자율')
  Widget buildForm(BuildContext context, VoidCallback onChanged);
  void computePreview(TextEditingController summary, TextEditingController desc);
  void dispose(); // 내부 컨트롤러 정리
}

/// 지원 템플릿
class ApplyTemplate implements EventTemplate {
  final worker = TextEditingController(); // 업무자
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

/// 입사 템플릿 (★ 날짜 입력을 텍스트 필드로)
class HireTemplate implements EventTemplate {
  final region = TextEditingController();
  final name = TextEditingController();
  final phone = TextEditingController();
  final gmail = TextEditingController();
  final bank = TextEditingController();
  final accountNo = TextEditingController();
  final salary = TextEditingController();
  final contractType = TextEditingController();

  // ★ 텍스트 입력용 컨트롤러 추가
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

      // ★ 숫자 입력 텍스트 필드 (YYYY-MM-DD / YYYYMMDD)
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

/// 출근 템플릿
class CheckInTemplate implements EventTemplate {
  final name = TextEditingController(); // 이름
  final contractAmount = TextEditingController(); // 계약액
  final contractType = TextEditingController(); // 계약 형태
  final requestedDocs = TextEditingController(); // 요청 문서(쉼표/줄바꿈 구분)
  final workDateText = TextEditingController(); // ★ 출근일(텍스트 입력)
  DateTime? workDate; // 출근일(파싱된 값)

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
          // ✅ 멀티라인 TextField도 키보드/하단 고정바 위로 충분히 올라오도록 scrollPadding 적용
          scrollPadding: EdgeInsets.only(bottom: bottomInset + _kEditorBottomActionBarReserve + 24),
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

/// 자율 템플릿
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
          // ✅ 멀티라인 TextField도 키보드/하단 고정바 위로 충분히 올라오도록 scrollPadding 적용
          scrollPadding: EdgeInsets.only(bottom: bottomInset + _kEditorBottomActionBarReserve + 24),
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

class _ReadOnlyCard extends StatelessWidget {
  const _ReadOnlyCard({required this.summary, required this.description});

  final String summary;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(summary, style: const TextStyle(fontWeight: FontWeight.w700)),
          if (description.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              description,
              style: const TextStyle(color: Colors.black87, height: 1.3),
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.next,
        onChanged: onChanged,
        // ✅ 포커스 시 키보드 위로 충분히 자동 스크롤되도록
        //    키보드 높이 + 하단 고정바 영역 + 여유를 확보
        scrollPadding: EdgeInsets.only(bottom: bottomInset + _kEditorBottomActionBarReserve + 24),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          isDense: true,
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
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(label),
      subtitle: Text(valueText),
      trailing: const Icon(Icons.edit_calendar),
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
    final entries = palette.entries.toList();
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _ColorDot(
          color: Colors.white,
          borderColor: Colors.grey.shade400,
          isSelected: selectedId == null,
          label: '없음',
          onTap: () => onSelected(null),
        ),
        for (final e in entries)
          _ColorDot(
            color: e.value,
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
    final isLight = color.computeLuminance() > 0.6;
    final checkColor = isLight ? Colors.black : Colors.white;

    final dot = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor ?? Colors.black12,
          width: 1,
        ),
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
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
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
    final theme = Theme.of(context);
    final textColor = selected ? theme.colorScheme.primary : Colors.black54;

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
                  color: textColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 2,
            color: selected ? theme.colorScheme.primary : Colors.transparent,
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
              color: selected ? Colors.black87 : Colors.black26,
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
    this.allDay = true, // 항상 종일
    this.colorId, // "1"~"11" 또는 null
    this.progress = 0, // 0 또는 100
  });

  final String summary;
  final String? description;
  final DateTime start; // yyyy-MM-dd 의도(시간 없이)
  final DateTime end; // yyyy-MM-dd 의도(다음날 0시 의미)
  final bool allDay;
  final String? colorId;
  final int progress; // 0 or 100
}
