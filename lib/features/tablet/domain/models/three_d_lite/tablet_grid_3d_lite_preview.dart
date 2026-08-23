import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../pages/widgets/tablet_common_components.dart';
import '../../../../location/domain/models/grid_rect.dart';
import '../../../../location/domain/models/location_model.dart';
import '../../../../location/domain/models/parking_grid_model.dart';
import '../two_d/tablet_grid_2d_preview.dart'
    show ParkingGridOverlay, ParkingSlotStatus;

class TabletGrid3dLitePreview extends StatefulWidget {
  const TabletGrid3dLitePreview({
    super.key,
    required this.locations,
    required this.overlay,
    this.onDebugLog,
  });

  final List<LocationModel> locations;
  final ParkingGridOverlay overlay;
  final ValueChanged<String>? onDebugLog;

  @override
  State<TabletGrid3dLitePreview> createState() => _TabletGrid3dLitePreviewState();
}

class _TabletGrid3dLitePreviewState extends State<TabletGrid3dLitePreview>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _entryController;
  int _index = 0;
  int _viewQuarterTurns = 0;
  bool _reduceMotion = false;
  String _lastSceneStatsKey = '';

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 940),
    );
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    )..forward();
    _syncPulse();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (next != _reduceMotion) {
      _reduceMotion = next;
      _syncPulse();
    }
  }

  int _locationsIdentitySignature(List<LocationModel> locations) {
    return Object.hashAll(
      locations.map<Object>((location) => identityHashCode(location)),
    );
  }

  @override
  void didUpdateWidget(covariant TabletGrid3dLitePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_locationsIdentitySignature(oldWidget.locations) !=
        _locationsIdentitySignature(widget.locations)) {
      final entries = _entries;
      if (_index >= entries.length) {
        _index = entries.isEmpty ? 0 : entries.length - 1;
      }
      if (!_reduceMotion) {
        _entryController
          ..reset()
          ..forward();
      }
    }
    _syncPulse();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _entryController.dispose();
    super.dispose();
  }

  bool get _hasDepartureRequest {
    return widget.overlay.slotStatusByKey.values
            .any((value) => value == ParkingSlotStatus.departureRequest) ||
        widget.overlay.groupStatusByKey.values
            .any((value) => value == ParkingSlotStatus.departureRequest);
  }

  void _syncPulse() {
    final shouldAnimate = !_reduceMotion && _hasDepartureRequest;
    if (shouldAnimate) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
        _emitDebug('departure_pulse_started');
      }
    } else {
      if (_pulseController.isAnimating) {
        _pulseController.stop();
        _emitDebug(
          'departure_pulse_stopped',
          <String, Object?>{'reduceMotion': _reduceMotion},
        );
      }
      _pulseController.value = 0;
    }
  }

  void _emitDebug(
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    final now = DateTime.now();
    final buffer = StringBuffer()
      ..write('[TabletGrid3DLite] ')
      ..write(now.toIso8601String())
      ..write(' event=')
      ..write(event);
    for (final entry in details.entries) {
      if (entry.value == null) continue;
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(entry.value);
    }
    final line = buffer.toString();
    debugPrint(line);
    widget.onDebugLog?.call(line);
  }

  void _reportScene(_SceneModel scene) {
    final parked = scene.slots
        .where((slot) => slot.status == ParkingSlotStatus.parked)
        .length;
    final departure = scene.slots
        .where((slot) => slot.status == ParkingSlotStatus.departureRequest)
        .length;
    final key = <Object?>[
      scene.parentName,
      scene.rows,
      scene.cols,
      scene.slots.length,
      parked,
      departure,
      scene.roadRects.length,
      scene.road2Rects.length,
      scene.pillarCells.length,
      scene.towers.length,
      scene.lod.name,
      _viewQuarterTurns,
    ].join('|');
    if (_lastSceneStatsKey == key) return;
    _lastSceneStatsKey = key;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emitDebug(
        'scene_stats',
        <String, Object?>{
          'parent': scene.parentName,
          'rows': scene.rows,
          'cols': scene.cols,
          'cells': scene.rows * scene.cols,
          'slots': scene.slots.length,
          'parked': parked,
          'departure': departure,
          'roadRects': scene.roadRects.length,
          'road2Rects': scene.road2Rects.length,
          'pillars': scene.pillarCells.length,
          'towers': scene.towers.length,
          'lod': scene.lod.name,
          'strategy': 'layered_lite',
          'staticCache': _gridStaticGeometryCache.length,
          'view': _viewQuarterTurns,
        },
      );
    });
  }

  List<_StructuredEntry> get _entries {
    final result = <_StructuredEntry>[];
    for (final location in widget.locations) {
      if (!_isStructuredParent(location)) continue;
      final model = location.parkingGrid;
      if (model == null || model.rows <= 0 || model.cols <= 0) continue;
      result.add(
        _StructuredEntry(
          location: location,
          title: _trimOrEmpty(location.locationName).isEmpty
              ? '주차장'
              : _trimOrEmpty(location.locationName),
        ),
      );
    }
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }


  void _goTo(int next) {
    final entries = _entries;
    if (entries.isEmpty) return;
    setState(() {
      _index = (next % entries.length + entries.length) % entries.length;
    });
    if (!_reduceMotion) {
      _entryController
        ..reset()
        ..forward();
    }
    _emitDebug('area_changed', <String, Object?>{'index': _index});
  }

  void _setView(int value) {
    final next = ((value % 4) + 4) % 4;
    if (next == _viewQuarterTurns) return;
    setState(() => _viewQuarterTurns = next);
    if (!_reduceMotion) {
      _entryController
        ..reset()
        ..forward();
    }
    _emitDebug(
      'view_changed',
      <String, Object?>{'view': _viewQuarterTurns, 'label': _viewLabel(_viewQuarterTurns)},
    );
  }

  void _handleHorizontalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 250) return;
    _setView(_viewQuarterTurns + (velocity < 0 ? 1 : -1));
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final entries = _entries;
    if (entries.length <= 1) return;
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 250) return;
    _goTo(_index + (velocity < 0 ? 1 : -1));
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    if (entries.isEmpty) {
      return const TabletCommonEmptyState(
        title: '표시 가능한 주차 그리드가 없습니다',
        message: '복합 부모 주차 구역에 저장된 grid 데이터가 필요합니다.',
        icon: Icons.grid_4x4_rounded,
      );
    }

    final safeIndex = _index.clamp(0, entries.length - 1).toInt();
    final current = entries[safeIndex];
    final scene = _buildScene(
      parent: current.location,
      allLocations: widget.locations,
      overlay: widget.overlay,
    );
    _reportScene(scene);
    final tokens = CommonUiTheme.of(context);
    final entryAnimation = CurvedAnimation(
      parent: _entryController,
      curve: CommonUiMotion.enter,
    );
    final sceneContent = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[
            tokens.canvas,
            tokens.surface.withOpacity(0.98),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _StaticScenePainter(
                  scene: scene,
                  tokens: tokens,
                  viewQuarterTurns: _viewQuarterTurns,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: RepaintBoundary(
              child: CustomPaint(
                painter: _VehicleScenePainter(
                  scene: scene,
                  tokens: tokens,
                  viewQuarterTurns: _viewQuarterTurns,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: CustomPaint(
              painter: _DeparturePulsePainter(
                scene: scene,
                tokens: tokens,
                viewQuarterTurns: _viewQuarterTurns,
                pulse: _pulseController,
                reduceMotion: _reduceMotion,
              ),
            ),
          ),
        ],
      ),
    );

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: _handleHorizontalDragEnd,
      onVerticalDragEnd:
          entries.length > 1 ? _handleVerticalDragEnd : null,
      child: FadeTransition(
        opacity: _reduceMotion
            ? const AlwaysStoppedAnimation<double>(1)
            : entryAnimation,
        child: ScaleTransition(
          scale: _reduceMotion
              ? const AlwaysStoppedAnimation<double>(1)
              : Tween<double>(begin: 0.985, end: 1).animate(entryAnimation),
          child: sceneContent,
        ),
      ),
    );
  }

}

