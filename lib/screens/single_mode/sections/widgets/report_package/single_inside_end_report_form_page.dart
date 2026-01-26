import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../repositories/end_work_report_repo_services/end_work_report_repository.dart';
import '../../../../../utils/google_auth_v7.dart';
import '../../../../../utils/api/email_config.dart';
import 'single_inside_report_styles.dart';
import 'single_inside_report_signature_dialog.dart';
import 'package:easydev/screens/hubs_mode/dev_package/debug_package/debug_api_logger.dart';

class SingleInsideEndReportFormPage extends StatefulWidget {
  const SingleInsideEndReportFormPage({super.key});

  @override
  State<SingleInsideEndReportFormPage> createState() => _SingleInsideEndReportFormPageState();
}

/// ─────────────────────────────────────────────────────────────
/// [요구사항 반영] Firestore 조회(get/query) 없음.
/// - insert(set/merge)만 수행하여 end_work_reports 스키마에 맞게 저장.
///
/// [변경 요구사항]
/// - ✅ 월 문서 1개 유지 + reports 맵에 일자별 데이터 누적
///   end_work_reports/area_<area>/months/<yyyyMM>
///     └ reports: { "<yyyy-MM-dd>": { ...payload... }, ... }
///
/// - ✅ 동일 batch 내 원자 upsert:
///     - end_work_reports/area_<area>                  (area meta)
///     - end_work_reports/area_<area>/months/<yyyyMM>  (month meta + reports map 누적)
///
/// - ⚠️ 일자 서브컬렉션(reports/<yyyy-MM-dd>) 문서 생성은 제거
///
/// [리팩터링]
/// - ✅ Firestore 관련 write 로직은 repositories/end_work_report_repository.dart 로 분리
/// - ✅ UI에서는 Repository 호출만 수행
/// ─────────────────────────────────────────────────────────────
class _SingleInsideEndReportFormPageState extends State<SingleInsideEndReportFormPage> {
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

  // SharedPreferences에서 불러오는 division
  String? _divisionFromPrefs;

  String get _signerName => _nameCtrl.text.trim();

  bool _sending = false; // 최종 메일 제출 중 여부

  // 1차 제출(서버 저장) 상태
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

  // ✅ Firestore write 로직 분리: Repository
  final EndWorkReportRepository _endWorkReportRepository = EndWorkReportRepository();

  // ─────────────────────────────────────────────────────────────
  // ✅ API 디버그 로직: 표준 태그 / 로깅 헬퍼
  // ─────────────────────────────────────────────────────────────
  static const String _tReport = 'report';
  static const String _tReportEnd = 'report/end';
  static const String _tReportEndFirst = 'report/end/first_submit';
  static const String _tReportPdf = 'report/pdf';
  static const String _tReportEmail = 'report/email';

  static const String _tFirestoreWrite = 'firestore/write';
  static const String _tPrefs = 'prefs';

  static const String _tGmail = 'gmail';
  static const String _tGmailSend = 'gmail/send';

  // MIME base64 line length (RFC 2045 recommends 76 chars)
  static const int _mimeB64LineLength = 76;

  static Future<void> _logApiError({
    required String tag,
    required String message,
    required Object error,
    Map<String, dynamic>? extra,
    List<String>? tags,
  }) async {
    try {
      await DebugApiLogger().log(
        <String, dynamic>{
          'tag': tag,
          'message': message,
          'error': error.toString(),
          if (extra != null) 'extra': extra,
        },
        level: 'error',
        tags: tags,
      );
    } catch (_) {}
  }

  String _wrapBase64Lines(String b64, {int lineLength = _mimeB64LineLength}) {
    if (b64.isEmpty) return '';
    final sb = StringBuffer();
    for (int i = 0; i < b64.length; i += lineLength) {
      final end = (i + lineLength < b64.length) ? (i + lineLength) : b64.length;
      sb.write(b64.substring(i, end));
      sb.write('\r\n');
    }
    return sb.toString();
  }

  @override
  void initState() {
    super.initState();

    _nameCtrl.addListener(() => setState(() {}));
    _vehicleCountCtrl.addListener(_onVehicleCountChanged);

    _updateMailBody(); // 메일 본문 자동 생성
    _loadSelectedArea();
    _loadDivision();
  }

  Future<void> _loadSelectedArea() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final area = prefs.getString('selectedArea') ?? '';
      if (!mounted) return;
      setState(() {
        _selectedArea = area.trim().isEmpty ? null : area.trim();
      });

