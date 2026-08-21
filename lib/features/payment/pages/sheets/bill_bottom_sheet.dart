import 'dart:async';

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
import '../../../../shared/secondary/application/secondary_bill_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../dev/application/area_state.dart';
import '../../applications/bill_state.dart';
import 'bill_setting_section_editor_dialog.dart';
import 'models/bill_settings_draft.dart';

class BillSettingWorkspace extends StatefulWidget {
  const BillSettingWorkspace({super.key});

  @override
  State<BillSettingWorkspace> createState() => _BillSettingWorkspaceState();
}

class _BillSettingWorkspaceState extends State<BillSettingWorkspace> {
  final TextEditingController _countTypeController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _scrollViewportKey = GlobalKey();
  final Map<BillSettingsSection, GlobalKey> _sectionKeys =
      <BillSettingsSection, GlobalKey>{
    for (final section in BillSettingsSection.values) section: GlobalKey(),
  };
  final NumberFormat _won = NumberFormat.decimalPattern();

  int? _basicStandard;
  int? _basicAmount;
  int? _addStandard;
  int? _addAmount;
  String? _saveError;
  bool _saving = false;
  bool _validationSubmitted = false;
  bool _reduceMotion = false;
  int _handledNavigationRequestId = -1;
  BillSettingsSection? _pendingVisibleSection;
  BillSettingsSection? _editingSection;
  bool _visibleSectionScheduled = false;
  SecondaryBillWorkspaceState? _workspace;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSectionStates(source: 'initial_form_state');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _workspace ??= context.read<SecondaryBillWorkspaceState>();
  }

  @override
  void dispose() {
    _countTypeController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _identityOk => _countTypeController.text.trim().isNotEmpty;
  bool get _pricingOk =>
      _basicStandard != null &&
      _basicAmount != null &&
      _basicAmount! >= 0 &&
      _addStandard != null &&
      _addAmount != null &&
      _addAmount! >= 0;

  BillSettingsSectionState _sectionState(BillSettingsSection section) {
    switch (section) {
      case BillSettingsSection.identity:
        if (_identityOk) return BillSettingsSectionState.complete;
        return _validationSubmitted
            ? BillSettingsSectionState.error
            : BillSettingsSectionState.incomplete;
      case BillSettingsSection.pricing:
        if (_pricingOk) return BillSettingsSectionState.complete;
        return _validationSubmitted
            ? BillSettingsSectionState.error
            : BillSettingsSectionState.incomplete;
    }
  }

  Map<BillSettingsSection, BillSettingsSectionState> _allSectionStates() {
    return <BillSettingsSection, BillSettingsSectionState>{
      for (final section in BillSettingsSection.values)
        section: _sectionState(section),
    };
  }

  void _syncSectionStates({required String source}) {
    _workspace?.updateSectionStates(_allSectionStates(), source: source);
  }

  BillSettingsDraft _currentDraft() {
    return BillSettingsDraft(
      countType: _countTypeController.text.trim(),
      basicStandard: _basicStandard,
      basicAmount: _basicAmount,
      addStandard: _addStandard,
      addAmount: _addAmount,
    );
  }

  void _applyEditorDraft(
    BillSettingsSection section,
    BillSettingsDraft draft,
  ) {
    setState(() {
      switch (section) {
        case BillSettingsSection.identity:
          _countTypeController.text = draft.countType;
          break;
        case BillSettingsSection.pricing:
          _basicStandard = draft.basicStandard;
          _basicAmount = draft.basicAmount;
          _addStandard = draft.addStandard;
          _addAmount = draft.addAmount;
          break;
      }
      _saveError = null;
    });
    _workspace?.setSettingsDirty(true, source: 'editor_apply_${section.name}');
    _workspace?.selectSettingsSection(section, source: 'editor_apply');
    _syncSectionStates(source: 'editor_apply_${section.name}');
  }

  String _sectionTitle(BillSettingsSection section) {
    switch (section) {
      case BillSettingsSection.identity:
        return '정산 유형';
      case BillSettingsSection.pricing:
        return '요금 기준';
    }
  }

  Size _editorTargetSize(BillSettingsSection section) {
    switch (section) {
      case BillSettingsSection.identity:
        return const Size(460, 330);
      case BillSettingsSection.pricing:
        return const Size(520, 540);
    }
  }

  Rect? _sourceRectFor(BillSettingsSection section) {
    final sectionContext = _sectionKeys[section]?.currentContext;
    final box = sectionContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  Future<void> _openSectionEditor(
    BillSettingsSection section, {
    bool ensureVisible = true,
  }) async {
    if (_saving || _editingSection != null) return;
    _workspace?.selectSettingsSection(section, source: 'summary_row_tap');
    if (ensureVisible) {
      await _scrollToSection(section);
      if (!mounted) return;
    }
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final sourceRect = _sourceRectFor(section);
    if (sourceRect == null) {
      _workspace?.log(
        'settings_editor_open_failed section=${section.name} reason=no_source_rect',
      );
      return;
    }
    setState(() => _editingSection = section);
    _workspace?.log('settings_editor_open_requested section=${section.name}');
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final trace = await DeveloperOperationTrace.start(
      context: rootContext,
      title: '${_sectionTitle(section)} 편집',
      initialMessage: '정산 유형 설정 편집을 시작합니다: section=${section.name}',
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
        builder: (dialogContext) {
          return BillSettingSectionEditorDialog(
            section: section,
            initialDraft: _currentDraft().detached(),
            trace: trace,
            onApply: (draft) => _applyEditorDraft(section, draft),
          );
        },
      );
      trace.log(
        '편집 Dialog 종료: section=${section.name} applied=${applied == true}',
      );
      _workspace?.log(
        'settings_editor_closed section=${section.name} applied=${applied == true}',
      );
    } finally {
      if (mounted && _editingSection == section) {
        setState(() => _editingSection = null);
      }
    }
  }

  Future<void> _scrollToSection(BillSettingsSection section) async {
    final sectionContext = _sectionKeys[section]?.currentContext;
    if (sectionContext == null) return;
    _workspace?.log('settings_scroll_requested section=${section.name}');
    await Scrollable.ensureVisible(
      sectionContext,
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      alignment: 0.02,
    );
  }

  void _scheduleNavigationRequest(SecondaryBillWorkspaceState workspace) {
    final requestId = workspace.settingsNavigationRequestId;
    if (requestId == _handledNavigationRequestId) return;
    _handledNavigationRequestId = requestId;
    final target = workspace.activeSettingsSection;
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
    BillSettingsSection? best;
    double bestDistance = double.infinity;
    for (final section in BillSettingsSection.values) {
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
    if (best == null || best == _workspace?.activeSettingsSection) return false;
    _pendingVisibleSection = best;
    if (_visibleSectionScheduled) return false;
    _visibleSectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibleSectionScheduled = false;
      if (!mounted) return;
      final section = _pendingVisibleSection;
      _pendingVisibleSection = null;
      if (section == null) return;
      _workspace?.selectSettingsSection(section, source: 'form_scroll');
    });
    return false;
  }

  BillSettingsSection? _firstInvalidSection() {
    final states = _allSectionStates();
    for (final section in BillSettingsSection.values) {
      final state = states[section];
      if (state == BillSettingsSectionState.error ||
          state == BillSettingsSectionState.incomplete) {
        return section;
      }
    }
    return null;
  }

  String _identitySummary() {
    final value = _countTypeController.text.trim();
    return value.isEmpty ? '유형명 입력 필요' : value;
  }

  String _pricingSummary() {
    if (!_pricingOk) return '기본/추가 요금 입력 필요';
    return '기본 ${_basicStandard}분 · ${_won.format(_basicAmount)}원 · 추가 ${_addStandard}분 · ${_won.format(_addAmount)}원';
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _validationSubmitted = true;
      _saveError = null;
    });
    _syncSectionStates(source: 'submit_validation');
    final invalidSection = _firstInvalidSection();
    if (invalidSection != null) {
      _workspace?.log(
        'settings_validation_failed section=${invalidSection.name}',
      );
      _workspace?.requestSettingsSection(
        invalidSection,
        source: 'submit_validation_failed',
      );
      await HapticFeedback.mediumImpact();
      await _scrollToSection(invalidSection);
      if (!mounted) return;
      await _openSectionEditor(invalidSection, ensureVisible: false);
      return;
    }

    final workspace = _workspace;
    final area = context.read<AreaState>().currentArea.trim();
    final billState = context.read<BillState>();
    final draft = _currentDraft();

    setState(() => _saving = true);
    workspace?.setSettingsSaving(true, source: 'submit_started');
    workspace?.log(
      'settings_submit_started countTypeLength=${draft.countType.length} basicStandard=${draft.basicStandard} addStandard=${draft.addStandard}',
    );

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '정산 유형 등록',
      initialMessage: '새 정산 유형의 등록 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 정산 유형 설정 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 정산 유형 설정 로그를 콘솔에 기록합니다.',
    );

    try {
      if (area.isEmpty) {
        throw StateError('현재 지역 정보가 없습니다.');
      }
      trace.log(
        '입력값 검증 통과: countTypeLength=${draft.countType.length}, basicStandard=${draft.basicStandard}, basicAmountValid=${draft.basicAmount != null}, addStandard=${draft.addStandard}, addAmountValid=${draft.addAmount != null}',
        progress: .18,
      );
      final billData = <String, dynamic>{
        'type': '변동',
        'CountType': draft.countType,
        'basicStandard': draft.basicStandard,
        'basicAmount': draft.basicAmount,
        'addStandard': draft.addStandard,
        'addAmount': draft.addAmount,
        'area': area,
        'isSelected': false,
      };
      trace.log('저장 모델 구성 완료: area=$area type=변동', progress: .38);
      trace.log('Firestore 정산 문서 저장을 요청합니다.', progress: .58);
      await billState.addBillFromMap(billData);
      if (!mounted) return;
      trace.log('정산 캐시 반영 완료', progress: .9);
      await trace.succeed('정산 유형 등록이 완료되었습니다.');
      if (!mounted) return;
      workspace?.setSettingsDirty(false, source: 'submit_success');
      workspace?.log('settings_submit_completed mode=create');
      showSuccessSnackbar(
        context,
        '정산 유형 등록이 완료되었습니다.',
        useCommonUi: true,
      );
      workspace?.returnToManagement(source: 'submit_success');
    } catch (error, stackTrace) {
      await trace.fail(
        '정산 유형 등록 중 예외가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      final message = '정산 유형을 저장하지 못했습니다. 입력 내용은 유지됩니다.';
      setState(() => _saveError = message);
      workspace?.log('settings_submit_exception error=$error');
      if (!trace.developerMode) {
        await StatusDialog.showFailure(
          context,
          title: '정산 유형 등록 불가',
          description: '$message\n네트워크 상태를 확인한 뒤 다시 시도하세요.',
          visibleDuration: const Duration(seconds: 5),
          useCommonUi: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
      workspace?.setSettingsSaving(false, source: 'submit_finished');
    }
  }

  void _returnToManagement() {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    _workspace?.returnToManagement(source: 'settings_footer_back');
  }

  Widget _sectionContainer(BillSettingsSection section, Widget child) {
    return KeyedSubtree(
      key: _sectionKeys[section],
      child: child,
    );
  }

  ({Color color, IconData icon, String label}) _sectionStatusVisual(
    BuildContext context,
    BillSettingsSectionState state,
  ) {
    final tokens = CommonUiTheme.of(context);
    switch (state) {
      case BillSettingsSectionState.complete:
        return (
          color: tokens.success,
          icon: Icons.check_circle_rounded,
          label: '완료',
        );
      case BillSettingsSectionState.incomplete:
        return (
          color: tokens.warning,
          icon: Icons.priority_high_rounded,
          label: '입력 필요',
        );
      case BillSettingsSectionState.error:
        return (
          color: tokens.danger,
          icon: Icons.error_rounded,
          label: '오류',
        );
    }
  }

  Widget _buildSectionStatusTrailing(
    BuildContext context, {
    required String title,
    required BillSettingsSection section,
    required SecondaryBillWorkspaceState workspace,
  }) {
    final state = workspace.stateFor(section);
    final visual = _sectionStatusVisual(context, state);
    return Semantics(
      label: '$title, ${visual.label}',
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
          key: ValueKey<BillSettingsSectionState>(state),
          size: 17,
          color: visual.color,
        ),
      ),
    );
  }

  Widget _buildSummarySection(
    BuildContext context, {
    required BillSettingsSection section,
    required String title,
    required String summary,
  }) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workspace = context.watch<SecondaryBillWorkspaceState>();
    final active = workspace.activeSettingsSection == section ||
        _editingSection == section;

    return _sectionContainer(
      section,
      Semantics(
        button: true,
        label: '$title, $summary',
        child: OpsDockSelectableRowSurface(
          selected: active,
          selectionColor: tokens.accent,
          selectedContainer: tokens.accentContainer,
          onTap: () => unawaited(_openSectionEditor(section)),
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: textTheme.bodyMedium?.copyWith(
                              color: tokens.textPrimary,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildSectionStatusTrailing(
                          context,
                          title: title,
                          section: section,
                          workspace: workspace,
                        ),
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
                duration:
                    _reduceMotion ? Duration.zero : CommonUiMotion.selection,
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
    final workspace = context.watch<SecondaryBillWorkspaceState>();
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
        AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween<double>(begin: .96, end: 1).animate(animation),
              child: child,
            ),
          ),
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

  Widget _buildFlatInlineMessage(BuildContext context, String? message) {
    if (message == null || message.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 16, color: tokens.danger),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message.trim(),
              style: textTheme.labelSmall?.copyWith(
                color: tokens.danger,
                fontWeight: FontWeight.w800,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
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
                    : Column(
                        children: [
                          _buildFlatInlineMessage(context, _saveError),
                          divider,
                        ],
                      ),
              ),
              _buildSummarySection(
                context,
                section: BillSettingsSection.identity,
                title: '정산 유형',
                summary: _identitySummary(),
              ),
              divider,
              _buildSummarySection(
                context,
                section: BillSettingsSection.pricing,
                title: '요금 기준',
                summary: _pricingSummary(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final key = _saving
        ? 'bill_settings_footer_saving'
        : 'bill_settings_footer_create';
    return OpsDockContextFooter(
      key: ValueKey<String>(key),
      children: [
        Expanded(
          child: CommonButton(
            label: '정산 목록',
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
            label: '등록 완료',
            icon: Icons.add_card_rounded,
            onPressed: _saving ? null : _handleSave,
            loading: _saving,
            variant: CommonButtonVariant.primary,
            haptic: CommonHaptic.selection,
            minHeight: 42,
            expand: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final workspace = context.watch<SecondaryBillWorkspaceState>();
    _scheduleNavigationRequest(workspace);

    return Material(
      color: tokens.canvas,
      child: Stack(
        children: [
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: _buildStatusStrip(context),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
                  child: _buildContentSurface(context),
                ),
              ),
              OpsDockContextFooterTransition(
                child: _buildFooter(context),
              ),
            ],
          ),
          OpsDockLoadingOverlay(loading: _saving),
        ],
      ),
    );
  }
}