String _viewLabel(int quarterTurns) {
  switch (quarterTurns % 4) {
    case 0:
      return '정면';
    case 1:
      return '우측';
    case 2:
      return '후면';
    default:
      return '좌측';
  }
}



class _StructuredEntry {
  const _StructuredEntry({
    required this.location,
    required this.title,
  });

  final LocationModel location;
  final String title;
}

enum _SceneLod { overview, simplified, detailed }

class _GridStaticGeometry {
  const _GridStaticGeometry({
    required this.pillarCells,
    required this.roadRects,
    required this.road2Rects,
    required this.signature,
  });

  final List<math.Point<int>> pillarCells;
  final List<GridRect> roadRects;
  final List<GridRect> road2Rects;
  final int signature;
}

final Map<ParkingGridModel, _GridStaticGeometry> _gridStaticGeometryCache =
    <ParkingGridModel, _GridStaticGeometry>{};

_GridStaticGeometry _staticGeometryForGrid(ParkingGridModel grid) {
  final cached = _gridStaticGeometryCache[grid];
  if (cached != null) return cached;

  final pillarCells = <math.Point<int>>[];
  for (int row = 0; row < grid.rows; row++) {
    for (int col = 0; col < grid.cols; col++) {
      final cellType = _cellAt(grid, row, col);
      if (cellType == ParkingGridCellType.pillar ||
          cellType == ParkingGridCellType.wall) {
        pillarCells.add(math.Point<int>(col, row));
      }
    }
  }
  final road2Set = grid.road2Cells.toSet();
  final roadRects = _mergeRoadRects(grid, road2Set, false);
  final road2Rects = _mergeRoadRects(grid, road2Set, true);
  final value = _GridStaticGeometry(
    pillarCells: List<math.Point<int>>.unmodifiable(pillarCells),
    roadRects: List<GridRect>.unmodifiable(roadRects),
    road2Rects: List<GridRect>.unmodifiable(road2Rects),
    signature: Object.hash(
      grid.rows,
      grid.cols,
      Object.hashAll(grid.cells),
      Object.hashAll(grid.road2Cells),
      Object.hashAll(pillarCells),
      Object.hashAll(roadRects),
      Object.hashAll(road2Rects),
    ),
  );
  if (_gridStaticGeometryCache.length >= 12) {
    _gridStaticGeometryCache.remove(_gridStaticGeometryCache.keys.first);
  }
  _gridStaticGeometryCache[grid] = value;
  return value;
}

class _SceneModel {
  const _SceneModel({
    required this.parentName,
    required this.rows,
    required this.cols,
    required this.grid,
    required this.regions,
    required this.slots,
    required this.entrances,
    required this.exits,
    required this.towers,
    required this.pillarCells,
    required this.roadRects,
    required this.road2Rects,
    required this.lod,
    required this.staticSignature,
    required this.vehicleSignature,
    required this.dynamicSignature,
  });

  final String parentName;
  final int rows;
  final int cols;
  final ParkingGridModel grid;
  final List<_SceneRegion> regions;
  final List<_SceneSlot> slots;
  final List<GridRect> entrances;
  final List<GridRect> exits;
  final List<GridRect> towers;
  final List<math.Point<int>> pillarCells;
  final List<GridRect> roadRects;
  final List<GridRect> road2Rects;
  final _SceneLod lod;
  final int staticSignature;
  final int vehicleSignature;
  final int dynamicSignature;
}

class _SceneRegion {
  const _SceneRegion({
    required this.name,
    required this.rect,
    required this.status,
  });

  final String name;
  final GridRect rect;
  final ParkingSlotStatus status;
}

class _SceneSlot {
  const _SceneSlot({
    required this.groupName,
    required this.label,
    required this.no,
    required this.rect,
    required this.status,
    required this.category,
    required this.categoryLabel,
    required this.footprint,
  });

  final String groupName;
  final String label;
  final int? no;
  final GridRect rect;
  final ParkingSlotStatus status;
  final String category;
  final String categoryLabel;
  final String footprint;

  bool get hasVehicle =>
      status == ParkingSlotStatus.parked || status == ParkingSlotStatus.departureRequest;
}

bool _isStructuredParent(LocationModel location) {
  if (location.parkingGrid == null) return false;
  if (location.isCompositeParent) return true;
  return location.parkingGrid != null;
}

String _trimOrEmpty(Object? value) => (value ?? '').toString().trim();

ParkingGridCellType _cellAt(ParkingGridModel grid, int row, int col) {
  final index = row * grid.cols + col;
  if (index < 0 || index >= grid.cells.length) {
    return ParkingGridCellType.empty;
  }
  return grid.cellTypeAt(index);
}
String _normalizeName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');
String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

