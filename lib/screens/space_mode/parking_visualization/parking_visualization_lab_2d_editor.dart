part of 'parking_visualization_lab_screen.dart';


enum _PaintTool {
  empty, 
  road,
  occupied, 
  blocked, 
  pillar,

  wall,
  wallEraser,
  wallSelect,

  entrance,
  exit,
  gateEraser,
}

class _ParkingGarage2DEditor extends StatefulWidget {
  final int rows;
  final int cols;
  final List<ParkingCellState> cells;

  final _CellColorResolver getCellColor;

  final int selectedCellIndex;
  final ValueChanged<int> onSelectCell;

  final ValueChanged<List<ParkingCellState>> onChangedCells;

  final _EdgePlacement? entranceGate;
  final _EdgePlacement? exitGate;
  final void Function(_EdgePlacement? entrance, _EdgePlacement? exit)
  onChangedGates;

  final _PaintTool tool;

  
  final Map<_EdgePlacement, _WallGroupId?> walls;

  
  final Map<_WallGroupId, String> wallGroups;

  
  final Set<_EdgePlacement> selectedWalls;
  final ValueChanged<Map<_EdgePlacement, _WallGroupId?>> onChangedWalls;
  final ValueChanged<Set<_EdgePlacement>> onChangedSelectedWalls;

  const _ParkingGarage2DEditor({
    required this.rows,
    required this.cols,
    required this.cells,
    required this.getCellColor,
    required this.selectedCellIndex,
    required this.onSelectCell,
    required this.onChangedCells,
    required this.entranceGate,
    required this.exitGate,
    required this.onChangedGates,
    required this.tool,
    required this.walls,
    required this.wallGroups,
    required this.selectedWalls,
    required this.onChangedWalls,
    required this.onChangedSelectedWalls,
  });

  @override
  State<_ParkingGarage2DEditor> createState() => _ParkingGarage2DEditorState();
}

class _ParkingGarage2DEditorState extends State<_ParkingGarage2DEditor> {
  int _lastDragIdx = -1;
  _EdgePlacement? _lastDragEdge;

  bool _isGateTool(_PaintTool t) =>
      t == _PaintTool.entrance ||
          t == _PaintTool.exit ||
          t == _PaintTool.gateEraser;

  bool _isWallTool(_PaintTool t) =>
      t == _PaintTool.wall ||
          t == _PaintTool.wallEraser ||
          t == _PaintTool.wallSelect;

  bool _isEdgeTool(_PaintTool t) => _isGateTool(t) || _isWallTool(t);

  
  bool _isSpotTool(_PaintTool t) =>
      t == _PaintTool.empty || t == _PaintTool.occupied || t == _PaintTool.blocked;

  ParkingCellState _stateForTool(_PaintTool t) {
    switch (t) {
      case _PaintTool.empty:
        return ParkingCellState.empty;
      case _PaintTool.road:
        return ParkingCellState.road;
      case _PaintTool.occupied:
        return ParkingCellState.occupied;
      case _PaintTool.blocked:
        return ParkingCellState.blocked;
      case _PaintTool.pillar:
        return ParkingCellState.pillar;

      case _PaintTool.wall:
      case _PaintTool.wallEraser:
      case _PaintTool.wallSelect:
      case _PaintTool.entrance:
      case _PaintTool.exit:
      case _PaintTool.gateEraser:
        return ParkingCellState.empty;
    }
  }

  ParkingCellState _cycle(ParkingCellState s) {
    
    switch (s) {
      case ParkingCellState.empty:
        return ParkingCellState.road;
      case ParkingCellState.road:
        return ParkingCellState.occupied;
      case ParkingCellState.occupied:
        return ParkingCellState.blocked;
      case ParkingCellState.blocked:
        return ParkingCellState.pillar;
      case ParkingCellState.pillar:
        return ParkingCellState.empty;
    }
  }

  
  List<int> _spotIndices(int idx) =>
      _spotIndicesForIndex(idx, widget.rows, widget.cols);

  
  int _spotRep(int idx) => _spotRepIndex(idx, widget.cols);

