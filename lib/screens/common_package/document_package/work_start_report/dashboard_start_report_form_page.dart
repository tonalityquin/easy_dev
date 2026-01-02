// lib/screens/simple_package/simple_inside_package/sections/simple_inside_report_form_page.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../../../utils/google_auth_v7.dart';
import '../../../../../../../utils/api/email_config.dart';
import 'dashboard_start_report_styles.dart';
import 'dashboard_start_report_signature_dialog.dart';

class DashboardStartReportFormPage extends StatefulWidget {
  const DashboardStartReportFormPage({super.key});

  @override
  State<DashboardStartReportFormPage> createState() => _DashboardStartReportFormPageState();
}

class _DashboardStartReportFormPageState extends State<DashboardStartReportFormPage> {
  final _formKey = GlobalKey<FormState>();

  // 기존 기본 정보 컨트롤러 (현재 UI에서는 사용하지 않지만, 향후 확장 고려해 유지)
  final _deptCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();

  final _contentCtrl = TextEditingController();

  final _mailSubjectCtrl = TextEditingController();
  final _mailBodyCtrl = TextEditingController();

  final _deptNode = FocusNode();
  final _nameNode = FocusNode();
  final _positionNode = FocusNode();
  final _contentNode = FocusNode();

  Uint8List? _signaturePngBytes;
  DateTime? _signDateTime;

  // 특이사항 여부: null = 미선택, true = 있음, false = 없음
  bool? _hasSpecialNote;

  // SharedPreferences에서 불러오는 선택 영역 (업무명)
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
    _nameCtrl.addListener(() => setState(() {}));
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
    _contentCtrl.dispose();
    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();

