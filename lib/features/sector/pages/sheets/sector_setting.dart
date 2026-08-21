import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_origin_morph_dialog.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/application/secondary_sector_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../dev/application/area_state.dart';
import '../../applications/sector_state.dart';
import '../../domain/models/sector_model.dart';
import 'models/sector_settings_draft.dart';
import 'sector_setting_section_editor_dialog.dart';

class SectorSettingWorkspace extends StatefulWidget {
  const SectorSettingWorkspace({
    super.key,
    required this.initialSector,
  });

  final SectorModel? initialSector;

  @override
  State<SectorSettingWorkspace> createState() =>
      _SectorSettingWorkspaceState();
}

class _SectorSettingWorkspaceState extends State<SectorSettingWorkspace> {
  final TextEditingController _nameController = TextEditingController();
  final GlobalKey _identityKey = GlobalKey();
  String? _saveError;
  bool _saving = false;
  bool _validationSubmitted = false;
  bool _reduceMotion = false;
  SectorSettingsSection? _editingSection;
  SecondarySectorWorkspaceState? _workspace;
  SectorModel? _initialSectorSnapshot;

  bool get isEditMode => _initialSectorSnapshot != null;

  @override
  void initState() {
    super.initState();
    _initialSectorSnapshot = widget.initialSector;
    _populateInitialValue();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSectionStates(source: 'initial_form_state');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _workspace ??= context.read<SecondarySectorWorkspaceState>();
  }

  @override
  void didUpdateWidget(covariant SectorSettingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialSector?.id == widget.initialSector?.id) return;
    if (widget.initialSector == null &&
        _saving &&
        _initialSectorSnapshot != null) {
      return;
    }
    _initialSectorSnapshot = widget.initialSector;
    _populateInitialValue();
    _validationSubmitted = false;
    _saveError = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSectionStates(source: 'editing_target_changed');
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _populateInitialValue() {
    _nameController.text = _initialSectorSnapshot?.name ?? '';
  }

  String get _nameError {
    final value = _nameController.text.trim();
    if (value.isEmpty) return '섹터명을 입력해야 합니다.';
    if (value.contains('/')) return '섹터명에는 / 문자를 사용할 수 없습니다.';
    if (value.length > 40) return '섹터명은 40자 이하로 입력해 주세요.';
    return '';
  }

  bool get _nameOk => _nameError.isEmpty;

  SectorSettingsSectionState _sectionState(SectorSettingsSection section) {
    switch (section) {
      case SectorSettingsSection.identity:
        if (_nameOk) return SectorSettingsSectionState.complete;
        return _validationSubmitted
            ? SectorSettingsSectionState.error
            : SectorSettingsSectionState.incomplete;
    }
  }

  Map<SectorSettingsSection, SectorSettingsSectionState> _allSectionStates() {
    return <SectorSettingsSection, SectorSettingsSectionState>{
      SectorSettingsSection.identity:
          _sectionState(SectorSettingsSection.identity),
    };
  }

  void _syncSectionStates({required String source}) {
    _workspace?.updateSectionStates(_allSectionStates(), source: source);
  }

  SectorSettingsDraft _currentDraft() {
    return SectorSettingsDraft(name: _nameController.text.trim());
  }

  void _applyEditorDraft(
    SectorSettingsSection section,
    SectorSettingsDraft draft,
  ) {
    setState(() {
      switch (section) {
        case SectorSettingsSection.identity:
          _nameController.text = draft.name;
          break;
      }
      _saveError = null;
    });
    _workspace?.setSettingsDirty(true, source: 'editor_apply_${section.name}');
    _workspace?.selectSettingsSection(section, source: 'editor_apply');
    _syncSectionStates(source: 'editor_apply_${section.name}');
  }

  String _sectionTitle(SectorSettingsSection section) {
    switch (section) {
      case SectorSettingsSection.identity:
        return '섹터 기본 정보';
    }
  }