  void _applyAt(int idx, ParkingCellState nextState) {
    if (idx < 0 || idx >= widget.cells.length) return;

    widget.onSelectCell(idx);

    if (widget.cells[idx] == nextState) return;

    final next = List<ParkingCellState>.from(widget.cells);
    next[idx] = nextState;
    widget.onChangedCells(next);
  }

  
  void _applySpotAt(int idx, ParkingCellState nextState) {
    final indices = _spotIndices(idx);
    if (indices.isEmpty) return;

    final rep = indices.first;
    widget.onSelectCell(rep);

    final next = List<ParkingCellState>.from(widget.cells);
    bool changed = false;

    for (final i in indices) {
      if (i < 0 || i >= next.length) continue;
      if (next[i] != nextState) {
        next[i] = nextState;
        changed = true;
      }
    }

    if (changed) widget.onChangedCells(next);
  }

  void _applyToolAt(int idx) {
    final nextState = _stateForTool(widget.tool);

    if (_isSpotTool(widget.tool)) {
      _applySpotAt(idx, nextState);
      return;
    }

    _applyAt(idx, nextState);
  }

  void _cycleAt(int idx) {
    if (idx < 0 || idx >= widget.cells.length) return;

    
    final st = widget.cells[idx];
    if (_isParkingZoneState(st)) {
      final rep = _spotRep(idx);
      final indices = _spotIndices(rep);
      if (indices.length >= 2) {
        final base = widget.cells[rep];
        final nextState = _cycle(base);
        _applySpotAt(rep, nextState);
        return;
      }
    }

    
    final nextState = _cycle(widget.cells[idx]);
    _applyAt(idx, nextState);
  }

  Set<_EdgeSide> _allowedOutwardSidesForCell(int r, int c) {
    final sides = <_EdgeSide>{};
    if (r == 0) sides.add(_EdgeSide.north);
    if (r == widget.rows - 1) sides.add(_EdgeSide.south);
    if (c == 0) sides.add(_EdgeSide.west);
    if (c == widget.cols - 1) sides.add(_EdgeSide.east);
    return sides;
  }