    _deptNode.dispose();
    _nameNode.dispose();
    _positionNode.dispose();
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
    _contentCtrl.clear();
    _mailSubjectCtrl.clear();
    _mailBodyCtrl.clear();
    setState(() {
      _signaturePngBytes = null;
      _signDateTime = null;
      _hasSpecialNote = null;
      // _selectedArea는 SharedPreferences 기반 설정 값이라 초기화하지 않고 유지
      _currentPageIndex = 0;
    });
    // 리셋 후에도 제목/본문은 기본값으로 자동 생성
    _updateMailSubject();
    _updateMailBody(force: true);
    // 페이지도 첫 페이지로
    _pageController.jumpToPage(0);
  }

  /// 특이사항 선택 값 + SharedPreferences 선택 영역에 따라 메일 제목 자동 생성
  void _updateMailSubject() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    // 특이사항 여부 텍스트
    String suffixSpecial = '';
    if (_hasSpecialNote != null) {
      suffixSpecial = _hasSpecialNote! ? ' - 특이사항 있음' : ' - 특이사항 없음';
    }

    // SharedPreferences에 저장된 selectedArea 사용 (없으면 '업무' 기본값)
    final area = (_selectedArea != null && _selectedArea!.trim().isNotEmpty) ? _selectedArea!.trim() : '업무';

    // 예: 콜센터 업무 시작 보고서 – 11월 25일자 - 특이사항 있음
    _mailSubjectCtrl.text = '$area 업무 시작 보고서 – ${month}월 ${day}일자$suffixSpecial';
  }

  /// 메일 본문 자동 생성 (작성 일시 포함)
  void _updateMailBody({bool force = false}) {
    if (!force && _mailBodyCtrl.text.trim().isNotEmpty) return;
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final d = now.day;
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    _mailBodyCtrl.text = '본 보고서는 ${y}년 ${m}월 ${d}일 ${hh}시 ${mm}분 기준으로 작성된 업무 시작 보고서입니다.';
  }

  String _buildPreviewText(BuildContext context) {
    final signInfo = (_signaturePngBytes != null)
        ? '전자서명: ${_signerName.isEmpty ? "(이름 미입력)" : _signerName} / '
            '${_signDateTime != null ? _fmtCompact(_signDateTime!) : "저장 시각 미기록"}'
        : '전자서명: (미첨부)';

    final specialText = _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');

    return [
      '— 업무 시작 보고서 —',
      '',
      '특이사항: $specialText',
      '',
      '[업무 내용]',
      _contentCtrl.text,
      '',
      signInfo,
      '작성일: ${_fmtDT(context, DateTime.now())}',
      '',
      '※ 메일 제목: ${_mailSubjectCtrl.text}',
      '※ 메일 본문: ${_mailBodyCtrl.text}',
    ].join('\n');
  }

  Future<void> _showPreview() async {
    HapticFeedback.lightImpact();
    _updateMailBody(); // 미리보기 전에 본문이 비어있으면 자동 생성
    final text = _buildPreviewText(context);

    // 화면에 보여줄 데이터들 다시 계산
    final specialText = _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');
    final signName = _signerName.isEmpty ? '이름 미입력' : _signerName;
    final signTimeText = _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);
    final createdAtText = _fmtDT(context, DateTime.now());

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
                              color: DashboardReportColors.dark,
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
                                        '업무 시작 보고서 미리보기',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '전송 전 보고서 내용을 한 번 더 확인해 주세요.',
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
                                          Icons.label_important_outline,
                                          '특이사항',
                                          specialText,
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
                                                color: DashboardReportColors.dark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '메일 전송 정보',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: DashboardReportColors.dark,
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

                                    // 특이 사항(업무 내용) 카드
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
                                                Icons.report_problem_outlined,
                                                size: 18,
                                                color: DashboardReportColors.dark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '특이 사항 상세 내용',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: DashboardReportColors.dark,
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
                                              _contentCtrl.text.trim().isEmpty ? '입력된 특이 사항이 없습니다.' : _contentCtrl.text,
                                              style: theme.textTheme.bodyMedium?.copyWith(
                                                height: 1.4,
                                                color:
                                                    _contentCtrl.text.trim().isEmpty ? Colors.grey[600] : Colors.black,
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
                                                color: DashboardReportColors.dark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '전자서명 정보',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: DashboardReportColors.dark,
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
                                    await Clipboard.setData(ClipboardData(text: text));
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
    // 1) 폼 필드 검증 (업무 내용 등)
    if (!_formKey.currentState!.validate()) return;

    // 2) 특이사항 여부 필수 선택
    if (_hasSpecialNote == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('특이사항 여부를 선택해 주세요.')),
      );
      // 자동으로 첫 페이지로 이동해 줘도 UX 좋음
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
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
      final toCsv = cfg.to.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');

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
      final nameForFile = _nameCtrl.text.trim().isEmpty ? '무기명' : _nameCtrl.text.trim();
      final filename = _safeFileName('업무시작보고서_${nameForFile}_${_dateTag(now)}');

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
    final s = raw.trim().isEmpty ? '업무시작보고서' : raw.trim();
    return s.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<Uint8List> _buildPdfBytes() async {
    pw.Font? regular;
    pw.Font? bold;

    try {
      final regData = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
      regular = pw.Font.ttf(regData);
    } catch (_) {}

    try {
      final boldData = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
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

    final specialText = _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');

    // 상단 간단 필드: 특이사항
    final fields = <MapEntry<String, String>>[
      MapEntry('특이사항', specialText),
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
      final timeText = _signDateTime == null ? '서명 전' : _fmtCompact(_signDateTime!);

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
              '업무 시작 보고서',
              style: pw.TextStyle(
                fontSize: 20,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.SizedBox(height: 12),
          buildFieldTable(),
          buildSection('[업무 내용]', _contentCtrl.text),
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

    final boundary = 'dart-mail-boundary-${DateTime.now().millisecondsSinceEpoch}';
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

    final raw = base64UrlEncode(utf8.encode(sb.toString())).replaceAll('=', '');
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
          color: DashboardReportColors.base,
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

  Widget _buildSpecialNoteBody() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘 업무 진행 중 특이사항이 있었는지 선택해 주세요.\n'
          '(예: 장애, 클레임, 일정 지연, 긴급 지원 등)',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.4,
              ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _hasSpecialNote = false;
                    _updateMailSubject();
                  });
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                },
                style: _hasSpecialNote == false
                    ? DashboardReportButtonStyles.primary()
                    : DashboardReportButtonStyles.outlined(),
                child: const Text('특이사항 없음'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  setState(() {
                    _hasSpecialNote = true;
                    _updateMailSubject();
                  });
                  _pageController.nextPage(
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOut,
                  );
                },
                style: _hasSpecialNote == true
                    ? DashboardReportButtonStyles.primary()
                    : DashboardReportButtonStyles.outlined(),
                child: const Text('특이사항 있음'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '※ 선택 결과는 메일 제목에 자동으로 반영되며, 다음 항목으로 자동 이동합니다.',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.black54,
              ),
        ),
      ],
    );
  }

  Widget _buildWorkContentBody() {
    return TextFormField(
      key: _contentFieldKey,
      controller: _contentCtrl,
      focusNode: _contentNode,
      decoration: _inputDec(
        labelText: '특이 사항',
        hintText: '예)\n'
            '- 육하원칙에 맞춰서 작성하세요.\n'
            '- 컴플레인, 사고, 인사 갈등, 고객사와의 소통 발생 여부 및 내용\n'
            '- 업무 프로세스, 업무 환경, 물품 파손 등 문제\n'
            '- 발생 과정 및 조치 사항\n',
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
        // ✅ 특이사항 "있음"인 경우에만 필수 입력
        if (_hasSpecialNote == true) {
          if (v == null || v.trim().isEmpty) {
            return '업무 내용을 입력하세요.';
          }
        }
        // 특이사항 없음(false) 또는 미선택(null)인 경우는 선택 입력으로 처리
        return null;
      },
    );
  }

  Widget _buildMailBody() {
    return Column(
      children: [
        TextFormField(
          controller: _mailSubjectCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: _inputDec(
            labelText: '메일 제목(자동 생성)',
            hintText: '예: 콜센터 업무 시작 보고서 – 11월 25일자 - 특이사항 있음',
          ),
          validator: (v) => (v == null || v.trim().isEmpty) ? '메일 제목이 자동 생성되지 않았습니다.' : null,
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: _mailBodyCtrl,
          readOnly: true,
          enableInteractiveSelection: true,
          decoration: _inputDec(
            labelText: '메일 본문(자동 생성)',
            hintText: '작성 시각 정보가 자동으로 입력됩니다.',
          ),
          minLines: 3,
          maxLines: 8,
        ),
      ],
    );
  }

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
                style: DashboardReportButtonStyles.smallPrimary(),
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
                  style: DashboardReportButtonStyles.smallOutlined(),
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
                  '업무 시작 보고서',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: 4,
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  'WORK START REPORT',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Colors.black54,
                        letterSpacing: 3,
                      ),
                ),
                const SizedBox(height: 16),

                // 실제 "종이" 느낌의 보고서 카드
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: DashboardReportColors.light.withOpacity(0.8),
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
                            color: DashboardReportColors.dark,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '업무 시작 보고서 양식',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: DashboardReportColors.dark,
                                ),
                          ),
                          const Spacer(),
                          Text(
                            '작성일 ${_fmtCompact(DateTime.now())}',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                          color: DashboardReportColors.light.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: DashboardReportColors.light.withOpacity(0.8),
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: DashboardReportColors.dark,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '해당 업무의 수행 내용과 결과를 사실에 근거하여 간결하게 작성해 주세요.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
                              style: DashboardReportButtonStyles.outlined(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _sending ? null : _showPreview,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('미리보기'),
                              style: DashboardReportButtonStyles.primary(),
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
        title: const Text('업무 시작 보고서 작성'),
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
              style: DashboardReportButtonStyles.smallPrimary(),
            ),
          ),
        ],
      ),
      // 👉 4. 전자서명(인덱스 3) 페이지만 제출 버튼 노출 + 서명 전에는 비활성화
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
                    onPressed: (!_sending && _signaturePngBytes != null) ? _submit : null,
                    icon: _sending
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                            ),
                          )
                        : const Icon(Icons.send_outlined),
                    label: Text(
                      _sending ? '전송 중…' : '제출',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: DashboardReportButtonStyles.primary(),
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

                // 첫 페이지로 다시 돌아오면 특이사항 선택 초기화
                if (index == 0) {
                  _hasSpecialNote = null;
                  _updateMailSubject();
                }
              });
            },
            children: [
              _buildReportPage(
                sectionTitle: '1. 특이사항 여부 (필수)',
                sectionBody: _buildSpecialNoteBody(),
              ),
              _buildReportPage(
                sectionTitle: '2. 특이 사항 (조건부 필수)',
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
