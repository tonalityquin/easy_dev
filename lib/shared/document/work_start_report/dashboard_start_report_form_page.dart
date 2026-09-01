import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/config/email_config.dart';
import '../../../app/utils/status_dialog.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../features/dev/debug/debug_api_logger.dart';
import '../../../features/selector/application/dev_auth.dart';
import '../../secondary/widgets/ops_console_widgets.dart';
import '../../utils/gmail_pdf_mailer.dart';

Future<void> showDashboardStartReportSideDock({
  required BuildContext context,
}) async {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  debugPrint(
    '[StartReportDock] route_push reduceMotion=$reduceMotion motion=operations_210_190',
  );
  await showOperationsRightSideDock<void>(
    context: context,
    useRootNavigator: true,
    barrierLabel: '업무 시작 보고',
    maxWidth: 360,
    widthFactor: .92,
    barrierDismissible: false,
    builder: (_) => const DashboardStartReportSideDock(),
  );
  debugPrint('[StartReportDock] route_closed');
}

class DashboardStartReportSideDock extends StatefulWidget {
  const DashboardStartReportSideDock({super.key});

  @override
  State<DashboardStartReportSideDock> createState() =>
      _DashboardStartReportSideDockState();
}

class _DashboardStartReportSideDockState
    extends State<DashboardStartReportSideDock> {
  static const String _tStart = 'start_report';
  static const String _tStartUi = 'start_report/ui';
  static const String _tStartPrefs = 'start_report/prefs';
  static const String _tStartEmail = 'start_report/email';
  static const String _tGmailSend = 'gmail/send';
  static const String _prefStartDraftHasSpecialNote =
      'start_report_draft_has_special_note';
  static const String _prefStartDraftContent = 'start_report_draft_content';
  static const int _maxDebugLines = 180;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _specialNoteKey = GlobalKey();
  final GlobalKey _contentFieldKey = GlobalKey();
  final TextEditingController _contentCtrl = TextEditingController();
  final FocusNode _contentNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final List<String> _debugLines = <String>[];

  bool? _hasSpecialNote;
  String? _selectedArea;
  String _recipient = '';
  bool _recipientValid = false;
  String _mailSubject = '';
  String _mailBody = '';
  DateTime _createdAt = DateTime.now();

  bool _initializing = true;
  bool _draftLoaded = false;
  bool _sending = false;
  bool _developerMode = false;
  bool _specialNoteInvalid = false;
  bool _contentInvalid = false;
  String _lastFailure = '';
  String _submitStage = 'idle';

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _developerMode = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_onDeveloperModeChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initialize());
    });
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_onDeveloperModeChanged);
    _contentCtrl.dispose();
    _contentNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onDeveloperModeChanged() {
    if (!mounted) return;
    final next = DevAuth.devModeEnabled.value;
    if (next == _developerMode) return;
    setState(() => _developerMode = next);
    _recordDebug('developer_mode_changed enabled=$next');
  }

  void _recordDebug(String message) {
    final normalized = message.trim();
    if (normalized.isEmpty) return;
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    final stamp =
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${three(now.millisecond)}';
    final line = '[$stamp] [StartReportDock] $normalized';
    _debugLines.add(line);
    if (_debugLines.length > _maxDebugLines) {
      _debugLines.removeRange(0, _debugLines.length - _maxDebugLines);
    }
    debugPrint(line);
  }

  String get _debugPrintCode {
    if (_debugLines.isEmpty) {
      return 'debugPrint(${jsonEncode('[StartReportDock] 기록된 로그가 없습니다.')});';
    }
    return _debugLines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  Future<void> _initialize() async {
    _recordDebug('initialize_start');
    try {
      final devMode = await DevAuth.isDevModeEnabled();
      await _loadSelectedArea();
      await _loadDraft();
      await _loadRecipient();
      _createdAt = DateTime.now();
      _updateMailContent(forceBody: true);
      if (!mounted) return;
      setState(() {
        _developerMode = devMode;
        _initializing = false;
        _draftLoaded = true;
      });
      _recordDebug(
        'initialize_complete area=${_resolveReportArea()} special=${_hasSpecialNote ?? 'unset'} contentLen=${_contentCtrl.text.trim().length} recipientValid=$_recipientValid',
      );
    } catch (error, stackTrace) {
      _recordDebug('initialize_failure error=$error');
      _recordDebug('initialize_failure_stack\n$stackTrace');
      await _logApiError(
        tag: 'DashboardStartReportSideDock._initialize',
        message: '업무 시작 보고 초기화 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tStartUi, _tStart],
      );
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _lastFailure = 'initialize';
      });
      await StatusDialog.showFailure(
        context,
        title: '업무 시작 보고 초기화 실패',
        useCommonUi: true,
      );
      if (_developerMode && mounted) {
        await _showDeveloperStatus(failure: true);
      }
    }
  }

  Future<void> _loadSelectedArea() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final area = prefs.getString('selectedArea') ?? '';
      _selectedArea = area.trim().isEmpty ? null : area.trim();
      _recordDebug(
        'area_loaded fallbackConfigured=${(_selectedArea ?? '').isNotEmpty}',
      );
    } catch (error, stackTrace) {
      _selectedArea = null;
      _recordDebug('area_load_failure error=$error');
      await _logApiError(
        tag: 'DashboardStartReportSideDock._loadSelectedArea',
        message: 'SharedPreferences(selectedArea) 로드 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tStartPrefs, _tStartUi, _tStart],
      );
    }
  }

  Future<void> _loadDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasSpecialNote = prefs.getBool(_prefStartDraftHasSpecialNote);
      final content = prefs.getString(_prefStartDraftContent) ?? '';
      _hasSpecialNote = hasSpecialNote;
      _contentCtrl.text = hasSpecialNote == false ? '' : content;
      _recordDebug(
        'draft_load_complete special=${_hasSpecialNote ?? 'unset'} contentLen=${_contentCtrl.text.trim().length}',
      );
    } catch (error, stackTrace) {
      _recordDebug('draft_load_failure error=$error');
      await _logApiError(
        tag: 'DashboardStartReportSideDock._loadDraft',
        message: '업무 시작 보고 임시저장 데이터 로드 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tStartPrefs, _tStartUi, _tStart],
      );
    }
  }

  Future<void> _loadRecipient() async {
    try {
      final config = await EmailConfig.load();
      _recipient = config.to.trim();
      _recipientValid = EmailConfig.isValidToList(_recipient);
      _recordDebug(
        'recipient_loaded configured=${_recipient.isNotEmpty} valid=$_recipientValid count=${_recipientCount(_recipient)}',
      );
    } catch (error, stackTrace) {
      _recipient = '';
      _recipientValid = false;
      _recordDebug('recipient_load_failure error=$error');
      await _logApiError(
        tag: 'DashboardStartReportSideDock._loadRecipient',
        message: '업무 시작 보고 수신처 로드 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tStartEmail, _tStartUi, _tStart],
      );
    }
  }

  int _recipientCount(String csv) {
    return csv
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .length;
  }

  Future<void> _persistDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_hasSpecialNote == null) {
        await prefs.remove(_prefStartDraftHasSpecialNote);
      } else {
        await prefs.setBool(
          _prefStartDraftHasSpecialNote,
          _hasSpecialNote!,
        );
      }
      await prefs.setString(
        _prefStartDraftContent,
        _hasSpecialNote == true ? _contentCtrl.text.trim() : '',
      );
    } catch (error, stackTrace) {
      _recordDebug('draft_persist_failure error=$error');
      await _logApiError(
        tag: 'DashboardStartReportSideDock._persistDraft',
        message: '업무 시작 보고 임시저장 실패',
        error: error,
        extra: <String, dynamic>{
          'hasSpecialNote': _hasSpecialNote,
          'contentLen': _contentCtrl.text.trim().length,
          'stack': stackTrace.toString(),
        },
        tags: const <String>[_tStartPrefs, _tStartUi, _tStart],
      );
    }
  }

  Future<void> _clearDraft() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefStartDraftHasSpecialNote);
      await prefs.remove(_prefStartDraftContent);
      _recordDebug('draft_clear_complete');
    } catch (error, stackTrace) {
      _recordDebug('draft_clear_failure error=$error');
      await _logApiError(
        tag: 'DashboardStartReportSideDock._clearDraft',
        message: '업무 시작 보고 임시저장 데이터 삭제 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tStartPrefs, _tStartUi, _tStart],
      );
    }
  }

  Future<void> _logApiError({
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

  String _resolveReportArea() {
    try {
      final currentArea = context.read<AreaState>().currentArea.trim();
      if (currentArea.isNotEmpty) return currentArea;
    } catch (_) {}
    final selectedArea = (_selectedArea ?? '').trim();
    if (selectedArea.isNotEmpty) return selectedArea;
    return '업무';
  }

  String _fmtCompact(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _dateTag(DateTime value) {
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y$m$d';
  }

  void _updateMailContent({bool forceBody = false}) {
    final now = _createdAt;
    final area = _resolveReportArea();
    final suffix = _hasSpecialNote == null
        ? ''
        : _hasSpecialNote!
            ? ' - 특이사항 있음'
            : ' - 특이사항 없음';
    _mailSubject =
        '$area 업무 시작 보고서 – ${now.month}월 ${now.day}일자$suffix';
    if (forceBody || _mailBody.trim().isEmpty) {
      final hh = now.hour.toString().padLeft(2, '0');
      final mm = now.minute.toString().padLeft(2, '0');
      _mailBody =
          '본 보고서는 ${now.year}년 ${now.month}월 ${now.day}일 ${hh}시 ${mm}분 기준으로 작성된 업무 시작 보고서입니다.';
    }
  }

  Future<void> _setSpecialNote(bool value) async {
    if (_sending || _initializing) return;
    if (_hasSpecialNote == value && !_specialNoteInvalid) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _hasSpecialNote = value;
      _specialNoteInvalid = false;
      _contentInvalid = false;
      if (!value) {
        _contentCtrl.clear();
      }
      _createdAt = DateTime.now();
      _updateMailContent(forceBody: true);
    });
    _recordDebug(
      'special_note_changed value=$value contentCleared=${!value}',
    );
    await _persistDraft();
  }

  Future<void> _reset() async {
    if (_sending || _initializing) return;
    FocusScope.of(context).unfocus();
    _formKey.currentState?.reset();
    _contentCtrl.clear();
    await _clearDraft();
    if (!mounted) return;
    setState(() {
      _hasSpecialNote = null;
      _specialNoteInvalid = false;
      _contentInvalid = false;
      _createdAt = DateTime.now();
      _mailBody = '';
      _lastFailure = '';
      _submitStage = 'idle';
      _updateMailContent(forceBody: true);
    });
    _recordDebug('reset_complete');
    await HapticFeedback.selectionClick();
    if (_scrollController.hasClients) {
      await _scrollController.animateTo(
        0,
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
        curve: CommonUiMotion.enter,
      );
    }
  }

  Future<void> _ensureVisible(GlobalKey key) async {
    final targetContext = key.currentContext;
    if (targetContext == null) return;
    await Scrollable.ensureVisible(
      targetContext,
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      alignment: .18,
    );
  }

  Future<bool> _validateForSubmit() async {
    if (_hasSpecialNote == null) {
      setState(() => _specialNoteInvalid = true);
      _recordDebug('validation_failure reason=special_note_unselected');
      await HapticFeedback.heavyImpact();
      await _ensureVisible(_specialNoteKey);
      return false;
    }

    if (_hasSpecialNote == true && _contentCtrl.text.trim().isEmpty) {
      setState(() => _contentInvalid = true);
      _recordDebug('validation_failure reason=detail_empty');
      await HapticFeedback.heavyImpact();
      _contentNode.requestFocus();
      await _ensureVisible(_contentFieldKey);
      return false;
    }

    if (!_recipientValid) {
      _recordDebug('validation_failure reason=invalid_recipient');
      await _handleFailure(
        reason: 'invalid_recipient',
        error: StateError('invalid_recipient'),
        stackTrace: StackTrace.current,
        title: '업무 시작 보고 제출 실패',
      );
      return false;
    }

    return true;
  }

  Future<void> _submit() async {
    if (_sending || _initializing) return;
    FocusScope.of(context).unfocus();
    final valid = await _validateForSubmit();
    if (!valid || !mounted) return;

    setState(() {
      _sending = true;
      _lastFailure = '';
      _createdAt = DateTime.now();
      _mailBody = '';
      _updateMailContent(forceBody: true);
    });
    _submitStage = 'prepare';
    _recordDebug(
      'submit_start area=${_resolveReportArea()} special=$_hasSpecialNote contentLen=${_contentCtrl.text.trim().length} recipientCount=${_recipientCount(_recipient)}',
    );

    try {
      final toCsv = _recipient
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .join(', ');
      final subject = _mailSubject.trim();
      final body = _mailBody.trim();

      if (subject.isEmpty) {
        throw StateError('empty_subject');
      }

      _submitStage = 'pdf_build';
      _recordDebug('pdf_build_start');
      final pdfBytes = await _buildPdfBytes();
      _recordDebug('pdf_build_complete bytes=${pdfBytes.length}');

      _submitStage = 'gmail_send';
      final filename = _safeFileName('업무시작보고서_${_dateTag(_createdAt)}');
      _recordDebug(
        'gmail_send_start recipientCount=${_recipientCount(toCsv)} subjectLen=${subject.length}',
      );
      await GmailPdfMailer.sendPdf(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );
      _recordDebug('gmail_send_complete');

      _submitStage = 'draft_clear';
      await _clearDraft();
      _submitStage = 'complete';
      _recordDebug('submit_complete');

      if (!mounted) return;
      setState(() => _sending = false);
      await HapticFeedback.lightImpact();
      await StatusDialog.showSuccess(
        context,
        title: StatusDialog.workStartReportSuccess,
        useCommonUi: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() => _sending = false);
      }
      await _handleFailure(
        reason: _submitStage,
        error: error,
        stackTrace: stackTrace,
        title: '업무 시작 보고 제출 실패',
      );
    }
  }

  Future<void> _handleFailure({
    required String reason,
    required Object error,
    required StackTrace stackTrace,
    required String title,
  }) async {
    _lastFailure = reason;
    _recordDebug('failure reason=$reason error=$error');
    _recordDebug('failure_stack reason=$reason\n$stackTrace');
    await _logApiError(
      tag: 'DashboardStartReportSideDock.$reason',
      message: title,
      error: error,
      extra: <String, dynamic>{
        'reason': reason,
        'stack': stackTrace.toString(),
        'hasSpecialNote': _hasSpecialNote,
        'contentLen': _contentCtrl.text.trim().length,
        'recipientValid': _recipientValid,
      },
      tags: const <String>[_tStartEmail, _tStartUi, _tStart, _tGmailSend],
    );
    if (!mounted) return;
    await HapticFeedback.heavyImpact();
    await StatusDialog.showFailure(
      context,
      title: title,
      useCommonUi: true,
    );
    if (_developerMode && mounted) {
      await _showDeveloperStatus(failure: true);
    }
  }

  Future<void> _showDeveloperStatus({bool failure = false}) async {
    if (!_developerMode || !mounted) return;
    _recordDebug(
      'developer_status_open failure=$failure special=${_hasSpecialNote ?? 'unset'} contentLen=${_contentCtrl.text.trim().length} sending=$_sending recipientValid=$_recipientValid stage=$_submitStage lastFailure=${_lastFailure.isEmpty ? 'none' : _lastFailure}',
    );
    final description = <String>[
      '지역: ${_resolveReportArea()}',
      '특이사항: ${_hasSpecialNote == null ? '미선택' : (_hasSpecialNote! ? '있음' : '없음')}',
      '내용 길이: ${_contentCtrl.text.trim().length}',
      '임시저장 로드: $_draftLoaded',
      '초기화 중: $_initializing',
      '전송 중: $_sending',
      '수신처 유효: $_recipientValid',
      '수신처 개수: ${_recipientCount(_recipient)}',
      '제출 단계: $_submitStage',
      '마지막 실패: ${_lastFailure.isEmpty ? '없음' : _lastFailure}',
      '애니메이션 감소: $_reduceMotion',
    ].join('\n');

    if (failure) {
      await StatusDialog.showFailure(
        context,
        title: '업무 시작 보고 상태',
        description: description,
        copyText: _debugPrintCode,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: Duration.zero,
        useCommonUi: true,
        awaitManualClose: true,
      );
      return;
    }

    await StatusDialog.showSuccess(
      context,
      title: '업무 시작 보고 상태',
      description: description,
      copyText: _debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  void _closeDock() {
    if (_sending) return;
    _recordDebug(
      'dock_close special=${_hasSpecialNote ?? 'unset'} contentLen=${_contentCtrl.text.trim().length}',
    );
    Navigator.of(context).pop();
  }

  String _buildPreviewText() {
    final specialText = _hasSpecialNote == null
        ? '미선택'
        : _hasSpecialNote!
            ? '있음'
            : '없음';
    return <String>[
      '업무 시작 보고',
      '지역: ${_resolveReportArea()}',
      '작성 시각: ${_fmtCompact(_createdAt)}',
      '특이사항: $specialText',
      if (_hasSpecialNote == true) '특이사항 내용: ${_contentCtrl.text.trim()}',
      '수신처: ${_recipient.trim().isEmpty ? '미설정' : _recipient.trim()}',
      '메일 제목: $_mailSubject',
      '메일 본문: $_mailBody',
    ].join('\n');
  }

  Future<void> _copyPreviewText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    await HapticFeedback.lightImpact();
    _recordDebug('preview_copy length=${text.length}');
    if (!mounted) return;
    await StatusDialog.showSuccess(
      context,
      title: '텍스트 복사 완료',
      useCommonUi: true,
    );
  }

  Future<void> _showPreview() async {
    if (_sending || _initializing) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _createdAt = DateTime.now();
      _mailBody = '';
      _updateMailContent(forceBody: true);
    });
    _recordDebug('preview_open');
    final previewText = _buildPreviewText();

    await showCommonOverlayDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
        final textTheme = Theme.of(dialogContext).textTheme;
        final maxHeight = MediaQuery.of(dialogContext).size.height * .78;
        return Dialog(
          backgroundColor: tokens.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 520, maxHeight: maxHeight),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
              child: Material(
                color: tokens.canvas,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        border: Border(
                          bottom: BorderSide(color: tokens.borderSubtle),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: tokens.accentContainer,
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              Icons.visibility_outlined,
                              size: 20,
                              color: tokens.onAccentContainer,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              '업무 시작 보고 미리보기',
                              style: textTheme.titleMedium?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          CommonIconButton(
                            icon: Icons.close_rounded,
                            tooltip: '닫기',
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            haptic: CommonHaptic.selection,
                            size: 38,
                            iconSize: 19,
                          ),
                        ],
                      ),
                    ),
                    Flexible(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OpsDockListSurface(
                              child: Column(
                                children: [
                                  _StartReportValueRow(
                                    label: '지역',
                                    value: _resolveReportArea(),
                                  ),
                                  _divider(tokens),
                                  _StartReportValueRow(
                                    label: '작성 시각',
                                    value: _fmtCompact(_createdAt),
                                  ),
                                  _divider(tokens),
                                  _StartReportValueRow(
                                    label: '특이사항',
                                    value: _hasSpecialNote == null
                                        ? '미선택'
                                        : _hasSpecialNote!
                                            ? '있음'
                                            : '없음',
                                  ),
                                  _divider(tokens),
                                  _StartReportValueRow(
                                    label: '수신처',
                                    value: _recipient.trim().isEmpty
                                        ? '미설정'
                                        : _recipient.trim(),
                                  ),
                                  _divider(tokens),
                                  _StartReportValueRow(
                                    label: '메일 제목',
                                    value: _mailSubject,
                                    maxValueLines: 3,
                                  ),
                                  _divider(tokens),
                                  _StartReportValueRow(
                                    label: '메일 본문',
                                    value: _mailBody,
                                    maxValueLines: 4,
                                  ),
                                ],
                              ),
                            ),
                            if (_hasSpecialNote == true) ...[
                              const SizedBox(height: 10),
                              _PreviewDetailSurface(
                                title: '특이사항 내용',
                                body: _contentCtrl.text.trim().isEmpty
                                    ? '-'
                                    : _contentCtrl.text.trim(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    OpsDockContextFooter(
                      children: [
                        Expanded(
                          child: CommonButton(
                            label: '텍스트 복사',
                            icon: Icons.copy_all_rounded,
                            variant: CommonButtonVariant.secondary,
                            minHeight: 46,
                            expand: true,
                            haptic: CommonHaptic.selection,
                            onPressed: () => _copyPreviewText(previewText),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: CommonButton(
                            label: '닫기',
                            variant: CommonButtonVariant.tertiary,
                            minHeight: 46,
                            expand: true,
                            onPressed: () => Navigator.of(dialogContext).pop(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
    _recordDebug('preview_close');
  }

  String _safeFileName(String raw) {
    final value = raw.trim().isEmpty ? '업무시작보고서' : raw.trim();
    return value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<Uint8List> _buildPdfBytes() async {
    pw.Font? regular;
    pw.Font? bold;

    try {
      final data =
          await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
      regular = pw.Font.ttf(data);
    } catch (_) {}

    try {
      final data =
          await rootBundle.load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
      bold = pw.Font.ttf(data);
    } catch (_) {
      bold = regular;
    }

    final theme = regular != null
        ? pw.ThemeData.withFont(
            base: regular,
            bold: bold ?? regular,
            italic: regular,
            boldItalic: bold ?? regular,
          )
        : pw.ThemeData.base();
    final document = pw.Document();
    final specialText = _hasSpecialNote == null
        ? '미선택'
        : _hasSpecialNote!
            ? '있음'
            : '없음';

    document.addPage(
      pw.MultiPage(
        theme: theme,
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(32, 36, 32, 36),
        build: (_) => [
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
          _pdfFieldTable(
            <MapEntry<String, String>>[
              MapEntry<String, String>('지역', _resolveReportArea()),
              MapEntry<String, String>('특이사항', specialText),
            ],
          ),
          if (_hasSpecialNote == true)
            _pdfSection('특이사항 내용', _contentCtrl.text.trim()),
        ],
        footer: (_) => pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            '생성 시각: ${_fmtCompact(_createdAt)}',
            style: const pw.TextStyle(
              fontSize: 9,
              color: PdfColors.grey700,
            ),
          ),
        ),
      ),
    );

    return document.save();
  }

  pw.Widget _pdfFieldTable(List<MapEntry<String, String>> fields) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey400, width: .5),
      columnWidths: const <int, pw.TableColumnWidth>{
        0: pw.FlexColumnWidth(3),
        1: pw.FlexColumnWidth(7),
      },
      children: [
        for (final field in fields)
          pw.TableRow(
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                color: PdfColors.grey200,
                child: pw.Text(
                  field.key,
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  field.value,
                  style: const pw.TextStyle(fontSize: 11),
                ),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget _pdfSection(String title, String body) {
    return pw.Column(
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
            border: pw.Border.all(color: PdfColors.grey400, width: .5),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(
            body.isEmpty ? '-' : body,
            style: const pw.TextStyle(fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _divider(CommonUiTokens tokens) {
    return Divider(
      height: 1,
      thickness: 1,
      color: tokens.borderSubtle,
    );
  }

  Widget _buildContextStrip(CommonUiTokens tokens) {
    final textTheme = Theme.of(context).textTheme;
    return CommonSideDockReveal(
      order: 1,
      offsetY: 6,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Row(
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 18,
              color: tokens.iconSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: _reduceMotion
                    ? Duration.zero
                    : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                child: Text(
                  _fmtCompact(_createdAt),
                  key: ValueKey<String>(_fmtCompact(_createdAt)),
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              decoration: BoxDecoration(
                color: _recipientValid
                    ? tokens.successContainer
                    : tokens.warningContainer,
                borderRadius: BorderRadius.circular(CommonUiShapes.pill),
              ),
              child: Text(
                _recipientValid ? '전송 준비' : '수신처 확인',
                style: textTheme.labelSmall?.copyWith(
                  color: _recipientValid
                      ? tokens.onSuccessContainer
                      : tokens.onWarningContainer,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSpecialNoteRow(CommonUiTokens tokens) {
    final textTheme = Theme.of(context).textTheme;
    return AnimatedContainer(
      key: _specialNoteKey,
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      padding: const EdgeInsets.fromLTRB(11, 10, 11, 11),
      decoration: BoxDecoration(
        color: _specialNoteInvalid
            ? tokens.dangerContainer.withOpacity(.46)
            : tokens.transparent,
        border: _specialNoteInvalid
            ? Border.all(color: tokens.danger.withOpacity(.72))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.report_problem_outlined,
                size: 18,
                color: tokens.iconSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                '특이사항',
                style: textTheme.bodyMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Spacer(),
              AnimatedSwitcher(
                duration: _reduceMotion
                    ? Duration.zero
                    : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                child: Text(
                  _hasSpecialNote == null
                      ? '미선택'
                      : _hasSpecialNote!
                          ? '있음'
                          : '없음',
                  key: ValueKey<String>('special-${_hasSpecialNote ?? 'unset'}'),
                  style: textTheme.bodySmall?.copyWith(
                    color: _specialNoteInvalid
                        ? tokens.danger
                        : tokens.textSecondary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: CommonButton(
                  label: '없음',
                  variant: _hasSpecialNote == false
                      ? CommonButtonVariant.primary
                      : CommonButtonVariant.secondary,
                  selected: _hasSpecialNote == false,
                  onPressed: _sending || _initializing
                      ? null
                      : () => _setSpecialNote(false),
                  minHeight: 44,
                  expand: true,
                  haptic: CommonHaptic.selection,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: CommonButton(
                  label: '있음',
                  variant: _hasSpecialNote == true
                      ? CommonButtonVariant.primary
                      : CommonButtonVariant.secondary,
                  selected: _hasSpecialNote == true,
                  onPressed: _sending || _initializing
                      ? null
                      : () => _setSpecialNote(true),
                  minHeight: 44,
                  expand: true,
                  haptic: CommonHaptic.selection,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildListSurface(CommonUiTokens tokens) {
    return CommonSideDockReveal(
      order: 2,
      offsetY: 7,
      child: OpsDockListSurface(
        child: Column(
          children: [
            _buildSpecialNoteRow(tokens),
            _divider(tokens),
            _StartReportValueRow(
              label: '작성 시각',
              value: _fmtCompact(_createdAt),
              icon: Icons.schedule_rounded,
            ),
            _divider(tokens),
            _StartReportValueRow(
              label: '메일 제목',
              value: _mailSubject,
              icon: Icons.subject_rounded,
              maxValueLines: 2,
            ),
            _divider(tokens),
            _StartReportValueRow(
              label: '수신처',
              value: _recipient.trim().isEmpty ? '미설정' : _recipient.trim(),
              icon: Icons.alternate_email_rounded,
              maxValueLines: 2,
              valueColor: _recipientValid ? null : tokens.warning,
            ),
            _divider(tokens),
            _StartReportValueRow(
              label: '메일 내용',
              value: '자동 생성됨',
              icon: Icons.mail_outline_rounded,
              trailingIcon: Icons.chevron_right_rounded,
              onTap: _sending || _initializing ? null : _showPreview,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailSurface(CommonUiTokens tokens) {
    final textTheme = Theme.of(context).textTheme;
    final duration = _reduceMotion ? Duration.zero : CommonUiMotion.component;
    return AnimatedSize(
      duration: duration,
      curve: CommonUiMotion.enter,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: duration,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) {
          if (_reduceMotion) return child;
          final curved = CurvedAnimation(
            parent: animation,
            curve: CommonUiMotion.enter,
            reverseCurve: CommonUiMotion.exit,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, .045),
                end: Offset.zero,
              ).animate(curved),
              child: ScaleTransition(
                scale: Tween<double>(begin: .985, end: 1).animate(curved),
                child: child,
              ),
            ),
          );
        },
        child: _hasSpecialNote == true
            ? Container(
                key: const ValueKey<String>('start-report-detail-visible'),
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _contentInvalid
                        ? tokens.danger
                        : tokens.borderSubtle,
                    width: _contentInvalid ? 1.3 : 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: tokens.shadow,
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  key: _contentFieldKey,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.edit_note_rounded,
                          size: 18,
                          color: tokens.iconSecondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '특이사항 내용',
                          style: textTheme.bodyMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 9),
                    Form(
                      key: _formKey,
                      child: TextFormField(
                        controller: _contentCtrl,
                        focusNode: _contentNode,
                        enabled: !_sending,
                        keyboardType: TextInputType.multiline,
                        minLines: 7,
                        maxLines: 12,
                        autovalidateMode: AutovalidateMode.onUserInteraction,
                        validator: (value) {
                          if (_hasSpecialNote == true &&
                              (value == null || value.trim().isEmpty)) {
                            return '업무 내용을 입력하세요.';
                          }
                          return null;
                        },
                        onChanged: (_) {
                          if (_contentInvalid) {
                            setState(() => _contentInvalid = false);
                          }
                          unawaited(_persistDraft());
                        },
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: tokens.surfaceOverlay,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CommonUiShapes.control,
                            ),
                            borderSide: BorderSide(color: tokens.borderSubtle),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CommonUiShapes.control,
                            ),
                            borderSide: BorderSide(color: tokens.borderSubtle),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CommonUiShapes.control,
                            ),
                            borderSide: BorderSide(
                              color: tokens.focusRing,
                              width: 2,
                            ),
                          ),
                          errorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CommonUiShapes.control,
                            ),
                            borderSide: BorderSide(color: tokens.danger),
                          ),
                          focusedErrorBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              CommonUiShapes.control,
                            ),
                            borderSide: BorderSide(
                              color: tokens.danger,
                              width: 2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const SizedBox.shrink(
                key: ValueKey<String>('start-report-detail-hidden'),
              ),
      ),
    );
  }

  Widget _buildFooter() {
    return OpsDockContextFooter(
      children: [
        Expanded(
          child: CommonButton(
            label: '초기화',
            variant: CommonButtonVariant.tertiary,
            minHeight: 46,
            expand: true,
            onPressed: _sending || _initializing ? null : _reset,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: CommonButton(
            label: '미리보기',
            variant: CommonButtonVariant.secondary,
            minHeight: 46,
            expand: true,
            onPressed: _sending || _initializing ? null : _showPreview,
            haptic: CommonHaptic.selection,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: CommonButton(
            label: _sending ? '전송 중' : '제출',
            variant: CommonButtonVariant.primary,
            minHeight: 46,
            expand: true,
            loading: _sending,
            preserveVariantWhenDisabled: true,
            onPressed: _sending || _initializing ? null : _submit,
            haptic: CommonHaptic.light,
          ),
        ),
      ],
    );
  }

  Widget _buildContentCanvas(CommonUiTokens tokens) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(CommonUiShapes.card),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.canvas,
          border: Border.all(color: tokens.borderSubtle),
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
        ),
        child: Stack(
          children: [
            SingleChildScrollView(
              controller: _scrollController,
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildContextStrip(tokens),
                  const SizedBox(height: 10),
                  _buildListSurface(tokens),
                  _buildDetailSurface(tokens),
                ],
              ),
            ),
            OpsDockLoadingOverlay(loading: _initializing || _sending),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final area = _resolveReportArea();

    return CommonSideDockFrame(
      title: '업무 시작 보고',
      subtitle: '$area · 업무 시작',
      icon: Icons.play_circle_outline_rounded,
      closeEnabled: !_sending,
      onClose: _closeDock,
      onLongPress: _developerMode ? _showDeveloperStatus : null,
      headerAction: AnimatedSwitcher(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .88, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: _developerMode
            ? CommonIconButton(
                key: const ValueKey<String>('start-report-debug-visible'),
                icon: Icons.bug_report_rounded,
                tooltip: '디버그 상태',
                onPressed: _showDeveloperStatus,
                haptic: CommonHaptic.selection,
                size: 38,
                iconSize: 19,
              )
            : const SizedBox.shrink(
                key: ValueKey<String>('start-report-debug-hidden'),
              ),
      ),
      footer: _buildFooter(),
      child: _buildContentCanvas(tokens),
    );
  }
}

class _StartReportValueRow extends StatefulWidget {
  const _StartReportValueRow({
    required this.label,
    required this.value,
    this.icon,
    this.trailingIcon,
    this.onTap,
    this.maxValueLines = 1,
    this.valueColor,
  });

  final String label;
  final String value;
  final IconData? icon;
  final IconData? trailingIcon;
  final VoidCallback? onTap;
  final int maxValueLines;
  final Color? valueColor;

  @override
  State<_StartReportValueRow> createState() => _StartReportValueRowState();
}

class _StartReportValueRowState extends State<_StartReportValueRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final interactive = widget.onTap != null;

    return AnimatedScale(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
      curve: CommonUiMotion.enter,
      scale: _pressed && interactive ? .985 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: interactive
              ? (value) {
                  if (!mounted) return;
                  setState(() => _pressed = value);
                }
              : null,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            curve: CommonUiMotion.standard,
            color: _pressed && interactive
                ? tokens.surfaceSelected.withOpacity(.5)
                : tokens.transparent,
            padding: const EdgeInsets.fromLTRB(11, 10, 11, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.icon != null) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      widget.icon,
                      size: 18,
                      color: tokens.iconSecondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: 4,
                  child: Text(
                    widget.label,
                    style: textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 7,
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : CommonUiMotion.selection,
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, .08),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      widget.value,
                      key: ValueKey<String>(widget.value),
                      maxLines: widget.maxValueLines,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: textTheme.bodySmall?.copyWith(
                        color: widget.valueColor ?? tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
                if (widget.trailingIcon != null) ...[
                  const SizedBox(width: 5),
                  Icon(
                    widget.trailingIcon,
                    size: 18,
                    color: interactive
                        ? tokens.iconSecondary
                        : tokens.iconDisabled,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PreviewDetailSurface extends StatelessWidget {
  const _PreviewDetailSurface({
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: textTheme.bodyMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: textTheme.bodySmall?.copyWith(
              color: tokens.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
