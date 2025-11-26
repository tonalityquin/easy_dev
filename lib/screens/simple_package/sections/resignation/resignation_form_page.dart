import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../../utils/google_auth_v7.dart';
import '../../../../../../utils/api/email_config.dart';
import 'resignation_styles.dart';
import 'resignation_signature_dialog.dart';

/// 사직 사유 유형
enum ResignationReasonType {
  personal,    // 개인 사정
  contractEnd, // 계약 만료
  other,       // 기타
}

class ResignationFormPage extends StatefulWidget {
  const ResignationFormPage({super.key});

  @override
  State<ResignationFormPage> createState() => _ResignationFormPageState();
}

class _ResignationFormPageState extends State<ResignationFormPage> {
  final _formKey = GlobalKey<FormState>();

  // 기본 정보 컨트롤러
  final _deptCtrl = TextEditingController();     // 부서명
  final _nameCtrl = TextEditingController();     // 성명
  final _positionCtrl = TextEditingController(); // 직위
  final _rrnCtrl = TextEditingController();      // 주민등록번호

  final _contentCtrl = TextEditingController(); // 사직 사유(자동 문장 or 자율 서술)

  final _mailSubjectCtrl = TextEditingController();
  final _mailBodyCtrl = TextEditingController();

  final _deptNode = FocusNode();
  final _nameNode = FocusNode();
  final _positionNode = FocusNode();
  final _rrnNode = FocusNode();
  final _contentNode = FocusNode();

  Uint8List? _signaturePngBytes;
  DateTime? _signDateTime;

  // 사직 예정일
  DateTime? _resignDate;

  // 사직 사유 유형
  ResignationReasonType? _reasonType;

  // SharedPreferences에서 불러오는 선택 영역 (업무/사업장 명 등)
  String? _selectedArea;

  String get _signerName => _nameCtrl.text.trim();

  bool _sending = false;

  // 페이지 컨트롤러 (섹션별 좌우 스와이프)
  final PageController _pageController = PageController();

  // 현재 페이지 인덱스 (0~3)
  int _currentPageIndex = 0;

