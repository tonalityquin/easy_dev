import 'dart:math';
import 'package:flutter/material.dart';

import '../../../domain/models/grid_rect.dart';
import '../../../domain/models/parking_grid_model.dart';

enum GridEditTool {
  empty,
  road,
  road2,
  pillar,
  wall,
  wallEraser,
  wallSelect,
  parking12,
  parking21,
  parking22,
  parkingEraser,
  entranceRect,
  exitRect,
  towerRect,
  rectEraser,
}

enum _RectLayer { entrance, exit, tower }

class ParkingGrid2DEditor extends StatefulWidget {
  final int rows;
  final int cols;
  final List<ParkingGridCellType> cells;
  final GridEditTool tool;

  final Set<int> road2Cells;
  final ValueChanged<Set<int>> onChangedRoad2Cells;

  final List<GridRect> entranceRects;
  final List<GridRect> exitRects;
  final List<GridRect> towerRects;

  final ValueChanged<List<GridRect>> onChangedEntranceRects;
  final ValueChanged<List<GridRect>> onChangedExitRects;
  final ValueChanged<List<GridRect>> onChangedTowerRects;

  final Map<EdgePlacement, WallGroupId?> walls;
  final Map<WallGroupId, String> wallGroups;
  final Set<EdgePlacement> selectedWalls;

  final List<ParkingArea> parkingAreas;
  final ValueChanged<List<ParkingArea>> onChangedParkingAreas;

  final ValueChanged<List<ParkingGridCellType>> onChangedCells;
  final ValueChanged<Map<EdgePlacement, WallGroupId?>> onChangedWalls;
  final ValueChanged<Set<EdgePlacement>> onChangedSelectedWalls;

  const ParkingGrid2DEditor({
    super.key,
    required this.rows,
    required this.cols,
    required this.cells,
    required this.tool,
    required this.road2Cells,
    required this.onChangedRoad2Cells,
    required this.entranceRects,
    required this.exitRects,
    required this.towerRects,
    required this.onChangedEntranceRects,
    required this.onChangedExitRects,
    required this.onChangedTowerRects,
    required this.walls,
    required this.wallGroups,
    required this.selectedWalls,
    required this.parkingAreas,
    required this.onChangedParkingAreas,
    required this.onChangedCells,
    required this.onChangedWalls,
    required this.onChangedSelectedWalls,
  });

  @override
  State<ParkingGrid2DEditor> createState() => _ParkingGrid2DEditorState();
}

class _ParkingGrid2DEditorState extends State<ParkingGrid2DEditor> {
  int _lastDragIdx = -1;
  EdgePlacement? _lastDragEdge;

  bool _longPressActive = false;
  int _lastLongPressIdx = -1;

  int _rectDragStartIdx = -1;
  int _rectDragCurIdx = -1;
  GridRect? _rectDraftRect;
  _RectLayer? _rectDraftLayer;

