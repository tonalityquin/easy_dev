import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../utils/google_auth_v7.dart';
import '../../../../../utils/api/email_config.dart';
import 'simple_inside_report_styles.dart';
import 'simple_inside_report_signature_dialog.dart';

class SimpleInsideEndReportFormPage extends StatefulWidget {
  const SimpleInsideEndReportFormPage({super.key});

  @override
  State<SimpleInsideEndReportFormPage> createState() => _SimpleInsideEndReportFormPageState();
}

/// ─────────────────────────────────────────────────────────────
/// [요구사항 반영] Firestore 조회(get/query) 없음.
/// - insert(set/merge)만 수행하여 end_work_reports 스키마에 맞게 저장.
/// - [추가 요구사항] 월 샤딩(months/yyyyMM/reports/yyyy-MM-dd) 구조로 저장
/// - [추가 요구사항] 동일 batch 내 3개 문서 원자 upsert
/// ─────────────────────────────────────────────────────────────
class _SimpleInsideEndReportFormPageState extends State<SimpleInsideEndReportFormPage> {
  final _formKey = GlobalKey<FormState>();

  // 기본 정보 컨트롤러(확장 대비 유지)
  final _deptCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();

  final _contentCtrl = TextEditingController();
  final _vehicleCountCtrl = TextEditingController(); // 차량 대수 입력

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

  // SharedPreferences에서 불러오는 선택 영역(업무명/area로도 사용)
  String? _selectedArea;

  // SharedPreferences에서 불러오는 division (Dashboard 업로드 스키마와 동일 필드로 저장용)
  String? _divisionFromPrefs;

  String get _signerName => _nameCtrl.text.trim();

  bool _sending = false; // 최종 메일 제출 중 여부

  // 1차 제출(서버 저장) 상태: Dashboard와 동일한 게이트 로직
  bool _firstSubmitting = false;
  bool _firstSubmittedCompleted = false;

  // 차량 대수 입력 유효 여부(1차 제출 버튼 enable)
  bool _isVehicleCountValid = false;

  // 페이지 컨트롤러 (섹션별 좌우 스와이프)
  final PageController _pageController = PageController();

  // 현재 페이지 인덱스 (0~4)
  int _currentPageIndex = 0;

  // 키보드 가림 방지용 키
  final GlobalKey _vehicleFieldKey = GlobalKey();
  final GlobalKey _contentFieldKey = GlobalKey();

  // Firestore (write only)
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  @override
  void initState() {
    super.initState();

    _nameCtrl.addListener(() => setState(() {}));

    // Dashboard와 동일하게: 입력 변경 시 유효성 + 제목 업데이트
    _vehicleCountCtrl.addListener(_onVehicleCountChanged);

    _updateMailBody(); // 메일 본문 자동 생성
    _loadSelectedArea();
    _loadDivision();
  }

  Future<void> _loadSelectedArea() async {
    final prefs = await SharedPreferences.getInstance();
    final area = prefs.getString('selectedArea') ?? '';
    if (!mounted) return;
    setState(() {
      _selectedArea = area.trim().isEmpty ? null : area.trim();
    });

    // 사용자가 아직 제목을 입력하지 않은 경우에만 자동 채움
    if (_mailSubjectCtrl.text.trim().isEmpty) {
      _updateMailSubject();
    }
  }

  Future<void> _loadDivision() async {
    // 기존 통계 페이지에서 사용하던 키와 동일하게 'division' 사용
    final prefs = await SharedPreferences.getInstance();
    final div = (prefs.getString('division') ?? '').trim();
    if (!mounted) return;
    setState(() {
      _divisionFromPrefs = div.isEmpty ? null : div;
    });
  }

  @override
  void dispose() {
    _deptCtrl.dispose();
    _nameCtrl.dispose();
    _positionCtrl.dispose();
    _contentCtrl.dispose();
    _vehicleCountCtrl.dispose();
    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();

    _deptNode.dispose();
    _nameNode.dispose();
    _positionNode.dispose();
    _contentNode.dispose();

    _pageController.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
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
    _vehicleCountCtrl.clear();
    _mailSubjectCtrl.clear();
    _mailBodyCtrl.clear();

    setState(() {
      _signaturePngBytes = null;
      _signDateTime = null;
      _hasSpecialNote = null;

      _currentPageIndex = 0;

      _firstSubmitting = false;
      _firstSubmittedCompleted = false;
      _isVehicleCountValid = false;
      // _selectedArea는 prefs 기반이라 유지
    });

    _updateMailSubject();
    _updateMailBody(force: true);

    _pageController.jumpToPage(0);
  }

