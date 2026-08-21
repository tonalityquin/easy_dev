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
import '../../domain/models/grid_rect.dart';
import '../../domain/models/location_model.dart';
import '../../domain/models/parking_grid_model.dart';
import 'location_child_area_editor_dialog.dart';
import 'location_child_exclusion_editor_dialog.dart';
import 'location_child_section_editor_dialog.dart';
import 'location_child_slot_editor_dialog.dart';
import 'models/location_child_settings_draft.dart';
import 'widgets/parking_grid_preview.dart';

class LocationChildSettingWorkspace extends StatefulWidget {
  const LocationChildSettingWorkspace({
    super.key,
    required this.parent,
    required this.initialChild,
  });

  final LocationModel parent;
  final LocationModel? initialChild;

  @override
  State<LocationChildSettingWorkspace> createState() =>
      _LocationChildSettingWorkspaceState();
}

class _LocationChildSettingWorkspaceState
    extends State<LocationChildSettingWorkspace> {
  final GlobalKey _identityKey = GlobalKey();
  final GlobalKey _areaKey = GlobalKey();
  final GlobalKey _exclusionKey = GlobalKey();
  final GlobalKey _slotsKey = GlobalKey();
  late LocationChildSettingsDraft _draft;
  LocationModel? _initialChildSnapshot;
  SecondaryLocationWorkspaceState? _workspace;
  LocationChildSettingsSection? _editingSection;
  String? _saveError;
  bool _saving = false;
  bool _validationSubmitted = false;
  bool _reduceMotion = false;
  int _handledNavigationRequestId = 0;

  bool get isEditMode => _initialChildSnapshot != null;
  ParkingGridModel get _parentGrid => widget.parent.parkingGrid!;

  @override
  void initState() {
    super.initState();
    _initialChildSnapshot = widget.initialChild;
    _draft = _initialDraft();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reconcileDraft(source: 'child_initial_reconcile', notify: false);
      _syncSectionStates(source: 'child_initial_form_state');
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _workspace ??= context.read<SecondaryLocationWorkspaceState>();
  }

  @override
  void didUpdateWidget(covariant LocationChildSettingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialChild?.id == widget.initialChild?.id &&
        oldWidget.parent.id == widget.parent.id) {
      return;
    }
    if (widget.initialChild == null && _saving && _initialChildSnapshot != null) {
      return;
    }
    _initialChildSnapshot = widget.initialChild;
    setState(() {
      _draft = _initialDraft();
      _saveError = null;
      _validationSubmitted = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _reconcileDraft(source: 'child_edit_target_changed', notify: false);
      _syncSectionStates(source: 'child_edit_target_changed');
    });
  }

  LocationChildSettingsDraft _initialDraft() {
    final child = _initialChildSnapshot;
    final initial = LocationChildSettingsDraft(
      name: child?.locationName.trim() ?? '',
      parentId: widget.parent.id,
      parentName: widget.parent.locationName.trim(),
      rect: child?.childRect?.normalized(),
      userExcludedSlotAreaIds: <String>{},
      slotNumbersByAreaId: <String, int>{
        for (final slot in child?.childSlots ?? const <ChildSlot>[])
          if (slot.areaId.trim().isNotEmpty && slot.no > 0)
            slot.areaId.trim(): slot.no,
      },
      isTower: child?.isTowerChild ?? false,
      towerCapacity: child?.capacity ?? 1,
    );
    if (child == null || child.isTowerChild || child.childRect == null) {
      return initial;
    }
    final snapshots = _siblingSnapshots();
    final baseFeedback = initial.feedback(
      parentGrid: _parentGrid,
      siblings: snapshots,
    );
    final owned = _childAreaIds(child).toSet();
    final excluded = baseFeedback.candidateSlotAreaIds
        .where((id) => !baseFeedback.occupiedByOtherChildAreaIds.contains(id))
        .where((id) => !owned.contains(id))
        .toSet();
    return initial
        .copyWith(userExcludedSlotAreaIds: excluded)
        .reconciled(parentGrid: _parentGrid, siblings: snapshots);
  }

  List<String> _childAreaIds(LocationModel child) {
    final out = <String>[];
    final seen = <String>{};
    for (final raw in child.childSlotAreaIds) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      if (seen.add(id)) out.add(id);
    }
    if (out.isNotEmpty) return out;
    for (final slot in child.childSlots) {
      final id = slot.areaId.trim();
      if (id.isEmpty) continue;
      if (seen.add(id)) out.add(id);
    }
    return out;
  }

  bool _belongsToParent(LocationModel child) {
    final childParentId = child.parentId?.trim() ?? '';
    if (childParentId.isNotEmpty) return childParentId == widget.parent.id;
    final legacyParent = child.parent?.trim() ?? '';
    return _nameKey(legacyParent) == _nameKey(widget.parent.locationName);
  }

  List<LocationModel> _siblingModels() {
    final area = context.read<AreaState>().currentArea.trim();
    final currentId = _initialChildSnapshot?.id;
    final state = context.read<LocationState>();
    final out = state.locations.where((location) {
      if (!location.isCompositeChild) return false;
      if (area.isNotEmpty && location.area.trim() != area) return false;
      if (currentId != null && location.id == currentId) return false;
      return _belongsToParent(location);
    }).toList();
    return out;
  }

  List<LocationChildAllocationSnapshot> _siblingSnapshots() {
    return _siblingModels()
        .map(
          (child) => LocationChildAllocationSnapshot(
            childId: child.id,
            childName: child.locationName,
            rect: child.childRect?.normalized(),
            ownedSlotAreaIds: _childAreaIds(child).toSet(),
            isTower: child.isTowerChild,
          ),
        )
        .toList(growable: false);
  }

  static String _normalizeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

  LocationChildAllocationFeedback get _feedback => _draft.feedback(
        parentGrid: _parentGrid,
        siblings: _siblingSnapshots(),
      );

  String get _nameError {
    final value = _normalizeName(_draft.name);
    if (value.isEmpty) return '자식구역명을 입력해 주세요.';
    if (value.length > 40) return '자식구역명은 40자 이하로 입력해 주세요.';
    if (_nameKey(value) == _nameKey(widget.parent.locationName)) {
      return '자식구역명은 부모구역명과 같을 수 없습니다.';
    }
    for (final sibling in _siblingModels()) {
      if (_nameKey(sibling.locationName) == _nameKey(value)) {
        return '같은 부모구역에 동일한 자식구역명이 이미 존재합니다.';
      }
    }
    return '';
  }

  String get _areaError {
    final rect = _draft.rect;
    if (rect == null) return '자식구역 영역을 설정해 주세요.';
    final normalized = rect.normalized();
    if (normalized.r0 < 0 ||
        normalized.c0 < 0 ||
        normalized.r1 >= _parentGrid.rows ||
        normalized.c1 >= _parentGrid.cols) {
      return '자식구역이 부모 도면 범위를 벗어납니다.';
    }
    if (_draft.isTower) {
      final registered = _parentGrid.towerRects
          .map((value) => value.normalized())
          .any((value) => value == normalized);
      if (!registered) return '부모 도면에 등록된 주차 타워 영역을 선택해 주세요.';
      final overlapsSibling = _siblingSnapshots()
          .map((sibling) => sibling.rect?.normalized())
          .whereType<GridRect>()
          .any((value) => value.overlaps(normalized));
      if (overlapsSibling) return '선택한 주차 타워 영역이 기존 자식구역과 겹칩니다.';
      if (_draft.towerCapacity <= 0) return '타워 수용 대수는 1 이상이어야 합니다.';
      return '';
    }
    if (_feedback.effectiveCount <= 0) {
      return '실제로 사용할 수 있는 주차 슬롯이 1개 이상 필요합니다.';
    }
    return '';
  }

  String get _slotError {
    if (_draft.isTower) return '';
    final ids = _feedback.effectiveSlotAreaIds;
    if (ids.isEmpty) return '슬롯 번호를 설정할 실제 주차 슬롯이 없습니다.';
    final numbers = <int>{};
    for (final id in ids) {
      final number = _draft.slotNumbersByAreaId[id];
      if (number == null || number <= 0) {
        return '모든 실제 자식 주차 슬롯의 번호를 설정해 주세요.';
      }
      if (!numbers.add(number)) {
        return '같은 자식구역 안에서 슬롯 번호는 중복될 수 없습니다.';
      }
    }
    return '';
  }

  LocationChildSettingsSectionState _sectionState(
    LocationChildSettingsSection section,
  ) {
    switch (section) {
      case LocationChildSettingsSection.identity:
        if (_nameError.isEmpty) return LocationChildSettingsSectionState.complete;
        return _validationSubmitted
            ? LocationChildSettingsSectionState.error
            : LocationChildSettingsSectionState.incomplete;
      case LocationChildSettingsSection.area:
        if (_areaError.isEmpty) return LocationChildSettingsSectionState.complete;
        return _validationSubmitted
            ? LocationChildSettingsSectionState.error
            : LocationChildSettingsSectionState.incomplete;
      case LocationChildSettingsSection.exclusion:
        return LocationChildSettingsSectionState.complete;
      case LocationChildSettingsSection.slots:
        if (_slotError.isEmpty) return LocationChildSettingsSectionState.complete;
        return _validationSubmitted
            ? LocationChildSettingsSectionState.error
            : LocationChildSettingsSectionState.incomplete;
    }
  }

  Map<LocationChildSettingsSection, LocationChildSettingsSectionState>
      _allSectionStates() {
    return <LocationChildSettingsSection, LocationChildSettingsSectionState>{
      for (final section in LocationChildSettingsSection.values)
        section: _sectionState(section),
    };
  }

  void _syncSectionStates({required String source}) {
    _workspace?.updateChildSectionStates(_allSectionStates(), source: source);
  }

  void _reconcileDraft({required String source, bool notify = true}) {
    final next = _draft.reconciled(
      parentGrid: _parentGrid,
      siblings: _siblingSnapshots(),
    );
    final changed = next.userExcludedSlotAreaIds.length !=
            _draft.userExcludedSlotAreaIds.length ||
        next.slotNumbersByAreaId.length != _draft.slotNumbersByAreaId.length;
    _draft = next;
    if (notify && changed && mounted) setState(() {});
    final feedback = _feedback;
    _workspace?.log(
      '$source candidate=${feedback.candidateCount} occupied=${feedback.occupiedCount} reusable=${feedback.reusableOverlapCount} excluded=${feedback.userExcludedCount} effective=${feedback.effectiveCount}',
    );
  }

  void _applyDraft(
    LocationChildSettingsSection section,
    LocationChildSettingsDraft draft,
  ) {
    final snapshots = _siblingSnapshots();
    final next = draft.detached().reconciled(
      parentGrid: _parentGrid,
      siblings: snapshots,
    );
    setState(() {
      _draft = next;
      _saveError = null;
    });
    _workspace?.setSettingsDirty(true, source: 'child_editor_apply_${section.name}');
    _workspace?.selectChildSettingsSection(section, source: 'child_editor_apply');
    final feedback = _feedback;
    _workspace?.log(
      'child_draft_applied section=${section.name} rect=${_draft.rect?.normalized()} candidate=${feedback.candidateCount} occupied=${feedback.occupiedCount} reusable=${feedback.reusableOverlapCount} excluded=${feedback.userExcludedCount} effective=${feedback.effectiveCount} slotNumbers=${_draft.slotNumbersByAreaId.length}',
    );
    _syncSectionStates(source: 'child_editor_apply_${section.name}');
  }

  GlobalKey _keyFor(LocationChildSettingsSection section) {
    switch (section) {
      case LocationChildSettingsSection.identity:
        return _identityKey;
      case LocationChildSettingsSection.area:
        return _areaKey;
      case LocationChildSettingsSection.exclusion:
        return _exclusionKey;
      case LocationChildSettingsSection.slots:
        return _slotsKey;
    }
  }

  Rect? _sourceRectFor(LocationChildSettingsSection section) {
    final sectionContext = _keyFor(section).currentContext;
    final box = sectionContext?.findRenderObject() as RenderBox?;
    if (box == null || !box.attached || !box.hasSize) return null;
    final origin = box.localToGlobal(Offset.zero);
    return origin & box.size;
  }

  String _sectionTitle(LocationChildSettingsSection section) {
    switch (section) {
      case LocationChildSettingsSection.identity:
        return '자식구역 기본 정보';
      case LocationChildSettingsSection.area:
        return '자식구역 크기 및 영역';
      case LocationChildSettingsSection.exclusion:
        return '제외 영역';
      case LocationChildSettingsSection.slots:
        return '슬롯 번호';
    }
  }

  Future<void> _scrollToSection(LocationChildSettingsSection section) async {
    final sectionContext = _keyFor(section).currentContext;
    if (sectionContext == null) return;
    _workspace?.log('child_settings_scroll_requested section=${section.name}');
    await Scrollable.ensureVisible(
      sectionContext,
      duration: _reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.enter,
      alignment: .02,
    );
  }

  void _scheduleNavigationRequest(SecondaryLocationWorkspaceState workspace) {
    final requestId = workspace.childSettingsNavigationRequestId;
    if (requestId == _handledNavigationRequestId) return;
    _handledNavigationRequestId = requestId;
    final target = workspace.activeChildSettingsSection;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_scrollToSection(target));
    });
  }

  Future<void> _openEditor(LocationChildSettingsSection section) async {
    if (_saving || _editingSection != null) return;
    if (_draft.isTower &&
        (section == LocationChildSettingsSection.exclusion ||
            section == LocationChildSettingsSection.slots)) {
      _workspace?.selectChildSettingsSection(section, source: 'child_tower_section_tap');
      return;
    }
    if (section != LocationChildSettingsSection.identity &&
        _draft.rect == null &&
        section != LocationChildSettingsSection.area) {
      _workspace?.requestChildSettingsSection(
        LocationChildSettingsSection.area,
        source: 'child_dependency_missing_rect',
      );
      await _openEditor(LocationChildSettingsSection.area);
      return;
    }
    _workspace?.selectChildSettingsSection(section, source: 'child_summary_row_tap');
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final sourceRect = _sourceRectFor(section);
    if (sourceRect == null) {
      _workspace?.log('child_editor_open_failed section=${section.name} reason=no_source_rect');
      return;
    }
    setState(() => _editingSection = section);
    final rootContext = Navigator.of(context, rootNavigator: true).context;
    final trace = await DeveloperOperationTrace.start(
      context: rootContext,
      title: '${_sectionTitle(section)} 편집',
      initialMessage: '자식구역 설정 편집을 시작합니다: section=${section.name}',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 편집 Dialog의 버그 아이콘에서 debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 자식구역 편집 동작을 콘솔에 기록합니다.',
      showDialogImmediately: false,
    );
    try {
      trace.log(
        '원본 row bounds 확보 section=${section.name} width=${sourceRect.width.toStringAsFixed(1)} height=${sourceRect.height.toStringAsFixed(1)}',
      );
      final snapshots = _siblingSnapshots();
      final targetSize = switch (section) {
        LocationChildSettingsSection.identity => const Size(520, 420),
        LocationChildSettingsSection.area => const Size(900, 800),
        LocationChildSettingsSection.exclusion => const Size(900, 820),
        LocationChildSettingsSection.slots => const Size(940, 860),
      };
      final applied = await showCommonOriginMorphDialog<bool>(
        context: context,
        sourceRect: sourceRect,
        targetSize: targetSize,
        barrierDismissible: false,
        barrierLabel: '${_sectionTitle(section)} 편집',
        builder: (_) {
          switch (section) {
            case LocationChildSettingsSection.identity:
              return LocationChildSectionEditorDialog(
                initialDraft: _draft.detached(),
                trace: trace,
                onApply: (draft) => _applyDraft(section, draft),
              );
            case LocationChildSettingsSection.area:
              return LocationChildAreaEditorDialog(
                initialDraft: _draft.detached(),
                parentGrid: _parentGrid,
                siblings: snapshots,
                trace: trace,
                onApply: (draft) => _applyDraft(section, draft),
              );
            case LocationChildSettingsSection.exclusion:
              return LocationChildExclusionEditorDialog(
                initialDraft: _draft.detached(),
                parentGrid: _parentGrid,
                siblings: snapshots,
                trace: trace,
                onApply: (draft) => _applyDraft(section, draft),
              );
            case LocationChildSettingsSection.slots:
              return LocationChildSlotEditorDialog(
                initialDraft: _draft.detached(),
                parentGrid: _parentGrid,
                siblings: snapshots,
                trace: trace,
                onApply: (draft) => _applyDraft(section, draft),
              );
          }
        },
      );
      trace.log('자식구역 section Dialog 종료 section=${section.name} applied=${applied == true}');
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
    _reconcileDraft(source: 'child_submit_reconcile', notify: false);
    _syncSectionStates(source: 'child_submit_validation');

    if (_nameError.isNotEmpty) {
      _workspace?.requestChildSettingsSection(
        LocationChildSettingsSection.identity,
        source: 'child_submit_validation_failed',
      );
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      await _openEditor(LocationChildSettingsSection.identity);
      return;
    }
    if (_areaError.isNotEmpty) {
      _workspace?.requestChildSettingsSection(
        LocationChildSettingsSection.area,
        source: 'child_submit_validation_failed',
      );
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      await _openEditor(LocationChildSettingsSection.area);
      return;
    }
    if (_slotError.isNotEmpty) {
      _workspace?.requestChildSettingsSection(
        LocationChildSettingsSection.slots,
        source: 'child_submit_validation_failed',
      );
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      await _openEditor(LocationChildSettingsSection.slots);
      return;
    }

    final workspace = _workspace;
    final state = context.read<LocationState>();
    final area = context.read<AreaState>().currentArea.trim();
    final child = _initialChildSnapshot;
    final feedback = _feedback;
    final operationTitle = isEditMode ? '자식구역 수정' : '자식구역 생성';
    final rect = _draft.rect!;
    final capacity = _draft.isTower ? _draft.towerCapacity : feedback.effectiveCount;
    final slotIds = _draft.isTower
        ? <String>[]
        : feedback.effectiveSlotAreaIds.toList();
    slotIds.sort();
    final slotNumbers = _draft.isTower
        ? const <String, int>{}
        : <String, int>{
            for (final id in slotIds) id: _draft.slotNumbersByAreaId[id]!,
          };

    setState(() => _saving = true);
    workspace?.setSettingsSaving(true, source: 'child_submit_started');
    workspace?.log(
      'child_settings_submit_started mode=${isEditMode ? 'edit' : 'create'} childKind=${_draft.isTower ? 'tower' : 'normal'} rect=${rect.normalized()} candidate=${feedback.candidateCount} occupied=${feedback.occupiedCount} reusable=${feedback.reusableOverlapCount} excluded=${feedback.userExcludedCount} effective=${feedback.effectiveCount}',
    );

    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: operationTitle,
      initialMessage: '$operationTitle 요청을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 자식구역 저장 로그를 debugPrint 코드로 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF: 자식구역 저장 로그를 콘솔에 기록합니다.',
    );

    String? writeError;
    try {
      if (area.isEmpty) throw StateError('현재 지역 정보가 없습니다.');
      trace.log(
        'draft 검증 통과 parentId=${widget.parent.id} nameLength=${_draft.name.length} rect=${rect.normalized()} kind=${_draft.isTower ? 'tower' : 'normal'}',
        progress: .22,
      );
      trace.log(
        'allocation candidate=${feedback.candidateCount} occupied=${feedback.occupiedCount} reusable=${feedback.reusableOverlapCount} userExcluded=${feedback.userExcludedCount} effective=${feedback.effectiveCount} numbered=${slotNumbers.length}',
        progress: .48,
      );
      final saved = child == null
          ? await state.createCompositeChild(
              parentId: widget.parent.id,
              child: _draft.name,
              capacity: capacity,
              area: area,
              rect: rect,
              childSlotAreaIds: slotIds,
              childSlotNumbersByAreaId: slotNumbers,
              isTower: _draft.isTower,
              onError: (message) {
                writeError = message;
                trace.log('저장 검증 메시지: $message');
              },
            )
          : await state.updateCompositeChild(
              id: child.id,
              parentId: widget.parent.id,
              child: _draft.name,
              capacity: capacity,
              area: area,
              rect: rect,
              childSlotAreaIds: slotIds,
              childSlotNumbersByAreaId: slotNumbers,
              isTower: _draft.isTower,
              onError: (message) {
                writeError = message;
                trace.log('저장 검증 메시지: $message');
              },
            );
      if (!saved) throw StateError(writeError ?? '$operationTitle에 실패했습니다.');
      trace.log('Firestore 동기화 완료', progress: .86);
      await trace.succeed('$operationTitle 완료');
      if (!mounted) return;
      workspace?.setSettingsDirty(false, source: 'child_submit_success');
      showSuccessSnackbar(
        context,
        isEditMode ? '자식구역 수정이 완료되었습니다.' : '자식구역 생성이 완료되었습니다.',
        useCommonUi: true,
      );
      state.clearSelection();
      workspace?.returnToManagement(source: 'child_submit_success');
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
      workspace?.log('child_settings_submit_failed error=$message');
    } finally {
      if (mounted) setState(() => _saving = false);
      workspace?.setSettingsSaving(false, source: 'child_submit_finished');
    }
  }

  void _returnToManagement() {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    context.read<LocationState>().clearSelection();
    _workspace?.returnToManagement(source: 'child_settings_footer_back');
  }

  ({Color color, IconData icon}) _statusVisual(
    BuildContext context,
    LocationChildSettingsSectionState state,
  ) {
    final tokens = CommonUiTheme.of(context);
    switch (state) {
      case LocationChildSettingsSectionState.complete:
        return (color: tokens.success, icon: Icons.check_rounded);
      case LocationChildSettingsSectionState.incomplete:
        return (color: tokens.warning, icon: Icons.priority_high_rounded);
      case LocationChildSettingsSectionState.error:
        return (color: tokens.danger, icon: Icons.error_outline_rounded);
    }
  }

  Widget _summaryRow(
    BuildContext context, {
    required GlobalKey rowKey,
    required LocationChildSettingsSection section,
    required IconData icon,
    required String title,
    required String summary,
    bool enabled = true,
  }) {
    final tokens = CommonUiTheme.of(context);
    final workspace = context.watch<SecondaryLocationWorkspaceState>();
    final active = workspace.activeChildSettingsSection == section ||
        _editingSection == section;
    final state = _sectionState(section);
    final visual = _statusVisual(context, state);
    return KeyedSubtree(
      key: rowKey,
      child: OpsDockSelectableRowSurface(
        selected: active,
        selectionColor: tokens.accent,
        selectedContainer: tokens.accentContainer,
        onTap: () {
          if (!enabled || _saving) return;
          unawaited(_openEditor(section));
        },
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        child: Row(
          children: [
            Icon(icon, size: 19, color: active ? tokens.accent : tokens.iconPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: enabled ? tokens.textPrimary : tokens.textSecondary,
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
            AnimatedSwitcher(
              duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
              child: Icon(
                visual.icon,
                key: ValueKey<LocationChildSettingsSectionState>(state),
                size: 17,
                color: visual.color,
              ),
            ),
            if (enabled) ...[
              const SizedBox(width: 4),
              Icon(Icons.chevron_right_rounded, size: 19, color: tokens.iconSecondary),
            ],
          ],
        ),
      ),
    );
  }

  List<ChildSlot> _previewNumberedSlots() {
    return _draft.numberedSlots(
      parentGrid: _parentGrid,
      siblings: _siblingSnapshots(),
    );
  }

  Widget _buildPreview(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final feedback = _feedback;
    final siblingRegions = _siblingModels()
        .where((child) => child.childRect != null)
        .map(
          (child) => ChildRegionOverlay(
            id: child.id,
            rect: child.childRect!,
            label: child.locationName,
            isSelected: false,
            useEffectiveShape: !child.isTowerChild,
            effectiveParkingAreaIds: _childAreaIds(child).toSet(),
          ),
        )
        .toList();
    if (_draft.rect != null) {
      siblingRegions.add(
        ChildRegionOverlay(
          id: _initialChildSnapshot?.id ?? 'draft-child',
          rect: _draft.rect!,
          label: _draft.name.trim().isEmpty ? '자식구역' : _draft.name,
          isSelected: true,
          useEffectiveShape: !_draft.isTower,
          effectiveParkingAreaIds: feedback.effectiveSlotAreaIds,
        ),
      );
    }
    final effectiveKey = feedback.effectiveSlotAreaIds.toList()..sort();
    final occupiedKey = feedback.occupiedByOtherChildAreaIds.toList()..sort();
    final excludedKey = feedback.userExcludedAreaIds.toList()..sort();
    final signature = '${_draft.rect}-${effectiveKey.join('|')}-${occupiedKey.join('|')}-${excludedKey.join('|')}-${_draft.slotNumbersByAreaId}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.map_outlined, size: 18, color: tokens.iconSecondary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '현재 자식구역',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _draft.isTower
                    ? '주차 타워'
                    : '실제 슬롯 ${feedback.effectiveCount}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 9),
          AnimatedSwitcher(
            duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
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
                borderRadius: BorderRadius.circular(CommonUiShapes.control),
              ),
              child: ParkingGridPreview(
                grid: _parentGrid,
                maxExtent: 300,
                showLegend: false,
                showParkingAreaLabels: false,
                childRegions: siblingRegions,
                showChildRegionLabels: true,
                showAllChildRegionLabels: false,
                effectiveParkingAreaIds:
                    _draft.isTower ? const <String>{} : feedback.effectiveSlotAreaIds,
                occupiedParkingAreaIds:
                    _draft.isTower ? const <String>{} : feedback.occupiedByOtherChildAreaIds,
                reusableParkingAreaIds:
                    _draft.isTower ? const <String>{} : feedback.reusableOverlapAreaIds,
                excludedParkingAreaIds:
                    _draft.isTower ? const <String>{} : feedback.userExcludedAreaIds,
                showChildSlotNumbers: !_draft.isTower,
                childSlotsToLabel: _previewNumberedSlots(),
              ),
            ),
          ),
          const SizedBox(height: 8),
          AnimatedSwitcher(
            duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
            child: Text(
              _draft.isTower
                  ? '부모 도면의 등록 타워 영역 · 수용 ${_draft.towerCapacity}대'
                  : '후보 ${feedback.candidateCount} · 자동 제외 ${feedback.occupiedCount} · 재사용 가능 ${feedback.reusableOverlapCount} · 사용자 제외 ${feedback.userExcludedCount} · 실제 ${feedback.effectiveCount}',
              key: ValueKey<String>(
                '${_draft.isTower}-${feedback.candidateCount}-${feedback.occupiedCount}-${feedback.reusableOverlapCount}-${feedback.userExcludedCount}-${feedback.effectiveCount}-${_draft.towerCapacity}',
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStrip(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final states = _allSectionStates();
    final incomplete = states.values.where((state) {
      return state == LocationChildSettingsSectionState.incomplete ||
          state == LocationChildSettingsSectionState.error;
    }).length;
    final complete = incomplete == 0;
    return Row(
      children: [
        Expanded(
          child: AnimatedSwitcher(
            duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
            child: Text(
              complete ? '설정 확인 완료' : '확인 필요 $incomplete개',
              key: ValueKey<int>(incomplete),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: complete ? tokens.success : tokens.warning,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ),
        AnimatedSwitcher(
          duration: _reduceMotion ? Duration.zero : CommonUiMotion.selection,
          child: Icon(
            complete ? Icons.check_circle_rounded : Icons.error_outline_rounded,
            key: ValueKey<bool>(complete),
            size: 18,
            color: complete ? tokens.success : tokens.warning,
          ),
        ),
      ],
    );
  }

  Widget _buildContentSurface(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final feedback = _feedback;
    final rect = _draft.rect?.normalized();
    final assigned = _draft.slotNumbersByAreaId.entries
        .where((entry) => feedback.effectiveSlotAreaIds.contains(entry.key) && entry.value > 0)
        .length;
    final identitySummary = _nameError.isEmpty ? _draft.name : '자식구역명 입력 필요';
    final areaSummary = _draft.isTower
        ? rect == null
            ? '주차 타워 영역 선택 필요'
            : '주차 타워 · ${rect.width} × ${rect.height} · 수용 ${_draft.towerCapacity}대'
        : rect == null
            ? '직사각형 영역 선택 필요'
            : '${rect.width} × ${rect.height} · 실제 슬롯 ${feedback.effectiveCount}개';
    final exclusionSummary = _draft.isTower
        ? '주차 타워는 주차면 제외 설정을 사용하지 않습니다.'
        : rect == null
            ? '영역을 먼저 설정해 주세요.'
            : '자동 제외 ${feedback.occupiedCount} · 사용자 제외 ${feedback.userExcludedCount} · 재사용 가능 ${feedback.reusableOverlapCount}';
    final slotSummary = _draft.isTower
        ? '주차 타워는 개별 슬롯 번호를 사용하지 않습니다.'
        : rect == null
            ? '영역을 먼저 설정해 주세요.'
            : '$assigned / ${feedback.effectiveCount} 설정';

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
            section: LocationChildSettingsSection.identity,
            icon: Icons.location_on_outlined,
            title: '자식구역 기본 정보',
            summary: identitySummary,
          ),
          Container(height: 1, color: tokens.borderSubtle),
          _summaryRow(
            context,
            rowKey: _areaKey,
            section: LocationChildSettingsSection.area,
            icon: Icons.aspect_ratio_rounded,
            title: '자식구역 크기 및 영역',
            summary: areaSummary,
          ),
          Container(height: 1, color: tokens.borderSubtle),
          _summaryRow(
            context,
            rowKey: _exclusionKey,
            section: LocationChildSettingsSection.exclusion,
            icon: Icons.content_cut_rounded,
            title: '제외 영역',
            summary: exclusionSummary,
            enabled: !_draft.isTower,
          ),
          Container(height: 1, color: tokens.borderSubtle),
          _summaryRow(
            context,
            rowKey: _slotsKey,
            section: LocationChildSettingsSection.slots,
            icon: Icons.format_list_numbered_rounded,
            title: '슬롯 번호',
            summary: slotSummary,
            enabled: !_draft.isTower,
          ),
          Container(height: 1, color: tokens.borderSubtle),
          _buildPreview(context),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final key = _saving
        ? 'location_child_footer_saving'
        : isEditMode
            ? 'location_child_footer_edit'
            : 'location_child_footer_create';
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