      if (_mailSubjectCtrl.text.trim().isEmpty) {
        _updateMailSubject();
      }
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideEndReportFormPage._loadSelectedArea',
        message: 'SharedPreferences(selectedArea) 로드 실패',
        error: e,
        tags: const <String>[_tReport, _tReportEnd, _tPrefs],
      );

      if (_mailSubjectCtrl.text.trim().isEmpty) {
        _updateMailSubject();
      }
    }
  }

  Future<void> _loadDivision() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final div = (prefs.getString('division') ?? '').trim();
      if (!mounted) return;
      setState(() {
        _divisionFromPrefs = div.isEmpty ? null : div;
      });
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideEndReportFormPage._loadDivision',
        message: 'SharedPreferences(division) 로드 실패',
        error: e,
        tags: const <String>[_tReport, _tReportEnd, _tPrefs],
      );
    }
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
    });

    _updateMailSubject();
    _updateMailBody(force: true);

    _pageController.jumpToPage(0);
  }

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

    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final cs2 = Theme.of(ctx).colorScheme;
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
                      color: cs2.surface,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(20, 14, 16, 12),
                            decoration: BoxDecoration(color: cs2.primary),
                            child: Row(
                              children: [
                                Icon(Icons.visibility_outlined, color: cs2.onPrimary),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '업무 종료 보고서 미리보기',
                                    style: textTheme.bodyMedium?.copyWith(
                                      color: cs2.onPrimary,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => Navigator.of(ctx).pop(),
                                  icon: Icon(Icons.close, color: cs2.onPrimary),
                                ),
                              ],
                            ),
                          ),
                          Flexible(
                            child: Scrollbar(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                                child: Text(
                                  text,
                                  style: textTheme.bodyMedium?.copyWith(height: 1.4, color: cs2.onSurface),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            decoration: BoxDecoration(
                              color: cs2.surfaceContainerLow,
                              border: Border(top: BorderSide(color: cs2.outlineVariant.withOpacity(0.7))),
                            ),
                            child: Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    HapticFeedback.selectionClick();
                                    await Clipboard.setData(ClipboardData(text: text));
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('텍스트가 클립보드에 복사되었습니다.')),
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

  Future<bool> _showDurationBlockingDialog({
    required BuildContext context,
    required String message,
    required Duration duration,
  }) async {
    return (await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _DurationBlockingDialog(message: message, duration: duration),
    )) ??
        false;
  }

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
      if (!mounted) return;
      final nav = Navigator.of(context, rootNavigator: true);
      if (nav.canPop()) nav.pop();
    }
  }

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
      EndWorkReportWriteResult? result;

      await _runWithBlockingDialog(
        context: context,
        message: '1차 업무 종료 보고를 저장 중입니다. 잠시만 기다려 주세요...',
        task: () async {
          result = await _endWorkReportRepository.upsertFirstEndReport(
            area: area,
            division: division,
            uploadedBy: userName,
            vehicleInputCount: vehicleInputCount,
          );
        },
      );

      if (!mounted) return;
      final r = result;

      if (r == null) {
        _showSnack('1차 업무 종료 보고 저장 결과를 가져오지 못했습니다.');
        return;
      }

      setState(() {
        _firstSubmittedCompleted = true;
      });

      _showSnack(
        [
          '1차 업무 종료 보고 저장 완료',
          '• area: ${r.area}',
          '• division: ${r.division}',
          '• monthKey: ${r.monthKey}',
          '• 저장 문서: ${r.monthDocPath}',
          '• 저장 필드: ${r.reportsFieldPath}',
          '• 서버 저장 입고 대수(vehicleInput): ${r.vehicleInputCount}대',
          '• 서버 저장 출고 대수(vehicleOutput): ${r.vehicleOutputCount}대 (조회 없음 → 0)',
          '• metrics 스냅샷: ${r.snapshotLockedVehicleCount} / ${r.snapshotTotalLockedFee} (조회 없음 → 0)',
        ].join('\n'),
      );
    } catch (e) {
      await _logApiError(
        tag: 'SimpleInsideEndReportFormPage._submitFirstEndReport',
        message: '1차 제출(Firestore write) 실패',
        error: e,
        extra: <String, dynamic>{
          'area': area,
          'division': division,
          'vehicleInputCount': raw,
          'uploadedBy': userName,
        },
        tags: const <String>[_tReport, _tReportEnd, _tReportEndFirst, _tFirestoreWrite],
      );

      _showSnack('1차 업무 종료 보고 저장 중 오류: $e');
    } finally {
      if (mounted) setState(() => _firstSubmitting = false);
    }
  }

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
        await _logApiError(
          tag: 'SimpleInsideEndReportFormPage._submit',
          message: '수신자(To) 설정이 비어있거나 형식이 올바르지 않음',
          error: Exception('invalid_to'),
          extra: <String, dynamic>{'toRaw': cfg.to},
          tags: const <String>[_tReport, _tReportEnd, _tReportEmail],
        );

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('수신자(To)가 비어있거나 형식이 올바르지 않습니다. 설정에서 수신자를 저장해 주세요.'),
          ),
        );
        return;
      }

      final toCsv = cfg.to.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).join(', ');

      final subject = _mailSubjectCtrl.text.trim();
      _updateMailBody(force: true);
      final body = _mailBodyCtrl.text.trim();

      if (subject.isEmpty) {
        await _logApiError(
          tag: 'SimpleInsideEndReportFormPage._submit',
          message: '메일 제목이 비어있음(자동 생성 실패)',
          error: Exception('empty_subject'),
          tags: const <String>[_tReport, _tReportEnd],
        );

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
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('메일 전송 완료')));
    } catch (e) {
      await _logApiError(
        tag: 'SimpleInsideEndReportFormPage._submit',
        message: '업무 종료 보고서 최종 제출 실패(메일 전송)',
        error: e,
        extra: <String, dynamic>{
          'hasSignature': _signaturePngBytes != null,
          'hasSpecialNote': _hasSpecialNote,
          'contentLen': _contentCtrl.text.trim().length,
          'vehicleRaw': _vehicleCountCtrl.text.trim(),
          'subjectLen': _mailSubjectCtrl.text.trim().length,
        },
        tags: const <String>[_tReport, _tReportEnd, _tReportEmail],
      );

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
    } catch (e) {
      await _logApiError(
        tag: 'SimpleInsideEndReportFormPage._buildPdfBytes',
        message: 'PDF 폰트 로드 실패(Regular)',
        error: e,
        tags: const <String>[_tReport, _tReportEnd, _tReportPdf],
      );
    }

    try {
      final boldData = await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
      bold = pw.Font.ttf(boldData);
    } catch (e) {
      await _logApiError(
        tag: 'SimpleInsideEndReportFormPage._buildPdfBytes',
        message: 'PDF 폰트 로드 실패(Bold) — regular로 대체',
        error: e,
        tags: const <String>[_tReport, _tReportEnd, _tReportPdf],
      );
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
                child: pw.Text(kv.key, style: const pw.TextStyle(fontSize: 11)),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(kv.value, style: const pw.TextStyle(fontSize: 11)),
              ),
            ],
          ),
      ],
    );

    pw.Widget buildSection(String title, String body) => pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(height: 8),
        pw.Text(title, style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(8),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(body.isEmpty ? '-' : body, style: const pw.TextStyle(fontSize: 11)),
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
          pw.Text('전자서명', style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Row(
            children: [
              pw.Expanded(child: pw.Text('서명자: $name', style: const pw.TextStyle(fontSize: 11))),
              pw.SizedBox(width: 8),
              pw.Text('서명 일시: $timeText', style: const pw.TextStyle(fontSize: 11)),
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
                style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey),
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
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
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
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ),
      ),
    );

    try {
      return doc.save();
    } catch (e) {
      await _logApiError(
        tag: 'SimpleInsideEndReportFormPage._buildPdfBytes',
        message: 'PDF 생성/저장 실패',
        error: e,
        extra: <String, dynamic>{
          'contentLen': _contentCtrl.text.trim().length,
          'vehicleRaw': _vehicleCountCtrl.text.trim(),
          'hasSignature': _signaturePngBytes != null,
        },
        tags: const <String>[_tReport, _tReportEnd, _tReportPdf],
      );
      rethrow;
    }
  }

  Future<void> _sendEmailViaGmail({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    try {
      final client = await GoogleAuthV7.authedClient(const <String>[]);
      final api = gmail.GmailApi(client);

      final boundary = 'dart-mail-boundary-${DateTime.now().millisecondsSinceEpoch}';
      final subjectB64 = base64.encode(utf8.encode(subject));

      final attachmentB64 = base64.encode(pdfBytes);
      final attachmentWrapped = _wrapBase64Lines(attachmentB64);

      const crlf = '\r\n';
      final sb = StringBuffer()
        ..write('To: $to$crlf')
        ..write('Subject: =?utf-8?B?$subjectB64?=$crlf')
        ..write('MIME-Version: 1.0$crlf')
        ..write('Content-Type: multipart/mixed; boundary="$boundary"$crlf')
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: text/plain; charset="utf-8"$crlf')
        ..write('Content-Transfer-Encoding: 7bit$crlf')
        ..write(crlf)
        ..write(body)
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: application/pdf; name="$filename"$crlf')
        ..write('Content-Disposition: attachment; filename="$filename"$crlf')
        ..write('Content-Transfer-Encoding: base64$crlf')
        ..write(crlf)
        ..write(attachmentWrapped)
        ..write('--$boundary--$crlf');

      final raw = base64UrlEncode(utf8.encode(sb.toString())).replaceAll('=', '');
      final msg = gmail.Message()..raw = raw;

      await api.users.messages.send(msg, 'me');
    } catch (e) {
      await _logApiError(
        tag: 'SimpleInsideEndReportFormPage._sendEmailViaGmail',
        message: 'Gmail 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'toLen': to.trim().length,
          'subjectLen': subject.trim().length,
          'bodyLen': body.trim().length,
          'filename': filename,
          'pdfBytes': pdfBytes.length,
        },
        tags: const <String>[_tReport, _tReportEnd, _tReportEmail, _tGmail, _tGmailSend],
      );
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // UI 섹션
  // ─────────────────────────────────────────────────────────────

  Widget _buildSpecialNoteBody() {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget buildChoice({
      required bool value,
      required String label,
    }) {
      final selected = _hasSpecialNote == value;

      return Expanded(
        child: selected
            ? ElevatedButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() {
              _hasSpecialNote = value;
              _updateMailSubject();
            });
            _pageController.nextPage(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          },
          style: SingleReportButtonStyles.primary(context),
          child: Text(label),
        )
            : OutlinedButton(
          onPressed: () {
            HapticFeedback.selectionClick();
            setState(() {
              _hasSpecialNote = value;
              _updateMailSubject();
            });
            _pageController.nextPage(
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            );
          },
          style: SingleReportButtonStyles.outlined(context),
          child: Text(label),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘 업무 진행 중 특이사항이 있었는지 선택해 주세요.\n'
              '(예: 장애, 클레임, 일정 지연, 긴급 지원 등)',
          style: textTheme.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            buildChoice(value: false, label: '특이사항 없음'),
            const SizedBox(width: 12),
            buildChoice(value: true, label: '특이사항 있음'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          '※ 선택 결과는 메일 제목에 자동으로 반영되며, 다음 항목으로 자동 이동합니다.',
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _buildVehicleBody() {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    Widget metricRow(String label, String value, {bool isEmphasis = false}) {
      return Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
          Text(
            value,
            style: textTheme.bodySmall?.copyWith(
              fontWeight: isEmphasis ? FontWeight.w800 : FontWeight.w600,
              color: isEmphasis ? cs.onSurface : cs.onSurface,
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
          style: textTheme.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: _vehicleFieldKey,
          controller: _vehicleCountCtrl,
          decoration: _inputDec(context, labelText: '일일 차량 입고 대수', hintText: '예: 12'),
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

        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Text(
                    '시스템 집계 기준 (참고용)',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '이 화면은 Firebase 조회를 수행하지 않으므로, 시스템 집계 값을 표시하지 않습니다.\n'
                    '보고용 "일일 차량 입고 대수"는 반드시 직접 입력해 주세요.',
                style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.6)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    metricRow('시스템 입차', '미집계'),
                    const SizedBox(height: 4),
                    metricRow('출차', '미집계'),
                    const SizedBox(height: 4),
                    metricRow('중복 입차', '미집계'),
                    Divider(height: 16, color: cs.outlineVariant.withOpacity(0.7)),
                    metricRow('시스템 합산(입차+출차+중복 입차)', '미집계', isEmphasis: true),
                  ],
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
            style: SingleReportButtonStyles.primary(context),
            icon: _firstSubmitting
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(cs.onPrimary),
              ),
            )
                : const Icon(Icons.cloud_upload_outlined),
            label: Text(
              _firstSubmitting
                  ? '1차 제출 중…'
                  : (_firstSubmittedCompleted ? '1차 제출 완료(재제출 가능)' : '1차 제출'),
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ),

        const SizedBox(height: 4),
        Text(
          '※ 1차 제출을 완료해야 다음 단계로 진행할 수 있습니다.',
          style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
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
        context,
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
          if (v == null || v.trim().isEmpty) return '업무 내용을 입력하세요.';
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
            context,
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
            context,
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
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
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
                  Icon(Icons.person_outline, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '서명자: ${_signerName.isEmpty ? "이름 미입력" : _signerName}',
                    style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, color: cs.onSurface),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.access_time, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Text(
                    '서명 일시: ${_signDateTime == null ? "저장 시 자동" : _fmtCompact(_signDateTime!)}',
                    style: textTheme.bodyMedium?.copyWith(color: cs.onSurface),
                  ),
                ],
              ),
              ElevatedButton.icon(
                onPressed: _openSignatureDialog,
                icon: const Icon(Icons.border_color),
                label: const Text('서명하기'),
                style: SingleReportButtonStyles.smallPrimary(context),
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
                  style: SingleReportButtonStyles.smallOutlined(context),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        if (_signaturePngBytes != null)
          Container(
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
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
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scrollbar(
      child: SingleChildScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
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
                  style: textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: 3,
                    color: cs.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'WORK COMPLETION REPORT',
                  textAlign: TextAlign.center,
                  style: textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    letterSpacing: 2.4,
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.8),
                      width: 1,
                    ),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.edit_note_rounded, size: 22, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(
                            '업무 종료 보고서 양식',
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: cs.onSurface,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '작성일 ${_fmtCompact(DateTime.now())}',
                            style: textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(height: 24, color: cs.outlineVariant.withOpacity(0.7)),
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline, size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '해당 업무의 수행 내용과 결과를 사실에 근거하여 간결하게 작성해 주세요.',
                                style: textTheme.bodySmall?.copyWith(height: 1.4, color: cs.onSurface),
                              ),
                            ),
                          ],
                        ),
                      ),
                      _gap(20),
                      _sectionCard(
                        context,
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
                              style: SingleReportButtonStyles.outlined(context),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: _sending ? null : _showPreview,
                              icon: const Icon(Icons.visibility_outlined),
                              label: const Text('미리보기'),
                              style: SingleReportButtonStyles.primary(context),
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

  InputDecoration _inputDec(
      BuildContext context, {
        required String labelText,
        String? hintText,
      }) {
    final cs = Theme.of(context).colorScheme;

    return InputDecoration(
      labelText: labelText,
      hintText: hintText,
      filled: true,
      fillColor: cs.surfaceContainerLow,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: cs.primary, width: 1.6),
      ),
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    );
  }

  Widget _sectionCard(
      BuildContext context, {
        required String title,
        required Widget child,
        EdgeInsetsGeometry padding = const EdgeInsets.all(12),
        EdgeInsetsGeometry? margin,
      }) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      margin: margin ?? const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.8)),
      ),
      color: cs.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
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
    final cs = Theme.of(context).colorScheme;

    final result = await showGeneralDialog<SignatureResult>(
      context: context,
      barrierLabel: '서명',
      barrierDismissible: false,
      barrierColor: cs.scrim.withOpacity(0.55),
      pageBuilder: (ctx, animation, secondaryAnimation) {
        return SignatureFullScreenDialog(
          name: _signerName,
          initialDateTime: _signDateTime,
        );
      },
      transitionBuilder: (ctx, animation, secondaryAnimation, child) {
        return FadeTransition(
          opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: const Text('업무 종료 보고서 작성'),
        centerTitle: true,
        backgroundColor: cs.surface,
        foregroundColor: cs.onSurface,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.8), width: 1)),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ElevatedButton.icon(
              onPressed: _sending ? null : _showPreview,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('미리보기'),
              style: SingleReportButtonStyles.smallPrimary(context),
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
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(0.8), width: 1)),
          ),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (!_sending && _signaturePngBytes != null) ? _submit : null,
              icon: _sending
                  ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(cs.onPrimary),
                ),
              )
                  : const Icon(Icons.send_outlined),
              label: Text(
                _sending ? '전송 중…' : '제출',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              style: SingleReportButtonStyles.primary(context),
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
              if (!_firstSubmittedCompleted && index > 1) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _pageController.animateToPage(
                    1,
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOut,
                  );
                });
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('다음 단계로 진행하기 전에 먼저 "1차 제출"을 완료해 주세요.')),
                );
                return;
              }

              setState(() {
                _currentPageIndex = index;

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

class _DurationBlockingDialog extends StatefulWidget {
  const _DurationBlockingDialog({required this.message, required this.duration});

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
      setState(() => _remainSec -= 1);

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
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(child: Text(remainText, style: const TextStyle(fontWeight: FontWeight.w700))),
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
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 14),
            Expanded(child: Text(message, style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }
}
