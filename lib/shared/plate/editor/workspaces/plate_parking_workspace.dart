import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/location/applications/location_state.dart';
import '../../../../features/location/domain/models/grid_rect.dart';
import '../../../../features/location/domain/models/location_model.dart';
import '../../../../features/location/domain/models/parking_grid_model.dart';
import '../../../../features/selector/application/dev_auth.dart';
import '../../../parking_dot_map/effective_child_region_geometry.dart';
import '../../../parking_dot_map/parking_status_dot_map_surface.dart';
import '../../../parking_spatial/parking_spatial_geometry.dart';
import '../../../parking_spatial/parking_spatial_transition.dart';
import '../../domain/repositories/plate_repository.dart';
import '../domain/plate_parking_area_configuration.dart';
import '../domain/plate_parking_display.dart';
import '../widgets/plate_parking_parent_selector.dart';
import '../widgets/plate_parking_plain_selector.dart';

enum _BlockedSlotKind { parked, departureRequest }

enum _SpatialSlotState {
  empty,
  occupied,
  departureRequest,
  current,
  selected,
  recommended,
}

class _ViewRow {
  const _ViewRow({required this.location});

  final String location;
}

class _ParkingSelectionData {
  const _ParkingSelectionData({
    required this.parent,
    required this.child,
    required this.slotNo,
  });

  final String parent;
  final String child;
  final int slotNo;
}

class _ParkingRecommendation {
  const _ParkingRecommendation({
    required this.child,
    required this.slot,
  });

  final LocationModel child;
  final ChildSlot slot;
}

class _ResolvedChildRegion {
  const _ResolvedChildRegion({
    required this.child,
    required this.nominalRect,
    required this.effectivePath,
    required this.hitRect,
    required this.freeCount,
    required this.capacity,
    required this.enabled,
    required this.recommended,
    required this.current,
    required this.selected,
  });

  final LocationModel child;
  final Rect nominalRect;
  final Path effectivePath;
  final Rect hitRect;
  final int freeCount;
  final int capacity;
  final bool enabled;
  final bool recommended;
  final bool current;
  final bool selected;
}

class _ResolvedSpatialSlot {
  const _ResolvedSpatialSlot({
    required this.slot,
    required this.visualRect,
    required this.hitRect,
    required this.state,
  });

  final ChildSlot slot;
  final Rect visualRect;
  final Rect hitRect;
  final _SpatialSlotState state;
}

class PlateParkingWorkspace extends StatefulWidget {
  const PlateParkingWorkspace({
    super.key,
    required this.currentLocation,
    required this.onLocationApplied,
    required this.onExit,
    this.onInvalidAreaConfiguration,
    this.preferredParkingAreas = const <String>[],
    this.onClearLocation,
    this.onDebug,
    this.areaOverride,
  });

  final String currentLocation;
  final ValueChanged<String> onLocationApplied;
  final VoidCallback onExit;
  final VoidCallback? onInvalidAreaConfiguration;
  final List<String> preferredParkingAreas;
  final VoidCallback? onClearLocation;
  final ValueChanged<String>? onDebug;
  final String? areaOverride;

  @override
  State<PlateParkingWorkspace> createState() => _PlateParkingWorkspaceState();
}

