import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../../../app/config/email_config.dart';
import '../../../../../../shared/utils/gmail_pdf_mailer.dart';
import '../../../../../dashboard/domain/repositories/end_work_report_repository.dart';
import '../../../../../dev/application/area_state.dart';
import '../../../../../dev/debug/debug_api_logger.dart';
import 'single_inside_report_styles.dart';

class SingleInsideEndReportFormPage extends StatefulWidget {
  const SingleInsideEndReportFormPage({super.key});

  @override
  State<SingleInsideEndReportFormPage> createState() =>
      _SingleInsideEndReportFormPageState();
}

class _SingleInsideEndReportFormPageState
    extends State<SingleInsideEndReportFormPage> {
  final _formKey = GlobalKey<FormState>();

  final _deptCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _positionCtrl = TextEditingController();

  final _contentCtrl = TextEditingController();
  final _vehicleCountCtrl = TextEditingController();

  final _mailSubjectCtrl = TextEditingController();
  final _mailBodyCtrl = TextEditingController();

  final _deptNode = FocusNode();
  final _nameNode = FocusNode();
  final _positionNode = FocusNode();
  final _contentNode = FocusNode();

  bool? _hasSpecialNote;

  String? _selectedArea;
  String? _divisionFromPrefs;

  bool _sending = false;
  bool _firstSubmitting = false;
  bool _firstSubmittedCompleted = false;
  bool _isVehicleCountValid = false;

  final PageController _pageController = PageController();

  int _currentPageIndex = 0;

  final GlobalKey _vehicleFieldKey = GlobalKey();
  final GlobalKey _contentFieldKey = GlobalKey();

  final EndWorkReportRepository _endWorkReportRepository =
      EndWorkReportRepository();

  static const String _tReport = 'report';
  static const String _tReportEnd = 'report/end';
  static const String _tReportEndFirst = 'report/end/first_submit';
  static const String _tReportPdf = 'report/pdf';
  static const String _tReportEmail = 'report/email';

  static const String _tFirestoreWrite = 'firestore/write';
  static const String _tPrefs = 'prefs';

  static const String _tGmail = 'gmail';
  static const String _tGmailSend = 'gmail/send';


  static const String _draftVehicleCountKey =
      'single_inside_end_report_draft_vehicle_count';
  static const String _draftHasSpecialNoteKey =
      'single_inside_end_report_draft_has_special_note';
  static const String _draftContentKey =
      'single_inside_end_report_draft_content';

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

  @override
  void initState() {
    super.initState();

    _vehicleCountCtrl.addListener(_onVehicleCountChanged);

    _updateMailBody();
    _loadSelectedArea();
    _loadDivision();
    _loadDraft();
  }

  Future<void> _loadSelectedArea() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final area = prefs.getString('selectedArea') ?? '';
      if (!mounted) return;
      setState(() {
        _selectedArea = area.trim().isEmpty ? null : area.trim();
      });

      _updateMailSubject();
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideEndReportFormPage._loadSelectedArea',
        message: 'SharedPreferences(selectedArea) 로드 실패',
        error: e,
        tags: const <String>[_tReport, _tReportEnd, _tPrefs],
      );

      _updateMailSubject();
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

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final vehicleCount =
          (prefs.getString(_draftVehicleCountKey) ?? '').trim();
      final content = prefs.getString(_draftContentKey) ?? '';
      final specialRaw = prefs.getString(_draftHasSpecialNoteKey);

      bool? hasSpecialNote;
      if (specialRaw == 'true') {
        hasSpecialNote = true;
      } else if (specialRaw == 'false') {
        hasSpecialNote = false;
      }

      _vehicleCountCtrl.text = vehicleCount;
      _contentCtrl.text = content;

      if (!mounted) return;
      setState(() {
        _hasSpecialNote = hasSpecialNote;
      });

      _updateMailSubject();
      _updateMailBody(force: true);
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideEndReportFormPage._loadDraft',
        message: '임시저장 데이터 로드 실패',
        error: e,
        tags: const <String>[_tReport, _tReportEnd, _tPrefs],
      );
    }
  }

  Future<void> _persistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _draftVehicleCountKey, _vehicleCountCtrl.text.trim());

      if (_hasSpecialNote == null) {
        await prefs.remove(_draftHasSpecialNoteKey);
      } else {
        await prefs.setString(
          _draftHasSpecialNoteKey,
          _hasSpecialNote!.toString(),
        );
      }

      final content = _contentCtrl.text.trim();
      if (content.isEmpty) {
        await prefs.remove(_draftContentKey);
      } else {
        await prefs.setString(_draftContentKey, content);
      }
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideEndReportFormPage._persistDraft',
        message: '임시저장 데이터 저장 실패',
        error: e,
        tags: const <String>[_tReport, _tReportEnd, _tPrefs],
      );
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_draftVehicleCountKey);
      await prefs.remove(_draftHasSpecialNoteKey);
      await prefs.remove(_draftContentKey);
    } catch (e) {
      await _logApiError(
        tag: 'SingleInsideEndReportFormPage._clearDraft',
        message: '임시저장 데이터 삭제 실패',
        error: e,
        tags: const <String>[_tReport, _tReportEnd, _tPrefs],
      );
    }
  }

  void _handleSpecialNoteSelection(bool value) {
    HapticFeedback.selectionClick();
    setState(() {
      _hasSpecialNote = value;
      if (!value) {
        _contentCtrl.clear();
      }
      _updateMailSubject();
      if (!value) {
        _updateMailBody(force: true);
      }
    });
    FocusScope.of(context).unfocus();
    _persistDraft();

    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      value ? 2 : 3,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  void _goBackFromCurrentPage() {
    FocusScope.of(context).unfocus();
    if (!_pageController.hasClients) return;

    if (_currentPageIndex == 3) {
      _pageController.animateToPage(
        _hasSpecialNote == true ? 2 : 1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    if (_currentPageIndex == 2) {
      _pageController.animateToPage(
        1,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
      return;
    }

    if (_currentPageIndex == 1) {
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _exitPage() async {
    if (_sending || _firstSubmitting) return;
    if (!mounted) return;
    Navigator.of(context).pop();
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

  Future<void> _reset() async {
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
      _hasSpecialNote = null;
      _currentPageIndex = 0;
      _firstSubmitting = false;
      _firstSubmittedCompleted = false;
      _isVehicleCountValid = false;
    });

    _updateMailSubject();
    _updateMailBody(force: true);

    if (_pageController.hasClients) {
      _pageController.jumpToPage(0);
    }

    await _clearDraft();
  }

  String _resolveCurrentOrSelectedArea() {
    try {
      final currentArea = context.read<AreaState>().currentArea.trim();
      if (currentArea.isNotEmpty) return currentArea;
    } catch (_) {}

    final selectedArea = (_selectedArea ?? '').trim();
    if (selectedArea.isNotEmpty) return selectedArea;

    return '';
  }

  String _resolveReportArea() {
    final area = _resolveCurrentOrSelectedArea();
    return area.isEmpty ? '업무' : area;
  }

  String _resolveCurrentOrStoredDivision() {
    try {
      final currentDivision = context.read<AreaState>().currentDivision.trim();
      if (currentDivision.isNotEmpty) return currentDivision;
    } catch (_) {}

    final storedDivision = (_divisionFromPrefs ?? '').trim();
    if (storedDivision.isNotEmpty) return storedDivision;

    return '';
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

    final area = _resolveReportArea();
    _mailSubjectCtrl.text =
        '$area 업무 종료 보고서 – ${month}월 ${day}일자$vehiclePart$suffixSpecial';
  }

  void _updateMailBody({bool force = false}) {
    if (!force && _mailBodyCtrl.text.trim().isNotEmpty) return;
    final now = DateTime.now();
    final y = now.year;
    final m = now.month;
    final d = now.day;
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    _mailBodyCtrl.text =
        '본 보고서는 ${y}년 ${m}월 ${d}일 ${hh}시 ${mm}분 기준으로 작성된 업무 종료 보고서입니다.';
  }

  void _onVehicleCountChanged() {
    final raw = _vehicleCountCtrl.text.trim();
    final isValid = raw.isNotEmpty && RegExp(r'^\d+$').hasMatch(raw);
    if (_isVehicleCountValid != isValid) {
      setState(() => _isVehicleCountValid = isValid);
    }
    _updateMailSubject();
    _persistDraft();
  }

  String _buildPreviewText(BuildContext context) {
    final specialText =
        _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');

    final vehicleRaw = _vehicleCountCtrl.text.trim();
    final vehicleText = vehicleRaw.isEmpty ? '입력 안 됨' : '$vehicleRaw대';

    return [
      '— 업무 종료 보고서 —',
      '',
      '특이사항: $specialText',
      '출차 대수: $vehicleText',
      '',
      '[업무 내용]',
      _contentCtrl.text,
      '',
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

    final textTheme = Theme.of(context).textTheme;

    await showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) {
        final cs2 = Theme.of(ctx).colorScheme;
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
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
                                Icon(Icons.visibility_outlined,
                                    color: cs2.onPrimary),
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
                                padding:
                                    const EdgeInsets.fromLTRB(20, 16, 20, 12),
                                child: Text(
                                  text,
                                  style: textTheme.bodyMedium?.copyWith(
                                      height: 1.4, color: cs2.onSurface),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                            decoration: BoxDecoration(
                              color: cs2.surfaceContainerLow,
                              border: Border(
                                  top: BorderSide(
                                      color:
                                          cs2.outlineVariant.withOpacity(0.7))),
                            ),
                            child: Row(
                              children: [
                                TextButton.icon(
                                  onPressed: () async {
                                    HapticFeedback.selectionClick();
                                    await Clipboard.setData(
                                        ClipboardData(text: text));
                                    debugPrint(
                                        '[SingleInsideEndReportFormPage] preview text copied to clipboard');
                                  },
                                  icon:
                                      const Icon(Icons.copy_rounded, size: 18),
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
      debugPrint('[SingleInsideEndReportFormPage] vehicle count is empty');
      return;
    }
    if (!RegExp(r'^\d+$').hasMatch(raw)) {
      debugPrint(
          '[SingleInsideEndReportFormPage] vehicle count is invalid: $raw');
      return;
    }

    final area = _resolveCurrentOrSelectedArea();
    final division = _resolveCurrentOrStoredDivision();
    final userName =
        (_nameCtrl.text.trim().isEmpty) ? '무기명' : _nameCtrl.text.trim();

    if (area.isEmpty) {
      debugPrint(
          '[SingleInsideEndReportFormPage] area is empty. currentArea or selectedArea must be available');
      return;
    }
    if (division.isEmpty) {
      debugPrint(
          '[SingleInsideEndReportFormPage] division is empty. currentDivision or stored division must be available');
      return;
    }

    HapticFeedback.lightImpact();

    setState(() => _firstSubmitting = true);

    try {
      final vehicleOutputCount = int.parse(raw);
      EndWorkReportWriteResult? result;

      await _runWithBlockingDialog(
        context: context,
        message: '1차 업무 종료 보고를 저장 중입니다. 잠시만 기다려 주세요...',
        task: () async {
          result = await _endWorkReportRepository.upsertFirstEndReport(
            area: area,
            division: division,
            uploadedBy: userName,
            vehicleOutputCount: vehicleOutputCount,
          );
        },
      );

      if (!mounted) return;
      final r = result;

      if (r == null) {
        debugPrint(
            '[SingleInsideEndReportFormPage] first submit result is null');
        return;
      }

      setState(() {
        _firstSubmittedCompleted = true;
      });

      await _persistDraft();

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_pageController.hasClients) return;
        _pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      });

      debugPrint(
        [
          '1차 업무 종료 보고 저장 완료',
          '• area: ${r.area}',
          '• division: ${r.division}',
          '• monthKey: ${r.monthKey}',
          '• 저장 문서: ${r.monthDocPath}',
          '• 저장 필드: ${r.reportsFieldPath}',
          '• 서버 저장 출고 대수(vehicleOutput): ${r.vehicleOutputCount}대',
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
          'vehicleOutputCount': raw,
          'uploadedBy': userName,
        },
        tags: const <String>[
          _tReport,
          _tReportEnd,
          _tReportEndFirst,
          _tFirestoreWrite
        ],
      );

      debugPrint('1차 업무 종료 보고 저장 중 오류: $e');
    } finally {
      if (mounted) setState(() => _firstSubmitting = false);
    }
  }

  Future<void> _showSubmitSuccessDialogAndClose() async {
    if (!mounted) return;

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierLabel: '업무 종료 보고 완료',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await Future<void>.delayed(const Duration(milliseconds: 1200));
          if (dialogContext.mounted) {
            Navigator.of(dialogContext, rootNavigator: true).pop();
          }
        });

        final cs = Theme.of(dialogContext).colorScheme;
        final textTheme = Theme.of(dialogContext).textTheme;

        return Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: const BoxConstraints(maxWidth: 320),
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: cs.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      Icons.check_rounded,
                      size: 32,
                      color: cs.primary,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    '업무 종료 보고 완료',
                    textAlign: TextAlign.center,
                    style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: cs.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );

    if (!mounted) return;

    final pageNav = Navigator.of(context);
    if (pageNav.canPop()) {
      pageNav.pop();
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_hasSpecialNote == null) {
      debugPrint(
          '[SingleInsideEndReportFormPage] special note selection missing');
      _pageController.animateToPage(
        1,
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
        debugPrint(
            '[SingleInsideEndReportFormPage] invalid recipient list. Save recipients in settings');
        return;
      }

      final toCsv = cfg.to
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .join(', ');

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
        debugPrint('[SingleInsideEndReportFormPage] mail subject is empty');
        return;
      }

      final pdfBytes = await _buildPdfBytes();
      final now = DateTime.now();
      final nameForFile =
          _nameCtrl.text.trim().isEmpty ? '무기명' : _nameCtrl.text.trim();
      final filename = _safeFileName('업무종료보고서_${nameForFile}_${_dateTag(now)}');

      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );

      await _clearDraft();

      if (!mounted) return;
      debugPrint('[SingleInsideEndReportFormPage] mail send completed');
      await _showSubmitSuccessDialogAndClose();
    } catch (e) {
      await _logApiError(
        tag: 'SimpleInsideEndReportFormPage._submit',
        message: '업무 종료 보고서 최종 제출 실패(메일 전송)',
        error: e,
        extra: <String, dynamic>{
          'hasSpecialNote': _hasSpecialNote,
          'contentLen': _contentCtrl.text.trim().length,
          'vehicleRaw': _vehicleCountCtrl.text.trim(),
          'subjectLen': _mailSubjectCtrl.text.trim().length,
        },
        tags: const <String>[_tReport, _tReportEnd, _tReportEmail],
      );

      if (!mounted) return;
      debugPrint('메일 전송 실패: $e');
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
      final regData = await rootBundle
          .load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
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
      final boldData =
          await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
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

    final specialText =
        _hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음');
    final vehicleRaw = _vehicleCountCtrl.text.trim();
    final vehicleText = vehicleRaw.isEmpty ? '입력 안 됨' : '$vehicleRaw대';

    final fields = <MapEntry<String, String>>[
      MapEntry('특이사항', specialText),
      MapEntry('출차 대수', vehicleText),
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
                    child: pw.Text(kv.key,
                        style: const pw.TextStyle(fontSize: 11)),
                  ),
                  pw.Container(
                    padding: const pw.EdgeInsets.all(6),
                    child: pw.Text(kv.value,
                        style: const pw.TextStyle(fontSize: 11)),
                  ),
                ],
              ),
          ],
        );

    pw.Widget buildSection(String title, String body) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(height: 8),
            pw.Text(title,
                style:
                    pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Container(
              width: double.infinity,
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
                borderRadius: pw.BorderRadius.circular(4),
              ),
              child: pw.Text(body.isEmpty ? '-' : body,
                  style: const pw.TextStyle(fontSize: 11)),
            ),
          ],
        );

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
      await GmailPdfMailer.sendPdf(
        pdfBytes: pdfBytes,
        filename: filename,
        to: to,
        subject: subject,
        body: body,
      );
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
        tags: const <String>[
          _tReport,
          _tReportEnd,
          _tReportEmail,
          _tGmail,
          _tGmailSend,
        ],
      );
      rethrow;
    }
  }


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
                onPressed: () => _handleSpecialNoteSelection(value),
                style: SingleReportButtonStyles.primary(context),
                child: Text(label),
              )
            : OutlinedButton(
                onPressed: () => _handleSpecialNoteSelection(value),
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
          style:
              textTheme.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
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
          '※ 선택 결과는 메일 제목에 자동으로 반영됩니다.',
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
              color: cs.onSurface,
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '오늘 하루 동안 해당 업무의 출차 대수를 입력해 주세요.',
          style:
              textTheme.bodyMedium?.copyWith(height: 1.4, color: cs.onSurface),
        ),
        const SizedBox(height: 12),
        TextFormField(
          key: _vehicleFieldKey,
          controller: _vehicleCountCtrl,
          decoration:
              _inputDec(context, labelText: '출차 대수', hintText: '예: 12'),
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
            if (value.isEmpty) return '출차 대수를 입력하세요.';
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
                  Icon(Icons.info_outline,
                      size: 18, color: cs.onSurfaceVariant),
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
                '보고용 출차 대수는 직접 입력한 숫자로 저장됩니다.',
                style: textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
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
                    metricRow('출차', '직접 입력'),
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
            onPressed: (_firstSubmitting || !_isVehicleCountValid)
                ? null
                : _submitFirstEndReport,
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
      onChanged: (_) {
        if (_hasSpecialNote == true) {
          _persistDraft();
        }
      },
      validator: (v) {
        if (_hasSpecialNote == true) {
          if (v == null || v.trim().isEmpty) return '업무 내용을 입력하세요.';
        }
        return null;
      },
    );
  }

  void _saveSpecialContentAndGoToMail() {
    FocusScope.of(context).unfocus();

    if (_hasSpecialNote == null) {
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          1,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
      return;
    }

    if (_hasSpecialNote == true && _contentCtrl.text.trim().isEmpty) {
      _formKey.currentState?.validate();
      final ctx = _contentFieldKey.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
      _contentNode.requestFocus();
      return;
    }

    _updateMailBody(force: true);
    _persistDraft();

    if (!_pageController.hasClients) return;
    _pageController.animateToPage(
      3,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
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
          validator: (v) =>
              (v == null || v.trim().isEmpty) ? '메일 제목이 자동 생성되지 않았습니다.' : null,
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
                          Icon(Icons.edit_note_rounded,
                              size: 22, color: cs.onSurfaceVariant),
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
                            style: textTheme.bodySmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Divider(
                          height: 24,
                          color: cs.outlineVariant.withOpacity(0.7)),
                      const SizedBox(height: 4),
                      Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHigh,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: cs.outlineVariant.withOpacity(0.8)),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.info_outline,
                                size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '해당 업무의 수행 내용과 결과를 사실에 근거하여 간결하게 작성해 주세요.',
                                style: textTheme.bodySmall?.copyWith(
                                    height: 1.4, color: cs.onSurface),
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
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }

  Widget _gap(double h) => SizedBox(height: h);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        backgroundColor: cs.surface,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: '닫기',
            onPressed: (_sending || _firstSubmitting) ? null : _exitPage,
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
          ),
          title: const Text('업무 종료 보고서 작성'),
          centerTitle: true,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: Border(
              bottom: BorderSide(
                  color: cs.outlineVariant.withOpacity(0.8), width: 1)),
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
        bottomNavigationBar: (_currentPageIndex == 2 || _currentPageIndex == 3)
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
                    border: Border(
                        top: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.8),
                            width: 1)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_sending || _firstSubmitting)
                              ? null
                              : _goBackFromCurrentPage,
                          icon: const Icon(Icons.arrow_back_rounded),
                          label: const Text('이전'),
                          style: SingleReportButtonStyles.outlined(context),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: (_sending || _firstSubmitting)
                              ? null
                              : (_currentPageIndex == 2
                                  ? _saveSpecialContentAndGoToMail
                                  : _submit),
                          icon: _currentPageIndex == 3 && _sending
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        cs.onPrimary),
                                  ),
                                )
                              : Icon(_currentPageIndex == 2
                                  ? Icons.save_outlined
                                  : Icons.send_outlined),
                          label: Text(
                            _currentPageIndex == 2
                                ? '저장'
                                : (_sending ? '전송 중…' : '제출'),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: SingleReportButtonStyles.primary(context),
                        ),
                      ),
                    ],
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
              physics: const NeverScrollableScrollPhysics(),
              onPageChanged: (index) {
                if (!_firstSubmittedCompleted && index > 0) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!_pageController.hasClients) return;
                    _pageController.animateToPage(
                      0,
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeOut,
                    );
                  });
                  debugPrint(
                      '[SingleInsideEndReportFormPage] first submit required before proceeding to next step');
                  return;
                }

                if (!mounted) return;
                setState(() {
                  _currentPageIndex = index;
                });
              },
              children: [
                _buildReportPage(
                  sectionTitle: '1. 출차 대수',
                  sectionBody: _buildVehicleBody(),
                ),
                _buildReportPage(
                  sectionTitle: '2. 특이사항 여부 (필수)',
                  sectionBody: _buildSpecialNoteBody(),
                ),
                _buildReportPage(
                  sectionTitle: '3. 특이 사항 (조건부 필수)',
                  sectionBody: _buildWorkContentBody(),
                ),
                _buildReportPage(
                  sectionTitle: '4. 메일 전송 내용',
                  sectionBody: _buildMailBody(),
                ),
              ],
            ),
          ),
        ),
      ),
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
            const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 14),
            Expanded(
                child: Text(message,
                    style: const TextStyle(fontWeight: FontWeight.w700))),
          ],
        ),
      ),
    );
  }
}
