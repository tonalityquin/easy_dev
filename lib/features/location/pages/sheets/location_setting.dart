import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/models/grid_rect.dart';
import '../../domain/models/parking_grid_model.dart';
import 'widgets/location_draft.dart';
import 'widgets/parking_grid_2d_editor.dart';
import 'widgets/parking_grid_child_rect_selector.dart';

enum _LocationEntryMode { structured, plainText }
enum _CreateMode { parent, child }

class LocationSettingBottomSheet extends StatefulWidget {
  final ValueChanged<LocationDraft> onSave;
  final Set<String> existingNameKeysInArea;
  final Set<String> existingChildCompositeKeysInArea;
  final List<String> parentNamesInArea;
  final Map<String, ParkingGridModel> parentParkingGridsByParentKey;
  final Map<String, List<GridRect>> existingChildRectsByParentKey;

  final String? editingParentName;
  final ParkingGridModel? editingParentParkingGrid;


  final String? editingChildId;
  final String? editingChildParentName;
  final String? editingChildName;
  final int? editingChildCapacity;
  final GridRect? editingChildRect;
  final bool? editingChildIsTower;

  final String? editingPlainTextId;
  final String? editingPlainTextName;
  final int? editingPlainTextCapacity;

  const LocationSettingBottomSheet({
    super.key,
    required this.onSave,
    required this.existingNameKeysInArea,
    required this.existingChildCompositeKeysInArea,
    required this.parentNamesInArea,
    required this.parentParkingGridsByParentKey,
    this.existingChildRectsByParentKey = const <String, List<GridRect>>{},
    this.editingParentName,
    this.editingParentParkingGrid,
    this.editingChildId,
    this.editingChildParentName,
    this.editingChildName,
    this.editingChildCapacity,
    this.editingChildRect,
    this.editingChildIsTower,
    this.editingPlainTextId,
    this.editingPlainTextName,
    this.editingPlainTextCapacity,
  });

  @override
  State<LocationSettingBottomSheet> createState() => _LocationSettingBottomSheetState();
}

class _LocationSettingBottomSheetState extends State<LocationSettingBottomSheet> {
  _LocationEntryMode _entryMode = _LocationEntryMode.structured;
  _CreateMode _mode = _CreateMode.parent;

  bool get _isParentEdit => widget.editingParentName != null && widget.editingParentParkingGrid != null;

  bool get _isChildEdit => widget.editingChildId != null &&
      widget.editingChildParentName != null &&
      widget.editingChildName != null &&
      widget.editingChildCapacity != null &&
      widget.editingChildRect != null;

  bool get _isPlainTextEdit =>
      widget.editingPlainTextId != null && widget.editingPlainTextName != null;

  String? _editingChildOriginalCompositeKey;
  String? _editingPlainTextOriginalNameKey;

  bool _childIsTower = false;

  final TextEditingController _parentController = TextEditingController();

  static const int _minGridSize = 2;
  static const int _maxGridSize = 20;
  int _gridSize = 6;

  GridEditTool _tool = GridEditTool.empty;

  late List<ParkingGridCellType> _gridCells;
  Set<int> _road2Cells = <int>{};

  Map<EdgePlacement, WallGroupId?> _walls = <EdgePlacement, WallGroupId?>{};
  Map<WallGroupId, String> _wallGroups = <WallGroupId, String>{};
  Set<EdgePlacement> _selectedWalls = <EdgePlacement>{};
  int _wallGroupSeq = 0;

  List<ParkingArea> _parkingAreas = <ParkingArea>[];

  List<GridRect> _entranceRects = <GridRect>[];
  List<GridRect> _exitRects = <GridRect>[];
  List<GridRect> _towerRects = <GridRect>[];

  String? _selectedParent;
  final TextEditingController _childController = TextEditingController();
  final TextEditingController _capacityController = TextEditingController();
  final TextEditingController _plainTextNameController = TextEditingController();
  final TextEditingController _plainTextCapacityController = TextEditingController();

  ParkingGridModel? _selectedParentGrid;
  GridRect? _selectedChildRect;

  bool _childSquareLock = false;

  String? _errorMessage;

  final TextEditingController _tlRController = TextEditingController();
  final TextEditingController _tlCController = TextEditingController();
  final TextEditingController _trRController = TextEditingController();
  final TextEditingController _trCController = TextEditingController();
  final TextEditingController _blRController = TextEditingController();
  final TextEditingController _blCController = TextEditingController();
  final TextEditingController _brRController = TextEditingController();
  final TextEditingController _brCController = TextEditingController();

  String _normalizeName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

  String _childCompositeKey(String parent, String child) {
    return '${_nameKey(parent)}|${_nameKey(child)}';
  }

  void _clearChildRectInputs() {
    _tlRController.clear();
    _tlCController.clear();
    _trRController.clear();
    _trCController.clear();
    _blRController.clear();
    _blCController.clear();
    _brRController.clear();
    _brCController.clear();
  }

  void _syncChildRectInputsFromRect(GridRect? rect) {
    if (rect == null) {
      _clearChildRectInputs();
      return;
    }
    final r = rect.normalized();
    _tlRController.text = r.r0.toString();
    _tlCController.text = r.c0.toString();
    _trRController.text = r.r0.toString();
    _trCController.text = r.c1.toString();
    _blRController.text = r.r1.toString();
    _blCController.text = r.c0.toString();
    _brRController.text = r.r1.toString();
    _brCController.text = r.c1.toString();
  }

  int? _parseInt(TextEditingController c) {
    final t = c.text.trim();
    if (t.isEmpty) return null;
    return int.tryParse(t);
  }

  bool _applyChildRectFromInputs({
    required String parent,
    required ParkingGridModel grid,
  }) {
    if (_childIsTower) {
      _setError('주차 타워 모드에서는 좌표 입력 대신 타워 영역을 선택하세요.');
      return false;
    }

    final rows = grid.rows;
    final cols = grid.cols;

    final values = <int?>[
      _parseInt(_tlRController),
      _parseInt(_tlCController),
      _parseInt(_trRController),
      _parseInt(_trCController),
      _parseInt(_blRController),
      _parseInt(_blCController),
      _parseInt(_brRController),
      _parseInt(_brCController),
    ];

    if (values.any((v) => v == null)) {
      _setError('좌표를 모두 입력하세요.');
      return false;
    }

    final rVals = <int>[values[0]!, values[2]!, values[4]!, values[6]!];
    final cVals = <int>[values[1]!, values[3]!, values[5]!, values[7]!];

    if (rVals.any((v) => v < 0 || v >= rows) || cVals.any((v) => v < 0 || v >= cols)) {
      _setError('좌표는 그리드 범위 내(행 0~${rows - 1}, 열 0~${cols - 1})여야 합니다.');
      return false;
    }

    var r0 = rVals.reduce(min);
    var r1 = rVals.reduce(max);
    var c0 = cVals.reduce(min);
    var c1 = cVals.reduce(max);

    if (_childSquareLock) {
      final h = r1 - r0;
      final w = c1 - c0;
      var side = max(h, w);
      side = min(side, min((rows - 1) - r0, (cols - 1) - c0));
      r1 = r0 + side;
      c1 = c0 + side;
    }

    final rect = GridRect(r0: r0, c0: c0, r1: r1, c1: c1).normalized();

    if (_overlapsExistingChildRects(
      parent,
      rect,
      excludeExactRect: _isChildEdit ? widget.editingChildRect : null,
    )) {
      _setError('선택한 영역이 기존 자식 구역과 겹칩니다. 다른 영역을 지정하세요.');
      return false;
    }

    _clearError();
    setState(() {
      _selectedChildRect = rect;
    });
    _syncChildRectInputsFromRect(rect);
    return true;
  }

  void _syncSelectedParentGrid({bool resetChildSelection = true}) {
    final p = (_selectedParent ?? '').trim();
    if (p.isEmpty) {
      setState(() {
        _selectedParentGrid = null;
        _selectedChildRect = null;
      });
      _clearChildRectInputs();
      return;
    }

    final pk = _nameKey(p);
    final g = widget.parentParkingGridsByParentKey[pk];

    setState(() {
      _selectedParentGrid = g;
      if (resetChildSelection) {
        _selectedChildRect = null;
      }
    });

    if (resetChildSelection) {
      _clearChildRectInputs();
    }
  }