class _PlateParkingWorkspaceState extends State<PlateParkingWorkspace>
    with SingleTickerProviderStateMixin {
  final GlobalKey _rootKey = GlobalKey();
  late final AnimationController _focusController;
  String _currentLocation = '';
  String? _selectedParentName;
  String? _recentParentName;
  String _loadedArea = '';
  bool _occupancyLoading = false;
  String? _occupancyError;
  Map<String, _BlockedSlotKind> _blockedByLocation =
      <String, _BlockedSlotKind>{};
  LocationModel? _focusedParent;
  LocationModel? _focusedChild;
  Rect? _focusSourceRect;
  Rect? _focusTargetRect;
  bool _focusClosing = false;
  String? _towerAutoAssigningChildKey;
  bool _debugDialogShowing = false;
  final List<String> _debugLines = <String>[];
  String _lastParkingDisplayDebugSignature = '';
  String _lastAreaConfigurationSignature = '';
  bool _invalidAreaConfigurationHandling = false;

  @override
  void initState() {
    super.initState();
    _currentLocation = widget.currentLocation.trim();
    _focusController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 340),
      reverseDuration: const Duration(milliseconds: 340),
    );
  }

  @override
  void didUpdateWidget(covariant PlateParkingWorkspace oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.currentLocation != widget.currentLocation) {
      _currentLocation = widget.currentLocation.trim();
    }
    if (oldWidget.areaOverride != widget.areaOverride) {
      _syncArea();
    }
  }

  String _effectiveArea() {
    final override = widget.areaOverride?.trim() ?? '';
    if (override.isNotEmpty) return override;
    return context.read<AreaState>().currentArea.trim();
  }

  void _syncArea() {
    final area = _effectiveArea();
    if (area == _loadedArea) return;
    _loadedArea = area;
    _selectedParentName = null;
    _recentParentName = null;
    _blockedByLocation = <String, _BlockedSlotKind>{};
    _occupancyLoading = false;
    _occupancyError = null;
    _lastAreaConfigurationSignature = '';
    _invalidAreaConfigurationHandling = false;
    if (area.isNotEmpty) {
      unawaited(_reloadOccupancy());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncArea();
  }

  @override
  void dispose() {
    _focusController.dispose();
    super.dispose();
  }

  static String _normalizeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

  static bool _isCompositeChild(LocationModel location) {
    return location.isCompositeChild || (location.parent ?? '').trim().isNotEmpty;
  }

  static int? _parseFirstInt(String raw) {
    final match = RegExp(r'(\d+)').firstMatch(raw);
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  static List<String> _splitLocation(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return const <String>[];
    return value
        .split(' - ')
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList(growable: false);
  }

  static _ParkingSelectionData? _selectionData(String raw) {
    final segments = _splitLocation(raw);
    if (segments.length < 3) return null;
    final slotNo = _parseFirstInt(segments[2]);
    if (slotNo == null || slotNo <= 0) return null;
    return _ParkingSelectionData(
      parent: segments[0],
      child: segments[1],
      slotNo: slotNo,
    );
  }

  static String _slotKey(String parent, String child, int slotNo) {
    return '${_nameKey(parent)}|${_nameKey(child)}|$slotNo';
  }

  static String _normalizeParkingAreaCategory(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll('×', 'x')
        .replaceAll(RegExp(r'\s+'), '');
    if (normalized.isEmpty) return '';
    final ev = normalized.contains('전기차') ||
        normalized.contains('전기') ||
        normalized.contains('ev') ||
        normalized.contains('electric');
    final pregnant = normalized.contains('임산부') ||
        normalized.contains('pregnant') ||
        normalized.contains('maternity');
    final disabled = normalized.contains('장애인') ||
        normalized.contains('disabled') ||
        normalized.contains('accessible') ||
        normalized.contains('handicap');
    final extendedB = normalized.contains('확장형b') ||
        normalized.contains('확장b') ||
        normalized.contains('extendedb') ||
        normalized.contains('expandedb');
    final extendedA = normalized.contains('확장형a') ||
        normalized.contains('확장a') ||
        normalized.contains('extendeda') ||
        normalized.contains('expandeda');
    final extended = extendedA ||
        extendedB ||
        normalized.contains('확장형') ||
        normalized.contains('확장') ||
        normalized.contains('extended') ||
        normalized.contains('expand');
    final standard = normalized.contains('일반형') ||
        normalized.contains('일반') ||
        normalized.contains('standard') ||
        normalized.contains('normal') ||
        normalized.contains('general');
    final compact = normalized.contains('경형') ||
        normalized.contains('경차') ||
        normalized.contains('compact') ||
        normalized.contains('light') ||
        normalized.contains('small');
    if (ev) {
      if (extendedB) return '전기차 확장형 B';
      if (extendedA || extended) return '전기차 확장형 A';
      if (standard) return '전기차 일반형';
      if (compact) return '전기차 경형';
      return '전기차';
    }
    if (pregnant) {
      if (extendedB) return '임산부 배려 확장형 B';
      return '임산부 배려 확장형 A';
    }
    if (disabled) {
      if (extendedB) return '장애인 확장형 B';
      if (extendedA || extended) return '장애인 확장형 A';
      if (standard) return '장애인 일반형';
      return '장애인';
    }
    if (extendedB) return '확장형 B';
    if (extendedA) return '확장형 A';
    if (extended) return '확장형';
    if (standard) return '일반형';
    if (compact) return '경형';
    return value.trim();
  }

  static String _slotCategory(ChildSlot slot) {
    for (final value in <String>[
      slot.categoryLabel,
      slot.label,
      slot.category,
      slot.kind,
    ]) {
      final normalized = _normalizeParkingAreaCategory(value);
      if (normalized.isNotEmpty) return normalized;
    }
    return '';
  }

  void _debug(String message) {
    final line = '[PlateParkingWorkspace] $message';
    debugPrint(line);
    if (_debugLines.isEmpty || _debugLines.last != line) {
      _debugLines.add(line);
      if (_debugLines.length > 220) {
        _debugLines.removeRange(0, _debugLines.length - 220);
      }
    }
    widget.onDebug?.call(message);
  }

  String get _debugPrintCode => _debugLines
      .map((line) => 'debugPrint(${jsonEncode(line)});')
      .join('\n');

  void _recordParkingDisplayDebug({
    required String internal,
    required String visible,
    required bool isTower,
  }) {
    final signature = '$internal|$visible|$isTower';
    if (_lastParkingDisplayDebugSignature == signature) return;
    _lastParkingDisplayDebugSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastParkingDisplayDebugSignature != signature) return;
      _debug(
        'parking_display=header_resolved tower=$isTower internal=$internal visible=$visible towerSlotVisibility=${isTower ? 'hidden' : 'visible'}',
      );
    });
  }

  Future<void> _showDebugStatusDialog() async {
    if (_debugDialogShowing) return;
    final enabled = await DevAuth.isDevModeEnabled();
    if (!enabled || !mounted) return;
    setState(() => _debugDialogShowing = true);
    _debug(
      'parking_debug=status_dialog_open area=$_loadedArea currentLocation=${_currentLocation.trim()} towerAutoAssigning=${_towerAutoAssigningChildKey ?? ''}',
    );
    try {
      final code = _debugPrintCode;
      await StatusDialog.showSuccess(
        context,
        title: '주차 위치 디버그',
        description: _debugLines.join('\n'),
        copyText: code,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: Duration.zero,
        useCommonUi: true,
        awaitManualClose: true,
      );
    } finally {
      if (mounted) {
        setState(() => _debugDialogShowing = false);
      }
    }
  }

  void _reportAreaConfiguration(
    PlateParkingAreaConfiguration configuration,
  ) {
    final signature =
        '$_loadedArea|${configuration.mode.name}|${configuration.plainCount}|${configuration.diagramCount}';
    if (_lastAreaConfigurationSignature == signature) return;
    _lastAreaConfigurationSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _lastAreaConfigurationSignature != signature) return;
      _debug(
        'parking_area_configuration=resolved area=$_loadedArea mode=${configuration.mode.name} plainCount=${configuration.plainCount} diagramCount=${configuration.diagramCount}',
      );
    });
  }

  Future<void> _handleMixedAreaConfiguration(
    PlateParkingAreaConfiguration configuration,
  ) async {
    if (_invalidAreaConfigurationHandling || !mounted) return;
    _invalidAreaConfigurationHandling = true;
    _debug(
      'parking_area_configuration=invalid area=$_loadedArea mode=mixed plainCount=${configuration.plainCount} diagramCount=${configuration.diagramCount} action=warn_and_close_side_dock',
    );
    await HapticFeedback.mediumImpact();
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!mounted) return;
    await StatusDialog.showFailure(
      context,
      title: '주차구역 유형 충돌',
      description:
          '현재 지역에 텍스트형과 도면형 주차구역이 함께 등록되어 있습니다. 두 유형은 한 지역에서 동시에 사용할 수 없습니다. 구역 관리에서 하나의 유형으로 통일한 후 다시 시도해 주세요.',
      copyText: developerMode ? _debugPrintCode : null,
      copyButtonLabel: 'debugPrint 코드 복사',
      visibleDuration: Duration.zero,
      useCommonUi: true,
      awaitManualClose: true,
    );
    if (!mounted) return;
    _debug(
      'parking_area_configuration=warning_acknowledged area=$_loadedArea action=close_side_dock',
    );
    final onInvalid = widget.onInvalidAreaConfiguration;
    if (onInvalid != null) {
      onInvalid();
    } else {
      widget.onExit();
    }
  }

  Future<bool> _refreshOccupancy() async {
    final area = _loadedArea.trim();
    if (area.isEmpty || !mounted) return false;
    setState(() {
      _occupancyLoading = true;
      _occupancyError = null;
    });
    try {
      final repository = context.read<PlateRepository>();
      final locations = await Future.wait(<Future<List<String>>>[
        repository.fetchViewLocations(
          collectionName: 'parking_completed_view',
          area: area,
        ),
        repository.fetchViewLocations(
          collectionName: 'departure_requests_view',
          area: area,
        ),
      ]);
      final rows = locations
          .map(
            (items) => items
                .map((location) => _ViewRow(location: location))
                .toList(growable: false),
          )
          .toList(growable: false);
      final blocked = <String, _BlockedSlotKind>{};
      void apply(List<_ViewRow> input, _BlockedSlotKind kind) {
        for (final row in input) {
          final segments = _splitLocation(row.location);
          if (segments.length < 3) continue;
          final slotNo = _parseFirstInt(segments[2]);
          if (slotNo == null || slotNo <= 0) continue;
          blocked[_slotKey(segments[0], segments[1], slotNo)] = kind;
        }
      }
      apply(rows[0], _BlockedSlotKind.parked);
      apply(rows[1], _BlockedSlotKind.departureRequest);
      if (!mounted) return false;
      setState(() {
        _blockedByLocation = blocked;
        _occupancyLoading = false;
        _occupancyError = null;
      });
      _debug(
        'parking_spatial=occupancy_ready area=$area blocked=${blocked.length} source=view_firestore',
      );
      return true;
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _occupancyLoading = false;
        _occupancyError = error.toString();
      });
      _debug('parking_spatial=occupancy_error error=$error');
      return false;
    }
  }

  Future<void> _reloadOccupancy() async {
    await _refreshOccupancy();
  }

  List<String> _preferredCategories() {
    return widget.preferredParkingAreas
        .map(_normalizeParkingAreaCategory)
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }

  _ParkingRecommendation? _recommendationForChildren(
    String parentName,
    List<LocationModel> children,
  ) {
    final priorities = _preferredCategories();
    if (priorities.isEmpty) return null;
    final current = _selectionData(_currentLocation);
    for (var priorityIndex = 0;
        priorityIndex < priorities.length;
        priorityIndex++) {
      final priority = priorities[priorityIndex];
      final candidates = <_ParkingRecommendation>[];
      for (final child in children) {
        if (child.isTowerChild) continue;
        final slots = List<ChildSlot>.of(child.childSlots)
          ..sort((a, b) => a.no.compareTo(b.no));
        for (final slot in slots) {
          if (_slotCategory(slot) != priority) continue;
          final key = _slotKey(parentName, child.locationName, slot.no);
          final isCurrent = current != null &&
              _nameKey(current.parent) == _nameKey(parentName) &&
              _nameKey(current.child) == _nameKey(child.locationName) &&
              current.slotNo == slot.no;
          if (_blockedByLocation.containsKey(key) && !isCurrent) continue;
          candidates.add(
            _ParkingRecommendation(
              child: child,
              slot: slot,
            ),
          );
          break;
        }
      }
      if (candidates.isNotEmpty) {
        candidates.sort((a, b) {
          final slotCompare = a.slot.no.compareTo(b.slot.no);
          if (slotCompare != 0) return slotCompare;
          return a.child.locationName.compareTo(b.child.locationName);
        });
        return candidates.first;
      }
    }
    return null;
  }

  int _capacityOf(LocationModel child) {
    if (child.childSlots.isNotEmpty) return child.childSlots.length;
    return math.max(0, child.capacity);
  }

  int _freeCount(
    String parentName,
    LocationModel child,
  ) {
    final current = _selectionData(_currentLocation);
    final capacity = _capacityOf(child);
    if (capacity <= 0) return 0;
    var blocked = 0;
    if (child.childSlots.isNotEmpty) {
      for (final slot in child.childSlots) {
        final isCurrent = current != null &&
            _nameKey(current.parent) == _nameKey(parentName) &&
            _nameKey(current.child) == _nameKey(child.locationName) &&
            current.slotNo == slot.no;
        if (isCurrent) continue;
        if (_blockedByLocation.containsKey(
          _slotKey(parentName, child.locationName, slot.no),
        )) {
          blocked++;
        }
      }
    } else {
      for (var no = 1; no <= capacity; no++) {
        final isCurrent = current != null &&
            _nameKey(current.parent) == _nameKey(parentName) &&
            _nameKey(current.child) == _nameKey(child.locationName) &&
            current.slotNo == no;
        if (isCurrent) continue;
        if (_blockedByLocation.containsKey(
          _slotKey(parentName, child.locationName, no),
        )) {
          blocked++;
        }
      }
    }
    return math.max(0, capacity - blocked);
  }

  bool _isCurrentChild(String parentName, LocationModel child) {
    final current = _selectionData(_currentLocation);
    return current != null &&
        _nameKey(current.parent) == _nameKey(parentName) &&
        _nameKey(current.child) == _nameKey(child.locationName);
  }

  bool _isSelectedChild(String parentName, LocationModel child) {
    final assigningKey = _towerAutoAssigningChildKey;
    if (assigningKey == null || !child.isTowerChild) return false;
    return assigningKey ==
        '${_nameKey(parentName)}|${_nameKey(child.locationName)}';
  }

  int? _firstAvailableTowerSlot(
    String parentName,
    LocationModel child,
  ) {
    final capacity = _capacityOf(child);
    if (capacity <= 0) return null;
    for (var no = 1; no <= capacity; no++) {
      final key = _slotKey(parentName, child.locationName, no);
      if (!_blockedByLocation.containsKey(key)) return no;
    }
    return null;
  }

  int _blockedTowerSlotCount(
    String parentName,
    LocationModel child,
  ) {
    final capacity = _capacityOf(child);
    if (capacity <= 0) return 0;
    var count = 0;
    for (var no = 1; no <= capacity; no++) {
      if (_blockedByLocation.containsKey(
        _slotKey(parentName, child.locationName, no),
      )) {
        count++;
      }
    }
    return count;
  }

  Future<void> _towerAutoAssignSettle() async {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return;
    await Future<void>.delayed(const Duration(milliseconds: 170));
  }

  Future<void> _autoSelectTowerSlot(
    LocationModel parent,
    LocationModel child,
  ) async {
    if (!child.isTowerChild || _focusClosing || _focusedChild != null) return;
    if (_towerAutoAssigningChildKey != null) {
      _debug(
        'tower_auto_assign=ignored reason=already_running parent=${parent.locationName} child=${child.locationName}',
      );
      return;
    }
    final capacity = _capacityOf(child);
    if (capacity <= 0) {
      _debug(
        'tower_auto_assign=blocked reason=invalid_capacity parent=${parent.locationName} child=${child.locationName} capacity=$capacity',
      );
      HapticFeedback.selectionClick();
      return;
    }
    final assigningKey =
        '${_nameKey(parent.locationName)}|${_nameKey(child.locationName)}';
    setState(() => _towerAutoAssigningChildKey = assigningKey);
    HapticFeedback.selectionClick();
    _debug(
      'tower_auto_assign=start parent=${parent.locationName} child=${child.locationName} capacity=$capacity source=tower_tap policy=lowest_available_slot',
    );
    try {
      final current = _selectionData(_currentLocation);
      final sameTower = current != null &&
          _nameKey(current.parent) == _nameKey(parent.locationName) &&
          _nameKey(current.child) == _nameKey(child.locationName);
      if (sameTower &&
          current.slotNo > 0 &&
          current.slotNo <= capacity) {
        await _towerAutoAssignSettle();
        if (!mounted) return;
        _debug(
          'tower_auto_assign=resolved parent=${parent.locationName} child=${child.locationName} slot=${current.slotNo} resolution=keep_current_slot capacity=$capacity',
        );
        _selectSlot(parent.locationName, child, current.slotNo);
        return;
      }

      final refreshed = await _refreshOccupancy();
      if (!mounted) return;
      if (!refreshed) {
        _debug(
          'tower_auto_assign=blocked reason=occupancy_refresh_failed parent=${parent.locationName} child=${child.locationName} capacity=$capacity',
        );
        HapticFeedback.mediumImpact();
        return;
      }

      final slotNo = _firstAvailableTowerSlot(parent.locationName, child);
      final blockedCount = _blockedTowerSlotCount(
        parent.locationName,
        child,
      );
      if (slotNo == null) {
        _debug(
          'tower_auto_assign=blocked reason=no_available_slot parent=${parent.locationName} child=${child.locationName} capacity=$capacity blocked=$blockedCount sources=parking_completed_view+departure_requests_view',
        );
        HapticFeedback.mediumImpact();
        return;
      }

      final slotKey = _slotKey(
        parent.locationName,
        child.locationName,
        slotNo,
      );
      await _towerAutoAssignSettle();
      if (!mounted) return;
      _debug(
        'tower_auto_assign=resolved parent=${parent.locationName} child=${child.locationName} slot=$slotNo slotKey=$slotKey capacity=$capacity blocked=$blockedCount free=${math.max(0, capacity - blockedCount)} resolution=lowest_available_slot sources=parking_completed_view+departure_requests_view departure_request_counts_as_occupied=true',
      );
      _selectSlot(parent.locationName, child, slotNo);
    } finally {
      if (mounted && _towerAutoAssigningChildKey == assigningKey) {
        setState(() => _towerAutoAssigningChildKey = null);
      }
    }
  }

  String _fullLocation(String parent, LocationModel child, int slotNo) {
    ChildSlot? matched;
    for (final slot in child.childSlots) {
      if (slot.no == slotNo) {
        matched = slot;
        break;
      }
    }
    final label = matched?.label.trim() ?? '';
    final slotSegment = label.isEmpty
        ? '슬롯 $slotNo'
        : '슬롯 $slotNo · $label';
    return '$parent - ${child.locationName} - $slotSegment';
  }

  void _selectSlot(String parent, LocationModel child, int slotNo) {
    if (_focusClosing) return;
    final full = _fullLocation(parent, child, slotNo);
    final locations = context.read<LocationState>().locations;
    final display = plateParkingOverviewLocation(
      full,
      locations: locations,
    );
    HapticFeedback.mediumImpact();
    _debug(
      'parking_slot=selected parent=$parent child=${child.locationName} slot=$slotNo location=$full',
    );
    _debug(
      'parking_display=resolved tower=${child.isTowerChild} internal=$full visible=$display towerSlotVisibility=${child.isTowerChild ? 'hidden' : 'visible'}',
    );
    widget.onLocationApplied(full);
    _currentLocation = full;
    _debug('parking_slot=auto_applied location=$full');
    _debug('parking_dialog=close reason=slot_auto_apply location=$full');
    widget.onExit();
  }

  void _selectPlainLocation(LocationModel location) {
    if (_invalidAreaConfigurationHandling) return;
    final value = _normalizeName(location.locationName);
    if (value.isEmpty) return;
    HapticFeedback.mediumImpact();
    _debug(
      'parking_plain=selected area=$_loadedArea location=$value capacity=${location.capacity}',
    );
    widget.onLocationApplied(value);
    _currentLocation = value;
    _debug(
      'parking_location=auto_applied type=plain location=$value',
    );
    _debug(
      'parking_dialog=close reason=plain_auto_apply location=$value',
    );
    widget.onExit();
  }

  void _clearCurrentLocation() {
    if (_towerAutoAssigningChildKey != null) return;
    if (widget.onClearLocation == null || _currentLocation.isEmpty) return;
    final previous = _currentLocation;
    setState(() {
      _currentLocation = '';
    });
    widget.onClearLocation?.call();
    HapticFeedback.selectionClick();
    _debug('parking_location=cleared previous=$previous');
  }

  Rect? _globalRectToRoot(Rect globalRect) {
    final context = _rootKey.currentContext;
    if (context == null) return null;
    final renderObject = context.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final topLeft = renderObject.globalToLocal(globalRect.topLeft);
    final bottomRight = renderObject.globalToLocal(globalRect.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  Future<void> _openChild(
    LocationModel parent,
    LocationModel child,
    Rect globalSourceRect,
  ) async {
    if (_towerAutoAssigningChildKey != null) {
      _debug(
        'parking_child=ignored reason=tower_auto_assigning parent=${parent.locationName} child=${child.locationName}',
      );
      return;
    }
    if (child.isTowerChild) {
      await _autoSelectTowerSlot(parent, child);
      return;
    }
    if (_focusedChild != null || _focusClosing) return;
    final rootContext = _rootKey.currentContext;
    final rootObject = rootContext?.findRenderObject();
    if (rootObject is! RenderBox || !rootObject.hasSize) return;
    final sourceRect = _globalRectToRoot(globalSourceRect);
    if (sourceRect == null || sourceRect.isEmpty) return;
    final size = rootObject.size;
    final compact = size.width < 600;
    final horizontal = compact ? 10.0 : 22.0;
    final vertical = compact ? 10.0 : 18.0;
    final targetRect = Rect.fromLTWH(
      horizontal,
      vertical,
      math.max(220.0, size.width - horizontal * 2),
      math.max(280.0, size.height - vertical * 2),
    );
    setState(() {
      _focusedParent = parent;
      _focusedChild = child;
      _focusSourceRect = sourceRect;
      _focusTargetRect = targetRect;
    });
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _focusController.duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 340);
    _focusController.reverseDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 340);
    _focusController.value = 0;
    HapticFeedback.selectionClick();
    _debug(
      'parking_child=open parent=${parent.locationName} child=${child.locationName} source=${_rectDebug(sourceRect)} target=${_rectDebug(targetRect)} durationMs=${_focusController.duration?.inMilliseconds ?? 0}',
    );
    await _focusController.forward();
    if (!mounted) return;
    _debug(
      'parking_child=expanded parent=${parent.locationName} child=${child.locationName}',
    );
    unawaited(_reloadOccupancy());
  }

  Future<void> _closeFocus({required String reason}) async {
    if (_focusedChild == null || _focusClosing) return;
    _focusClosing = true;
    final parent = _focusedParent?.locationName ?? '';
    final child = _focusedChild?.locationName ?? '';
    _debug('parking_child=collapse_started parent=$parent child=$child reason=$reason');
    try {
      await _focusController.reverse();
    } finally {
      if (mounted) {
        setState(() {
          _focusedParent = null;
          _focusedChild = null;
          _focusSourceRect = null;
          _focusTargetRect = null;
        });
      }
      _focusClosing = false;
      _debug('parking_child=collapsed parent=$parent child=$child reason=$reason');
    }
  }

  static String _rectDebug(Rect rect) {
    return '${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)},${rect.width.toStringAsFixed(1)},${rect.height.toStringAsFixed(1)}';
  }

  static int _naturalCompare(String a, String b) {
    final left = RegExp(r'\d+|\D+')
        .allMatches(a.trim().toLowerCase())
        .map((match) => match.group(0) ?? '')
        .toList(growable: false);
    final right = RegExp(r'\d+|\D+')
        .allMatches(b.trim().toLowerCase())
        .map((match) => match.group(0) ?? '')
        .toList(growable: false);
    final count = math.min(left.length, right.length);
    for (var index = 0; index < count; index++) {
      final leftPart = left[index];
      final rightPart = right[index];
      final leftNumber = int.tryParse(leftPart);
      final rightNumber = int.tryParse(rightPart);
      final compare = leftNumber != null && rightNumber != null
          ? leftNumber.compareTo(rightNumber)
          : leftPart.compareTo(rightPart);
      if (compare != 0) return compare;
    }
    return left.length.compareTo(right.length);
  }

  List<LocationModel> _childrenFor(
    LocationModel parent,
    List<LocationModel> locations,
  ) {
    final parentKeys = <String>{
      _nameKey(parent.locationName),
      if (parent.id.trim().isNotEmpty) _nameKey(parent.id),
    };
    final result = locations
        .where(
          (location) =>
              _isCompositeChild(location) &&
              (parentKeys.contains(_nameKey(location.parent ?? '')) ||
                  parentKeys.contains(_nameKey(location.parentId ?? ''))),
        )
        .toList()
      ..sort((a, b) => _naturalCompare(a.locationName, b.locationName));
    return result;
  }

  Widget _buildHeader(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final current = _currentLocation.trim();
    final locations = context.watch<LocationState>().locations;
    final displayCurrent = plateParkingOverviewLocation(
      current,
      locations: locations,
    );
    final currentIsTower = plateParkingLocationIsTower(
      current,
      locations: locations,
    );
    _recordParkingDisplayDebug(
      internal: current,
      visible: displayCurrent,
      isTower: currentIsTower,
    );
    final canClear = current.isNotEmpty && widget.onClearLocation != null;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 9, 12, 9),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(Icons.local_parking_rounded, size: 18, color: tokens.accent),
          const SizedBox(width: 8),
          Expanded(
            child: AnimatedSwitcher(
              duration: (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
                  ? Duration.zero
                  : const Duration(milliseconds: 160),
              child: Text(
                current.isEmpty
                    ? '현재 주차 위치가 없습니다.'
                    : '현재 $displayCurrent',
                key: ValueKey<String>(displayCurrent),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ),
          ),
          ValueListenableBuilder<bool>(
            valueListenable: DevAuth.devModeEnabled,
            builder: (context, enabled, _) {
              if (!enabled) return const SizedBox.shrink();
              return IconButton(
                onPressed: _debugDialogShowing
                    ? null
                    : () => unawaited(_showDebugStatusDialog()),
                icon: const Icon(Icons.bug_report_outlined, size: 19),
              );
            },
          ),
          if (canClear) ...[
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _clearCurrentLocation,
              icon: const Icon(Icons.remove_circle_outline_rounded, size: 17),
              label: const Text('위치 사용 안 함'),
            ),
          ],
        ],
      ),
    );
  }

  void _selectParent(LocationModel parent) {
    if (_towerAutoAssigningChildKey != null) return;
    if (_focusedChild != null || _focusClosing) return;
    HapticFeedback.selectionClick();
    setState(() {
      _selectedParentName = parent.locationName;
      _recentParentName = parent.locationName;
    });
    _debug(
      'parking_parent=selected parent=${parent.locationName} area=$_loadedArea',
    );
    _debug(
      'parking_parent_stage=map parent=${parent.locationName} area=$_loadedArea',
    );
  }

  void _showParentSelector({required String reason}) {
    final previous = _selectedParentName?.trim() ?? '';
    if (_towerAutoAssigningChildKey != null) return;
    if (previous.isEmpty || _focusedChild != null || _focusClosing) return;
    HapticFeedback.selectionClick();
    setState(() => _selectedParentName = null);
    _debug(
      'parking_parent_stage=selector previous=$previous reason=$reason area=$_loadedArea',
    );
  }

  LocationModel? _selectedParent(List<LocationModel> parents) {
    final selectedKey = _nameKey(_selectedParentName ?? '');
    if (selectedKey.isEmpty) return null;
    for (final parent in parents) {
      if (_nameKey(parent.locationName) == selectedKey) return parent;
    }
    return null;
  }

  Widget _buildSelectedParentStage(
    BuildContext context,
    LocationModel parent,
    List<LocationModel> locations,
  ) {
    final tokens = CommonUiTheme.of(context);
    final children = _childrenFor(parent, locations);
    return Column(
      key: ValueKey<String>('parent_map:${parent.locationName}'),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(8, 6, 12, 6),
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
          ),
          child: Row(
            children: [
              IconButton(
                tooltip: '부모 구역 다시 선택',
                onPressed: () => _showParentSelector(reason: 'header'),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  parent.locationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${children.length}',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _SpatialParentMap(
            key: ValueKey<String>('parent:${parent.locationName}'),
            parent: parent,
            children: children,
            currentLocation: _currentLocation,
            occupancyLoading: _occupancyLoading,
            blockedByLocation: _blockedByLocation,
            freeCount: _freeCount,
            capacityOf: _capacityOf,
            recommendation: _recommendationForChildren(
              parent.locationName,
              children,
            ),
            isCurrentChild: _isCurrentChild,
            isSelectedChild: _isSelectedChild,
            onChildTap: _openChild,
            onDebug: _debug,
          ),
        ),
      ],
    );
  }

  Widget _buildDiagramMain(
    BuildContext context,
    List<LocationModel> locations,
    List<LocationModel> diagramParents,
  ) {
    final topLevels = diagramParents
        .where((parent) {
          final grid = parent.parkingGrid;
          return grid != null && grid.rows > 0 && grid.cols > 0;
        })
        .toList(growable: false)
      ..sort((a, b) => _naturalCompare(a.locationName, b.locationName));
    if (topLevels.isEmpty) {
      return _SpatialMessage(
        icon: Icons.map_outlined,
        title: '표시할 주차 공간이 없습니다.',
        message: '현재 지역의 도면형 주차구역에 사용할 수 있는 주차 그리드가 없습니다.',
        actionLabel: '닫기',
        onAction: widget.onExit,
      );
    }
    final selectedParent = _selectedParent(topLevels);
    if (_selectedParentName != null && selectedParent == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _selectedParentName == null) return;
        final missing = _selectedParentName!;
        setState(() => _selectedParentName = null);
        _debug(
          'parking_parent=selection_invalidated parent=$missing area=$_loadedArea',
        );
      });
    }
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 230),
      reverseDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(begin: .97, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: selectedParent == null
          ? PlateParkingParentSelector(
              key: const ValueKey<String>('parent_selector'),
              parents: topLevels,
              childrenForParent: (parent) => _childrenFor(parent, locations),
              recentParentName: _recentParentName,
              area: _loadedArea,
              onSelected: _selectParent,
              onDebug: _debug,
            )
          : _buildSelectedParentStage(context, selectedParent, locations),
    );
  }

  Widget _buildMain(
    BuildContext context,
    List<LocationModel> locations,
  ) {
    final configuration = PlateParkingAreaConfiguration.resolve(locations);
    _reportAreaConfiguration(configuration);
    switch (configuration.mode) {
      case PlateParkingAreaMode.mixed:
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          unawaited(_handleMixedAreaConfiguration(configuration));
        });
        return const _SpatialLoading();
      case PlateParkingAreaMode.plain:
        final plain = List<LocationModel>.of(configuration.plainLocations)
          ..sort((a, b) => _naturalCompare(a.locationName, b.locationName));
        if (_selectedParentName != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || _selectedParentName == null) return;
            setState(() => _selectedParentName = null);
          });
        }
        return PlateParkingPlainSelector(
          key: const ValueKey<String>('plain_selector'),
          locations: plain,
          currentLocation: _currentLocation,
          area: _loadedArea,
          onSelected: _selectPlainLocation,
          onDebug: _debug,
        );
      case PlateParkingAreaMode.diagram:
        return _buildDiagramMain(
          context,
          locations,
          configuration.diagramParents,
        );
      case PlateParkingAreaMode.empty:
        return _SpatialMessage(
          icon: Icons.info_outline_rounded,
          title: '사용할 주차 구역이 없습니다.',
          message: '현재 지역의 주차구역 구성을 확인해 주세요.',
          actionLabel: '닫기',
          onAction: widget.onExit,
        );
    }
  }

  Widget _buildFocusOverlay(BuildContext context) {
    final parent = _focusedParent;
    final child = _focusedChild;
    final source = _focusSourceRect;
    final target = _focusTargetRect;
    if (parent == null || child == null || source == null || target == null) {
      return const SizedBox.shrink();
    }
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Positioned.fill(
      child: ParkingSpatialSourceRectTransition(
        animation: _focusController,
        sourceRect: source,
        targetRect: target,
        reduceMotion: reduceMotion,
        closeSemanticsLabel: '${child.locationName} 닫기',
        onCloseRequested: (source) {
          unawaited(_closeFocus(reason: source));
        },
        onSystemPop: () {},
        onExpanded: () {
          _debug(
            'parking_child=transition_expanded parent=${parent.locationName} child=${child.locationName}',
          );
        },
        onCollapsed: () {
          _debug(
            'parking_child=transition_collapsed parent=${parent.locationName} child=${child.locationName}',
          );
        },
        onCollapseLifecycle: (info) {
          _debug(
            'parking_child=collapse_lifecycle parent=${parent.locationName} child=${child.locationName} expandedBeforeCollapse=${info.expandedBeforeCollapse} early=${info.earlyCollapse} maxProgress=${info.maxRawProgress.toStringAsFixed(3)}',
          );
        },
        builder: (context, progress, interactionEnabled) {
          return _SpatialChildFocus(
            key: ValueKey<String>(
              '${parent.locationName}|${child.locationName}',
            ),
            parent: parent,
            child: child,
            blockedByLocation: _blockedByLocation,
            currentLocation: _currentLocation,
            recommendation: _recommendationForChildren(
              parent.locationName,
              _childrenFor(
                parent,
                context
                    .read<LocationState>()
                    .locations
                    .where((location) => location.area.trim() == _loadedArea)
                    .toList(growable: false),
              ),
            ),
            occupancyLoading: _occupancyLoading,
            progress: progress,
            interactionEnabled: interactionEnabled,
            onClose: () => unawaited(_closeFocus(reason: 'header')),
            onSlotSelected: _selectSlot,
            onDebug: _debug,
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final observedArea =
        context.select<AreaState, String>((state) => state.currentArea.trim());
    final overrideArea = widget.areaOverride?.trim() ?? '';
    final currentArea = overrideArea.isNotEmpty ? overrideArea : observedArea;
    return PopScope(
      canPop: _focusedChild == null && _selectedParentName == null,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_focusedChild != null) {
          unawaited(_closeFocus(reason: 'system_back'));
          return;
        }
        if (_selectedParentName != null) {
          _showParentSelector(reason: 'system_back');
        }
      },
      child: Material(
        color: tokens.surface,
        child: Stack(
          key: _rootKey,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                AnimatedSwitcher(
                  duration: MediaQuery.maybeOf(context)?.disableAnimations == true
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  reverseDuration:
                      MediaQuery.maybeOf(context)?.disableAnimations == true
                          ? Duration.zero
                          : const Duration(milliseconds: 140),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return SizeTransition(
                      sizeFactor: animation,
                      axisAlignment: -1,
                      child: FadeTransition(opacity: animation, child: child),
                    );
                  },
                  child: _occupancyLoading
                      ? LinearProgressIndicator(
                          key: const ValueKey<String>('occupancy_loading'),
                          minHeight: 2,
                          color: Theme.of(context).colorScheme.primary,
                          backgroundColor: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withOpacity(.35),
                        )
                      : _occupancyError != null
                          ? Material(
                              key: const ValueKey<String>('occupancy_error'),
                              color:
                                  Theme.of(context).colorScheme.errorContainer,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline_rounded,
                                      size: 17,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onErrorContainer,
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        '주차 현황을 불러오지 못했습니다.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onErrorContainer,
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          : const SizedBox.shrink(
                              key: ValueKey<String>('occupancy_ready'),
                            ),
                ),
                Expanded(
                  child: Consumer<LocationState>(
                    builder: (context, locationState, _) {
                      if (locationState.isLoading) {
                        return const _SpatialLoading();
                      }
                      final locations = locationState.locations
                          .where(
                            (location) =>
                                location.area.trim() == currentArea,
                          )
                          .toList(growable: false);
                      if (locations.isEmpty) {
                        return _SpatialMessage(
                          icon: Icons.info_outline_rounded,
                          title: '주차 구역 데이터가 없습니다.',
                          message: currentArea.isEmpty
                              ? '현재 지역이 설정되지 않았습니다.'
                              : '$currentArea 지역의 주차 구역 데이터를 확인할 수 없습니다.',
                          actionLabel: '닫기',
                          onAction: widget.onExit,
                        );
                      }
                      return _buildMain(context, locations);
                    },
                  ),
                ),
              ],
            ),
            _buildFocusOverlay(context),
          ],
        ),
      ),
    );
  }
}

