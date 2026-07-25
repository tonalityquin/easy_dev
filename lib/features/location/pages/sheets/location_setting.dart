import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/utils/location_debug_status.dart';
import '../../domain/models/grid_rect.dart';
import '../../domain/models/parking_grid_model.dart';
import 'widgets/location_draft.dart';
import 'widgets/parking_grid_2d_editor.dart';
import 'widgets/parking_grid_child_rect_selector.dart';
import '../../../../shared/secondary/widgets/ops_console_dialogs.dart';
import '../../../../shared/secondary/widgets/ops_console_widgets.dart';

enum LocationSettingIntent {
  createParent,
  editParent,
  createChild,
  editChild,
  editPlainText,
}
enum _ParentToolGroup { basic, parking, facility }

class LocationSettingBottomSheet extends StatefulWidget {
  final LocationSettingIntent intent;
  final Future<bool> Function(LocationDraft draft) onSave;
  final Set<String> existingNameKeysInArea;
  final Set<String> existingChildCompositeKeysInArea;
  final Map<String, ParkingGridModel> parentParkingGridsByParentKey;
  final Map<String, List<GridRect>> existingChildRectsByParentKey;
  final Map<String, Set<String>> existingChildAreaIdsByParentKey;
  final String? fixedParentName;

  final String? editingParentName;
  final ParkingGridModel? editingParentParkingGrid;


  final String? editingChildId;
  final String? editingChildParentName;
  final String? editingChildName;
  final int? editingChildCapacity;
  final GridRect? editingChildRect;
  final bool? editingChildIsTower;
  final List<String> editingChildSlotAreaIds;
  final Map<String, int> editingChildSlotNumbersByAreaId;

  final String? editingPlainTextId;
  final String? editingPlainTextName;
  final int? editingPlainTextCapacity;

  const LocationSettingBottomSheet({
    super.key,
    required this.intent,
    required this.onSave,
    required this.existingNameKeysInArea,
    required this.existingChildCompositeKeysInArea,
    required this.parentParkingGridsByParentKey,
    this.existingChildRectsByParentKey = const <String, List<GridRect>>{},
    this.existingChildAreaIdsByParentKey = const <String, Set<String>>{},
    this.fixedParentName,
    this.editingParentName,
    this.editingParentParkingGrid,
    this.editingChildId,
    this.editingChildParentName,
    this.editingChildName,
    this.editingChildCapacity,
    this.editingChildRect,
    this.editingChildIsTower,
    this.editingChildSlotAreaIds = const <String>[],
    this.editingChildSlotNumbersByAreaId = const <String, int>{},
    this.editingPlainTextId,
    this.editingPlainTextName,
    this.editingPlainTextCapacity,
  });

  @override
  State<LocationSettingBottomSheet> createState() => _LocationSettingBottomSheetState();
}

class _LocationSettingBottomSheetState extends State<LocationSettingBottomSheet> {
  bool get _isParentIntent =>
      widget.intent == LocationSettingIntent.createParent ||
      widget.intent == LocationSettingIntent.editParent;

  bool get _isChildIntent =>
      widget.intent == LocationSettingIntent.createChild ||
      widget.intent == LocationSettingIntent.editChild;

  bool get _isPlainTextIntent =>
      widget.intent == LocationSettingIntent.editPlainText;

  bool get _isParentEdit =>
      widget.intent == LocationSettingIntent.editParent &&
      widget.editingParentName != null &&
      widget.editingParentParkingGrid != null;

  bool get _isChildEdit =>
      widget.intent == LocationSettingIntent.editChild &&
      widget.editingChildId != null &&
      widget.editingChildParentName != null &&
      widget.editingChildName != null &&
      widget.editingChildCapacity != null &&
      widget.editingChildRect != null;

  bool get _isPlainTextEdit =>
      widget.intent == LocationSettingIntent.editPlainText &&
      widget.editingPlainTextId != null &&
      widget.editingPlainTextName != null;

  String? _editingChildOriginalCompositeKey;
  String? _editingPlainTextOriginalNameKey;

  bool _childIsTower = false;

  final TextEditingController _parentController = TextEditingController();

  static const int _minGridSize = 2;
  static const int _maxGridSize = 20;
  int _gridSize = 6;

  GridEditTool _tool = GridEditTool.empty;
  _ParentToolGroup _parentToolGroup = _ParentToolGroup.basic;

  late List<ParkingGridCellType> _gridCells;
  Set<int> _road2Cells = <int>{};


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
  Set<String> _selectedChildParkingAreaIds = <String>{};
  final Map<String, TextEditingController> _childSlotNoControllers = <String, TextEditingController>{};
  bool _childAreaPickMode = false;

  bool _childSquareLock = false;

  String? _errorMessage;
  bool _saving = false;

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

  void _syncChildSlotNoControllers({Map<String, int> initialNumbers = const <String, int>{}}) {
    final ids = _selectedChildParkingAreaIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final removeIds = _childSlotNoControllers.keys.where((id) => !ids.contains(id)).toList(growable: false);
    for (final id in removeIds) {
      _childSlotNoControllers.remove(id)?.dispose();
    }
    for (final id in ids) {
      if (_childSlotNoControllers.containsKey(id)) continue;
      final no = initialNumbers[id];
      _childSlotNoControllers[id] = TextEditingController(text: no == null || no <= 0 ? '' : no.toString());
    }
  }