  @override
  void initState() {
    super.initState();

    if (_isPlainTextEdit) {
      _entryMode = _LocationEntryMode.plainText;
      _plainTextNameController.text = (widget.editingPlainTextName ?? '').trim();
      final cap = widget.editingPlainTextCapacity;
      _plainTextCapacityController.text = cap == null || cap <= 0 ? '' : cap.toString();
      _editingPlainTextOriginalNameKey = _nameKey(_plainTextNameController.text);
    } else if (_isChildEdit) {
      _entryMode = _LocationEntryMode.structured;
      _mode = _CreateMode.child;
      _selectedParent = (widget.editingChildParentName ?? '').trim();
    } else {
      _entryMode = _LocationEntryMode.structured;
      if (widget.parentNamesInArea.isNotEmpty) {
        _selectedParent = widget.parentNamesInArea.first;
      }
    }

    _gridCells = List<ParkingGridCellType>.filled(
      _gridSize * _gridSize,
      ParkingGridCellType.empty,
      growable: false,
    );

    _parkingAreas = <ParkingArea>[];
    _road2Cells = <int>{};
    _entranceRects = <GridRect>[];
    _exitRects = <GridRect>[];
    _towerRects = <GridRect>[];

    if (_isParentEdit) {
      _entryMode = _LocationEntryMode.structured;
      _mode = _CreateMode.parent;
      _parentController.text = (widget.editingParentName ?? '').trim();
      final g = widget.editingParentParkingGrid;
      if (g != null) {
        _applyParentGridForEdit(g);
      }
    }

    if (_isChildEdit) {
      _entryMode = _LocationEntryMode.structured;
      _mode = _CreateMode.child;
      _selectedParent = (widget.editingChildParentName ?? '').trim();
      _childController.text = (widget.editingChildName ?? '').trim();
      _capacityController.text = (widget.editingChildCapacity ?? 0).toString();
      _selectedChildRect = widget.editingChildRect?.normalized();
      _syncChildRectInputsFromRect(_selectedChildRect);

      _childIsTower = widget.editingChildIsTower == true;
      if (_childIsTower) {
        _childSquareLock = false;
      }

      _editingChildOriginalCompositeKey = _childCompositeKey(
        (_selectedParent ?? '').trim(),
        _childController.text,
      );
    }

    _syncSelectedParentGrid(resetChildSelection: !_isChildEdit);
  }

  @override
  void dispose() {
    _parentController.dispose();
    _childController.dispose();
    _capacityController.dispose();
    _plainTextNameController.dispose();
    _plainTextCapacityController.dispose();

    _tlRController.dispose();
    _tlCController.dispose();
    _trRController.dispose();
    _trCController.dispose();
    _blRController.dispose();
    _blCController.dispose();
    _brRController.dispose();
    _brCController.dispose();

    super.dispose();
  }

  void _setError(String msg) => setState(() => _errorMessage = msg);
  void _clearError() => setState(() => _errorMessage = null);

  void _setTool(GridEditTool next) {
    setState(() {
      _tool = next;
      if (_tool != GridEditTool.wallSelect) {
        _selectedWalls = <EdgePlacement>{};
      }
    });
  }

  WallGroupId _newWallGroupId() {
    _wallGroupSeq++;
    return 'wg_${DateTime.now().microsecondsSinceEpoch}_${_wallGroupSeq}';
  }

  void _cleanupWallGroups() {
    final used = _walls.values.whereType<WallGroupId>().toSet();
    _wallGroups.removeWhere((id, _) => !used.contains(id));
  }

  WallGroupId? _findGroupIdByName(String name) {
    final target = name.trim();
    if (target.isEmpty) return null;
    for (final e in _wallGroups.entries) {
      if (e.value.trim() == target) return e.key;
    }
    return null;
  }

  bool _rectInBounds(GridRect r, int rows, int cols) {
    final n = r.normalized();
    if (n.r0 < 0 || n.c0 < 0) return false;
    if (n.r1 >= rows || n.c1 >= cols) return false;
    return true;
  }

  List<GridRect> _filterRectsWithin(List<GridRect> list, int rows, int cols) {
    final out = <GridRect>[];
    for (final r in list) {
      final n = r.normalized();
      if (_rectInBounds(n, rows, cols)) out.add(n);
    }
    return <GridRect>{...out}.toList(growable: false);
  }

  void _applyParentGridForEdit(ParkingGridModel grid) {
    final target = max(_minGridSize, min(_maxGridSize, max(grid.rows, grid.cols)));
    final oldRows = max(0, grid.rows);
    final oldCols = max(0, grid.cols);

    final nextCells = List<ParkingGridCellType>.filled(
      target * target,
      ParkingGridCellType.empty,
      growable: false,
    );

    final copyRows = min(target, oldRows);
    final copyCols = min(target, oldCols);

    for (int r = 0; r < copyRows; r++) {
      for (int c = 0; c < copyCols; c++) {
        final oldIdx = r * oldCols + c;
        final newIdx = r * target + c;
        if (oldIdx >= 0 && oldIdx < grid.cells.length) {
          nextCells[newIdx] = grid.cells[oldIdx];
        }
      }
    }

    final nextRoad2 = <int>{};
    for (final idx in grid.road2Cells) {
      final r = idx ~/ oldCols;
      final c = idx % oldCols;
      if (r < 0 || c < 0) continue;
      if (r >= copyRows || c >= copyCols) continue;
      final newIdx = r * target + c;
      if (newIdx < 0 || newIdx >= nextCells.length) continue;
      if (nextCells[newIdx] == ParkingGridCellType.road) nextRoad2.add(newIdx);
    }

    final nextWalls = <EdgePlacement, WallGroupId?>{};
    for (final e in grid.walls.entries) {
      try {
        final ep = EdgePlacement.fromKey(e.key);
        if (!isEdgeValid(ep, target, target)) continue;
        nextWalls[ep] = e.value;
      } catch (_) {}
    }

    final nextGroups = Map<WallGroupId, String>.from(grid.wallGroups);

    final nextParkingAreas = <ParkingArea>[];
    for (final a in grid.parkingAreas) {
      final r1 = a.r0 + a.kind.h - 1;
      final c1 = a.c0 + a.kind.w - 1;
      if (a.r0 < 0 || a.c0 < 0) continue;
      if (r1 >= target || c1 >= target) continue;
      nextParkingAreas.add(a);
    }

    var entranceRects = _filterRectsWithin(grid.entranceRects, target, target);
    var exitRects = _filterRectsWithin(grid.exitRects, target, target);
    final towerRects = _filterRectsWithin(grid.towerRects, target, target);

    final legacyE = grid.entranceGate;
    final legacyX = grid.exitGate;

    if (entranceRects.isEmpty && legacyE != null) {
      entranceRects = <GridRect>[GridRect(r0: legacyE.r, c0: legacyE.c, r1: legacyE.r, c1: legacyE.c)];
    }

    if (exitRects.isEmpty && legacyX != null) {
      exitRects = <GridRect>[GridRect(r0: legacyX.r, c0: legacyX.c, r1: legacyX.r, c1: legacyX.c)];
    }

    _gridSize = target;
    _tool = GridEditTool.empty;
    _gridCells = nextCells;
    _road2Cells = nextRoad2;
    _walls = nextWalls;
    _wallGroups = nextGroups;
    _selectedWalls = <EdgePlacement>{};
    _parkingAreas = nextParkingAreas;
    _entranceRects = entranceRects;
    _exitRects = exitRects;
    _towerRects = towerRects;

    _cleanupWallGroups();
  }