  Rect? _sourceRectFor(SectorSettingsSection section) {
    final key = switch (section) {
      SectorSettingsSection.identity => _identityKey,
    };
    final sectionContext = key.currentContext;
    final box = sectionContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  Future<void> _openSectionEditor(SectorSettingsSection section) async {
    if (_saving || _editingSection != null) return;
    _workspace?.selectSettingsSection(section, source: 'summary_row_tap');
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
      initialMessage: '섹터 설정 편집을 시작합니다: section=${section.name}',
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
        targetSize: const Size(460, 330),
        barrierDismissible: false,
        barrierLabel: '${_sectionTitle(section)} 편집',
        builder: (dialogContext) {
          return SectorSettingSectionEditorDialog(
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

  String _errorMessage(Object error, {required String fallback}) {
    if (error is SectorDuplicateNameException ||
        error is SectorAreaMismatchException ||
        error is SectorNotFoundException) {
      return error.toString();
    }
    if (error is StateError) return error.message;
    if (error is ArgumentError) {
      return error.message?.toString() ?? fallback;
    }
    return fallback;
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _validationSubmitted = true;
      _saveError = null;
    });
    _syncSectionStates(source: 'submit_validation');
    if (!_nameOk) {
      _workspace?.log('settings_validation_failed section=identity');
      _workspace?.requestSettingsSection(
        SectorSettingsSection.identity,
        source: 'submit_validation_failed',
      );
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      await _openSectionEditor(SectorSettingsSection.identity);
      return;
    }

    final workspace = _workspace;
    final state = context.read<SectorState>();
    final area = context.read<AreaState>().currentArea.trim();
    final initialSector = _initialSectorSnapshot;
    final draft = _currentDraft();
    final operationTitle = isEditMode ? '섹터 수정' : '섹터 등록';

    setState(() => _saving = true);
    workspace?.setSettingsSaving(true, source: 'submit_started');
    workspace?.log(
      'settings_submit_started mode=${isEditMode ? 'edit' : 'create'} nameLength=${draft.name.length}',
    );

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: operationTitle,
      initialMessage: '$operationTitle 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 섹터 설정 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 섹터 설정 로그를 콘솔에 기록합니다.',
    );

    try {
      if (area.isEmpty) {
        throw StateError('현재 지역 정보가 없습니다.');
      }
      final targetDocumentId = buildSectorDocumentId(
        name: draft.name,
        area: area,
      );
      trace.log(
        '입력값 검증 통과: mode=${isEditMode ? 'edit' : 'create'}, nameLength=${draft.name.length}, areaReady=true, targetIdLength=${targetDocumentId.length}',
        progress: .2,
      );
      trace.log('섹터명 정규화 및 중복 여부를 확인합니다.', progress: .42);
      final result = initialSector == null
          ? await state.createSector(draft.name)
          : await state.updateSector(
              id: initialSector.id,
              name: draft.name,
            );
      trace.log(
        'Firestore sector 저장 및 지역별 캐시 반영 완료: resultIdLength=${result.id.length}',
        progress: .88,
      );
      await trace.succeed('$operationTitle이 완료되었습니다.');
      if (!mounted) return;
      workspace?.setSettingsDirty(false, source: 'submit_success');
      workspace?.log(
        'settings_submit_completed mode=${isEditMode ? 'edit' : 'create'} resultId=${result.id}',
      );
      showSuccessSnackbar(
        context,
        isEditMode ? '섹터 수정이 완료되었습니다.' : '섹터 등록이 완료되었습니다.',
        useCommonUi: true,
      );
      workspace?.returnToManagement(source: 'submit_success');
    } catch (error, stackTrace) {
      final fallback = isEditMode ? '섹터 수정에 실패했습니다.' : '섹터 등록에 실패했습니다.';
      await trace.fail(
        '$operationTitle 중 예외가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      final detail = _errorMessage(error, fallback: fallback);
      final message = '$detail 입력 내용은 유지됩니다.';
      setState(() => _saveError = message);
      workspace?.log('settings_submit_exception error=$error');
      if (!trace.developerMode) {
        await StatusDialog.showFailure(
          context,
          title: '$operationTitle 불가',
          description: '$message\n내용을 확인한 뒤 다시 시도하세요.',
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

  ({Color color, IconData icon, String label}) _sectionStatusVisual(
    BuildContext context,
    SectorSettingsSectionState state,
  ) {
    final tokens = CommonUiTheme.of(context);
    switch (state) {
      case SectorSettingsSectionState.complete:
        return (
          color: tokens.success,
          icon: Icons.check_circle_rounded,
          label: '완료',
        );
      case SectorSettingsSectionState.incomplete:
        return (
          color: tokens.warning,
          icon: Icons.priority_high_rounded,
          label: '입력 필요',
        );
      case SectorSettingsSectionState.error:
        return (
          color: tokens.danger,
          icon: Icons.error_rounded,
          label: '오류',
        );
    }
  }

  Widget _buildSectionStatusTrailing(
    BuildContext context, {
    required SecondarySectorWorkspaceState workspace,
  }) {
    final state = workspace.stateFor(SectorSettingsSection.identity);
    final visual = _sectionStatusVisual(context, state);
    return Semantics(
      label: '섹터 기본 정보, ${visual.label}',
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
          key: ValueKey<SectorSettingsSectionState>(state),
          size: 17,
          color: visual.color,
        ),
      ),
    );
  }

  Widget _buildSummarySection(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final workspace = context.watch<SecondarySectorWorkspaceState>();
    final active = workspace.activeSettingsSection ==
            SectorSettingsSection.identity ||
        _editingSection == SectorSettingsSection.identity;
    final summary = _nameOk ? _nameController.text.trim() : '섹터명 입력 필요';

    return KeyedSubtree(
      key: _identityKey,
      child: Semantics(
        button: true,
        label: '섹터 기본 정보, $summary',
        child: OpsDockSelectableRowSurface(
          selected: active,
          selectionColor: tokens.accent,
          selectedContainer: tokens.accentContainer,
          onTap: () => unawaited(
            _openSectionEditor(SectorSettingsSection.identity),
          ),
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
                            '섹터 기본 정보',
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
                        key: ValueKey<String>('sector_identity_$summary'),
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
                turns: _editingSection == SectorSettingsSection.identity
                    ? .25
                    : 0,
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
    final workspace = context.watch<SecondarySectorWorkspaceState>();
    final incompleteCount = workspace.incompleteSectionCount;
    final hasSaveError = _saveError != null && _saveError!.trim().isNotEmpty;
    final label = hasSaveError
        ? '저장 확인 필요'
        : incompleteCount == 0
            ? '입력 확인 완료'
            : '입력 확인 필요';
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnimatedSize(
            duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
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
          _buildSummarySection(context),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final key = _saving
        ? 'sector_settings_footer_saving'
        : isEditMode
            ? 'sector_settings_footer_edit'
            : 'sector_settings_footer_create';
    return OpsDockContextFooter(
      key: ValueKey<String>(key),
      children: [
        Expanded(
          child: CommonButton(
            label: '섹터 목록',
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
            label: isEditMode ? '수정 완료' : '등록 완료',
            icon: isEditMode
                ? Icons.save_rounded
                : Icons.add_location_alt_rounded,
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
    context.watch<SecondarySectorWorkspaceState>();

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
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: _buildContentSurface(context),
                  ),
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
