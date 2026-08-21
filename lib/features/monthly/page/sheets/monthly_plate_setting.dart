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
import 'models/monthly_settings_draft.dart';
import 'monthly_plate_setting_section_editor_dialog.dart';

class MonthlyPlateSettingWorkspace extends StatefulWidget {
  const MonthlyPlateSettingWorkspace({
    super.key,
    required this.isEditMode,
    this.initialDocId,
    this.initialData,
  });

  final bool isEditMode;
  final String? initialDocId;
  final Map<String, dynamic>? initialData;

  @override
  State<MonthlyPlateSettingWorkspace> createState() =>
      _MonthlyPlateSettingWorkspaceState();
}

class _MonthlyPlateSettingWorkspaceState
    extends State<MonthlyPlateSettingWorkspace> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _scrollViewportKey = GlobalKey();
  final Map<MonthlyWorkspaceSection, GlobalKey> _sectionKeys =
      <MonthlyWorkspaceSection, GlobalKey>{
    MonthlyWorkspaceSection.vehicle: GlobalKey(),
    MonthlyWorkspaceSection.product: GlobalKey(),
    MonthlyWorkspaceSection.period: GlobalKey(),
    MonthlyWorkspaceSection.memo: GlobalKey(),
  };
  final List<String> _debugLines = <String>[];
  final NumberFormat _won = NumberFormat.decimalPattern();

  late MonthlySettingsDraft _draft;
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
    _draft = widget.isEditMode &&
            widget.initialDocId != null &&
            widget.initialData != null
        ? MonthlySettingsDraft.fromRecord(
            docId: widget.initialDocId!,
            data: widget.initialData!,
          )
        : MonthlySettingsDraft.empty();
    _devModeEnabled = DevAuth.devModeEnabled.value;
    DevAuth.devModeEnabled.addListener(_handleDevModeChanged);
    _log(
      'mounted mode=${widget.isEditMode ? 'edit' : 'create'} doc=${widget.initialDocId ?? '-'}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSectionStates(source: 'initial_form_state');
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
    final line = '[$stamp] [MonthlyPlateSetting] ${message.trim()}';
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
      return 'debugPrint(${_dartLiteral('[MonthlyPlateSetting] 기록된 로그가 없습니다.')});';
    }
    return _debugLines
        .map((line) => 'debugPrint(${_dartLiteral(line)});')
        .join('\n');
  }

  Future<void> _showDeveloperStatusDialog() async {
    final enabled = await DevAuth.isDevModeEnabled();
    if (!mounted || !enabled) return;
    _log(
      'developer_status_dialog_open active=${_workspace?.activeSection.name ?? '-'} dirty=${_workspace?.dirty ?? false} saving=$_saving',
    );
    await StatusDialog.showSuccess(
      context,
      title: widget.isEditMode ? '정기권 수정 디버그' : '정기권 등록 디버그',
      description:
          'active=${_workspace?.activeSection.name ?? '-'}\ndirty=${_workspace?.dirty ?? false}\nsaving=$_saving\nmode=${widget.isEditMode ? 'edit' : 'create'}',
      copyText: _debugPrintCode,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
  }

  bool get _vehicleOk {
    if (widget.isEditMode) return true;
    return (_draft.frontDigit.length == 2 || _draft.frontDigit.length == 3) &&
        _draft.middleDigit.length == 1 &&
        _draft.backDigit.length == 4 &&
        _draft.region.trim().isNotEmpty;
  }

  bool get _productOk {
    return _draft.countType.trim().isNotEmpty &&
        MonthlyParkingOptions.isAllowedRegularType(_draft.regularType) &&
        MonthlyParkingOptions.isAllowedPeriodUnit(
          regularType: _draft.regularType,
          periodUnit: _draft.periodUnit,
        ) &&
        (_draft.regularAmount ?? 0) > 0 &&
        (_draft.duration ?? 0) > 0;
  }

  bool get _periodOk {
    final start = MonthlyDateRangeCalculator.parseStrict(_draft.startDate);
    final end = MonthlyDateRangeCalculator.parseStrict(_draft.endDate);
    final duration = _draft.duration ?? 0;
    if (start == null || end == null || duration <= 0) return false;
    if (!MonthlyParkingOptions.isAllowedRegularType(_draft.regularType)) {
      return false;
    }
    final normalized = MonthlyDateRangeCalculator.normalizeStartDate(
      startDate: start,
      regularType: _draft.regularType,
    );
    if (MonthlyDateRangeCalculator.format(normalized) !=
        MonthlyDateRangeCalculator.format(start)) {
      return false;
    }
    final expected = MonthlyDateRangeCalculator.calculateEndDate(
      startDate: normalized,
      duration: duration,
      periodUnit: _draft.periodUnit,
      regularType: _draft.regularType,
    );
    return MonthlyDateRangeCalculator.format(expected) ==
        MonthlyDateRangeCalculator.format(end);
  }

  MonthlyWorkspaceSectionState _sectionState(MonthlyWorkspaceSection section) {
    bool valid;
    switch (section) {
      case MonthlyWorkspaceSection.vehicle:
        valid = _vehicleOk;
        break;
      case MonthlyWorkspaceSection.product:
        valid = _productOk;
        break;
      case MonthlyWorkspaceSection.period:
        valid = _periodOk;
        break;
      case MonthlyWorkspaceSection.memo:
        return _draft.customStatus.trim().isEmpty &&
                _draft.specialNote.trim().isEmpty
            ? MonthlyWorkspaceSectionState.optional
            : MonthlyWorkspaceSectionState.complete;
      case MonthlyWorkspaceSection.paymentAmount:
      case MonthlyWorkspaceSection.paymentExtension:
      case MonthlyWorkspaceSection.paymentNote:
        return MonthlyWorkspaceSectionState.optional;
    }
    if (valid) return MonthlyWorkspaceSectionState.complete;
    return _validationSubmitted
        ? MonthlyWorkspaceSectionState.error
        : MonthlyWorkspaceSectionState.incomplete;
  }

  Map<MonthlyWorkspaceSection, MonthlyWorkspaceSectionState>
      _allSectionStates() {
    return <MonthlyWorkspaceSection, MonthlyWorkspaceSectionState>{
      for (final section in const <MonthlyWorkspaceSection>[
        MonthlyWorkspaceSection.vehicle,
        MonthlyWorkspaceSection.product,
        MonthlyWorkspaceSection.period,
        MonthlyWorkspaceSection.memo,
      ])
        section: _sectionState(section),
    };
  }

  void _syncSectionStates({required String source}) {
    _workspace?.updateSectionStates(_allSectionStates(), source: source);
  }

  MonthlyWorkspaceSection? _firstInvalidSection() {
    for (final section in const <MonthlyWorkspaceSection>[
      MonthlyWorkspaceSection.vehicle,
      MonthlyWorkspaceSection.product,
      MonthlyWorkspaceSection.period,
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
      case MonthlyWorkspaceSection.vehicle:
        return '차량 정보';
      case MonthlyWorkspaceSection.product:
        return '상품과 요금';
      case MonthlyWorkspaceSection.period:
        return '정기권 기간';
      case MonthlyWorkspaceSection.memo:
        return '운영 메모';
      case MonthlyWorkspaceSection.paymentAmount:
        return '결제 금액';
      case MonthlyWorkspaceSection.paymentExtension:
        return '기간 연장';
      case MonthlyWorkspaceSection.paymentNote:
        return '결제 메모';
    }
  }

  String _sectionSummary(MonthlyWorkspaceSection section) {
    switch (section) {
      case MonthlyWorkspaceSection.vehicle:
        if (!_vehicleOk) return '번호판 지역과 차량번호 입력 필요';
        return '${_draft.region} · ${_draft.plateNumber}';
      case MonthlyWorkspaceSection.product:
        if (!_productOk) return '정기권 이름, 타입, 요금과 기간 입력 필요';
        return '${_draft.countType} · ${_draft.regularType} · ${_won.format(_draft.regularAmount)}원 · ${MonthlyParkingOptions.durationLabel(regularType: _draft.regularType, duration: _draft.duration ?? 1, periodUnit: _draft.periodUnit)}';
      case MonthlyWorkspaceSection.period:
        if (!_periodOk) return '시작일과 종료일 확인 필요';
        return '${_draft.startDate} ~ ${_draft.endDate}';
      case MonthlyWorkspaceSection.memo:
        final values = <String>[
          if (_draft.customStatus.trim().isNotEmpty) _draft.customStatus.trim(),
          if (_draft.specialNote.trim().isNotEmpty) _draft.specialNote.trim(),
        ];
        return values.isEmpty ? '메모 없음' : values.join(' · ');
      case MonthlyWorkspaceSection.paymentAmount:
      case MonthlyWorkspaceSection.paymentExtension:
      case MonthlyWorkspaceSection.paymentNote:
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

  Size _editorTargetSize(MonthlyWorkspaceSection section) {
    switch (section) {
      case MonthlyWorkspaceSection.vehicle:
        return Size(520, widget.isEditMode ? 390 : 470);
      case MonthlyWorkspaceSection.product:
        return const Size(520, 500);
      case MonthlyWorkspaceSection.period:
        return const Size(500, 450);
      case MonthlyWorkspaceSection.memo:
        return const Size(500, 470);
      case MonthlyWorkspaceSection.paymentAmount:
      case MonthlyWorkspaceSection.paymentExtension:
      case MonthlyWorkspaceSection.paymentNote:
        return const Size(480, 420);
    }
  }

  Rect? _sourceRectFor(MonthlyWorkspaceSection section) {
    final sectionContext = _sectionKeys[section]?.currentContext;
    final box = sectionContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  Future<void> _scrollToSection(MonthlyWorkspaceSection section) async {
    final sectionContext = _sectionKeys[section]?.currentContext;
    if (sectionContext == null) return;
    await Scrollable.ensureVisible(
      sectionContext,
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
      MonthlyWorkspaceSection.vehicle,
      MonthlyWorkspaceSection.product,
      MonthlyWorkspaceSection.period,
      MonthlyWorkspaceSection.memo,
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
      _workspace?.selectSection(section, source: 'form_scroll');
    });
    return false;
  }

  void _applyEditorDraft(
    MonthlyWorkspaceSection section,
    MonthlySettingsDraft draft,
  ) {
    setState(() {
      _draft = draft;
      _saveError = null;
    });
    _workspace?.setDirty(true, source: 'editor_apply_${section.name}');
    _workspace?.selectSection(section, source: 'editor_apply');
    _syncSectionStates(source: 'editor_apply_${section.name}');
    _log('editor_applied section=${section.name}');
  }

  Future<void> _openSectionEditor(
    MonthlyWorkspaceSection section, {
    bool ensureVisible = true,
  }) async {
    if (_saving || _editingSection != null) return;
    _workspace?.selectSection(section, source: 'summary_row_tap');
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
      initialMessage: '정기권 설정 편집을 시작합니다: section=${section.name}',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 편집 Dialog의 버그 아이콘에서 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 편집 동작을 콘솔에 기록합니다.',
      showDialogImmediately: false,
    );
    try {
      trace.log(
        '원본 row bounds 확보: width=${sourceRect.width.toStringAsFixed(1)}, height=${sourceRect.height.toStringAsFixed(1)}',
      );
      final applied = await showCommonOriginMorphDialog<bool>(
        context: context,
        sourceRect: sourceRect,
        targetSize: _editorTargetSize(section),
        barrierDismissible: false,
        barrierLabel: '${_sectionTitle(section)} 편집',
        builder: (_) => MonthlyPlateSettingSectionEditorDialog(
          section: section,
          initialDraft: _draft.detached(),
          isEditMode: widget.isEditMode,
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
    _syncSectionStates(source: 'submit_validation');
    final invalid = _firstInvalidSection();
    if (invalid != null) {
      _log('validation_failed section=${invalid.name}');
      _workspace?.requestSection(invalid, source: 'submit_validation_failed');
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
    workspace?.setSaving(true, source: 'submit_started');
    _log(
      'submit_started mode=${widget.isEditMode ? 'edit' : 'create'} area=$area plate=${_draft.plateNumber}',
    );

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: widget.isEditMode ? '정기권 수정' : '정기권 등록',
      initialMessage: widget.isEditMode
          ? '정기권 수정 요청을 시작합니다.'
          : '정기권 등록 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 저장 로그를 Status Dialog에서 확인하고 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 저장 로그를 콘솔에 기록합니다.',
    );

    try {
      if (area.isEmpty) throw StateError('현재 지점 정보가 없습니다.');
      trace.log(
        '입력값 검증 통과: plate=${_draft.plateNumber} type=${_draft.regularType} duration=${_draft.duration} amount=${_draft.regularAmount}',
        progress: .2,
      );
      await context.read<PlateRepository>().setMonthlyPlateStatus(
            plateNumber: _draft.plateNumber,
            area: area,
            region: _draft.region.trim().isEmpty ? '전국' : _draft.region.trim(),
            customStatus: _draft.customStatus.trim(),
            createdBy: userName,
            countType: _draft.countType.trim(),
            regularAmount: _draft.regularAmount ?? 0,
            regularDurationValue: _draft.duration ?? 0,
            regularType: _draft.regularType ?? '',
            startDate: _draft.startDate.trim(),
            endDate: _draft.endDate.trim(),
            periodUnit: _draft.periodUnit,
            specialNote: _draft.specialNote.trim(),
            isExtended: false,
          );
      if (!mounted) return;
      trace.log('Repository 저장 완료', progress: .9);
      await trace.succeed(
        widget.isEditMode ? '정기권 수정이 완료되었습니다.' : '정기권 등록이 완료되었습니다.',
      );
      if (!mounted) return;
      workspace?.setDirty(false, source: 'submit_success');
      workspace?.setSaving(false, source: 'submit_success');
      setState(() => _saving = false);
      showSuccessSnackbar(
        context,
        widget.isEditMode ? '정기 주차 정보가 수정되었습니다.' : '정기 주차가 등록되었습니다.',
        useCommonUi: true,
      );
      _log('submit_completed mode=${widget.isEditMode ? 'edit' : 'create'}');
      workspace?.returnToManagement(source: 'submit_success', refresh: true);
    } catch (error, stackTrace) {
      if (!mounted) return;
      final message = widget.isEditMode
          ? '정기권 수정에 실패했습니다. 입력 내용은 유지됩니다.'
          : '정기권 등록에 실패했습니다. 입력 내용은 유지됩니다.';
      await trace.fail(
        '정기권 저장 중 예외가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _saveError = message);
      _log('submit_failed error=$error');
      if (!trace.developerMode) {
        await StatusDialog.showFailure(
          context,
          title: widget.isEditMode ? '정기권 수정 불가' : '정기권 등록 불가',
          description: message,
          visibleDuration: const Duration(seconds: 5),
          useCommonUi: true,
        );
      }
    } finally {
      if (mounted && _saving) setState(() => _saving = false);
      workspace?.setSaving(false, source: 'submit_finished');
    }
  }

  void _returnToManagement() {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    _log('return_to_management');
    _workspace?.returnToManagement(source: 'settings_footer_back');
  }

  Widget _buildSectionStatusTrailing(
    BuildContext context, {
    required MonthlyWorkspaceSection section,
  }) {
    final workspace = context.watch<SecondaryMonthlyWorkspaceState>();
    final state = workspace.stateFor(section);
    final visual = _statusVisual(context, state);
    return Semantics(
      label: '${_sectionTitle(section)}, ${visual.label}',
      child: AnimatedSwitcher(
        duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .94, end: 1).animate(animation),
            child: child,
          ),
        ),
        child: Icon(
          visual.icon,
          key: ValueKey<MonthlyWorkspaceSectionState>(state),
          size: 17,
          color: visual.color,
        ),
      ),
    );
  }

  Widget _buildSummarySection(
    BuildContext context,
    MonthlyWorkspaceSection section,
  ) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workspace = context.watch<SecondaryMonthlyWorkspaceState>();
    final active = workspace.activeSection == section || _editingSection == section;
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
                        const SizedBox(width: 8),
                        _buildSectionStatusTrailing(context, section: section),
                      ],
                    ),
                    const SizedBox(height: 5),
                    AnimatedSwitcher(
                      duration: _reduceMotion
                          ? Duration.zero
                          : CommonUiMotion.selection,
                      switchInCurve: CommonUiMotion.enter,
                      switchOutCurve: CommonUiMotion.exit,
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
                curve: CommonUiMotion.standard,
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
    final hasSaveError = _saveError != null && _saveError!.trim().isNotEmpty;
    final label = hasSaveError
        ? '저장 확인 필요'
        : incompleteCount == 0
            ? '입력 확인 완료'
            : '확인 필요 $incompleteCount개';
    final icon = hasSaveError
        ? Icons.error_rounded
        : incompleteCount == 0
            ? Icons.check_circle_rounded
            : Icons.error_outline_rounded;
    final color = hasSaveError
        ? tokens.danger
        : incompleteCount == 0
            ? tokens.success
            : tokens.warning;
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
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          child: Icon(
            icon,
            key: ValueKey<String>(label),
            size: 16,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildContentSurface(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final divider = Container(height: 1, color: tokens.borderSubtle);
    return OpsDockListSurface(
      child: NotificationListener<ScrollNotification>(
        onNotification: _handleScrollNotification,
        child: SingleChildScrollView(
          key: _scrollViewportKey,
          controller: _scrollController,
          padding: EdgeInsets.zero,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AnimatedSize(
                duration:
                    _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.enter,
                child: _saveError == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.all(12),
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
              if (_saveError != null) divider,
              _buildSummarySection(context, MonthlyWorkspaceSection.vehicle),
              divider,
              _buildSummarySection(context, MonthlyWorkspaceSection.product),
              divider,
              _buildSummarySection(context, MonthlyWorkspaceSection.period),
              divider,
              _buildSummarySection(context, MonthlyWorkspaceSection.memo),
            ],
          ),
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
            label: widget.isEditMode ? '수정 완료' : '생성 완료',
            icon: widget.isEditMode ? Icons.save_rounded : Icons.add_rounded,
            onPressed: _saving ? null : _handleSave,
            loading: _saving,
            variant: CommonButtonVariant.primary,
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                  child: _buildContentSurface(context),
                ),
              ),
              _buildFooter(context),
            ],
          ),
          OpsDockLoadingOverlay(loading: _saving),
        ],
      ),
    );
  }
}
