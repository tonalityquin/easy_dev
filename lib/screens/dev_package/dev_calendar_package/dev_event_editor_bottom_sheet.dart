import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// 호출 헬퍼
Future<EditResult?> showEventEditorBottomSheet(
    BuildContext context, {
      required String title,
      required String initialSummary,
      required DateTime initialStart,
      required DateTime initialEnd,
      String initialDescription = '',
      bool initialAllDay = true, // 항상 종일 (정책상 사용하지 않지만 시그니처는 유지)
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

    // ★ 템플릿 세트 구성(외부 주입 없으면 기본 세트)
    _templates = widget.templates ??
        [
          ApplyTemplate(),
          HireTemplate(),
          FreeTemplate(
            initialTitle: widget.initialSummary,
            initialBody: widget.initialDescription,
          ),
        ];

    // 시작 탭: 편집모드면 free, 생성모드면 키워드로 추론(입사/지원 없으면 free)
    int initialIndex = 0;
    if (widget.isEditMode) {
      initialIndex = _templates.indexWhere((t) => t.id == 'free');
      if (initialIndex < 0) initialIndex = 0;
    } else {
      final s = widget.initialSummary;
      if (s.contains('입사')) {
        final idx = _templates.indexWhere((t) => t.id == 'hire');
        initialIndex = idx >= 0 ? idx : 0;
      } else if (s.contains('지원')) {
        final idx = _templates.indexWhere((t) => t.id == 'apply');
        initialIndex = idx >= 0 ? idx : 0;
      } else {
        final idx = _templates.indexWhere((t) => t.id == 'free');
        initialIndex = idx >= 0 ? idx : 0;
      }
    }

    _tabController = TabController(
      length: _templates.length,
      vsync: this,
      initialIndex: initialIndex.clamp(0, _templates.length - 1),
    );

    // 생성 모드에서만 탭 변경 시 템플릿으로 미리보기 재생성
    if (!widget.isEditMode) {
      _tabController.addListener(_rebuildTemplate);
      WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildTemplate());
    }
  }

  @override
  void dispose() {
    _summary.dispose();
    _desc.dispose();
    _tabController.dispose();
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
        padding: EdgeInsets.only(bottom: viewInsets.bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.97,
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
                    padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
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
                          Text('원본 내용',
                              style: Theme.of(context).textTheme.titleSmall),
                          const SizedBox(height: 8),
                          _ReadOnlyCard(
                            summary: widget.initialSummary,
                            description: widget.initialDescription,
                          ),
                          const SizedBox(height: 12),
                        ],
                        Text(
                            widget.isEditMode ? '새 내용 미리보기' : '미리보기',
                            style: Theme.of(context).textTheme.titleSmall),
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
                      keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
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
                                  _start = DateTime(
                                      picked.year, picked.month, picked.day);
                                  if (!_end.isAfter(_start)) {
                                    _end =
                                        _start.add(const Duration(days: 1));
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
                                  _end = DateTime(
                                      picked.year, picked.month, picked.day);
                                  if (!_end.isAfter(_start)) {
                                    _end =
                                        _start.add(const Duration(days: 1));
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
                          child: Text('이벤트 색상',
                              style: Theme.of(context).textTheme.bodyMedium),
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
                          child: Text('진행도',
                              style: Theme.of(context).textTheme.bodyMedium),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          children: [
                            ChoiceChip(
                              label: const Text('0%'),
                              selected: _progress == 0,
                              onSelected: (_) =>
                                  setState(() => _progress = 0),
                            ),
                            ChoiceChip(
                              label: const Text('100%'),
                              selected: _progress == 100,
                              onSelected: (_) =>
                                  setState(() => _progress = 100),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // 탭 (동적 템플릿)
                        Column(
                          children: [
                            TabBar(
                              controller: _tabController,
                              labelColor:
                              Theme.of(context).colorScheme.primary,
                              unselectedLabelColor: Colors.black54,
                              tabs: [
                                for (final t in _templates) Tab(text: t.label),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // 현재 탭 폼
                            _templates[_tabController.index]
                                .buildForm(context, _rebuildTemplate),
                          ],
                        ),

                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '※ 종일 이벤트는 종료가 “다음날 0시”로 해석됩니다.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.black54),
                          ),
                        ),

                        const SizedBox(height: 16),
                        Row(
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
  String get id;        // 내부 아이디 (예: 'apply', 'hire', 'free')
  String get label;     // 탭 라벨 (예: '지원')
  Widget buildForm(BuildContext context, VoidCallback onChanged);
  void computePreview(TextEditingController summary, TextEditingController desc);
  void dispose();       // 내부 컨트롤러 정리
}

/// 지원 템플릿
class ApplyTemplate implements EventTemplate {
  final worker = TextEditingController(); // 업무자
  final region = TextEditingController();
  final name   = TextEditingController();
  final reason = TextEditingController();
  final time   = TextEditingController();

  @override
  String get id => 'apply';
  @override
  String get label => '지원';

  @override
  Widget buildForm(BuildContext context, VoidCallback onChanged) {
    return Column(children: [
      _LabeledField(label: '업무자', controller: worker, onChanged: (_) => onChanged()),
      _LabeledField(label: '지역',   controller: region, onChanged: (_) => onChanged()),
      _LabeledField(label: '이름',   controller: name,   onChanged: (_) => onChanged()),
      _LabeledField(label: '사유',   controller: reason, onChanged: (_) => onChanged()),
      _LabeledField(label: '시간',   controller: time,   hint: '예: 10:00~12:00', onChanged: (_) => onChanged()),
    ]);
  }

  @override
  void computePreview(TextEditingController summary, TextEditingController desc) {
    final t = [
      if (region.text.trim().isNotEmpty) region.text.trim(),
      if (name.text.trim().isNotEmpty)   name.text.trim(),
      if (worker.text.trim().isNotEmpty) worker.text.trim(),
      '지원',
    ].join(' ').trim();

    final lines = <String>[];
    if (reason.text.trim().isNotEmpty) lines.add('사유: ${reason.text.trim()}');
    if (time.text.trim().isNotEmpty)   lines.add('시간: ${time.text.trim()}');

    summary.text = t.isEmpty ? '지원' : t;
    desc.text    = lines.join('\n');
  }

  @override
  void dispose() {
    worker.dispose(); region.dispose(); name.dispose(); reason.dispose(); time.dispose();
  }
}

/// 입사 템플릿
class HireTemplate implements EventTemplate {
  final region = TextEditingController();
  final name   = TextEditingController();
  final phone  = TextEditingController();
  final gmail  = TextEditingController();
  final bank   = TextEditingController();
  final accountNo    = TextEditingController();
  final salary       = TextEditingController();
  final contractType = TextEditingController();

  DateTime? workStartDate;
  DateTime? firstEndDate;

  @override
  String get id => 'hire';
  @override
  String get label => '입사';

  @override
  Widget buildForm(BuildContext context, VoidCallback onChanged) {
    final fmt = DateFormat('yyyy-MM-dd');
    return Column(children: [
      _LabeledField(label: '지역', controller: region, onChanged: (_) => onChanged()),
      _LabeledField(label: '이름', controller: name,   onChanged: (_) => onChanged()),
      _LabeledField(label: '전화번호', controller: phone, keyboardType: TextInputType.phone, onChanged: (_) => onChanged()),
      _LabeledField(label: '지메일', controller: gmail, keyboardType: TextInputType.emailAddress, hint: '예: name@gmail.com', onChanged: (_) => onChanged()),
      _LabeledField(label: '은행계좌', controller: bank, hint: '예: 우리은행', onChanged: (_) => onChanged()),
      _LabeledField(label: '계좌번호', controller: accountNo, keyboardType: TextInputType.number, onChanged: (_) => onChanged()),
      _LabeledField(label: '총 급여', controller: salary, hint: '예: 3,000,000원', keyboardType: TextInputType.number, onChanged: (_) => onChanged()),
      _LabeledField(label: '계약 형태', controller: contractType, hint: '예: 정규직/계약직', onChanged: (_) => onChanged()),
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('근무 시작일'),
        subtitle: Text(workStartDate == null ? '미선택' : fmt.format(workStartDate!)),
        trailing: const Icon(Icons.edit_calendar),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: workStartDate ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            workStartDate = DateTime(picked.year, picked.month, picked.day);
            onChanged();
          }
        },
      ),
      ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        title: const Text('첫 계약 종료일'),
        subtitle: Text(firstEndDate == null ? '미선택' : fmt.format(firstEndDate!)),
        trailing: const Icon(Icons.edit_calendar),
        onTap: () async {
          final picked = await showDatePicker(
            context: context,
            initialDate: firstEndDate ?? DateTime.now(),
            firstDate: DateTime(2000),
            lastDate: DateTime(2100),
          );
          if (picked != null) {
            firstEndDate = DateTime(picked.year, picked.month, picked.day);
            onChanged();
          }
        },
      ),
    ]);
  }

  @override
  void computePreview(TextEditingController summary, TextEditingController desc) {
    final fmt = DateFormat('yyyy-MM-dd');
    final t = [
      if (region.text.trim().isNotEmpty) region.text.trim(),
      if (name.text.trim().isNotEmpty)   name.text.trim(),
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
    if (firstEndDate != null)  lines.add('첫 계약 종료일: ${fmt.format(firstEndDate!)}');

    summary.text = t.isEmpty ? '입사' : t;
    desc.text    = lines.join('\n');
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
  }
}

/// 자율 템플릿
class FreeTemplate implements EventTemplate {
  final TextEditingController title = TextEditingController();
  final TextEditingController body  = TextEditingController();

  FreeTemplate({String? initialTitle, String? initialBody}) {
    if (initialTitle != null) title.text = initialTitle;
    if (initialBody  != null) body.text  = initialBody;
  }

  @override
  String get id => 'free';
  @override
  String get label => '자율';

  @override
  Widget buildForm(BuildContext context, VoidCallback onChanged) {
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
    desc.text    = body.text;
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        textInputAction: TextInputAction.next,
        onChanged: onChanged,
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