bool _isCompositeChildType(String? type) {
  final normalized = _trimOrEmpty(type).toLowerCase();
  return normalized == 'composite_child' || normalized == 'composite';
}

List<String> _parentAliases(LocationModel parent) {
  final aliases = <String>{};
  final values = <String?>[
    parent.locationName,
    parent.id,
    parent.parent,
  ];
  for (final value in values) {
    final trimmed = _trimOrEmpty(value);
    if (trimmed.isNotEmpty) {
      aliases.add(_nameKey(trimmed));
    }
  }
  return aliases.toList(growable: false);
}

bool _matchesParentRef(LocationModel parent, LocationModel child) {
  final aliases = _parentAliases(parent);
  final candidates = <String?>[
    child.parent,
    child.parentId,
  ];
  for (final candidate in candidates) {
    final key = _nameKey(_trimOrEmpty(candidate));
    if (key.isNotEmpty && aliases.contains(key)) {
      return true;
    }
  }
  return false;
}

bool _matchesAreaLoose(String parentArea, String childArea) {
  final a = _trimOrEmpty(parentArea);
  final b = _trimOrEmpty(childArea);
  if (a.isEmpty || b.isEmpty) return true;
  return a == b;
}

_SceneModel _buildScene({
  required LocationModel parent,
  required List<LocationModel> allLocations,
  required ParkingGridOverlay overlay,
}) {
  final grid = parent.parkingGrid!;
  final parentArea = _trimOrEmpty(parent.area);
  final parentName = _trimOrEmpty(parent.locationName);
  final overlayForParent = overlay.forParent(parent.locationName);
  final regions = <_SceneRegion>[];
  final slots = <_SceneSlot>[];
  final seenSlotKeys = <String>{};

  for (final location in allLocations) {
    if (!_isCompositeChildType(location.type)) continue;
    if (!_matchesParentRef(parent, location)) continue;
    if (!_matchesAreaLoose(parentArea, location.area)) continue;

    final childName = _trimOrEmpty(location.locationName).isEmpty
        ? '구역'
        : _trimOrEmpty(location.locationName);

    final rect = location.childRect?.normalized();
    if (rect != null) {
      regions.add(
        _SceneRegion(
          name: childName,
          rect: rect,
          status: overlayForParent.statusForChildAny(childName: childName),
        ),
      );
    }

    for (final slot in location.childSlots) {
      final rect = GridRect(
        r0: slot.r0,
        c0: slot.c0,
        r1: slot.r1,
        c1: slot.c1,
      ).normalized();
      final key = '${_nameKey(childName)}|${slot.no}|${rect.toKey()}';
      if (!seenSlotKeys.add(key)) continue;
      slots.add(
        _SceneSlot(
          groupName: childName,
          label: slot.label,
          no: slot.no <= 0 ? null : slot.no,
          rect: rect,
          status: overlayForParent.statusForSlot(
            childName: childName,
            no: slot.no <= 0 ? null : slot.no,
          ),
          category: slot.category,
          categoryLabel: slot.categoryLabel,
          footprint: slot.footprint,
        ),
      );
    }
  }

  if (slots.isEmpty) {
    for (final area in grid.parkingAreas) {
      final rect = GridRect(
        r0: area.r0,
        c0: area.c0,
        r1: area.r1,
        c1: area.c1,
      ).normalized();
      final key = 'fallback|${rect.toKey()}';
      if (!seenSlotKeys.add(key)) continue;
      slots.add(
        _SceneSlot(
          groupName: '주차면',
          label: area.label,
          no: null,
          rect: rect,
          status: ParkingSlotStatus.empty,
          category: area.categoryKey,
          categoryLabel: area.categoryLabel,
          footprint: area.footprintLabel,
        ),
      );
    }
  }

  final staticGeometry = _staticGeometryForGrid(grid);
  final pillarCells = staticGeometry.pillarCells;
  final roadRects = staticGeometry.roadRects;
  final road2Rects = staticGeometry.road2Rects;
  final entrances = grid.entranceRects
      .map((rect) => rect.normalized())
      .toList(growable: false);
  final exits = grid.exitRects
      .map((rect) => rect.normalized())
      .toList(growable: false);
  final towers = grid.towerRects
      .map((rect) => rect.normalized())
      .toList(growable: false);

  final cellCount = grid.rows * grid.cols;
  final slotCount = slots.length;
  final vehicleCount = slots.where((slot) => slot.hasVehicle).length;
  final lod = cellCount >= 640 || slotCount >= 220 || vehicleCount >= 160
      ? _SceneLod.overview
      : cellCount >= 240 || slotCount >= 80 || vehicleCount >= 60
          ? _SceneLod.simplified
          : _SceneLod.detailed;

  regions.sort((a, b) => a.rect.area.compareTo(b.rect.area));
  slots.sort((a, b) {
    final byRow = a.rect.top.compareTo(b.rect.top);
    if (byRow != 0) return byRow;
    return a.rect.left.compareTo(b.rect.left);
  });

  final staticSignature = Object.hash(
    parentName,
    grid.rows,
    grid.cols,
    staticGeometry.signature,
    Object.hashAll(
      regions.map(
        (region) => Object.hash(
          region.name,
          region.rect,
        ),
      ),
    ),
    Object.hashAll(
      slots.map(
        (slot) => Object.hash(
          slot.groupName,
          slot.label,
          slot.no,
          slot.rect,
          slot.category,
          slot.categoryLabel,
          slot.footprint,
        ),
      ),
    ),
    Object.hashAll(entrances),
    Object.hashAll(exits),
    Object.hashAll(towers),
    lod.index,
  );
  final vehicleSignature = Object.hash(
    Object.hashAll(
      slots.map(
        (slot) => Object.hash(
          slot.rect,
          slot.hasVehicle,
        ),
      ),
    ),
    lod.index,
  );
  final dynamicSignature = Object.hash(
    Object.hashAll(
      slots.map(
        (slot) => Object.hash(
          slot.groupName,
          slot.no,
          slot.rect,
          slot.status.index,
        ),
      ),
    ),
    lod.index,
  );

  return _SceneModel(
    parentName: parentName,
    rows: grid.rows,
    cols: grid.cols,
    grid: grid,
    regions: regions,
    slots: slots,
    entrances: entrances,
    exits: exits,
    towers: towers,
    pillarCells: pillarCells,
    roadRects: roadRects,
    road2Rects: road2Rects,
    lod: lod,
    staticSignature: staticSignature,
    vehicleSignature: vehicleSignature,
    dynamicSignature: dynamicSignature,
  );
}