  // 키보드가 필드를 가리지 않도록 하기 위한 키
  final GlobalKey _contentFieldKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(() {
      setState(() {});
      _updateMailBody(); // 이름 변경 시 메일 본문에 반영
    });
    _updateMailBody(); // 메일 본문 자동 생성
    _loadSelectedArea();
  }

  Future<void> _loadSelectedArea() async {
    final prefs = await SharedPreferences.getInstance();
    final area = prefs.getString('selectedArea') ?? '';
    if (!mounted) return;
    setState(() {
      _selectedArea = area.isEmpty ? null : area;
    });

    // 사용자가 아직 제목을 입력하지 않은 경우에만 자동 채움
    if (_mailSubjectCtrl.text.trim().isEmpty) {
      _updateMailSubject();
    }
  }

  @override
  void dispose() {
    _deptCtrl.dispose();
    _nameCtrl.dispose();
    _positionCtrl.dispose();
    _rrnCtrl.dispose();
    _contentCtrl.dispose();
    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();

    _deptNode.dispose();
    _nameNode.dispose();
    _positionNode.dispose();
    _rrnNode.dispose();
    _contentNode.dispose();

    _pageController.dispose();

    super.dispose();
  }

  String _fmtDT(BuildContext context, DateTime? dt) {
    if (dt == null) return '미선택';
    final loc = MaterialLocalizations.of(context);
    final dateStr = loc.formatFullDate(dt);
    final timeStr = loc.formatTimeOfDay(
      TimeOfDay.fromDateTime(dt),
      alwaysUse24HourFormat: true,
    );
    return '$dateStr $timeStr';
  }

  String _fmtDateOnly(DateTime dt) {
    final loc = MaterialLocalizations.of(context);
    return loc.formatFullDate(dt);
  }

  String _fmtCompact(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _dateTag(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  void _reset() {
    HapticFeedback.lightImpact();
    _formKey.currentState?.reset();
    _deptCtrl.clear();
    _nameCtrl.clear();
    _positionCtrl.clear();
    _rrnCtrl.clear();
    _contentCtrl.clear();
    _mailSubjectCtrl.clear();
    _mailBodyCtrl.clear();
    setState(() {
      _signaturePngBytes = null;
      _signDateTime = null;
      _resignDate = null;
      _reasonType = null;
      // _selectedArea는 SharedPreferences 기반 설정 값이라 초기화하지 않고 유지
      _currentPageIndex = 0;
    });
    // 리셋 후에도 제목/본문은 기본값으로 자동 생성
    _updateMailSubject();
    _updateMailBody(force: true);
    // 페이지도 첫 페이지로
    _pageController.jumpToPage(0);
  }

  /// SharedPreferences 선택 영역에 따라 메일 제목 자동 생성 (사직서)
  void _updateMailSubject() {
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final d = now.day;

    // SharedPreferences에 저장된 selectedArea 사용 (없으면 '업무' 기본값)
    final area =
    (_selectedArea != null && _selectedArea!.trim().isNotEmpty) ? _selectedArea!.trim() : '업무';

    // 예: 콜센터 사직서 제출 – 2025년 11월 26일자
    _mailSubjectCtrl.text = '$area 사직서 제출 – ${y}년 ${m}월 ${d}일자';
  }

  /// 메일 본문 자동 생성 (작성 일시 + 사직 예정일 + 이름)
  void _updateMailBody({bool force = false}) {
    if (!force && _mailBodyCtrl.text.trim().isNotEmpty) return;
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final d = now.day;
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');

    final name = _signerName.isEmpty ? '무기명' : _signerName;
    final resignDateText =
    _resignDate == null ? '미정' : _fmtDateOnly(_resignDate!);

    _mailBodyCtrl.text =
    '본 메일은 ${name}님의 사직서 제출을 위한 자동 생성 메일입니다.\n'
        '사직 예정일: $resignDateText\n'
        '작성 기준 시각: ${y}년 ${m}월 ${d}일 ${hh}시 ${mm}분';
  }

  /// "개인 사정" 또는 "계약 만료" 선택 시 자동으로 들어갈 문장 생성
  String _buildTemplateReasonSentence() {
    if (!(_reasonType == ResignationReasonType.personal ||
        _reasonType == ResignationReasonType.contractEnd)) {
      return _contentCtrl.text;
    }

    final reasonText =
    _reasonType == ResignationReasonType.personal ? '개인 사정' : '계약 만료';

    if (_resignDate == null) {
      // 날짜가 아직 선택 안 된 경우, 빈 괄호 형태로 노출
      return '상기 본인은 (${reasonText}) 으로 (    )년 (  )월 (  )일부로 '
          '사직하고자 하오니 재가하여 주시기 바랍니다.';
    }

    final year = _resignDate!.year.toString();
    final month = _resignDate!.month.toString();
    final day = _resignDate!.day.toString();

    return '상기 본인은 (${reasonText}) 으로 ($year)년 ($month)월 ($day)일부로 '
        '사직하고자 하오니 재가하여 주시기 바랍니다.';
  }

  /// 템플릿 유형(개인 사정/계약 만료)일 때 _contentCtrl 에 자동 문장 반영
  void _updateTemplateContent() {
    if (_reasonType == ResignationReasonType.personal ||
        _reasonType == ResignationReasonType.contractEnd) {
      _contentCtrl.text = _buildTemplateReasonSentence();
    }
    // 기타(자율 서술)일 때는 사용자가 직접 쓰므로 건드리지 않음
  }

  String _buildPreviewText(BuildContext context) {
    final signInfo = (_signaturePngBytes != null)
        ? '전자서명: ${_signerName.isEmpty ? "(이름 미입력)" : _signerName} / '
        '${_signDateTime != null ? _fmtCompact(_signDateTime!) : "저장 시각 미기록"}'
        : '전자서명: (미첨부)';

    final dept = _deptCtrl.text.trim().isEmpty ? '(부서 미입력)' : _deptCtrl.text.trim();
    final position =
    _positionCtrl.text.trim().isEmpty ? '(직위 미입력)' : _positionCtrl.text.trim();
    final name = _signerName.isEmpty ? '(이름 미입력)' : _signerName;
    final rrn =
    _rrnCtrl.text.trim().isEmpty ? '(주민등록번호 미입력)' : _rrnCtrl.text.trim();
    final resignDateText =
    _resignDate == null ? '(사직 예정일 미선택)' : _fmtDateOnly(_resignDate!);

    return [
      '— 사직서 —',
      '',
      '부서: $dept',
      '직위: $position',
      '성명: $name',
      '주민등록번호: $rrn',
      '사직 예정일: $resignDateText',
      '',
      '[사직 사유]',
      _contentCtrl.text,
      '',
      signInfo,
      '작성일: ${_fmtDT(context, DateTime.now())}',
      '',
      '※ 메일 제목: ${_mailSubjectCtrl.text}',
      '※ 메일 본문: ${_mailBodyCtrl.text}',
    ].join('\n');
  }

  Future<void> _pickResignDate() async {
    final now = DateTime.now();
    final initial = _resignDate ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: '사직 예정일 선택',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (picked != null) {
      setState(() {
        _resignDate = picked;
        _updateTemplateContent();
      });
      _updateMailBody(force: true);
    }
  }

  Future<void> _showPreview() async {
    HapticFeedback.lightImpact();
    _updateMailBody(); // 미리보기 전에 본문이 비어있으면 자동 생성
    final text = _buildPreviewText(context);

    // 화면에 보여줄 데이터들 다시 계산
    final signName = _signerName.isEmpty ? '이름 미입력' : _signerName;
    final signTimeText =
    _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);
    final createdAtText = _fmtDT(context, DateTime.now());
    final resignDateText =
    _resignDate == null ? '미선택' : _fmtDateOnly(_resignDate!);

    Widget _infoPill(IconData icon, String label, String value) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.grey[700]),
            const SizedBox(width: 6),
            Text(
              '$label ',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[700],
                fontWeight: FontWeight.w500,
              ),
            ),
            Flexible(
              child: Text(
                value,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      );
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);

        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final maxHeight = MediaQuery.of(ctx).size.height * 0.8;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 720,
                    maxHeight: maxHeight,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Material(
                      color: Colors.white,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 상단 헤더 바
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                            decoration: const BoxDecoration(
                              color: ResignationColors.dark,
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.visibility_outlined,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '사직서 미리보기',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '전송 전 사직서 내용을 한 번 더 확인해 주세요.',
                                        style: theme.textTheme.bodySmall?.copyWith(
                                          color: Colors.white.withOpacity(0.8),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: const Icon(
                                    Icons.close,
                                    color: Colors.white,
                                  ),
                                  tooltip: '닫기',
                                ),
                              ],
                            ),
                          ),

                          // 본문 스크롤 영역
                          Flexible(
                            child: Scrollbar(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    // 상단 요약 배지들
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: [
                                        _infoPill(
                                          Icons.calendar_today_outlined,
                                          '작성일',
                                          createdAtText,
                                        ),
                                        _infoPill(
                                          Icons.event_available_outlined,
                                          '사직 예정일',
                                          resignDateText,
                                        ),
                                        _infoPill(
                                          Icons.person_outline,
                                          '성명',
                                          signName,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),

                                    // 메일 정보 카드
                                    Container(
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFF9FAFB),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.email_outlined,
                                                size: 18,
                                                color: ResignationColors.dark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '메일 전송 정보',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: ResignationColors.dark,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          const Divider(height: 20),
                                          const SizedBox(height: 2),
                                          Text(
                                            '제목',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _mailSubjectCtrl.text,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Text(
                                            '본문 (자동 생성)',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: Colors.grey[700],
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.grey.withOpacity(0.2),
                                              ),
                                            ),
                                            child: Text(
                                              _mailBodyCtrl.text,
                                              style: theme.textTheme.bodyMedium,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // 사직 사유 카드
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.description_outlined,
                                                size: 18,
                                                color: ResignationColors.dark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '사직 사유 상세 내용',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: ResignationColors.dark,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          const Divider(height: 20),
                                          const SizedBox(height: 2),
                                          Container(
                                            width: double.infinity,
                                            padding: const EdgeInsets.all(10),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFFBFBFB),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(
                                                color: Colors.grey.withOpacity(0.2),
                                              ),
                                            ),
                                            child: Text(
                                              _contentCtrl.text.trim().isEmpty
                                                  ? '입력된 사직 사유가 없습니다.'
                                                  : _contentCtrl.text,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                height: 1.4,
                                                color: _contentCtrl.text.trim().isEmpty
                                                    ? Colors.grey[600]
                                                    : Colors.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 16),

                                    // 서명 정보 + 이미지
                                    Container(
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.grey.withOpacity(0.3),
                                        ),
                                      ),
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.edit_outlined,
                                                size: 18,
                                                color: ResignationColors.dark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '전자서명 정보',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: ResignationColors.dark,
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 8),
                                          const Divider(height: 20),
                                          const SizedBox(height: 2),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '서명자',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: Colors.grey[700],
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      signName,
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 12),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      '서명 일시',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: Colors.grey[700],
                                                        fontWeight: FontWeight.w600,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      signTimeText,
                                                      style: theme.textTheme.bodyMedium?.copyWith(
                                                        fontWeight: FontWeight.w500,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          Container(
                                            height: 140,
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(12),
                                              border: Border.all(
                                                color: Colors.grey.withOpacity(0.4),
                                              ),
                                              color: const Color(0xFFFAFAFA),
                                            ),
                                            child: _signaturePngBytes == null
                                                ? Center(
                                              child: Text(
                                                '서명 이미지가 없습니다. (전자서명 완료 후 제출할 수 있습니다.)',
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: Colors.grey[600],
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                            )
                                                : Padding(
                                              padding: const EdgeInsets.all(8),
                                              child: Image.memory(
                                                _signaturePngBytes!,
                                                fit: BoxFit.contain,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    const SizedBox(height: 12),

                                    // 원본 텍스트 안내
                                    Container(
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFEEF2FF),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Row(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.info_outline,
                                            size: 18,
                                            color: Color(0xFF4F46E5),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Text(
                                              '하단의 "텍스트 복사" 버튼을 누르면 이 미리보기 내용을 '
                                                  '텍스트 형태로 복사하여 메신저 등에 붙여넣을 수 있습니다.',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                height: 1.4,
                                                color: const Color(0xFF1F2937),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                          // 하단 액션 영역
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFAFAFA),
                              border: Border(
                                top: BorderSide(
                                  color: Colors.grey.withOpacity(0.2),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    HapticFeedback.selectionClick();
                                    await Clipboard.setData(
                                      ClipboardData(text: text),
                                    );
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(
                                        content: Text('텍스트가 클립보드에 복사되었습니다.'),
                                      ),
                                    );
                                  },
                                  icon: const Icon(Icons.copy_rounded, size: 18),
                                  label: const Text('텍스트 복사'),
                                ),
                                const SizedBox(width: 4),
                                TextButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  child: const Text('닫기'),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Future<void> _submit() async {
    // 1) 폼 필드 검증 (성명, 기타 입력 필드 등)
    if (!_formKey.currentState!.validate()) return;

    // 2) 사직 사유 유형 필수 선택
    if (_reasonType == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('사직 사유 유형(개인 사정/계약 만료/기타)을 선택해 주세요.')),
      );
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    // 3) 사직 사유 유형별 추가 검증
    if (_reasonType == ResignationReasonType.personal ||
        _reasonType == ResignationReasonType.contractEnd) {
      // 개인 사정/계약 만료 → 템플릿 문장 + 사직 예정일 필수
      if (_resignDate == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('개인 사정/계약 만료 선택 시, 사직 예정일을 선택해 주세요.')),
        );
        _pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        return;
      }
      if (_contentCtrl.text.trim().isEmpty) {
        // 이 경우는 거의 없지만 방어 로직
        setState(() => _updateTemplateContent());
      }
    } else if (_reasonType == ResignationReasonType.other) {
      // 기타 → 자유 서술 필수
      if (_contentCtrl.text.trim().isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('기타 사유 선택 시, 사직 사유를 자율적으로 입력해 주세요.')),
        );
        _pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
        return;
      }
    }

    HapticFeedback.lightImpact();
    setState(() => _sending = true);
    try {
      final cfg = await EmailConfig.load();
      if (!EmailConfig.isValidToList(cfg.to)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '수신자(To)가 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 저장해 주세요.',
            ),
          ),
        );
        return;
      }
      final toCsv = cfg.to
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(', ');

      final subject = _mailSubjectCtrl.text.trim();
      // 제출 시점 기준으로 본문 시간 강제 갱신
      _updateMailBody(force: true);
      final body = _mailBodyCtrl.text.trim();
      if (subject.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('메일 제목이 자동 생성되지 않았습니다.')),
        );
        return;
      }

      final pdfBytes = await _buildPdfBytes();
      final now = DateTime.now();
      final nameForFile =
      _nameCtrl.text.trim().isEmpty ? '무기명' : _nameCtrl.text.trim();
      final filename =
      _safeFileName('사직서_${nameForFile}_${_dateTag(now)}');

      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('메일 전송 완료')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('메일 전송 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _safeFileName(String raw) {
    final s = raw.trim().isEmpty ? '사직서' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<Uint8List> _buildPdfBytes() async {
    pw.Font? regular;
    pw.Font? bold;

    try {
      final regData =
      await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
      regular = pw.Font.ttf(regData);
    } catch (_) {}

    try {
      final boldData =
      await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
      bold = pw.Font.ttf(boldData);
    } catch (_) {
      bold = regular;
    }

    final theme = (regular != null)
        ? pw.ThemeData.withFont(
      base: regular,
      bold: bold ?? regular,
      italic: regular,
      boldItalic: bold ?? regular,
    )
        : pw.ThemeData.base();

    final doc = pw.Document();

    final dept = _deptCtrl.text.trim().isEmpty ? '-' : _deptCtrl.text.trim();
    final position =
    _positionCtrl.text.trim().isEmpty ? '-' : _positionCtrl.text.trim();
    final name = _signerName.isEmpty ? '-' : _signerName;
    final rrn = _rrnCtrl.text.trim().isEmpty ? '-' : _rrnCtrl.text.trim();
    final resignDateText =
    _resignDate == null ? '-' : _fmtDateOnly(_resignDate!);

    // 상단 간단 필드
    final fields = <MapEntry<String, String>>[
      MapEntry('성명', name),
      MapEntry('주민등록번호', rrn),
      MapEntry('직위', position),
      MapEntry('부서명', dept),
      MapEntry('사직 예정일', resignDateText),
    ];

    pw.Widget buildFieldTable() => pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(7),
      },
      children: [
        for (final kv in fields)
          pw.TableRow(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                color: PdfColors.grey200,
                child: pw.Text(
                  kv.key,
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  kv.value,
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
      ],
    );

    pw.Widget buildSection(String title, String body) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 8),
        pw.Text(
          title,
          style: pw.TextStyle(
            fontSize: 13,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            body.isEmpty ? '-' : body,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
      ],
    );

    pw.Widget buildSignature() {
      final name = _signerName.isEmpty ? '이름 미입력' : _signerName;
      final timeText =
      _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);

      return pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(height: 8),
          pw.Text(
            '전자서명',
            style: pw.TextStyle(
              fontSize: 13,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(
                child: pw.Text(
                  '서명자: $name',
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
              pw.SizedBox(width: 8),
              pw.Text(
                '서명 일시: $timeText',
                style: const pw.TextStyle(fontSize: 11),
              ),
            ],
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            height: 120,
            width: double.infinity,
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: _signaturePngBytes == null
                ? pw.Center(
              child: pw.Text(
                '서명 이미지 없음',
                style: const pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.grey,
                ),
              ),
            )
                : pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Image(
                pw.MemoryImage(_signaturePngBytes!),
                fit: pw.BoxFit.contain,
              ),
            ),
          ),
        ],
      );
    }

    doc.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
        build: (context) => [
          pw.Center(
            child: pw.Text(
              '사직서',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          buildFieldTable(),
          buildSection('[사직 사유]', _contentCtrl.text),
          buildSignature(),
        ],
        footer: (context) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '생성 시각: ${_fmtCompact(DateTime.now())}',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
        ),
      ),
    );

    return doc.save();
  }

  Future<void> _sendEmailViaGmail({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    final client = await GoogleAuthV7.authedClient(const <String>[]);
    final api = gmail.GmailApi(client);

    final boundary =
        'dart-mail-boundary-${DateTime.now().millisecondsSinceEpoch}';
    final subjectB64 = base64.encode(utf8.encode(subject));
    final sb = StringBuffer()
      ..writeln('To: $to')
      ..writeln('Subject: =?utf-8?B?$subjectB64?=')
      ..writeln('MIME-Version: 1.0')
      ..writeln('Content-Type: multipart/mixed; boundary="$boundary"')
      ..writeln()
      ..writeln('--$boundary')
      ..writeln('Content-Type: text/plain; charset="utf-8"')
      ..writeln('Content-Transfer-Encoding: 7bit')
      ..writeln()
      ..writeln(body)
      ..writeln()
      ..writeln('--$boundary')
      ..writeln('Content-Type: application/pdf; name="$filename"')
      ..writeln('Content-Disposition: attachment; filename="$filename"')
      ..writeln('Content-Transfer-Encoding: base64')
      ..writeln()
      ..writeln(base64.encode(pdfBytes))
      ..writeln('--$boundary--');

    final raw =
    base64UrlEncode(utf8.encode(sb.toString())).replaceAll('=', '');
    final msg = gmail.Message()..raw = raw;
    await api.users.messages.send(msg, 'me');
  }

  InputDecoration _inputDec({
    required String labelText,
    String? hintText,
  }) {
    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.grey),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(
          color: ResignationColors.base,
          width: 1.6,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(
        vertical: 14,
        horizontal: 12,
      ),
    );
  }

  Widget _sectionCard({
    required String title,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(12),
    EdgeInsetsGeometry? margin,
  }) {
    return Card(
      elevation: 0,
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: Colors.black12),
      ),
      color: Colors.white,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _gap(double h) => SizedBox(height: h);

  Future<void> _openSignatureDialog() async {
    HapticFeedback.selectionClick();
    final result = await showGeneralDialog<SignatureResult>(
      context: context,
      barrierLabel: '서명',
      barrierDismissible: false,
      barrierColor: Colors.black54,
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return SignatureFullScreenDialog(
          name: _signerName,
          initialDateTime: _signDateTime,
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOut,
          ),
          child: child,
        );
      },
    );

    if (result != null) {
      setState(() {
        _signaturePngBytes = result.pngBytes;
        _signDateTime = result.signDateTime;
      });
    }
  }

  // ===== 섹션별 본문 위젯들 =====

  /// 1. 기본 정보 (성명, 주민번호, 직위, 부서명)
  Widget _buildBasicInfoBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '사직서에 들어갈 기본 정보를 입력해 주세요.\n'
              '성명, 주민등록번호, 직위, 부서명은 인사/관리 부서에서 인사기록 작성 시 참고하게 됩니다.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _nameCtrl,
          focusNode: _nameNode,
          decoration: _inputDec(
            labelText: '성명 (필수)',
            hintText: '예: 홍길동',
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return '성명을 입력해 주세요.';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _rrnCtrl,
          focusNode: _rrnNode,
          decoration: _inputDec(
            labelText: '주민등록번호 (필수)',
            hintText: '예: 900101-1******',
          ),
          validator: (v) {
            if (v == null || v.trim().isEmpty) {
              return '주민등록번호를 입력해 주세요.';
            }
            return null;
          },
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _positionCtrl,
          focusNode: _positionNode,
          decoration: _inputDec(
            labelText: '직위',
            hintText: '예: 매니저, 사원',
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _deptCtrl,
          focusNode: _deptNode,
          decoration: _inputDec(
            labelText: '부서명',
            hintText: '예: 콜센터팀, 운영팀',
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '※ 위 정보는 PDF 사직서 및 메일에 함께 기재됩니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Colors.black54,
          ),
        ),
      ],
    );
  }

  /// 2. 사직 사유 (유형 선택 + 템플릿 문장/자유 서술)
  Widget _buildWorkContentBody() {
    final theme = Theme.of(context);

    Widget reasonButton(ResignationReasonType type, String label) {
      final isSelected = _reasonType == type;
      return Expanded(
        child: ElevatedButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() {
              _reasonType = type;
              if (type == ResignationReasonType.personal ||
                  type == ResignationReasonType.contractEnd) {
                // 템플릿 모드 → 자동 문장 생성
                _updateTemplateContent();
              } else if (type == ResignationReasonType.other) {
                // 기타 → 자유 서술, 기존 텍스트 유지 (필요 시 주석 해제하여 초기화 가능)
                // _contentCtrl.clear();
              }
            });
          },
          style: isSelected
              ? ResignationButtonStyles.primary()
              : ResignationButtonStyles.outlined(),
          child: Text(label),
        ),
      );
    }

    final isTemplateType = _reasonType == ResignationReasonType.personal ||
        _reasonType == ResignationReasonType.contractEnd;

    final templateSentence =
    isTemplateType ? _buildTemplateReasonSentence() : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '사직 사유 유형을 선택해 주세요.\n'
              '개인 사정/계약 만료 선택 시, 아래 문장이 자동으로 생성되며 년/월/일을 선택해 삽입합니다.\n'
              '기타를 선택한 경우, 자유롭게 사직 사유를 서술할 수 있습니다.',
          style: theme.textTheme.bodyMedium?.copyWith(
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            reasonButton(ResignationReasonType.personal, '개인 사정'),
            const SizedBox(width: 8),
            reasonButton(ResignationReasonType.contractEnd, '계약 만료'),
            const SizedBox(width: 8),
            reasonButton(ResignationReasonType.other, '기타'),
          ],
        ),
        const SizedBox(height: 12),

        if (_reasonType == null) ...[
          Text(
            '※ 사직 사유 유형을 먼저 선택해 주세요.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black54,
            ),
          ),
        ] else if (isTemplateType) ...[
          // 개인 사정 / 계약 만료 → 날짜 선택 + 템플릿 문장
          Text(
            '사직 예정일 선택 (년/월/일)',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickResignDate,
                  icon: const Icon(Icons.event_outlined),
                  label: Text(
                    _resignDate == null
                        ? '사직 예정일 선택'
                        : _fmtDateOnly(_resignDate!),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '※ 선택한 사직 예정일은 아래 문장 및 PDF/메일에도 함께 반영됩니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '자동 생성 문장',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFBFBFB),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: Colors.grey.withOpacity(0.2),
              ),
            ),
            child: Text(
              templateSentence,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.4,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '원문 형식:\n'
                '상기 본인은 (개인 사정/계약 만료) 으로 (  )년 (  )월 (  )일부로 사직하고자 하오니 재가하여 주시기 바랍니다.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.black54,
              height: 1.4,
            ),
          ),
        ] else if (_reasonType == ResignationReasonType.other) ...[
          // 기타 → 자유 서술 (필수)
          TextFormField(
            key: _contentFieldKey,
            controller: _contentCtrl,
            focusNode: _contentNode,
            decoration: _inputDec(
              labelText: '사직 사유 (기타, 자율 서술 / 필수)',
              hintText: '예)\n'
                  '- 사직을 결정하게 된 배경\n'
                  '- 이직/개인 사유/건강 상의 이유 등 구체적 내용\n'
                  '- 인수인계 계획 및 담당자 등',
            ),
            keyboardType: TextInputType.multiline,
            minLines: 8,
            maxLines: 16,
            onTap: () {
              Future.delayed(const Duration(milliseconds: 150), () {
                final ctx = _contentFieldKey.currentContext;
                if (ctx != null) {
                  Scrollable.ensureVisible(
                    ctx,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                }
              });
            },
            validator: (v) {
              if (_reasonType == ResignationReasonType.other) {
                if (v == null || v.trim().isEmpty) {
                  return '기타 사유 선택 시, 사직 사유를 입력해 주세요.';
                }
              }
              return null;
            },
          ),
        ],
      ],
    );
  }

  /// 3. 메일 제목/본문
  Widget _buildMailBody() {
    return Column(
      children: [
        TextFormField(
          controller: _mailSubjectCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: _inputDec(
            labelText: '메일 제목(자동 생성)',
            hintText: '예: 콜센터 사직서 제출 – 2025년 11월 26일자',
          ),
          validator: (v) =>
          (v == null || v.trim().isNotEmpty)
              ? null
              : '메일 제목이 자동 생성되지 않았습니다.',
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _mailBodyCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: _inputDec(
            labelText: '메일 본문(자동 생성)',
            hintText: '사직 예정일 및 작성 시각 정보가 자동으로 입력됩니다.',
          ),
          minLines: 3,
          maxLines: 8,
        ),
      ],
    );
  }

  /// 4. 전자서명
  Widget _buildSignatureBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 12,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Wrap(
            spacing: 16,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.person_outline, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '서명자: ${_signerName.isEmpty ? "이름 미입력" : _signerName}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.access_time, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '서명 일시: ${_signDateTime == null ? "저장 시 자동" : _fmtCompact(_signDateTime!)}',
                    style: const TextStyle(
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _openSignatureDialog,
                icon: const Icon(Icons.border_color),
                label: const Text('서명하기'),
                style: ResignationButtonStyles.smallPrimary(),
              ),
              if (_signaturePngBytes != null)
                OutlinedButton.icon(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    setState(() {
                      _signaturePngBytes = null;
                      _signDateTime = null;
                    });
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('서명 삭제'),
                  style: ResignationButtonStyles.smallOutlined(),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_signaturePngBytes != null)
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: Colors.black12),
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Image.memory(
                    _signaturePngBytes!,
                    height: 120,
                    fit: BoxFit.contain,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// 공통 페이지 래퍼: 문서 헤더 + 안내문 + 섹션 카드 + 하단 (초기화/미리보기)
  Widget _buildReportPage({
    required String sectionTitle,
    required Widget sectionBody,
  }) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scrollbar(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(
          16,
          16,
          16,
          16 + bottomInset, // 키보드 높이만큼 추가 패딩
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 상단 문서 헤더
                Text(
                  '사직서',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'RESIGNATION LETTER',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.black54,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 16),

                // 실제 "종이" 느낌의 신청서 카드
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: ResignationColors.light.withOpacity(0.8),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // 상단 메타 정보 라인
                      Row(
                        children: [
                          const Icon(
                            Icons.edit_note_rounded,
                            size: 22,
                            color: ResignationColors.dark,
                          ),
                          const SizedBox(width: 8),
                          // 오버플로우 방지를 위해 제목을 Expanded + ellipsis 처리
                          Expanded(
                            child: Text(
                              '사직서 양식',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: ResignationColors.dark,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '작성일 ${_fmtCompact(DateTime.now())}',
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Divider(height: 24),
                      const SizedBox(height: 4),

                      // 안내 문구
                      Container(
                        decoration: BoxDecoration(
                          color: ResignationColors.light.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: ResignationColors.light.withOpacity(0.8),
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: ResignationColors.dark,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '성명/주민등록번호/직위/부서명, 사직 사유 유형, 사직 예정일 및 전자서명 정보를 사실에 근거하여 작성해 주세요.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                  height: 1.4,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      _gap(20),

                      // 섹션 카드 (한 페이지당 하나만)
                      _sectionCard(
                        title: sectionTitle,
                        margin: const EdgeInsets.only(bottom: 0),
                        child: sectionBody,
                      ),

                      _gap(12),

                      // 하단 보조 액션 (초기화 / 미리보기)
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _sending ? null : _reset,
                              icon: const Icon(Icons.refresh_outlined),
                              label: const Text('초기화'),
                              style: ResignationButtonStyles.outlined(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _sending ? null : _showPreview,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('미리보기'),
                              style: ResignationButtonStyles.primary(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      // 바깥 배경
      backgroundColor: const Color(0xFFEFF3F6),
      appBar: AppBar(
        title: const Text('사직서 작성'),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: const Border(
          bottom: BorderSide(color: Colors.black12, width: 1),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: _showPreview,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('미리보기'),
              style: ResignationButtonStyles.smallPrimary(),
            ),
          ),
        ],
      ),
      // 전자서명(인덱스 3) 페이지만 제출 버튼 노출 + 서명 전에는 비활성화
      bottomNavigationBar: _currentPageIndex == 3
          ? SafeArea(
        top: false,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 10,
            bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.black12, width: 1),
            ),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              // ✅ 서명 전에는 비활성화, 서명 완료 후에만 활성화
              onPressed: (!_sending && _signaturePngBytes != null)
                  ? _submit
                  : null,
              icon: _sending
                  ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor:
                  AlwaysStoppedAnimation<Color>(Colors.black),
                ),
              )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _sending ? '전송 중…' : '제출',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: ResignationButtonStyles.primary(),
            ),
          ),
        ),
      )
          : null,
      body: SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: PageView(
            controller: _pageController,
            onPageChanged: (index) {
              setState(() {
                _currentPageIndex = index;
              });
            },
            children: [
              _buildReportPage(
                sectionTitle: '1. 기본 정보 (성명/주민등록번호/직위/부서명)',
                sectionBody: _buildBasicInfoBody(),
              ),
              _buildReportPage(
                sectionTitle: '2. 사직 사유 선택 및 문장',
                sectionBody: _buildWorkContentBody(),
              ),
              _buildReportPage(
                sectionTitle: '3. 메일 전송 내용',
                sectionBody: _buildMailBody(),
              ),
              _buildReportPage(
                sectionTitle: '4. 전자서명',
                sectionBody: _buildSignatureBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