  _EdgeSide _resolvePerimeterSide({
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

    double distFor(_EdgeSide s) {
      switch (s) {
        case _EdgeSide.north:
          return (p.dy - rect.top).abs();
        case _EdgeSide.south:
          return (rect.bottom - p.dy).abs();
        case _EdgeSide.west:
          return (p.dx - rect.left).abs();
        case _EdgeSide.east:
          return (rect.right - p.dx).abs();
      }
    }

    _EdgeSide best = allowed.first;
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

  void _applyGateAt({
    required int idx,
    required _EdgeSide side,
  }) {
    if (idx < 0 || idx >= widget.cells.length) return;

    final r = idx ~/ widget.cols;
    final c = idx % widget.cols;

    final g = _EdgePlacement(r: r, c: c, side: side);
    if (!_isEdgeValid(g, widget.rows, widget.cols)) return;

    widget.onSelectCell(idx);

    _EdgePlacement? entrance = widget.entranceGate;
    _EdgePlacement? exit = widget.exitGate;

    
    if (widget.walls.containsKey(g)) {
      final nextWalls = Map<_EdgePlacement, _WallGroupId?>.from(widget.walls);
      nextWalls.remove(g);
      widget.onChangedWalls(nextWalls);

      final nextSel = Set<_EdgePlacement>.from(widget.selectedWalls);
      nextSel.remove(g);
      widget.onChangedSelectedWalls(nextSel);
    }

    if (widget.tool == _PaintTool.gateEraser) {
      if (entrance == g) entrance = null;
      if (exit == g) exit = null;
      widget.onChangedGates(entrance, exit);
      return;
    }

    if (widget.tool == _PaintTool.entrance) {
      entrance = g;
      widget.onChangedGates(entrance, exit);
      return;
    }

    if (widget.tool == _PaintTool.exit) {
      exit = g;
      widget.onChangedGates(entrance, exit);
      return;
    }
  }

  void _applyWallAt({
    required int idx,
    required _EdgeSide side,
  }) {
    if (idx < 0 || idx >= widget.cells.length) return;

    final r = idx ~/ widget.cols;
    final c = idx % widget.cols;

    final w = _EdgePlacement(r: r, c: c, side: side);
    if (!_isEdgeValid(w, widget.rows, widget.cols)) return;

    widget.onSelectCell(idx);

    final nextWalls = Map<_EdgePlacement, _WallGroupId?>.from(widget.walls);
    final nextSel = Set<_EdgePlacement>.from(widget.selectedWalls);

    
    void removeGateIfSame() {
      _EdgePlacement? entrance = widget.entranceGate;
      _EdgePlacement? exit = widget.exitGate;
      bool changed = false;

      if (entrance == w) {
        entrance = null;
        changed = true;
      }
      if (exit == w) {
        exit = null;
        changed = true;
      }
      if (changed) {
        widget.onChangedGates(entrance, exit);
      }
    }

    switch (widget.tool) {
      case _PaintTool.wall:
        removeGateIfSame();
        if (!nextWalls.containsKey(w)) {
          nextWalls[w] = null; 
        }
        widget.onChangedWalls(nextWalls);
        widget.onChangedSelectedWalls(
            nextSel.where(nextWalls.containsKey).toSet());
        return;

      case _PaintTool.wallEraser:
        if (nextWalls.containsKey(w)) {
          nextWalls.remove(w);
          nextSel.remove(w);
          widget.onChangedWalls(nextWalls);
          widget.onChangedSelectedWalls(nextSel);
        }
        return;

      case _PaintTool.wallSelect:
        removeGateIfSame();
        if (!nextWalls.containsKey(w)) {
          nextWalls[w] = null;
        }
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

        void handleTap(Offset localPos) {
          final idx = hit(localPos);
          if (idx < 0) return;

          final rect = layout.rectForIndex(idx);

          if (_isEdgeTool(widget.tool)) {
            final side = _resolvePerimeterSide(
                idx: idx, p: localPos, rect: rect, layout: layout);

            if (_isGateTool(widget.tool)) {
              _applyGateAt(idx: idx, side: side);
            } else if (_isWallTool(widget.tool)) {
              _applyWallAt(idx: idx, side: side);
            }
          } else {
            _applyToolAt(idx);
          }
        }

        void handleDrag(Offset localPos) {
          final idx = hit(localPos);
          if (idx < 0) return;

          final rect = layout.rectForIndex(idx);

          if (_isEdgeTool(widget.tool)) {
            final side = _resolvePerimeterSide(
                idx: idx, p: localPos, rect: rect, layout: layout);
            final r = idx ~/ widget.cols;
            final c = idx % widget.cols;
            final edge = _EdgePlacement(r: r, c: c, side: side);

            if (_lastDragEdge == edge) return;
            _lastDragEdge = edge;

            if (_isGateTool(widget.tool)) {
              _applyGateAt(idx: idx, side: side);
            } else if (_isWallTool(widget.tool)) {
              _applyWallAt(idx: idx, side: side);
            }
          } else {
            
            final dragKey = _isSpotTool(widget.tool) ? _spotRep(idx) : idx;
            if (dragKey == _lastDragIdx) return;
            _lastDragIdx = dragKey;

            _applyToolAt(idx);
          }
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => handleTap(d.localPosition),
          onPanStart: (d) {
            _lastDragIdx = -1;
            _lastDragEdge = null;
            handleDrag(d.localPosition);
          },
          onPanUpdate: (d) => handleDrag(d.localPosition),
          onPanEnd: (_) {
            _lastDragIdx = -1;
            _lastDragEdge = null;
          },
          onLongPressStart: (d) {
            final idx = hit(d.localPosition);
            if (idx >= 0 && !_isEdgeTool(widget.tool)) _cycleAt(idx);
          },
          child: CustomPaint(
            painter: _Parking2DGridPainter(
              rows: widget.rows,
              cols: widget.cols,
              cells: widget.cells,
              colorScheme: cs,
              colorResolver: widget.getCellColor,
              layout: layout,
              selectedCellIndex: widget.selectedCellIndex,
              entranceGate: widget.entranceGate,
              exitGate: widget.exitGate,
              walls: widget.walls,
              wallGroups: widget.wallGroups,
              selectedWalls: widget.selectedWalls,
            ),
            child: const SizedBox.expand(),
          ),
        );
      },
    );
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

  _EdgeSide nearestSide(Offset p, Rect rect) {
    final dTop = (p.dy - rect.top).abs();
    final dBottom = (rect.bottom - p.dy).abs();
    final dLeft = (p.dx - rect.left).abs();
    final dRight = (rect.right - p.dx).abs();

    final minD = min(min(dTop, dBottom), min(dLeft, dRight));
    if (minD == dTop) return _EdgeSide.north;
    if (minD == dBottom) return _EdgeSide.south;
    if (minD == dLeft) return _EdgeSide.west;
    return _EdgeSide.east;
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

class _Parking2DGridPainter extends CustomPainter {
  final int rows;
  final int cols;
  final List<ParkingCellState> cells;
  final ColorScheme colorScheme;
  final _CellColorResolver colorResolver;
  final _Grid2DLayout layout;
  final int selectedCellIndex;

  final _EdgePlacement? entranceGate;
  final _EdgePlacement? exitGate;

  final Map<_EdgePlacement, _WallGroupId?> walls;
  final Map<_WallGroupId, String> wallGroups;
  final Set<_EdgePlacement> selectedWalls;

  _Parking2DGridPainter({
    required this.rows,
    required this.cols,
    required this.cells,
    required this.colorScheme,
    required this.colorResolver,
    required this.layout,
    required this.selectedCellIndex,
    required this.entranceGate,
    required this.exitGate,
    required this.walls,
    required this.wallGroups,
    required this.selectedWalls,
  });

  Color _shade(Color c, double deltaLightness) {
    final hsl = HSLColor.fromColor(c);
    final nextL = (hsl.lightness + deltaLightness).clamp(0.0, 1.0);
    return hsl.withLightness(nextL).toColor();
  }

  bool _isValidSpotPair(int r, int c0) {
    if (r < 0 || r >= rows) return false;
    if (c0 < 0 || c0 + 1 >= cols) return false;
    final idx0 = r * cols + c0;
    final idx1 = idx0 + 1;
    if (idx0 < 0 || idx1 < 0 || idx1 >= cells.length) return false;
    final a = cells[idx0];
    final b = cells[idx1];
    return _isParkingZoneState(a) && a == b;
  }

  Set<int> _selectedHighlightIndices() {
    final sel = selectedCellIndex;
    if (sel < 0 || sel >= cells.length) return <int>{};
    final r = sel ~/ cols;
    final c = sel % cols;
    final c0 = _spotRepCol(c);

    if (_isParkingZoneState(cells[sel]) && _isValidSpotPair(r, c0)) {
      final rep = r * cols + c0;
      return {rep, rep + 1};
    }
    return {sel};
  }

  _GateKind _gateKindFor(_EdgePlacement g) {
    final isE = (entranceGate != null && entranceGate == g);
    final isX = (exitGate != null && exitGate == g);
    if (isE && isX) return _GateKind.mixed;
    if (isE) return _GateKind.entrance;
    return _GateKind.exit;
  }

  Color _gateAccent(_GateKind k) {
    switch (k) {
      case _GateKind.entrance:
        return Colors.green;
      case _GateKind.exit:
        return Colors.red;
      case _GateKind.mixed:
        return Colors.amber;
    }
  }

  String _gateLabel(_GateKind k) {
    switch (k) {
      case _GateKind.entrance:
        return '입구';
      case _GateKind.exit:
        return '출구';
      case _GateKind.mixed:
        return '입/출';
    }
  }

  void _drawBarrier2D(Canvas canvas, _EdgePlacement g, _GateKind kind) {
    final cs = colorScheme;
    final accent = _gateAccent(kind);

    final rect = layout.cellRect(g.r, g.c);
    final cell = layout.cell;

    Offset edgeCenter;
    Offset outward;
    switch (g.side) {
      case _EdgeSide.north:
        edgeCenter = Offset(rect.center.dx, rect.top);
        outward = const Offset(0, -1);
        break;
      case _EdgeSide.south:
        edgeCenter = Offset(rect.center.dx, rect.bottom);
        outward = const Offset(0, 1);
        break;
      case _EdgeSide.west:
        edgeCenter = Offset(rect.left, rect.center.dy);
        outward = const Offset(-1, 0);
        break;
      case _EdgeSide.east:
        edgeCenter = Offset(rect.right, rect.center.dy);
        outward = const Offset(1, 0);
        break;
    }

    final outPx = max(8.0, cell * 0.14);
    final postCenter = edgeCenter + outward * outPx;

    final postW = max(7.0, cell * 0.12);
    final postH = max(14.0, cell * 0.22);

    Rect postRect;
    if (g.side == _EdgeSide.north || g.side == _EdgeSide.south) {
      postRect =
          Rect.fromCenter(center: postCenter, width: postW, height: postH);
    } else {
      postRect =
          Rect.fromCenter(center: postCenter, width: postH, height: postW);
    }

    final postFill = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.onSurface.withOpacity(0.78);

    canvas.drawRRect(
      RRect.fromRectAndRadius(postRect, Radius.circular(postW * 0.35)),
      postFill,
    );

    final armLen = cell * 0.78;
    final armTh = max(6.0, cell * 0.12);

    Rect armRect;
    if (g.side == _EdgeSide.north || g.side == _EdgeSide.south) {
      armRect = Rect.fromCenter(
        center: edgeCenter + outward * (outPx * 0.55),
        width: armLen,
        height: armTh,
      );
    } else {
      armRect = Rect.fromCenter(
        center: edgeCenter + outward * (outPx * 0.55),
        width: armTh,
        height: armLen,
      );
    }

    final armBase = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.surface.withOpacity(0.96);

    final armBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, armTh * 0.12)
      ..color = accent.withOpacity(0.95);

    canvas.drawRRect(
      RRect.fromRectAndRadius(armRect, Radius.circular(armTh * 0.45)),
      armBase,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(armRect, Radius.circular(armTh * 0.45)),
      armBorder,
    );

    final stripe = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, armTh * 0.14)
      ..color = accent.withOpacity(0.90);

    const stripeCount = 4;
    for (int i = 0; i < stripeCount; i++) {
      final t = (i + 1) / (stripeCount + 1);
      if (g.side == _EdgeSide.north || g.side == _EdgeSide.south) {
        final x = armRect.left + armRect.width * t;
        canvas.drawLine(
          Offset(x - armTh * 0.35, armRect.top),
          Offset(x + armTh * 0.35, armRect.bottom),
          stripe,
        );
      } else {
        final y = armRect.top + armRect.height * t;
        canvas.drawLine(
          Offset(armRect.left, y - armTh * 0.35),
          Offset(armRect.right, y + armTh * 0.35),
          stripe,
        );
      }
    }

    final tp = TextPainter(
      text: TextSpan(
        text: _gateLabel(kind),
        style: TextStyle(
          fontSize: max(10.0, cell * 0.20),
          fontWeight: FontWeight.w900,
          color: accent.withOpacity(0.95),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, postRect.topLeft + const Offset(2, -16));
  }

  void _drawPillar2D(Canvas canvas, Rect rect) {
    final cs = colorScheme;
    final cell = layout.cell;

    final center = rect.center;
    final r = max(3.0, cell * 0.18);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.onSurface.withOpacity(0.20);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, cell * 0.035)
      ..color = cs.onSurface.withOpacity(0.55);

    canvas.drawCircle(center, r, fill);
    canvas.drawCircle(center, r, stroke);

    final hi = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.surface.withOpacity(0.75);

    canvas.drawCircle(center + Offset(-r * 0.25, -r * 0.25), r * 0.22, hi);
  }

  void _drawRoadMark2D(Canvas canvas, Rect rect) {
    final cs = colorScheme;
    final cell = layout.cell;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(1.2, cell * 0.04)
      ..color = cs.surface.withOpacity(0.70);

    final a = Offset(rect.center.dx, rect.top + rect.height * 0.18);
    final b = Offset(rect.center.dx, rect.bottom - rect.height * 0.18);

    final dash = max(4.0, cell * 0.12);
    final gap = max(3.0, cell * 0.08);

    double t = 0;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len <= 1e-6) return;
    final ux = dx / len;
    final uy = dy / len;

    while (t < len) {
      final t2 = min(len, t + dash);
      canvas.drawLine(
        Offset(a.dx + ux * t, a.dy + uy * t),
        Offset(a.dx + ux * t2, a.dy + uy * t2),
        paint,
      );
      t = t2 + gap;
    }

    
    final c = rect.center;
    final p2 = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(1.0, cell * 0.03)
      ..color = cs.surface.withOpacity(0.70);

    canvas.drawLine(
      Offset(rect.left + rect.width * 0.20, c.dy),
      Offset(rect.right - rect.width * 0.20, c.dy),
      p2,
    );
  }

  void _drawWall2D(Canvas canvas, _EdgePlacement w, {required bool selected}) {
    final cs = colorScheme;
    final cell = layout.cell;
    final rect = layout.cellRect(w.r, w.c);

    final th = max(3.0, cell * 0.12);
    final out = max(4.0, cell * 0.10);

    Offset a;
    Offset b;
    Offset outward;

    switch (w.side) {
      case _EdgeSide.north:
        a = Offset(rect.left, rect.top);
        b = Offset(rect.right, rect.top);
        outward = const Offset(0, -1);
        break;
      case _EdgeSide.south:
        a = Offset(rect.left, rect.bottom);
        b = Offset(rect.right, rect.bottom);
        outward = const Offset(0, 1);
        break;
      case _EdgeSide.west:
        a = Offset(rect.left, rect.top);
        b = Offset(rect.left, rect.bottom);
        outward = const Offset(-1, 0);
        break;
      case _EdgeSide.east:
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
      ..color = selected
          ? cs.primary.withOpacity(0.92)
          : cs.outlineVariant.withOpacity(0.65);

    canvas.drawLine(a, b, base);
    canvas.drawLine(a, b, hi);
  }

  void _drawWallName2D(Canvas canvas, _EdgePlacement w, String name) {
    final cs = colorScheme;
    final rect = layout.cellRect(w.r, w.c);
    final cell = layout.cell;

    Offset pos;
    switch (w.side) {
      case _EdgeSide.north:
        pos = Offset(rect.center.dx, rect.top - max(18.0, cell * 0.28));
        break;
      case _EdgeSide.south:
        pos = Offset(rect.center.dx, rect.bottom + max(6.0, cell * 0.12));
        break;
      case _EdgeSide.west:
        pos = Offset(rect.left - max(60.0, cell * 0.80), rect.center.dy - 8);
        break;
      case _EdgeSide.east:
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

  void _drawSpotMark2D(Canvas canvas, Rect spotRect, String mark, Color color) {
    final tp = TextPainter(
      text: TextSpan(
        text: mark,
        style: TextStyle(
          fontSize: max(12.0, layout.cell * 0.42),
          fontWeight: FontWeight.w900,
          color: color,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final center = spotRect.center;
    tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
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

    canvas.drawRRect(
      RRect.fromRectAndRadius(gridRect, const Radius.circular(10)),
      bg,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(gridRect, const Radius.circular(10)),
      border,
    );

    
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        if (idx < 0 || idx >= cells.length) continue;

        final rect = layout.cellRect(r, c).deflate(1.0);
        final st = cells[idx];

        final fill = Paint()
          ..style = PaintingStyle.fill
          ..color = colorResolver(cs, st);

        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(6)),
          fill,
        );

        if (st == ParkingCellState.pillar) {
          _drawPillar2D(canvas, rect);
        } else if (st == ParkingCellState.road) {
          _drawRoadMark2D(canvas, rect);
        } else if (st == ParkingCellState.occupied ||
            st == ParkingCellState.blocked) {
          
          final c0 = _spotRepCol(c);
          final repIdx = r * cols + c0;

          if (_isValidSpotPair(r, c0)) {
            if (idx == repIdx) {
              final rect0 = layout.cellRect(r, c0).deflate(1.0);
              final rect1 = layout.cellRect(r, c0 + 1).deflate(1.0);
              final spotRect = Rect.fromLTRB(
                min(rect0.left, rect1.left),
                min(rect0.top, rect1.top),
                max(rect0.right, rect1.right),
                max(rect0.bottom, rect1.bottom),
              );

              final mark = (st == ParkingCellState.occupied) ? 'P' : '×';
              final color = (st == ParkingCellState.occupied)
                  ? cs.onPrimaryContainer.withOpacity(0.92)
                  : cs.onErrorContainer.withOpacity(0.92);
              _drawSpotMark2D(canvas, spotRect, mark, color);
            }
          } else {
            
            final mark = (st == ParkingCellState.occupied) ? 'P' : '×';
            final tp = TextPainter(
              text: TextSpan(
                text: mark,
                style: TextStyle(
                  fontSize: layout.cell * 0.40,
                  fontWeight: FontWeight.w900,
                  color: st == ParkingCellState.occupied
                      ? cs.onPrimaryContainer.withOpacity(0.92)
                      : cs.onErrorContainer.withOpacity(0.92),
                ),
              ),
              textDirection: TextDirection.ltr,
            )..layout();
            tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
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
      canvas.drawLine(
        Offset(layout.origin.dx, y),
        Offset(layout.origin.dx + cols * layout.cell, y),
        gridLine,
      );
    }
    for (int c = 0; c <= cols; c++) {
      final x = layout.origin.dx + c * layout.cell;
      canvas.drawLine(
        Offset(x, layout.origin.dy),
        Offset(x, layout.origin.dy + rows * layout.cell),
        gridLine,
      );
    }

    
    for (final w in walls.keys) {
      _drawWall2D(canvas, w, selected: selectedWalls.contains(w));
    }

    
    final reps = <_WallGroupId, _EdgePlacement>{};
    for (final e in walls.entries) {
      final gid = e.value;
      if (gid == null) continue;

      final name = wallGroups[gid]?.trim();
      if (name == null || name.isEmpty) continue;

      if (!reps.containsKey(gid)) {
        reps[gid] = e.key;
      } else {
        final cur = reps[gid]!;
        final a = _edgeSortKey(e.key);
        final b = _edgeSortKey(cur);
        if (a < b) reps[gid] = e.key;
      }
    }
    for (final entry in reps.entries) {
      final name = wallGroups[entry.key]?.trim() ?? '';
      if (name.isNotEmpty) {
        _drawWallName2D(canvas, entry.value, name);
      }
    }

    
    final set = <_EdgePlacement>{};
    if (entranceGate != null) set.add(entranceGate!);
    if (exitGate != null) set.add(exitGate!);

    for (final g in set) {
      _drawBarrier2D(canvas, g, _gateKindFor(g));
    }

    
    final selSet = _selectedHighlightIndices();
    if (selSet.isNotEmpty) {
      final selList = selSet.toList()..sort();
      final halo = Paint()
        ..style = PaintingStyle.fill
        ..color = cs.primary.withOpacity(0.10);

      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(2.0, layout.cell * 0.06)
        ..color = cs.primary.withOpacity(0.92);

      if (selList.length == 2 &&
          selList[1] == selList[0] + 1 &&
          (selList[0] ~/ cols) == (selList[1] ~/ cols)) {
        final r0 = selList[0] ~/ cols;
        final c0 = selList[0] % cols;
        final rect0 = layout.cellRect(r0, c0).deflate(1.0);
        final rect1 = layout.cellRect(r0, c0 + 1).deflate(1.0);
        final spotRect = Rect.fromLTRB(
          min(rect0.left, rect1.left),
          min(rect0.top, rect1.top),
          max(rect0.right, rect1.right),
          max(rect0.bottom, rect1.bottom),
        );

        canvas.drawRRect(
          RRect.fromRectAndRadius(spotRect, const Radius.circular(8)),
          halo,
        );
        canvas.drawRRect(
          RRect.fromRectAndRadius(spotRect, const Radius.circular(8)),
          stroke,
        );
      } else {
        for (final idx in selList) {
          if (idx < 0 || idx >= cells.length) continue;
          final r = idx ~/ cols;
          final c = idx % cols;
          final rect = layout.cellRect(r, c).deflate(1.0);
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(6)),
            halo,
          );
          canvas.drawRRect(
            RRect.fromRectAndRadius(rect, const Radius.circular(6)),
            stroke,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Parking2DGridPainter oldDelegate) {
    return oldDelegate.rows != rows ||
        oldDelegate.cols != cols ||
        oldDelegate.layout.cell != layout.cell ||
        oldDelegate.layout.origin != layout.origin ||
        oldDelegate.cells != cells ||
        oldDelegate.selectedCellIndex != selectedCellIndex ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.entranceGate != entranceGate ||
        oldDelegate.exitGate != exitGate ||
        oldDelegate.walls != walls ||
        oldDelegate.wallGroups != wallGroups ||
        oldDelegate.selectedWalls != selectedWalls;
  }
}