  void _setSelectedChildParkingAreaIds(
    Set<String> next, {
    Map<String, int> initialNumbers = const <String, int>{},
    bool updateCapacity = true,
  }) {
    _selectedChildParkingAreaIds = next.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    _syncChildSlotNoControllers(initialNumbers: initialNumbers);
    if (updateCapacity) {
      _capacityController.text = _selectedChildParkingAreaIds.length.toString();
    }
  }

  void _clearSelectedChildParkingAreaIds({bool updateCapacity = true}) {
    _setSelectedChildParkingAreaIds(<String>{}, updateCapacity: updateCapacity);
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

    _clearError();
    setState(() {
      _selectedChildRect = rect;
      _childAreaPickMode = false;
      _syncSelectedChildParkingAreasFromRect(grid, rect);
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
        _clearSelectedChildParkingAreaIds();
        _childAreaPickMode = false;
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
        _clearSelectedChildParkingAreaIds();
        _childAreaPickMode = false;
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
      _plainTextNameController.text = (widget.editingPlainTextName ?? '').trim();
      final cap = widget.editingPlainTextCapacity;
      _plainTextCapacityController.text =
          cap == null || cap <= 0 ? '' : cap.toString();
      _editingPlainTextOriginalNameKey =
          _nameKey(_plainTextNameController.text);
    } else if (_isChildIntent) {
      _selectedParent = (widget.fixedParentName ??
              widget.editingChildParentName ??
              '')
          .trim();
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
      _parentController.text = (widget.editingParentName ?? '').trim();
      final g = widget.editingParentParkingGrid;
      if (g != null) {
        _applyParentGridForEdit(g);
      }
    }

    if (_isChildEdit) {
      _selectedParent = (widget.fixedParentName ??
              widget.editingChildParentName ??
              '')
          .trim();
      _childController.text = (widget.editingChildName ?? '').trim();
      _capacityController.text = (widget.editingChildCapacity ?? 0).toString();
      _selectedChildRect = widget.editingChildRect?.normalized();
      _childIsTower = widget.editingChildIsTower == true;
      _setSelectedChildParkingAreaIds(
        widget.editingChildSlotAreaIds
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toSet(),
        initialNumbers: widget.editingChildSlotNumbersByAreaId,
        updateCapacity: !_childIsTower,
      );
      _syncChildRectInputsFromRect(_selectedChildRect);

      if (_childIsTower) {
        _childSquareLock = false;
      }

      _editingChildOriginalCompositeKey = _childCompositeKey(
        (_selectedParent ?? '').trim(),
        _childController.text,
      );
    }

    _syncSelectedParentGrid(resetChildSelection: !_isChildEdit);
    if (_isChildEdit && !_childIsTower && _selectedChildParkingAreaIds.isEmpty) {
      final grid = _selectedParentGrid;
      final rect = _selectedChildRect;
      if (grid != null && rect != null) {
        _setSelectedChildParkingAreaIds(
          _areaIdsInRect(grid, rect).toSet(),
          initialNumbers: widget.editingChildSlotNumbersByAreaId,
        );
      }
    }
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
    for (final controller in _childSlotNoControllers.values) {
      controller.dispose();
    }

    super.dispose();
  }

  void _setError(String msg) => setState(() => _errorMessage = msg);
  void _clearError() => setState(() => _errorMessage = null);

  void _setTool(GridEditTool next) {
    setState(() => _tool = next);
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

    _gridSize = target;
    _tool = GridEditTool.empty;
    _gridCells = nextCells;
    _road2Cells = nextRoad2;
    _parkingAreas = nextParkingAreas;
    _entranceRects = entranceRects;
    _exitRects = exitRects;
    _towerRects = towerRects;

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
      _parkingAreas = nextParkingAreas;
      _entranceRects = nextEntrances;
      _exitRects = nextExits;
      _towerRects = nextTowers;
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

      _parkingAreas = <ParkingArea>[];

      _entranceRects = <GridRect>[];
      _exitRects = <GridRect>[];
      _towerRects = <GridRect>[];
    });
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

  (int h, int w) _parkingSizeForKind(ParkingAreaKind k) => (k.h, k.w);

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


  List<String> _areaIdsInRect(ParkingGridModel grid, GridRect rect) {
    final ids = <String>[];
    for (final a in grid.parkingAreas) {
      final id = a.id.trim();
      if (id.isEmpty) continue;
      if (_areaContainedInRect(a, rect)) ids.add(id);
    }
    return ids;
  }

  Set<String> _editingChildOriginalAreaIds() {
    if (!_isChildEdit) return <String>{};
    return widget.editingChildSlotAreaIds
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toSet();
  }

  Set<String> _disabledChildAreaIdsForParent(String parent) {
    final pk = _nameKey(parent);
    final all = Set<String>.from(widget.existingChildAreaIdsByParentKey[pk] ?? const <String>{});
    all.removeAll(_editingChildOriginalAreaIds());
    return all;
  }