  void _resizeGridPreserving({required int nextSize}) {
    if (nextSize == _gridSize) return;

    final from = _gridSize;
    final oldCells = _gridCells;
    final oldRoad2 = _road2Cells;

    final to = max(_minGridSize, min(_maxGridSize, nextSize));

    final nextCells = List<ParkingGridCellType>.filled(
      to * to,
      ParkingGridCellType.empty,
      growable: false,
    );

    final copy = min(from, to);
    for (int r = 0; r < copy; r++) {
      for (int c = 0; c < copy; c++) {
        final oldIdx = r * from + c;
        final newIdx = r * to + c;
        if (oldIdx >= 0 && oldIdx < oldCells.length) {
          nextCells[newIdx] = oldCells[oldIdx];
        }
      }
    }

    final nextRoad2 = <int>{};
    for (final idx in oldRoad2) {
      final r = idx ~/ from;
      final c = idx % from;
      if (r < 0 || c < 0) continue;
      if (r >= copy || c >= copy) continue;
      final newIdx = r * to + c;
      if (newIdx < 0 || newIdx >= nextCells.length) continue;
      if (nextCells[newIdx] == ParkingGridCellType.road) nextRoad2.add(newIdx);
    }

    final nextWalls = <EdgePlacement, WallGroupId?>{};
    for (final e in _walls.entries) {
      final ep = e.key;
      if (!isEdgeValid(ep, to, to)) continue;
      nextWalls[ep] = e.value;
    }

    final nextGroups = Map<WallGroupId, String>.from(_wallGroups);

    final nextParkingAreas = <ParkingArea>[];
    for (final a in _parkingAreas) {
      final r1 = a.r0 + a.kind.h - 1;
      final c1 = a.c0 + a.kind.w - 1;
      if (a.r0 < 0 || a.c0 < 0) continue;
      if (r1 >= to || c1 >= to) continue;
      nextParkingAreas.add(a);
    }

    final nextEntrances = _filterRectsWithin(_entranceRects, to, to);
    final nextExits = _filterRectsWithin(_exitRects, to, to);
    final nextTowers = _filterRectsWithin(_towerRects, to, to);

    setState(() {
      _gridSize = to;
      _gridCells = nextCells;
      _road2Cells = nextRoad2;
      _walls = nextWalls;
      _wallGroups = nextGroups;
      _selectedWalls = _selectedWalls.where(_walls.containsKey).toSet();
      _parkingAreas = nextParkingAreas;
      _entranceRects = nextEntrances;
      _exitRects = nextExits;
      _towerRects = nextTowers;
      _cleanupWallGroups();
    });
  }

  void _resetGrid({int? size}) {
    final nextSize = size ?? _gridSize;
    setState(() {
      _gridSize = nextSize;
      _tool = GridEditTool.empty;
      _gridCells = List<ParkingGridCellType>.filled(
        _gridSize * _gridSize,
        ParkingGridCellType.empty,
        growable: false,
      );

      _road2Cells = <int>{};
      _walls = <EdgePlacement, WallGroupId?>{};
      _wallGroups = <WallGroupId, String>{};
      _selectedWalls = <EdgePlacement>{};

      _parkingAreas = <ParkingArea>[];

      _entranceRects = <GridRect>[];
      _exitRects = <GridRect>[];
      _towerRects = <GridRect>[];
    });
  }