  /// 특이사항 선택 값 + selectedArea + 차량 대수 → 메일 제목 자동 생성
  void _updateMailSubject() {
    final now = DateTime.now();
    final month = now.month;
    final day = now.day;

    String suffixSpecial = '';
    if (_hasSpecialNote != null) {
      suffixSpecial = _hasSpecialNote! ? ' - 특이사항 있음' : ' - 특이사항 없음';
    }

    String vehiclePart = '';
    final vehicleRaw = _vehicleCountCtrl.text.trim();
    if (vehicleRaw.isNotEmpty) {
      final count = int.tryParse(vehicleRaw);
      if (count != null) {
        vehiclePart = ' ${count}대';
      }
    }

    final area = (_selectedArea != null && _selectedArea!.trim().isNotEmpty) ? _selectedArea!.trim() : '업무';

    _mailSubjectCtrl.text = '$area 업무 종료 보고서 – ${month}월 ${day}일자$vehiclePart$suffixSpecial';
  }

  /// 메일 본문 자동 생성(작성 일시 포함)
  void _updateMailBody({bool force = false}) {
    if (!force && _mailBodyCtrl.text.trim().isNotEmpty) return;
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final d = now.day;
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    _mailBodyCtrl.text = '본 보고서는 ${y}년 ${m}월 ${d}일 ${hh}시 ${mm}분 기준으로 작성된 업무 종료 보고서입니다.';
  }

  /// Dashboard와 동일: 차량 입력 변경 시 유효성 상태 + 제목 업데이트
  void _onVehicleCountChanged() {
    final raw = _vehicleCountCtrl.text.trim();
    final isValid = raw.isNotEmpty && RegExp(r'^\d+$').hasMatch(raw);
    if (_isVehicleCountValid != isValid) {
      setState(() => _isVehicleCountValid = isValid);
    }
    _updateMailSubject();
  }

