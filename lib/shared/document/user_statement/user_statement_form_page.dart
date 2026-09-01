import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:provider/provider.dart';

import '../../../app/auth/gmail_sender_auth.dart';
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
import 'user_statement_signature_dialog.dart';

Future<void> showUserStatementSideDock({
  required BuildContext context,
}) async {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  debugPrint(
    '[UserStatementDock] route_push reduceMotion=$reduceMotion motion=operations_210_190',
  );
  await showOperationsRightSideDock<void>(
    context: context,
    useRootNavigator: true,
    barrierLabel: '경위서',
    maxWidth: 360,
    widthFactor: .92,
    barrierDismissible: false,
    builder: (_) => const UserStatementSideDock(),
  );
  debugPrint('[UserStatementDock] route_closed');
}

class UserStatementSideDock extends StatefulWidget {
  const UserStatementSideDock({super.key});

  @override
  State<UserStatementSideDock> createState() => _UserStatementSideDockState();
}

class _UserStatementSideDockState extends State<UserStatementSideDock> {
  static const String _tStatement = 'statement';
  static const String _tStatementForm = 'statement/form';
  static const String _tStatementPdf = 'statement/pdf';
  static const String _tStatementEmail = 'statement/email';
  static const String _tGmailSend = 'gmail/send';
  static const int _mimeB64LineLength = 76;
  static const int _maxDebugLines = 180;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _eventKey = GlobalKey();
  final GlobalKey _contentKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final List<String> _debugLines = <String>[];

  final TextEditingController _deptCtrl = TextEditingController();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _positionCtrl = TextEditingController();
  final TextEditingController _contentCtrl = TextEditingController();
  final TextEditingController _mailSubjectCtrl = TextEditingController();
  final TextEditingController _mailBodyCtrl = TextEditingController();

  final FocusNode _deptNode = FocusNode();
  final FocusNode _nameNode = FocusNode();
  final FocusNode _positionNode = FocusNode();
  final FocusNode _contentNode = FocusNode();

  DateTime? _eventDateTime;
  Uint8List? _signaturePngBytes;
  DateTime? _signDateTime;
  String _recipient = '';
  bool _recipientValid = false;
  bool _initializing = true;
  bool _sending = false;
  bool _developerMode = false;
  bool _eventInvalid = false;
  bool _contentInvalid = false;
  String _submitStage = 'idle';
  String _lastFailure = '';

