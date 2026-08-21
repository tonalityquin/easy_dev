import 'dart:math';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../../app/utils/location_debug_status.dart';
import '../../../domain/models/grid_rect.dart';
import '../../../domain/models/parking_grid_model.dart';

class ParkingGridChildRectSelector extends StatefulWidget {
  final ParkingGridModel grid;
  final GridRect? value;
  final ValueChanged<GridRect?> onChanged;
  final Set<String> selectedParkingAreaIds;
  final Set<String> disabledParkingAreaIds;
  final Set<String> occupiedParkingAreaIds;
  final Set<String> reusableParkingAreaIds;
  final Set<String> excludedParkingAreaIds;
  final ValueChanged<Set<String>>? onChangedSelectedParkingAreaIds;
  final bool parkingAreaPickMode;

  final bool squareLock;
  final bool showHint;

  final bool showParkingAreas;
  final bool showParkingAreaCountHint;

  final bool showAxisIndex;
  final int axisIndexStep;
  final List<GridRect> towerRects;
  final bool towerSelectMode;

  const ParkingGridChildRectSelector({
    super.key,
    required this.grid,
    required this.value,
    required this.onChanged,
    this.selectedParkingAreaIds = const <String>{},
    this.disabledParkingAreaIds = const <String>{},
    this.occupiedParkingAreaIds = const <String>{},
    this.reusableParkingAreaIds = const <String>{},
    this.excludedParkingAreaIds = const <String>{},
    this.onChangedSelectedParkingAreaIds,
    this.parkingAreaPickMode = false,
    required this.squareLock,
    this.showHint = true,
    this.showParkingAreas = true,
    this.showParkingAreaCountHint = true,
    this.showAxisIndex = true,
    this.axisIndexStep = 5,
    this.towerRects = const <GridRect>[],
    this.towerSelectMode = false,
  });

  @override
  State<ParkingGridChildRectSelector> createState() =>
      _ParkingGridChildRectSelectorState();
}