  void _syncSelectedChildParkingAreasFromRect(ParkingGridModel grid, GridRect rect) {
    final parent = (_selectedParent ?? '').trim();
    final disabled = _disabledChildAreaIdsForParent(parent);
    final next = _areaIdsInRect(grid, rect).where((id) => !disabled.contains(id)).toSet();
    _setSelectedChildParkingAreaIds(next);
  }

  int _selectedChildParkingAreaCount() => _selectedChildParkingAreaIds.length;

  String _selectedChildSlotSummary(ParkingGridModel grid) {
    if (_selectedChildParkingAreaIds.isEmpty) return '선택된 주차면적 없음';
    final counts = <String, int>{};
    for (final a in grid.parkingAreas) {
      if (!_selectedChildParkingAreaIds.contains(a.id)) continue;
      counts[a.kind.label] = (counts[a.kind.label] ?? 0) + 1;
    }
    if (counts.isEmpty) return '선택된 주차면적 ${_selectedChildParkingAreaIds.length}개';
    return counts.entries.map((e) => '${e.key} ${e.value}').join(' · ');
  }

  List<ParkingArea> _selectedChildParkingAreasSorted(ParkingGridModel grid) {
    final out = grid.parkingAreas
        .where((area) => _selectedChildParkingAreaIds.contains(area.id.trim()))
        .toList();
    out.sort((a, b) {
      final ar0 = min(a.r0, a.r1);
      final br0 = min(b.r0, b.r1);
      final dr = ar0.compareTo(br0);
      if (dr != 0) return dr;

      final ac0 = min(a.c0, a.c1);
      final bc0 = min(b.c0, b.c1);
      final dc = ac0.compareTo(bc0);
      if (dc != 0) return dc;

      final dk = a.kind.index.compareTo(b.kind.index);
      if (dk != 0) return dk;

      return a.id.compareTo(b.id);
    });
    return out;
  }

  String _parkingAreaPositionText(ParkingArea area) {
    final r0 = min(area.r0, area.r1);
    final r1 = max(area.r0, area.r1);
    final c0 = min(area.c0, area.c1);
    final c1 = max(area.c0, area.c1);
    return 'r:$r0-$r1, c:$c0-$c1';
  }