  String get _signerName => _nameCtrl.text.trim();
  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  @override
  void initState() {
    super.initState();
    _developerMode = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_onDeveloperModeChanged);
    _nameCtrl.addListener(_onNameChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initialize());
    });
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_onDeveloperModeChanged);
    _nameCtrl.removeListener(_onNameChanged);
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
    _scrollController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onDeveloperModeChanged() {
    if (!mounted) return;
    final next = DevAuth.devModeEnabled.value;
    if (_developerMode == next) return;
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
    final line = '[$stamp] [UserStatementDock] $normalized';
    _debugLines.add(line);
    if (_debugLines.length > _maxDebugLines) {
      _debugLines.removeRange(0, _debugLines.length - _maxDebugLines);
    }
    debugPrint(line);
  }

  String get _debugPrintCode {
    if (_debugLines.isEmpty) {
      return 'debugPrint(${jsonEncode('[UserStatementDock] 기록된 로그가 없습니다.')});';
    }
    return _debugLines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  Future<void> _initialize() async {
    _recordDebug('initialize_start');
    try {
      final developerMode = await DevAuth.isDevModeEnabled();
      await _loadRecipient();
      if (!mounted) return;
      setState(() {
        _developerMode = developerMode;
        _initializing = false;
      });
      _recordDebug(
        'initialize_complete area=${_resolveArea()} recipientValid=$_recipientValid',
      );
    } catch (error, stackTrace) {
      _recordDebug('initialize_failure error=$error');
      _recordDebug('initialize_failure_stack\n$stackTrace');
      await _logApiError(
        tag: 'UserStatementSideDock._initialize',
        message: '경위서 초기화 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tStatementForm, _tStatement],
      );
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _lastFailure = 'initialize';
      });
      await StatusDialog.showFailure(
        context,
        title: '경위서 초기화 실패',
        useCommonUi: true,
      );
      if (_developerMode && mounted) {
        await _showDeveloperStatus(failure: true);
      }
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
        tag: 'UserStatementSideDock._loadRecipient',
        message: '경위서 수신처 로드 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tStatementEmail, _tStatement],
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

  String _resolveArea() {
    try {
      final area = context.read<AreaState>().currentArea.trim();
      if (area.isNotEmpty) return area;
    } catch (_) {}
    return '업무';
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

  Future<void> _pickDateTime() async {
    if (_sending) return;
    try {
      final now = DateTime.now();
      final date = await showCommonDatePicker(
        context: context,
        initialDate: _eventDateTime ?? now,
        firstDate: DateTime(now.year - 5),
        lastDate: DateTime(now.year + 5),
      );
      if (!mounted || date == null) return;
      final time = await showCommonTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_eventDateTime ?? now),
        builder: (ctx, child) => MediaQuery(
          data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
          child: child!,
        ),
      );
      if (!mounted || time == null) return;
      setState(() {
        _eventDateTime = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        );
        _eventInvalid = false;
      });
      _recordDebug('event_datetime_changed configured=true');
    } catch (error, stackTrace) {
      _recordDebug('event_datetime_failure error=$error');
      await _logApiError(
        tag: 'UserStatementSideDock._pickDateTime',
        message: '경위서 사건 일시 선택 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tStatementForm, _tStatement],
      );
      if (!mounted) return;
      await _handleFailure(
        reason: 'event_datetime',
        error: error,
        stackTrace: stackTrace,
        title: '사건 일시 선택 실패',
      );
    }
  }

  void _reset() {
    if (_sending) return;
    FocusScope.of(context).unfocus();
    _formKey.currentState?.reset();
    _deptCtrl.clear();
    _nameCtrl.clear();
    _positionCtrl.clear();
    _contentCtrl.clear();
    _mailSubjectCtrl.clear();
    _mailBodyCtrl.clear();
    setState(() {
      _eventDateTime = null;
      _signaturePngBytes = null;
      _signDateTime = null;
      _eventInvalid = false;
      _contentInvalid = false;
      _submitStage = 'idle';
      _lastFailure = '';
    });
    _recordDebug('reset_complete');
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
        curve: CommonUiMotion.enter,
      );
    }
  }

  Future<void> _openSignatureDialog() async {
    if (_sending) return;
    _recordDebug('signature_open');
    try {
      final result = await showUserStatementSignatureOverlay(
        context: context,
        name: _signerName,
        initialDateTime: _signDateTime,
      );
      if (result == null || !mounted) return;
      setState(() {
        _signaturePngBytes = result.pngBytes;
        _signDateTime = result.signDateTime;
      });
      await HapticFeedback.lightImpact();
      _recordDebug('signature_saved bytes=${result.pngBytes.length}');
    } catch (error, stackTrace) {
      _recordDebug('signature_failure error=$error');
      await _logApiError(
        tag: 'UserStatementSideDock._openSignatureDialog',
        message: '경위서 전자서명 처리 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tStatementForm, _tStatement],
      );
      if (!mounted) return;
      await _handleFailure(
        reason: 'signature',
        error: error,
        stackTrace: stackTrace,
        title: '전자서명 처리 실패',
      );
    }
  }

  void _removeSignature() {
    if (_sending || _signaturePngBytes == null) return;
    setState(() {
      _signaturePngBytes = null;
      _signDateTime = null;
    });
    _recordDebug('signature_removed');
  }

  String _buildPreviewText() {
    final signature = _signaturePngBytes == null
        ? '미첨부'
        : '${_signerName.isEmpty ? '이름 미입력' : _signerName} / ${_signDateTime == null ? '시각 미기록' : _fmtCompact(_signDateTime!)}';
    return <String>[
      '경위서',
      '지역: ${_resolveArea()}',
      '소속: ${_deptCtrl.text.trim()}',
      '성명: ${_nameCtrl.text.trim()}',
      '직책: ${_positionCtrl.text.trim()}',
      '사건 일시: ${_fmtDT(context, _eventDateTime)}',
      '내용: ${_contentCtrl.text.trim()}',
      '전자서명: $signature',
      '수신처: ${_recipient.isEmpty ? '미설정' : _recipient}',
      '메일 제목: ${_mailSubjectCtrl.text.trim()}',
      '메일 본문: ${_mailBodyCtrl.text.trim()}',
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
    if (_sending) return;
    FocusScope.of(context).unfocus();
    _recordDebug('preview_open');
    final text = _buildPreviewText();
    await showCommonOverlayDialog<void>(
      context: context,
      barrierLabel: '경위서 미리보기',
      builder: (dialogContext) {
        final tokens = CommonUiTheme.of(dialogContext);
        final media = MediaQuery.of(dialogContext);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 620,
            maxHeight: media.size.height * .82,
          ),
          child: Material(
            color: tokens.surfaceRaised,
            borderRadius: BorderRadius.circular(CommonUiShapes.sheet),
            clipBehavior: Clip.antiAlias,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _PreviewHeader(
                  title: '경위서 미리보기',
                  onClose: () => Navigator.of(dialogContext).pop(),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      children: [
                        OpsDockListSurface(
                          child: Column(
                            children: [
                              _StaticValueRow(label: '지역', value: _resolveArea()),
                              _DockDivider(),
                              _StaticValueRow(
                                label: '사건 일시',
                                value: _fmtDT(context, _eventDateTime),
                              ),
                              _DockDivider(),
                              _StaticValueRow(
                                label: '전자서명',
                                value: _signaturePngBytes == null ? '미첨부' : '완료',
                              ),
                              _DockDivider(),
                              _StaticValueRow(
                                label: '수신처',
                                value: _recipient.isEmpty ? '미설정' : _recipient,
                                maxLines: 2,
                              ),
                              _DockDivider(),
                              _StaticValueRow(
                                label: '메일 제목',
                                value: _mailSubjectCtrl.text.trim().isEmpty
                                    ? '미입력'
                                    : _mailSubjectCtrl.text.trim(),
                                maxLines: 2,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DetailSurface(
                          title: '사실 관계',
                          child: SelectableText(
                            _contentCtrl.text.trim().isEmpty
                                ? '미입력'
                                : _contentCtrl.text.trim(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        _DetailSurface(
                          title: '메일 본문',
                          child: SelectableText(
                            _mailBodyCtrl.text.trim().isEmpty
                                ? '미입력'
                                : _mailBodyCtrl.text.trim(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                OpsDockContextFooter(
                  children: [
                    Expanded(
                      child: CommonButton(
                        label: '텍스트 복사',
                        icon: Icons.copy_rounded,
                        onPressed: () => _copyPreviewText(text),
                        variant: CommonButtonVariant.secondary,
                        expand: true,
                        haptic: CommonHaptic.selection,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: CommonButton(
                        label: '닫기',
                        icon: Icons.close_rounded,
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        variant: CommonButtonVariant.tertiary,
                        expand: true,
                        haptic: CommonHaptic.selection,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    _recordDebug('preview_close');
  }

  Future<void> _submit() async {
    if (_sending || _initializing) return;
    FocusScope.of(context).unfocus();
    final formValid = _formKey.currentState?.validate() ?? false;
    final eventValid = _eventDateTime != null;
    final contentValid = _contentCtrl.text.trim().isNotEmpty;
    if (!formValid || !eventValid || !contentValid || !_recipientValid) {
      setState(() {
        _eventInvalid = !eventValid;
        _contentInvalid = !contentValid;
      });
      _recordDebug(
        'validation_failure form=$formValid event=$eventValid content=$contentValid recipient=$_recipientValid',
      );
      if (!eventValid) {
        await _scrollTo(_eventKey);
      } else if (!contentValid) {
        await _scrollTo(_contentKey);
        _contentNode.requestFocus();
      }
      if (!_recipientValid && mounted) {
        await StatusDialog.showFailure(
          context,
          title: '경위서 제출 실패',
          useCommonUi: true,
        );
      }
      return;
    }

    setState(() {
      _sending = true;
      _lastFailure = '';
    });
    _submitStage = 'prepare';
    _recordDebug(
      'submit_start deptLen=${_deptCtrl.text.trim().length} nameLen=${_nameCtrl.text.trim().length} positionLen=${_positionCtrl.text.trim().length} contentLen=${_contentCtrl.text.trim().length} signature=${_signaturePngBytes != null} recipientCount=${_recipientCount(_recipient)}',
    );

    try {
      final toCsv = _recipient
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .join(', ');
      final subject = _mailSubjectCtrl.text.trim();
      final body = _mailBodyCtrl.text.trim();
      if (subject.isEmpty) throw StateError('empty_subject');

      _submitStage = 'pdf_build';
      _recordDebug('pdf_build_start');
      final pdfBytes = await _buildPdfBytes();
      _recordDebug('pdf_build_complete bytes=${pdfBytes.length}');

      _submitStage = 'gmail_send';
      final now = DateTime.now();
      final nameForFile =
          _nameCtrl.text.trim().isEmpty ? '무기명' : _nameCtrl.text.trim();
      final filename = _safeFileName(
        '경위서_${nameForFile}_${_dateTag(now)}',
      );
      _recordDebug(
        'gmail_send_start recipientCount=${_recipientCount(toCsv)} subjectLen=${subject.length}',
      );
      await _sendEmailViaGmail(
        pdfBytes: pdfBytes,
        filename: '$filename.pdf',
        to: toCsv,
        subject: subject,
        body: body,
      );
      _recordDebug('gmail_send_complete');

      _submitStage = 'complete';
      _recordDebug('submit_complete');
      if (!mounted) return;
      setState(() => _sending = false);
      await HapticFeedback.lightImpact();
      await StatusDialog.showSuccess(
        context,
        title: StatusDialog.userStatementSubmitSuccess,
        useCommonUi: true,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
    } catch (error, stackTrace) {
      if (mounted) setState(() => _sending = false);
      await _handleFailure(
        reason: _submitStage,
        error: error,
        stackTrace: stackTrace,
        title: '경위서 제출 실패',
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
    _recordDebug('failure_stack\n$stackTrace');
    await _logApiError(
      tag: 'UserStatementSideDock.$reason',
      message: title,
      error: error,
      extra: <String, dynamic>{
        'stack': stackTrace.toString(),
        'deptLen': _deptCtrl.text.trim().length,
        'nameLen': _nameCtrl.text.trim().length,
        'positionLen': _positionCtrl.text.trim().length,
        'contentLen': _contentCtrl.text.trim().length,
        'subjectLen': _mailSubjectCtrl.text.trim().length,
        'bodyLen': _mailBodyCtrl.text.trim().length,
        'eventConfigured': _eventDateTime != null,
        'signatureConfigured': _signaturePngBytes != null,
        'recipientValid': _recipientValid,
      },
      tags: const <String>[
        _tStatementForm,
        _tStatementEmail,
        _tStatement,
      ],
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
      'developer_status_open failure=$failure sending=$_sending stage=$_submitStage lastFailure=${_lastFailure.isEmpty ? 'none' : _lastFailure}',
    );
    final description = <String>[
      '지역: ${_resolveArea()}',
      '소속 입력: ${_deptCtrl.text.trim().isNotEmpty}',
      '성명 입력: ${_nameCtrl.text.trim().isNotEmpty}',
      '직책 입력: ${_positionCtrl.text.trim().isNotEmpty}',
      '사건 일시: ${_eventDateTime != null}',
      '내용 길이: ${_contentCtrl.text.trim().length}',
      '전자서명: ${_signaturePngBytes != null}',
      '수신처 유효: $_recipientValid',
      '수신처 개수: ${_recipientCount(_recipient)}',
      '초기화 중: $_initializing',
      '전송 중: $_sending',
      '제출 단계: $_submitStage',
      '마지막 실패: ${_lastFailure.isEmpty ? '없음' : _lastFailure}',
      '애니메이션 감소: $_reduceMotion',
    ].join('\n');
    if (failure) {
      await StatusDialog.showFailure(
        context,
        title: '경위서 상태',
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
      title: '경위서 상태',
      description: description,
      copyText: _debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  Future<void> _scrollTo(GlobalKey key) async {
    final target = key.currentContext;
    if (target == null) return;
    await Scrollable.ensureVisible(
      target,
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      alignment: .16,
    );
  }

  void _closeDock() {
    if (_sending) return;
    _recordDebug(
      'dock_close contentLen=${_contentCtrl.text.trim().length} signature=${_signaturePngBytes != null}',
    );
    Navigator.of(context).pop();
  }

  String _safeFileName(String raw) {
    final value = raw.trim().isEmpty ? '경위서' : raw.trim();
    return value.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
  }

  Future<Uint8List> _buildPdfBytes() async {
    try {
      pw.Font? regular;
      pw.Font? bold;

      try {
        final regData = await rootBundle
            .load('assets/fonts/NotoSansKR/NotoSansKR-Regular.ttf');
        regular = pw.Font.ttf(regData);
      } catch (_) {}

      try {
        final boldData = await rootBundle
            .load('assets/fonts/NotoSansKR/NotoSansKR-Bold.ttf');
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

      final dt = _eventDateTime;
      final eventText = (dt == null) ? '-' : _fmtCompact(dt);

      final fields = <MapEntry<String, String>>[
        MapEntry(
            '소속', _deptCtrl.text.trim().isEmpty ? '-' : _deptCtrl.text.trim()),
        MapEntry(
            '성명', _nameCtrl.text.trim().isEmpty ? '-' : _nameCtrl.text.trim()),
        MapEntry(
            '직책',
            _positionCtrl.text.trim().isEmpty
                ? '-'
                : _positionCtrl.text.trim()),
        MapEntry('일시', eventText),
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
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 4),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400, width: 0.5),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Text(
              body.trim().isEmpty ? '-' : body,
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
            pw.Text('전자서명',
                style:
                pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Expanded(
                    child: pw.Text('서명자: $name',
                        style: const pw.TextStyle(fontSize: 11))),
                pw.SizedBox(width: 8),
                pw.Text('서명 일시: $timeText',
                    style: const pw.TextStyle(fontSize: 11)),
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
                      fontSize: 10, color: PdfColors.grey),
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
                '경위서',
                style:
                pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
              ),
            ),
            pw.SizedBox(height: 12),
            buildFieldTable(),
            buildSection('[내용(육하원칙 기반)]', _contentCtrl.text),
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

      return doc.save();
    } catch (e) {
      await _logApiError(
        tag: 'UserStatementSideDock._buildPdfBytes',
        message: 'PDF 생성 실패',
        error: e,
        extra: <String, dynamic>{
          'deptLen': _deptCtrl.text.trim().length,
          'nameLen': _nameCtrl.text.trim().length,
          'positionLen': _positionCtrl.text.trim().length,
          'contentLen': _contentCtrl.text.trim().length,
          'hasEventTime': _eventDateTime != null,
          'hasSignature': _signaturePngBytes != null,
        },
        tags: const <String>[_tStatementPdf, _tStatement],
      );
      rethrow;
    }
  }

  String _wrapBase64Lines(String b64, {int lineLength = _mimeB64LineLength}) {
    if (b64.isEmpty) return '';
    final sb = StringBuffer();
    for (int i = 0; i < b64.length; i += lineLength) {
      final end = (i + lineLength < b64.length) ? i + lineLength : b64.length;
      sb.write(b64.substring(i, end));
      sb.write('\r\n');
    }
    return sb.toString();
  }

  String _encodeSubjectRfc2047(String subject) {
    final subjectB64 = base64.encode(utf8.encode(subject));
    return '=?utf-8?B?$subjectB64?=';
  }

  Future<void> _sendEmailViaGmail({
    required Uint8List pdfBytes,
    required String filename,
    required String to,
    required String subject,
    required String body,
  }) async {
    final client = await GmailSenderAuth.client();
    try {
      final api = gmail.GmailApi(client);

      final boundary =
          'dart-mail-boundary-${DateTime.now().millisecondsSinceEpoch}';
      const crlf = '\r\n';

      final pdfB64Wrapped = _wrapBase64Lines(base64.encode(pdfBytes));

      final mime = StringBuffer()
        ..write('To: $to$crlf')
        ..write('Subject: ${_encodeSubjectRfc2047(subject)}$crlf')
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
        ..write(pdfB64Wrapped)
        ..write('--$boundary--$crlf');

      final raw =
      base64UrlEncode(utf8.encode(mime.toString())).replaceAll('=', '');
      final msg = gmail.Message()..raw = raw;
      await api.users.messages.send(msg, 'me');
    } catch (e) {
      await _logApiError(
        tag: 'UserStatementFormPage._sendEmailViaGmail',
        message: 'Gmail API 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'toLen': to.length,
          'subjectLen': subject.length,
          'bodyLen': body.length,
          'pdfBytes': pdfBytes.length,
          'filename': filename,
        },
        tags: const <String>[_tStatementEmail, _tStatement, _tGmailSend],
      );
      rethrow;
    } finally {
      try {
        client.close();
      } catch (_) {}
    }
  }


  InputDecoration _inputDecoration(String label) {
    final tokens = CommonUiTheme.of(context);
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: tokens.surfaceOverlay,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        borderSide: BorderSide(color: tokens.borderSubtle),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        borderSide: BorderSide(color: tokens.borderSubtle),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        borderSide: BorderSide(color: tokens.focusRing, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        borderSide: BorderSide(color: tokens.danger, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        borderSide: BorderSide(color: tokens.danger, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 13,
      ),
    );
  }

  Widget _buildContentCanvas() {
    final tokens = CommonUiTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(CommonUiShapes.card),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.canvas,
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Stack(
          children: [
            Form(
              key: _formKey,
              child: SingleChildScrollView(
                controller: _scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _StatusStrip(
                      primary: _fmtCompact(DateTime.now()),
                      secondary: _recipientValid ? '전송 준비' : '수신처 확인',
                    ),
                    const SizedBox(height: 10),
                    OpsDockListSurface(
                      child: Column(
                        children: [
                          _InputRow(
                            child: TextFormField(
                              controller: _deptCtrl,
                              focusNode: _deptNode,
                              enabled: !_sending,
                              decoration: _inputDecoration('소속'),
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _nameNode.requestFocus(),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? '소속을 입력하세요.'
                                      : null,
                            ),
                          ),
                          _DockDivider(),
                          _InputRow(
                            child: TextFormField(
                              controller: _nameCtrl,
                              focusNode: _nameNode,
                              enabled: !_sending,
                              decoration: _inputDecoration('성명'),
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  _positionNode.requestFocus(),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? '성명을 입력하세요.'
                                      : null,
                            ),
                          ),
                          _DockDivider(),
                          _InputRow(
                            child: TextFormField(
                              controller: _positionCtrl,
                              focusNode: _positionNode,
                              enabled: !_sending,
                              decoration: _inputDecoration('직책'),
                              textInputAction: TextInputAction.done,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? '직책을 입력하세요.'
                                      : null,
                            ),
                          ),
                          _DockDivider(),
                          Container(
                            key: _eventKey,
                            child: _ActionRow(
                              label: '사건 일시',
                              value: _fmtDT(context, _eventDateTime),
                              icon: Icons.event_rounded,
                              enabled: !_sending,
                              danger: _eventInvalid,
                              onTap: _pickDateTime,
                            ),
                          ),
                          _DockDivider(),
                          _StaticValueRow(
                            label: '수신처',
                            value: _recipient.isEmpty ? '미설정' : _recipient,
                            danger: !_recipientValid,
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(
                      key: _contentKey,
                      child: _DetailSurface(
                        title: '사실 관계',
                        danger: _contentInvalid,
                        child: TextFormField(
                          controller: _contentCtrl,
                          focusNode: _contentNode,
                          enabled: !_sending,
                          decoration: _inputDecoration('내용'),
                          keyboardType: TextInputType.multiline,
                          minLines: 7,
                          maxLines: 14,
                          onChanged: (_) {
                            if (_contentInvalid &&
                                _contentCtrl.text.trim().isNotEmpty) {
                              setState(() => _contentInvalid = false);
                            }
                          },
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                                  ? '내용을 입력하세요.'
                                  : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _DetailSurface(
                      title: '메일 전송',
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _mailSubjectCtrl,
                            enabled: !_sending,
                            decoration: _inputDecoration('메일 제목'),
                            textInputAction: TextInputAction.next,
                            validator: (value) =>
                                value == null || value.trim().isEmpty
                                    ? '메일 제목을 입력하세요.'
                                    : null,
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: _mailBodyCtrl,
                            enabled: !_sending,
                            decoration: _inputDecoration('메일 본문'),
                            keyboardType: TextInputType.multiline,
                            minLines: 4,
                            maxLines: 8,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    _SignatureSurface(
                      signed: _signaturePngBytes != null,
                      signer: _signerName,
                      signTime: _signDateTime == null
                          ? '미서명'
                          : _fmtCompact(_signDateTime!),
                      enabled: !_sending,
                      onSign: _openSignatureDialog,
                      onRemove: _removeSignature,
                    ),
                  ],
                ),
              ),
            ),
            OpsDockLoadingOverlay(loading: _initializing || _sending),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return OpsDockContextFooterTransition(
      child: OpsDockContextFooter(
        key: ValueKey<String>(
          _sending ? 'sending' : 'ready',
        ),
        children: [
          Expanded(
            child: CommonButton(
              label: '초기화',
              icon: Icons.restart_alt_rounded,
              onPressed: _sending || _initializing ? null : _reset,
              variant: CommonButtonVariant.tertiary,
              expand: true,
              haptic: CommonHaptic.selection,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: CommonButton(
              label: '미리보기',
              icon: Icons.visibility_outlined,
              onPressed: _sending || _initializing ? null : _showPreview,
              variant: CommonButtonVariant.secondary,
              expand: true,
              haptic: CommonHaptic.selection,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: CommonButton(
              label: _sending ? '전송 중' : '제출',
              icon: _sending ? null : Icons.send_rounded,
              loading: _sending,
              onPressed: _sending || _initializing ? null : _submit,
              expand: true,
              haptic: CommonHaptic.medium,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final area = _resolveArea();
    return CommonSideDockFrame(
      title: '경위서',
      subtitle: '$area · 경위서 작성',
      icon: Icons.description_outlined,
      closeEnabled: !_sending,
      onClose: _closeDock,
      onLongPress: _developerMode ? _showDeveloperStatus : null,
      headerAction: AnimatedSwitcher(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .88, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: _developerMode
            ? CommonIconButton(
                key: const ValueKey<String>('developer'),
                icon: Icons.bug_report_rounded,
                tooltip: '상태',
                onPressed: _showDeveloperStatus,
                haptic: CommonHaptic.selection,
                size: 38,
              )
            : const SizedBox.shrink(
                key: ValueKey<String>('developer-hidden'),
              ),
      ),
      footer: _buildFooter(),
      child: _buildContentCanvas(),
    );
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.primary, required this.secondary});
  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              primary,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Text(
            secondary,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _InputRow extends StatelessWidget {
  const _InputRow({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: child,
    );
  }
}

class _DockDivider extends StatelessWidget {
  const _DockDivider();

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      color: CommonUiTheme.of(context).borderSubtle,
    );
  }
}

class _StaticValueRow extends StatelessWidget {
  const _StaticValueRow({
    required this.label,
    required this.value,
    this.danger = false,
    this.maxLines = 1,
  });

  final String label;
  final String value;
  final bool danger;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : CommonUiMotion.selection,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
      color: danger ? tokens.dangerContainer.withOpacity(.38) : Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 74,
            child: Text(
              label,
              style: textTheme.bodySmall?.copyWith(
                color: danger ? tokens.danger : tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                  ? Duration.zero
                  : CommonUiMotion.selection,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .05),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: Text(
                value,
                key: ValueKey<String>(value),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: textTheme.bodyMedium?.copyWith(
                  color: danger ? tokens.danger : tokens.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionRow extends StatefulWidget {
  const _ActionRow({
    required this.label,
    required this.value,
    required this.icon,
    required this.enabled,
    required this.danger,
    required this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool enabled;
  final bool danger;
  final VoidCallback onTap;

  @override
  State<_ActionRow> createState() => _ActionRowState();
}

class _ActionRowState extends State<_ActionRow> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedScale(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
      scale: _pressed ? .985 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.enabled ? widget.onTap : null,
          onHighlightChanged: widget.enabled
              ? (value) => setState(() => _pressed = value)
              : null,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
            color: widget.danger
                ? tokens.dangerContainer.withOpacity(.38)
                : _pressed
                    ? tokens.surfaceSelected.withOpacity(.55)
                    : Colors.transparent,
            child: Row(
              children: [
                Icon(
                  widget.icon,
                  size: 19,
                  color: widget.danger ? tokens.danger : tokens.iconSecondary,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    widget.label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: widget.danger
                              ? tokens.danger
                              : tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
                Flexible(
                  child: Text(
                    widget.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: widget.danger
                              ? tokens.danger
                              : tokens.textSecondary,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  Icons.chevron_right_rounded,
                  size: 19,
                  color: tokens.iconSecondary,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DetailSurface extends StatelessWidget {
  const _DetailSurface({
    required this.title,
    required this.child,
    this.danger = false,
  });

  final String title;
  final Widget child;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: danger ? tokens.danger : tokens.borderSubtle,
          width: danger ? 1.5 : 1,
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: danger ? tokens.danger : tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }
}

class _SignatureSurface extends StatelessWidget {
  const _SignatureSurface({
    required this.signed,
    required this.signer,
    required this.signTime,
    required this.enabled,
    required this.onSign,
    required this.onRemove,
  });

  final bool signed;
  final String signer;
  final String signTime;
  final bool enabled;
  final VoidCallback onSign;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      alignment: Alignment.topCenter,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '전자서명',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  child: Text(
                    signed ? '완료' : '미서명',
                    key: ValueKey<bool>(signed),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: signed ? tokens.success : tokens.textSecondary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
              ],
            ),
            if (signed) ...[
              const SizedBox(height: 8),
              Text(
                '${signer.isEmpty ? '이름 미입력' : signer} · $signTime',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                    ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: CommonButton(
                    label: signed ? '다시 서명' : '서명',
                    icon: Icons.draw_rounded,
                    onPressed: enabled ? onSign : null,
                    variant: signed
                        ? CommonButtonVariant.secondary
                        : CommonButtonVariant.primary,
                    expand: true,
                    haptic: CommonHaptic.selection,
                  ),
                ),
                if (signed) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: CommonButton(
                      label: '삭제',
                      icon: Icons.delete_outline_rounded,
                      onPressed: enabled ? onRemove : null,
                      variant: CommonButtonVariant.tertiary,
                      expand: true,
                      haptic: CommonHaptic.selection,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewHeader extends StatelessWidget {
  const _PreviewHeader({required this.title, required this.onClose});
  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_outlined, color: tokens.iconSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
          ),
          CommonIconButton(
            icon: Icons.close_rounded,
            tooltip: '닫기',
            onPressed: onClose,
            haptic: CommonHaptic.selection,
            size: 38,
          ),
        ],
      ),
    );
  }
}