class _ParkingGridChildRectSelectorState
    extends State<ParkingGridChildRectSelector> {
  int? _anchorR;
  int? _anchorC;
  GridRect? _valueBeforeDrag;
  bool _dragSelectionActive = false;

  void _reportGestureFailure(
    String operation,
    Object error,
    StackTrace stackTrace, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    LocationDebugStatus.report(
      context: context,
      title: '자식 영역 제스처 처리 실패',
      operation: 'ParkingGridChildRectSelector.$operation',
      error: error,
      stackTrace: stackTrace,
      details: <String, Object?>{
        'anchorR': _anchorR,
        'anchorC': _anchorC,
        'dragSelectionActive': _dragSelectionActive,
        'rows': widget.grid.rows,
        'cols': widget.grid.cols,
        ...details,
      },
    );
  }

  void _runGesture(
    String operation,
    VoidCallback action, {
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    try {
      action();
    } catch (error, stackTrace) {
      _reportGestureFailure(
        operation,
        error,
        stackTrace,
        details: details,
      );
    }
  }

  void _completeDragSelection() {
    _clearAnchor();
    _dragSelectionActive = false;
    _valueBeforeDrag = null;
  }

  void _cancelDragSelection() {
    final previous = _valueBeforeDrag;
    final restore = _dragSelectionActive;
    _clearAnchor();
    _dragSelectionActive = false;
    _valueBeforeDrag = null;
    if (restore) {
      widget.onChanged(previous);
    }
  }

  void _clearAnchor() {
    _anchorR = null;
    _anchorC = null;
  }

  GridRect? _towerRectAtCell(int r, int c) {
    if (widget.towerRects.isEmpty) return null;
    for (final raw in widget.towerRects) {
      final tr = raw.normalized();
      if (r >= tr.r0 && r <= tr.r1 && c >= tr.c0 && c <= tr.c1) {
        return tr;
      }
    }
    return null;
  }

  ParkingArea? _parkingAreaAtCell(int r, int c) {
    for (final a in widget.grid.parkingAreas) {
      final top = a.r0;
      final left = a.c0;
      final bottom = a.r0 + a.kind.h - 1;
      final right = a.c0 + a.kind.w - 1;
      if (r >= top && r <= bottom && c >= left && c <= right) {
        return a;
      }
    }
    return null;
  }

  void _toggleParkingArea(ParkingArea area) {
    final id = area.id.trim();
    if (id.isEmpty) return;
    if (widget.disabledParkingAreaIds.contains(id) ||
        widget.occupiedParkingAreaIds.contains(id)) return;
    final current = Set<String>.from(widget.selectedParkingAreaIds);
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }
    widget.onChangedSelectedParkingAreaIds?.call(current);
  }

  (int r, int c)? _hitTestCell(
    Offset local,
    double cellSize, {
    bool clampToBounds = false,
  }) {
    if (cellSize <= 0) return null;

    var dx = local.dx;
    var dy = local.dy;

    if (clampToBounds) {
      final maxDx = max(0.0, widget.grid.cols * cellSize - 0.001);
      final maxDy = max(0.0, widget.grid.rows * cellSize - 0.001);
      dx = dx.clamp(0.0, maxDx).toDouble();
      dy = dy.clamp(0.0, maxDy).toDouble();
    }

    final c = (dx / cellSize).floor();
    final r = (dy / cellSize).floor();
    if (r < 0 || c < 0 || r >= widget.grid.rows || c >= widget.grid.cols) {
      return null;
    }
    return (r, c);
  }

  GridRect _buildRectFromAnchor(int ar, int ac, int br, int bc) {
    if (!widget.squareLock) {
      return GridRect(r0: ar, c0: ac, r1: br, c1: bc).normalized();
    }

    final dr = br - ar;
    final dc = bc - ac;

    final dirR = (dr >= 0) ? 1 : -1;
    final dirC = (dc >= 0) ? 1 : -1;

    final desired = max(dr.abs(), dc.abs());

    final maxSideR = (dirR > 0) ? (widget.grid.rows - 1 - ar) : ar;
    final maxSideC = (dirC > 0) ? (widget.grid.cols - 1 - ac) : ac;

    final side = min(desired, min(maxSideR, maxSideC));

    final rr = ar + dirR * side;
    final cc = ac + dirC * side;

    return GridRect(r0: ar, c0: ac, r1: rr, c1: cc).normalized();
  }

  void _updateByCell(int r, int c) {
    final ar = _anchorR;
    final ac = _anchorC;
    if (ar == null || ac == null) return;

    final rect = _buildRectFromAnchor(ar, ac, r, c);
    widget.onChanged(rect);
  }

  bool _areaContainedInRect(ParkingArea a, GridRect rect) {
    final rr = rect.normalized();

    final top = min(a.r0, a.r1);
    final bottom = max(a.r0, a.r1);
    final left = min(a.c0, a.c1);
    final right = max(a.c0, a.c1);

    return top >= rr.r0 && bottom <= rr.r1 && left >= rr.c0 && right <= rr.c1;
  }

  int _countParkingAreasInSelection() {
    final sel = widget.value?.normalized();
    if (sel == null) return 0;

    final areas = widget.grid.parkingAreas;
    if (areas.isEmpty) return 0;

    int count = 0;
    for (final a in areas) {
      if (_areaContainedInRect(a, sel)) count++;
    }
    return count;
  }

  Widget _buildHint(ColorScheme cs, int areaCountHint) {
    const hintGap = 8.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.towerSelectMode
              ? '타워 선택 모드: 타워 영역을 탭해서 선택하세요. (더블탭=선택 해제)'
              : (widget.squareLock
              ? '정사각형 모드: 드래그로 정사각형 영역을 선택하세요. (탭=1칸)'
              : '직사각형 모드: 드래그로 영역을 선택하세요. (탭=1칸)'),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: cs.onSurfaceVariant.withOpacity(.85),
          ),
        ),
        if (widget.showParkingAreas && widget.showParkingAreaCountHint) ...[
          const SizedBox(height: 4),
          Text(
            '선택 영역 내 주차면적(완전 포함): $areaCountHint',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant.withOpacity(.90),
            ),
          ),
        ],
        const SizedBox(height: hintGap),
      ],
    );
  }

  Widget _buildGridViewport({
    required ColorScheme cs,
    required ParkingGridModel grid,
    required double availableW,
    required double availableH,
  }) {
    final cols = max(1, grid.cols);
    final rows = max(1, grid.rows);
    final rawCell = min(
      availableW / cols,
      availableH / rows,
    );
    final cellSize = min(rawCell, 90.0);

    if (cellSize <= 0 || cellSize.isNaN || cellSize.isInfinite) {
      return const SizedBox.shrink();
    }

    final gridW = cellSize * cols;
    final gridH = cellSize * rows;

    return Center(
      child: SizedBox(
        width: gridW,
        height: gridH,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          dragStartBehavior: DragStartBehavior.down,
          onDoubleTap: widget.parkingAreaPickMode
              ? null
              : () {
                  _clearAnchor();
                  widget.onChanged(null);
                },
          onTapUp: (details) => _runGesture(
            'onTapUp',
            () {
              final hit = _hitTestCell(details.localPosition, cellSize);
              if (hit == null) return;

              _clearAnchor();

              if (widget.parkingAreaPickMode && !widget.towerSelectMode) {
                final area = _parkingAreaAtCell(hit.$1, hit.$2);
                if (area != null) {
                  _toggleParkingArea(area);
                }
                return;
              }

              if (widget.towerSelectMode) {
                final tower = _towerRectAtCell(hit.$1, hit.$2);
                if (tower == null) return;
                widget.onChanged(tower);
                return;
              }

              widget.onChanged(
                GridRect(
                  r0: hit.$1,
                  c0: hit.$2,
                  r1: hit.$1,
                  c1: hit.$2,
                ),
              );
            },
            details: <String, Object?>{
              'dx': details.localPosition.dx,
              'dy': details.localPosition.dy,
            },
          ),
          onPanStart: (details) => _runGesture(
            'onPanStart',
            () {
              final hit = _hitTestCell(
                details.localPosition,
                cellSize,
                clampToBounds: true,
              );
              if (hit == null) return;

              if (widget.parkingAreaPickMode && !widget.towerSelectMode) {
                return;
              }

              _valueBeforeDrag = widget.value?.normalized();
              _dragSelectionActive = true;

              if (widget.towerSelectMode) {
                _clearAnchor();
                final tower = _towerRectAtCell(hit.$1, hit.$2);
                if (tower == null) {
                  _completeDragSelection();
                  return;
                }
                widget.onChanged(tower);
                return;
              }

              _anchorR = hit.$1;
              _anchorC = hit.$2;
              widget.onChanged(
                GridRect(
                  r0: hit.$1,
                  c0: hit.$2,
                  r1: hit.$1,
                  c1: hit.$2,
                ),
              );
            },
            details: <String, Object?>{
              'dx': details.localPosition.dx,
              'dy': details.localPosition.dy,
            },
          ),
          onPanUpdate: (details) => _runGesture(
            'onPanUpdate',
            () {
              if (!_dragSelectionActive) return;
              final hit = _hitTestCell(
                details.localPosition,
                cellSize,
                clampToBounds: true,
              );
              if (hit == null) return;

              if (widget.towerSelectMode) {
                final tower = _towerRectAtCell(hit.$1, hit.$2);
                if (tower == null) return;
                widget.onChanged(tower);
                return;
              }

              _updateByCell(hit.$1, hit.$2);
            },
            details: <String, Object?>{
              'dx': details.localPosition.dx,
              'dy': details.localPosition.dy,
            },
          ),
          onPanEnd: (_) => _runGesture(
            'onPanEnd',
            _completeDragSelection,
          ),
          onPanCancel: () => _runGesture(
            'onPanCancel',
            _cancelDragSelection,
          ),
          child: CustomPaint(
            painter: _ParkingGridChildRectPainter(
              grid: grid,
              selection: widget.value,
              colorScheme: cs,
              showParkingAreas: widget.showParkingAreas,
              showAxisIndex: widget.showAxisIndex,
              axisIndexStep: widget.axisIndexStep,
              towerRects: widget.towerRects,
              selectedParkingAreaIds: widget.selectedParkingAreaIds,
              disabledParkingAreaIds: widget.disabledParkingAreaIds,
              occupiedParkingAreaIds: widget.occupiedParkingAreaIds,
              reusableParkingAreaIds: widget.reusableParkingAreaIds,
              excludedParkingAreaIds: widget.excludedParkingAreaIds,
              parkingAreaPickMode: widget.parkingAreaPickMode,
              towerSelectMode: widget.towerSelectMode,
            ),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final grid = widget.grid;

    final areaCountHint =
        widget.showParkingAreaCountHint && widget.showParkingAreas
            ? _countParkingAreasInSelection()
            : 0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = max(0.0, constraints.maxWidth);
        final hasBoundedH = constraints.hasBoundedHeight;

        if (!hasBoundedH) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.showHint) _buildHint(cs, areaCountHint),
              _buildGridViewport(
                cs: cs,
                grid: grid,
                availableW: maxW,
                availableH: maxW,
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: [
            if (widget.showHint) _buildHint(cs, areaCountHint),
            Expanded(
              child: LayoutBuilder(
                builder: (context, gridConstraints) {
                  final availW = max(0.0, gridConstraints.maxWidth);
                  final availH = max(0.0, gridConstraints.maxHeight);

                  return _buildGridViewport(
                    cs: cs,
                    grid: grid,
                    availableW: availW,
                    availableH: availH,
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ParkingGridChildRectPainter extends CustomPainter {
  final ParkingGridModel grid;
  final GridRect? selection;
  final ColorScheme colorScheme;

  final bool showParkingAreas;
  final bool showAxisIndex;
  final int axisIndexStep;

  
  final List<GridRect> towerRects;
  final Set<String> selectedParkingAreaIds;
  final Set<String> disabledParkingAreaIds;
  final Set<String> occupiedParkingAreaIds;
  final Set<String> reusableParkingAreaIds;
  final Set<String> excludedParkingAreaIds;
  final bool parkingAreaPickMode;
  final bool towerSelectMode;

  _ParkingGridChildRectPainter({
    required this.grid,
    required this.selection,
    required this.colorScheme,
    required this.showParkingAreas,
    required this.showAxisIndex,
    required this.axisIndexStep,
    required this.towerRects,
    required this.selectedParkingAreaIds,
    required this.disabledParkingAreaIds,
    required this.occupiedParkingAreaIds,
    required this.reusableParkingAreaIds,
    required this.excludedParkingAreaIds,
    required this.parkingAreaPickMode,
    required this.towerSelectMode,
  });

  void _drawPillarMarker(Canvas canvas, Rect rect, double cell, ColorScheme cs) {
    final center = rect.center;
    final rr = max(3.0, cell * 0.18);

    final pFill = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.onSurface.withOpacity(0.20);

    final pStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.2, cell * 0.035)
      ..color = cs.onSurface.withOpacity(0.55);

    canvas.drawCircle(center, rr, pFill);
    canvas.drawCircle(center, rr, pStroke);
  }

  void _drawParkingArea(Canvas canvas, ParkingArea a, double cell, ColorScheme cs, {required bool drawLabel}) {
    final h = a.kind.h;
    final w = a.kind.w;
    final top = a.r0;
    final left = a.c0;
    final bottom = a.r0 + h - 1;
    final right = a.c0 + w - 1;

    final rect = Rect.fromLTWH(
      left * cell,
      top * cell,
      (right - left + 1) * cell,
      (bottom - top + 1) * cell,
    ).deflate(max(1.0, cell * 0.10));

    final style = _parkingAreaStyle(a.kind, cs);
    final id = a.id.trim();
    final isSelectedArea = selectedParkingAreaIds.contains(id);
    final isOccupiedArea = occupiedParkingAreaIds.contains(id) ||
        disabledParkingAreaIds.contains(id);
    final isReusableArea = reusableParkingAreaIds.contains(id);
    final isExcludedArea = excludedParkingAreaIds.contains(id);
    final fillColor = isOccupiedArea
        ? cs.surfaceVariant.withOpacity(0.28)
        : isExcludedArea
            ? cs.errorContainer.withOpacity(0.26)
            : isSelectedArea
                ? style.fill
                : isReusableArea
                    ? cs.tertiaryContainer.withOpacity(0.30)
                    : parkingAreaPickMode
                        ? style.fill.withOpacity(0.18)
                        : style.fill;
    final strokeColor = isOccupiedArea
        ? cs.outline.withOpacity(0.52)
        : isExcludedArea
            ? cs.error.withOpacity(0.88)
            : isReusableArea
                ? cs.tertiary.withOpacity(0.92)
                : isSelectedArea
                    ? style.stroke
                    : parkingAreaPickMode
                        ? style.stroke.withOpacity(0.34)
                        : style.stroke;

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSelectedArea || isReusableArea || isExcludedArea
          ? max(1.8, cell * 0.10)
          : max(1.2, cell * 0.07)
      ..color = strokeColor;

    final rr = RRect.fromRectAndRadius(rect, Radius.circular(max(4.0, cell * 0.18)));
    canvas.drawRRect(rr, fill);
    canvas.drawRRect(rr, stroke);

    if (isOccupiedArea || isExcludedArea) {
      final cross = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeWidth = max(1.4, cell * 0.065)
        ..color = (isOccupiedArea ? cs.outline : cs.error).withOpacity(0.74);
      final inset = max(3.0, cell * 0.15);
      canvas.drawLine(
        Offset(rect.left + inset, rect.top + inset),
        Offset(rect.right - inset, rect.bottom - inset),
        cross,
      );
      canvas.drawLine(
        Offset(rect.right - inset, rect.top + inset),
        Offset(rect.left + inset, rect.bottom - inset),
        cross,
      );
    }

    if (!drawLabel) return;
    if (rect.width < 18 || rect.height < 14) return;

    final label = _parkingAreaHintLabel(a.kind);
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: TextStyle(
          fontSize: max(8.0, min(cell * 0.30, 12.0)),
          fontWeight: FontWeight.w900,
          color: style.text.withOpacity(0.95),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: max(0.0, rect.width - 4));

    tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
  }

  ({Color fill, Color stroke, Color text}) _parkingAreaStyle(ParkingAreaKind kind, ColorScheme cs) {
    switch (kind.categoryKey) {
      case 'compact':
        return (
          fill: const Color(0xFF64B5F6).withOpacity(0.58),
          stroke: const Color(0xFF1565C0).withOpacity(0.92),
          text: const Color(0xFF0D47A1),
        );
      case 'standard':
        return (
          fill: cs.secondaryContainer.withOpacity(0.52),
          stroke: cs.secondary.withOpacity(0.92),
          text: cs.onSecondaryContainer,
        );
      case 'extendedA':
      case 'extendedB':
        return (
          fill: const Color(0xFFFFD54F).withOpacity(0.62),
          stroke: const Color(0xFFF9A825).withOpacity(0.92),
          text: const Color(0xFF5D4037),
        );
      case 'evCompact':
      case 'evStandard':
      case 'evExtendedA':
      case 'evExtendedB':
        return (
          fill: const Color(0xFFA5D6A7).withOpacity(0.62),
          stroke: const Color(0xFF2E7D32).withOpacity(0.92),
          text: const Color(0xFF1B5E20),
        );
      case 'pregnantExtendedA':
      case 'pregnantExtendedB':
        return (
          fill: const Color(0xFFF8BBD0).withOpacity(0.62),
          stroke: const Color(0xFFC2185B).withOpacity(0.92),
          text: const Color(0xFF880E4F),
        );
      case 'disabledStandard':
      case 'disabledExtendedA':
      case 'disabledExtendedB':
        return (
          fill: const Color(0xFFB39DDB).withOpacity(0.62),
          stroke: const Color(0xFF512DA8).withOpacity(0.92),
          text: const Color(0xFF311B92),
        );
      default:
        return (
          fill: cs.secondaryContainer.withOpacity(0.45),
          stroke: cs.secondary.withOpacity(0.90),
          text: cs.onSecondaryContainer,
        );
    }
  }

  String _parkingAreaHintLabel(ParkingAreaKind kind) => kind.shortLabel;

  void _drawAxisIndex(Canvas canvas, Size size, double cell, ColorScheme cs, {required int rows, required int cols}) {
    if (!showAxisIndex) return;
    final step = max(1, axisIndexStep);

    final fontSize = max(9.0, min(14.0, cell * 0.28));
    final style = TextStyle(
      color: cs.onSurfaceVariant.withOpacity(0.85),
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
    );

    final pad = max(2.0, cell * 0.06);

    for (int c = 0; c < cols; c += step) {
      final tp = TextPainter(
        text: TextSpan(text: '$c', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final x = c * cell + (cell - tp.width) / 2;
      final maxX = max(0.0, size.width - tp.width);
      tp.paint(canvas, Offset(x.clamp(0.0, maxX), pad));
    }

    for (int r = 0; r < rows; r += step) {
      final tp = TextPainter(
        text: TextSpan(text: '$r', style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      final y = r * cell + (cell - tp.height) / 2;
      final maxY = max(0.0, size.height - tp.height);
      tp.paint(canvas, Offset(pad, y.clamp(0.0, maxY)));
    }
  }

  bool _parkingAreaContainedInSelection(ParkingArea area, GridRect selection) {
    final rect = selection.normalized();
    return area.r0 >= rect.r0 &&
        area.r1 <= rect.r1 &&
        area.c0 >= rect.c0 &&
        area.c1 <= rect.c1;
  }

  Path _selectionShapePath(
    GridRect selection,
    double cell,
    RRect rawRegion,
  ) {
    var path = Path()..addRRect(rawRegion);
    if (towerSelectMode) return path;
    for (final area in grid.parkingAreas) {
      final id = area.id.trim();
      if (id.isEmpty ||
          selectedParkingAreaIds.contains(id) ||
          !_parkingAreaContainedInSelection(area, selection)) {
        continue;
      }
      final cutRect = Rect.fromLTWH(
        area.c0 * cell,
        area.r0 * cell,
        (area.c1 - area.c0 + 1) * cell,
        (area.r1 - area.r0 + 1) * cell,
      ).inflate(max(.5, cell * .025));
      final cutPath = Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            cutRect,
            Radius.circular(max(3.0, cell * .12)),
          ),
        );
      path = Path.combine(PathOperation.difference, path, cutPath);
    }
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cs = colorScheme;

    final rows = max(1, grid.rows);
    final cols = max(1, grid.cols);

    final cell = size.width / cols;

    final bg = Paint()..color = cs.surfaceVariant.withOpacity(.25);
    canvas.drawRect(Offset.zero & size, bg);

    final pEmpty = Paint()..color = cs.surface.withOpacity(0.98);
    final pRoad = Paint()..color = cs.primaryContainer.withOpacity(0.55);
    final pPillar = Paint()..color = cs.tertiaryContainer.withOpacity(0.75);
    final pWall = Paint()..color = cs.onSurface.withOpacity(0.72);

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final t = (idx >= 0 && idx < grid.cells.length) ? grid.cells[idx] : ParkingGridCellType.empty;

        final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
        if (t == ParkingGridCellType.road) {
          canvas.drawRect(rect, pRoad);
        } else if (t == ParkingGridCellType.pillar) {
          canvas.drawRect(rect, pPillar);
        } else if (t == ParkingGridCellType.wall) {
          canvas.drawRect(rect, pWall);
        } else {
          canvas.drawRect(rect, pEmpty);
        }
      }
    }

    if (showParkingAreas && grid.parkingAreas.isNotEmpty) {
      for (final a in grid.parkingAreas) {
        _drawParkingArea(canvas, a, cell, cs, drawLabel: false);
      }
    }

    if (towerRects.isNotEmpty) {
      final fill = Paint()
        ..style = PaintingStyle.fill
        ..color = cs.tertiaryContainer.withOpacity(0.45);

      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.2, cell * 0.08)
        ..color = cs.tertiary.withOpacity(0.90);

      for (final raw in towerRects) {
        final t = raw.normalized();

        final r0 = t.r0.clamp(0, rows - 1);
        final r1 = t.r1.clamp(0, rows - 1);
        final c0 = t.c0.clamp(0, cols - 1);
        final c1 = t.c1.clamp(0, cols - 1);

        final rect = Rect.fromLTWH(
          c0 * cell,
          r0 * cell,
          (c1 - c0 + 1) * cell,
          (r1 - r0 + 1) * cell,
        ).deflate(max(1.0, cell * 0.10));

        final rr = RRect.fromRectAndRadius(rect, Radius.circular(max(5.0, cell * 0.22)));
        canvas.drawRRect(rr, fill);
        canvas.drawRRect(rr, stroke);

        if (rect.width > 18 && rect.height > 18) {
          final tp = TextPainter(
            text: TextSpan(
              text: 'T',
              style: TextStyle(
                fontSize: max(11.0, min(cell * 0.62, 20.0)),
                fontWeight: FontWeight.w900,
                color: cs.onTertiaryContainer.withOpacity(0.85),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
        }
      }
    }


    final sel = selection?.normalized();
    if (sel != null) {
      final r0 = sel.r0.clamp(0, rows - 1);
      final r1 = sel.r1.clamp(0, rows - 1);
      final c0 = sel.c0.clamp(0, cols - 1);
      final c1 = sel.c1.clamp(0, cols - 1);
      final rect = Rect.fromLTWH(
        c0 * cell,
        r0 * cell,
        (c1 - c0 + 1) * cell,
        (r1 - r0 + 1) * cell,
      );
      final rawRegion = RRect.fromRectAndRadius(
        rect,
        Radius.circular(max(4.0, cell * 0.12)),
      );
      final shape = _selectionShapePath(sel, cell, rawRegion);
      if (!towerSelectMode) {
        canvas.drawRRect(
          rawRegion,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = max(1.0, cell * .04)
            ..color = cs.primary.withOpacity(.34),
        );
      }
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.fill
          ..color = cs.primary.withOpacity(0.18),
      );
      canvas.drawPath(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeWidth = max(1.2, cell * 0.06)
          ..color = cs.primary.withOpacity(0.85),
      );
    }

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = cs.outlineVariant.withOpacity(0.8);

    for (int r = 0; r <= rows; r++) {
      final y = r * cell;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    for (int c = 0; c <= cols; c++) {
      final x = c * cell;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        if (idx < 0 || idx >= grid.cells.length) continue;

        final t = grid.cells[idx];
        if (t != ParkingGridCellType.pillar) continue;

        final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell).deflate(max(0.8, cell * 0.06));
        _drawPillarMarker(canvas, rect, cell, cs);
      }
    }

    if (showParkingAreas && grid.parkingAreas.isNotEmpty) {
      for (final a in grid.parkingAreas) {
        _drawParkingArea(canvas, a, cell, cs, drawLabel: true);
      }
    }

    final frame = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = max(1.4, cell * 0.08)
      ..color = cs.outline.withOpacity(0.55);
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), frame);

    _drawAxisIndex(canvas, size, cell, cs, rows: rows, cols: cols);
  }

  @override
  bool shouldRepaint(covariant _ParkingGridChildRectPainter oldDelegate) {
    return oldDelegate.grid != grid ||
        oldDelegate.selection != selection ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.showParkingAreas != showParkingAreas ||
        oldDelegate.showAxisIndex != showAxisIndex ||
        oldDelegate.axisIndexStep != axisIndexStep ||
        oldDelegate.towerRects != towerRects ||
        oldDelegate.selectedParkingAreaIds != selectedParkingAreaIds ||
        oldDelegate.disabledParkingAreaIds != disabledParkingAreaIds ||
        oldDelegate.occupiedParkingAreaIds != occupiedParkingAreaIds ||
        oldDelegate.reusableParkingAreaIds != reusableParkingAreaIds ||
        oldDelegate.excludedParkingAreaIds != excludedParkingAreaIds ||
        oldDelegate.parkingAreaPickMode != parkingAreaPickMode ||
        oldDelegate.towerSelectMode != towerSelectMode;
  }
}