  Map<String, int>? _validateChildSlotNumbers(List<String> ids) {
    final out = <String, int>{};
    final used = <int>{};
    for (final rawId in ids) {
      final id = rawId.trim();
      if (id.isEmpty) continue;
      final controller = _childSlotNoControllers[id];
      final raw = controller?.text.trim() ?? '';
      if (raw.isEmpty) {
        _setError('선택된 모든 주차면적에 슬롯 번호를 입력하세요.');
        return null;
      }
      final no = int.tryParse(raw);
      if (no == null || no <= 0) {
        _setError('슬롯 번호는 1 이상의 숫자여야 합니다.');
        return null;
      }
      if (!used.add(no)) {
        _setError('같은 자식 구역 안에서 슬롯 번호는 중복될 수 없습니다.');
        return null;
      }
      out[id] = no;
    }
    return out;
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
    if (_isPlainTextIntent) {
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

      if (!_isPlainTextEdit) {
        _setError('수정할 텍스트 구역 정보를 찾을 수 없습니다.');
        return null;
      }

      return PlainTextLocationUpdateDraft(
        id: widget.editingPlainTextId!,
        name: name,
        capacity: cap,
      );
    }

    if (_isParentIntent) {
      final parent = _normalizeName(_parentController.text);
      final parentKey = _nameKey(parent);

      if (parent.isEmpty) {
        _setError('부모(상위) 구역명을 입력하세요.');
        return null;
      }

      if (!_isParentEdit &&
          widget.existingNameKeysInArea.contains(parentKey)) {
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

    final rawCap = int.tryParse(_capacityController.text.trim());
    if (rawCap == null || rawCap <= 0) {
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

      if (_overlapsExistingChildRects(
        parent,
        rect,
        excludeExactRect: _isChildEdit ? widget.editingChildRect : null,
      )) {
        _setError('선택한 타워 영역이 기존 자식 구역과 겹칩니다. 다른 영역을 선택하세요.');
        return null;
      }
    }

    final ids = _childIsTower
        ? <String>[]
        : (_selectedChildParkingAreaIds
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toSet()
              .toList()
          ..sort());

    if (!_childIsTower && ids.isEmpty) {
      _setError('자식 구역에 포함할 주차면적을 1개 이상 선택하세요.');
      return null;
    }

    final slotNumbersByAreaId = _childIsTower ? const <String, int>{} : _validateChildSlotNumbers(ids);
    if (slotNumbersByAreaId == null) return null;

    final cap = _childIsTower ? rawCap : ids.length;
    _capacityController.text = cap.toString();

    _clearError();

    if (_isChildEdit) {
      return CompositeChildUpdateDraft(
        id: widget.editingChildId!,
        child: child,
        capacity: cap,
        rect: rect,
        childSlotAreaIds: ids,
        childSlotNumbersByAreaId: slotNumbersByAreaId,
        isTower: _childIsTower,
      );
    }

    return CompositeChildDraft(
      child: child,
      capacity: cap,
      rect: rect,
      childSlotAreaIds: ids,
      childSlotNumbersByAreaId: slotNumbersByAreaId,
      isTower: _childIsTower,
    );
  }

  Future<bool> _confirmParentGridUpdate() {
    return showOpsConfirmDialog(
      context: context,
      title: '부모 구역 수정 저장',
      message: '부모 도면을 저장하면 하위 자식 구역의 슬롯 정보가 재계산될 수 있습니다.',
      confirmLabel: '저장',
      icon: Icons.warning_amber_rounded,
      destructive: true,
    );
  }

  Future<void> _handleSave() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final draft = _tryBuildDraft();
    if (draft == null) return;
    if (!_draftMatchesIntent(draft)) {
      _setError('현재 작업과 일치하지 않는 저장 요청입니다.');
      return;
    }

    if (draft is CompositeParentUpdateDraft) {
      final confirmed = await _confirmParentGridUpdate();
      if (!confirmed || !mounted) return;
    }

    setState(() => _saving = true);
    var saved = false;
    try {
      saved = await widget.onSave(draft);
    } catch (e, stackTrace) {
      LocationDebugStatus.report(
        context: context,
        title: '구역 저장 실패',
        operation: 'LocationSettingBottomSheet._handleSave',
        error: e,
        stackTrace: stackTrace,
        details: <String, Object?>{'draftType': draft.runtimeType},
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (!mounted) return;
    if (saved) Navigator.pop(context);
  }

  Widget _sectionCard(
    ColorScheme cs, {
    required String title,
    String? subtitle,
    Widget? trailing,
    required Widget child,
    EdgeInsetsGeometry padding = const EdgeInsets.all(14),
  }) {
    return OpsPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: padding,
      accentColor: cs.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpsSectionTitle(
            title: title,
            subtitle: subtitle,
            icon: Icons.dashboard_customize_rounded,
            trailing: trailing,
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _banner(
    ColorScheme cs, {
    required String text,
    IconData icon = Icons.info_outline_rounded,
    bool isError = false,
  }) {
    final bg = isError ? cs.errorContainer.withOpacity(.62) : cs.primaryContainer.withOpacity(.32);
    final fg = isError ? cs.onErrorContainer : cs.onPrimaryContainer;
    final border = isError ? cs.error.withOpacity(.35) : cs.primary.withOpacity(.22);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w800,
                height: 1.28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label, {
    required ColorScheme cs,
    Widget? prefixIcon,
  }) {
    return InputDecoration(
      labelText: label,

      prefixIcon: prefixIcon,
      isDense: true,
      filled: true,
      fillColor: cs.surface,
      contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      labelStyle: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800),
      hintStyle: TextStyle(color: cs.onSurfaceVariant.withOpacity(.70), fontWeight: FontWeight.w700),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.outlineVariant.withOpacity(.86)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.primary, width: 1.45),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
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

  String _parentToolGroupLabel(_ParentToolGroup group) {
    switch (group) {
      case _ParentToolGroup.basic:
        return '기본';
      case _ParentToolGroup.parking:
        return '주차면';
      case _ParentToolGroup.facility:
        return '시설';
    }
  }

  IconData _parentToolGroupIcon(_ParentToolGroup group) {
    switch (group) {
      case _ParentToolGroup.basic:
        return Icons.layers_rounded;
      case _ParentToolGroup.parking:
        return Icons.local_parking_rounded;
      case _ParentToolGroup.facility:
        return Icons.login_rounded;
    }
  }

  Widget _buildParentToolGroupSelector(ColorScheme cs) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final group in _ParentToolGroup.values)
          OpsFormChip(
            label: _parentToolGroupLabel(group),
            selected: _parentToolGroup == group,
            icon: _parentToolGroupIcon(group),
            onTap: () => setState(() => _parentToolGroup = group),
          ),
      ],
    );
  }

  List<Widget> _activeParentToolChips(ColorScheme cs) {
    switch (_parentToolGroup) {
      case _ParentToolGroup.basic:
        return [
          _toolChip(cs, '빈칸', GridEditTool.empty, Icons.layers_clear_rounded),
          _toolChip(cs, '도로1', GridEditTool.road, Icons.alt_route_rounded),
          _toolChip(cs, '도로2', GridEditTool.road2, Icons.alt_route_rounded),
          _toolChip(cs, '기둥', GridEditTool.pillar, Icons.view_column_rounded),
        ];
      case _ParentToolGroup.parking:
        return [
          _toolChip(cs, '경형 1×2', GridEditTool.parkingCompact12, Icons.local_parking_rounded),
          _toolChip(cs, '경형 2×1', GridEditTool.parkingCompact21, Icons.local_parking_rounded),
          _toolChip(cs, '일반형 1×2', GridEditTool.parkingStandard12, Icons.local_parking_rounded),
          _toolChip(cs, '일반형 2×1', GridEditTool.parkingStandard21, Icons.local_parking_rounded),
          _toolChip(cs, '확장형 A 1×2', GridEditTool.parkingExtendedA12, Icons.local_parking_rounded),
          _toolChip(cs, '확장형 A 2×1', GridEditTool.parkingExtendedA21, Icons.local_parking_rounded),
          _toolChip(cs, '확장형 B 2×2', GridEditTool.parkingExtendedB22, Icons.local_parking_rounded),
          _toolChip(cs, '전기차 경형 1×2', GridEditTool.parkingEvCompact12, Icons.ev_station_rounded),
          _toolChip(cs, '전기차 경형 2×1', GridEditTool.parkingEvCompact21, Icons.ev_station_rounded),
          _toolChip(cs, '전기차 일반형 1×2', GridEditTool.parkingEvStandard12, Icons.ev_station_rounded),
          _toolChip(cs, '전기차 일반형 2×1', GridEditTool.parkingEvStandard21, Icons.ev_station_rounded),
          _toolChip(cs, '전기차 확장형 A 1×2', GridEditTool.parkingEvExtendedA12, Icons.ev_station_rounded),
          _toolChip(cs, '전기차 확장형 A 2×1', GridEditTool.parkingEvExtendedA21, Icons.ev_station_rounded),
          _toolChip(cs, '전기차 확장형 B 2×2', GridEditTool.parkingEvExtendedB22, Icons.ev_station_rounded),
          _toolChip(cs, '임산부 확장형 A 1×2', GridEditTool.parkingPregnantExtendedA12, Icons.pregnant_woman_rounded),
          _toolChip(cs, '임산부 확장형 A 2×1', GridEditTool.parkingPregnantExtendedA21, Icons.pregnant_woman_rounded),
          _toolChip(cs, '임산부 확장형 B 2×2', GridEditTool.parkingPregnantExtendedB22, Icons.pregnant_woman_rounded),
          _toolChip(cs, '장애인 일반형 1×2', GridEditTool.parkingDisabledStandard12, Icons.accessible_rounded),
          _toolChip(cs, '장애인 일반형 2×1', GridEditTool.parkingDisabledStandard21, Icons.accessible_rounded),
          _toolChip(cs, '장애인 확장형 A 1×2', GridEditTool.parkingDisabledExtendedA12, Icons.accessible_rounded),
          _toolChip(cs, '장애인 확장형 A 2×1', GridEditTool.parkingDisabledExtendedA21, Icons.accessible_rounded),
          _toolChip(cs, '장애인 확장형 B 2×2', GridEditTool.parkingDisabledExtendedB22, Icons.accessible_rounded),
          _toolChip(cs, '주차면 삭제', GridEditTool.parkingEraser, Icons.delete_outline_rounded),
        ];
      case _ParentToolGroup.facility:
        return [
          _toolChip(cs, '입구', GridEditTool.entranceRect, Icons.login_rounded),
          _toolChip(cs, '출구', GridEditTool.exitRect, Icons.logout_rounded),
          _toolChip(cs, '타워', GridEditTool.towerRect, Icons.apartment_rounded),
          _toolChip(cs, '영역 삭제', GridEditTool.rectEraser, Icons.delete_forever_rounded),
        ];
    }
  }

  int _countCellType(ParkingGridCellType type) {
    var count = 0;
    for (final cell in _gridCells) {
      if (cell == type) count++;
    }
    return count;
  }

  Widget _buildParentEditScopePanel(ColorScheme cs) {
    if (!_isParentEdit) return const SizedBox.shrink();
    return OpsPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      accentColor: cs.error,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpsSectionTitle(
            title: '수정 범위',
            icon: Icons.lock_outline_rounded,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OpsInfoPill(text: '부모명 잠금', icon: Icons.lock_rounded),
              OpsInfoPill(text: '지역 잠금', icon: Icons.business_rounded),
              OpsInfoPill(text: '도면 수정 가능', icon: Icons.grid_4x4_rounded),
              OpsInfoPill(text: '주차면 수정 가능', icon: Icons.tune_rounded),
            ],
          ),
          const SizedBox(height: 12),
          OpsInlineMessage(
            message: '저장 시 하위 자식 구역의 슬롯 정보가 재계산될 수 있습니다.',
            danger: true,
            icon: Icons.warning_amber_rounded,
          ),
        ],
      ),
    );
  }

  Widget _buildParentSaveSummary(ColorScheme cs) {
    final road1Count = _countCellType(ParkingGridCellType.road);
    final road2Count = _road2Cells.length;
    final pillarCount = _countCellType(ParkingGridCellType.pillar);
    final gateCount = _entranceRects.length + _exitRects.length;
    final towerCount = _towerRects.length;
    return OpsPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpsSectionTitle(
            title: '저장 전 요약',
            icon: Icons.fact_check_rounded,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _statPill(cs, '그리드', '$_gridSize×$_gridSize'),
              _statPill(cs, '주차면', '${_parkingAreas.length}'),
              _statPill(cs, '도로1', '$road1Count'),
              _statPill(cs, '도로2', '$road2Count'),
              _statPill(cs, '기둥', '$pillarCount'),
              _statPill(cs, '입출구', '$gateCount'),
              _statPill(cs, '타워', '$towerCount'),
            ],
          ),
        ],
      ),
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
      title: '도면 편집',
      trailing: gridStepper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpsCommandPanel(
            children: [
              _buildParentToolGroupSelector(cs),
              const SizedBox(height: 10),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: Wrap(
                  key: ValueKey<_ParentToolGroup>(_parentToolGroup),
                  spacing: 8,
                  runSpacing: 8,
                  children: _activeParentToolChips(cs),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
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
          const SizedBox(height: 12),
          OpsPanel(
            margin: EdgeInsets.zero,
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
                parkingAreas: _parkingAreas,
                onChangedParkingAreas: (next) => setState(() => _parkingAreas = next),
                onChangedCells: (next) => setState(() => _gridCells = next),
              ),
            ),
          ),
        ],
      ),
    );

    final gateCount = _entranceRects.length + _exitRects.length;
    final towerCount = _towerRects.length;
    final rectCount = gateCount + towerCount;

    final gateList = _sectionCard(
      cs,
      title: '입구/출구/주차 타워',
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        editor,
        const SizedBox(height: 12),
        gateList,
        const SizedBox(height: 12),
        _buildParentSaveSummary(cs),
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
      child: OpsPanel(
        margin: EdgeInsets.zero,
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
    );
  }

  Widget _buildChildSlotNumberInputs(ColorScheme cs, ParkingGridModel grid) {
    if (_childIsTower || _selectedChildParkingAreaIds.isEmpty) {
      return const SizedBox.shrink();
    }

    _syncChildSlotNoControllers();
    final areas = _selectedChildParkingAreasSorted(grid);

    if (areas.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant.withOpacity(.65)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.format_list_numbered_rounded, color: cs.primary, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '슬롯 번호 지정',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '선택된 모든 주차면적에 1 이상의 고유 번호를 입력해야 저장할 수 있습니다.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant.withOpacity(.9)),
          ),
          const SizedBox(height: 12),
          for (int i = 0; i < areas.length; i++) ...[
            _childSlotNumberRow(cs, areas[i]),
            if (i != areas.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _childSlotNumberRow(ColorScheme cs, ParkingArea area) {
    final id = area.id.trim();
    final controller = _childSlotNoControllers[id] ?? TextEditingController();
    if (!_childSlotNoControllers.containsKey(id)) {
      _childSlotNoControllers[id] = controller;
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  area.kind.label,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
                const SizedBox(height: 3),
                Text(
                  _parkingAreaPositionText(area),
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: cs.onSurfaceVariant.withOpacity(.85)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 112,
          child: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(4),
            ],
            textInputAction: TextInputAction.next,
            decoration: _inputDecoration(
              '번호',
              cs: cs,

              prefixIcon: const Icon(Icons.numbers_rounded),
            ),
          ),
        ),
      ],
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
    final selectedSlots = _childIsTower ? 0 : _selectedChildParkingAreaCount();
    final disabledAreaIds = _disabledChildAreaIdsForParent(parent);

    final selector = OpsPanel(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(12),
      child: SizedBox(
          height: 340,
          child: ParkingGridChildRectSelector(
            grid: grid,
            value: _selectedChildRect,
            selectedParkingAreaIds: _selectedChildParkingAreaIds,
            disabledParkingAreaIds: disabledAreaIds,
            onChangedSelectedParkingAreaIds: (ids) {
              setState(() {
                _setSelectedChildParkingAreaIds(ids);
              });
            },
            parkingAreaPickMode: _childAreaPickMode,
            squareLock: _childSquareLock,
            showAxisIndex: true,
            axisIndexStep: 5,
            towerRects: grid.towerRects,
            towerSelectMode: _childIsTower,
            onChanged: (v) {
              final nv = v?.normalized();
              final isTowerRect = nv != null && towers.any((t) => t == nv);

              setState(() {
                _selectedChildRect = nv;

                if (isTowerRect) {
                  _childIsTower = true;
                  _childSquareLock = false;
                  _childAreaPickMode = false;
                  _clearSelectedChildParkingAreaIds(updateCapacity: false);
                } else {
                  _childIsTower = false;
                  _childAreaPickMode = false;
                  if (nv != null) {
                    _syncSelectedChildParkingAreasFromRect(grid, nv);
                  } else {
                    _clearSelectedChildParkingAreaIds(updateCapacity: false);
                    _capacityController.clear();
                  }
                }
              });

              _syncChildRectInputsFromRect(nv);
            },
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
                        _clearSelectedChildParkingAreaIds(updateCapacity: false);
                        _childAreaPickMode = false;
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
                  setState(() {
                    _selectedChildRect = null;
                    _clearSelectedChildParkingAreaIds();
                    _childAreaPickMode = false;
                  });
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
                setState(() {
                  _childSquareLock = set.first;
                  _childAreaPickMode = false;
                });
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
                      setState(() {
                        _selectedChildRect = towers[i];
                        _clearSelectedChildParkingAreaIds(updateCapacity: false);
                        _childAreaPickMode = false;
                      });
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
          if (!_childIsTower && rect != null) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    '실제 포함 슬롯: $selectedSlots / 후보 $inferredSlots',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: cs.onSurface),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() => _childAreaPickMode = !_childAreaPickMode);
                  },
                  icon: Icon(_childAreaPickMode ? Icons.check_box_rounded : Icons.indeterminate_check_box_rounded),
                  label: Text(_childAreaPickMode ? '선택 완료' : '일부 제외/포함'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    side: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
                    shape: const StadiumBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _syncSelectedChildParkingAreasFromRect(grid, rect);
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    side: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('후보 전체 선택'),
                ),
                OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _clearSelectedChildParkingAreaIds();
                    });
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cs.onSurface,
                    side: BorderSide(color: cs.outlineVariant.withOpacity(.75)),
                    shape: const StadiumBorder(),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  child: const Text('전체 제외'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _banner(
              cs,
              text: _childAreaPickMode
                  ? '주차면적을 탭해 이 자식 구역에 포함/제외할 수 있습니다. 회색은 이미 다른 자식 구역에 배정된 슬롯입니다.'
                  : '일부를 잘라내려면 “일부 제외/포함”을 누른 뒤 주차면적을 탭하세요. 제외된 슬롯은 미배정 상태로 남습니다.',
              icon: Icons.touch_app_rounded,
            ),
            const SizedBox(height: 8),
            _banner(cs, text: _selectedChildSlotSummary(grid), icon: Icons.local_parking_rounded),
            const SizedBox(height: 8),
            _buildChildSlotNumberInputs(cs, grid),
          ],
          const SizedBox(height: 12),
          _banner(cs, text: '현재 선택: $rectLabel', icon: Icons.crop_free_rounded),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  _childIsTower
                      ? '타워 자식 구역은 슬롯을 자동 생성하지 않습니다.'
                      : '선택 영역 후보: $inferredSlots · 실제 포함: $selectedSlots',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: cs.onSurface),
                ),
              ),
              OutlinedButton(
                onPressed: (_childIsTower || rect == null)
                    ? null
                    : () {
                  _capacityController.text = selectedSlots.toString();
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
            '직사각형/정사각형은 후보 범위이고, 실제 자식 구역 소속은 선택된 주차면적 기준으로 저장됩니다.',
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



  bool _draftMatchesIntent(LocationDraft draft) {
    switch (widget.intent) {
      case LocationSettingIntent.createParent:
        return draft is CompositeParentDraft;
      case LocationSettingIntent.editParent:
        return draft is CompositeParentUpdateDraft;
      case LocationSettingIntent.createChild:
        return draft is CompositeChildDraft;
      case LocationSettingIntent.editChild:
        return draft is CompositeChildUpdateDraft;
      case LocationSettingIntent.editPlainText:
        return draft is PlainTextLocationUpdateDraft;
    }
  }

  Widget _animatedContent({
    required Key key,
    required Widget child,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (current, animation) {
        final offset = Tween<Offset>(
          begin: const Offset(0, .025),
          end: Offset.zero,
        ).animate(animation);
        final scale = Tween<double>(
          begin: .985,
          end: 1,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: offset,
            child: ScaleTransition(
              scale: scale,
              child: current,
            ),
          ),
        );
      },
      child: KeyedSubtree(
        key: key,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isEditMode = _isParentEdit || _isChildEdit || _isPlainTextEdit;
    final isChild = _isChildIntent;
    final parentName = isChild
        ? (_selectedParent ?? '').trim()
        : _parentController.text.trim();
    final noParent = isChild &&
        (parentName.isEmpty || _selectedParentGrid == null);

    final title = switch (widget.intent) {
      LocationSettingIntent.createParent => '부모 구역 추가',
      LocationSettingIntent.editParent => '부모 구역 수정',
      LocationSettingIntent.createChild => '자식 구역 추가',
      LocationSettingIntent.editChild => '자식 구역 수정',
      LocationSettingIntent.editPlainText => '텍스트 구역 수정',
    };

    final saveLabel = switch (widget.intent) {
      LocationSettingIntent.createParent => '부모 구역 저장',
      LocationSettingIntent.editParent => '부모 수정 저장',
      LocationSettingIntent.createChild => '자식 구역 저장',
      LocationSettingIntent.editChild => '자식 수정 저장',
      LocationSettingIntent.editPlainText => '구역 수정 저장',
    };

    final contentKey = ValueKey<LocationSettingIntent>(widget.intent);

    final parentContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionCard(
          cs,
          title: '부모 구역 식별값',
          child: TextField(
            controller: _parentController,
            readOnly: _isParentEdit,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            textInputAction: TextInputAction.done,
            style: TextStyle(color: cs.onSurface),
            decoration: _inputDecoration(
              '부모 구역명',
              cs: cs,
              prefixIcon: const Icon(Icons.location_on_rounded),
            ),
          ),
        ),
        _buildParentEditScopePanel(cs),
        _buildParentGridEditor(cs),
      ],
    );

    final childInfo = _sectionCard(
      cs,
      title: '자식 구역 식별값',
      subtitle: '선택한 부모 구역에 고정된 자식 구역 정보를 입력합니다.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InputDecorator(
            decoration: _inputDecoration(
              '부모 구역',
              cs: cs,
              prefixIcon: const Icon(Icons.account_tree_rounded),
            ),
            child: Text(
              parentName.isEmpty ? '부모 구역 없음' : parentName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: parentName.isEmpty ? cs.error : cs.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _childController,
            onTapOutside: (_) => FocusScope.of(context).unfocus(),
            textInputAction: TextInputAction.next,
            style: TextStyle(color: cs.onSurface),
            decoration: _inputDecoration(
              '자식 구역명',
              cs: cs,
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
              prefixIcon: const Icon(Icons.local_parking_rounded),
            ),
          ),
        ],
      ),
    );

    final childContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (noParent)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _banner(
              cs,
              text: '선택한 부모 구역의 도면을 찾을 수 없습니다.',
              icon: Icons.error_outline_rounded,
              isError: true,
            ),
          ),
        childInfo,
        const SizedBox(height: 12),
        _buildChildGridSelector(cs),
      ],
    );

    final content = switch (widget.intent) {
      LocationSettingIntent.createParent ||
      LocationSettingIntent.editParent =>
        parentContent,
      LocationSettingIntent.createChild ||
      LocationSettingIntent.editChild =>
        childContent,
      LocationSettingIntent.editPlainText => _buildPlainTextContent(cs),
    };

    final selectedSlotCount = _selectedChildParkingAreaIds.length;
    final gridLabel = _isParentIntent
        ? '${_gridSize}×$_gridSize'
        : (_selectedParentGrid == null
            ? '-'
            : '${_selectedParentGrid!.rows}×${_selectedParentGrid!.cols}');

    return OpsWorkSheet(
      title: title,
      subtitle: '',
      icon: isChild
          ? Icons.subdirectory_arrow_right_rounded
          : Icons.location_on_rounded,
      areaLabel: isEditMode ? '수정 작업' : '신규 작업',
      metrics: [
        OpsMetric(
          label: '대상',
          value: _isParentIntent
              ? '부모'
              : (_isChildIntent ? '자식' : '텍스트'),
          icon: _isParentIntent
              ? Icons.account_tree_rounded
              : (_isChildIntent
                  ? Icons.subdirectory_arrow_right_rounded
                  : Icons.text_fields_rounded),
          color: cs.primary,
        ),
        OpsMetric(
          label: '부모',
          value: parentName.isEmpty ? '-' : parentName,
          icon: Icons.account_tree_rounded,
          color: noParent ? cs.error : cs.primary,
        ),
        OpsMetric(
          label: '그리드',
          value: gridLabel,
          icon: Icons.grid_4x4_rounded,
          color: cs.primary,
        ),
        OpsMetric(
          label: '슬롯',
          value: '$selectedSlotCount',
          icon: Icons.local_parking_rounded,
          color: isChild && selectedSlotCount == 0 && !_childIsTower
              ? cs.error
              : cs.primary,
        ),
      ],
      bottomBar: OpsBottomActionBar(
        children: [
          Expanded(
            child: OpsActionButton(
              label: '취소',
              icon: Icons.close_rounded,
              onPressed: _saving ? null : () => Navigator.pop(context),
              tonal: true,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OpsActionButton(
              label: _saving ? '저장 중' : saveLabel,
              icon: _saving
                  ? Icons.hourglass_top_rounded
                  : (isEditMode
                      ? Icons.save_rounded
                      : Icons.add_location_alt_rounded),
              onPressed: _saving || noParent ? null : _handleSave,
            ),
          ),
        ],
      ),
      body: TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        tween: Tween<double>(begin: 0, end: 1),
        builder: (context, value, child) {
          return Opacity(
            opacity: value,
            child: Transform.translate(
              offset: Offset(0, 14 * (1 - value)),
              child: child,
            ),
          );
        },
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return SizeTransition(
                  sizeFactor: animation,
                  axisAlignment: -1,
                  child: FadeTransition(
                    opacity: animation,
                    child: child,
                  ),
                );
              },
              child: _errorMessage == null
                  ? const SizedBox.shrink()
                  : Padding(
                      key: ValueKey<String>(_errorMessage!),
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _banner(
                        cs,
                        text: _errorMessage!,
                        icon: Icons.error_outline_rounded,
                        isError: true,
                      ),
                    ),
            ),
            OpsCommandPanel(
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OpsInfoPill(
                      text: isEditMode ? '수정 모드' : '등록 모드',
                      icon: isEditMode ? Icons.edit_rounded : Icons.add_rounded,
                    ),
                    OpsInfoPill(
                      text: _isParentIntent
                          ? '부모 전용'
                          : (_isChildIntent ? '자식 전용' : '텍스트 전용'),
                      icon: _isParentIntent
                          ? Icons.account_tree_rounded
                          : (_isChildIntent
                              ? Icons.subdirectory_arrow_right_rounded
                              : Icons.text_fields_rounded),
                    ),
                    if (_isChildIntent)
                      OpsInfoPill(
                        text: parentName.isEmpty ? '부모 미지정' : parentName,
                        icon: Icons.lock_rounded,
                      ),
                    if (_isChildIntent)
                      OpsInfoPill(
                        text: _childIsTower ? '타워 자식' : '일반 자식',
                        icon: _childIsTower
                            ? Icons.apartment_rounded
                            : Icons.crop_square_rounded,
                      ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _animatedContent(
              key: contentKey,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: content,
              ),
            ),
          ],
        ),
      ),
    );
  }

}
