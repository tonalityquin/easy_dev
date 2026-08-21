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
import '../../../../shared/secondary/widgets/ops_console_dialogs.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';
import '../../../dev/application/area_state.dart';
import '../../applications/location_state.dart';
import '../../domain/models/location_model.dart';
import '../../domain/models/parking_grid_model.dart';
import 'location_parent_section_editor_dialog.dart';
import 'location_parent_tool_editor_dialog.dart';
import 'location_parent_tool_spec.dart';
import 'models/location_parent_settings_draft.dart';
import 'widgets/parking_grid_preview.dart';

class LocationParentSettingWorkspace extends StatefulWidget {
  const LocationParentSettingWorkspace({
    super.key,
    required this.initialParent,
  });

  final LocationModel? initialParent;

  @override
  State<LocationParentSettingWorkspace> createState() =>
      _LocationParentSettingWorkspaceState();
}

class _LocationParentSettingWorkspaceState
    extends State<LocationParentSettingWorkspace> {
  final GlobalKey _identityKey = GlobalKey();
  final GlobalKey _sizeKey = GlobalKey();
  final GlobalKey _layoutKey = GlobalKey();
  final Map<LocationParentToolCategory, GlobalKey> _layoutActionKeys =
      <LocationParentToolCategory, GlobalKey>{
    for (final category in LocationParentToolCategory.values)
      category: GlobalKey(),
  };
  late LocationParentSettingsDraft _draft;
  LocationModel? _initialParentSnapshot;
  SecondaryLocationWorkspaceState? _workspace;
  LocationParentSettingsSection? _editingSection;
  LocationParentToolCategory? _editingCategory;
  String? _saveError;
  bool _saving = false;
  bool _validationSubmitted = false;
  bool _reduceMotion = false;
  int _handledNavigationRequestId = 0;

  bool get isEditMode => _initialParentSnapshot != null;

  @override
  void initState() {
    super.initState();
    _initialParentSnapshot = widget.initialParent;
    _draft = _initialDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSectionStates(source: 'initial_parent_form_state');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _workspace ??= context.read<SecondaryLocationWorkspaceState>();
  }

  @override
  void didUpdateWidget(covariant LocationParentSettingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialParent?.id == widget.initialParent?.id) return;
    if (widget.initialParent == null && _saving && _initialParentSnapshot != null) {
      return;
    }
    _initialParentSnapshot = widget.initialParent;
    setState(() {
      _draft = _initialDraft();
      _saveError = null;
      _validationSubmitted = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSectionStates(source: 'parent_edit_target_changed');
    });
  }

  LocationParentSettingsDraft _initialDraft() {
    final parent = _initialParentSnapshot;
    final grid = parent?.parkingGrid;
    if (grid != null) {
      return LocationParentSettingsDraft(
        name: parent?.locationName.trim() ?? '',
        parkingGrid: LocationParentSettingsDraft.detachedParkingGrid(grid),
      );
    }
    return LocationParentSettingsDraft(
      name: '',
      parkingGrid: ParkingGridModel.fromEnumCells(
        rows: 6,
        cols: 6,
        cells: List<ParkingGridCellType>.filled(
          36,
          ParkingGridCellType.empty,
          growable: false,
        ),
      ),
    );
  }

  String get _nameError {
    final value = _draft.name.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (value.isEmpty) return '부모구역명을 입력해 주세요.';
    if (value.length > 40) return '부모구역명은 40자 이하로 입력해 주세요.';
    return '';
  }

  String get _sizeError {
    final grid = _draft.parkingGrid;
    if (grid.rows < 2 || grid.rows > 20 || grid.cols < 2 || grid.cols > 20) {
      return '부모구역 크기는 행과 열 각각 2~20 범위여야 합니다.';
    }
    if (grid.cells.length != grid.rows * grid.cols) {
      return '부모구역 그리드 데이터가 올바르지 않습니다.';
    }
    return '';
  }

  LocationParentSettingsSectionState _sectionState(
    LocationParentSettingsSection section,
  ) {
    switch (section) {
      case LocationParentSettingsSection.identity:
        if (_nameError.isEmpty) return LocationParentSettingsSectionState.complete;
        return _validationSubmitted
            ? LocationParentSettingsSectionState.error
            : LocationParentSettingsSectionState.incomplete;
      case LocationParentSettingsSection.size:
        if (_sizeError.isEmpty) return LocationParentSettingsSectionState.complete;
        return _validationSubmitted
            ? LocationParentSettingsSectionState.error
            : LocationParentSettingsSectionState.incomplete;
      case LocationParentSettingsSection.layout:
        return LocationParentSettingsSectionState.complete;
    }
  }

  Map<LocationParentSettingsSection, LocationParentSettingsSectionState>
      _allSectionStates() {
    return <LocationParentSettingsSection, LocationParentSettingsSectionState>{
      for (final section in LocationParentSettingsSection.values)
        section: _sectionState(section),
    };
  }

  void _syncSectionStates({required String source}) {
    _workspace?.updateSectionStates(_allSectionStates(), source: source);
  }

  void _applyDraft(
    LocationParentSettingsSection section,
    LocationParentSettingsDraft draft,
  ) {
    setState(() {
      _draft = draft.detached();
      _saveError = null;
    });
    _workspace?.setSettingsDirty(true, source: 'parent_editor_apply_${section.name}');
    _workspace?.selectSettingsSection(section, source: 'parent_editor_apply');
    _syncSectionStates(source: 'parent_editor_apply_${section.name}');
  }

  String _sectionTitle(LocationParentSettingsSection section) {
    switch (section) {
      case LocationParentSettingsSection.identity:
        return '부모구역 기본 정보';
      case LocationParentSettingsSection.size:
        return '부모구역 크기';
      case LocationParentSettingsSection.layout:
        return '도면 작업';
    }
  }

  GlobalKey _keyFor(LocationParentSettingsSection section) {
    switch (section) {
      case LocationParentSettingsSection.identity:
        return _identityKey;
      case LocationParentSettingsSection.size:
        return _sizeKey;
      case LocationParentSettingsSection.layout:
        return _layoutKey;
    }
  }

  Rect? _sourceRectFor(LocationParentSettingsSection section) {
    final sectionContext = _keyFor(section).currentContext;
    final box = sectionContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  Future<void> _scrollToSection(LocationParentSettingsSection section) async {
    final sectionContext = _keyFor(section).currentContext;
    if (sectionContext == null) return;
    _workspace?.log('parent_settings_scroll_requested section=${section.name}');
    await Scrollable.ensureVisible(
      sectionContext,
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      alignment: 0.02,
    );
  }

  void _scheduleNavigationRequest(SecondaryLocationWorkspaceState workspace) {
    final requestId = workspace.settingsNavigationRequestId;
    if (requestId == _handledNavigationRequestId) return;
    _handledNavigationRequestId = requestId;
    final target = workspace.activeSettingsSection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_scrollToSection(target));
    });
  }

  Future<void> _openSectionEditor(LocationParentSettingsSection section) async {
    if (_saving || _editingSection != null) return;
    if (section == LocationParentSettingsSection.layout) {
      _workspace?.requestSettingsSection(
        LocationParentSettingsSection.layout,
        source: 'parent_layout_section_focus',
      );
      return;
    }
    _workspace?.selectSettingsSection(section, source: 'parent_summary_row_tap');
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final sourceRect = _sourceRectFor(section);
    if (sourceRect == null) {
      _workspace?.log(
        'parent_settings_editor_open_failed section=${section.name} reason=no_source_rect',
      );
      return;
    }
    setState(() => _editingSection = section);
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final trace = await DeveloperOperationTrace.start(
      context: rootContext,
      title: '${_sectionTitle(section)} 편집',
      initialMessage: '부모구역 설정 편집을 시작합니다: section=${section.name}',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 편집 Dialog의 버그 아이콘에서 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 부모구역 편집 동작을 콘솔에 기록합니다.',
      showDialogImmediately: false,
    );
    try {
      trace.log(
        '원본 row bounds 확보: width=${sourceRect.width.toStringAsFixed(1)}, height=${sourceRect.height.toStringAsFixed(1)}',
      );
      final applied = await showCommonOriginMorphDialog<bool>(
        context: context,
        sourceRect: sourceRect,
        targetSize: section == LocationParentSettingsSection.identity
            ? const Size(500, 360)
            : const Size(620, 680),
        barrierDismissible: false,
        barrierLabel: '${_sectionTitle(section)} 편집',
        builder: (_) => LocationParentSectionEditorDialog(
          section: section,
          initialDraft: _draft.detached(),
          editMode: isEditMode,
          trace: trace,
          onApply: (draft) => _applyDraft(section, draft),
        ),
      );
      trace.log(
        '부모구역 section Dialog 종료 section=${section.name} applied=${applied == true}',
      );
      _workspace?.log(
        'parent_settings_editor_closed section=${section.name}',
      );
    } finally {
      if (mounted && _editingSection == section) {
        setState(() => _editingSection = null);
      }
    }
  }

  Rect? _sourceRectForLayoutCategory(LocationParentToolCategory category) {
    final buttonContext = _layoutActionKeys[category]?.currentContext;
    final box = buttonContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  Future<void> _openLayoutCategory(
    LocationParentToolCategory category,
  ) async {
    if (_saving || _editingSection != null) return;
    _workspace?.selectSettingsSection(
      LocationParentSettingsSection.layout,
      source: 'parent_layout_category_tap',
    );
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final sourceRect = _sourceRectForLayoutCategory(category);
    if (sourceRect == null) {
      _workspace?.log(
        'parent_layout_category_open_failed category=${category.name} reason=no_source_rect',
      );
      return;
    }
    setState(() {
      _editingSection = LocationParentSettingsSection.layout;
      _editingCategory = category;
    });
    final label = locationParentToolCategoryLabel(category);
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final trace = await DeveloperOperationTrace.start(
      context: rootContext,
      title: '$label 작업',
      initialMessage: '부모구역 $label 도면 작업을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 작업 Dialog의 버그 아이콘에서 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 도면 작업을 콘솔에 기록합니다.',
      showDialogImmediately: false,
    );
    try {
      trace.log(
        '원본 action bounds 확보 category=${category.name} width=${sourceRect.width.toStringAsFixed(1)} height=${sourceRect.height.toStringAsFixed(1)}',
      );
      final applied = await showCommonOriginMorphDialog<bool>(
        context: context,
        sourceRect: sourceRect,
        targetSize: const Size(860, 780),
        barrierDismissible: false,
        barrierLabel: '$label 작업',
        builder: (_) => LocationParentToolEditorDialog(
          category: category,
          initialDraft: _draft.detached(),
          trace: trace,
          onApply: (draft) => _applyDraft(
            LocationParentSettingsSection.layout,
            draft,
          ),
        ),
      );
      trace.log(
        '부모구역 category 작업 종료 category=${category.name} applied=${applied == true}',
      );
      _workspace?.log(
        'parent_layout_category_closed category=${category.name} applied=${applied == true}',
      );
    } finally {
      if (mounted &&
          _editingSection == LocationParentSettingsSection.layout) {
        setState(() {
          _editingSection = null;
          _editingCategory = null;
        });
      }
    }
  }

  Future<bool> _confirmParentGridUpdate() {
    return showOpsConfirmDialog(
      context: context,
      title: '부모구역 수정 저장',
      message: '부모 도면을 저장하면 하위 자식 구역의 슬롯 정보가 재계산될 수 있습니다.',
      confirmLabel: '저장',
      icon: Icons.warning_amber_rounded,
      destructive: true,
    );
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _validationSubmitted = true;
      _saveError = null;
    });
    _syncSectionStates(source: 'parent_submit_validation');

    if (_nameError.isNotEmpty) {
      _workspace?.requestSettingsSection(
        LocationParentSettingsSection.identity,
        source: 'parent_submit_validation_failed',
      );
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      await _openSectionEditor(LocationParentSettingsSection.identity);
      return;
    }
    if (_sizeError.isNotEmpty) {
      _workspace?.requestSettingsSection(
        LocationParentSettingsSection.size,
        source: 'parent_submit_validation_failed',
      );
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      await _openSectionEditor(LocationParentSettingsSection.size);
      return;
    }
    if (isEditMode) {
      final confirmed = await _confirmParentGridUpdate();
      if (!confirmed || !mounted) return;
    }

    final workspace = _workspace;
    final state = context.read<LocationState>();
    final area = context.read<AreaState>().currentArea.trim();
    final parent = _initialParentSnapshot;
    final operationTitle = isEditMode ? '부모구역 수정' : '부모구역 생성';

    setState(() => _saving = true);
    workspace?.setSettingsSaving(true, source: 'parent_submit_started');
    workspace?.log(
      'parent_settings_submit_started mode=${isEditMode ? 'edit' : 'create'} rows=${_draft.parkingGrid.rows} cols=${_draft.parkingGrid.cols}',
    );

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: operationTitle,
      initialMessage: '$operationTitle 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 부모구역 저장 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 부모구역 저장 로그를 콘솔에 기록합니다.',
    );

    String? writeError;
    try {
      if (area.isEmpty) throw StateError('현재 지역 정보가 없습니다.');
      trace.log(
        '부모구역 draft 검증 통과 mode=${isEditMode ? 'edit' : 'create'} areaReady=true nameLength=${_draft.name.length} grid=${_draft.parkingGrid.rows}x${_draft.parkingGrid.cols}',
        progress: .24,
      );
      trace.log(
        '도면 저장 준비 parking=${_draft.parkingGrid.parkingAreas.length} entrance=${_draft.parkingGrid.entranceRects.length} exit=${_draft.parkingGrid.exitRects.length} tower=${_draft.parkingGrid.towerRects.length}',
        progress: .48,
      );
      final saved = parent == null
          ? await state.createCompositeParent(
              _draft.name,
              area,
              parkingGrid: _draft.parkingGrid,
              onError: (message) {
                writeError = message;
                trace.log('저장 검증 메시지: $message');
              },
            )
          : await state.updateCompositeParent(
              parentId: parent.id,
              area: area,
              parkingGrid: _draft.parkingGrid,
              onError: (message) {
                writeError = message;
                trace.log('저장 검증 메시지: $message');
              },
            );
      if (!saved) {
        throw StateError(writeError ?? '$operationTitle에 실패했습니다.');
      }
      trace.log('Firestore 동기화 완료', progress: .86);
      await trace.succeed('$operationTitle 완료');
      if (!mounted) return;
      workspace?.setSettingsDirty(false, source: 'parent_submit_success');
      showSuccessSnackbar(
        context,
        isEditMode ? '부모구역 수정이 완료되었습니다.' : '부모구역 생성이 완료되었습니다.',
        useCommonUi: true,
      );
      workspace?.returnToManagement(source: 'parent_submit_success');
    } catch (error, stackTrace) {
      final message = writeError ?? error.toString().replaceFirst('Bad state: ', '');
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
      workspace?.log('parent_settings_submit_failed error=$message');
    } finally {
      if (mounted) setState(() => _saving = false);
      workspace?.setSettingsSaving(false, source: 'parent_submit_finished');
    }
  }

  void _returnToManagement() {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    _workspace?.returnToManagement(source: 'parent_settings_footer_back');
  }

  ({Color color, IconData icon, String label}) _statusVisual(
    BuildContext context,
    LocationParentSettingsSectionState state,
  ) {
    final tokens = CommonUiTheme.of(context);
    switch (state) {
      case LocationParentSettingsSectionState.complete:
        return (color: tokens.success, icon: Icons.check_rounded, label: '완료');
      case LocationParentSettingsSectionState.incomplete:
        return (
          color: tokens.warning,
          icon: Icons.priority_high_rounded,
          label: '확인 필요',
        );
      case LocationParentSettingsSectionState.error:
        return (
          color: tokens.danger,
          icon: Icons.error_outline_rounded,
          label: '오류',
        );
    }
  }

  Widget _statusIcon(
    BuildContext context,
    LocationParentSettingsSectionState state,
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
        key: ValueKey<LocationParentSettingsSectionState>(state),
        size: 17,
        color: visual.color,
      ),
    );
  }

  Widget _summaryRow(
    BuildContext context, {
    required GlobalKey rowKey,
    required LocationParentSettingsSection section,
    required IconData icon,
    required String title,
    required String summary,
  }) {
    final tokens = CommonUiTheme.of(context);
    final workspace = context.watch<SecondaryLocationWorkspaceState>();
    final active = workspace.activeSettingsSection == section ||
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
                    duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
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
            Icon(Icons.chevron_right_rounded, size: 19, color: tokens.iconSecondary),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusStrip(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final states = _allSectionStates();
    final incomplete = states.values.where((state) {
      return state == LocationParentSettingsSectionState.incomplete ||
          state == LocationParentSettingsSectionState.error;
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
            allComplete ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            key: ValueKey<bool>(allComplete),
            size: 18,
            color: allComplete ? tokens.success : tokens.warning,
          ),
        ),
      ],
    );
  }

  String _layoutCategoryDetail(LocationParentToolCategory category) {
    switch (category) {
      case LocationParentToolCategory.structure:
        return '벽 · 도로 · 기둥';
      case LocationParentToolCategory.parking:
        return '주차면 유형 및 배치';
      case LocationParentToolCategory.facility:
        return '입구 · 출구 · 주차 타워';
      case LocationParentToolCategory.cleanup:
        return '셀 · 주차면 · 시설 삭제';
    }
  }

  Widget _layoutCategoryButton(
    BuildContext context,
    LocationParentToolCategory category,
  ) {
    final active = _editingCategory == category;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommonButton(
          key: _layoutActionKeys[category],
          label: locationParentToolCategoryLabel(category),
          icon: locationParentToolCategoryIcon(category),
          onPressed: _saving
              ? null
              : () => unawaited(_openLayoutCategory(category)),
          variant: CommonButtonVariant.secondary,
          selected: active,
          haptic: CommonHaptic.selection,
          minHeight: 42,
          expand: true,
        ),
        const SizedBox(height: 4),
        Text(
          _layoutCategoryDetail(category),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: CommonUiTheme.of(context).textSecondary,
                fontWeight: FontWeight.w700,
              ),
        ),
      ],
    );
  }

  Widget _buildLayoutWorkspace(
    BuildContext context,
    ParkingGridModel grid,
  ) {
    final tokens = CommonUiTheme.of(context);
    final wallCount =
        grid.cells.where((cell) => cell == ParkingGridCellType.wall).length;
    final roadCount =
        grid.cells.where((cell) => cell == ParkingGridCellType.road).length;
    final pillarCount =
        grid.cells.where((cell) => cell == ParkingGridCellType.pillar).length;
    final signature = grid.toJson().toString();
    return KeyedSubtree(
      key: _layoutKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.map_outlined,
                  size: 18,
                  color: tokens.iconSecondary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '도면 현황',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                        ),
                  ),
                ),
                Text(
                  '${grid.rows} × ${grid.cols}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            AnimatedSwitcher(
              duration:
                  _reduceMotion ? Duration.zero : CommonUiMotion.selection,
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: .985, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: Container(
                key: ValueKey<String>(signature),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: tokens.canvas,
                  border: Border.all(color: tokens.borderSubtle),
                  borderRadius:
                      BorderRadius.circular(CommonUiShapes.control),
                ),
                child: ParkingGridPreview(
                  grid: grid,
                  maxExtent: 300,
                  showLegend: false,
                  showParkingAreaLabels: false,
                  showChildRegions: false,
                  showChildRegionLabels: false,
                  showAllChildRegionLabels: false,
                  showChildSlotNumbers: false,
                ),
              ),
            ),
            const SizedBox(height: 8),
            AnimatedSwitcher(
              duration:
                  _reduceMotion ? Duration.zero : CommonUiMotion.selection,
              child: Text(
                '벽 $wallCount · 도로 $roadCount · 기둥 $pillarCount · 주차면 ${grid.parkingAreas.length} · 입구 ${grid.entranceRects.length} · 출구 ${grid.exitRects.length} · 타워 ${grid.towerRects.length}',
                key: ValueKey<String>(
                  '$wallCount-$roadCount-$pillarCount-${grid.parkingAreas.length}-${grid.entranceRects.length}-${grid.exitRects.length}-${grid.towerRects.length}',
                ),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.35,
                    ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Icon(
                  Icons.architecture_rounded,
                  size: 18,
                  color: tokens.iconSecondary,
                ),
                const SizedBox(width: 8),
                Text(
                  '도면 작업',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _layoutCategoryButton(
                    context,
                    LocationParentToolCategory.structure,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _layoutCategoryButton(
                    context,
                    LocationParentToolCategory.parking,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _layoutCategoryButton(
                    context,
                    LocationParentToolCategory.facility,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _layoutCategoryButton(
                    context,
                    LocationParentToolCategory.cleanup,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContentSurface(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final grid = _draft.parkingGrid;
    final identitySummary =
        _nameError.isEmpty ? _draft.name : '부모구역명 입력 필요';
    final sizeSummary = '${grid.rows} × ${grid.cols}';

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
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
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
            section: LocationParentSettingsSection.identity,
            icon: Icons.location_on_rounded,
            title: '부모구역 기본 정보',
            summary: identitySummary,
          ),
          Container(height: 1, color: tokens.borderSubtle),
          _summaryRow(
            context,
            rowKey: _sizeKey,
            section: LocationParentSettingsSection.size,
            icon: Icons.aspect_ratio_rounded,
            title: '부모구역 크기',
            summary: sizeSummary,
          ),
          Container(height: 1, color: tokens.borderSubtle),
          _buildLayoutWorkspace(context, grid),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final key = _saving
        ? 'location_parent_footer_saving'
        : isEditMode
            ? 'location_parent_footer_edit'
            : 'location_parent_footer_create';
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