  String _buildPreviewText(BuildContext context) {
    final signInfo = (_signaturePngBytes != null)
        ? '전자서명: ${_signerName.isEmpty ? "(이름 미입력)" : _signerName} / '
        '${_signDateTime != null ? _fmtCompact(_signDateTime!) : "저장 시각 미기록"}'
        : '전자서명: (미첨부)';

    final specialText = _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');

    final vehicleRaw = _vehicleCountCtrl.text.trim();
    final vehicleText = vehicleRaw.isEmpty ? '입력 안 됨' : '$vehicleRaw대';

    return [
      '— 업무 종료 보고서 —',
      '',
      '특이사항: $specialText',
      '일일 차량 입고 대수: $vehicleText',
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
    _updateMailBody();
    final text = _buildPreviewText(context);

    final specialText = _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');
    final vehicleRaw = _vehicleCountCtrl.text.trim();
    final vehicleText = vehicleRaw.isEmpty ? '입력 안 됨' : '$vehicleRaw대';
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
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                            decoration: const BoxDecoration(
                              color: SimpleReportColors.dark,
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
                                        '업무 종료 보고서 미리보기',
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
                          Flexible(
                            child: Scrollbar(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
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
                                        _infoPill(
                                          Icons.directions_car_outlined,
                                          '일일 차량 입고 대수',
                                          vehicleText,
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
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
                                                color: SimpleReportColors.dark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '메일 전송 정보',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: SimpleReportColors.dark,
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
                                                color: SimpleReportColors.dark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '특이 사항 상세 내용',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: SimpleReportColors.dark,
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
                                                color: _contentCtrl.text.trim().isEmpty ? Colors.grey[600] : Colors.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 16),
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
                                                color: SimpleReportColors.dark,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                '전자서명 정보',
                                                style: theme.textTheme.bodyMedium?.copyWith(
                                                  fontWeight: FontWeight.w600,
                                                  color: SimpleReportColors.dark,
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

  // ─────────────────────────────────────────────────────────────
  // [추가] Dashboard와 동일 UX: 15초 취소 가능 블로킹 다이얼로그
  // ─────────────────────────────────────────────────────────────
  Future<bool> _showDurationBlockingDialog({
    required BuildContext context,
    required String message,
    required Duration duration,
  }) async {
    return (await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _DurationBlockingDialog(
          message: message,
          duration: duration,
        );
      },
    )) ??
        false;
  }

  // ─────────────────────────────────────────────────────────────
  // [추가] Dashboard와 동일 UX: 작업 수행 중 블로킹 다이얼로그
  // ─────────────────────────────────────────────────────────────
  Future<void> _runWithBlockingDialog({
    required BuildContext context,
    required String message,
    required Future<void> Function() task,
  }) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BlockingProgressDialog(message: message),
    );

    try {
      await task();
    } finally {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
    }
  }

  // ─────────────────────────────────────────────────────────────
  // [핵심] 2단계 "1차 제출" (Firestore write only)
  //
  // 요구사항 반영:
  //  1) 월 샤딩 저장:
  //     end_work_reports/area_<area>/months/<yyyyMM>/reports/<yyyy-MM-dd>
  //     history는 일별 report 문서 필드로 유지(arrayUnion)
  //  2) 메타 문서 upsert:
  //     동일 batch에
  //       - end_work_reports/area_<area>
  //       - end_work_reports/area_<area>/months/<yyyyMM>
  //       - end_work_reports/area_<area>/months/<yyyyMM>/reports/<yyyy-MM-dd>
  //     를 원자적으로 commit
  //  3) monthKey(yyyyMM) 추가:
  //     DateFormat('yyyyMM').format(now)
  //     일별 report 문서에도 monthKey 저장
  //  4) 레거시 dot-path 저장 제거:
  //     reports.<dateStr>.* payload 구성 삭제
  // ─────────────────────────────────────────────────────────────
  Future<void> _submitFirstEndReport() async {
    if (_firstSubmitting) return;

    final raw = _vehicleCountCtrl.text.trim();
    if (raw.isEmpty) {
      _showSnack('일일 차량 입고 대수를 입력해 주세요.');
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(raw)) {
      _showSnack('일일 차량 입고 대수에는 숫자만 입력해 주세요.');
      return;
    }

    final area = (_selectedArea ?? '').trim();
    final division = (_divisionFromPrefs ?? '').trim();
    final userName = (_nameCtrl.text.trim().isEmpty) ? '무기명' : _nameCtrl.text.trim();

    if (area.isEmpty) {
      _showSnack('업무(Area) 정보가 없습니다. 설정에서 selectedArea를 저장해 주세요.');
      return;
    }
    if (division.isEmpty) {
      _showSnack('division 정보가 없습니다. SharedPreferences에 division을 저장해 주세요.');
      return;
    }

    HapticFeedback.lightImpact();

    final proceed = await _showDurationBlockingDialog(
      context: context,
      message: '일일 차량 입고 대수를 기준으로 1차 업무 종료 보고를 저장합니다.\n'
          '약 15초 후 자동 진행되며, 취소하려면 아래 [취소] 버튼을 눌러 주세요.\n'
          '중간에 화면을 이탈하지 마세요.',
      duration: const Duration(seconds: 15),
    );

    if (!proceed) {
      _showSnack('1차 업무 종료 보고가 취소되었습니다.');
      return;
    }

    setState(() => _firstSubmitting = true);

    try {
      final vehicleInputCount = int.parse(raw);

      // 조회 금지 요건으로 인해 계산/스냅샷 값은 0으로 저장
      final vehicleOutputManual = 0;
      const snapshotLockedVehicleCount = 0;
      const snapshotTotalLockedFee = 0;

      final now = DateTime.now();

      // yyyy-MM-dd (일별 doc id)
      final dateStr = DateFormat('yyyy-MM-dd').format(now);

      // yyyyMM (월 샤딩 key)
      final monthKey = DateFormat('yyyyMM').format(now);

      final createdAtIso = now.toIso8601String();

      // refs
      final areaRef = _firestore.collection('end_work_reports').doc('area_$area');
      final monthRef = areaRef.collection('months').doc(monthKey);
      final reportRef = monthRef.collection('reports').doc(dateStr);

      // history entry (일별 report 문서 필드)
      final historyEntry = <String, dynamic>{
        'date': dateStr,
        'monthKey': monthKey,
        'createdAt': createdAtIso,
        'uploadedBy': userName,
        'vehicleCount': <String, dynamic>{
          'vehicleInput': vehicleInputCount,
          'vehicleOutput': vehicleOutputManual,
        },
        'metrics': <String, dynamic>{
          'snapshot_lockedVehicleCount': snapshotLockedVehicleCount,
          'snapshot_totalLockedFee': snapshotTotalLockedFee,
        },
      };

      // 1) area meta upsert
      final areaMetaPayload = <String, dynamic>{
        'division': division,
        'area': area,
        'updatedAt': createdAtIso,
        'lastReportDate': dateStr,
        'lastMonthKey': monthKey,
      };

      // 2) month meta upsert
      final monthMetaPayload = <String, dynamic>{
        'division': division,
        'area': area,
        'monthKey': monthKey,
        'updatedAt': createdAtIso,
        'lastReportDate': dateStr,
      };

      // 3) daily report upsert (신규 문서 기반 payload)
      final dailyReportPayload = <String, dynamic>{
        'division': division,
        'area': area,
        'date': dateStr,
        'monthKey': monthKey,
        'vehicleCount': <String, dynamic>{
          'vehicleInput': vehicleInputCount,
          'vehicleOutput': vehicleOutputManual,
        },
        'metrics': <String, dynamic>{
          'snapshot_lockedVehicleCount': snapshotLockedVehicleCount,
          'snapshot_totalLockedFee': snapshotTotalLockedFee,
        },
        'createdAt': createdAtIso,
        'uploadedBy': userName,

        // history는 "일별 report 문서"의 필드로 유지
        'history': FieldValue.arrayUnion(<Map<String, dynamic>>[historyEntry]),
      };

      await _runWithBlockingDialog(
        context: context,
        message: '1차 업무 종료 보고를 저장 중입니다. 잠시만 기다려 주세요...',
        task: () async {
          final batch = _firestore.batch();

          batch.set(areaRef, areaMetaPayload, SetOptions(merge: true));
          batch.set(monthRef, monthMetaPayload, SetOptions(merge: true));
          batch.set(reportRef, dailyReportPayload, SetOptions(merge: true));

          await batch.commit();
        },
      );

      if (!mounted) return;

      setState(() {
        _firstSubmittedCompleted = true;
      });

      _showSnack(
        [
          '1차 업무 종료 보고 저장 완료',
          '• area: $area',
          '• division: $division',
          '• monthKey: $monthKey',
          '• 저장 경로: end_work_reports/area_$area/months/$monthKey/reports/$dateStr',
          '• 서버 저장 입고 대수(vehicleInput): ${vehicleInputCount}대',
          '• 서버 저장 출고 대수(vehicleOutput): ${vehicleOutputManual}대 (조회 없음 → 0)',
          '• metrics 스냅샷: ${snapshotLockedVehicleCount} / ${snapshotTotalLockedFee} (조회 없음 → 0)',
        ].join('\n'),
      );
    } catch (e) {
      _showSnack('1차 업무 종료 보고 저장 중 오류: $e');
    } finally {
      if (mounted) setState(() => _firstSubmitting = false);
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 최종 제출(메일 전송) - 기존 로직 유지
  // ─────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_hasSpecialNote == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('특이사항 여부를 선택해 주세요.')),
      );
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
      final filename = _safeFileName('업무종료보고서_${nameForFile}_${_dateTag(now)}');

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
    final s = raw.trim().isEmpty ? '업무종료보고서' : raw.trim();
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

    final vehicleRaw = _vehicleCountCtrl.text.trim();
    final vehicleText = vehicleRaw.isEmpty ? '입력 안 됨' : '$vehicleRaw대';

    final fields = <MapEntry<String, String>>[
      MapEntry('특이사항', specialText),
      MapEntry('일일 차량 입고 대수', vehicleText),
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
              '업무 종료 보고서',
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
          color: SimpleReportColors.base,
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

  // ─────────────────────────────────────────────────────────────
  // 섹션 바디들
  // ─────────────────────────────────────────────────────────────
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
                style: _hasSpecialNote == false ? SimpleReportButtonStyles.primary() : SimpleReportButtonStyles.outlined(),
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
                style: _hasSpecialNote == true ? SimpleReportButtonStyles.primary() : SimpleReportButtonStyles.outlined(),
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

  /// Dashboard와 동일한 “2단계 UI/로직”:
  /// - 필수 입력 + 숫자 검증
  /// - 1차 제출 버튼(유효 입력 시 enable)
  /// - 시스템 집계 카드 UI는 유지하되, 조회 금지 요건으로 값은 미집계 안내
  Widget _buildVehicleBody() {
    final textTheme = Theme.of(context).textTheme;

    Widget metricRow(String label, String value, {bool isEmphasis = false}) {
      return Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: Colors.black54,
              ),
            ),
          ),
          Text(
            value,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: isEmphasis ? FontWeight.w700 : FontWeight.w600,
              color: isEmphasis ? SimpleReportColors.dark : Colors.black87,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘 하루 동안 해당 업무로 입고된 차량 대수를 입력해 주세요.',
          style: textTheme.bodyMedium?.copyWith(
            height: 1.4,
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: _vehicleFieldKey,
          controller: _vehicleCountCtrl,
          decoration: _inputDec(
            labelText: '일일 차량 입고 대수',
            hintText: '예: 12',
          ),
          keyboardType: TextInputType.number,
          onTap: () {
            Future.delayed(const Duration(milliseconds: 150), () {
              final ctx = _vehicleFieldKey.currentContext;
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
            final value = v?.trim() ?? '';
            if (value.isEmpty) return '일일 차량 입고 대수를 입력하세요.';
            if (!RegExp(r'^\d+$').hasMatch(value)) return '숫자만 입력하세요.';
            return null;
          },
        ),
        const SizedBox(height: 8),

        // 시스템 집계 안내 카드(디자인은 유지, 값은 조회 금지로 미집계)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: SimpleReportColors.light.withOpacity(0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: SimpleReportColors.light.withOpacity(0.8),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.info_outline,
                    size: 18,
                    color: SimpleReportColors.dark,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '시스템 집계 기준 (참고용)',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: SimpleReportColors.dark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '이 화면은 Firebase 조회를 수행하지 않으므로, 시스템 집계 값을 표시하지 않습니다.\n'
                    '보고용 "일일 차량 입고 대수"는 반드시 직접 입력해 주세요.',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.black87,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.black12.withOpacity(0.0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    metricRow('시스템 입차', '미집계'),
                    const SizedBox(height: 4),
                    metricRow('출차', '미집계'),
                    const SizedBox(height: 4),
                    metricRow('중복 입차', '미집계'),
                    const Divider(height: 16),
                    metricRow(
                      '시스템 합산(입차+출차+중복 입차)',
                      '미집계',
                      isEmphasis: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '※ 시스템 집계는 표시하지 않으며, 입력값이 곧 저장값(vehicleInput)으로 반영됩니다.',
                style: textTheme.bodySmall?.copyWith(
                  color: Colors.black54,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: (_firstSubmitting || !_isVehicleCountValid) ? null : _submitFirstEndReport,
            style: SimpleReportButtonStyles.primary(),
            icon: _firstSubmitting
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(
              _firstSubmitting ? '1차 제출 중…' : (_firstSubmittedCompleted ? '1차 제출 완료(재제출 가능)' : '1차 제출'),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ),

        const SizedBox(height: 4),

        Text(
          '※ 1차 제출을 완료해야 다음 단계로 진행할 수 있습니다.',
          style: textTheme.bodySmall?.copyWith(
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
        if (_hasSpecialNote == true) {
          if (v == null || v.trim().isEmpty) {
            return '업무 내용을 입력하세요.';
          }
        }
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
            hintText: '예: 콜센터 업무 종료 보고서 – 11월 25일자 12대 - 특이사항 있음',
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
                style: SimpleReportButtonStyles.smallPrimary(),
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
                  style: SimpleReportButtonStyles.smallOutlined(),
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
          16 + bottomInset,
        ),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  '업무 종료 보고서',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'WORK COMPLETION REPORT',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: Colors.black54,
                    letterSpacing: 3,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: SimpleReportColors.light.withOpacity(0.8),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.edit_note_rounded,
                            size: 22,
                            color: SimpleReportColors.dark,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '업무 종료 보고서 양식',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: SimpleReportColors.dark,
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
                      Container(
                        decoration: BoxDecoration(
                          color: SimpleReportColors.light.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: SimpleReportColors.light.withOpacity(0.8),
                          ),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.info_outline,
                              size: 18,
                              color: SimpleReportColors.dark,
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
                      _sectionCard(
                        title: sectionTitle,
                        margin: const EdgeInsets.only(bottom: 0),
                        child: sectionBody,
                      ),
                      _gap(12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: _sending ? null : _reset,
                              icon: const Icon(Icons.refresh_outlined),
                              label: const Text('초기화'),
                              style: SimpleReportButtonStyles.outlined(),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _sending ? null : _showPreview,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('미리보기'),
                              style: SimpleReportButtonStyles.primary(),
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
      backgroundColor: const Color(0xFFEFF3F6),
      appBar: AppBar(
        title: const Text('업무 종료 보고서 작성'),
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
              style: SimpleReportButtonStyles.smallPrimary(),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _currentPageIndex == 4
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
              style: SimpleReportButtonStyles.primary(),
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
              // Dashboard와 동일: 1차 제출 완료 전에는 2페이지(인덱스 1) 이후로 진행 금지
              if (!_firstSubmittedCompleted && index > 1) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                });

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('다음 단계로 진행하기 전에 먼저 "1차 제출"을 완료해 주세요.'),
                  ),
                );
                return;
              }

              setState(() {
                _currentPageIndex = index;

                // 첫 페이지로 돌아오면 특이사항 선택 초기화(기존 로직 유지)
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
                sectionTitle: '2. 일일 차량 입고 대수',
                sectionBody: _buildVehicleBody(),
              ),
              _buildReportPage(
                sectionTitle: '3. 특이 사항 (조건부 필수)',
                sectionBody: _buildWorkContentBody(),
              ),
              _buildReportPage(
                sectionTitle: '4. 메일 전송 내용',
                sectionBody: _buildMailBody(),
              ),
              _buildReportPage(
                sectionTitle: '5. 전자서명',
                sectionBody: _buildSignatureBody(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// 15초 취소 가능 다이얼로그(간단 구현)
/// - duration 종료 시 자동 "진행(true)" 반환
/// - 사용자가 취소 누르면 false
/// ─────────────────────────────────────────────────────────────
class _DurationBlockingDialog extends StatefulWidget {
  const _DurationBlockingDialog({
    required this.message,
    required this.duration,
  });

  final String message;
  final Duration duration;

  @override
  State<_DurationBlockingDialog> createState() => _DurationBlockingDialogState();
}

class _DurationBlockingDialogState extends State<_DurationBlockingDialog> {
  Timer? _timer;
  late int _remainSec;

  @override
  void initState() {
    super.initState();
    _remainSec = widget.duration.inSeconds;

    _timer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() {
        _remainSec -= 1;
      });

      if (_remainSec <= 0) {
        _timer?.cancel();
        if (mounted) Navigator.of(context).pop(true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remainText = _remainSec > 0 ? '$_remainSec초 후 자동 진행' : '진행 중...';

    return AlertDialog(
      title: const Text('확인'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.message),
          const SizedBox(height: 12),
          Row(
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  remainText,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            _timer?.cancel();
            Navigator.of(context).pop(false);
          },
          child: const Text('취소'),
        ),
      ],
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// 작업 중 블로킹 다이얼로그
/// ─────────────────────────────────────────────────────────────
class _BlockingProgressDialog extends StatelessWidget {
  const _BlockingProgressDialog({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 28),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
        child: Row(
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
