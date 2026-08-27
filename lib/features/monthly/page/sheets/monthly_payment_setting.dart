import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_origin_morph_dialog.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/plate/domain/repositories/plate_repository.dart';
import '../../../../shared/secondary/application/secondary_monthly_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../account/applications/user_state.dart';
import '../../../dev/application/area_state.dart';
import '../../../selector/application/dev_auth.dart';
import '../../application/monthly_date_range_calculator.dart';
import '../../domain/monthly_parking_options.dart';
import 'models/monthly_payment_settings_draft.dart';
import 'monthly_payment_setting_section_editor_dialog.dart';

class MonthlyPaymentSettingWorkspace extends StatefulWidget {
  const MonthlyPaymentSettingWorkspace({
    super.key,
    required this.docId,
    required this.initialData,
  });

  final String docId;
  final Map<String, dynamic> initialData;

  @override
  State<MonthlyPaymentSettingWorkspace> createState() =>
      _MonthlyPaymentSettingWorkspaceState();
}

class _MonthlyPaymentSettingWorkspaceState
    extends State<MonthlyPaymentSettingWorkspace> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _scrollViewportKey = GlobalKey();
  final Map<MonthlyWorkspaceSection, GlobalKey> _sectionKeys =
      <MonthlyWorkspaceSection, GlobalKey>{
    MonthlyWorkspaceSection.paymentAmount: GlobalKey(),
    MonthlyWorkspaceSection.paymentExtension: GlobalKey(),
    MonthlyWorkspaceSection.paymentNote: GlobalKey(),
  };
  final List<String> _debugLines = <String>[];
  final NumberFormat _won = NumberFormat.decimalPattern();

  late MonthlyPaymentSettingsDraft _draft;
  late final String _plateNumber;
  late final String _countType;
  late final String? _regularType;
  late final String _periodUnit;
  late final int _duration;
  late final String _startDate;
  late final String _endDate;
  late final int _paymentHistoryCount;
  bool _saving = false;
  bool _validationSubmitted = false;
  bool _reduceMotion = false;
  bool _devModeEnabled = false;
  String? _saveError;
  int _handledNavigationRequestId = -1;
  MonthlyWorkspaceSection? _editingSection;
  MonthlyWorkspaceSection? _pendingVisibleSection;
  bool _visibleSectionScheduled = false;
  SecondaryMonthlyWorkspaceState? _workspace;

  @override
  void initState() {
    super.initState();
    final data = widget.initialData;
    _plateNumber = widget.docId.split('_').first;
    _countType = (data['countType'] ?? '').toString();
    _regularType = MonthlyParkingOptions.normalizeRegularType(
      data['regularType']?.toString(),
    );
    _periodUnit = MonthlyParkingOptions.resolvePeriodUnit(
      regularType: _regularType,
      periodUnit: data['periodUnit']?.toString(),
    );
    _duration = _asInt(
      data['regularDurationValue'] ?? data['regularDurationHours'],
    );
    _startDate = (data['startDate'] ?? '').toString();
    _endDate = (data['endDate'] ?? '').toString();
    final rawHistory = data['payment_history'];
    _paymentHistoryCount = rawHistory is List ? rawHistory.length : 0;
    final amount = _asInt(data['regularAmount']);
    _draft = MonthlyPaymentSettingsDraft(
      paymentAmount: amount > 0 ? amount : null,
      extended: false,
      note: '',
    );
    _devModeEnabled = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_handleDevModeChanged);
    _log('mounted doc=${widget.docId} plate=$_plateNumber history=$_paymentHistoryCount');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSectionStates(source: 'initial_payment_state');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _workspace ??= context.read<SecondaryMonthlyWorkspaceState>();
  }

  @override
  void dispose() {
    DevAuth.devModeEnabled.removeListener(_handleDevModeChanged);
    _scrollController.dispose();
    super.dispose();
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  void _handleDevModeChanged() {
    if (!mounted) return;
    final enabled = DevAuth.devModeEnabled.value;
    if (_devModeEnabled == enabled) return;
    setState(() => _devModeEnabled = enabled);
    _log('developer_mode_changed enabled=$enabled');
  }

  void _log(String message) {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    String three(int value) => value.toString().padLeft(3, '0');
    final stamp =
        '${two(now.hour)}:${two(now.minute)}:${two(now.second)}.${three(now.millisecond)}';
    final line = '[$stamp] [MonthlyPaymentSetting] ${message.trim()}';
    _debugLines.add(line);
    if (_debugLines.length > 220) {
      _debugLines.removeRange(0, _debugLines.length - 220);
    }
    debugPrint(line);
    _workspace?.log(message);
  }

  String _dartLiteral(String value) {
    return jsonEncode(value).replaceAll(r'$', r'\$');
  }

  String get _debugPrintCode {
    if (_debugLines.isEmpty) {
      return 'debugPrint(${_dartLiteral('[MonthlyPaymentSetting] 기록된 로그가 없습니다.')});';
    }
    return _debugLines
        .map((line) => 'debugPrint(${_dartLiteral(line)});')
        .join('\n');
  }

  Future<void> _showDeveloperStatusDialog() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!mounted || !enabled) return;
    _log(
      'developer_status_dialog_open active=${_workspace?.activeSection.name ?? '-'} amount=${_draft.paymentAmount ?? 0} extended=${_draft.extended} saving=$_saving',
    );
    await StatusDialog.showSuccess(
      context,
      title: '정기권 결제 디버그',
      description:
          'plate=$_plateNumber\nactive=${_workspace?.activeSection.name ?? '-'}\namount=${_draft.paymentAmount ?? 0}\nextended=${_draft.extended}\nsaving=$_saving',
      copyText: _debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  DateTime? get _nextStart {
    if (!_extensionAvailable) return null;
    final end = MonthlyDateRangeCalculator.parseStrict(_endDate);
    if (end == null) return null;
    return MonthlyDateRangeCalculator.calculateNextStartDate(
      end,
      regularType: _regularType,
    );
  }

  DateTime? get _nextEnd {
    if (!_extensionAvailable) return null;
    final end = MonthlyDateRangeCalculator.parseStrict(_endDate);
    if (end == null) return null;
    return MonthlyDateRangeCalculator.calculateNextEndDate(
      currentEndDate: end,
      duration: _duration,
      periodUnit: _periodUnit,
      regularType: _regularType,
    );
  }

  bool get _extensionAvailable {
    return MonthlyParkingOptions.isAllowedRegularType(_regularType) &&
        MonthlyParkingOptions.isAllowedPeriodUnit(
          regularType: _regularType,
          periodUnit: _periodUnit,
        ) &&
        _duration > 0 &&
        MonthlyDateRangeCalculator.parseStrict(_endDate) != null;
  }

  String get _extensionSummary {
    final nextStart = _nextStart;
    final nextEnd = _nextEnd;
    if (nextStart == null || nextEnd == null) {
      return '현재 정기권 정보로 연장 기간을 계산할 수 없습니다.';
    }
    return '현재 $_startDate ~ $_endDate\n연장 ${MonthlyDateRangeCalculator.format(nextStart)} ~ ${MonthlyDateRangeCalculator.format(nextEnd)}';
  }

  MonthlyWorkspaceSectionState _sectionState(MonthlyWorkspaceSection section) {
    switch (section) {
      case MonthlyWorkspaceSection.paymentAmount:
        if ((_draft.paymentAmount ?? 0) > 0) {
          return MonthlyWorkspaceSectionState.complete;
        }
        return _validationSubmitted
            ? MonthlyWorkspaceSectionState.error
            : MonthlyWorkspaceSectionState.incomplete;
      case MonthlyWorkspaceSection.paymentExtension:
        if (!_draft.extended || _extensionAvailable) {
          return MonthlyWorkspaceSectionState.complete;
        }
        return _validationSubmitted
            ? MonthlyWorkspaceSectionState.error
            : MonthlyWorkspaceSectionState.incomplete;
      case MonthlyWorkspaceSection.paymentNote:
        return _draft.note.trim().isEmpty
            ? MonthlyWorkspaceSectionState.optional
            : MonthlyWorkspaceSectionState.complete;
      case MonthlyWorkspaceSection.vehicle:
      case MonthlyWorkspaceSection.product:
      case MonthlyWorkspaceSection.period:
      case MonthlyWorkspaceSection.memo:
        return MonthlyWorkspaceSectionState.optional;
    }
  }

  Map<MonthlyWorkspaceSection, MonthlyWorkspaceSectionState>
      _allSectionStates() {
    return <MonthlyWorkspaceSection, MonthlyWorkspaceSectionState>{
      MonthlyWorkspaceSection.paymentAmount:
          _sectionState(MonthlyWorkspaceSection.paymentAmount),
      MonthlyWorkspaceSection.paymentExtension:
          _sectionState(MonthlyWorkspaceSection.paymentExtension),
      MonthlyWorkspaceSection.paymentNote:
          _sectionState(MonthlyWorkspaceSection.paymentNote),
    };
  }

  void _syncSectionStates({required String source}) {
    _workspace?.updateSectionStates(_allSectionStates(), source: source);
  }

  MonthlyWorkspaceSection? _firstInvalidSection() {
    for (final section in const <MonthlyWorkspaceSection>[
      MonthlyWorkspaceSection.paymentAmount,
      MonthlyWorkspaceSection.paymentExtension,
    ]) {
      final state = _sectionState(section);
      if (state == MonthlyWorkspaceSectionState.incomplete ||
          state == MonthlyWorkspaceSectionState.error) {
        return section;
      }
    }
    return null;
  }

  String _sectionTitle(MonthlyWorkspaceSection section) {
    switch (section) {
      case MonthlyWorkspaceSection.paymentAmount:
        return '결제 금액';
      case MonthlyWorkspaceSection.paymentExtension:
        return '기간 연장';
      case MonthlyWorkspaceSection.paymentNote:
        return '결제 메모';
      case MonthlyWorkspaceSection.vehicle:
      case MonthlyWorkspaceSection.product:
      case MonthlyWorkspaceSection.period:
      case MonthlyWorkspaceSection.memo:
        return '';
    }
  }

  String _sectionSummary(MonthlyWorkspaceSection section) {
    switch (section) {
      case MonthlyWorkspaceSection.paymentAmount:
        return (_draft.paymentAmount ?? 0) > 0
            ? '${_won.format(_draft.paymentAmount)}원'
            : '결제 금액 입력 필요';
      case MonthlyWorkspaceSection.paymentExtension:
        return _draft.extended ? _extensionSummary.replaceAll('\n', ' · ') : '연장하지 않음';
      case MonthlyWorkspaceSection.paymentNote:
        return _draft.note.trim().isEmpty ? '메모 없음' : _draft.note.trim();
      case MonthlyWorkspaceSection.vehicle:
      case MonthlyWorkspaceSection.product:
      case MonthlyWorkspaceSection.period:
      case MonthlyWorkspaceSection.memo:
        return '';
    }
  }

  ({Color color, IconData icon, String label}) _statusVisual(
    BuildContext context,
    MonthlyWorkspaceSectionState state,
  ) {
    final tokens = CommonUiTheme.of(context);
    switch (state) {
      case MonthlyWorkspaceSectionState.complete:
        return (
          color: tokens.success,
          icon: Icons.check_circle_rounded,
          label: '완료',
        );
      case MonthlyWorkspaceSectionState.incomplete:
        return (
          color: tokens.warning,
          icon: Icons.priority_high_rounded,
          label: '입력 필요',
        );
      case MonthlyWorkspaceSectionState.error:
        return (
          color: tokens.danger,
          icon: Icons.error_rounded,
          label: '오류',
        );
      case MonthlyWorkspaceSectionState.optional:
        return (
          color: tokens.info,
          icon: Icons.remove_circle_outline_rounded,
          label: '선택',
        );
    }
  }

  Rect? _sourceRectFor(MonthlyWorkspaceSection section) {
    final sectionContext = _sectionKeys[section]?.currentContext;
    final box = sectionContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Size _targetSize(MonthlyWorkspaceSection section) {
    switch (section) {
      case MonthlyWorkspaceSection.paymentAmount:
        return const Size(480, 350);
      case MonthlyWorkspaceSection.paymentExtension:
        return const Size(500, 500);
      case MonthlyWorkspaceSection.paymentNote:
        return const Size(500, 420);
      case MonthlyWorkspaceSection.vehicle:
      case MonthlyWorkspaceSection.product:
      case MonthlyWorkspaceSection.period:
      case MonthlyWorkspaceSection.memo:
        return const Size(480, 380);
    }
  }

  Future<void> _scrollToSection(MonthlyWorkspaceSection section) async {
    final context = _sectionKeys[section]?.currentContext;
    if (context == null) return;
    await Scrollable.ensureVisible(
      context,
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      alignment: .02,
    );
  }

  void _scheduleNavigationRequest(SecondaryMonthlyWorkspaceState workspace) {
    final requestId = workspace.navigationRequestId;
    if (requestId == _handledNavigationRequestId) return;
    _handledNavigationRequestId = requestId;
    final target = workspace.activeSection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_scrollToSection(target));
    });
  }

  bool _handleScrollNotification(ScrollNotification notification) {
    if (notification is! ScrollUpdateNotification &&
        notification is! UserScrollNotification) {
      return false;
    }
    final viewportContext = _scrollViewportKey.currentContext;
    final viewportBox = viewportContext?.findRenderObject() as RenderBox?;
    if (viewportBox == null || !viewportBox.attached) return false;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    MonthlyWorkspaceSection? best;
    double bestDistance = double.infinity;
    for (final section in const <MonthlyWorkspaceSection>[
      MonthlyWorkspaceSection.paymentAmount,
      MonthlyWorkspaceSection.paymentExtension,
      MonthlyWorkspaceSection.paymentNote,
    ]) {
      final sectionContext = _sectionKeys[section]?.currentContext;
      final box = sectionContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final distance = (top - viewportTop - 18).abs();
      if (top <= viewportTop + 96) {
        if (distance < bestDistance) {
          best = section;
          bestDistance = distance;
        }
      } else if (best == null && distance < bestDistance) {
        best = section;
        bestDistance = distance;
      }
    }
    if (best == null || best == _workspace?.activeSection) return false;
    _pendingVisibleSection = best;
    if (_visibleSectionScheduled) return false;
    _visibleSectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleSectionScheduled = false;
      if (!mounted) return;
      final section = _pendingVisibleSection;
      _pendingVisibleSection = null;
      if (section == null) return;
      _log('scroll_section_changed section=${section.name}');
      _workspace?.selectSection(section, source: 'payment_form_scroll');
    });
    return false;
  }

  void _applyEditorDraft(
    MonthlyWorkspaceSection section,
    MonthlyPaymentSettingsDraft draft,
  ) {
    setState(() {
      _draft = draft;
      _saveError = null;
    });
    _workspace?.setDirty(true, source: 'payment_editor_apply_${section.name}');
    _workspace?.selectSection(section, source: 'payment_editor_apply');
    _syncSectionStates(source: 'payment_editor_apply_${section.name}');
    _log('editor_applied section=${section.name}');
  }

  Future<void> _openSectionEditor(
    MonthlyWorkspaceSection section, {
    bool ensureVisible = true,
  }) async {
    if (_saving || _editingSection != null) return;
    _workspace?.selectSection(section, source: 'payment_summary_row_tap');
    if (ensureVisible) {
      await _scrollToSection(section);
      if (!mounted) return;
    }
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final sourceRect = _sourceRectFor(section);
    if (sourceRect == null) {
      _log('editor_open_failed section=${section.name} reason=no_source_rect');
      return;
    }
    setState(() => _editingSection = section);
    final trace = await DeveloperOperationTrace.start(
      context: Navigator.of(context, rootNavigator: true).context,
      title: '${_sectionTitle(section)} 편집',
      initialMessage: '정기권 결제 설정 편집을 시작합니다: section=${section.name}',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 편집 Dialog의 버그 아이콘에서 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 편집 동작을 콘솔에 기록합니다.',
      showDialogImmediately: false,
    );
    try {
      final applied = await showCommonOriginMorphDialog<bool>(
        context: context,
        sourceRect: sourceRect,
        targetSize: _targetSize(section),
        barrierDismissible: false,
        barrierLabel: '${_sectionTitle(section)} 편집',
        builder: (_) => MonthlyPaymentSettingSectionEditorDialog(
          section: section,
          initialDraft: _draft.detached(),
          extensionAvailable: _extensionAvailable,
          extensionSummary: _extensionSummary,
          trace: trace,
          onApply: (draft) => _applyEditorDraft(section, draft),
        ),
      );
      trace.log('편집 Dialog 종료: section=${section.name} applied=${applied == true}');
      _log('editor_closed section=${section.name} applied=${applied == true}');
    } finally {
      if (mounted && _editingSection == section) {
        setState(() => _editingSection = null);
      }
    }
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _validationSubmitted = true;
      _saveError = null;
    });
    _syncSectionStates(source: 'payment_submit_validation');
    final invalid = _firstInvalidSection();
    if (invalid != null) {
      _workspace?.requestSection(invalid, source: 'payment_validation_failed');
      _log('validation_failed section=${invalid.name}');
      await HapticFeedback.mediumImpact();
      await _scrollToSection(invalid);
      if (!mounted) return;
      await _openSectionEditor(invalid, ensureVisible: false);
      return;
    }

    final area = context.read<AreaState>().currentArea.trim();
    final userName = context.read<UserState>().name;
    final workspace = _workspace;
    setState(() => _saving = true);
    workspace?.setSaving(true, source: 'payment_submit_started');
    _log(
      'submit_started area=$area plate=$_plateNumber amount=${_draft.paymentAmount} extended=${_draft.extended}',
    );

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '정기권 결제',
      initialMessage: '정기권 결제 저장 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 결제 로그를 Status Dialog에서 확인하고 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 결제 로그를 콘솔에 기록합니다.',
    );

    try {
      if (area.isEmpty) throw StateError('현재 지점 정보가 없습니다.');
      String? nextStartText;
      String? nextEndText;
      if (_draft.extended) {
        final nextStart = _nextStart;
        final nextEnd = _nextEnd;
        if (nextStart == null || nextEnd == null) {
          throw StateError('연장 기간을 계산할 수 없습니다.');
        }
        nextStartText = MonthlyDateRangeCalculator.format(nextStart);
        nextEndText = MonthlyDateRangeCalculator.format(nextEnd);
      }
      trace.log(
        '결제 검증 통과: amount=${_draft.paymentAmount} extended=${_draft.extended} nextStart=${nextStartText ?? '-'} nextEnd=${nextEndText ?? '-'}',
        progress: .22,
      );
      await context.read<PlateRepository>().recordMonthlyPaymentAndMaybeExtend(
            plateNumber: _plateNumber,
            area: area,
            paidBy: userName,
            paymentAmount: _draft.paymentAmount ?? 0,
            note: _draft.note.trim(),
            extended: _draft.extended,
            regularType: _regularType ?? '',
            periodUnit: _periodUnit,
            durationValue: _duration,
            startDate: nextStartText,
            endDate: nextEndText,
            extendedBy: _draft.extended ? userName : null,
          );
      if (!mounted) return;
      final markerNow = DateTime.now();
      final markerMonth = '${markerNow.year.toString().padLeft(4, '0')}${markerNow.month.toString().padLeft(2, '0')}';
      trace.log(
        '결제 Repository 저장 완료 plateStatusMarkerPolicy=current_month_deduplicated markerMonth=$markerMonth',
        progress: .9,
      );
      await trace.succeed('정기권 결제가 완료되었습니다.');
      if (!mounted) return;
      workspace?.setDirty(false, source: 'payment_submit_success');
      workspace?.setSaving(false, source: 'payment_submit_success');
      setState(() => _saving = false);
      showSuccessSnackbar(context, '결제가 저장되었습니다.', useCommonUi: true);
      _log('submit_completed historyBefore=$_paymentHistoryCount');
      workspace?.returnToManagement(
        source: 'payment_submit_success',
        refresh: true,
      );
    } catch (error, stackTrace) {
      if (!mounted) return;
      const message = '결제 저장에 실패했습니다. 입력 내용은 유지됩니다.';
      await trace.fail(
        '정기권 결제 중 예외가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _saveError = message);
      _log('submit_failed error=$error');
      if (!trace.developerMode) {
        await StatusDialog.showFailure(
          context,
          title: '정기권 결제 불가',
          description: message,
          visibleDuration: const Duration(seconds: 5),
          useCommonUi: true,
        );
      }
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
      workspace?.setSaving(false, source: 'payment_submit_finished');
    }
  }

  void _returnToManagement() {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    _log('return_to_management');
    _workspace?.returnToManagement(source: 'payment_footer_back');
  }

  Widget _buildReadOnlySummary(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return OpsDockListSurface(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _plateNumber,
              style: textTheme.titleSmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_countType.isEmpty ? '정기 주차' : _countType} · ${_regularType ?? '상품 확인 필요'} · $_startDate ~ $_endDate',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '결제 이력 $_paymentHistoryCount회',
              style: textTheme.labelSmall?.copyWith(
                color: tokens.textSecondary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    MonthlyWorkspaceSection section,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workspace = context.watch<SecondaryMonthlyWorkspaceState>();
    final active = workspace.activeSection == section || _editingSection == section;
    final state = workspace.stateFor(section);
    final visual = _statusVisual(context, state);
    final summary = _sectionSummary(section);
    return KeyedSubtree(
      key: _sectionKeys[section],
      child: Semantics(
        button: true,
        label: '${_sectionTitle(section)}, $summary',
        child: OpsDockSelectableRowSurface(
          selected: active,
          selectionColor: tokens.accent,
          selectedContainer: tokens.accentContainer,
          onTap: () => unawaited(_openSectionEditor(section)),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _sectionTitle(section),
                            style: textTheme.bodyMedium?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        AnimatedSwitcher(
                          duration: _reduceMotion
                              ? Duration.zero
                              : CommonUiMotion.selection,
                          child: Icon(
                            visual.icon,
                            key: ValueKey<MonthlyWorkspaceSectionState>(state),
                            size: 17,
                            color: visual.color,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    AnimatedSwitcher(
                      duration: _reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      transitionBuilder: (child, animation) => FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(.02, 0),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      ),
                      child: Text(
                        summary,
                        key: ValueKey<String>('${section.name}_$summary'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.labelSmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w700,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              AnimatedRotation(
                turns: _editingSection == section ? .25 : 0,
                duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                child: Icon(
                  Icons.chevron_right_rounded,
                  size: 20,
                  color: active ? tokens.accent : tokens.iconSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusStrip(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workspace = context.watch<SecondaryMonthlyWorkspaceState>();
    final incompleteCount = workspace.incompleteSectionCount;
    final hasError = _saveError != null;
    final label = hasError
        ? '결제 확인 필요'
        : incompleteCount == 0
            ? '결제 입력 확인 완료'
            : '확인 필요 $incompleteCount개';
    return Row(
      children: [
        Text(
          label,
          style: textTheme.labelSmall?.copyWith(
            color: tokens.textSecondary,
            fontWeight: FontWeight.w700,
          ),
        ),
        const Spacer(),
        if (_devModeEnabled) ...[
          CommonIconButton(
            icon: Icons.bug_report_outlined,
            tooltip: '디버그 상태',
            onPressed: _showDeveloperStatusDialog,
            haptic: CommonHaptic.selection,
            size: 30,
            iconSize: 15,
          ),
          const SizedBox(width: 4),
        ],
        AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          child: Icon(
            hasError
                ? Icons.error_rounded
                : incompleteCount == 0
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
            key: ValueKey<String>(label),
            size: 16,
            color: hasError
                ? tokens.danger
                : incompleteCount == 0
                    ? tokens.success
                    : tokens.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final divider = Container(height: 1, color: tokens.borderSubtle);
    return NotificationListener<ScrollNotification>(
      onNotification: _handleScrollNotification,
      child: SingleChildScrollView(
        key: _scrollViewportKey,
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
        child: Column(
          children: [
            _buildReadOnlySummary(context),
            const SizedBox(height: 8),
            OpsDockListSurface(
              child: Column(
                children: [
                  if (_saveError != null) ...[
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _saveError!,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: tokens.danger,
                                    fontWeight: FontWeight.w800,
                                  ),
                        ),
                      ),
                    ),
                    divider,
                  ],
                  _buildSection(
                    context,
                    MonthlyWorkspaceSection.paymentAmount,
                  ),
                  divider,
                  _buildSection(
                    context,
                    MonthlyWorkspaceSection.paymentExtension,
                  ),
                  divider,
                  _buildSection(
                    context,
                    MonthlyWorkspaceSection.paymentNote,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return OpsDockContextFooter(
      children: [
        Expanded(
          child: CommonButton(
            label: '정기 주차 관리',
            icon: Icons.arrow_back_rounded,
            onPressed: _saving ? null : _returnToManagement,
            variant: CommonButtonVariant.secondary,
            haptic: CommonHaptic.selection,
            minHeight: 42,
            expand: true,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: CommonButton(
            label: '결제 완료',
            icon: Icons.check_circle_rounded,
            onPressed: _saving ? null : _handleSave,
            loading: _saving,
            haptic: CommonHaptic.medium,
            minHeight: 42,
            expand: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspace = context.watch<SecondaryMonthlyWorkspaceState>();
    _scheduleNavigationRequest(workspace);
    final tokens = CommonUiTheme.of(context);
    return Material(
      color: tokens.canvas,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: _buildStatusStrip(context),
              ),
              Expanded(child: _buildContent(context)),
              _buildFooter(context),
            ],
          ),
          OpsDockLoadingOverlay(loading: _saving),
        ],
      ),
    );
  }
}