List<GridRect> _mergeRoadRects(
  ParkingGridModel grid,
  Set<int> road2Set,
  bool road2,
) {
  final rows = grid.rows;
  final cols = grid.cols;
  final visited = Uint8List(rows * cols);
  final result = <GridRect>[];

  int indexOf(int row, int col) => row * cols + col;

  bool isVisited(int row, int col) => visited[indexOf(row, col)] != 0;

  void markVisited(int row, int col) {
    visited[indexOf(row, col)] = 1;
  }

  bool matches(int row, int col) {
    if (row < 0 || row >= rows || col < 0 || col >= cols) return false;
    final index = row * cols + col;
    if (_cellAt(grid, row, col) != ParkingGridCellType.road) return false;
    return road2Set.contains(index) == road2;
  }

  for (int row = 0; row < rows; row++) {
    for (int col = 0; col < cols; col++) {
      if (isVisited(row, col) || !matches(row, col)) continue;

      int width = 1;
      while (col + width < cols &&
          !isVisited(row, col + width) &&
          matches(row, col + width)) {
        width++;
      }

      int height = 1;
      bool canGrow = true;
      while (row + height < rows && canGrow) {
        for (int x = col; x < col + width; x++) {
          if (isVisited(row + height, x) || !matches(row + height, x)) {
            canGrow = false;
            break;
          }
        }
        if (canGrow) height++;
      }

      for (int y = row; y < row + height; y++) {
        for (int x = col; x < col + width; x++) {
          markVisited(y, x);
        }
      }

      result.add(
        GridRect(
          r0: row,
          c0: col,
          r1: row + height - 1,
          c1: col + width - 1,
        ),
      );
    }
  }
  return result;
}

class _IsoProjector {
  _IsoProjector({
    required this.size,
    required this.rows,
    required this.cols,
    required this.quarterTurns,
    required this.maxHeightUnits,
  }) {
    _resolve();
  }

  final Size size;
  final int rows;
  final int cols;
  final int quarterTurns;
  final double maxHeightUnits;
  late double _scale;
  late Offset _origin;

  double get pixelsPerUnit => _scale;

  void _resolve() {
    final corners = <Offset>[
      _projectRaw(0, 0, 0),
      _projectRaw(cols.toDouble(), 0, 0),
      _projectRaw(cols.toDouble(), rows.toDouble(), 0),
      _projectRaw(0, rows.toDouble(), 0),
      _projectRaw(0, 0, maxHeightUnits),
      _projectRaw(cols.toDouble(), 0, maxHeightUnits),
      _projectRaw(cols.toDouble(), rows.toDouble(), maxHeightUnits),
      _projectRaw(0, rows.toDouble(), maxHeightUnits),
    ];
    double minX = corners.first.dx;
    double maxX = corners.first.dx;
    double minY = corners.first.dy;
    double maxY = corners.first.dy;
    for (final point in corners.skip(1)) {
      minX = math.min(minX, point.dx);
      maxX = math.max(maxX, point.dx);
      minY = math.min(minY, point.dy);
      maxY = math.max(maxY, point.dy);
    }
    final width = math.max(1e-3, maxX - minX);
    final height = math.max(1e-3, maxY - minY);
    final availableWidth = math.max(0.0, size.width - 44);
    final availableHeight = math.max(0.0, size.height - 58);
    _scale = math.min(availableWidth / width, availableHeight / height);
    _origin = Offset(
      (size.width - width * _scale) / 2 - minX * _scale,
      (size.height - height * _scale) / 2 - minY * _scale,
    );
  }

  Offset project(double x, double y, double z) {
    final raw = _projectRaw(x, y, z);
    return Offset(_origin.dx + raw.dx * _scale, _origin.dy + raw.dy * _scale);
  }

  double depthForRect(GridRect rect) {
    return _projectRaw(
      rect.left + rect.width / 2,
      rect.top + rect.height / 2,
      0,
    ).dy;
  }

  Offset _projectRaw(double x, double y, double z) {
    final centerX = cols / 2;
    final centerY = rows / 2;
    final px = x - centerX;
    final py = y - centerY;
    final radians = (quarterTurns % 4) * math.pi / 2;
    final cosA = math.cos(radians);
    final sinA = math.sin(radians);
    final rx = px * cosA - py * sinA;
    final ry = px * sinA + py * cosA;
    return Offset(rx - ry, (rx + ry) * 0.58 - z);
  }
}

class _StaticScenePainter extends CustomPainter {
  const _StaticScenePainter({
    required this.scene,
    required this.tokens,
    required this.viewQuarterTurns,
  });

  final _SceneModel scene;
  final CommonUiTokens tokens;
  final int viewQuarterTurns;

  @override
  void paint(Canvas canvas, Size size) {
    final projector = _IsoProjector(
      size: size,
      rows: scene.rows,
      cols: scene.cols,
      quarterTurns: viewQuarterTurns,
      maxHeightUnits: scene.lod == _SceneLod.detailed ? 3.3 : 2.2,
    );

    final backgroundPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: <Color>[
          tokens.canvas,
          tokens.surface,
        ],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, backgroundPaint);

    final floorTop = tokens.isDark
        ? const Color(0xFF596271)
        : const Color(0xFFC7CDD5);
    _drawPrism(
      canvas,
      projector,
      0,
      0,
      scene.cols.toDouble(),
      scene.rows.toDouble(),
      0.18,
      topColor: floorTop,
      leftColor: _shade(floorTop, -0.10),
      rightColor: _shade(floorTop, -0.18),
      strokeColor: _shade(floorTop, -0.22).withOpacity(0.60),
    );

