import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../app/utils/location_debug_status.dart';
import '../../../app/utils/snackbar_helper.dart';
import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';

import '../../dev/application/area_state.dart';
import '../../selector/application/dev_auth.dart';
import '../applications/location_state.dart';
import '../data/services/location_reservation_integrity_service.dart';
import '../domain/models/location_model.dart';
import '../domain/models/parking_grid_model.dart';
import 'sheets/location_setting.dart';
import 'sheets/widgets/location_draft.dart';
import 'sheets/widgets/parking_grid_preview.dart';
import '../../../shared/secondary/application/secondary_location_workspace_state.dart';
import '../../../shared/secondary/widgets/ops_console_dialogs.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';

enum _LocationMaintenanceAction { reservationIntegrity, rebuildChildSlots }

class LocationManagement extends StatefulWidget {
  const LocationManagement({
    super.key,
    this.workspace,
  });

  final SecondaryLocationWorkspaceState? workspace;

  @override
  State<LocationManagement> createState() => _LocationManagementState();
}

class _LocationManagementState extends State<LocationManagement> {
  String _filter = 'all';
  String _query = '';
  late final SecondaryLocationWorkspaceState _localWorkspace;
  final TextEditingController _searchController = TextEditingController();
  final LocationReservationIntegrityService _reservationIntegrityService =
      LocationReservationIntegrityService();
  bool _reservationIntegrityCheckInProgress = false;
  bool _refreshing = false;
  bool _selectionValidationScheduled = false;
  String? _lastArea;

  SecondaryLocationWorkspaceState get _workspace =>
      widget.workspace ?? _localWorkspace;

  bool get _showOnlySelectedChild => _workspace.showOnlySelectedChild;

  bool get _showSelectedChildSlotNumbers =>
      _workspace.showSelectedChildSlotNumbers;

  String? get _focusedParentKey => _workspace.focusedParentKey;