  @override
  void didUpdateWidget(covariant ParkingGrid2DEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tool != widget.tool) {
      if (!_isRectTool(widget.tool)) {
        _clearRectDraft();
      } else {
        _clearRectDraft();
      }
    }
  }

  bool _isCellTool(GridEditTool t) =>
      t == GridEditTool.empty ||
          t == GridEditTool.road ||
          t == GridEditTool.road2 ||
          t == GridEditTool.pillar;

  bool _isWallTool(GridEditTool t) =>
      t == GridEditTool.wall || t == GridEditTool.wallEraser || t == GridEditTool.wallSelect;

  bool _isEdgeTool(GridEditTool t) => _isWallTool(t);

  bool _isParkingTool(GridEditTool t) =>
      t == GridEditTool.parking12 ||
          t == GridEditTool.parking21 ||
          t == GridEditTool.parking22 ||
          t == GridEditTool.parkingEraser;

  bool _isRectTool(GridEditTool t) =>
      t == GridEditTool.entranceRect ||
          t == GridEditTool.exitRect ||
          t == GridEditTool.towerRect ||
          t == GridEditTool.rectEraser;

  _RectLayer? _layerForTool(GridEditTool t) {
    if (t == GridEditTool.entranceRect) return _RectLayer.entrance;
    if (t == GridEditTool.exitRect) return _RectLayer.exit;
    if (t == GridEditTool.towerRect) return _RectLayer.tower;
    return null;
  }

  ParkingGridCellType _cellForTool(GridEditTool t) {
    switch (t) {
      case GridEditTool.empty:
        return ParkingGridCellType.empty;
      case GridEditTool.road:
      case GridEditTool.road2:
        return ParkingGridCellType.road;
      case GridEditTool.pillar:
        return ParkingGridCellType.pillar;
      default:
        return ParkingGridCellType.empty;
    }
  }

  ParkingGridCellType _cycleCell(ParkingGridCellType cur) {
    switch (cur) {
      case ParkingGridCellType.empty:
        return ParkingGridCellType.road;
      case ParkingGridCellType.road:
        return ParkingGridCellType.pillar;
      case ParkingGridCellType.pillar:
        return ParkingGridCellType.empty;
    }
  }

  (int h, int w) _desiredSizeForTool(GridEditTool t) {
    switch (t) {
      case GridEditTool.parking12:
        return (1, 2);
      case GridEditTool.parking21:
        return (2, 1);
      case GridEditTool.parking22:
        return (2, 2);
      default:
        return (0, 0);
    }
  }

  ParkingAreaKind _kindForTool(GridEditTool t) {
    final desired = _desiredSizeForTool(t);
    final values = ParkingAreaKind.values;
    if (values.isEmpty) {
      throw StateError('ParkingAreaKind.values is empty');
    }

    final wantToken = '${desired.$1}${desired.$2}';
    final byName = values.where((k) => k.name.toLowerCase().contains(wantToken)).toList();
    if (byName.isNotEmpty) return byName.first;

    if (t == GridEditTool.parking12) return values[0];
    if (t == GridEditTool.parking21) return values.length > 1 ? values[1] : values[0];
    if (t == GridEditTool.parking22) return values.length > 2 ? values[2] : values.last;
    return values.first;
  }

  (int h, int w) _sizeForKind(ParkingAreaKind k) {
    final name = k.name.toLowerCase();
    if (name.contains('12')) return (1, 2);
    if (name.contains('21')) return (2, 1);
    if (name.contains('22')) return (2, 2);
    final idx = ParkingAreaKind.values.indexOf(k);
    if (idx == 0) return (1, 2);
    if (idx == 1) return (2, 1);
    return (2, 2);
  }

  String _nextParkingAreaId() => 'pa_${DateTime.now().microsecondsSinceEpoch}';

  int _idx(int r, int c) => r * widget.cols + c;

  (int top, int left, int bottom, int right) _boundsOf(ParkingArea a) {
    final (h, w) = _sizeForKind(a.kind);
    final top = a.r0;
    final left = a.c0;
    final bottom = a.r0 + h - 1;
    final right = a.c0 + w - 1;
    return (top, left, bottom, right);
  }

  bool _cellInsideArea(ParkingArea a, int r, int c) {
    final (top, left, bottom, right) = _boundsOf(a);
    return r >= top && r <= bottom && c >= left && c <= right;
  }

  bool _rectOverlapsArea(ParkingArea a, int top, int left, int bottom, int right) {
    final (aTop, aLeft, aBottom, aRight) = _boundsOf(a);
    final overlapRow = !(bottom < aTop || top > aBottom);
    final overlapCol = !(right < aLeft || left > aRight);
    return overlapRow && overlapCol;
  }

  Set<int> _occupiedCellsByParkingAreas(List<ParkingArea> areas) {
    final occ = <int>{};
    for (final a in areas) {
      final (top, left, bottom, right) = _boundsOf(a);
      for (int r = top; r <= bottom; r++) {
        for (int c = left; c <= right; c++) {
          if (r < 0 || c < 0 || r >= widget.rows || c >= widget.cols) continue;
          occ.add(_idx(r, c));
        }
      }
    }
    return occ;
  }

  bool _isCellOccupiedByParkingArea(int r, int c) {
    for (final a in widget.parkingAreas) {
      if (_cellInsideArea(a, r, c)) return true;
    }
    return false;
  }

  void _eraseParkingAreaAtCell(int r, int c) {
    if (widget.parkingAreas.isEmpty) return;
    final next = widget.parkingAreas.where((a) => !_cellInsideArea(a, r, c)).toList(growable: false);
    if (next.length == widget.parkingAreas.length) return;
    widget.onChangedParkingAreas(next);
  }

  void _applyParkingAreaAtCell(int r, int c) {
    if (widget.tool == GridEditTool.parkingEraser) {
      _eraseParkingAreaAtCell(r, c);
      return;
    }

    final (h, w) = _desiredSizeForTool(widget.tool);
    if (h <= 0 || w <= 0) return;

    final top = min(r, widget.rows - h);
    final left = min(c, widget.cols - w);
    final bottom = top + h - 1;
    final right = left + w - 1;

    if (top < 0 || left < 0 || bottom >= widget.rows || right >= widget.cols) return;

    for (int rr = top; rr <= bottom; rr++) {
      for (int cc = left; cc <= right; cc++) {
        final i = _idx(rr, cc);
        if (i < 0 || i >= widget.cells.length) return;
        if (widget.cells[i] != ParkingGridCellType.empty) return;
      }
    }

    for (final a in widget.parkingAreas) {
      if (_rectOverlapsArea(a, top, left, bottom, right)) return;
    }

    final occ = _occupiedCellsByParkingAreas(widget.parkingAreas);
    for (int rr = top; rr <= bottom; rr++) {
      for (int cc = left; cc <= right; cc++) {
        if (occ.contains(_idx(rr, cc))) return;
      }
    }

    final kind = _kindForTool(widget.tool);
    final newArea = ParkingArea(
      id: _nextParkingAreaId(),
      r0: top,
      c0: left,
      kind: kind,
    );

    final next = <ParkingArea>[...widget.parkingAreas, newArea];
    widget.onChangedParkingAreas(next);
  }

  GridRect _rectFromIdxPair(int a, int b) {
    final r0 = a ~/ widget.cols;
    final c0 = a % widget.cols;
    final r1 = b ~/ widget.cols;
    final c1 = b % widget.cols;
    return GridRect(r0: r0, c0: c0, r1: r1, c1: c1).normalized();
  }

  List<GridRect> _rectsForLayer(_RectLayer layer) {
    switch (layer) {
      case _RectLayer.entrance:
        return widget.entranceRects;
      case _RectLayer.exit:
        return widget.exitRects;
      case _RectLayer.tower:
        return widget.towerRects;
    }
  }

  void _emitRectsForLayer(_RectLayer layer, List<GridRect> next) {
    final v = List<GridRect>.unmodifiable(next);
    switch (layer) {
      case _RectLayer.entrance:
        widget.onChangedEntranceRects(v);
        return;
      case _RectLayer.exit:
        widget.onChangedExitRects(v);
        return;
      case _RectLayer.tower:
        widget.onChangedTowerRects(v);
        return;
    }
  }

  void _clearRectDraft() {
    if (_rectDraftRect == null && _rectDragStartIdx == -1 && _rectDragCurIdx == -1) return;
    setState(() {
      _rectDragStartIdx = -1;
      _rectDragCurIdx = -1;
      _rectDraftRect = null;
      _rectDraftLayer = null;
    });
  }

  bool _rectOverlapsAnyRects(GridRect rect, List<GridRect> rects) {
    final n = rect.normalized();
    for (final e in rects) {
      if (e.normalized().overlaps(n)) return true;
    }
    return false;
  }

  bool _rectOverlapsAnyLayer(GridRect rect) {
    for (final layer in _RectLayer.values) {
      if (_rectOverlapsAnyRects(rect, _rectsForLayer(layer))) return true;
    }
    return false;
  }

  bool _towerRectTouchesNonEmpty(GridRect rect) {
    final n = rect.normalized();
    for (int r = n.r0; r <= n.r1; r++) {
      for (int c = n.c0; c <= n.c1; c++) {
        final idx = r * widget.cols + c;
        if (idx < 0 || idx >= widget.cells.length) return true;
        if (widget.cells[idx] != ParkingGridCellType.empty) return true;
      }
    }
    return false;
  }

  bool _towerRectOverlapsParkingAreas(GridRect rect) {
    final n = rect.normalized();
    for (final a in widget.parkingAreas) {
      final h = a.kind.h;
      final w = a.kind.w;
      final areaRect = GridRect(
        r0: a.r0,
        c0: a.c0,
        r1: a.r0 + h - 1,
        c1: a.c0 + w - 1,
      ).normalized();
      if (areaRect.overlaps(n)) return true;
    }
    return false;
  }

  void _addRect(GridRect rect, {required _RectLayer layer}) {
    final n = rect.normalized();
    final list = _rectsForLayer(layer);
    final next = <GridRect>[...list];
    final exists = next.any((e) => e.normalized() == n);
    if (exists) return;

    if (layer == _RectLayer.tower) {
      if (_rectOverlapsAnyLayer(n)) return;
      if (_towerRectOverlapsParkingAreas(n)) return;
      if (_towerRectTouchesNonEmpty(n)) return;
    } else {
      if (_rectOverlapsAnyRects(n, widget.towerRects)) return;
    }

    next.add(n);
    _emitRectsForLayer(layer, next);
  }

  void _eraseRectsAtCell(int r, int c) {
    for (final layer in _RectLayer.values) {
      final list = _rectsForLayer(layer);
      if (list.isEmpty) continue;
      final next = list.where((e) => !e.normalized().containsCell(r, c)).toList(growable: false);
      if (next.length != list.length) _emitRectsForLayer(layer, next);
    }
  }

  Set<EdgeSide> _allowedOutwardSidesForCell(int r, int c) {
    final sides = <EdgeSide>{};
    if (r == 0) sides.add(EdgeSide.north);
    if (r == widget.rows - 1) sides.add(EdgeSide.south);
    if (c == 0) sides.add(EdgeSide.west);
    if (c == widget.cols - 1) sides.add(EdgeSide.east);
    return sides;
  }

  EdgeSide _resolvePerimeterSide({
    required int idx,
    required Offset p,
    required Rect rect,
    required _Grid2DLayout layout,
  }) {
    final r = idx ~/ widget.cols;
    final c = idx % widget.cols;

    final allowed = _allowedOutwardSidesForCell(r, c);
    final raw = layout.nearestSide(p, rect);

    if (allowed.isEmpty) return raw;
    if (allowed.contains(raw)) return raw;

    double distFor(EdgeSide s) {
      switch (s) {
        case EdgeSide.north:
          return (p.dy - rect.top).abs();
        case EdgeSide.south:
          return (rect.bottom - p.dy).abs();
        case EdgeSide.west:
          return (p.dx - rect.left).abs();
        case EdgeSide.east:
          return (rect.right - p.dx).abs();
      }
    }

    EdgeSide best = allowed.first;
    double bestD = distFor(best);
    for (final s in allowed) {
      final d = distFor(s);
      if (d < bestD) {
        bestD = d;
        best = s;
      }
    }
    return best;
  }

  void _applyCellAt(int idx) {
    if (idx < 0 || idx >= widget.cells.length) return;

    final r = idx ~/ widget.cols;
    final c = idx % widget.cols;
    if (_isCellOccupiedByParkingArea(r, c)) return;

    final nextCell = _cellForTool(widget.tool);
    final nextCells = List<ParkingGridCellType>.from(widget.cells);
    final nextRoad2 = Set<int>.from(widget.road2Cells);

    if (widget.tool == GridEditTool.road2) {
      nextCells[idx] = ParkingGridCellType.road;
      nextRoad2.add(idx);
    } else if (widget.tool == GridEditTool.road) {
      nextCells[idx] = ParkingGridCellType.road;
      nextRoad2.remove(idx);
    } else {
      nextCells[idx] = nextCell;
      if (nextCell != ParkingGridCellType.road) {
        nextRoad2.remove(idx);
      } else {
        nextRoad2.remove(idx);
      }
    }

    final changedCells = !_listEquals(widget.cells, nextCells);
    final changedRoad2 = !_setEquals(widget.road2Cells, nextRoad2);

    if (changedCells) widget.onChangedCells(nextCells);
    if (changedRoad2) widget.onChangedRoad2Cells(nextRoad2);
  }

  void _cycleCellAt(int idx) {
    if (idx < 0 || idx >= widget.cells.length) return;

    final r = idx ~/ widget.cols;
    final c = idx % widget.cols;
    if (_isCellOccupiedByParkingArea(r, c)) return;

    final nextCells = List<ParkingGridCellType>.from(widget.cells);
    final nextRoad2 = Set<int>.from(widget.road2Cells);

    nextCells[idx] = _cycleCell(nextCells[idx]);

    if (nextCells[idx] != ParkingGridCellType.road) {
      nextRoad2.remove(idx);
    } else {
      nextRoad2.remove(idx);
    }

    final changedCells = !_listEquals(widget.cells, nextCells);
    final changedRoad2 = !_setEquals(widget.road2Cells, nextRoad2);

    if (changedCells) widget.onChangedCells(nextCells);
    if (changedRoad2) widget.onChangedRoad2Cells(nextRoad2);
  }

  void _applyWallAt({required int idx, required EdgeSide side}) {
    final r = idx ~/ widget.cols;
    final c = idx % widget.cols;
    final w = EdgePlacement(r: r, c: c, side: side);
    if (!isEdgeValid(w, widget.rows, widget.cols)) return;

    final nextWalls = Map<EdgePlacement, WallGroupId?>.from(widget.walls);
    final nextSel = Set<EdgePlacement>.from(widget.selectedWalls);

    switch (widget.tool) {
      case GridEditTool.wall:
        nextWalls.putIfAbsent(w, () => null);
        widget.onChangedWalls(nextWalls);
        return;
      case GridEditTool.wallEraser:
        if (nextWalls.containsKey(w)) {
          nextWalls.remove(w);
          nextSel.remove(w);
          widget.onChangedWalls(nextWalls);
          widget.onChangedSelectedWalls(nextSel);
        }
        return;
      case GridEditTool.wallSelect:
        nextWalls.putIfAbsent(w, () => null);
        if (nextSel.contains(w)) {
          nextSel.remove(w);
        } else {
          nextSel.add(w);
        }
        widget.onChangedWalls(nextWalls);
        widget.onChangedSelectedWalls(nextSel);
        return;
      default:
        return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final layout = _Grid2DLayout.fit(
          size: size,
          rows: widget.rows,
          cols: widget.cols,
          padding: 10,
        );

        int hit(Offset p) => layout.hitTest(p);

        _RectLayer? currentLayer() => _layerForTool(widget.tool);
        bool isRectEraser() => widget.tool == GridEditTool.rectEraser;

        void handleTap(Offset localPos) {
          final idx = hit(localPos);
          if (idx < 0) return;

          if (_isRectTool(widget.tool)) {
            final r = idx ~/ widget.cols;
            final c = idx % widget.cols;

            if (isRectEraser()) {
              _eraseRectsAtCell(r, c);
            } else {
              final layer = currentLayer();
              if (layer == null) return;
              final rect = GridRect(r0: r, c0: c, r1: r, c1: c).normalized();
              _addRect(rect, layer: layer);
            }
            return;
          }

          if (_isParkingTool(widget.tool)) {
            final r = idx ~/ widget.cols;
            final c = idx % widget.cols;
            _applyParkingAreaAtCell(r, c);
            return;
          }

          if (_isEdgeTool(widget.tool)) {
            final rect = layout.rectForIndex(idx);
            final side = _resolvePerimeterSide(idx: idx, p: localPos, rect: rect, layout: layout);
            _applyWallAt(idx: idx, side: side);
            return;
          }

          _applyCellAt(idx);
        }

        void startRectDrag(Offset localPos) {
          final idx = hit(localPos);
          if (idx < 0) return;

          if (isRectEraser()) {
            _lastDragIdx = -1;
            final r = idx ~/ widget.cols;
            final c = idx % widget.cols;
            _eraseRectsAtCell(r, c);
            _lastDragIdx = idx;
            return;
          }

          final layer = currentLayer();
          if (layer == null) return;

          setState(() {
            _rectDragStartIdx = idx;
            _rectDragCurIdx = idx;
            _rectDraftLayer = layer;
            _rectDraftRect = _rectFromIdxPair(idx, idx);
          });
        }

        void updateRectDrag(Offset localPos) {
          final idx = hit(localPos);
          if (idx < 0) return;

          if (isRectEraser()) {
            if (idx == _lastDragIdx) return;
            _lastDragIdx = idx;
            final r = idx ~/ widget.cols;
            final c = idx % widget.cols;
            _eraseRectsAtCell(r, c);
            return;
          }

          if (_rectDragStartIdx < 0) return;
          if (idx == _rectDragCurIdx) return;

          _rectDragCurIdx = idx;
          final rect = _rectFromIdxPair(_rectDragStartIdx, _rectDragCurIdx);
          setState(() {
            _rectDraftRect = rect;
          });
        }

        void endRectDrag() {
          if (isRectEraser()) {
            _lastDragIdx = -1;
            return;
          }

          final startIdx = _rectDragStartIdx;
          final curIdx = _rectDragCurIdx;
          if (startIdx < 0 || curIdx < 0) {
            _clearRectDraft();
            return;
          }

          final layer = _rectDraftLayer;
          if (layer == null) {
            _clearRectDraft();
            return;
          }

          final rect = _rectFromIdxPair(startIdx, curIdx);
          _addRect(rect, layer: layer);
          _clearRectDraft();
        }

        void handleDrag(Offset localPos) {
          if (_longPressActive) return;

          final idx = hit(localPos);
          if (idx < 0) return;

          if (_isParkingTool(widget.tool)) {
            if (idx == _lastDragIdx) return;
            _lastDragIdx = idx;
            final r = idx ~/ widget.cols;
            final c = idx % widget.cols;
            _applyParkingAreaAtCell(r, c);
            return;
          }

          if (_isEdgeTool(widget.tool)) {
            final rect = layout.rectForIndex(idx);
            final side = _resolvePerimeterSide(idx: idx, p: localPos, rect: rect, layout: layout);
            final r = idx ~/ widget.cols;
            final c = idx % widget.cols;
            final edge = EdgePlacement(r: r, c: c, side: side);
            if (_lastDragEdge == edge) return;
            _lastDragEdge = edge;
            _applyWallAt(idx: idx, side: side);
            return;
          }

          if (idx == _lastDragIdx) return;
          _lastDragIdx = idx;
          _applyCellAt(idx);
        }

        void handleLongPressStart(Offset localPos) {
          if (!_isCellTool(widget.tool)) return;

          final idx = hit(localPos);
          if (idx < 0) return;

          _longPressActive = true;
          _lastLongPressIdx = idx;
          _cycleCellAt(idx);
        }

        void handleLongPressMove(Offset localPos) {
          if (!_longPressActive) return;
          if (!_isCellTool(widget.tool)) return;

          final idx = hit(localPos);
          if (idx < 0) return;
          if (idx == _lastLongPressIdx) return;

          _lastLongPressIdx = idx;
          _cycleCellAt(idx);
        }

        void handleLongPressEnd() {
          _longPressActive = false;
          _lastLongPressIdx = -1;
        }

        final visibleSelectedWalls =
        widget.tool == GridEditTool.wallSelect ? widget.selectedWalls : <EdgePlacement>{};

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => handleTap(d.localPosition),
          onPanStart: (d) {
            _lastDragIdx = -1;
            _lastDragEdge = null;
            if (_isRectTool(widget.tool)) {
              startRectDrag(d.localPosition);
            } else {
              handleDrag(d.localPosition);
            }
          },
          onPanUpdate: (d) {
            if (_isRectTool(widget.tool)) {
              updateRectDrag(d.localPosition);
            } else {
              handleDrag(d.localPosition);
            }
          },
          onPanEnd: (_) {
            _lastDragIdx = -1;
            _lastDragEdge = null;
            if (_isRectTool(widget.tool)) endRectDrag();
          },
          onLongPressStart: (d) => handleLongPressStart(d.localPosition),
          onLongPressMoveUpdate: (d) => handleLongPressMove(d.localPosition),
          onLongPressEnd: (_) => handleLongPressEnd(),
          child: CustomPaint(
            painter: _ParkingGrid2DPainter(
              rows: widget.rows,
              cols: widget.cols,
              cells: widget.cells,
              road2Cells: widget.road2Cells,
              entranceRects: widget.entranceRects,
              exitRects: widget.exitRects,
              towerRects: widget.towerRects,
              draftRect: _rectDraftRect,
              draftRectLayer: _rectDraftLayer,
              colorScheme: cs,
              layout: layout,
              walls: widget.walls,
              wallGroups: widget.wallGroups,
              selectedWalls: visibleSelectedWalls,
              parkingAreas: widget.parkingAreas,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }

  bool _listEquals(List<ParkingGridCellType> a, List<ParkingGridCellType> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  bool _setEquals(Set<int> a, Set<int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final v in a) {
      if (!b.contains(v)) return false;
    }
    return true;
  }
}

@immutable
class _Grid2DLayout {
  final int rows;
  final int cols;
  final double padding;
  final double cell;
  final Offset origin;

  const _Grid2DLayout({
    required this.rows,
    required this.cols,
    required this.padding,
    required this.cell,
    required this.origin,
  });

  factory _Grid2DLayout.fit({
    required Size size,
    required int rows,
    required int cols,
    required double padding,
  }) {
    final usableW = max(40.0, size.width - 2 * padding);
    final usableH = max(40.0, size.height - 2 * padding);

    final cell = min(usableW / cols, usableH / rows).clamp(8.0, 90.0);

    final gridW = cell * cols;
    final gridH = cell * rows;

    final ox = (size.width - gridW) / 2;
    final oy = (size.height - gridH) / 2;

    return _Grid2DLayout(
      rows: rows,
      cols: cols,
      padding: padding,
      cell: cell,
      origin: Offset(ox, oy),
    );
  }

  Rect cellRect(int r, int c) {
    return Rect.fromLTWH(
      origin.dx + c * cell,
      origin.dy + r * cell,
      cell,
      cell,
    );
  }

  Rect rectForIndex(int idx) {
    final r = idx ~/ cols;
    final c = idx % cols;
    return cellRect(r, c);
  }

  EdgeSide nearestSide(Offset p, Rect rect) {
    final dTop = (p.dy - rect.top).abs();
    final dBottom = (rect.bottom - p.dy).abs();
    final dLeft = (p.dx - rect.left).abs();
    final dRight = (rect.right - p.dx).abs();

    final minD = min(min(dTop, dBottom), min(dLeft, dRight));
    if (minD == dTop) return EdgeSide.north;
    if (minD == dBottom) return EdgeSide.south;
    if (minD == dLeft) return EdgeSide.west;
    return EdgeSide.east;
  }

  int hitTest(Offset p) {
    final x = p.dx;
    final y = p.dy;

    final left = origin.dx;
    final top = origin.dy;
    final right = origin.dx + cols * cell;
    final bottom = origin.dy + rows * cell;

    if (x < left || x >= right || y < top || y >= bottom) return -1;

    final c = ((x - left) / cell).floor();
    final r = ((y - top) / cell).floor();

    if (r < 0 || r >= rows || c < 0 || c >= cols) return -1;
    return r * cols + c;
  }
}

class _ParkingGrid2DPainter extends CustomPainter {
  final int rows;
  final int cols;
  final List<ParkingGridCellType> cells;
  final Set<int> road2Cells;
  final List<GridRect> entranceRects;
  final List<GridRect> exitRects;
  final List<GridRect> towerRects;
  final GridRect? draftRect;
  final _RectLayer? draftRectLayer;
  final ColorScheme colorScheme;
  final _Grid2DLayout layout;

  final Map<EdgePlacement, WallGroupId?> walls;
  final Map<WallGroupId, String> wallGroups;
  final Set<EdgePlacement> selectedWalls;
  final List<ParkingArea> parkingAreas;

  _ParkingGrid2DPainter({
    required this.rows,
    required this.cols,
    required this.cells,
    required this.road2Cells,
    required this.entranceRects,
    required this.exitRects,
    required this.towerRects,
    required this.draftRect,
    required this.draftRectLayer,
    required this.colorScheme,
    required this.layout,
    required this.walls,
    required this.wallGroups,
    required this.selectedWalls,
    required this.parkingAreas,
  });

  Color _shade(Color c, double deltaLightness) {
    final hsl = HSLColor.fromColor(c);
    final nextL = (hsl.lightness + deltaLightness).clamp(0.0, 1.0);
    return hsl.withLightness(nextL).toColor();
  }

  Color _cellColor(int idx, ParkingGridCellType t) {
    final cs = colorScheme;
    switch (t) {
      case ParkingGridCellType.road:
        return road2Cells.contains(idx)
            ? cs.tertiaryContainer.withOpacity(0.70)
            : cs.surfaceVariant.withOpacity(0.95);
      case ParkingGridCellType.pillar:
        return cs.errorContainer.withOpacity(0.75);
      case ParkingGridCellType.empty:
        return cs.primaryContainer.withOpacity(0.55);
    }
  }

  (int h, int w) _sizeForKind(ParkingAreaKind k) {
    final name = k.name.toLowerCase();
    if (name.contains('12')) return (1, 2);
    if (name.contains('21')) return (2, 1);
    if (name.contains('22')) return (2, 2);
    final idx = ParkingAreaKind.values.indexOf(k);
    if (idx == 0) return (1, 2);
    if (idx == 1) return (2, 1);
    return (2, 2);
  }

  void _drawParkingAreas(Canvas canvas) {
    if (parkingAreas.isEmpty) return;

    final cs = colorScheme;
    final cell = layout.cell;

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.secondaryContainer.withOpacity(0.45);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.4, cell * 0.06)
      ..color = cs.secondary.withOpacity(0.90);

    for (final a in parkingAreas) {
      final (h, w) = _sizeForKind(a.kind);

      final top = a.r0;
      final left = a.c0;
      final bottom = a.r0 + h - 1;
      final right = a.c0 + w - 1;

      if (top < 0 || left < 0 || bottom >= rows || right >= cols) continue;

      final tl = layout.cellRect(top, left);
      final br = layout.cellRect(bottom, right);

      final rect = Rect.fromLTRB(tl.left, tl.top, br.right, br.bottom)
          .deflate(max(1.0, cell * 0.04));

      final rr = RRect.fromRectAndRadius(rect, Radius.circular(max(6.0, cell * 0.18)));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);
    }
  }

  ({Color fill, Color stroke, String label}) _styleForRectLayer(_RectLayer layer) {
    final cs = colorScheme;
    switch (layer) {
      case _RectLayer.entrance:
        return (
        fill: cs.primaryContainer.withOpacity(0.22),
        stroke: cs.primary.withOpacity(0.92),
        label: '입구',
        );
      case _RectLayer.exit:
        return (
        fill: cs.errorContainer.withOpacity(0.22),
        stroke: cs.error.withOpacity(0.92),
        label: '출구',
        );
      case _RectLayer.tower:
        return (
        fill: cs.tertiaryContainer.withOpacity(0.18),
        stroke: cs.tertiary.withOpacity(0.92),
        label: '주차 타워',
        );
    }
  }

  ({Color fill, Color stroke}) _styleForDraft(_RectLayer layer) {
    final cs = colorScheme;
    switch (layer) {
      case _RectLayer.entrance:
        return (
        fill: cs.primaryContainer.withOpacity(0.12),
        stroke: cs.primary.withOpacity(0.95),
        );
      case _RectLayer.exit:
        return (
        fill: cs.errorContainer.withOpacity(0.12),
        stroke: cs.error.withOpacity(0.95),
        );
      case _RectLayer.tower:
        return (
        fill: cs.tertiaryContainer.withOpacity(0.10),
        stroke: cs.tertiary.withOpacity(0.95),
        );
    }
  }

  void _drawRectLayer(Canvas canvas, List<GridRect> rects, {required _RectLayer layer}) {
    if (rects.isEmpty) return;

    final cell = layout.cell;

    final style = _styleForRectLayer(layer);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = style.fill;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.6, cell * 0.07)
      ..color = style.stroke;

    final labelStyle = TextStyle(
      fontSize: max(10.0, cell * 0.18),
      fontWeight: FontWeight.w900,
      color: style.stroke.withOpacity(0.98),
    );

    for (final raw in rects) {
      final r = raw.normalized();
      if (r.r0 < 0 || r.c0 < 0 || r.r1 >= rows || r.c1 >= cols) continue;

      final tl = layout.cellRect(r.r0, r.c0);
      final br = layout.cellRect(r.r1, r.c1);

      final rect = Rect.fromLTRB(tl.left, tl.top, br.right, br.bottom)
          .deflate(max(1.0, cell * 0.06));

      final rr = RRect.fromRectAndRadius(rect, Radius.circular(max(6.0, cell * 0.22)));
      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);

      final text = style.label;
      final tp = TextPainter(
        text: TextSpan(text: text, style: labelStyle),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: rect.width - 6);

      if (rect.width >= 24 && rect.height >= 18) {
        tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, rect.top + max(2.0, cell * 0.06)));
      }
    }
  }

  void _drawDraftRect(Canvas canvas) {
    final raw = draftRect;
    final layer = draftRectLayer;
    if (raw == null) return;
    if (layer == null) return;

    final cell = layout.cell;
    final r = raw.normalized();
    if (r.r0 < 0 || r.c0 < 0 || r.r1 >= rows || r.c1 >= cols) return;

    final tl = layout.cellRect(r.r0, r.c0);
    final br = layout.cellRect(r.r1, r.c1);

    final rect = Rect.fromLTRB(tl.left, tl.top, br.right, br.bottom).deflate(max(1.0, cell * 0.06));

    final style = _styleForDraft(layer);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = style.fill;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(2.4, cell * 0.10)
      ..color = style.stroke;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(max(6.0, cell * 0.22))),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, Radius.circular(max(6.0, cell * 0.22))),
      stroke,
    );
  }

  void _drawWall2D(Canvas canvas, EdgePlacement w, {required bool selected}) {
    final cs = colorScheme;
    final cell = layout.cell;
    final rect = layout.cellRect(w.r, w.c);

    final th = max(3.0, cell * 0.12);
    final out = max(4.0, cell * 0.10);

    Offset a;
    Offset b;
    Offset outward;

    switch (w.side) {
      case EdgeSide.north:
        a = Offset(rect.left, rect.top);
        b = Offset(rect.right, rect.top);
        outward = const Offset(0, -1);
        break;
      case EdgeSide.south:
        a = Offset(rect.left, rect.bottom);
        b = Offset(rect.right, rect.bottom);
        outward = const Offset(0, 1);
        break;
      case EdgeSide.west:
        a = Offset(rect.left, rect.top);
        b = Offset(rect.left, rect.bottom);
        outward = const Offset(-1, 0);
        break;
      case EdgeSide.east:
        a = Offset(rect.right, rect.top);
        b = Offset(rect.right, rect.bottom);
        outward = const Offset(1, 0);
        break;
    }

    a = a + outward * out;
    b = b + outward * out;

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = th
      ..color = cs.onSurface.withOpacity(0.40);

    final hi = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = th + 1.2
      ..color = selected ? cs.primary.withOpacity(0.92) : cs.outlineVariant.withOpacity(0.65);

    canvas.drawLine(a, b, base);
    canvas.drawLine(a, b, hi);
  }

  void _drawWallName2D(Canvas canvas, EdgePlacement w, String name) {
    final cs = colorScheme;
    final rect = layout.cellRect(w.r, w.c);
    final cell = layout.cell;

    Offset pos;
    switch (w.side) {
      case EdgeSide.north:
        pos = Offset(rect.center.dx, rect.top - max(18.0, cell * 0.28));
        break;
      case EdgeSide.south:
        pos = Offset(rect.center.dx, rect.bottom + max(6.0, cell * 0.12));
        break;
      case EdgeSide.west:
        pos = Offset(rect.left - max(60.0, cell * 0.80), rect.center.dy - 8);
        break;
      case EdgeSide.east:
        pos = Offset(rect.right + max(6.0, cell * 0.12), rect.center.dy - 8);
        break;
    }

    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          fontSize: max(10.0, cell * 0.18),
          fontWeight: FontWeight.w900,
          color: cs.onSurface.withOpacity(0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 160);

    tp.paint(canvas, pos);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cs = colorScheme;

    final gridRect = Rect.fromLTWH(
      layout.origin.dx,
      layout.origin.dy,
      layout.cell * cols,
      layout.cell * rows,
    );

    final bg = Paint()
      ..style = PaintingStyle.fill
      ..color = _shade(cs.surfaceVariant, 0.05);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = cs.outlineVariant.withOpacity(0.95);

    canvas.drawRRect(RRect.fromRectAndRadius(gridRect, const Radius.circular(10)), bg);
    canvas.drawRRect(RRect.fromRectAndRadius(gridRect, const Radius.circular(10)), border);

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        if (idx < 0 || idx >= cells.length) continue;

        final rect = layout.cellRect(r, c).deflate(1.0);
        final t = cells[idx];

        final fill = Paint()
          ..style = PaintingStyle.fill
          ..color = _cellColor(idx, t);

        canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), fill);

        if (t == ParkingGridCellType.pillar) {
          final center = rect.center;
          final rr = max(3.0, layout.cell * 0.18);
          final pFill = Paint()..color = cs.onSurface.withOpacity(0.20);
          final pStroke = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.2, layout.cell * 0.035)
            ..color = cs.onSurface.withOpacity(0.55);
          canvas.drawCircle(center, rr, pFill);
          canvas.drawCircle(center, rr, pStroke);
        }

        if (t == ParkingGridCellType.road) {
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = max(1.2, layout.cell * 0.04)
            ..color = cs.surface.withOpacity(0.70);

          final a = Offset(rect.center.dx, rect.top + rect.height * 0.18);
          final b = Offset(rect.center.dx, rect.bottom - rect.height * 0.18);

          final dash = max(4.0, layout.cell * 0.12);
          final gap = max(3.0, layout.cell * 0.08);

          double t0 = 0;
          final dx = b.dx - a.dx;
          final dy = b.dy - a.dy;
          final len = sqrt(dx * dx + dy * dy);
          if (len > 1e-6) {
            final ux = dx / len;
            final uy = dy / len;
            while (t0 < len) {
              final t1 = min(len, t0 + dash);
              canvas.drawLine(
                Offset(a.dx + ux * t0, a.dy + uy * t0),
                Offset(a.dx + ux * t1, a.dy + uy * t1),
                paint,
              );
              t0 = t1 + gap;
            }
          }
        }
      }
    }

    final gridLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = cs.outlineVariant.withOpacity(0.25);

    for (int r = 0; r <= rows; r++) {
      final y = layout.origin.dy + r * layout.cell;
      canvas.drawLine(Offset(layout.origin.dx, y), Offset(layout.origin.dx + cols * layout.cell, y), gridLine);
    }
    for (int c = 0; c <= cols; c++) {
      final x = layout.origin.dx + c * layout.cell;
      canvas.drawLine(Offset(x, layout.origin.dy), Offset(x, layout.origin.dy + rows * layout.cell), gridLine);
    }

    _drawParkingAreas(canvas);

    _drawRectLayer(canvas, entranceRects, layer: _RectLayer.entrance);
    _drawRectLayer(canvas, exitRects, layer: _RectLayer.exit);
    _drawRectLayer(canvas, towerRects, layer: _RectLayer.tower);
    _drawDraftRect(canvas);

    for (final w in walls.keys) {
      _drawWall2D(canvas, w, selected: selectedWalls.contains(w));
    }

    final reps = <WallGroupId, EdgePlacement>{};
    for (final e in walls.entries) {
      final gid = e.value;
      if (gid == null) continue;

      final name = wallGroups[gid]?.trim();
      if (name == null || name.isEmpty) continue;

      if (!reps.containsKey(gid)) {
        reps[gid] = e.key;
      } else {
        final cur = reps[gid]!;
        final a = edgeSortKey(e.key);
        final b = edgeSortKey(cur);
        if (a < b) reps[gid] = e.key;
      }
    }

    for (final entry in reps.entries) {
      final name = wallGroups[entry.key]?.trim() ?? '';
      if (name.isNotEmpty) _drawWallName2D(canvas, entry.value, name);
    }
  }

  @override
  bool shouldRepaint(covariant _ParkingGrid2DPainter oldDelegate) {
    return oldDelegate.rows != rows ||
        oldDelegate.cols != cols ||
        oldDelegate.layout.cell != layout.cell ||
        oldDelegate.layout.origin != layout.origin ||
        oldDelegate.cells != cells ||
        oldDelegate.road2Cells != road2Cells ||
        oldDelegate.entranceRects != entranceRects ||
        oldDelegate.exitRects != exitRects ||
        oldDelegate.towerRects != towerRects ||
        oldDelegate.draftRect != draftRect ||
        oldDelegate.draftRectLayer != draftRectLayer ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.walls != walls ||
        oldDelegate.wallGroups != wallGroups ||
        oldDelegate.selectedWalls != selectedWalls ||
        oldDelegate.parkingAreas != parkingAreas;
  }
}