class _SpatialParentMap extends StatefulWidget {
  const _SpatialParentMap({
    super.key,
    required this.parent,
    required this.children,
    required this.currentLocation,
    required this.occupancyLoading,
    required this.blockedByLocation,
    required this.freeCount,
    required this.capacityOf,
    required this.recommendation,
    required this.isCurrentChild,
    required this.isSelectedChild,
    required this.onChildTap,
    required this.onDebug,
  });

  final LocationModel parent;
  final List<LocationModel> children;
  final String currentLocation;
  final bool occupancyLoading;
  final Map<String, _BlockedSlotKind> blockedByLocation;
  final int Function(String parentName, LocationModel child) freeCount;
  final int Function(LocationModel child) capacityOf;
  final _ParkingRecommendation? recommendation;
  final bool Function(String parentName, LocationModel child) isCurrentChild;
  final bool Function(String parentName, LocationModel child) isSelectedChild;
  final Future<void> Function(
    LocationModel parent,
    LocationModel child,
    Rect globalSourceRect,
  ) onChildTap;
  final ValueChanged<String> onDebug;

  @override
  State<_SpatialParentMap> createState() => _SpatialParentMapState();
}

class _SpatialParentMapState extends State<_SpatialParentMap>
    with SingleTickerProviderStateMixin {
  final GlobalKey _mapKey = GlobalKey();
  late final AnimationController _revealController;
  String? _pressedChildKey;
  String? _peekChildKey;
  bool _peekVisible = false;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 0,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final disabled = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (disabled) {
        _revealController.value = 1;
        widget.onDebug(
          'parking_parent=reveal_skipped parent=${widget.parent.locationName} reason=reduce_motion',
        );
      } else {
        widget.onDebug(
          'parking_parent=reveal_start parent=${widget.parent.locationName} durationMs=220',
        );
        unawaited(
          _revealController.forward().then((_) {
            if (!mounted) return;
            widget.onDebug(
              'parking_parent=reveal_complete parent=${widget.parent.locationName}',
            );
          }),
        );
      }
    });
  }

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  static String _nameKey(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  String _slotKey(String child, int slotNo) =>
      '${_nameKey(widget.parent.locationName)}|${_nameKey(child)}|$slotNo';

  List<_ResolvedChildRegion> _resolveChildren(
    ParkingStatusDotMapLayout layout,
    ParkingGridModel grid,
  ) {
    final mapped = <LocationModel>[];
    final nominalRects = <Rect>[];
    final paths = <Path>[];
    for (final child in widget.children) {
      final childRect = resolveParkingSpatialChildRect(child, grid);
      if (childRect == null) continue;
      final nominal = layout.rectFor(childRect).intersect(layout.mapRect);
      if (nominal.isEmpty || nominal.width <= 0 || nominal.height <= 0) continue;
      final effectiveAreaIds = resolvedChildParkingAreaIds(child);
      final path = buildEffectiveChildRegionPath(
        grid: grid,
        childRect: childRect,
        effectiveParkingAreaIds: effectiveAreaIds,
        nominalRegion: RRect.fromRectAndRadius(
          nominal,
          const Radius.circular(8),
        ),
        parkingAreaRect: (area) => layout.rectFor(
          GridRect(
            r0: area.r0,
            c0: area.c0,
            r1: area.r1,
            c1: area.c1,
          ),
        ),
        useEffectiveShape: !child.isTowerChild,
        cutInflate: math.max(.5, layout.scale * .035),
        cutRadius: math.max(3.0, layout.scale * .13),
      );
      mapped.add(child);
      nominalRects.add(nominal);
      paths.add(path);
    }
    final hits = resolveParkingSpatialHitRects(
      visualRects: nominalRects,
      bounds: layout.mapRect,
    );
    final out = <_ResolvedChildRegion>[];
    for (var i = 0; i < mapped.length; i++) {
      final child = mapped[i];
      final free = widget.freeCount(widget.parent.locationName, child);
      final capacity = widget.capacityOf(child);
      final current = widget.isCurrentChild(widget.parent.locationName, child);
      final selected = widget.isSelectedChild(widget.parent.locationName, child);
      final recommended = widget.recommendation != null &&
          _nameKey(widget.recommendation!.child.locationName) ==
              _nameKey(child.locationName);
      out.add(
        _ResolvedChildRegion(
          child: child,
          nominalRect: nominalRects[i],
          effectivePath: paths[i],
          hitRect: hits[i],
          freeCount: free,
          capacity: capacity,
          enabled: free > 0 || current,
          recommended: recommended,
          current: current,
          selected: selected,
        ),
      );
    }
    return out;
  }

  _ResolvedChildRegion? _entryAt(
    Offset position,
    List<_ResolvedChildRegion> entries,
  ) {
    for (final entry in entries.reversed) {
      if (entry.effectivePath.contains(position) ||
          entry.hitRect.contains(position)) {
        return entry;
      }
    }
    return null;
  }

  Rect? _globalRect(Rect localRect) {
    final context = _mapKey.currentContext;
    final object = context?.findRenderObject();
    if (object is! RenderBox || !object.hasSize) return null;
    final topLeft = object.localToGlobal(localRect.topLeft);
    final bottomRight = object.localToGlobal(localRect.bottomRight);
    return Rect.fromPoints(topLeft, bottomRight);
  }

  void _showPeek(_ResolvedChildRegion entry) {
    setState(() {
      _peekChildKey = _nameKey(entry.child.locationName);
      _peekVisible = true;
    });
  }

  void _hidePeek() {
    if (_peekChildKey == null) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    setState(() => _peekVisible = false);
    Future<void>.delayed(
      reduceMotion ? Duration.zero : const Duration(milliseconds: 130),
      () {
        if (!mounted || _peekVisible) return;
        setState(() => _peekChildKey = null);
      },
    );
  }

  List<_ResolvedSpatialSlot> _parentSlotDots(
    ParkingStatusDotMapLayout layout,
  ) {
    final current = _PlateParkingWorkspaceState._selectionData(
      widget.currentLocation,
    );
    final result = <_ResolvedSpatialSlot>[];
    for (final child in widget.children) {
      for (final slot in child.childSlots) {
        final rect = layout
            .rectFor(
              GridRect(
                r0: slot.r0,
                c0: slot.c0,
                r1: slot.r1,
                c1: slot.c1,
              ),
            )
            .intersect(layout.mapRect);
        if (rect.isEmpty) continue;
        final key = _slotKey(child.locationName, slot.no);
        final currentSlot = current != null &&
            _nameKey(current.parent) == _nameKey(widget.parent.locationName) &&
            _nameKey(current.child) == _nameKey(child.locationName) &&
            current.slotNo == slot.no;
        final recommendation = widget.recommendation != null &&
            _nameKey(widget.recommendation!.child.locationName) ==
                _nameKey(child.locationName) &&
            widget.recommendation!.slot.no == slot.no;
        final blocked = widget.blockedByLocation[key];
        final state = currentSlot
            ? _SpatialSlotState.current
            : blocked == _BlockedSlotKind.departureRequest
                    ? _SpatialSlotState.departureRequest
                    : blocked == _BlockedSlotKind.parked
                        ? _SpatialSlotState.occupied
                        : recommendation
                            ? _SpatialSlotState.recommended
                            : _SpatialSlotState.empty;
        result.add(
          _ResolvedSpatialSlot(
            slot: slot,
            visualRect: rect,
            hitRect: rect,
            state: state,
          ),
        );
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final grid = widget.parent.parkingGrid;
    if (grid == null) return const SizedBox.shrink();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedBuilder(
      animation: _revealController,
      builder: (context, child) {
        final value = reduceMotion
            ? 1.0
            : Curves.easeOutCubic.transform(_revealController.value);
        return Opacity(
          opacity: (.88 + .12 * value).clamp(0.0, 1.0).toDouble(),
          child: Transform.scale(
            scale: .992 + .008 * value,
            child: child,
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final size = Size(constraints.maxWidth, constraints.maxHeight);
            final layout = ParkingStatusDotMapLayout.resolve(
              size: size,
              grid: grid,
              padding: 10,
            );
            if (layout == null) return const SizedBox.shrink();
            final entries = _resolveChildren(layout, grid);
            final slotDots = _parentSlotDots(layout);
            return GestureDetector(
              key: _mapKey,
              behavior: HitTestBehavior.opaque,
              onTapDown: (details) {
                final entry = _entryAt(details.localPosition, entries);
                setState(
                  () => _pressedChildKey =
                      entry == null ? null : _nameKey(entry.child.locationName),
                );
              },
              onTapCancel: () => setState(() => _pressedChildKey = null),
              onTapUp: (details) {
                final entry = _entryAt(details.localPosition, entries);
                setState(() => _pressedChildKey = null);
                if (entry == null) return;
                if (!entry.enabled) {
                  HapticFeedback.selectionClick();
                  widget.onDebug(
                    'parking_child=blocked parent=${widget.parent.locationName} child=${entry.child.locationName} reason=no_selectable_slot',
                  );
                  _showPeek(entry);
                  Future<void>.delayed(const Duration(milliseconds: 900), () {
                    if (!mounted ||
                        _peekChildKey != _nameKey(entry.child.locationName)) {
                      return;
                    }
                    _hidePeek();
                  });
                  return;
                }
                final global = _globalRect(entry.nominalRect);
                if (global == null) return;
                widget.onDebug(
                  'parking_child=pressed parent=${widget.parent.locationName} child=${entry.child.locationName} free=${entry.freeCount} capacity=${entry.capacity}',
                );
                unawaited(widget.onChildTap(widget.parent, entry.child, global));
              },
              onLongPressStart: (details) {
                final entry = _entryAt(details.localPosition, entries);
                if (entry == null) return;
                HapticFeedback.mediumImpact();
                _showPeek(entry);
                widget.onDebug(
                  'parking_child=peek parent=${widget.parent.locationName} child=${entry.child.locationName} free=${entry.freeCount} capacity=${entry.capacity}',
                );
              },
              onLongPressEnd: (_) => _hidePeek(),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ParkingStatusDotMapSurface(
                      grid: grid,
                      framed: false,
                      padding: 10,
                    ),
                  ),
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        painter: _ChildRegionPainter(
                          entries: entries,
                          pressedChildKey: _pressedChildKey,
                          primary: Theme.of(context).colorScheme.primary,
                          tertiary: Theme.of(context).colorScheme.tertiary,
                          secondary: Theme.of(context).colorScheme.secondary,
                          neutral: Theme.of(context).colorScheme.onSurfaceVariant,
                          disabled: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                  ),
                  for (final slot in slotDots)
                    _ParentSlotDot(entry: slot),
                  for (final entry in entries)
                    Positioned.fromRect(
                      rect: entry.nominalRect,
                      child: IgnorePointer(
                        child: Center(
                          child: _ChildRegionLabel(
                            name: entry.child.locationName,
                            freeCount: entry.freeCount,
                            capacity: entry.capacity,
                            enabled: entry.enabled,
                            recommended: entry.recommended,
                            current: entry.current,
                            selected: entry.selected,
                          ),
                        ),
                      ),
                    ),
                  if (_peekChildKey != null)
                    for (final entry in entries)
                      if (_nameKey(entry.child.locationName) == _peekChildKey)
                        _ChildPeekBubble(
                          entry: entry,
                          bounds: layout.mapRect,
                          visible: _peekVisible,
                        ),
                  if (widget.occupancyLoading)
                    Positioned(
                      right: 12,
                      top: 12,
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surface
                                .withOpacity(.9),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 5,
                            ),
                            child: Text(
                              '현황 갱신 중',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _ChildRegionPainter extends CustomPainter {
  const _ChildRegionPainter({
    required this.entries,
    required this.pressedChildKey,
    required this.primary,
    required this.tertiary,
    required this.secondary,
    required this.neutral,
    required this.disabled,
  });

  final List<_ResolvedChildRegion> entries;
  final String? pressedChildKey;
  final Color primary;
  final Color tertiary;
  final Color secondary;
  final Color neutral;
  final Color disabled;

  static String _nameKey(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  @override
  void paint(Canvas canvas, Size size) {
    for (final entry in entries) {
      final pressed = _nameKey(entry.child.locationName) == pressedChildKey;
      final fill = entry.selected
          ? primary.withOpacity(.19)
          : entry.current
              ? tertiary.withOpacity(.14)
              : entry.recommended
                  ? secondary.withOpacity(.13)
                  : entry.enabled
                      ? neutral.withOpacity(pressed ? .18 : .10)
                      : disabled.withOpacity(.08);
      final stroke = entry.selected
          ? primary.withOpacity(.95)
          : entry.current
              ? tertiary.withOpacity(.88)
              : entry.recommended
                  ? secondary.withOpacity(.9)
                  : entry.enabled
                      ? neutral.withOpacity(pressed ? .86 : .56)
                      : disabled.withOpacity(.38);
      canvas.drawPath(
        entry.effectivePath,
        Paint()
          ..style = PaintingStyle.fill
          ..color = fill,
      );
      canvas.drawPath(
        entry.effectivePath,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = pressed || entry.selected ? 2 : 1.2
          ..color = stroke,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ChildRegionPainter oldDelegate) {
    return oldDelegate.entries != entries ||
        oldDelegate.pressedChildKey != pressedChildKey ||
        oldDelegate.primary != primary ||
        oldDelegate.tertiary != tertiary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.neutral != neutral ||
        oldDelegate.disabled != disabled;
  }
}

class _ChildRegionLabel extends StatelessWidget {
  const _ChildRegionLabel({
    required this.name,
    required this.freeCount,
    required this.capacity,
    required this.enabled,
    required this.recommended,
    required this.current,
    required this.selected,
  });

  final String name;
  final int freeCount;
  final int capacity;
  final bool enabled;
  final bool recommended;
  final bool current;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tone = selected || current ? cs.primary : cs.onSurface;
    return AnimatedScale(
      scale: selected ? 1.04 : 1,
      duration: (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
          ? Duration.zero
          : const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 112),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(enabled ? .9 : .72),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected || current
                ? cs.primary.withOpacity(.78)
                : cs.outlineVariant.withOpacity(.65),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (selected) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      value: reduceMotion ? 1 : null,
                      strokeWidth: 1.6,
                      color: cs.primary,
                      backgroundColor: cs.primary.withOpacity(.14),
                    ),
                  ),
                  const SizedBox(width: 4),
                ] else if (recommended) ...[
                  Icon(Icons.auto_awesome_rounded, size: 12, color: cs.primary),
                  const SizedBox(width: 3),
                ],
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w900,
                      color: tone,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 1),
            Text(
              enabled ? '빈 $freeCount/$capacity' : '빈 자리 없음',
              maxLines: 1,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w800,
                color: enabled ? cs.onSurfaceVariant : cs.error,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChildPeekBubble extends StatelessWidget {
  const _ChildPeekBubble({
    required this.entry,
    required this.bounds,
    required this.visible,
  });

  final _ResolvedChildRegion entry;
  final Rect bounds;
  final bool visible;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final width = math.min(150.0, bounds.width - 16).toDouble();
    final left = (entry.nominalRect.center.dx - width / 2)
        .clamp(bounds.left + 8, bounds.right - width - 8)
        .toDouble();
    final top = (entry.nominalRect.top - 58)
        .clamp(bounds.top + 8, bounds.bottom - 62)
        .toDouble();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion
        ? Duration.zero
        : visible
            ? const Duration(milliseconds: 160)
            : const Duration(milliseconds: 130);
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: duration,
        curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(0, .08),
          duration: duration,
          curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
          child: AnimatedScale(
            scale: visible ? 1 : .94,
            duration: duration,
            curve: visible ? Curves.easeOutCubic : Curves.easeInCubic,
            child: Material(
          elevation: 5,
          borderRadius: BorderRadius.circular(10),
          color: cs.surface,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.child.locationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 2),
                Text(
                  '빈 자리 ${entry.freeCount} / ${entry.capacity}',
                  style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  ),
);
  }
}

class _ParentSlotDot extends StatelessWidget {
  const _ParentSlotDot({required this.entry});

  final _ResolvedSpatialSlot entry;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = switch (entry.state) {
      _SpatialSlotState.selected => cs.primary,
      _SpatialSlotState.current => cs.tertiary,
      _SpatialSlotState.departureRequest => cs.error,
      _SpatialSlotState.occupied => cs.onSurfaceVariant,
      _SpatialSlotState.recommended => cs.primary.withOpacity(.68),
      _SpatialSlotState.empty => cs.outlineVariant.withOpacity(.46),
    };
    final rect = entry.visualRect.deflate(
      math.min(entry.visualRect.shortestSide * .18, 1.5),
    );
    return Positioned.fromRect(
      rect: rect,
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withOpacity(entry.state == _SpatialSlotState.empty ? .35 : .72),
            borderRadius: BorderRadius.circular(2.5),
          ),
        ),
      ),
    );
  }
}

class _SpatialChildFocus extends StatefulWidget {
  const _SpatialChildFocus({
    super.key,
    required this.parent,
    required this.child,
    required this.blockedByLocation,
    required this.currentLocation,
    required this.recommendation,
    required this.occupancyLoading,
    required this.progress,
    required this.interactionEnabled,
    required this.onClose,
    required this.onSlotSelected,
    required this.onDebug,
  });

  final LocationModel parent;
  final LocationModel child;
  final Map<String, _BlockedSlotKind> blockedByLocation;
  final String currentLocation;
  final _ParkingRecommendation? recommendation;
  final bool occupancyLoading;
  final double progress;
  final bool interactionEnabled;
  final VoidCallback onClose;
  final void Function(String parent, LocationModel child, int slotNo)
      onSlotSelected;
  final ValueChanged<String> onDebug;

  @override
  State<_SpatialChildFocus> createState() => _SpatialChildFocusState();
}

class _SpatialChildFocusState extends State<_SpatialChildFocus> {
  int? _pressedSlotNo;
  String _lastHitRectDiagnosticSignature = '';

  static String _nameKey(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

  static _ParkingSelectionData? _selectionData(String raw) =>
      _PlateParkingWorkspaceState._selectionData(raw);

  String _slotKey(int slotNo) {
    return '${_nameKey(widget.parent.locationName)}|${_nameKey(widget.child.locationName)}|$slotNo';
  }

  _SpatialSlotState _slotState(int slotNo) {
    final current = _selectionData(widget.currentLocation);
    if (current != null &&
        _nameKey(current.parent) == _nameKey(widget.parent.locationName) &&
        _nameKey(current.child) == _nameKey(widget.child.locationName) &&
        current.slotNo == slotNo) {
      return _SpatialSlotState.current;
    }
    final blocked = widget.blockedByLocation[_slotKey(slotNo)];
    if (blocked == _BlockedSlotKind.departureRequest) {
      return _SpatialSlotState.departureRequest;
    }
    if (blocked == _BlockedSlotKind.parked) {
      return _SpatialSlotState.occupied;
    }
    if (widget.recommendation != null &&
        _nameKey(widget.recommendation!.child.locationName) ==
            _nameKey(widget.child.locationName) &&
        widget.recommendation!.slot.no == slotNo) {
      return _SpatialSlotState.recommended;
    }
    return _SpatialSlotState.empty;
  }

  bool _selectable(_SpatialSlotState state) {
    return state == _SpatialSlotState.empty ||
        state == _SpatialSlotState.recommended ||
        state == _SpatialSlotState.current;
  }

  List<_ResolvedSpatialSlot> _resolveSlots(
    ParkingStatusDotMapLayout layout,
  ) {
    final slots = List<ChildSlot>.of(widget.child.childSlots)
      ..sort((a, b) => a.no.compareTo(b.no));
    final mapped = <ChildSlot>[];
    final visuals = <Rect>[];
    for (final slot in slots) {
      final visual = layout
          .rectFor(
            GridRect(
              r0: slot.r0,
              c0: slot.c0,
              r1: slot.r1,
              c1: slot.c1,
            ),
          )
          .intersect(layout.mapRect);
      if (visual.isEmpty || visual.width <= 0 || visual.height <= 0) continue;
      mapped.add(slot);
      visuals.add(visual);
    }
    final hits = resolveParkingSpatialHitRects(
      visualRects: visuals,
      bounds: layout.mapRect,
    );
    final constrained = hits.any(
      (hit) =>
          (hit.width - layout.mapRect.width).abs() <= .001 ||
          (hit.height - layout.mapRect.height).abs() <= .001,
    );
    if (constrained) {
      final signature =
          '${layout.mapRect.width.toStringAsFixed(3)}|${layout.mapRect.height.toStringAsFixed(3)}|${hits.length}';
      if (_lastHitRectDiagnosticSignature != signature) {
        _lastHitRectDiagnosticSignature = signature;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          widget.onDebug(
            'parking_hit_rect=bounded_to_map parent=${widget.parent.locationName} child=${widget.child.locationName} mapWidth=${layout.mapRect.width.toStringAsFixed(3)} mapHeight=${layout.mapRect.height.toStringAsFixed(3)} slots=${hits.length}',
          );
        });
      }
    }
    return <_ResolvedSpatialSlot>[
      for (var i = 0; i < mapped.length; i++)
        _ResolvedSpatialSlot(
          slot: mapped[i],
          visualRect: visuals[i],
          hitRect: hits[i],
          state: _slotState(mapped[i].no),
        ),
    ];
  }

  _ResolvedSpatialSlot? _entryAt(
    Offset position,
    List<_ResolvedSpatialSlot> entries,
  ) {
    for (final entry in entries.reversed) {
      if (entry.hitRect.contains(position)) return entry;
    }
    return null;
  }

  void _handleTap(_ResolvedSpatialSlot entry) {
    if (!widget.interactionEnabled) return;
    if (!_selectable(entry.state)) {
      HapticFeedback.selectionClick();
      widget.onDebug(
        'parking_slot=blocked parent=${widget.parent.locationName} child=${widget.child.locationName} slot=${entry.slot.no} state=${entry.state.name}',
      );
      return;
    }
    widget.onSlotSelected(
      widget.parent.locationName,
      widget.child,
      entry.slot.no,
    );
  }

  Widget _buildMapBody(
    BuildContext context,
    GridRect? childRect,
  ) {
    if (childRect == null) {
      if (widget.progress < .9) {
        return const SizedBox.expand();
      }
      return const _SpatialMessage(
        icon: Icons.crop_free_rounded,
        title: '자식 구역 범위를 확인할 수 없습니다.',
        message: 'childRect 또는 childSlots 위치 정보를 확인하세요.',
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final grid = widget.parent.parkingGrid!;
        final size = Size(
          constraints.maxWidth,
          constraints.maxHeight,
        );
        final layout = ParkingStatusDotMapLayout.resolve(
          size: size,
          grid: grid,
          viewport: childRect,
          padding: 12,
        );
        if (layout == null) return const SizedBox.shrink();
        final entries = _resolveSlots(layout);
        final effectiveAreaIds = resolvedChildParkingAreaIds(widget.child);
        final effectivePath = buildEffectiveChildRegionPath(
          grid: grid,
          childRect: childRect,
          effectiveParkingAreaIds: effectiveAreaIds,
          nominalRegion: RRect.fromRectAndRadius(
            layout.rectFor(childRect).intersect(layout.mapRect),
            const Radius.circular(10),
          ),
          parkingAreaRect: (area) => layout.rectFor(
            GridRect(
              r0: area.r0,
              c0: area.c0,
              r1: area.r1,
              c1: area.c1,
            ),
          ),
          useEffectiveShape: !widget.child.isTowerChild,
          cutInflate: math.max(.5, layout.scale * .035),
          cutRadius: math.max(3.0, layout.scale * .13),
        );
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: widget.interactionEnabled
              ? (details) {
                  final entry = _entryAt(details.localPosition, entries);
                  setState(() => _pressedSlotNo = entry?.slot.no);
                }
              : null,
          onTapCancel: () => setState(() => _pressedSlotNo = null),
          onTapUp: widget.interactionEnabled
              ? (details) {
                  final entry = _entryAt(details.localPosition, entries);
                  setState(() => _pressedSlotNo = null);
                  if (entry != null) _handleTap(entry);
                }
              : null,
          child: Stack(
            children: [
              Positioned.fill(
                child: ParkingStatusDotMapSurface(
                  grid: grid,
                  viewport: childRect,
                  visibleParkingAreaIds: effectiveAreaIds,
                  framed: false,
                  padding: 12,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(
                    painter: _ChildFocusPathPainter(
                      path: effectivePath,
                      fill: Theme.of(context)
                          .colorScheme
                          .primary
                          .withOpacity(.045),
                      stroke: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withOpacity(.38),
                    ),
                  ),
                ),
              ),
              for (final entry in entries)
                _SpatialSlotMarker(
                  entry: entry,
                  pressed: _pressedSlotNo == entry.slot.no,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(7, 4, 10, 4),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: '부모 구역으로',
            onPressed: widget.interactionEnabled ? widget.onClose : null,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 40, height: 40),
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.child.locationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                ),
                Text(
                  widget.parent.locationName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ],
            ),
          ),
          if (widget.occupancyLoading)
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final childRect = resolveParkingSpatialChildRect(
      widget.child,
      widget.parent.parkingGrid!,
    );
    final progress = widget.progress.clamp(0.0, 1.0).toDouble();
    final headerProgress =
        ((progress - .52) / .48).clamp(0.0, 1.0).toDouble();
    return Material(
      color: tokens.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final headerHeight = 52.0;
          final showHeader = headerProgress > .01 &&
              constraints.maxWidth >= 120 &&
              constraints.maxHeight >= 120;
          final mapTop = showHeader ? headerHeight * headerProgress : 0.0;
          return Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: Padding(
                  padding: EdgeInsets.only(
                    top: mapTop,
                  ),
                  child: _buildMapBody(context, childRect),
                ),
              ),
              if (showHeader)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: headerHeight,
                  child: IgnorePointer(
                    ignoring: headerProgress < .94,
                    child: Opacity(
                      opacity: headerProgress,
                      child: Transform.translate(
                        offset: Offset(0, -8 * (1 - headerProgress)),
                        child: _buildHeader(context),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

}

class _ChildFocusPathPainter extends CustomPainter {
  const _ChildFocusPathPainter({
    required this.path,
    required this.fill,
    required this.stroke,
  });

  final Path path;
  final Color fill;
  final Color stroke;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fill,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _ChildFocusPathPainter oldDelegate) {
    return oldDelegate.path != path ||
        oldDelegate.fill != fill ||
        oldDelegate.stroke != stroke;
  }
}

class _SpatialSlotMarker extends StatelessWidget {
  const _SpatialSlotMarker({
    required this.entry,
    required this.pressed,
  });

  final _ResolvedSpatialSlot entry;
  final bool pressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final fill = switch (entry.state) {
      _SpatialSlotState.selected => cs.primaryContainer,
      _SpatialSlotState.current => cs.tertiaryContainer,
      _SpatialSlotState.departureRequest => cs.errorContainer,
      _SpatialSlotState.occupied => cs.surfaceContainerHighest,
      _SpatialSlotState.recommended => cs.secondaryContainer,
      _SpatialSlotState.empty => cs.surface.withOpacity(.92),
    };
    final stroke = switch (entry.state) {
      _SpatialSlotState.selected => cs.primary,
      _SpatialSlotState.current => cs.tertiary,
      _SpatialSlotState.departureRequest => cs.error,
      _SpatialSlotState.occupied => cs.outline,
      _SpatialSlotState.recommended => cs.secondary,
      _SpatialSlotState.empty => cs.outlineVariant,
    };
    final foreground = switch (entry.state) {
      _SpatialSlotState.selected => cs.onPrimaryContainer,
      _SpatialSlotState.current => cs.onTertiaryContainer,
      _SpatialSlotState.departureRequest => cs.onErrorContainer,
      _SpatialSlotState.occupied => cs.onSurfaceVariant,
      _SpatialSlotState.recommended => cs.onSecondaryContainer,
      _SpatialSlotState.empty => cs.onSurface,
    };
    final duration = reduceMotion ? Duration.zero : const Duration(milliseconds: 170);
    final pressDuration = reduceMotion ? Duration.zero : const Duration(milliseconds: 90);
    return Positioned.fromRect(
      rect: entry.visualRect,
      child: IgnorePointer(
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(begin: .88, end: 1),
          duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutBack,
          builder: (context, value, child) => Opacity(
            opacity: value.clamp(0.0, 1.0).toDouble(),
            child: Transform.scale(scale: value, child: child),
          ),
          child: AnimatedScale(
            scale: pressed ? .965 : 1,
            duration: pressDuration,
            curve: Curves.easeOutCubic,
            child: AnimatedContainer(
              duration: duration,
              curve: Curves.easeOutCubic,
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: stroke.withOpacity(pressed ? 1 : .82),
                  width: entry.state == _SpatialSlotState.selected ? 2 : 1,
                ),
                boxShadow: [
                  if (entry.state == _SpatialSlotState.selected || pressed)
                    BoxShadow(
                      color: cs.shadow.withOpacity(.13),
                      blurRadius: 7,
                      offset: const Offset(0, 1),
                    ),
                ],
              ),
              alignment: Alignment.center,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (entry.state == _SpatialSlotState.selected)
                        Icon(Icons.check_rounded, size: 11, color: foreground)
                      else if (entry.state == _SpatialSlotState.current)
                        Icon(Icons.my_location_rounded, size: 10, color: foreground)
                      else if (entry.state == _SpatialSlotState.departureRequest)
                        Icon(Icons.exit_to_app_rounded, size: 10, color: foreground)
                      else if (entry.state == _SpatialSlotState.occupied)
                        Icon(Icons.lock_outline_rounded, size: 10, color: foreground)
                      else if (entry.state == _SpatialSlotState.recommended)
                        Icon(Icons.auto_awesome_rounded, size: 10, color: foreground),
                      const SizedBox(width: 2),
                      Text(
                        '${entry.slot.no}',
                        style: TextStyle(
                          color: foreground,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SpatialLoading extends StatelessWidget {
  const _SpatialLoading();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          Expanded(
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: .42, end: .72),
              duration: (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
                  ? Duration.zero
                  : const Duration(milliseconds: 700),
              curve: Curves.easeInOut,
              builder: (context, value, _) => DecoratedBox(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest.withOpacity(value),
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '주차 공간을 불러오는 중입니다.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _SpatialMessage extends StatelessWidget {
  const _SpatialMessage({
    required this.icon,
    required this.title,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 28, color: cs.primary),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 14),
              CommonButton(
                label: actionLabel!,
                icon: Icons.arrow_back_rounded,
                onPressed: onAction,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