  @override
  void initState() {
    super.initState();
    _localWorkspace = SecondaryLocationWorkspaceState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _log('overview_mounted');
    });
    unawaited(DevAuth.isDevModeEnabled().then<void>((_) {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    if (widget.workspace == null) {
      _localWorkspace.dispose();
    }
    super.dispose();
  }

  void _log(String message) {
    _workspace.log(message);
  }

  static String _normalizeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

  static String _resolvedParentName(
    LocationModel child,
    Map<String, LocationModel> parentsById,
  ) {
    final storedName = (child.parent ?? '').trim();
    if (storedName.isNotEmpty) return storedName;
    final parentId = (child.parentId ?? '').trim();
    if (parentId.isEmpty) return '';
    return (parentsById[parentId]?.locationName ?? '').trim();
  }

  static List<String> _childAreaIds(LocationModel loc) {
    final out = <String>[];
    final seen = <String>{};

    for (final id in loc.childSlotAreaIds) {
      final v = id.trim();
      if (v.isEmpty) continue;
      if (seen.add(v)) out.add(v);
    }

    if (out.isNotEmpty) return out;

    for (final slot in loc.childSlots) {
      final v = slot.areaId.trim();
      if (v.isEmpty) continue;
      if (seen.add(v)) out.add(v);
    }

    return out;
  }


  static const String _miscGroupKey = '__misc__';


  void _openFocusedParent(
    String key,
    LocationState state, {
    required String parentId,
    required String title,
  }) {
    state.clearSelection();
    HapticFeedback.selectionClick();
    _workspace.openParent(
      key: key,
      parentId: parentId,
      title: title,
      source: 'parent_row',
    );
  }

  void _closeFocusedParent({String source = 'back'}) {
    if (!_workspace.isParentFocus) return;
    context.read<LocationState>().clearSelection();
    _workspace.closeParent(source: source);
  }

  void _selectFocusedChild(
    LocationModel child,
    LocationState state, {
    required String source,
  }) {
    final wasSelected = state.selectedLocationId == child.id;
    HapticFeedback.selectionClick();
    state.toggleLocationSelection(child.id);
    if (wasSelected) {
      if (_workspace.showOnlySelectedChild ||
          _workspace.showSelectedChildSlotNumbers) {
        _workspace.clearChildInspection(source: 'child_deselected');
      }
      _log('child_deselected id=${child.id} source=$source');
      return;
    }
    _log('child_selected id=${child.id} source=$source');
  }

  Future<bool> _confirmDelete(
    BuildContext context, {
    required LocationModel target,
    required int childCount,
    required int reservationSlotCount,
  }) {
    final parent = _isCompositeParent(target);
    final child = _isCompositeChild(target);
    final parentName = (target.parent ?? '').trim();
    final message = parent
        ? '${target.locationName} 부모 구역을 삭제하면 연결된 자식 구역 $childCount개와 관련 슬롯 예약 정보가 함께 삭제됩니다. 연결 슬롯 $reservationSlotCount개를 확인한 뒤 진행하세요.'
        : child
            ? '${target.locationName} 자식 구역을 삭제하면 ${parentName.isEmpty ? '현재 부모 구역' : parentName}의 공간 배치에서 제거되고 관련 슬롯 예약 정보도 함께 정리됩니다. 연결 슬롯 $reservationSlotCount개를 확인한 뒤 진행하세요.'
            : '${target.locationName} 구역이 운영 목록에서 제거됩니다. 관련 슬롯 예약 정보와 화면 배치를 확인한 뒤 진행하세요.';
    return showOpsConfirmDialog(
      context: context,
      title: parent
          ? '부모 구역 삭제 확인'
          : child
              ? '자식 구역 삭제 확인'
              : '구역 삭제 확인',
      message: message,
      confirmLabel: parent
          ? '부모 구역 삭제'
          : child
              ? '자식 구역 삭제'
              : '삭제',
      icon: Icons.delete_forever_rounded,
      destructive: true,
    );
  }

  bool _isCompositeParent(LocationModel loc) =>
      (loc.type ?? '') == 'composite_parent';

  bool _isCompositeChild(LocationModel loc) {
    final t = loc.type ?? 'single';
    return t == 'composite_child' || t == 'composite';
  }

  int _countEmptyCells(ParkingGridModel grid) {
    var count = 0;
    for (var i = 0; i < grid.cells.length; i++) {
      if (grid.cellTypeAt(i) == ParkingGridCellType.empty) count++;
    }
    return count;
  }

  int _countParkingAreas(ParkingGridModel grid) => grid.parkingAreas.length;

  String _slotLabelForSummary(ChildSlot s) {
    final label = s.label.trim();
    if (label.isNotEmpty) return label;

    final category = s.categoryLabel.trim();
    final footprint = s.footprint.trim();
    if (category.isNotEmpty && footprint.isNotEmpty) {
      return '$category $footprint';
    }
    if (category.isNotEmpty) return category;
    if (footprint.isNotEmpty) return footprint;

    final kind = s.kind.trim();
    return kind.isEmpty ? '미지정' : kind;
  }

  String _slotSummaryText(Iterable<ChildSlot> slots) {
    final counts = <String, int>{};
    for (final s in slots) {
      final label = _slotLabelForSummary(s);
      counts[label] = (counts[label] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key} ${e.value}').join(' · ');
  }

  String _integrityIssueSummary(LocationReservationIntegrityReport report) {
    final values = <String>[
      'normal=${report.normalCount}',
      'orphan=${report.count(LocationReservationIntegrityIssueType.orphan)}',
      'missing=${report.count(LocationReservationIntegrityIssueType.missing)}',
      'wrongOwner=${report.count(LocationReservationIntegrityIssueType.wrongOwner)}',
      'staleMetadata=${report.count(LocationReservationIntegrityIssueType.staleMetadata)}',
      'areaMismatch=${report.count(LocationReservationIntegrityIssueType.areaMismatch)}',
      'invalidParent=${report.count(LocationReservationIntegrityIssueType.invalidParent)}',
      'invalidArea=${report.count(LocationReservationIntegrityIssueType.invalidArea)}',
      'duplicateOwner=${report.count(LocationReservationIntegrityIssueType.duplicateOwner)}',
      'invalidReservation=${report.count(LocationReservationIntegrityIssueType.invalidReservation)}',
      'documentIdMismatch=${report.count(LocationReservationIntegrityIssueType.documentIdMismatch)}',
      'duplicateReservation=${report.count(LocationReservationIntegrityIssueType.duplicateReservation)}',
    ];
    return values.join(', ');
  }

  Future<void> _handleReservationIntegrityCheck(BuildContext context) async {
    _log('reservation_integrity_started');
    if (_reservationIntegrityCheckInProgress) return;
    setState(() => _reservationIntegrityCheckInProgress = true);

    DeveloperOperationTrace? trace;

    try {
      final developerMode = await DevAuth.isDevModeEnabled();
      if (!developerMode) {
        return;
      }

      if (!mounted || !context.mounted) return;

      final activeTrace = await DeveloperOperationTrace.start(
        context: context,
        title: '예약 정합성 검사',
        initialMessage: '현재 지역의 Location 예약 정합성 검사를 준비하고 있습니다.',
        useCommonUi: true,
        developerModeMessage:
            '개발자 모드 ON: 검사 로그의 debugPrint 코드를 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF',
      );
      trace = activeTrace;

      final area = context.read<AreaState>().currentArea.trim();
      activeTrace.log(
        '검사 정책: readOnly=true, source=server, locationsSourceOfTruth=true, reservationScope=area+parentId, reservationWrite=false',
        progress: 0.04,
      );

      final report = await _reservationIntegrityService.check(
        area: area,
        onProgress: (message, progress) {
          activeTrace.log(message, progress: progress);
        },
      );

      activeTrace.log(
        '검사 범위: area=${report.area}, locations=${report.locationCount}, parents=${report.parentCount}, children=${report.childCount}, expectedReservations=${report.expectedReservationCount}, actualReservations=${report.reservationCount}',
        progress: 0.88,
      );
      activeTrace.log(
        '검사 요약: ${_integrityIssueSummary(report)}',
        progress: 0.9,
      );

      if (report.issues.isNotEmpty) {
        activeTrace.log(
          '확인 필요 항목 상세 로그를 출력합니다: count=${report.issues.length}',
          progress: 0.92,
        );
        for (final issue in report.issues) {
          activeTrace.log(issue.toLogLine(), progress: 0.94);
        }
      }

      if (report.hasIssues) {
        await activeTrace.succeed(
          '예약 정합성 검사가 완료되었습니다. 확인이 필요한 항목 ${report.issues.length}건을 발견했습니다. 데이터는 변경하지 않았습니다.',
        );
      } else {
        await activeTrace.succeed(
          '예약 정합성 검사가 완료되었습니다. 문제가 발견되지 않았으며 데이터는 변경하지 않았습니다.',
        );
      }
    } catch (error, stackTrace) {
      if (trace != null) {
        await trace.fail(
          '예약 정합성 검사에 실패했습니다.',
          error: error,
          stackTrace: stackTrace,
        );
      } else if (mounted && context.mounted) {
        showFailedSnackbar(
          context,
          '예약 정합성 검사에 실패했습니다.',
          useCommonUi: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _reservationIntegrityCheckInProgress = false);
      }
    }
  }

  Future<void> _handleRebuildChildSlots(BuildContext context) async {
    final confirmed = await showOpsConfirmDialog(
      context: context,
      title: '자식 슬롯 재계산 확인',
      message: '현재 지역의 복합 부모 그리드를 기준으로 자식 슬롯 정보를 다시 계산하고 저장합니다. 운영 중인 공간 구조를 확인한 뒤 진행하세요.',
      confirmLabel: '재계산',
      icon: Icons.sync_alt_rounded,
    );
    if (!confirmed || !mounted || !context.mounted) return;

    final state = context.read<LocationState>();
    final area = context.read<AreaState>().currentArea.trim();
    String? errorMessage;
    DeveloperOperationTrace? trace;
    _log('child_slots_rebuild_started area=$area');

    try {
      trace = await DeveloperOperationTrace.start(
        context: context,
        title: '자식 슬롯 재계산',
        initialMessage: '현재 지역의 자식 슬롯 재계산을 준비합니다.',
        useCommonUi: true,
        developerModeMessage:
            '개발자 모드 ON: 재계산 로그의 debugPrint 코드를 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF',
      );
      trace.log('재계산 범위 확인: area=$area', progress: .12);
      final ok = await state.refreshChildSlotsForCurrentArea(
        onError: (message) {
          final value = message.trim();
          if (value.isNotEmpty) errorMessage = value;
        },
      );
      if (!ok) {
        throw StateError(errorMessage ?? '자식 슬롯 재계산에 실패했습니다.');
      }
      trace.log('Firestore 및 로컬 상태 반영 완료', progress: .9);
      await trace.succeed('자식 슬롯 재계산이 완료되었습니다.');
      _log('child_slots_rebuild_completed area=$area');
      if (mounted && context.mounted) {
        showSuccessSnackbar(
          context,
          '기존 자식 슬롯을 최신 주차면적으로 재계산했습니다.',
          useCommonUi: true,
        );
      }
    } catch (error, stackTrace) {
      _log('child_slots_rebuild_failed area=$area error=$error');
      if (trace != null) {
        await trace.fail(
          '자식 슬롯 재계산에 실패했습니다.',
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (mounted && context.mounted) {
        showFailedSnackbar(
          context,
          errorMessage ?? '자식 슬롯 재계산에 실패했습니다.',
          useCommonUi: true,
        );
      }
    }
  }

  Future<bool> _runWrite(
    BuildContext context,
    Future<bool> Function(ValueChanged<String> onError) operation, {
    bool preserveSelectionOnSuccess = false,
  }) async {
    String? errorMessage;
    final debugArea = context.read<AreaState>().currentArea.trim();
    final debugSelectedLocationId =
        context.read<LocationState>().selectedLocationId;

    _log(
      'write_started area=$debugArea selected=${debugSelectedLocationId ?? '-'}',
    );

    try {
      final ok = await operation((message) {
        final value = message.trim();
        if (value.isNotEmpty) errorMessage = value;
      });

      if (!mounted || !context.mounted) return ok;

      if (!ok) {
        _log(
          'write_failed area=$debugArea selected=${debugSelectedLocationId ?? '-'} message=${errorMessage ?? '-'}',
        );
        showFailedSnackbar(
          context,
          errorMessage ?? '주차 구역 작업에 실패했습니다.',
          useCommonUi: true,
        );
      } else {
        if (preserveSelectionOnSuccess && debugSelectedLocationId != null) {
          final currentState = context.read<LocationState>();
          final selectionStillExists = currentState.locations.any(
            (location) => location.id == debugSelectedLocationId,
          );
          if (selectionStillExists) {
            currentState.selectLocation(debugSelectedLocationId);
            _log(
              'selection_restored id=$debugSelectedLocationId source=write_completed',
            );
          }
        }
        _log(
          'write_completed area=$debugArea selected=${debugSelectedLocationId ?? '-'} preserveSelection=$preserveSelectionOnSuccess',
        );
      }

      return ok;
    } catch (error, stackTrace) {
      _log(
        'write_exception area=$debugArea selected=${debugSelectedLocationId ?? '-'} error=$error',
      );
      LocationDebugStatus.report(
        context: context,
        title: '주차 구역 작업 실패',
        operation: 'LocationManagement._runWrite',
        error: error,
        stackTrace: stackTrace,
        details: <String, Object?>{
          'area': debugArea,
          'selectedLocationId': debugSelectedLocationId,
        },
      );

      if (mounted && context.mounted) {
        showFailedSnackbar(
          context,
          errorMessage ?? '주차 구역 작업에 실패했습니다.',
          useCommonUi: true,
        );
      }

      return false;
    }
  }

  Future<void> _handleAddParent(BuildContext context) async {
    final area = context.read<AreaState>().currentArea.trim();
    if (area.isEmpty) {
      showFailedSnackbar(
        context,
        '현재 지역 정보가 없어 부모구역을 생성할 수 없습니다.',
        useCommonUi: true,
      );
      return;
    }
    _log('parent_settings_open_requested mode=create');
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    _workspace.openCreateParent(source: 'location_management_create_parent');
  }

  Future<void> _handleAddChild(
    BuildContext context,
    LocationModel parent,
  ) async {
    if (!_isCompositeParent(parent) || parent.parkingGrid == null) {
      showFailedSnackbar(
        context,
        '자식구역을 생성할 부모구역 도면을 찾을 수 없습니다.',
        useCommonUi: true,
      );
      return;
    }
    final area = context.read<AreaState>().currentArea.trim();
    if (area.isEmpty) {
      showFailedSnackbar(
        context,
        '현재 지역 정보가 없어 자식구역을 생성할 수 없습니다.',
        useCommonUi: true,
      );
      return;
    }
    _log('child_settings_open_requested mode=create parentId=${parent.id}');
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    context.read<LocationState>().clearSelection();
    _workspace.openCreateChild(
      parentId: parent.id,
      source: 'location_management_create_child',
    );
  }

  Future<void> _handleEditParent(
    BuildContext context, {
    LocationModel? targetParent,
  }) async {
    final locationState = context.read<LocationState>();
    LocationModel? parent = targetParent;
    if (parent == null) {
      final selectedId = locationState.selectedLocationId;
      if (selectedId != null) {
        for (final location in locationState.locations) {
          if (location.id == selectedId) {
            parent = location;
            break;
          }
        }
      }
    }
    final resolvedParent = parent;
    if (resolvedParent == null ||
        !_isCompositeParent(resolvedParent) ||
        resolvedParent.parkingGrid == null) {
      showFailedSnackbar(
        context,
        '수정할 부모구역 정보를 찾을 수 없습니다.',
        useCommonUi: true,
      );
      return;
    }
    _log('parent_settings_open_requested mode=edit parentId=${resolvedParent.id}');
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    locationState.clearSelection();
    _workspace.openEditParent(
      resolvedParent.id,
      source: 'location_management_edit_parent',
    );
  }

  Future<void> _handleEditChild(BuildContext context) async {
    final locationState = context.read<LocationState>();
    final selectedId = locationState.selectedLocationId;
    if (selectedId == null || selectedId.trim().isEmpty) return;

    LocationModel? child;
    for (final location in locationState.locations) {
      if (location.id == selectedId && _isCompositeChild(location)) {
        child = location;
        break;
      }
    }
    if (child == null) return;

    LocationModel? parent;
    final storedParentId = child.parentId?.trim() ?? '';
    final legacyParent = child.parent?.trim() ?? '';
    for (final location in locationState.locations) {
      if (!_isCompositeParent(location) || location.parkingGrid == null) continue;
      final sameById = storedParentId.isNotEmpty && location.id == storedParentId;
      final sameByName = storedParentId.isEmpty &&
          legacyParent.isNotEmpty &&
          _nameKey(location.locationName) == _nameKey(legacyParent);
      if (sameById || sameByName) {
        parent = location;
        break;
      }
    }
    if (parent == null) {
      showFailedSnackbar(
        context,
        '자식구역의 부모구역 도면을 찾을 수 없습니다.',
        useCommonUi: true,
      );
      return;
    }

    _log('child_settings_open_requested mode=edit childId=${child.id} parentId=${parent.id}');
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    locationState.clearSelection();
    _workspace.openEditChild(
      childId: child.id,
      parentId: parent.id,
      source: 'location_management_edit_child',
    );
  }

  Future<void> _handleEditPlainText(
    BuildContext context, {
    LocationModel? target,
  }) async {
    final locationState = context.read<LocationState>();
    LocationModel? selected = target;
    if (selected == null) {
      final selectedId = locationState.selectedLocationId;
      if (selectedId != null) {
        for (final location in locationState.locations) {
          if (location.id == selectedId) {
            selected = location;
            break;
          }
        }
      }
    }
    final resolvedSelected = selected;
    if (resolvedSelected == null ||
        _isCompositeParent(resolvedSelected) ||
        _isCompositeChild(resolvedSelected)) {
      return;
    }

    final area = context.read<AreaState>().currentArea.trim();
    final existingNameKeysInArea = locationState.locations
        .where((location) => location.area.trim() == area)
        .map((location) => _nameKey(location.locationName))
        .toSet();

    await showCommonOverlayBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (_) => LocationSettingBottomSheet(
        existingNameKeysInArea: existingNameKeysInArea,
        editingPlainTextId: resolvedSelected.id,
        editingPlainTextName: resolvedSelected.locationName,
        editingPlainTextCapacity: resolvedSelected.capacity,
        onSave: (draft) async {
          if (draft is! PlainTextLocationUpdateDraft) return false;
          return _runWrite(
            context,
            (onError) => locationState.updatePlainTextLocation(
              id: draft.id,
              name: draft.name,
              capacity: draft.capacity,
              area: area,
              onError: onError,
            ),
          );
        },
      ),
    );
  }

  Future<void> _handleDelete(
    BuildContext context, {
    String? targetId,
    bool closeFocusedOnSuccess = false,
  }) async {
    final locationState = context.read<LocationState>();
    final locationId = targetId ?? locationState.selectedLocationId;
    if (locationId == null) return;

    LocationModel? target;
    for (final location in locationState.locations) {
      if (location.id == locationId) {
        target = location;
        break;
      }
    }
    if (target == null) return;

    final children = <LocationModel>[];
    if (_isCompositeParent(target)) {
      final parentNameKey = _nameKey(target.locationName);
      for (final location in locationState.locations) {
        if (!_isCompositeChild(location)) continue;
        final parentId = (location.parentId ?? '').trim();
        final parentName = (location.parent ?? '').trim();
        if ((parentId.isNotEmpty && parentId == target.id) ||
            (parentId.isEmpty &&
                parentName.isNotEmpty &&
                _nameKey(parentName) == parentNameKey)) {
          children.add(location);
        }
      }
    }
    final reservationSlotCount = _isCompositeParent(target)
        ? children.fold<int>(
            0,
            (sum, child) => sum + _childAreaIds(child).length,
          )
        : _childAreaIds(target).length;

    _log(
      'delete_confirm_opened id=${target.id} parent=${_isCompositeParent(target)} child=${_isCompositeChild(target)} children=${children.length} slots=$reservationSlotCount',
    );
    final confirmed = await _confirmDelete(
      context,
      target: target,
      childCount: children.length,
      reservationSlotCount: reservationSlotCount,
    );
    if (!confirmed) {
      _log('delete_cancelled id=${target.id}');
      return;
    }

    final deleted = await _runWrite(
      context,
      (onError) => locationState.deleteLocations(
        [locationId],
        onError: onError,
      ),
    );

    if (deleted) {
      _log('delete_completed id=$locationId');
      if (_isCompositeChild(target) &&
          (_workspace.showOnlySelectedChild ||
              _workspace.showSelectedChildSlotNumbers)) {
        _workspace.clearChildInspection(source: 'child_deleted');
      }
      if (closeFocusedOnSuccess && mounted) {
        _closeFocusedParent(source: 'parent_deleted');
      }
    } else {
      _log('delete_failed id=$locationId');
    }
  }

  Future<void> _handleRefresh(BuildContext context) async {
    if (_refreshing) return;
    final state = context.read<LocationState>();
    final area = context.read<AreaState>().currentArea.trim();
    setState(() => _refreshing = true);
    _log('refresh_started area=$area');
    DeveloperOperationTrace? trace;
    try {
      trace = await DeveloperOperationTrace.start(
        context: context,
        title: '주차 구역 데이터 새로고침',
        initialMessage: '현재 지역의 주차 구역 데이터를 새로고침합니다.',
        useCommonUi: true,
        developerModeMessage:
            '개발자 모드 ON: 새로고침 로그의 debugPrint 코드를 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF',
      );
      trace.log('새로고침 범위 확인: area=$area', progress: .14);
      await state.manualLocationRefreshStrict();
      trace.log(
        '새로고침 완료: locations=${state.locations.length}',
        progress: .9,
      );
      await trace.succeed('주차 구역 데이터 새로고침이 완료되었습니다.');
      _log('refresh_completed area=$area count=${state.locations.length}');
    } catch (error, stackTrace) {
      _log('refresh_failed area=$area error=$error');
      if (trace != null) {
        await trace.fail(
          '주차 구역 데이터 새로고침에 실패했습니다.',
          error: error,
          stackTrace: stackTrace,
        );
      }
      if (mounted && context.mounted) {
        showFailedSnackbar(
          context,
          '주차 구역 데이터 새로고침에 실패했습니다.',
          useCommonUi: true,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  bool _matchesLocationQuery(LocationModel loc) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final parts = <String>[
      loc.locationName,
      loc.area,
      loc.type ?? '',
      loc.parent ?? '',
      loc.capacity.toString(),
      loc.isTowerChild ? '타워' : '',
      _slotSummaryText(loc.childSlots),
    ];
    return parts.join(' ').toLowerCase().contains(q);
  }

  void _setQuery(String value) {
    if (_query == value) return;
    setState(() => _query = value);
    _log('query_changed length=${value.trim().length}');
  }

  void _clearQuery() {
    if (_query.isEmpty) return;
    _searchController.clear();
    setState(() => _query = '');
    _log('query_cleared');
  }

  void _setFilter(String value) {
    if (_filter == value) {
      _log('filter_reselected value=$value');
      return;
    }
    HapticFeedback.selectionClick();
    setState(() => _filter = value);
    _log('filter_changed value=$value');
  }

  void _scheduleSelectionValidation({
    required LocationState state,
    required Set<String> validIds,
    required String reason,
  }) {
    final selectedId = state.selectedLocationId;
    if (selectedId == null || validIds.contains(selectedId)) return;
    if (_selectionValidationScheduled) return;
    _selectionValidationScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionValidationScheduled = false;
      if (!mounted) return;
      final currentState = context.read<LocationState>();
      final currentId = currentState.selectedLocationId;
      if (currentId == null || validIds.contains(currentId)) return;
      currentState.clearSelection();
      if (_workspace.showOnlySelectedChild ||
          _workspace.showSelectedChildSlotNumbers) {
        _workspace.clearChildInspection(source: 'selection_cleared');
      }
      _log('selection_cleared reason=$reason id=$currentId');
    });
  }

  void _scheduleFocusValidation({
    required String focusedKey,
    required Set<String> validGroupKeys,
  }) {
    if (validGroupKeys.contains(focusedKey)) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _workspace.focusedParentKey != focusedKey) return;
      context.read<LocationState>().clearSelection();
      _workspace.closeParent(source: 'missing_after_refresh');
      _log('parent_focus_cleared reason=missing_after_refresh key=$focusedKey');
    });
  }

  Future<void> _handleMaintenanceAction(
    BuildContext context,
    _LocationMaintenanceAction action,
  ) async {
    _log('maintenance_selected action=${action.name}');
    switch (action) {
      case _LocationMaintenanceAction.reservationIntegrity:
        await _handleReservationIntegrityCheck(context);
        return;
      case _LocationMaintenanceAction.rebuildChildSlots:
        await _handleRebuildChildSlots(context);
        return;
    }
  }

  Widget _buildMaintenanceMenu(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: DevAuth.devModeEnabled,
      builder: (context, developerMode, _) {
        return PopupMenuButton<_LocationMaintenanceAction>(
          tooltip: '고급 관리',
          onSelected: (action) {
            unawaited(_handleMaintenanceAction(context, action));
          },
          itemBuilder: (context) => <PopupMenuEntry<_LocationMaintenanceAction>>[
            if (developerMode)
              const PopupMenuItem<_LocationMaintenanceAction>(
                value: _LocationMaintenanceAction.reservationIntegrity,
                child: Row(
                  children: [
                    Icon(Icons.fact_check_rounded, size: 18),
                    SizedBox(width: 9),
                    Expanded(child: Text('예약 정합성 검사')),
                  ],
                ),
              ),
            const PopupMenuItem<_LocationMaintenanceAction>(
              value: _LocationMaintenanceAction.rebuildChildSlots,
              child: Row(
                children: [
                  Icon(Icons.sync_alt_rounded, size: 18),
                  SizedBox(width: 9),
                  Expanded(child: Text('현재 지역 자식 슬롯 재계산')),
                ],
              ),
            ),
          ],
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tokens.surface,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              border: Border.all(color: tokens.borderSubtle),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.more_horiz_rounded,
              color: tokens.iconSecondary,
              size: 21,
            ),
          ),
        );
      },
    );
  }

  Widget _buildOverviewToolbar(
    BuildContext context, {
    required bool canCreate,
  }) {
    return Row(
      children: [
        Expanded(
          child: OpsDockSearchField(
            controller: _searchController,
            query: _query,
            semanticLabel: '구역 검색',
            onChanged: _setQuery,
            onClear: _clearQuery,
          ),
        ),
        const SizedBox(width: 6),
        CommonIconButton(
          icon: Icons.refresh_rounded,
          tooltip: '새로고침',
          onPressed: _refreshing ? null : () => _handleRefresh(context),
          loading: _refreshing,
          haptic: CommonHaptic.selection,
          size: 40,
          iconSize: 20,
        ),
        const SizedBox(width: 4),
        CommonIconButton(
          icon: Icons.add_location_alt_rounded,
          tooltip: '구역 추가',
          onPressed: canCreate ? () => _handleAddParent(context) : null,
          haptic: CommonHaptic.selection,
          size: 40,
          iconSize: 20,
        ),
        const SizedBox(width: 4),
        _buildMaintenanceMenu(context),
      ],
    );
  }

  Widget _buildOverviewFooter(
    BuildContext context,
    LocationModel? selectedPlain,
  ) {
    if (selectedPlain == null) {
      return const SizedBox.shrink(
        key: ValueKey<String>('location-overview-footer-none'),
      );
    }
    return OpsDockContextFooter(
      key: ValueKey<String>('location-overview-footer-${selectedPlain.id}'),
      children: [
        Expanded(
          child: CommonButton(
            label: '수정',
            icon: Icons.edit_location_alt_rounded,
            onPressed: () => _handleEditPlainText(context, target: selectedPlain),
            variant: CommonButtonVariant.secondary,
            haptic: CommonHaptic.selection,
            expand: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CommonButton(
            label: '삭제',
            icon: Icons.delete_forever_rounded,
            onPressed: () => _handleDelete(context),
            variant: CommonButtonVariant.destructive,
            haptic: CommonHaptic.medium,
            expand: true,
          ),
        ),
      ],
    );
  }

  Widget _buildOverview(
    BuildContext context, {
    required LocationState state,
    required String currentArea,
    required List<LocationModel> allInArea,
    required List<LocationModel> visibleSingles,
    required Map<String, LocationModel> parentByKey,
    required Map<String, List<LocationModel>> groupedChildren,
    required Map<String, String> groupDisplayNameByKey,
    required Set<String> visibleGroupKeys,
  }) {
    final tokens = CommonUiTheme.of(context);
    final allSingles = allInArea.where((loc) {
      final type = loc.type;
      return type == null || type == 'single';
    }).toList();
    final allGroupKeys = <String>{
      ...parentByKey.keys,
      ...groupedChildren.keys,
    };
    final totalOverviewCount = allSingles.length + allGroupKeys.length;
    final visibleCount =
        (_filter == 'composite' ? 0 : visibleSingles.length) + visibleGroupKeys.length;
    final initialLoading = state.isLoading && allInArea.isEmpty;
    final selectedId = state.selectedLocationId;
    LocationModel? selectedPlain;
    if (selectedId != null && _filter != 'composite') {
      for (final loc in visibleSingles) {
        if (loc.id == selectedId) {
          selectedPlain = loc;
          break;
        }
      }
    }
    final validSelectionIds = <String>{
      if (_filter != 'composite') ...visibleSingles.map((e) => e.id),
    };
    _scheduleSelectionValidation(
      state: state,
      validIds: validSelectionIds,
      reason: _query.trim().isEmpty ? 'scope_changed' : 'filtered_out',
    );

    final bodyKey = visibleCount == 0
        ? 'location-overview-empty-${_filter}_${_query.trim()}'
        : 'location-overview-list-${_filter}_${_query.trim()}';

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: _buildOverviewToolbar(
                context,
                canCreate: currentArea.isNotEmpty,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: OpsDockStatusSegments<String>(
                selected: _filter,
                items: [
                  OpsDockStatusSegmentItem<String>(
                    value: 'all',
                    label: '전체',
                    count: totalOverviewCount,
                    color: tokens.accent,
                  ),
                  OpsDockStatusSegmentItem<String>(
                    value: 'composite',
                    label: '복합',
                    count: allGroupKeys.length,
                    color: tokens.info,
                  ),
                ],
                onSelected: _setFilter,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _query.trim().isEmpty
                      ? '$visibleCount개 표시'
                      : '$visibleCount개 표시 · 전체 $totalOverviewCount개',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
            const SizedBox(height: 7),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                child: OpsDockResultSwitcher(
                  child: visibleCount == 0
                      ? _LocationDockEmptyState(
                          key: ValueKey<String>(bodyKey),
                          icon: allInArea.isEmpty
                              ? Icons.add_location_alt_rounded
                              : Icons.search_off_rounded,
                          title: allInArea.isEmpty
                              ? '현재 지역에 주차 구역이 없습니다'
                              : '일치하는 구역이 없습니다',
                          message: allInArea.isEmpty
                              ? '부모 구역을 추가해 현장 공간 구조를 등록하세요.'
                              : '검색 또는 보기 조건을 조정하세요.',
                          action: allInArea.isEmpty
                              ? CommonButton(
                                  label: '구역 추가',
                                  icon: Icons.add_location_alt_rounded,
                                  onPressed: currentArea.isEmpty
                                      ? null
                                      : () => _handleAddParent(context),
                                  variant: CommonButtonVariant.primary,
                                  haptic: CommonHaptic.selection,
                                )
                              : _query.trim().isNotEmpty
                                  ? CommonButton(
                                      label: '검색 초기화',
                                      icon: Icons.restart_alt_rounded,
                                      onPressed: _clearQuery,
                                      variant: CommonButtonVariant.secondary,
                                      haptic: CommonHaptic.selection,
                                    )
                                  : CommonButton(
                                      label: '전체 보기',
                                      icon: Icons.grid_view_rounded,
                                      onPressed: () => _setFilter('all'),
                                      variant: CommonButtonVariant.secondary,
                                      haptic: CommonHaptic.selection,
                                    ),
                        )
                      : OpsDockListSurface(
                          key: ValueKey<String>(bodyKey),
                          child: _buildOverviewList(
                            state: state,
                            visibleSingles: _filter == 'composite'
                                ? const <LocationModel>[]
                                : visibleSingles,
                            parentByKey: parentByKey,
                            groupedChildren: groupedChildren,
                            groupDisplayNameByKey: groupDisplayNameByKey,
                            visibleGroupKeys: visibleGroupKeys,
                          ),
                        ),
                ),
              ),
            ),
            OpsDockContextFooterTransition(
              child: _buildOverviewFooter(context, selectedPlain),
            ),
          ],
        ),
        OpsDockLoadingOverlay(loading: initialLoading),
      ],
    );
  }

  Widget _buildOverviewList({
    required LocationState state,
    required List<LocationModel> visibleSingles,
    required Map<String, LocationModel> parentByKey,
    required Map<String, List<LocationModel>> groupedChildren,
    required Map<String, String> groupDisplayNameByKey,
    required Set<String> visibleGroupKeys,
  }) {
    final tokens = CommonUiTheme.of(context);
    final entries = <Widget>[];
    final sortedSingles = [...visibleSingles]
      ..sort((a, b) => a.locationName.compareTo(b.locationName));
    if (sortedSingles.isNotEmpty) {
      entries.add(const _LocationListSectionLabel(label: '단일 주차 구역'));
      for (final loc in sortedSingles) {
        entries.add(_buildPlainLocationRow(loc, state));
      }
    }

    final sortedGroupKeys = visibleGroupKeys.toList()
      ..sort((a, b) {
        final at = groupDisplayNameByKey[a] ?? a;
        final bt = groupDisplayNameByKey[b] ?? b;
        return at.compareTo(bt);
      });
    if (sortedGroupKeys.isNotEmpty) {
      entries.add(const _LocationListSectionLabel(label: '복합 주차 구역'));
      for (final key in sortedGroupKeys) {
        final title = groupDisplayNameByKey[key] ?? key;
        final children = groupedChildren[key] ?? const <LocationModel>[];
        final parent = parentByKey[key];
        entries.add(
          OpsDockSelectableRowSurface(
            selected: false,
            selectionColor: tokens.accent,
            selectedContainer: tokens.accentContainer,
            onTap: () => _openFocusedParent(
              key,
              state,
              parentId: parent?.id ?? '',
              title: title,
            ),
            child: _buildParentNavigationRowContent(
              title: title,
              parent: parent,
              children: children,
            ),
          ),
        );
      }
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: entries.length,
      separatorBuilder: (context, index) => Divider(
        height: 1,
        thickness: 1,
        color: tokens.borderSubtle,
      ),
      itemBuilder: (context, index) => entries[index],
    );
  }

  Widget _buildPlainLocationRow(LocationModel loc, LocationState state) {
    final tokens = CommonUiTheme.of(context);
    final selected = state.selectedLocationId == loc.id;
    return OpsDockSelectableRowSurface(
      selected: selected,
      selectionColor: tokens.accent,
      selectedContainer: tokens.accentContainer,
      onTap: () {
        HapticFeedback.selectionClick();
        state.toggleLocationSelection(loc.id);
        _log(
          selected
              ? 'plain_location_deselected id=${loc.id}'
              : 'plain_location_selected id=${loc.id}',
        );
      },
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.locationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 3),
                Text(
                  loc.capacity > 0 ? '공간 ${loc.capacity}대' : '공간 미지정',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _LocationSelectionIcon(selected: selected),
        ],
      ),
    );
  }

  Widget _buildParentNavigationRowContent({
    required String title,
    required LocationModel? parent,
    required List<LocationModel> children,
  }) {
    final tokens = CommonUiTheme.of(context);
    final totalCapacity = children.fold<int>(0, (sum, loc) => sum + loc.capacity);
    final grid = parent?.parkingGrid;
    final meta = <String>[
      '자식 ${children.length}',
      '공간 $totalCapacity대',
      if (grid != null) '${grid.rows}×${grid.cols}',
      if (grid == null) '도면 없음',
    ].join(' · ');
    return Row(
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '부모',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tokens.info,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                meta,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.arrow_forward_ios_rounded,
          size: 16,
          color: tokens.iconSecondary,
        ),
      ],
    );
  }

  Widget _buildParentFocus(
    BuildContext context, {
    required LocationState state,
    required String groupKey,
    required String groupName,
    required LocationModel? parent,
    required List<LocationModel> children,
  }) {
    final tokens = CommonUiTheme.of(context);
    final grid = parent?.parkingGrid;
    final selectedId = state.selectedLocationId;
    LocationModel? selectedChild;
    for (final child in children) {
      if (child.id == selectedId) {
        selectedChild = child;
        break;
      }
    }
    final validSelectionIds = children.map((e) => e.id).toSet();
    _scheduleSelectionValidation(
      state: state,
      validIds: validSelectionIds,
      reason: 'focus_scope_changed',
    );
    final childrenById = <String, LocationModel>{
      for (final child in children) child.id: child,
    };
    final overlays = <ChildRegionOverlay>[];
    for (final child in children) {
      final rect = child.childRect;
      if (rect == null) continue;
      final isSelected = selectedChild?.id == child.id;
      if (_showOnlySelectedChild && selectedChild != null && !isSelected) {
        continue;
      }
      overlays.add(
        ChildRegionOverlay(
          id: child.id,
          rect: rect,
          label: child.locationName.trim(),
          isSelected: isSelected,
          useEffectiveShape: !child.isTowerChild,
          effectiveParkingAreaIds: _childAreaIds(child).toSet(),
        ),
      );
    }
    final childSlotsToLabel =
        selectedChild != null && _showSelectedChildSlotNumbers
            ? selectedChild.childSlots
            : const <ChildSlot>[];
    final totalCapacity = children.fold<int>(0, (sum, child) => sum + child.capacity);
    final emptyCells = grid == null ? null : _countEmptyCells(grid);
    final parkingAreas = grid == null ? null : _countParkingAreas(grid);
    final initialLoading = state.isLoading && children.isEmpty && parent == null;

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 0),
              child: Row(
                children: [
                  CommonIconButton(
                    icon: Icons.add_location_alt_rounded,
                    tooltip: '자식 구역 추가',
                    onPressed: parent == null
                        ? null
                        : () => _handleAddChild(context, parent),
                    haptic: CommonHaptic.selection,
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(width: 4),
                  CommonIconButton(
                    icon: Icons.edit_location_alt_rounded,
                    tooltip: '부모 구역 수정',
                    onPressed: parent?.parkingGrid == null
                        ? null
                        : () => _handleEditParent(
                              context,
                              targetParent: parent,
                            ),
                    haptic: CommonHaptic.selection,
                    size: 40,
                    iconSize: 20,
                  ),
                  const SizedBox(width: 4),
                  CommonIconButton(
                    icon: Icons.refresh_rounded,
                    tooltip: '새로고침',
                    onPressed: _refreshing ? null : () => _handleRefresh(context),
                    loading: _refreshing,
                    haptic: CommonHaptic.selection,
                    size: 40,
                    iconSize: 20,
                  ),
                  const Spacer(),
                  PopupMenuButton<String>(
                    tooltip: '부모 구역 작업',
                    enabled: parent != null,
                    onSelected: (value) {
                      if (value == 'delete' && parent != null) {
                        unawaited(
                          _handleDelete(
                            context,
                            targetId: parent.id,
                            closeFocusedOnSuccess: true,
                          ),
                        );
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem<String>(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_forever_rounded, size: 18),
                            SizedBox(width: 9),
                            Expanded(child: Text('부모 구역 삭제')),
                          ],
                        ),
                      ),
                    ],
                    child: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tokens.surface,
                        borderRadius: BorderRadius.circular(CommonUiShapes.control),
                        border: Border.all(color: tokens.borderSubtle),
                      ),
                      alignment: Alignment.center,
                      child: Icon(
                        Icons.more_horiz_rounded,
                        color: parent == null
                            ? tokens.iconDisabled
                            : tokens.iconSecondary,
                        size: 21,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                key: PageStorageKey<String>('location-focus-$groupKey'),
                padding: const EdgeInsets.fromLTRB(10, 0, 10, 8),
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Parking Grid',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                      Text(
                        '자식 ${children.length} · 공간 $totalCapacity대',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: tokens.textSecondary,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Expanded(
                        child: CommonButton(
                          label: '선택 영역만',
                          icon: Icons.center_focus_strong_rounded,
                          selected:
                              selectedChild != null && _showOnlySelectedChild,
                          onPressed: selectedChild == null
                              ? null
                              : () => _workspace.setShowOnlySelectedChild(
                                    !_showOnlySelectedChild,
                                    source: 'grid_control',
                                  ),
                          variant: CommonButtonVariant.secondary,
                          haptic: CommonHaptic.selection,
                          expand: true,
                          minHeight: 36,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: CommonButton(
                          label: '슬롯 번호',
                          icon: Icons.tag_rounded,
                          selected: selectedChild != null &&
                              _showSelectedChildSlotNumbers,
                          onPressed: selectedChild == null
                              ? null
                              : () => _workspace.setShowSelectedChildSlotNumbers(
                                    !_showSelectedChildSlotNumbers,
                                    source: 'grid_control',
                                  ),
                          variant: CommonButtonVariant.secondary,
                          haptic: CommonHaptic.selection,
                          expand: true,
                          minHeight: 36,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  OpsDockListSurface(
                    child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: grid == null
                          ? _LocationGridMissingState(parentName: groupName)
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${grid.rows}×${grid.cols} · 빈칸 ${emptyCells ?? 0} · 주차면적 ${parkingAreas ?? 0}',
                                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                        color: tokens.textSecondary,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 9),
                                ParkingGridPreview(
                                  grid: grid,
                                  maxExtent: 360,
                                  showLegend: true,
                                  showChildRegions: true,
                                  childRegions: overlays,
                                  showChildRegionLabels: true,
                                  showAllChildRegionLabels: false,
                                  showChildSlotNumbers: selectedChild != null &&
                                      _showSelectedChildSlotNumbers,
                                  childSlotsToLabel: childSlotsToLabel,
                                  onTapChildRegion: (id) {
                                    final child = childrenById[id];
                                    if (child == null) {
                                      _log('grid_child_tap_ignored id=$id reason=missing');
                                      return;
                                    }
                                    _selectFocusedChild(
                                      child,
                                      state,
                                      source: 'grid',
                                    );
                                  },
                                ),
                              ],
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (children.isEmpty)
                    _LocationDockEmptyState(
                      key: const ValueKey<String>('location-focus-empty'),
                      icon: Icons.subdirectory_arrow_right_rounded,
                      title: '등록된 자식 구역이 없습니다',
                      message: parent == null
                          ? '부모 구역 정보를 확인하세요.'
                          : '현재 부모 구역에 자식 구역을 추가할 수 있습니다.',
                      action: parent == null
                          ? null
                          : CommonButton(
                              label: '자식 구역 추가',
                              icon: Icons.add_location_alt_rounded,
                              onPressed: () => _handleAddChild(context, parent),
                              variant: CommonButtonVariant.secondary,
                              haptic: CommonHaptic.selection,
                            ),
                    )
                  else
                    _buildSelectedChildInspection(
                      context,
                      selectedChild,
                      groupName: groupName,
                    ),
                ],
              ),
            ),
            OpsDockContextFooterTransition(
              child: _buildFocusedChildFooter(context, selectedChild),
            ),
          ],
        ),
        OpsDockLoadingOverlay(loading: initialLoading),
      ],
    );
  }

  Widget _buildSelectedChildInspection(
    BuildContext context,
    LocationModel? selectedChild, {
    required String groupName,
  }) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final child = selectedChild;
    final summary = child == null ? '' : _slotSummaryText(child.childSlots);
    final rect = child?.childRect;
    final metadata = child == null
        ? ''
        : <String>[
            if (child.isTowerChild) '타워',
            if (child.capacity > 0) '공간 ${child.capacity}대',
            if (rect != null) '영역 ${rect.height}×${rect.width}',
          ].join(' · ');
    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (childWidget, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0, .05),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: slide, child: childWidget),
          );
        },
        child: child == null
            ? const SizedBox.shrink(
                key: ValueKey<String>('location-child-inspection-none'),
              )
            : OpsDockListSurface(
                key: ValueKey<String>('location-child-inspection-${child.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(11),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: tokens.accentContainer.withOpacity(.72),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: tokens.accent.withOpacity(.32),
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          child.isTowerChild
                              ? Icons.apartment_rounded
                              : Icons.local_parking_rounded,
                          size: 19,
                          color: tokens.accent,
                        ),
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              child.locationName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: tokens.textPrimary,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              groupName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: tokens.textSecondary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            if (metadata.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                metadata,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: tokens.accent,
                                      fontWeight: FontWeight.w700,
                                      height: 1.25,
                                    ),
                              ),
                            ],
                            if (summary.isNotEmpty) ...[
                              const SizedBox(height: 3),
                              Text(
                                summary,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: tokens.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      height: 1.25,
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  Widget _buildFocusedChildFooter(
    BuildContext context,
    LocationModel? selectedChild,
  ) {
    if (selectedChild == null) {
      return const SizedBox.shrink(
        key: ValueKey<String>('location-focus-footer-none'),
      );
    }
    return OpsDockContextFooter(
      key: const ValueKey<String>('location-focus-footer-selected'),
      children: [
        Expanded(
          child: CommonButton(
            label: '수정',
            icon: Icons.edit_location_alt_rounded,
            onPressed: selectedChild.childRect == null
                ? null
                : () => _handleEditChild(context),
            variant: CommonButtonVariant.secondary,
            haptic: CommonHaptic.selection,
            expand: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: CommonButton(
            label: '삭제',
            icon: Icons.delete_forever_rounded,
            onPressed: () => _handleDelete(context),
            variant: CommonButtonVariant.destructive,
            haptic: CommonHaptic.medium,
            expand: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _workspace,
      builder: (context, _) {
        final locationState = context.watch<LocationState>();
        final currentArea = context.watch<AreaState>().currentArea.trim();
        if (_lastArea == null) {
          _lastArea = currentArea;
        } else if (_lastArea != currentArea) {
          final previous = _lastArea;
          _lastArea = currentArea;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            context.read<LocationState>().clearSelection();
            _workspace.reset(source: 'area_changed_${previous}_to_$currentArea');
            _log('area_changed from=${previous ?? '-'} to=$currentArea');
          });
        }

        final allInArea = locationState.locations
            .where((location) => location.area.trim() == currentArea)
            .toList();
        final allParents = allInArea.where(_isCompositeParent).toList();
        final allChildren = allInArea.where(_isCompositeChild).toList();
        final allSingles = allInArea.where((loc) {
          final type = loc.type;
          return type == null || type == 'single';
        }).toList();
        final parentByKey = <String, LocationModel>{
          for (final parent in allParents) _nameKey(parent.locationName): parent,
        };
        final parentById = <String, LocationModel>{
          for (final parent in allParents) parent.id: parent,
        };
        final groupDisplayNameByKey = <String, String>{
          for (final parent in allParents)
            _nameKey(parent.locationName): _normalizeName(parent.locationName),
        };
        final groupedChildren = <String, List<LocationModel>>{};
        for (final child in allChildren) {
          final parentName = _resolvedParentName(child, parentById);
          if (parentName.isEmpty) {
            groupedChildren.putIfAbsent(_miscGroupKey, () => <LocationModel>[])
              ..add(child);
            groupDisplayNameByKey.putIfAbsent(_miscGroupKey, () => '기타');
            continue;
          }
          final key = _nameKey(parentName);
          groupedChildren.putIfAbsent(key, () => <LocationModel>[]).add(child);
          groupDisplayNameByKey.putIfAbsent(
            key,
            () => _normalizeName(parentName),
          );
        }

        final visibleSingles =
            allSingles.where(_matchesLocationQuery).toList();
        final allGroupKeys = <String>{
          ...parentByKey.keys,
          ...groupedChildren.keys,
        };
        final visibleGroupKeys = <String>{};
        if (_query.trim().isEmpty) {
          visibleGroupKeys.addAll(allGroupKeys);
        } else {
          for (final key in allGroupKeys) {
            final parentMatches = parentByKey[key] != null &&
                _matchesLocationQuery(parentByKey[key]!);
            final childMatches = (groupedChildren[key] ?? const <LocationModel>[])
                .any(_matchesLocationQuery);
            if (parentMatches || childMatches) {
              visibleGroupKeys.add(key);
            }
          }
        }

        final focusedKey = _focusedParentKey;
        if (focusedKey != null) {
          _scheduleFocusValidation(
            focusedKey: focusedKey,
            validGroupKeys: allGroupKeys,
          );
        }
        final effectiveFocusedKey =
            focusedKey != null && allGroupKeys.contains(focusedKey)
                ? focusedKey
                : null;
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        final Widget activeWorkspace;
        if (effectiveFocusedKey == null) {
          activeWorkspace = KeyedSubtree(
            key: const ValueKey<String>('location-overview-workspace'),
            child: _buildOverview(
              context,
              state: locationState,
              currentArea: currentArea,
              allInArea: allInArea,
              visibleSingles: visibleSingles,
              parentByKey: parentByKey,
              groupedChildren: groupedChildren,
              groupDisplayNameByKey: groupDisplayNameByKey,
              visibleGroupKeys: visibleGroupKeys,
            ),
          );
        } else {
          activeWorkspace = KeyedSubtree(
            key: const ValueKey<String>('location-parent-focus-workspace'),
            child: _buildParentFocus(
              context,
              state: locationState,
              groupKey: effectiveFocusedKey,
              groupName: groupDisplayNameByKey[effectiveFocusedKey] ??
                  effectiveFocusedKey,
              parent: parentByKey[effectiveFocusedKey],
              children: [
                ...(groupedChildren[effectiveFocusedKey] ??
                    const <LocationModel>[]),
              ]..sort((a, b) => a.locationName.compareTo(b.locationName)),
            ),
          );
        }

        return PopScope(
          canPop: effectiveFocusedKey == null,
          onPopInvoked: (didPop) {
            if (didPop || effectiveFocusedKey == null) return;
            _closeFocusedParent(source: 'system_back');
          },
          child: AnimatedSwitcher(
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 230),
            reverseDuration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 210),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              if (reduceMotion) return child;
              final isFocus = child.key ==
                  const ValueKey<String>('location-parent-focus-workspace');
              final position = Tween<Offset>(
                begin: isFocus
                    ? const Offset(.075, 0)
                    : const Offset(-.035, 0),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                ),
              );
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: position,
                  child: child,
                ),
              );
            },
            child: activeWorkspace,
          ),
        );
      },
    );
  }
}

class _LocationListSectionLabel extends StatelessWidget {
  const _LocationListSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(11, 8, 11, 7),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _LocationSelectionIcon extends StatelessWidget {
  const _LocationSelectionIcon({required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      switchInCurve: CommonUiMotion.enter,
      switchOutCurve: CommonUiMotion.exit,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: animation, child: child),
      ),
      child: Icon(
        selected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
        key: ValueKey<bool>(selected),
        size: 19,
        color: selected ? tokens.accent : tokens.iconSecondary,
      ),
    );
  }
}

class _LocationDockEmptyState extends StatelessWidget {
  const _LocationDockEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: tokens.iconSecondary),
            const SizedBox(height: 9),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 5),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
            ),
            if (action != null) ...[
              const SizedBox(height: 12),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _LocationGridMissingState extends StatelessWidget {
  const _LocationGridMissingState({required this.parentName});

  final String parentName;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.grid_off_rounded, color: tokens.danger, size: 20),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            '$parentName의 parkingGrid가 없습니다. 저장 상태 또는 마이그레이션 결과를 확인하세요.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
          ),
        ),
      ],
    );
  }
}
