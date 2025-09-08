// lib/screens/head_package/calendar_package/event_editor_bottom_sheet.dart
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
      bool initialAllDay = true, // 항상 종일
      String? initialColorId,
    }) {
  return showModalBottomSheet<EditResult>(
    context: context,
    useSafeArea: true,                // ★ 안전영역 사용
    isScrollControlled: true,         // ★ 키보드 대응을 위해 전체 화면 높이 사용
    backgroundColor: Colors.transparent,
    builder: (_) => EventEditorBottomSheet(
      title: title,
      initialSummary: initialSummary,
      initialStart: initialStart,
      initialEnd: initialEnd,
      initialDescription: initialDescription,
      initialAllDay: initialAllDay,
      initialColorId: initialColorId,
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
  });

  final String title;
  final String initialSummary;
  final String initialDescription;
  final DateTime initialStart;
  final DateTime initialEnd;
  final bool initialAllDay;
  final String? initialColorId; // Google Calendar event colorId ("1"~"11") 또는 null

  @override
  State<EventEditorBottomSheet> createState() => _EventEditorBottomSheetState();
}

enum _TemplateTab { apply, hire } // 지원, 입사

class _EventEditorBottomSheetState extends State<EventEditorBottomSheet>
    with SingleTickerProviderStateMixin {
  // 공통(자동 생성 대상)
  late TextEditingController _summary; // 자동 생성 제목(읽기전용)
  late TextEditingController _desc;    // 자동 생성 설명(읽기전용)

  // 이벤트 자체(종일)
  late DateTime _start; // yyyy-MM-dd만 사용
  late DateTime _end;   // yyyy-MM-dd만 사용
  static const bool _allDay = true;

  // 색상
  String? _colorId;

  // 탭
  late TabController _tabController;

  // 지원 탭 입력
  final _applyRegion = TextEditingController();
  final _applyName   = TextEditingController();
  final _applyReason = TextEditingController();
  final _applyTime   = TextEditingController();

  // 입사 탭 입력
  final _hireRegion       = TextEditingController();
  final _hireName         = TextEditingController();
  final _hirePhone        = TextEditingController();
  final _hireGmail        = TextEditingController(); // 지메일
  final _hireBank         = TextEditingController();
  final _hireAccountNo    = TextEditingController();
  final _hireSalary       = TextEditingController();
  final _hireContractType = TextEditingController();
  DateTime? _hireWorkStartDate;
  DateTime? _hireFirstEndDate;

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
    _desc    = TextEditingController(text: widget.initialDescription);

    _start = _toLocalDateOnly(widget.initialStart);
    _end   = _toLocalDateOnly(widget.initialEnd);
    if (!_end.isAfter(_start)) {
      _end = _start.add(const Duration(days: 1));
    }

    _colorId = widget.initialColorId;

    // 초기 탭: 제목에 "입사" 포함 → 입사 탭, "지원" 포함 → 지원 탭, 기본 지원
    final initialIndex = widget.initialSummary.contains('입사')
        ? 1
        : (widget.initialSummary.contains('지원') ? 0 : 0);
    _tabController = TabController(length: 2, vsync: this, initialIndex: initialIndex);
    _tabController.addListener(_rebuildTemplate);

    // 최초 템플릿 생성
    WidgetsBinding.instance.addPostFrameCallback((_) => _rebuildTemplate());
  }

  @override
  void dispose() {
    _summary.dispose();
    _desc.dispose();
    _tabController.dispose();

    // 지원
    _applyRegion.dispose();
    _applyName.dispose();
    _applyReason.dispose();
    _applyTime.dispose();

    // 입사
    _hireRegion.dispose();
    _hireName.dispose();
    _hirePhone.dispose();
    _hireGmail.dispose();
    _hireBank.dispose();
    _hireAccountNo.dispose();
    _hireSalary.dispose();
    _hireContractType.dispose();

    super.dispose();
  }

  _TemplateTab get _currentTab =>
      _tabController.index == 1 ? _TemplateTab.hire : _TemplateTab.apply;

  void _rebuildTemplate() {
    final fmtDate = DateFormat('yyyy-MM-dd');

    if (_currentTab == _TemplateTab.apply) {
      final region = _applyRegion.text.trim();
      final name   = _applyName.text.trim();
      final reason = _applyReason.text.trim();
      final time   = _applyTime.text.trim();

      final title = [
        if (region.isNotEmpty) region,
        if (name.isNotEmpty) name,
        '지원',
      ].join(' ').trim();

      final desc = [
        '사유: $reason',
        '시간: $time',
      ].join('\n');

      _summary.text = title.isEmpty ? '지원' : title;
      _desc.text    = desc;
    } else {
      final region = _hireRegion.text.trim();
      final name   = _hireName.text.trim();

      final title = [
        if (region.isNotEmpty) region,
        if (name.isNotEmpty) name,
        '입사',
      ].join(' ').trim();

      final phone        = _hirePhone.text.trim();
      final gmail        = _hireGmail.text.trim();
      final bank         = _hireBank.text.trim();
      final accountNo    = _hireAccountNo.text.trim();
      final salary       = _hireSalary.text.trim();
      final contractType = _hireContractType.text.trim();
      final startStr     =
      _hireWorkStartDate != null ? fmtDate.format(_hireWorkStartDate!) : '';
      final endStr       =
      _hireFirstEndDate != null ? fmtDate.format(_hireFirstEndDate!) : '';

      final desc = [
        '전화번호: $phone',
        '지메일: $gmail',
        '은행계좌: $bank',
        '계좌번호: $accountNo',
        '총 급여: $salary',
        '계약 형태: $contractType',
        '근무 시작일: $startStr',
        '첫 계약 종료일: $endStr',
      ].join('\n');

      _summary.text = title.isEmpty ? '입사' : title;
      _desc.text    = desc;
    }

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets;
    final fmtDate = DateFormat('yyyy-MM-dd');

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(), // ★ 빈곳 탭 시 키보드 닫힘
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 200), // ★ 부드럽게 회피
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: viewInsets.bottom), // ★ 키보드 높이만큼 패딩
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
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.title,
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

                  // 내용(스크롤)
                  Expanded(
                    child: ListView(
                      controller: scrollController, // ★ DraggableScrollable와 연결
                      keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag, // ★ 드래그로 키보드 닫힘
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      children: [
                        // ===== 이벤트 날짜(종일) =====
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

                        // ===== 색상 선택 =====
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

                        // ===== 탭 (지원 / 입사) =====
                        DefaultTabController(
                          length: 2,
                          initialIndex: _currentTab == _TemplateTab.hire ? 1 : 0,
                          child: Column(
                            children: [
                              TabBar(
                                controller: _tabController,
                                labelColor: Theme.of(context).colorScheme.primary,
                                unselectedLabelColor: Colors.black54,
                                tabs: const [
                                  Tab(text: '지원'),
                                  Tab(text: '입사'),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _currentTab == _TemplateTab.apply
                                  ? _buildApplyForm()
                                  : _buildHireForm(),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),
                        // ===== 자동 생성 미리보기(읽기전용) =====
                        TextField(
                          controller: _summary,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: '제목(자동 생성)',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _desc,
                          readOnly: true,
                          minLines: 4,
                          maxLines: 8,
                          decoration: const InputDecoration(
                            labelText: '설명(자동 생성)',
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '※ 종일 이벤트는 종료가 “다음날 0시”로 해석됩니다.',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                          ),
                        ),

                        const SizedBox(height: 16),
                        // 하단 버튼(스크롤 영역 안으로 넣어 키보드/높이에 유연)
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

  // ====== 탭 폼들 ======

  Widget _buildApplyForm() {
    return Column(
      children: [
        _LabeledField(
          label: '지역',
          controller: _applyRegion,
          onChanged: (_) => _rebuildTemplate(),
        ),
        _LabeledField(
          label: '이름',
          controller: _applyName,
          onChanged: (_) => _rebuildTemplate(),
        ),
        _LabeledField(
          label: '사유',
          controller: _applyReason,
          onChanged: (_) => _rebuildTemplate(),
        ),
        _LabeledField(
          label: '시간',
          controller: _applyTime,
          hint: '예: 10:00~12:00',
          onChanged: (_) => _rebuildTemplate(),
        ),
      ],
    );
  }

  Widget _buildHireForm() {
    final fmt = DateFormat('yyyy-MM-dd');
    return Column(
      children: [
        _LabeledField(
          label: '지역',
          controller: _hireRegion,
          onChanged: (_) => _rebuildTemplate(),
        ),
        _LabeledField(
          label: '이름',
          controller: _hireName,
          onChanged: (_) => _rebuildTemplate(),
        ),
        _LabeledField(
          label: '전화번호',
          controller: _hirePhone,
          keyboardType: TextInputType.phone,
          onChanged: (_) => _rebuildTemplate(),
        ),
        _LabeledField(
          label: '지메일',
          controller: _hireGmail,
          keyboardType: TextInputType.emailAddress,
          hint: '예: name@gmail.com',
          onChanged: (_) => _rebuildTemplate(),
        ),
        _LabeledField(
          label: '은행계좌',
          controller: _hireBank,
          hint: '예: 우리은행',
          onChanged: (_) => _rebuildTemplate(),
        ),
        _LabeledField(
          label: '계좌번호',
          controller: _hireAccountNo,
          keyboardType: TextInputType.number,
          onChanged: (_) => _rebuildTemplate(),
        ),
        _LabeledField(
          label: '총 급여',
          controller: _hireSalary,
          hint: '예: 3,000,000원',
          keyboardType: TextInputType.number,
          onChanged: (_) => _rebuildTemplate(),
        ),
        _LabeledField(
          label: '계약 형태',
          controller: _hireContractType,
          hint: '예: 정규직/계약직',
          onChanged: (_) => _rebuildTemplate(),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('근무 시작일'),
          subtitle: Text(_hireWorkStartDate == null
              ? '미선택'
              : fmt.format(_hireWorkStartDate!)),
          trailing: const Icon(Icons.edit_calendar),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _hireWorkStartDate ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked == null) return;
            _hireWorkStartDate = DateTime(picked.year, picked.month, picked.day);
            _rebuildTemplate();
          },
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('첫 계약 종료일'),
          subtitle:
          Text(_hireFirstEndDate == null ? '미선택' : fmt.format(_hireFirstEndDate!)),
          trailing: const Icon(Icons.edit_calendar),
          onTap: () async {
            final picked = await showDatePicker(
              context: context,
              initialDate: _hireFirstEndDate ?? DateTime.now(),
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
            );
            if (picked == null) return;
            _hireFirstEndDate = DateTime(picked.year, picked.month, picked.day);
            _rebuildTemplate();
          },
        ),
      ],
    );
  }
}

// ====== 보조 위젯들 ======

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
        textInputAction: TextInputAction.next, // ★ 다음 필드로 이동 쉬움
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
      child: isSelected
          ? const Icon(Icons.check, size: 18, color: Colors.white)
          : null,
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
    this.colorId,       // "1"~"11" 또는 null
  });

  final String summary;
  final String? description;
  final DateTime start; // yyyy-MM-dd 의도(시간 없이)
  final DateTime end;   // yyyy-MM-dd 의도(다음날 0시 의미)
  final bool allDay;
  final String? colorId;
}
