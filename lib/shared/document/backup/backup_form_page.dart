import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
import 'backup_signature_dialog.dart';

enum ContractType {
  contract,
  freelancer,
}

Future<void> showBackupApplicationSideDock({
  required BuildContext context,
}) async {
  final reduceMotion =
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  debugPrint(
    '[LeaveApplicationDock] route_push reduceMotion=$reduceMotion motion=operations_210_190',
  );
  await showOperationsRightSideDock<void>(
    context: context,
    useRootNavigator: true,
    barrierLabel: '연차 지원 신청서',
    maxWidth: 360,
    widthFactor: .92,
    barrierDismissible: false,
    builder: (_) => const BackupApplicationSideDock(),
  );
  debugPrint('[LeaveApplicationDock] route_closed');
}

class BackupApplicationSideDock extends StatefulWidget {
  const BackupApplicationSideDock({super.key});

  @override
  State<BackupApplicationSideDock> createState() =>
      _BackupApplicationSideDockState();
}

class _BackupApplicationSideDockState
    extends State<BackupApplicationSideDock> {
  static const String _tBackup = 'backup';
  static const String _tBackupForm = 'backup/form';
  static const String _tBackupPdf = 'backup/pdf';
  static const String _tBackupEmail = 'backup/email';
  static const String _tBackupPrefs = 'backup/prefs';
  static const String _tGmail = 'gmail/send';
  static const int _mimeB64LineLength = 76;
  static const int _maxDebugLines = 180;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  final GlobalKey _contractKey = GlobalKey();
  final GlobalKey _supportKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final List<String> _debugLines = <String>[];

  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _rrnCtrl = TextEditingController();
  final TextEditingController _positionCtrl = TextEditingController();
  final TextEditingController _deptCtrl = TextEditingController();
  final TextEditingController _reasonCtrl = TextEditingController();
  final TextEditingController _targetCtrl = TextEditingController();
  final TextEditingController _timeCtrl = TextEditingController();
  final TextEditingController _processCtrl = TextEditingController();
  final TextEditingController _mailSubjectCtrl = TextEditingController();
  final TextEditingController _mailBodyCtrl = TextEditingController();

  final FocusNode _nameNode = FocusNode();
  final FocusNode _rrnNode = FocusNode();
  final FocusNode _positionNode = FocusNode();
  final FocusNode _deptNode = FocusNode();
  final FocusNode _reasonNode = FocusNode();

  Uint8List? _signaturePngBytes;
  DateTime? _signDateTime;
  ContractType? _contractType;
  String? _selectedArea;
  String _recipient = '';
  bool _recipientValid = false;
  bool _initializing = true;
  bool _sending = false;
  bool _developerMode = false;
  bool _contractInvalid = false;
  bool _supportInvalid = false;
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
    for (final controller in <TextEditingController>[
      _reasonCtrl,
      _targetCtrl,
      _timeCtrl,
      _processCtrl,
    ]) {
      controller.addListener(_onSupportChanged);
    }
    _updateMailBody(force: true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_initialize());
    });
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_onDeveloperModeChanged);
    _nameCtrl.removeListener(_onNameChanged);
    for (final controller in <TextEditingController>[
      _reasonCtrl,
      _targetCtrl,
      _timeCtrl,
      _processCtrl,
    ]) {
      controller.removeListener(_onSupportChanged);
    }
    _nameCtrl.dispose();
    _rrnCtrl.dispose();
    _positionCtrl.dispose();
    _deptCtrl.dispose();
    _reasonCtrl.dispose();
    _targetCtrl.dispose();
    _timeCtrl.dispose();
    _processCtrl.dispose();
    _mailSubjectCtrl.dispose();
    _mailBodyCtrl.dispose();
    _nameNode.dispose();
    _rrnNode.dispose();
    _positionNode.dispose();
    _deptNode.dispose();
    _reasonNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _onSupportChanged() {
    if (!mounted) return;
    final complete = _supportFieldsComplete;
    setState(() {
      if (complete) _supportInvalid = false;
    });
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
    final line = '[$stamp] [LeaveApplicationDock] $normalized';
    _debugLines.add(line);
    if (_debugLines.length > _maxDebugLines) {
      _debugLines.removeRange(0, _debugLines.length - _maxDebugLines);
    }
    debugPrint(line);
  }

  String get _debugPrintCode {
    if (_debugLines.isEmpty) {
      return 'debugPrint(${jsonEncode('[LeaveApplicationDock] 기록된 로그가 없습니다.')});';
    }
    return _debugLines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  Future<void> _initialize() async {
    _recordDebug('initialize_start');
    try {
      final developerMode = await DevAuth.isDevModeEnabled();
      await _loadSelectedArea();
      await _loadRecipient();
      _updateMailSubject();
      _updateMailBody(force: true);
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
        tag: 'BackupApplicationSideDock._initialize',
        message: '연차 지원 신청서 초기화 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tBackupForm, _tBackup],
      );
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _lastFailure = 'initialize';
      });
      await StatusDialog.showFailure(
        context,
        title: '연차 지원 신청서 초기화 실패',
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
        'area_fallback_loaded configured=${(_selectedArea ?? '').isNotEmpty}',
      );
    } catch (error, stackTrace) {
      _selectedArea = null;
      _recordDebug('area_fallback_failure error=$error');
      await _logApiError(
        tag: 'BackupApplicationSideDock._loadSelectedArea',
        message: '연차 지원 신청서 지역 정보 로드 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tBackupPrefs, _tBackup],
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
        tag: 'BackupApplicationSideDock._loadRecipient',
        message: '연차 지원 신청서 수신처 로드 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tBackupEmail, _tBackup],
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
    final fallback = (_selectedArea ?? '').trim();
    if (fallback.isNotEmpty) return fallback;
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

  String _contractTypeText(ContractType? value) {
    if (value == null) return '미선택';
    switch (value) {
      case ContractType.contract:
        return '계약직';
      case ContractType.freelancer:
        return '프리랜서';
    }
  }

  String _buildBodySentence() {
    final reason = _reasonCtrl.text.trim();
    final target = _targetCtrl.text.trim();
    final time = _timeCtrl.text.trim();
    final process = _processCtrl.text.trim();
    return '$reason으로 인해 $target의 $time 시간 대의 업무에 공백이 발생했습니다. '
        '본 문서를 통해 해당 공백에 대한 인적 지원을 받고자 하오며 향후 이에 대해서는 $process로 처리됨을 인지합니다.';
  }

  bool get _supportFieldsComplete =>
      _reasonCtrl.text.trim().isNotEmpty &&
      _targetCtrl.text.trim().isNotEmpty &&
      _timeCtrl.text.trim().isNotEmpty &&
      _processCtrl.text.trim().isNotEmpty;

  void _updateMailSubject() {
    final now = DateTime.now();
    final suffixType =
        _contractType == null ? '' : ' - ${_contractTypeText(_contractType)}';
    final area = _resolveArea();
    _mailSubjectCtrl.text =
        '$area 연차(결근) 지원 신청서 – ${now.month}월 ${now.day}일자$suffixType';
  }

  void _updateMailBody({bool force = false}) {
    if (!force && _mailBodyCtrl.text.trim().isNotEmpty) return;
    final now = DateTime.now();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    _mailBodyCtrl.text =
        '본 신청서는 ${now.year}년 ${now.month}월 ${now.day}일 ${hh}시 ${mm}분 기준으로 작성된 연차(결근) 지원 신청서입니다.';
  }

  void _setContractType(ContractType type) {
    if (_sending) return;
    if (_contractType == type && !_contractInvalid) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _contractType = type;
      _contractInvalid = false;
      _updateMailSubject();
    });
    _recordDebug('contract_type_changed value=${_contractTypeText(type)}');
  }

  void _reset() {
    if (_sending) return;
    FocusScope.of(context).unfocus();
    _formKey.currentState?.reset();
    _nameCtrl.clear();
    _rrnCtrl.clear();
    _positionCtrl.clear();
    _deptCtrl.clear();
    _reasonCtrl.clear();
    _targetCtrl.clear();
    _timeCtrl.clear();
    _processCtrl.clear();
    _mailSubjectCtrl.clear();
    _mailBodyCtrl.clear();
    setState(() {
      _signaturePngBytes = null;
      _signDateTime = null;
      _contractType = null;
      _contractInvalid = false;
      _supportInvalid = false;
      _submitStage = 'idle';
      _lastFailure = '';
    });
    _updateMailSubject();
    _updateMailBody(force: true);
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
      final result = await showBackupSignatureOverlay(
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
        tag: 'BackupApplicationSideDock._openSignatureDialog',
        message: '연차 지원 신청서 전자서명 처리 실패',
        error: error,
        extra: <String, dynamic>{'stack': stackTrace.toString()},
        tags: const <String>[_tBackupForm, _tBackup],
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
      '연차(결근) 지원 신청서',
      '지역: ${_resolveArea()}',
      '계약 형태: ${_contractTypeText(_contractType)}',
      '성명: ${_nameCtrl.text.trim()}',
      '주민등록번호: ${_rrnCtrl.text.trim()}',
      '직위: ${_positionCtrl.text.trim()}',
      '부서명: ${_deptCtrl.text.trim()}',
      '업무 공백 및 인력 지원 요청: ${_buildBodySentence()}',
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
      barrierLabel: '연차 지원 신청서 미리보기',
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
                  title: '연차 지원 신청서 미리보기',
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
                              _StaticValueRow(
                                label: '계약 형태',
                                value: _contractTypeText(_contractType),
                              ),
                              _DockDivider(),
                              _StaticValueRow(
                                label: '성명',
                                value: _nameCtrl.text.trim().isEmpty
                                    ? '미입력'
                                    : _nameCtrl.text.trim(),
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
                          title: '업무 공백 및 인력 지원 요청',
                          child: SelectableText(
                            _buildBodySentence().trim().isEmpty
                                ? '미입력'
                                : _buildBodySentence(),
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
    final contractValid = _contractType != null;
    final supportValid = _supportFieldsComplete;
    final signatureValid = _signaturePngBytes != null;
    if (!formValid ||
        !contractValid ||
        !supportValid ||
        !signatureValid ||
        !_recipientValid) {
      setState(() {
        _contractInvalid = !contractValid;
        _supportInvalid = !supportValid;
      });
      _recordDebug(
        'validation_failure form=$formValid contract=$contractValid support=$supportValid signature=$signatureValid recipient=$_recipientValid',
      );
      if (!contractValid) {
        await _scrollTo(_contractKey);
      } else if (!supportValid) {
        await _scrollTo(_supportKey);
        _reasonNode.requestFocus();
      }
      if (!_recipientValid && mounted) {
        await StatusDialog.showFailure(
          context,
          title: '연차 지원 신청서 제출 실패',
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
      'submit_start contract=${_contractTypeText(_contractType)} nameConfigured=${_nameCtrl.text.trim().isNotEmpty} rrnConfigured=${_rrnCtrl.text.trim().isNotEmpty} rrnLen=${_rrnCtrl.text.trim().length} support=$supportValid signature=${_signaturePngBytes != null} recipientCount=${_recipientCount(_recipient)}',
    );

    try {
      _updateMailBody(force: true);
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
        '연차결근지원신청서_${nameForFile}_${_dateTag(now)}',
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
        title: StatusDialog.leaveApplicationSubmitSuccess,
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
        title: '연차 지원 신청서 제출 실패',
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
      tag: 'BackupApplicationSideDock.$reason',
      message: title,
      error: error,
      extra: <String, dynamic>{
        'stack': stackTrace.toString(),
        'contractType': _contractTypeText(_contractType),
        'nameConfigured': _nameCtrl.text.trim().isNotEmpty,
        'rrnConfigured': _rrnCtrl.text.trim().isNotEmpty,
        'rrnLen': _rrnCtrl.text.trim().length,
        'positionConfigured': _positionCtrl.text.trim().isNotEmpty,
        'departmentConfigured': _deptCtrl.text.trim().isNotEmpty,
        'supportComplete': _supportFieldsComplete,
        'signatureConfigured': _signaturePngBytes != null,
        'recipientValid': _recipientValid,
      },
      tags: const <String>[_tBackupForm, _tBackupEmail, _tBackup],
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
      '계약 형태: ${_contractTypeText(_contractType)}',
      '성명 입력: ${_nameCtrl.text.trim().isNotEmpty}',
      '주민등록번호 입력: ${_rrnCtrl.text.trim().isNotEmpty}',
      '주민등록번호 길이: ${_rrnCtrl.text.trim().length}',
      '직위 입력: ${_positionCtrl.text.trim().isNotEmpty}',
      '부서 입력: ${_deptCtrl.text.trim().isNotEmpty}',
      '사유 입력: ${_reasonCtrl.text.trim().isNotEmpty}',
      '대상 입력: ${_targetCtrl.text.trim().isNotEmpty}',
      '시간대 입력: ${_timeCtrl.text.trim().isNotEmpty}',
      '처리 방식 입력: ${_processCtrl.text.trim().isNotEmpty}',
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
        title: '연차 지원 신청서 상태',
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
      title: '연차 지원 신청서 상태',
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
      'dock_close contract=${_contractTypeText(_contractType)} support=${_supportFieldsComplete} signature=${_signaturePngBytes != null}',
    );
    Navigator.of(context).pop();
  }

  String _safeFileName(String raw) {
    final value = raw.trim().isEmpty ? '연차결근지원신청서' : raw.trim();
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

      final contractText = _contractTypeText(_contractType);
      final name = _nameCtrl.text.trim().isEmpty ? '-' : _nameCtrl.text.trim();
      final rrn = _rrnCtrl.text.trim().isEmpty ? '-' : _rrnCtrl.text.trim();
      final position =
          _positionCtrl.text.trim().isEmpty ? '-' : _positionCtrl.text.trim();
      final dept = _deptCtrl.text.trim().isEmpty ? '-' : _deptCtrl.text.trim();
      final bodySentence = _buildBodySentence();

      final fields = <MapEntry<String, String>>[
        MapEntry('계약 형태', contractText),
        MapEntry('성명', name),
        MapEntry('주민등록번호', rrn),
        MapEntry('직위', position),
        MapEntry('부서명', dept),
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
                  child: pw.Text('서명자: $name',
                      style: const pw.TextStyle(fontSize: 11)),
                ),
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
                '연차(결근) 지원 신청서',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ),
            pw.SizedBox(height: 12),
            buildFieldTable(),
            buildSection('[업무 공백 및 인력 지원 요청]', bodySentence),
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

      final bytes = await doc.save();
      return bytes;
    } catch (e) {
      await _logApiError(
        tag: 'BackupApplicationSideDock._buildPdfBytes',
        message: 'PDF 생성 실패',
        error: e,
        extra: <String, dynamic>{
          'contractType': _contractTypeText(_contractType),
          'hasSignature': _signaturePngBytes != null,
          'nameLen': _nameCtrl.text.trim().length,
          'rrnLen': _rrnCtrl.text.trim().length,
        },
        tags: const <String>[_tBackupPdf, _tBackup, _tBackupForm],
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
        tag: 'BackupFormPage._sendEmailViaGmail',
        message: 'Gmail API 전송 실패',
        error: e,
        extra: <String, dynamic>{
          'toLen': to.length,
          'subjectLen': subject.length,
          'bodyLen': body.length,
          'pdfBytes': pdfBytes.length,
          'filename': filename,
        },
        tags: const <String>[_tBackupEmail, _tBackup, _tGmail],
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

  Widget _buildContractSegment() {
    Widget button(ContractType type, String label) {
      final selected = _contractType == type;
      return Expanded(
        child: CommonButton(
          label: label,
          selected: selected,
          variant: selected
              ? CommonButtonVariant.primary
              : CommonButtonVariant.secondary,
          onPressed: _sending ? null : () => _setContractType(type),
          expand: true,
          haptic: CommonHaptic.selection,
        ),
      );
    }

    return Container(
      key: _contractKey,
      child: _DetailSurface(
        title: '계약 형태',
        danger: _contractInvalid,
        child: Row(
          children: [
            button(ContractType.contract, '계약직'),
            const SizedBox(width: 8),
            button(ContractType.freelancer, '프리랜서'),
          ],
        ),
      ),
    );
  }

  Widget _buildSupportSurface() {
    final sentence = _buildBodySentence();
    return Container(
      key: _supportKey,
      child: _DetailSurface(
        title: '업무 공백 및 인력 지원',
        danger: _supportInvalid,
        child: Column(
          children: [
            TextFormField(
              controller: _reasonCtrl,
              focusNode: _reasonNode,
              enabled: !_sending,
              decoration: _inputDecoration('공백 사유'),
              onChanged: (_) => setState(() {}),
              validator: (value) =>
                  value == null || value.trim().isEmpty
                      ? '공백 사유를 입력하세요.'
                      : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _targetCtrl,
              enabled: !_sending,
              decoration: _inputDecoration('지원 대상'),
              onChanged: (_) => setState(() {}),
              validator: (value) =>
                  value == null || value.trim().isEmpty
                      ? '지원 대상을 입력하세요.'
                      : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _timeCtrl,
              enabled: !_sending,
              decoration: _inputDecoration('시간대'),
              onChanged: (_) => setState(() {}),
              validator: (value) =>
                  value == null || value.trim().isEmpty
                      ? '시간대를 입력하세요.'
                      : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _processCtrl,
              enabled: !_sending,
              decoration: _inputDecoration('처리 방식'),
              onChanged: (_) => setState(() {}),
              validator: (value) =>
                  value == null || value.trim().isEmpty
                      ? '처리 방식을 입력하세요.'
                      : null,
            ),
            const SizedBox(height: 10),
            AnimatedSwitcher(
              duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
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
              child: Container(
                key: ValueKey<String>(sentence),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: CommonUiTheme.of(context).surfaceOverlay,
                  borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  border: Border.all(
                    color: CommonUiTheme.of(context).borderSubtle,
                  ),
                ),
                child: Text(
                  sentence,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: CommonUiTheme.of(context).textSecondary,
                        height: 1.45,
                      ),
                ),
              ),
            ),
          ],
        ),
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
                    _buildContractSegment(),
                    const SizedBox(height: 10),
                    OpsDockListSurface(
                      child: Column(
                        children: [
                          _InputRow(
                            child: TextFormField(
                              controller: _nameCtrl,
                              focusNode: _nameNode,
                              enabled: !_sending,
                              decoration: _inputDecoration('성명'),
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _rrnNode.requestFocus(),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? '성명을 입력하세요.'
                                      : null,
                            ),
                          ),
                          _DockDivider(),
                          _InputRow(
                            child: TextFormField(
                              controller: _rrnCtrl,
                              focusNode: _rrnNode,
                              enabled: !_sending,
                              decoration: _inputDecoration('주민등록번호'),
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) =>
                                  _positionNode.requestFocus(),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? '주민등록번호를 입력하세요.'
                                      : null,
                            ),
                          ),
                          _DockDivider(),
                          _InputRow(
                            child: TextFormField(
                              controller: _positionCtrl,
                              focusNode: _positionNode,
                              enabled: !_sending,
                              decoration: _inputDecoration('직위'),
                              textInputAction: TextInputAction.next,
                              onFieldSubmitted: (_) => _deptNode.requestFocus(),
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? '직위를 입력하세요.'
                                      : null,
                            ),
                          ),
                          _DockDivider(),
                          _InputRow(
                            child: TextFormField(
                              controller: _deptCtrl,
                              focusNode: _deptNode,
                              enabled: !_sending,
                              decoration: _inputDecoration('부서명'),
                              textInputAction: TextInputAction.done,
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                      ? '부서명을 입력하세요.'
                                      : null,
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
                    _buildSupportSurface(),
                    const SizedBox(height: 10),
                    _DetailSurface(
                      title: '메일 전송',
                      child: Column(
                        children: [
                          TextFormField(
                            controller: _mailSubjectCtrl,
                            enabled: !_sending,
                            decoration: _inputDecoration('메일 제목'),
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
        key: ValueKey<String>(_sending ? 'sending' : 'ready'),
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
              onPressed:
                  _sending || _initializing || _signaturePngBytes == null
                      ? null
                      : _submit,
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
      title: '연차 지원 신청서',
      subtitle: '$area · 지원 신청',
      icon: Icons.event_available_outlined,
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
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
              child: Text(
                value,
                key: ValueKey<String>(value),
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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
