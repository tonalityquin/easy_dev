import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../../app/utils/snackbar_helper.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_origin_morph_dialog.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/secondary/application/secondary_location_workspace_state.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../dev/application/area_state.dart';
import '../../applications/location_state.dart';
import '../../domain/models/location_model.dart';
import 'location_plain_section_editor_dialog.dart';
import 'models/location_plain_settings_draft.dart';

class LocationPlainSettingWorkspace extends StatefulWidget {
  const LocationPlainSettingWorkspace({
    super.key,
    required this.initialLocation,
  });

  final LocationModel? initialLocation;

  @override
  State<LocationPlainSettingWorkspace> createState() =>
      _LocationPlainSettingWorkspaceState();
}

class _LocationPlainSettingWorkspaceState
    extends State<LocationPlainSettingWorkspace> {
  final GlobalKey _identityKey = GlobalKey();
  final GlobalKey _capacityKey = GlobalKey();
  late LocationPlainSettingsDraft _draft;
  LocationModel? _initialLocationSnapshot;
  SecondaryLocationWorkspaceState? _workspace;
  LocationPlainSettingsSection? _editingSection;
  String? _saveError;
  bool _saving = false;
  bool _validationSubmitted = false;
  bool _reduceMotion = false;
  int _handledNavigationRequestId = 0;

  bool get isEditMode => _initialLocationSnapshot != null;

  @override
  void initState() {
    super.initState();
    _initialLocationSnapshot = widget.initialLocation;
    _draft = _initialDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSectionStates(source: 'initial_plain_form_state');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _workspace ??= context.read<SecondaryLocationWorkspaceState>();
  }

  @override
  void didUpdateWidget(covariant LocationPlainSettingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialLocation?.id == widget.initialLocation?.id) return;
    if (widget.initialLocation == null &&
        _saving &&
        _initialLocationSnapshot != null) {
      return;
    }
    _initialLocationSnapshot = widget.initialLocation;
    setState(() {
      _draft = _initialDraft();
      _saveError = null;
      _validationSubmitted = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSectionStates(source: 'plain_edit_target_changed');
    });
  }

  LocationPlainSettingsDraft _initialDraft() {
    final initial = _initialLocationSnapshot;
    return LocationPlainSettingsDraft(
      name: initial?.locationName.trim() ?? '',
      capacity: initial?.capacity ?? 0,
    );
  }

  String get _nameError {
    final value = _draft.name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) return '구역명을 입력해 주세요.';
    if (value.length > 40) return '구역명은 40자 이하로 입력해 주세요.';
    return '';
  }

  String get _capacityError {
    if (_draft.capacity < 0) return '수용 가능 차량 수는 0 이상이어야 합니다.';
    if (_draft.capacity > 9999) {
      return '수용 가능 차량 수는 9999 이하로 입력해 주세요.';
    }
    return '';
  }

  LocationPlainSettingsSectionState _sectionState(
    LocationPlainSettingsSection section,
  ) {
    final error = switch (section) {
      LocationPlainSettingsSection.identity => _nameError,
      LocationPlainSettingsSection.capacity => _capacityError,
    };
    if (error.isEmpty) return LocationPlainSettingsSectionState.complete;
    return _validationSubmitted
        ? LocationPlainSettingsSectionState.error
        : LocationPlainSettingsSectionState.incomplete;
  }

  Map<LocationPlainSettingsSection, LocationPlainSettingsSectionState>
      _allSectionStates() {
    return <LocationPlainSettingsSection, LocationPlainSettingsSectionState>{
      for (final section in LocationPlainSettingsSection.values)
        section: _sectionState(section),
    };
  }

  void _syncSectionStates({required String source}) {
    _workspace?.updatePlainSectionStates(_allSectionStates(), source: source);
  }

  void _applyDraft(
    LocationPlainSettingsSection section,
    LocationPlainSettingsDraft draft,
  ) {
    setState(() {
      _draft = draft.detached();
      _saveError = null;
    });
    _workspace?.setSettingsDirty(
      true,
      source: 'plain_editor_apply_${section.name}',
    );
    _workspace?.selectPlainSettingsSection(
      section,
      source: 'plain_editor_apply',
    );
    _syncSectionStates(source: 'plain_editor_apply_${section.name}');
  }

  String _sectionTitle(LocationPlainSettingsSection section) {
    switch (section) {
      case LocationPlainSettingsSection.identity:
        return '텍스트형 구역 기본 정보';
      case LocationPlainSettingsSection.capacity:
        return '수용 가능 차량 수';
    }
  }

  GlobalKey _keyFor(LocationPlainSettingsSection section) {
    switch (section) {
      case LocationPlainSettingsSection.identity:
        return _identityKey;
      case LocationPlainSettingsSection.capacity:
        return _capacityKey;
    }
  }

  Rect? _sourceRectFor(LocationPlainSettingsSection section) {
    final sectionContext = _keyFor(section).currentContext;
    final box = sectionContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  Future<void> _scrollToSection(LocationPlainSettingsSection section) async {
    final sectionContext = _keyFor(section).currentContext;
    if (sectionContext == null) return;
    _workspace?.log('plain_settings_scroll_requested section=${section.name}');
    await Scrollable.ensureVisible(
      sectionContext,
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      alignment: 0.02,
    );
  }

  void _scheduleNavigationRequest(SecondaryLocationWorkspaceState workspace) {
    final requestId = workspace.plainSettingsNavigationRequestId;
    if (requestId == _handledNavigationRequestId) return;
    _handledNavigationRequestId = requestId;
    final target = workspace.activePlainSettingsSection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_scrollToSection(target));
    });
  }

  Future<void> _openSectionEditor(LocationPlainSettingsSection section) async {
    if (_saving || _editingSection != null) return;
    _workspace?.selectPlainSettingsSection(
      section,
      source: 'plain_summary_row_tap',
    );
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final sourceRect = _sourceRectFor(section);
    if (sourceRect == null) {
      _workspace?.log(
        'plain_settings_editor_open_failed section=${section.name} reason=no_source_rect',
      );
      return;
    }
    setState(() => _editingSection = section);
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final trace = await DeveloperOperationTrace.start(
      context: rootContext,
      title: '${_sectionTitle(section)} 편집',
      initialMessage: '텍스트형 구역 설정 편집을 시작합니다: section=${section.name}',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 편집 Dialog의 버그 아이콘에서 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 텍스트형 구역 편집 동작을 콘솔에 기록합니다.',
      showDialogImmediately: false,
    );
    try {
      trace.log(
        '원본 row bounds 확보: width=${sourceRect.width.toStringAsFixed(1)}, height=${sourceRect.height.toStringAsFixed(1)}',
      );
      final applied = await showCommonOriginMorphDialog<bool>(
        context: context,
        sourceRect: sourceRect,
        targetSize: section == LocationPlainSettingsSection.identity
            ? const Size(480, 330)
            : const Size(460, 310),
        barrierDismissible: false,
        barrierLabel: '${_sectionTitle(section)} 편집',
        builder: (_) => LocationPlainSectionEditorDialog(
          section: section,
          initialDraft: _draft.detached(),
          trace: trace,
          onApply: (draft) => _applyDraft(section, draft),
        ),
      );
      trace.log(
        '텍스트형 구역 편집 Dialog 종료 section=${section.name} applied=${applied == true}',
      );
      _workspace?.log(
        'plain_settings_editor_closed section=${section.name} applied=${applied == true}',
      );
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
    _syncSectionStates(source: 'plain_submit_validation');

    if (_nameError.isNotEmpty) {
      _workspace?.requestPlainSettingsSection(
        LocationPlainSettingsSection.identity,
        source: 'plain_submit_validation_failed',
      );
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      await _openSectionEditor(LocationPlainSettingsSection.identity);
      return;
    }
    if (_capacityError.isNotEmpty) {
      _workspace?.requestPlainSettingsSection(
        LocationPlainSettingsSection.capacity,
        source: 'plain_submit_validation_failed',
      );
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      await _openSectionEditor(LocationPlainSettingsSection.capacity);
      return;
    }

    final workspace = _workspace;
    final state = context.read<LocationState>();
    final area = context.read<AreaState>().currentArea.trim();
    final initial = _initialLocationSnapshot;
    final operationTitle = isEditMode ? '텍스트형 구역 수정' : '텍스트형 구역 생성';

    setState(() => _saving = true);
    workspace?.setSettingsSaving(true, source: 'plain_submit_started');
    workspace?.log(
      'plain_settings_submit_started mode=${isEditMode ? 'edit' : 'create'} nameLength=${_draft.name.length} capacity=${_draft.capacity}',
    );

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: operationTitle,
      initialMessage: '$operationTitle 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 텍스트형 구역 저장 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 텍스트형 구역 저장 로그를 콘솔에 기록합니다.',
    );

    String? writeError;
    try {
      if (area.isEmpty) throw StateError('현재 지역 정보가 없습니다.');
      trace.log(
        '텍스트형 구역 draft 검증 통과 mode=${isEditMode ? 'edit' : 'create'} areaReady=true nameLength=${_draft.name.length} capacity=${_draft.capacity}',
        progress: .28,
      );
      final saved = initial == null
          ? await state.createPlainTextLocation(
              name: _draft.name,
              capacity: _draft.capacity,
              area: area,
              onError: (message) {
                writeError = message;
                trace.log('저장 검증 메시지: $message');
              },
            )
          : await state.updatePlainTextLocation(
              id: initial.id,
              name: _draft.name,
              capacity: _draft.capacity,
              area: area,
              onError: (message) {
                writeError = message;
                trace.log('저장 검증 메시지: $message');
              },
            );
      if (!saved) {
        throw StateError(writeError ?? '$operationTitle에 실패했습니다.');
      }
      trace.log('Firestore 및 지역 캐시 동기화 완료', progress: .88);
      await trace.succeed('$operationTitle 완료');
      if (!mounted) return;
      workspace?.setSettingsDirty(false, source: 'plain_submit_success');
      showSuccessSnackbar(
        context,
        isEditMode
            ? '텍스트형 구역 수정이 완료되었습니다.'
            : '텍스트형 구역 생성이 완료되었습니다.',
        useCommonUi: true,
      );
      workspace?.returnToManagement(source: 'plain_submit_success');
    } catch (error, stackTrace) {
      final message =
          writeError ?? error.toString().replaceFirst('Bad state: ', '');
      await trace.fail(
        '$operationTitle 실패: 입력 내용은 유지됩니다.',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() => _saveError = message);
      showFailedSnackbar(
        context,
        '$message 입력 내용은 유지됩니다.',
        useCommonUi: true,
      );
      workspace?.log('plain_settings_submit_failed error=$message');
    } finally {
      if (mounted) setState(() => _saving = false);
      workspace?.setSettingsSaving(false, source: 'plain_submit_finished');
    }
  }

  void _returnToManagement() {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    _workspace?.returnToManagement(source: 'plain_settings_footer_back');
  }

  ({Color color, IconData icon, String label}) _statusVisual(
    BuildContext context,
    LocationPlainSettingsSectionState state,
  ) {
    final tokens = CommonUiTheme.of(context);
    switch (state) {
      case LocationPlainSettingsSectionState.complete:
        return (color: tokens.success, icon: Icons.check_rounded, label: '완료');
      case LocationPlainSettingsSectionState.incomplete:
        return (
          color: tokens.warning,
          icon: Icons.priority_high_rounded,
          label: '확인 필요',
        );
      case LocationPlainSettingsSectionState.error:
        return (
          color: tokens.danger,
          icon: Icons.error_outline_rounded,
          label: '오류',
        );
    }
  }

  Widget _statusIcon(
    BuildContext context,
    LocationPlainSettingsSectionState state,
  ) {
    final visual = _statusVisual(context, state);
    return AnimatedSwitcher(
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
      switchInCurve: CommonUiMotion.enter,
      switchOutCurve: CommonUiMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: Icon(
        visual.icon,
        key: ValueKey<LocationPlainSettingsSectionState>(state),
        size: 17,
        color: visual.color,
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context, {
    required GlobalKey rowKey,
    required LocationPlainSettingsSection section,
    required IconData icon,
    required String title,
    required String summary,
  }) {
    final tokens = CommonUiTheme.of(context);
    final workspace = context.watch<SecondaryLocationWorkspaceState>();
    final active = workspace.activePlainSettingsSection == section ||
        _editingSection == section;
    final state = _sectionState(section);
    return KeyedSubtree(
      key: rowKey,
      child: OpsDockSelectableRowSurface(
        selected: active,
        selectionColor: tokens.accent,
        selectedContainer: tokens.accentContainer,
        onTap: () => unawaited(_openSectionEditor(section)),
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 19,
              color: active ? tokens.accent : tokens.iconPrimary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 3),
                  AnimatedSwitcher(
                    duration:
                        _reduceMotion ? Duration.zero : CommonUiMotion.selection,
                    switchInCurve: CommonUiMotion.enter,
                    switchOutCurve: CommonUiMotion.exit,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(.025, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: Text(
                      summary,
                      key: ValueKey<String>(summary),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            height: 1.3,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _statusIcon(context, state),
            const SizedBox(width: 4),
            Icon(
              Icons.chevron_right_rounded,
              size: 19,
              color: tokens.iconSecondary,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusStrip(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final states = _allSectionStates();
    final incomplete = states.values.where((state) {
      return state == LocationPlainSettingsSectionState.incomplete ||
          state == LocationPlainSettingsSectionState.error;
    }).length;
    final allComplete = incomplete == 0;
    return Row(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
            child: Text(
              allComplete ? '설정 확인 완료' : '확인 필요 $incomplete개',
              key: ValueKey<int>(incomplete),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: allComplete ? tokens.success : tokens.warning,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(scale: animation, child: child),
          ),
          child: Icon(
            allComplete
                ? Icons.check_circle_rounded
                : Icons.error_outline_rounded,
            key: ValueKey<bool>(allComplete),
            size: 18,
            color: allComplete ? tokens.success : tokens.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildContentSurface(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final identitySummary = _nameError.isEmpty ? _draft.name : '구역명 입력 필요';
    final capacitySummary = '공간 ${_draft.capacity}대';
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
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                        color: tokens.dangerContainer.withOpacity(.42),
                        child: Text(
                          _saveError!,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: tokens.danger,
                                fontWeight: FontWeight.w700,
                                height: 1.35,
                              ),
                        ),
                      ),
                      Container(height: 1, color: tokens.borderSubtle),
                    ],
                  ),
          ),
          _summaryRow(
            context,
            rowKey: _identityKey,
            section: LocationPlainSettingsSection.identity,
            icon: Icons.text_fields_rounded,
            title: '구역 기본 정보',
            summary: identitySummary,
          ),
          Container(height: 1, color: tokens.borderSubtle),
          _summaryRow(
            context,
            rowKey: _capacityKey,
            section: LocationPlainSettingsSection.capacity,
            icon: Icons.local_parking_rounded,
            title: '수용 가능 차량 수',
            summary: capacitySummary,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final key = _saving
        ? 'location_plain_footer_saving'
        : isEditMode
            ? 'location_plain_footer_edit'
            : 'location_plain_footer_create';
    return OpsDockContextFooter(
      key: ValueKey<String>(key),
      children: [
        Expanded(
          child: CommonButton(
            label: '구역 관리',
            icon: Icons.arrow_back_rounded,
            onPressed: _saving ? null : _returnToManagement,
            variant: CommonButtonVariant.secondary,
            haptic: CommonHaptic.selection,
            minHeight: 42,
            expand: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CommonButton(
            label: isEditMode ? '수정 완료' : '생성 완료',
            icon: isEditMode ? Icons.save_rounded : Icons.add_rounded,
            onPressed: _saving ? null : _handleSave,
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
    final tokens = CommonUiTheme.of(context);
    final workspace = context.watch<SecondaryLocationWorkspaceState>();
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
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  child: _buildContentSurface(context),
                ),
              ),
              OpsDockContextFooterTransition(child: _buildFooter()),
            ],
          ),
          OpsDockLoadingOverlay(loading: _saving),
        ],
      ),
    );
  }
}