  Future<String?> _promptWallGroupName(BuildContext context, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final cs = Theme.of(context).colorScheme;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('벽 이름(그룹명) 지정'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '예) 북측 벽, 출구앞 벽, 외곽1 ...',
            ),
            onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: cs.primary),
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );

    final name = result?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  void _applyNameToSelectedWalls(String name) {
    if (_selectedWalls.isEmpty) return;
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final nextWalls = Map<EdgePlacement, WallGroupId?>.from(_walls);
    final nextGroups = Map<WallGroupId, String>.from(_wallGroups);

    final existingId = _findGroupIdByName(trimmed);
    final gid = existingId ?? _newWallGroupId();

    if (existingId == null) {
      nextGroups[gid] = trimmed;
    }

    for (final w in _selectedWalls) {
      if (nextWalls.containsKey(w)) nextWalls[w] = gid;
    }

    setState(() {
      _walls = nextWalls;
      _wallGroups = nextGroups;
      _cleanupWallGroups();
    });
  }

  void _clearNameOfSelectedWalls() {
    if (_selectedWalls.isEmpty) return;

    final nextWalls = Map<EdgePlacement, WallGroupId?>.from(_walls);
    for (final w in _selectedWalls) {
      if (nextWalls.containsKey(w)) nextWalls[w] = null;
    }

    setState(() {
      _walls = nextWalls;
      _cleanupWallGroups();
    });
  }

  void _deleteSelectedWalls() {
    if (_selectedWalls.isEmpty) return;

    final next = Map<EdgePlacement, WallGroupId?>.from(_walls);
    for (final w in _selectedWalls) {
      next.remove(w);
    }

    setState(() {
      _walls = next;
      _selectedWalls = <EdgePlacement>{};
      _cleanupWallGroups();
    });
  }

  Map<WallGroupId, List<EdgePlacement>> _wallGroupsToEdges() {
    final groups = <WallGroupId, List<EdgePlacement>>{};
    for (final e in _walls.entries) {
      final gid = e.value;
      if (gid == null) continue;
      final name = _wallGroups[gid]?.trim();
      if (name == null || name.isEmpty) continue;
      groups.putIfAbsent(gid, () => <EdgePlacement>[]).add(e.key);
    }
    return groups;
  }

  bool _overlapsExistingChildRects(
      String parentName,
      GridRect rect, {
        GridRect? excludeExactRect,
      }) {
    final pk = _nameKey(parentName);
    final list =
        widget.existingChildRectsByParentKey[pk] ?? const <GridRect>[];

    final target = rect.normalized();
    final exclude = excludeExactRect?.normalized();

    for (final r in list) {
      final n = r.normalized();
      if (exclude != null && n == exclude) continue;
      if (n.overlaps(target)) return true;
    }
    return false;
  }

  (int h, int w) _parkingSizeForKind(ParkingAreaKind k) {
    final n = k.name.toLowerCase();
    if (n.contains('12')) return (1, 2);
    if (n.contains('21')) return (2, 1);
    if (n.contains('22')) return (2, 2);
    final idx = ParkingAreaKind.values.indexOf(k);
    if (idx == 0) return (1, 2);
    if (idx == 1) return (2, 1);
    return (2, 2);
  }

  (int top, int left, int bottom, int right) _boundsOfArea(ParkingArea a) {
    final (h, w) = _parkingSizeForKind(a.kind);
    return (a.r0, a.c0, a.r0 + h - 1, a.c0 + w - 1);
  }

  bool _validateParkingAreasForSave({
    required int rows,
    required int cols,
    required List<ParkingGridCellType> cells,
    required List<ParkingArea> areas,
  }) {
    if (areas.isEmpty) return true;

    bool inBounds(ParkingArea a) {
      final (t, l, b, r) = _boundsOfArea(a);
      return t >= 0 && l >= 0 && b < rows && r < cols;
    }

    bool overlap(ParkingArea a, ParkingArea b) {
      final (aT, aL, aB, aR) = _boundsOfArea(a);
      final (bT, bL, bB, bR) = _boundsOfArea(b);
      final overlapRow = !(aB < bT || aT > bB);
      final overlapCol = !(aR < bL || aL > bR);
      return overlapRow && overlapCol;
    }

    for (final a in areas) {
      if (!inBounds(a)) return false;

      final (t, l, b, r) = _boundsOfArea(a);
      for (int rr = t; rr <= b; rr++) {
        for (int cc = l; cc <= r; cc++) {
          final idx = rr * cols + cc;
          if (idx < 0 || idx >= cells.length) return false;
          if (cells[idx] != ParkingGridCellType.empty) return false;
        }
      }
    }

    for (int i = 0; i < areas.length; i++) {
      for (int j = i + 1; j < areas.length; j++) {
        if (overlap(areas[i], areas[j])) return false;
      }
    }
    return true;
  }

  String? _validateTowerRectsForSave({
    required int rows,
    required int cols,
    required List<ParkingGridCellType> cells,
    required List<ParkingArea> parkingAreas,
    required List<GridRect> entranceRects,
    required List<GridRect> exitRects,
    required List<GridRect> towerRects,
  }) {
    if (towerRects.isEmpty) return null;

    int idx(int r, int c) => r * cols + c;

    final parkingUsed = <int>{};
    for (final a in parkingAreas) {
      final (t, l, b, r) = _boundsOfArea(a);
      for (int rr = t; rr <= b; rr++) {
        for (int cc = l; cc <= r; cc++) {
          final p = idx(rr, cc);
          if (p < 0 || p >= cells.length) continue;
          parkingUsed.add(p);
        }
      }
    }

    final gateUsed = <int>{};
    final gates = <GridRect>[...entranceRects, ...exitRects];
    for (final raw in gates) {
      final g = raw.normalized();
      for (int rr = g.r0; rr <= g.r1; rr++) {
        for (int cc = g.c0; cc <= g.c1; cc++) {
          final p = idx(rr, cc);
          if (p < 0 || p >= cells.length) continue;
          gateUsed.add(p);
        }
      }
    }

    final towerUsed = <int>{};
    for (final raw in towerRects) {
      final r = raw.normalized();
      if (r.r0 < 0 || r.c0 < 0 || r.r1 < 0 || r.c1 < 0) {
        return '주차 타워 영역 범위가 올바르지 않습니다.';
      }
      if (r.r0 >= rows || r.r1 >= rows || r.c0 >= cols || r.c1 >= cols) {
        return '주차 타워 영역이 그리드 밖으로 나갔습니다.';
      }

      for (int rr = r.r0; rr <= r.r1; rr++) {
        for (int cc = r.c0; cc <= r.c1; cc++) {
          final p = idx(rr, cc);
          if (p < 0 || p >= cells.length) {
            return '주차 타워 영역이 그리드 밖으로 나갔습니다.';
          }
          if (towerUsed.contains(p)) return '주차 타워 영역이 서로 겹칩니다.';
          if (parkingUsed.contains(p)) return '주차 타워 영역이 주차면적과 겹칩니다.';
          if (gateUsed.contains(p)) return '주차 타워 영역이 입구/출구 영역과 겹칩니다.';
          if (cells[p] != ParkingGridCellType.empty) return '주차 타워는 빈칸 위에만 설정할 수 있습니다.';
          towerUsed.add(p);
        }
      }
    }

    return null;
  }

  bool _areaContainedInRect(ParkingArea a, GridRect rect) {
    final rr = rect.normalized();
    final (t, l, b, r) = _boundsOfArea(a);
    return t >= rr.r0 && b <= rr.r1 && l >= rr.c0 && r <= rr.c1;
  }

  int _countParkingAreasInRect(ParkingGridModel grid, GridRect? rect) {
    if (rect == null) return 0;
    final areas = grid.parkingAreas;
    if (areas.isEmpty) return 0;

    int count = 0;
    for (final a in areas) {
      if (_areaContainedInRect(a, rect)) count++;
    }
    return count;
  }


  void _deleteRect(GridRect r) {
    final n = r.normalized();
    setState(() {
      _entranceRects = _entranceRects.where((e) => e.normalized() != n).toList(growable: false);
      _exitRects = _exitRects.where((e) => e.normalized() != n).toList(growable: false);
      _towerRects = _towerRects.where((e) => e.normalized() != n).toList(growable: false);
    });
  }

  void _clearAllRects() {
    setState(() {
      _entranceRects = <GridRect>[];
      _exitRects = <GridRect>[];
      _towerRects = <GridRect>[];
    });
  }

  LocationDraft? _tryBuildDraft() {
    if (_entryMode == _LocationEntryMode.plainText) {
      final name = _normalizeName(_plainTextNameController.text);
      final nameKey = _nameKey(name);
      final capText = _plainTextCapacityController.text.trim();
      final cap = capText.isEmpty ? 0 : int.tryParse(capText);

      if (name.isEmpty) {
        _setError('구역명을 입력하세요.');
        return null;
      }

      if ((_isPlainTextEdit ? _editingPlainTextOriginalNameKey : null) != nameKey &&
          widget.existingNameKeysInArea.contains(nameKey)) {
        _setError('이미 사용 중인 주차 구역명입니다: "$name"');
        return null;
      }

      if (cap == null || cap < 0) {
        _setError('수용 대수는 0 이상이어야 합니다.');
        return null;
      }

      _clearError();

      if (_isPlainTextEdit) {
        return PlainTextLocationUpdateDraft(
          id: widget.editingPlainTextId!,
          name: name,
          capacity: cap,
        );
      }

      return PlainTextLocationDraft(name: name, capacity: cap);
    }

    if (_mode == _CreateMode.parent) {
      final parent = _normalizeName(_parentController.text);
      final parentKey = _nameKey(parent);

      if (parent.isEmpty) {
        _setError('부모(상위) 구역명을 입력하세요.');
        return null;
      }

      if (!_isParentEdit && widget.existingNameKeysInArea.contains(parentKey)) {
        _setError('이미 사용 중인 주차 구역명입니다: "$parent"');
        return null;
      }

      if (_gridSize < _minGridSize || _gridSize > _maxGridSize) {
        _setError('그리드 크기는 $_minGridSize ~ $_maxGridSize 범위여야 합니다.');
        return null;
      }

      if (_gridCells.length != _gridSize * _gridSize) {
        _setError('그리드 데이터가 올바르지 않습니다. 다시 생성하세요.');
        return null;
      }

      final okAreas = _validateParkingAreasForSave(
        rows: _gridSize,
        cols: _gridSize,
        cells: _gridCells,
        areas: _parkingAreas,
      );
      if (!okAreas) {
        _setError('주차면적 데이터가 올바르지 않습니다. (범위/겹침/셀타입 확인)');
        return null;
      }

      final cleanedRoad2 = _road2Cells
          .where((i) => i >= 0 && i < _gridCells.length)
          .where((i) => _gridCells[i] == ParkingGridCellType.road)
          .toSet();

      final cleanedEntrances = _filterRectsWithin(_entranceRects, _gridSize, _gridSize);
      final cleanedExits = _filterRectsWithin(_exitRects, _gridSize, _gridSize);
      final cleanedTowers = _filterRectsWithin(_towerRects, _gridSize, _gridSize);

      final towerErr = _validateTowerRectsForSave(
        rows: _gridSize,
        cols: _gridSize,
        cells: _gridCells,
        parkingAreas: _parkingAreas,
        entranceRects: cleanedEntrances,
        exitRects: cleanedExits,
        towerRects: cleanedTowers,
      );
      if (towerErr != null) {
        _setError(towerErr);
        return null;
      }

      _clearError();

      final gridModel = ParkingGridModel.fromEnumCells(
        rows: _gridSize,
        cols: _gridSize,
        cells: _gridCells,
        walls: _walls.map((e, gid) => MapEntry(e.toKey(), gid)),
        wallGroups: _wallGroups,
        parkingAreas: _parkingAreas,
        entranceRects: cleanedEntrances,
        exitRects: cleanedExits,
        towerRects: cleanedTowers,
        road2Cells: (cleanedRoad2.toList()..sort()),
      );

      if (_isParentEdit) {
        return CompositeParentUpdateDraft(parent: parent, parkingGrid: gridModel);
      }

      return CompositeParentDraft(parent: parent, parkingGrid: gridModel);
    }

    final parent = (_selectedParent ?? '').trim();
    if (parent.isEmpty) {
      _setError('부모(상위) 구역을 선택하세요.');
      return null;
    }

    final grid = _selectedParentGrid;
    if (grid == null) {
      _setError('선택한 부모 구역의 레이아웃(parkingGrid)을 찾을 수 없습니다.');
      return null;
    }

    final child = _normalizeName(_childController.text);
    if (child.isEmpty) {
      _setError('자식(하위) 구역명을 입력하세요.');
      return null;
    }

    final cap = int.tryParse(_capacityController.text.trim());
    if (cap == null || cap <= 0) {
      _setError('수용 대수는 1 이상이어야 합니다.');
      return null;
    }

    if (_nameKey(parent) == _nameKey(child)) {
      _setError('자식 구역명 "$child"은 부모 구역명과 같을 수 없습니다.');
      return null;
    }

    final ck = _childCompositeKey(parent, child);
    final originalCk = _editingChildOriginalCompositeKey;
    if (widget.existingChildCompositeKeysInArea.contains(ck) && ck != originalCk) {
      _setError('이미 존재하는 자식 구역입니다: "$parent - $child"');
      return null;
    }

    final rect = _selectedChildRect?.normalized();
    if (rect == null) {
      _setError('부모 레이아웃에서 자식 영역(사각형)을 선택하거나 좌표를 적용하세요.');
      return null;
    }

    if (_childIsTower) {
      final towers = grid.towerRects.map((e) => e.normalized()).toList(growable: false);
      final ok = towers.any((t) => t == rect);
      if (!ok) {
        _setError('주차 타워 자식 구역은 부모에서 지정된 “주차 타워 영역” 중 하나를 선택해야 합니다.');
        return null;
      }
    }

    if (_overlapsExistingChildRects(
      parent,
      rect,
      excludeExactRect: _isChildEdit ? widget.editingChildRect : null,
    )) {
      _setError('선택한 영역이 기존 자식 구역과 겹칩니다. 다른 영역을 선택하세요.');
      return null;
    }

    _clearError();

    if (_isChildEdit) {
      return CompositeChildUpdateDraft(
        id: widget.editingChildId!,
        parent: parent,
        child: child,
        capacity: cap,
        rect: rect,
        isTower: _childIsTower,
      );
    }

    return CompositeChildDraft(
      parent: parent,
      child: child,
      capacity: cap,
      rect: rect,
      isTower: _childIsTower,
    );
  }

  void _handleSave() {
    FocusScope.of(context).unfocus();
    final draft = _tryBuildDraft();
    if (draft == null) return;

    widget.onSave(draft);
    Navigator.pop(context);
  }

  BoxDecoration _sheetDecoration(ColorScheme cs) {
    return BoxDecoration(
      color: cs.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
      border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
    );
  }

  ShapeBorder _cardShape(ColorScheme cs) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: BorderSide(color: cs.outlineVariant.withOpacity(.6)),
    );
  }

  TextStyle _sectionTitleStyle(ColorScheme cs) {
    return TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: 14,
      color: cs.onSurface,
    );
  }

  TextStyle _sectionSubStyle(ColorScheme cs) {
    return TextStyle(
      fontWeight: FontWeight.w700,
      fontSize: 12,
      color: cs.onSurfaceVariant.withOpacity(.85),
    );
  }

  Widget _sectionCard(
      ColorScheme cs, {
        required String title,
        String? subtitle,
        Widget? trailing,
        required Widget child,
        EdgeInsetsGeometry padding = const EdgeInsets.all(14),
      }) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: _cardShape(cs),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: _sectionTitleStyle(cs)),
                      if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(subtitle, style: _sectionSubStyle(cs)),
                      ],
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 12),
                  trailing,
                ],
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _banner(
      ColorScheme cs, {
        required String text,
        IconData icon = Icons.info_outline_rounded,
        bool isError = false,
      }) {
    final bg = isError ? cs.errorContainer : cs.surfaceContainerHigh;
    final fg = isError ? cs.onErrorContainer : cs.onSurface;
    return Card(
      elevation: 0,
      color: bg,
      shape: _cardShape(cs),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: fg),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  color: fg,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
      String label, {
        required ColorScheme cs,
        String? hintText,
        Widget? prefixIcon,
      }) {
    return InputDecoration(
      labelText: label,
      hintText: hintText,
      prefixIcon: prefixIcon,
      isDense: true,
      filled: true,
      fillColor: cs.surfaceContainerHigh,
      contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: cs.primary, width: 1.6),
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }

  Widget _buildEntryModeChips(ColorScheme cs) {
    return SegmentedButton<_LocationEntryMode>(
      segments: [
        ButtonSegment<_LocationEntryMode>(
          value: _LocationEntryMode.structured,
          label: const Text('구조형 구역'),
          icon: const Icon(Icons.account_tree_rounded),
        ),
        ButtonSegment<_LocationEntryMode>(
          value: _LocationEntryMode.plainText,
          label: const Text('텍스트형 구역'),
          icon: const Icon(Icons.text_fields_rounded),
        ),
      ],
      selected: <_LocationEntryMode>{_entryMode},
      showSelectedIcon: false,
      onSelectionChanged: (set) {
        if (set.isEmpty) return;
        final next = set.first;
        if (next == _entryMode) return;
        if ((_isParentEdit || _isChildEdit) && next != _LocationEntryMode.structured) return;
        if (_isPlainTextEdit && next != _LocationEntryMode.plainText) return;

        setState(() {
          _entryMode = next;
          _errorMessage = null;
          if (_entryMode == _LocationEntryMode.structured &&
              _selectedParent == null &&
              widget.parentNamesInArea.isNotEmpty) {
            _selectedParent = widget.parentNamesInArea.first;
          }
        });
        if (_entryMode == _LocationEntryMode.structured) {
          _syncSelectedParentGrid(resetChildSelection: !_isChildEdit);
        }
      },
    );
  }

  Widget _buildStructuredModeChips(ColorScheme cs) {
    final parentLabel = _isParentEdit ? '부모 수정' : '부모 생성';
    return SegmentedButton<_CreateMode>(
      segments: [
        ButtonSegment<_CreateMode>(
          value: _CreateMode.parent,
          label: Text(parentLabel),
          icon: Icon(_isParentEdit ? Icons.edit_rounded : Icons.add_rounded),
        ),
        ButtonSegment<_CreateMode>(
          value: _CreateMode.child,
          label: Text(_isChildEdit ? '자식 수정' : '자식 생성'),
          icon: Icon(_isChildEdit ? Icons.edit_rounded : Icons.call_split_rounded),
        ),
      ],
      selected: <_CreateMode>{_mode},
      showSelectedIcon: false,
      onSelectionChanged: (set) {
        if (set.isEmpty) return;
        final next = set.first;
        if (next == _mode) return;
        if (_isChildEdit && next == _CreateMode.parent) return;
        if (_isParentEdit && next == _CreateMode.child) return;

        if (next == _CreateMode.parent) {
          setState(() {
            _mode = _CreateMode.parent;
            _errorMessage = null;
          });
          return;
        }

        setState(() {
          _mode = _CreateMode.child;
          _errorMessage = null;
          if (_selectedParent == null && widget.parentNamesInArea.isNotEmpty) {
            _selectedParent = widget.parentNamesInArea.first;
          }
        });
        _syncSelectedParentGrid();
      },
    );
  }

  Widget _toolChip(ColorScheme cs, String label, GridEditTool tool, IconData icon) {
    final selected = _tool == tool;
    final fg = selected ? cs.onPrimaryContainer : cs.onSurface;
    final ic = selected ? cs.onPrimaryContainer : cs.onSurfaceVariant;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
      avatar: Icon(icon, size: 18, color: ic),
      selected: selected,
      selectedColor: cs.primaryContainer,
      backgroundColor: cs.surfaceContainerHigh,
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant.withOpacity(.65),
      ),
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      onSelected: (_) => _setTool(tool),
      shape: const StadiumBorder(),
    );
  }

  Widget _gateChip(
      ColorScheme cs, {
        required String kind,
        required GridRect rect,
        required VoidCallback onDelete,
      }) {
    final n = rect.normalized();
    final label = '$kind r:${n.r0}-${n.r1}, c:${n.c0}-${n.c1}';

    final selectedBg = kind == '입구'
        ? cs.primaryContainer
        : (kind == '출구' ? cs.errorContainer : cs.tertiaryContainer);

    return InputChip(
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
      onDeleted: onDelete,
      deleteIcon: const Icon(Icons.close_rounded),
      backgroundColor: cs.surfaceContainerHigh,
      selectedColor: selectedBg.withOpacity(0.55),
      side: BorderSide(color: cs.outlineVariant.withOpacity(.7)),
      shape: const StadiumBorder(),
      showCheckmark: false,
    );
  }

  Widget _buildParentGridEditor(ColorScheme cs) {
    final groups = _wallGroupsToEdges();
    final groupIds = groups.keys.toList()
      ..sort((a, b) {
        final an = (_wallGroups[a] ?? '').trim();
        final bn = (_wallGroups[b] ?? '').trim();
        return an.compareTo(bn);
      });

    final unnamedCount = _walls.values.where((gid) => gid == null).length;

    final wallSelectMode = _tool == GridEditTool.wallSelect;
    final selectedCount = wallSelectMode ? _selectedWalls.length : 0;
    final parkingCount = _parkingAreas.length;

    Widget groupBlock({
      required String title,
      String? subtitle,
      required List<Widget> children,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
          if (subtitle != null && subtitle.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(subtitle, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant.withOpacity(.85))),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: children,
          ),
        ],
      );
    }

    final gridStepper = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Tooltip(
          message: '축소',
          child: IconButton.filledTonal(
            onPressed: _gridSize <= _minGridSize ? null : () => _resizeGridPreserving(nextSize: _gridSize - 1),
            style: IconButton.styleFrom(
              backgroundColor: cs.surfaceContainerHigh,
              foregroundColor: cs.onSurface,
            ),
            icon: const Icon(Icons.remove_rounded),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: cs.outlineVariant.withOpacity(.7)),
          ),
          child: Text(
            '$_gridSize × $_gridSize',
            style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
          ),
        ),
        const SizedBox(width: 10),
        Tooltip(
          message: '확대',
          child: IconButton.filledTonal(
            onPressed: _gridSize >= _maxGridSize ? null : () => _resizeGridPreserving(nextSize: _gridSize + 1),
            style: IconButton.styleFrom(
              backgroundColor: cs.surfaceContainerHigh,
              foregroundColor: cs.onSurface,
            ),
            icon: const Icon(Icons.add_rounded),
          ),
        ),
      ],
    );

    final editor = _sectionCard(
      cs,
      title: '부모 레이아웃 편집',
      subtitle: '셀·주차·벽·입구/출구 영역을 배치해 부모 구역의 기본 지도를 만듭니다.',
      trailing: gridStepper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          groupBlock(
            title: '셀',
            subtitle: '롱프레스는 빈칸 → 도로1 → 기둥 순환 (도로2는 전용 도구)',
            children: [
              _toolChip(cs, '빈칸', GridEditTool.empty, Icons.layers_clear_rounded),
              _toolChip(cs, '도로1', GridEditTool.road, Icons.alt_route_rounded),
              _toolChip(cs, '도로2', GridEditTool.road2, Icons.alt_route_rounded),
              _toolChip(cs, '기둥', GridEditTool.pillar, Icons.view_column_rounded),
            ],
          ),
          const SizedBox(height: 14),
          groupBlock(
            title: '주차면적',
            subtitle: '빈칸 위에만 배치 가능 (1×2 / 2×1 / 2×2)',
            children: [
              _toolChip(cs, '1×2', GridEditTool.parking12, Icons.local_parking_rounded),
              _toolChip(cs, '2×1', GridEditTool.parking21, Icons.local_parking_rounded),
              _toolChip(cs, '2×2', GridEditTool.parking22, Icons.local_parking_rounded),
              _toolChip(cs, '삭제', GridEditTool.parkingEraser, Icons.delete_outline_rounded),
            ],
          ),
          const SizedBox(height: 14),
          groupBlock(
            title: '벽',
            subtitle: '외곽 변에만 생성됩니다. 선택/그룹 작업은 “벽선택”에서 가능합니다.',
            children: [
              _toolChip(cs, '벽', GridEditTool.wall, Icons.fence_rounded),
              _toolChip(cs, '삭제', GridEditTool.wallEraser, Icons.delete_outline_rounded),
              _toolChip(cs, '벽선택', GridEditTool.wallSelect, Icons.select_all_rounded),
            ],
          ),
          const SizedBox(height: 14),
          groupBlock(
            title: '입구/출구/주차 타워',
            subtitle: '같은 그리드에서 드래그로 영역을 추가하고, 영역삭제 도구로 탭하여 제거합니다.',
            children: [
              _toolChip(cs, '입구영역', GridEditTool.entranceRect, Icons.login_rounded),
              _toolChip(cs, '출구영역', GridEditTool.exitRect, Icons.logout_rounded),
              _toolChip(cs, '주차 타워', GridEditTool.towerRect, Icons.apartment_rounded),
              _toolChip(cs, '영역삭제', GridEditTool.rectEraser, Icons.delete_forever_rounded),
            ],
          ),
          const SizedBox(height: 14),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _resetGrid,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('전체 초기화'),
              style: OutlinedButton.styleFrom(
                foregroundColor: cs.onSurface,
                side: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
                shape: const StadiumBorder(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Card(
            elevation: 0,
            color: cs.surfaceContainerHigh,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AspectRatio(
                aspectRatio: 1,
                child: ParkingGrid2DEditor(
                  rows: _gridSize,
                  cols: _gridSize,
                  cells: _gridCells,
                  tool: _tool,
                  road2Cells: _road2Cells,
                  onChangedRoad2Cells: (next) => setState(() => _road2Cells = next),
                  entranceRects: _entranceRects,
                  exitRects: _exitRects,
                  towerRects: _towerRects,
                  onChangedEntranceRects: (next) => setState(() => _entranceRects = next),
                  onChangedExitRects: (next) => setState(() => _exitRects = next),
                  onChangedTowerRects: (next) => setState(() => _towerRects = next),
                  walls: _walls,
                  wallGroups: _wallGroups,
                  selectedWalls: _selectedWalls,
                  parkingAreas: _parkingAreas,
                  onChangedParkingAreas: (next) => setState(() => _parkingAreas = next),
                  onChangedCells: (next) => setState(() => _gridCells = next),
                  onChangedWalls: (next) => setState(() {
                    _walls = next;
                    _selectedWalls = _selectedWalls.where(_walls.containsKey).toSet();
                    _cleanupWallGroups();
                  }),
                  onChangedSelectedWalls: (sel) => setState(() {
                    if (_tool == GridEditTool.wallSelect) {
                      _selectedWalls = sel.where(_walls.containsKey).toSet();
                    }
                  }),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    final wallManage = _sectionCard(
      cs,
      title: '벽(외곽 변) 관리',
      subtitle: wallSelectMode ? '현재 “벽선택” 도구: 선택/그룹 작업 가능' : '“벽선택” 도구에서만 선택/그룹 작업이 가능합니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _statPill(cs, '벽', '${_walls.length}'),
              _statPill(cs, '그룹', '${_wallGroups.length}'),
              _statPill(cs, '선택', '$selectedCount'),
              _statPill(cs, '이름없음', '$unnamedCount'),
              _statPill(cs, '주차면적', '$parkingCount'),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: (!wallSelectMode || _selectedWalls.isEmpty)
                    ? null
                    : () async {
                  final name = await _promptWallGroupName(context);
                  if (name == null) return;
                  _applyNameToSelectedWalls(name);
                },
                icon: const Icon(Icons.edit_rounded),
                label: const Text('이름 지정'),
              ),
              FilledButton.tonalIcon(
                onPressed: (!wallSelectMode || _selectedWalls.isEmpty) ? null : _clearNameOfSelectedWalls,
                icon: const Icon(Icons.label_off_rounded),
                label: const Text('이름 제거'),
              ),
              FilledButton.tonalIcon(
                onPressed: (!wallSelectMode || _selectedWalls.isEmpty) ? null : _deleteSelectedWalls,
                icon: const Icon(Icons.delete_rounded),
                label: const Text('선택 삭제'),
              ),
              FilledButton.tonalIcon(
                onPressed: (!wallSelectMode || _selectedWalls.isEmpty)
                    ? null
                    : () => setState(() => _selectedWalls = <EdgePlacement>{}),
                icon: const Icon(Icons.deselect_rounded),
                label: const Text('선택 해제'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (groupIds.isNotEmpty) ...[
            Text('벽 그룹', style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final gid in groupIds)
                    ActionChip(
                      label: Text(
                        '${_wallGroups[gid] ?? gid} (${groups[gid]!.length})',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      avatar: const Icon(Icons.label_rounded),
                      onPressed: !wallSelectMode
                          ? null
                          : () {
                        setState(() {
                          _selectedWalls = groups[gid]!.toSet();
                        });
                      },
                    ),
                ],
              ),
            ),
          ] else ...[
            Text(
              '이름이 지정된 벽 그룹이 없습니다.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant.withOpacity(.85)),
            ),
          ],
        ],
      ),
    );

    final gateCount = _entranceRects.length + _exitRects.length;
    final towerCount = _towerRects.length;
    final rectCount = gateCount + towerCount;

    final gateList = _sectionCard(
      cs,
      title: '입구/출구/주차 타워',
      subtitle: '같은 그리드에서 “입구영역/출구영역/주차 타워” 도구로 드래그해 추가하고, “영역삭제” 도구로 탭/드래그하여 삭제합니다.',
      trailing: OutlinedButton.icon(
        onPressed: rectCount == 0 ? null : _clearAllRects,
        icon: const Icon(Icons.delete_sweep_rounded, size: 18),
        label: const Text('전체 삭제'),
        style: OutlinedButton.styleFrom(
          foregroundColor: cs.onSurface,
          side: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
          shape: const StadiumBorder(),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              _statPill(cs, '입구', '${_entranceRects.length}'),
              _statPill(cs, '출구', '${_exitRects.length}'),
              _statPill(cs, '주차 타워', '${_towerRects.length}'),
            ],
          ),
          const SizedBox(height: 10),
          if (rectCount == 0)
            Text(
              '추가된 입구/출구/주차 타워 영역이 없습니다.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant.withOpacity(.85)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in _entranceRects)
                  _gateChip(
                    cs,
                    kind: '입구',
                    rect: r,
                    onDelete: () => _deleteRect(r),
                  ),
                for (final r in _exitRects)
                  _gateChip(
                    cs,
                    kind: '출구',
                    rect: r,
                    onDelete: () => _deleteRect(r),
                  ),
                for (final r in _towerRects)
                  _gateChip(
                    cs,
                    kind: '주차 타워',
                    rect: r,
                    onDelete: () => _deleteRect(r),
                  ),
              ],
            ),
        ],
      ),
    );

    final tips = _banner(
      cs,
      text: '팁: 도로는 도로1/도로2로 구분할 수 있습니다. 주차면적은 빈칸 위에만 배치됩니다. 입구/출구/주차 타워는 같은 그리드에서 여러 개의 사각형 영역으로 지정합니다.',
      icon: Icons.lightbulb_outline_rounded,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        editor,
        const SizedBox(height: 12),
        gateList,
        const SizedBox(height: 12),
        wallManage,
        const SizedBox(height: 12),
        const SizedBox(height: 12),
        tips,
      ],
    );
  }


  Widget _buildPlainTextContent(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionCard(
          cs,
          title: '텍스트형 구역 정보',
          subtitle: '그리드, 부모/자식, 좌표 없이 이름만으로 관리하는 주차 구역입니다.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _plainTextNameController,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                textInputAction: TextInputAction.next,
                style: TextStyle(color: cs.onSurface),
                decoration: _inputDecoration(
                  '구역명',
                  cs: cs,
                  hintText: '예) 후문 앞, 외곽 주차장, 타워 2층',
                  prefixIcon: const Icon(Icons.text_fields_rounded),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _plainTextCapacityController,
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(4),
                ],
                textInputAction: TextInputAction.done,
                style: TextStyle(color: cs.onSurface),
                decoration: _inputDecoration(
                  '수용 가능 차량 수',
                  cs: cs,
                  hintText: '미입력 시 0',
                  prefixIcon: const Icon(Icons.local_parking_rounded),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _banner(
          cs,
          text: '텍스트형 구역은 배치도 영역과 연결되지 않습니다. 운영상 구역명과 수용 대수만 관리합니다.',
          icon: Icons.info_outline_rounded,
        ),
      ],
    );
  }

  Widget _coordCell(ColorScheme cs, String label, TextEditingController controller, {bool enabled = true}) {
    return Expanded(
      child: TextField(
        enabled: enabled,
        controller: controller,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(2),
        ],
        textInputAction: TextInputAction.next,
        decoration: _inputDecoration(label, cs: cs),
      ),
    );
  }

  Widget _cornerRow(ColorScheme cs, String label, TextEditingController r, TextEditingController c, {bool enabled = true}) {
    return Expanded(
      child: Card(
        elevation: 0,
        color: cs.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: cs.outlineVariant.withOpacity(.6)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface)),
              const SizedBox(height: 10),
              Row(
                children: [
                  _coordCell(cs, '행(r)', r, enabled: enabled),
                  const SizedBox(width: 8),
                  _coordCell(cs, '열(c)', c, enabled: enabled),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildChildGridSelector(ColorScheme cs) {
    final parent = (_selectedParent ?? '').trim();
    final grid = _selectedParentGrid;

    if (parent.isEmpty) {
      return _banner(cs, text: '부모 구역을 먼저 선택하세요.', icon: Icons.error_outline_rounded, isError: true);
    }

    if (grid == null) {
      return _banner(
        cs,
        text: '선택한 부모 구역에 레이아웃(parkingGrid)이 없습니다.\n부모 구역을 먼저 생성/저장한 뒤 다시 시도하세요.',
        icon: Icons.error_outline_rounded,
        isError: true,
      );
    }

    final towers = grid.towerRects.map((e) => e.normalized()).toList(growable: false);
    final hasTowers = towers.isNotEmpty;

    if (_childIsTower && !hasTowers) {
      return _banner(
        cs,
        text: '부모 구역에 주차 타워 영역이 없습니다.\n부모 편집에서 “주차 타워” 영역을 먼저 추가하세요.',
        icon: Icons.error_outline_rounded,
        isError: true,
      );
    }

    final rect = _selectedChildRect?.normalized();
    final rectLabel = rect == null ? '미선택' : 'r:${rect.r0}-${rect.r1}, c:${rect.c0}-${rect.c1} (가로 ${rect.width}, 세로 ${rect.height})';

    final inferredSlots = _childIsTower ? 0 : _countParkingAreasInRect(grid, rect);

    final selector = Card(
      elevation: 0,
      color: cs.surfaceContainerHigh,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: SizedBox(
          height: 340,
          child: ParkingGridChildRectSelector(
            grid: grid,
            value: _selectedChildRect,
            squareLock: _childSquareLock,
            showAxisIndex: true,
            axisIndexStep: 5,
            towerRects: grid.towerRects,
            towerSelectMode: _childIsTower,
            onChanged: (v) {
              final nv = v?.normalized();
              final isTowerRect = nv != null && towers.any((t) => t == nv);

              setState(() {
                _selectedChildRect = v;


                if (isTowerRect) {
                  _childIsTower = true;
                  _childSquareLock = false;
                } else {

                  _childIsTower = false;
                }
              });

              _syncChildRectInputsFromRect(v);
            },
          ),
        ),
      ),
    );

    return _sectionCard(
      cs,
      title: '자식 영역 선택',
      subtitle: '부모 2D 레이아웃에서 자식 구역(사각형)을 지정합니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(value: false, label: Text('일반 구역')),
                    ButtonSegment<bool>(value: true, label: Text('주차 타워')),
                  ],
                  selected: <bool>{_childIsTower},
                  showSelectedIcon: false,
                  onSelectionChanged: (set) {
                    if (set.isEmpty) return;
                    final next = set.first;

                    if (next && !hasTowers) {
                      _setError('부모 구역에 주차 타워 영역이 없습니다. 먼저 부모 편집에서 “주차 타워”를 추가하세요.');
                      return;
                    }

                    _clearError();
                    setState(() {
                      _childIsTower = next;

                      if (_childIsTower) {
                        _childSquareLock = false;

                        final cur = _selectedChildRect?.normalized();
                        final ok = cur != null && towers.any((t) => t == cur);
                        if (!ok) {
                          _selectedChildRect = null;
                          _clearChildRectInputs();
                        }
                      }
                    });
                  },
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: _selectedChildRect == null
                    ? null
                    : () {
                  setState(() => _selectedChildRect = null);
                  _clearChildRectInputs();
                },
                icon: const Icon(Icons.close_rounded, size: 18),
                label: const Text('선택 해제'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Opacity(
            opacity: _childIsTower ? 0.55 : 1.0,
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(value: false, label: Text('직사각형')),
                ButtonSegment<bool>(value: true, label: Text('정사각형')),
              ],
              selected: <bool>{_childSquareLock},
              showSelectedIcon: false,
              onSelectionChanged: _childIsTower
                  ? null
                  : (set) {
                if (set.isEmpty) return;
                setState(() => _childSquareLock = set.first);
              },
            ),
          ),
          if (_childIsTower) ...[
            const SizedBox(height: 12),
            Text(
              '주차 타워 영역(부모에서 지정됨)',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: cs.onSurface),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (int i = 0; i < towers.length; i++)
                  ChoiceChip(
                    selected: rect != null && rect == towers[i],
                    label: Text(
                      '타워 ${i + 1} r:${towers[i].r0}-${towers[i].r1}, c:${towers[i].c0}-${towers[i].c1}',
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    selectedColor: cs.tertiaryContainer.withOpacity(0.55),
                    backgroundColor: cs.surfaceContainerHigh,
                    side: BorderSide(color: cs.outlineVariant.withOpacity(.65)),
                    showCheckmark: false,
                    onSelected: (_) {
                      _clearError();
                      setState(() => _selectedChildRect = towers[i]);
                      _syncChildRectInputsFromRect(towers[i]);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            _banner(
              cs,
              text: '타워 모드에서는 부모에서 지정된 타워 영역 중 하나를 선택해야 합니다.',
              icon: Icons.info_outline_rounded,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          Text(
            '좌표 입력은 0부터 시작합니다. (행 0~${grid.rows - 1}, 열 0~${grid.cols - 1})',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: cs.onSurfaceVariant.withOpacity(.9)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _cornerRow(cs, '좌상', _tlRController, _tlCController, enabled: !_childIsTower),
              const SizedBox(width: 10),
              _cornerRow(cs, '우상', _trRController, _trCController, enabled: !_childIsTower),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _cornerRow(cs, '좌하', _blRController, _blCController, enabled: !_childIsTower),
              const SizedBox(width: 10),
              _cornerRow(cs, '우하', _brRController, _brCController, enabled: !_childIsTower),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _childIsTower ? null : () => _applyChildRectFromInputs(parent: parent, grid: grid),
                icon: const Icon(Icons.done_rounded),
                label: const Text('좌표 적용'),
              ),
              OutlinedButton.icon(
                onPressed: (_childIsTower || rect == null)
                    ? null
                    : () {
                  _syncChildRectInputsFromRect(rect);
                  setState(() {});
                },
                icon: const Icon(Icons.sync_rounded),
                label: const Text('현재 선택 → 좌표'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
                  shape: const StadiumBorder(),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _childIsTower
                    ? null
                    : () {
                  _clearChildRectInputs();
                  setState(() {});
                },
                icon: const Icon(Icons.backspace_outlined),
                label: const Text('좌표 초기화'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
                  shape: const StadiumBorder(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _banner(cs, text: '현재 선택: $rectLabel', icon: Icons.crop_free_rounded),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '선택 영역 내 주차면적(완전 포함): $inferredSlots',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
              ),
              OutlinedButton(
                onPressed: (_childIsTower || rect == null)
                    ? null
                    : () {
                  _capacityController.text = inferredSlots.toString();
                  setState(() {});
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: cs.onSurface,
                  side: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
                  shape: const StadiumBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
                child: const Text('수용대수 자동입력'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          selector,
          const SizedBox(height: 10),
          Text(
            '그리드는 미리보기/보조 선택용입니다. 좌표 적용으로 정확히 지정할 수 있습니다.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant.withOpacity(.85)),
          ),
        ],
      ),
    );
  }

  Widget _statPill(ColorScheme cs, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(.8)),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: cs.onSurfaceVariant,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ?? const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)).copyWith(
      color: cs.onSurfaceVariant.withOpacity(.72),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return SafeArea(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: location setting',
              child: Text('location setting', style: style),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    final screenHeight = MediaQuery.of(context).size.height;

    final noParents = widget.parentNamesInArea.isEmpty;
    final isStructured = _entryMode == _LocationEntryMode.structured;

    final title = _entryMode == _LocationEntryMode.plainText
        ? (_isPlainTextEdit ? '텍스트 구역 수정' : '텍스트 구역 생성')
        : (_mode == _CreateMode.parent && _isParentEdit)
        ? '부모 구역 수정'
        : (_mode == _CreateMode.child && _isChildEdit)
        ? '자식 구역 수정'
        : '주차 구역 생성';

    final header = Column(
      children: [
        Center(
          child: Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: cs.outlineVariant.withOpacity(.65),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Text(
          title,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
          ),
        ),
        const SizedBox(height: 12),
        _buildEntryModeChips(cs),
        if (isStructured) ...[
          const SizedBox(height: 12),
          _buildStructuredModeChips(cs),
        ],
        const SizedBox(height: 16),
      ],
    );

    final parentContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionCard(
          cs,
          title: '구역 정보',
          subtitle: _isParentEdit ? '부모 구역명은 수정할 수 없습니다.' : '부모(상위) 구역명을 입력하세요.',
          child: TextField(
            controller: _parentController,
            readOnly: _isParentEdit,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            textInputAction: TextInputAction.done,
            style: TextStyle(color: cs.onSurface),
            decoration: _inputDecoration(
              '부모(상위) 구역명',
              cs: cs,
              hintText: '예) A동 지하 2층, 외곽 주차장',
              prefixIcon: const Icon(Icons.location_on_rounded),
            ),
          ),
        ),
        _buildParentGridEditor(cs),
      ],
    );

    final childInfo = _sectionCard(
      cs,
      title: '자식 구역 정보',
      subtitle: '부모 구역을 선택하고, 하위 구역명과 수용 대수를 입력하세요.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (noParents)
            _banner(
              cs,
              text: '현재 지역에 생성된 부모 구역이 없습니다.\n먼저 “부모 생성”으로 부모 구역을 만든 뒤 자식을 추가하세요.',
              icon: Icons.error_outline_rounded,
              isError: true,
            )
          else
            DropdownButtonFormField<String>(
              value: _selectedParent,
              items: widget.parentNamesInArea
                  .map(
                    (p) => DropdownMenuItem<String>(
                  value: p,
                  child: Text(
                    p,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              )
                  .toList(),
              onChanged: _isChildEdit
                  ? null
                  : (v) {
                setState(() => _selectedParent = v);
                _syncSelectedParentGrid();
              },
              decoration: _inputDecoration(
                '부모(상위) 구역 선택',
                cs: cs,
                prefixIcon: const Icon(Icons.account_tree_rounded),
              ),
            ),
          const SizedBox(height: 12),
          TextField(
            controller: _childController,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            textInputAction: TextInputAction.next,
            style: TextStyle(color: cs.onSurface),
            decoration: _inputDecoration(
              '자식(하위) 구역명',
              cs: cs,
              hintText: '예) A구역, B구역, 출구앞',
              prefixIcon: const Icon(Icons.edit_location_alt_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _capacityController,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            textInputAction: TextInputAction.done,
            style: TextStyle(color: cs.onSurface),
            decoration: _inputDecoration(
              '수용 가능 차량 수',
              cs: cs,
              hintText: '예) 42',
              prefixIcon: const Icon(Icons.local_parking_rounded),
            ),
          ),
        ],
      ),
    );

    final childContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        childInfo,
        const SizedBox(height: 12),
        _buildChildGridSelector(cs),
      ],
    );

    final content = _entryMode == _LocationEntryMode.plainText
        ? _buildPlainTextContent(cs)
        : (_mode == _CreateMode.parent ? parentContent : childContent);

    final contentKey = _entryMode == _LocationEntryMode.plainText
        ? 'plain_text'
        : (_mode == _CreateMode.parent ? 'structured_parent' : 'structured_child');

    final scrollContent = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      child: Padding(
        key: ValueKey<String>(contentKey),
        padding: const EdgeInsets.only(bottom: 10),
        child: content,
      ),
    );

    final errorBanner = AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      child: _errorMessage == null
          ? const SizedBox.shrink()
          : Padding(
        key: ValueKey<String>(_errorMessage!),
        padding: const EdgeInsets.only(top: 10, bottom: 10),
        child: _banner(
          cs,
          text: _errorMessage!,
          icon: Icons.error_outline_rounded,
          isError: true,
        ),
      ),
    );

    final isEditMode = _isPlainTextEdit ||
        (_entryMode == _LocationEntryMode.structured &&
            ((_mode == _CreateMode.parent && _isParentEdit) ||
                (_mode == _CreateMode.child && _isChildEdit)));

    final actions = Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.onSurface,
              side: BorderSide(
                color: cs.outlineVariant.withOpacity(.75),
                width: 1.2,
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
            ),
            child: const Text('취소'),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: FilledButton(
            onPressed: (_entryMode == _LocationEntryMode.structured && _mode == _CreateMode.child && noParents)
                ? null
                : _handleSave,
            style: FilledButton.styleFrom(
              backgroundColor: cs.primary,
              foregroundColor: cs.onPrimary,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: const StadiumBorder(),
              elevation: 1,
            ),
            child: Text(
              isEditMode ? '수정 저장' : '저장',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
      ],
    );

    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: Stack(
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: screenHeight - bottomPadding),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
              decoration: _sheetDecoration(cs),
              child: Column(
                children: [
                  header,
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          scrollContent,
                          errorBanner,
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  actions,
                ],
              ),
            ),
          ),
          _buildScreenTag(context),
        ],
      ),
    );
  }

}