    _drawRoads(canvas, projector, scene.roadRects, false);
    _drawRoads(canvas, projector, scene.road2Rects, true);
    _drawRegions(canvas, projector);
    _drawSlots(canvas, projector);
    _drawPillars(canvas, projector);
    _drawTowers(canvas, projector);
    _drawGates(canvas, projector, scene.entrances, true);
    _drawGates(canvas, projector, scene.exits, false);
  }

  void _drawRoads(
    Canvas canvas,
    _IsoProjector projector,
    List<GridRect> rects,
    bool road2,
  ) {
    final topColor = road2
        ? (tokens.isDark ? const Color(0xFF333E4D) : const Color(0xFF788493))
        : (tokens.isDark ? const Color(0xFF3D4654) : const Color(0xFF8E98A5));
    final border = _shade(topColor, -0.20);
    final markerPaint = Paint()
      ..color = Colors.white.withOpacity(tokens.isDark ? 0.46 : 0.74)
      ..strokeWidth = scene.lod == _SceneLod.detailed ? 1.8 : 1.3
      ..strokeCap = StrokeCap.round;

    for (final rect in rects) {
      _drawTopPolygon(
        canvas,
        _rectTopPolygon(projector, rect, 0.025, inset: 0.035),
        fill: topColor,
        stroke: border,
      );
      if (scene.lod == _SceneLod.overview || projector.pixelsPerUnit < 7) continue;

      final centerX = rect.left + rect.width / 2;
      final centerY = rect.top + rect.height / 2;
      if (rect.width >= rect.height) {
        final start = projector.project(rect.left + 0.24, centerY, 0.04);
        final end = projector.project(rect.right + 0.76, centerY, 0.04);
        canvas.drawLine(start, end, markerPaint);
      } else {
        final start = projector.project(centerX, rect.top + 0.24, 0.04);
        final end = projector.project(centerX, rect.bottom + 0.76, 0.04);
        canvas.drawLine(start, end, markerPaint);
      }
    }
  }

  void _drawRegions(Canvas canvas, _IsoProjector projector) {
    if (scene.regions.isEmpty) return;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (int index = 0; index < scene.regions.length; index++) {
      final region = scene.regions[index];
      final base = index.isEven ? tokens.accent : tokens.info;
      _drawTopPolygon(
        canvas,
        _rectTopPolygon(projector, region.rect, 0.026, inset: 0.07),
        fill: base.withOpacity(scene.lod == _SceneLod.overview ? 0.06 : 0.10),
        stroke: base.withOpacity(0.26),
      );
      if (scene.lod == _SceneLod.overview) continue;
      final center = _rectCenter(projector, region.rect, 0.04);
      textPainter.text = TextSpan(
        text: region.name,
        style: TextStyle(
          fontSize: scene.lod == _SceneLod.detailed ? 12 : 10,
          fontWeight: FontWeight.w800,
          color: tokens.textPrimary.withOpacity(0.84),
        ),
      );
      textPainter.layout(maxWidth: 120);
      textPainter.paint(
        canvas,
        center.translate(-textPainter.width / 2, -textPainter.height / 2),
      );
    }
  }

  void _drawSlots(Canvas canvas, _IsoProjector projector) {
    if (scene.slots.isEmpty) return;

    if (scene.lod == _SceneLod.overview || projector.pixelsPerUnit < 5.5) {
      final path = Path();
      for (final slot in scene.slots) {
        final points = _rectTopPolygon(projector, slot.rect, 0.034, inset: 0.09);
        path.addPolygon(points, true);
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = tokens.borderStrong.withOpacity(0.40)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.9,
      );
      return;
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    for (final slot in scene.slots) {
      final top = _slotBaseColor(slot, tokens).withOpacity(tokens.isDark ? 0.72 : 0.94);
      final path = _pathFromPoints(
        _rectTopPolygon(projector, slot.rect, 0.034, inset: 0.08),
      );
      canvas.drawPath(path, Paint()..color = top);
      canvas.drawPath(
        path,
        Paint()
          ..color = tokens.borderStrong.withOpacity(0.34)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
      if (projector.pixelsPerUnit >= 7) {
        _drawCategoryMark(canvas, projector, slot);
      }

      final showLabel = projector.pixelsPerUnit >= 8.5 &&
          (scene.lod == _SceneLod.detailed || slot.rect.area >= 2);
      if (!showLabel) continue;
      final label = slot.no == null
          ? _compactSlotLabel(slot.categoryLabel, slot.label)
          : '';
      if (label.isEmpty) continue;
      final center = _rectCenter(projector, slot.rect, 0.055);
      textPainter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: scene.lod == _SceneLod.detailed ? 11 : 9,
          fontWeight: FontWeight.w900,
          color: tokens.textPrimary.withOpacity(0.72),
        ),
      );
      textPainter.layout(maxWidth: 60);
      textPainter.paint(
        canvas,
        center.translate(-textPainter.width / 2, -textPainter.height / 2),
      );
    }
  }

  void _drawCategoryMark(
    Canvas canvas,
    _IsoProjector projector,
    _SceneSlot slot,
  ) {
    final points = _rectTopPolygon(projector, slot.rect, 0.045, inset: 0.11);
    if (points.length < 4) return;
    final color = _categoryStripeColor(slot.category, slot.categoryLabel, tokens);
    canvas.drawLine(
      points[3],
      points[2],
      Paint()
        ..color = color.withOpacity(0.88)
        ..strokeWidth = scene.lod == _SceneLod.detailed ? 2.6 : 2.0
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawPillars(Canvas canvas, _IsoProjector projector) {
    final top = tokens.isDark ? const Color(0xFFB8C0CB) : const Color(0xFFE5E7EB);
    final cells = List<math.Point<int>>.of(scene.pillarCells)
      ..sort((a, b) {
        final ar = GridRect(r0: a.y, c0: a.x, r1: a.y, c1: a.x);
        final br = GridRect(r0: b.y, c0: b.x, r1: b.y, c1: b.x);
        return projector.depthForRect(ar).compareTo(projector.depthForRect(br));
      });
    for (final cell in cells) {
      if (scene.lod == _SceneLod.overview || projector.pixelsPerUnit < 7) {
        _drawFlatCell(
          canvas,
          projector,
          cell.y,
          cell.x,
          inset: 0.28,
          elevation: 0.04,
          fillColor: _shade(top, -0.06),
          strokeColor: _shade(top, -0.30),
        );
      } else {
        _drawPrism(
          canvas,
          projector,
          cell.x + 0.25,
          cell.y + 0.25,
          cell.x + 0.75,
          cell.y + 0.75,
          scene.lod == _SceneLod.detailed ? 1.10 : 0.54,
          topColor: top,
          leftColor: _shade(top, -0.12),
          rightColor: _shade(top, -0.22),
          strokeColor: _shade(top, -0.26).withOpacity(0.70),
        );
      }
    }
  }

  void _drawTowers(Canvas canvas, _IsoProjector projector) {
    final top = tokens.isDark ? const Color(0xFF8894A3) : const Color(0xFFCBD5E1);
    final towers = List<GridRect>.of(scene.towers)
      ..sort(
        (a, b) => projector.depthForRect(a).compareTo(projector.depthForRect(b)),
      );
    for (final rect in towers) {
      final height = scene.lod == _SceneLod.detailed ? 1.85 : 1.10;
      _drawPrism(
        canvas,
        projector,
        rect.left.toDouble(),
        rect.top.toDouble(),
        rect.right + 1.0,
        rect.bottom + 1.0,
        height,
        topColor: top,
        leftColor: _shade(top, -0.12),
        rightColor: _shade(top, -0.20),
        strokeColor: _shade(top, -0.26),
      );
      if (scene.lod == _SceneLod.overview || projector.pixelsPerUnit < 8) continue;
      final center = _rectCenter(projector, rect, height + 0.06);
      final painter = TextPainter(
        text: TextSpan(
          text: '주차타워',
          style: TextStyle(
            fontSize: scene.lod == _SceneLod.detailed ? 10 : 8,
            fontWeight: FontWeight.w900,
            color: tokens.textPrimary,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: 80);
      painter.paint(
        canvas,
        center.translate(-painter.width / 2, -painter.height / 2),
      );
    }
  }

  void _drawGates(
    Canvas canvas,
    _IsoProjector projector,
    List<GridRect> rects,
    bool isEntrance,
  ) {
    final label = isEntrance ? 'IN' : 'OUT';
    final base = isEntrance ? tokens.success : tokens.danger;
    final painter = TextPainter(textDirection: TextDirection.ltr);
    final orderedRects = List<GridRect>.of(rects)
      ..sort(
        (a, b) => projector.depthForRect(a).compareTo(projector.depthForRect(b)),
      );
    for (final rect in orderedRects) {
      final x0 = rect.left + 0.16;
      final y0 = rect.top + 0.18;
      final x1 = math.min(rect.right + 0.84, x0 + 0.34).toDouble();
      final y1 = math.min(rect.bottom + 0.82, y0 + 0.44).toDouble();
      _drawPrism(
        canvas,
        projector,
        x0,
        y0,
        x1,
        y1,
        scene.lod == _SceneLod.overview ? 0.28 : 0.48,
        topColor: base.withOpacity(0.92),
        leftColor: _shade(base, -0.12),
        rightColor: _shade(base, -0.22),
        strokeColor: _shade(base, -0.28),
      );

      if (scene.lod != _SceneLod.overview && projector.pixelsPerUnit >= 7) {
        final y = rect.top + rect.height / 2;
        final armStart = projector.project(rect.left + 0.36, y, 0.32);
        final armEnd = projector.project(rect.right + 0.78, y, 0.32);
        canvas.drawLine(
          armStart,
          armEnd,
          Paint()
            ..color = Colors.white.withOpacity(0.92)
            ..strokeWidth = 3.0
            ..strokeCap = StrokeCap.round,
        );
      }

      final center = _rectCenter(
        projector,
        rect,
        scene.lod == _SceneLod.overview ? 0.34 : 0.58,
      );
      painter.text = TextSpan(
        text: label,
        style: TextStyle(
          fontSize: scene.lod == _SceneLod.overview ? 8 : 10,
          fontWeight: FontWeight.w900,
          color: tokens.textPrimary,
        ),
      );
      painter.layout(maxWidth: 40);
      painter.paint(
        canvas,
        center.translate(-painter.width / 2, -painter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StaticScenePainter oldDelegate) {
    return oldDelegate.scene.staticSignature != scene.staticSignature ||
        oldDelegate.tokens != tokens ||
        oldDelegate.viewQuarterTurns != viewQuarterTurns;
  }
}

class _VehicleScenePainter extends CustomPainter {
  const _VehicleScenePainter({
    required this.scene,
    required this.tokens,
    required this.viewQuarterTurns,
  });

  final _SceneModel scene;
  final CommonUiTokens tokens;
  final int viewQuarterTurns;

  @override
  void paint(Canvas canvas, Size size) {
    final projector = _IsoProjector(
      size: size,
      rows: scene.rows,
      cols: scene.cols,
      quarterTurns: viewQuarterTurns,
      maxHeightUnits: scene.lod == _SceneLod.detailed ? 3.3 : 2.2,
    );
    final vehicles = scene.slots.where((slot) => slot.hasVehicle).toList();
    vehicles.sort(
      (a, b) => projector.depthForRect(a.rect).compareTo(
            projector.depthForRect(b.rect),
          ),
    );

    if (scene.lod == _SceneLod.overview || projector.pixelsPerUnit < 5.5) {
      _drawOverviewVehicles(canvas, projector, vehicles);
      return;
    }

    for (final slot in vehicles) {
      _drawVehicle(canvas, projector, slot);
    }
  }

  void _drawOverviewVehicles(
    Canvas canvas,
    _IsoProjector projector,
    List<_SceneSlot> vehicles,
  ) {
    final shadowPath = Path();
    final vehiclePath = Path();
    for (final slot in vehicles) {
      final body = _vehicleRect(slot.rect);
      shadowPath.addPolygon(
        <Offset>[
          projector.project(body.$1 + 0.05, body.$2 + 0.05, 0.045),
          projector.project(body.$3 + 0.05, body.$2 + 0.05, 0.045),
          projector.project(body.$3 + 0.05, body.$4 + 0.05, 0.045),
          projector.project(body.$1 + 0.05, body.$4 + 0.05, 0.045),
        ],
        true,
      );
      vehiclePath.addPolygon(
        <Offset>[
          projector.project(body.$1, body.$2, 0.07),
          projector.project(body.$3, body.$2, 0.07),
          projector.project(body.$3, body.$4, 0.07),
          projector.project(body.$1, body.$4, 0.07),
        ],
        true,
      );
    }
    canvas.drawPath(
      shadowPath,
      Paint()..color = Colors.black.withOpacity(tokens.isDark ? 0.16 : 0.10),
    );
    canvas.drawPath(vehiclePath, Paint()..color = _vehicleBodyColor(tokens));
    canvas.drawPath(
      vehiclePath,
      Paint()
        ..color = tokens.borderStrong.withOpacity(0.38)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
  }

  void _drawVehicle(
    Canvas canvas,
    _IsoProjector projector,
    _SceneSlot slot,
  ) {
    final body = _vehicleRect(slot.rect);
    final x0 = body.$1;
    final y0 = body.$2;
    final x1 = body.$3;
    final y1 = body.$4;
    final horizontal = slot.rect.width >= slot.rect.height;
    final bodyColor = _vehicleBodyColor(tokens);
    final roofColor = tokens.isDark
        ? const Color(0xFF738093)
        : const Color(0xFFD7DEE7);
    final stroke = tokens.borderStrong.withOpacity(0.46);

    final shadow = <Offset>[
      projector.project(x0 + 0.07, y0 + 0.07, 0.045),
      projector.project(x1 + 0.07, y0 + 0.07, 0.045),
      projector.project(x1 + 0.07, y1 + 0.07, 0.045),
      projector.project(x0 + 0.07, y1 + 0.07, 0.045),
    ];
    canvas.drawPath(
      _pathFromPoints(shadow),
      Paint()..color = Colors.black.withOpacity(tokens.isDark ? 0.20 : 0.14),
    );

    final bodyHeight = scene.lod == _SceneLod.detailed ? 0.24 : 0.18;
    _drawPrismAt(
      canvas,
      projector,
      x0,
      y0,
      x1,
      y1,
      0.055,
      bodyHeight,
      topColor: bodyColor,
      leftColor: _shade(bodyColor, -0.14),
      rightColor: _shade(bodyColor, -0.24),
      strokeColor: stroke,
    );

    if (scene.lod != _SceneLod.detailed || projector.pixelsPerUnit < 12) {
      return;
    }

    final roofInsetX = horizontal ? (x1 - x0) * 0.23 : (x1 - x0) * 0.12;
    final roofInsetY = horizontal ? (y1 - y0) * 0.12 : (y1 - y0) * 0.23;
    final rx0 = x0 + roofInsetX;
    final ry0 = y0 + roofInsetY;
    final rx1 = x1 - roofInsetX;
    final ry1 = y1 - roofInsetY;
    _drawPrismAt(
      canvas,
      projector,
      rx0,
      ry0,
      rx1,
      ry1,
      0.055 + bodyHeight * 0.72,
      0.16,
      topColor: roofColor,
      leftColor: _shade(roofColor, -0.14),
      rightColor: _shade(roofColor, -0.24),
      strokeColor: stroke.withOpacity(0.70),
    );
  }

  @override
  bool shouldRepaint(covariant _VehicleScenePainter oldDelegate) {
    return oldDelegate.scene.vehicleSignature != scene.vehicleSignature ||
        oldDelegate.tokens != tokens ||
        oldDelegate.viewQuarterTurns != viewQuarterTurns;
  }
}

class _DeparturePulsePainter extends CustomPainter {
  _DeparturePulsePainter({
    required this.scene,
    required this.tokens,
    required this.viewQuarterTurns,
    required this.pulse,
    required this.reduceMotion,
  }) : super(repaint: reduceMotion ? null : pulse);

  final _SceneModel scene;
  final CommonUiTokens tokens;
  final int viewQuarterTurns;
  final Animation<double> pulse;
  final bool reduceMotion;

  @override
  void paint(Canvas canvas, Size size) {
    final departures = scene.slots
        .where((slot) => slot.status == ParkingSlotStatus.departureRequest)
        .toList(growable: false);
    if (departures.isEmpty) return;

    final projector = _IsoProjector(
      size: size,
      rows: scene.rows,
      cols: scene.cols,
      quarterTurns: viewQuarterTurns,
      maxHeightUnits: scene.lod == _SceneLod.detailed ? 3.3 : 2.2,
    );
    final value = reduceMotion ? 0.72 : pulse.value;
    final color = tokens.statusDepartureRequested;
    final fillOpacity = 0.08 + value * 0.08;
    final strokeOpacity = 0.46 + value * 0.34;
    final strokeWidth = scene.lod == _SceneLod.overview
        ? 1.7 + value * 0.8
        : 2.1 + value * 1.1;
    final textPainter = TextPainter(textDirection: TextDirection.ltr);

    for (final slot in departures) {
      final path = _pathFromPoints(
        _rectTopPolygon(projector, slot.rect, 0.075, inset: 0.035),
      );
      canvas.drawPath(
        path,
        Paint()..color = color.withOpacity(fillOpacity),
      );
      canvas.drawPath(
        path,
        Paint()
          ..color = color.withOpacity(strokeOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth,
      );
      if (scene.lod == _SceneLod.overview) continue;

      final center = _rectCenter(
        projector,
        slot.rect,
        scene.lod == _SceneLod.detailed ? 0.56 : 0.42,
      );
      textPainter.text = TextSpan(
        text: '출차 요청',
        style: TextStyle(
          fontSize: scene.lod == _SceneLod.detailed ? 10 : 8,
          fontWeight: FontWeight.w900,
          color: tokens.onStatusDepartureRequestedContainer,
          backgroundColor: tokens.statusDepartureRequestedContainer.withOpacity(0.94),
        ),
      );
      textPainter.layout(maxWidth: 72);
      textPainter.paint(
        canvas,
        center.translate(-textPainter.width / 2, -textPainter.height / 2),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DeparturePulsePainter oldDelegate) {
    return oldDelegate.scene.dynamicSignature != scene.dynamicSignature ||
        oldDelegate.tokens != tokens ||
        oldDelegate.viewQuarterTurns != viewQuarterTurns ||
        oldDelegate.reduceMotion != reduceMotion;
  }
}

(double, double, double, double) _vehicleRect(GridRect rect) {
  final horizontal = rect.width >= rect.height;
  final compact = rect.area <= 2;
  final insetX = horizontal
      ? (compact ? 0.20 : 0.17)
      : (compact ? 0.27 : 0.23);
  final insetY = horizontal
      ? (compact ? 0.27 : 0.23)
      : (compact ? 0.20 : 0.17);
  return (
    rect.left + insetX,
    rect.top + insetY,
    rect.right + 1 - insetX,
    rect.bottom + 1 - insetY,
  );
}

Color _vehicleBodyColor(CommonUiTokens tokens) {
  return tokens.isDark ? const Color(0xFFCBD3DE) : const Color(0xFFF1F4F8);
}

List<Offset> _rectTopPolygon(
  _IsoProjector projector,
  GridRect rect,
  double elevation, {
  double inset = 0,
}) {
  final left = rect.left + inset;
  final top = rect.top + inset;
  final right = rect.right + 1 - inset;
  final bottom = rect.bottom + 1 - inset;
  return <Offset>[
    projector.project(left, top, elevation),
    projector.project(right, top, elevation),
    projector.project(right, bottom, elevation),
    projector.project(left, bottom, elevation),
  ];
}

Offset _rectCenter(_IsoProjector projector, GridRect rect, double elevation) {
  return projector.project(
    rect.left + rect.width / 2,
    rect.top + rect.height / 2,
    elevation,
  );
}

Path _pathFromPoints(List<Offset> points) {
  final path = Path();
  if (points.isEmpty) return path;
  path.moveTo(points.first.dx, points.first.dy);
  for (final point in points.skip(1)) {
    path.lineTo(point.dx, point.dy);
  }
  path.close();
  return path;
}

void _drawTopPolygon(
  Canvas canvas,
  List<Offset> points, {
  required Color fill,
  required Color stroke,
}) {
  final path = _pathFromPoints(points);
  canvas.drawPath(path, Paint()..color = fill);
  canvas.drawPath(
    path,
    Paint()
      ..color = stroke
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0,
  );
}

void _drawPrism(
  Canvas canvas,
  _IsoProjector projector,
  double x0,
  double y0,
  double x1,
  double y1,
  double height, {
  required Color topColor,
  required Color leftColor,
  required Color rightColor,
  required Color strokeColor,
}) {
  _drawPrismAt(
    canvas,
    projector,
    x0,
    y0,
    x1,
    y1,
    0,
    height,
    topColor: topColor,
    leftColor: leftColor,
    rightColor: rightColor,
    strokeColor: strokeColor,
  );
}

void _drawPrismAt(
  Canvas canvas,
  _IsoProjector projector,
  double x0,
  double y0,
  double x1,
  double y1,
  double baseZ,
  double height, {
  required Color topColor,
  required Color leftColor,
  required Color rightColor,
  required Color strokeColor,
}) {
  final topZ = baseZ + height;
  final bl = projector.project(x0, y0, baseZ);
  final br = projector.project(x1, y0, baseZ);
  final tr = projector.project(x1, y1, baseZ);
  final tl = projector.project(x0, y1, baseZ);

  final tbl = projector.project(x0, y0, topZ);
  final tbr = projector.project(x1, y0, topZ);
  final ttr = projector.project(x1, y1, topZ);
  final ttl = projector.project(x0, y1, topZ);

  final leftSide = _pathFromPoints(<Offset>[bl, tl, ttl, tbl]);
  final rightSide = _pathFromPoints(<Offset>[br, tr, ttr, tbr]);
  final top = _pathFromPoints(<Offset>[tbl, tbr, ttr, ttl]);

  canvas.drawPath(leftSide, Paint()..color = leftColor);
  canvas.drawPath(rightSide, Paint()..color = rightColor);
  canvas.drawPath(top, Paint()..color = topColor);

  final strokePaint = Paint()
    ..color = strokeColor
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  canvas.drawPath(leftSide, strokePaint);
  canvas.drawPath(rightSide, strokePaint);
  canvas.drawPath(top, strokePaint);
}

void _drawFlatCell(
  Canvas canvas,
  _IsoProjector projector,
  int row,
  int col, {
  required double inset,
  required double elevation,
  required Color fillColor,
  required Color strokeColor,
}) {
  final points = <Offset>[
    projector.project(col + inset, row + inset, elevation),
    projector.project(col + 1 - inset, row + inset, elevation),
    projector.project(col + 1 - inset, row + 1 - inset, elevation),
    projector.project(col + inset, row + 1 - inset, elevation),
  ];
  _drawTopPolygon(canvas, points, fill: fillColor, stroke: strokeColor);
}

Color _shade(Color color, double delta) {
  final hsl = HSLColor.fromColor(color);
  final lightness = (hsl.lightness + delta).clamp(0.0, 1.0).toDouble();
  return hsl.withLightness(lightness).toColor();
}

Color _slotBaseColor(_SceneSlot slot, CommonUiTokens tokens) {
  if (_isEvCategory(slot.category, slot.categoryLabel)) {
    return tokens.isDark ? const Color(0xFF213E37) : const Color(0xFFEAF8F1);
  }
  if (_isDisabledCategory(slot.category, slot.categoryLabel)) {
    return tokens.isDark ? const Color(0xFF302B46) : const Color(0xFFF0EDFA);
  }
  if (_isPregnantCategory(slot.category, slot.categoryLabel)) {
    return tokens.isDark ? const Color(0xFF482C3D) : const Color(0xFFFCEEF6);
  }
  return tokens.isDark ? const Color(0xFF454E5C) : const Color(0xFFF4F6F8);
}

Color _categoryStripeColor(
  String category,
  String categoryLabel,
  CommonUiTokens tokens,
) {
  if (_isEvCategory(category, categoryLabel)) {
    return tokens.success;
  }
  if (_isDisabledCategory(category, categoryLabel)) {
    return tokens.info;
  }
  if (_isPregnantCategory(category, categoryLabel)) {
    return tokens.warning;
  }
  return tokens.borderStrong;
}

bool _isEvCategory(String a, String b) {
  final value = '${a.toLowerCase()} ${b.toLowerCase()}';
  return value.contains('ev') || value.contains('전기');
}

bool _isDisabledCategory(String a, String b) {
  final value = '${a.toLowerCase()} ${b.toLowerCase()}';
  return value.contains('disabled') || value.contains('장애');
}

bool _isPregnantCategory(String a, String b) {
  final value = '${a.toLowerCase()} ${b.toLowerCase()}';
  return value.contains('pregnant') || value.contains('임산');
}

String _compactSlotLabel(String a, String b) {
  final raw = _trimOrEmpty(a).isNotEmpty ? _trimOrEmpty(a) : _trimOrEmpty(b);
  if (raw.isEmpty) return '';
  if (_isEvCategory(raw, raw)) return 'EV';
  if (_isDisabledCategory(raw, raw)) return '장애';
  if (_isPregnantCategory(raw, raw)) return '임산부';
  if (raw.contains('경')) return '경';
  if (raw.contains('확장')) return '확장';
  if (raw.contains('일반')) return '일반';
  return raw.length > 4 ? raw.substring(0, 4) : raw;
}
