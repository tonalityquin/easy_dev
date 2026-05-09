import 'dart:math';
import 'package:flutter/material.dart';

import '../../../domain/models/grid_rect.dart';
import '../../../domain/models/parking_grid_model.dart';

class ParkingGridChildRectSelector extends StatefulWidget {
  final ParkingGridModel grid;
  final GridRect? value;
  final ValueChanged<GridRect?> onChanged;
  final Set<String> selectedParkingAreaIds;
  final Set<String> disabledParkingAreaIds;
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
  State<ParkingGridChildRectSelector> createState() => _ParkingGridChildRectSelectorState();
}

class _ParkingGridChildRectSelectorState extends State<ParkingGridChildRectSelector> {
  int? _anchorR;
  int? _anchorC;

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
    if (widget.disabledParkingAreaIds.contains(id)) return;
    final current = Set<String>.from(widget.selectedParkingAreaIds);
    if (current.contains(id)) {
      current.remove(id);
    } else {
      current.add(id);
    }
    widget.onChangedSelectedParkingAreaIds?.call(current);
  }

  (int r, int c)? _hitTestCell(Offset local, double cellSize) {
    if (cellSize <= 0) return null;
    final c = (local.dx / cellSize).floor();
    final r = (local.dy / cellSize).floor();
    if (r < 0 || c < 0 || r >= widget.grid.rows || c >= widget.grid.cols) return null;
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
          onDoubleTap: () {
            _clearAnchor();
            widget.onChanged(null);
          },
          onTapDown: (d) {
            final hit = _hitTestCell(d.localPosition, cellSize);
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
              final tr = _towerRectAtCell(hit.$1, hit.$2);
              if (tr == null) return;
              widget.onChanged(tr);
              return;
            }

            widget.onChanged(
              GridRect(r0: hit.$1, c0: hit.$2, r1: hit.$1, c1: hit.$2),
            );
          },
          onPanStart: (d) {
            final hit = _hitTestCell(d.localPosition, cellSize);
            if (hit == null) return;

            if (widget.parkingAreaPickMode && !widget.towerSelectMode) {
              return;
            }

            if (widget.towerSelectMode) {
              _clearAnchor();
              final tr = _towerRectAtCell(hit.$1, hit.$2);
              if (tr == null) return;
              widget.onChanged(tr);
              return;
            }

            _anchorR = hit.$1;
            _anchorC = hit.$2;
            widget.onChanged(
              GridRect(r0: hit.$1, c0: hit.$2, r1: hit.$1, c1: hit.$2),
            );
          },
          onPanUpdate: (d) {
            final hit = _hitTestCell(d.localPosition, cellSize);
            if (hit == null) return;

            if (widget.towerSelectMode) {
              final tr = _towerRectAtCell(hit.$1, hit.$2);
              if (tr == null) return;
              widget.onChanged(tr);
              return;
            }

            _updateByCell(hit.$1, hit.$2);
          },
          onPanEnd: (_) => _clearAnchor(),
          onPanCancel: _clearAnchor,
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
              parkingAreaPickMode: widget.parkingAreaPickMode,
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

    final areaCountHint = (widget.showParkingAreaCountHint && widget.showParkingAreas) ? _countParkingAreasInSelection() : 0;

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
  final bool parkingAreaPickMode;

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
    required this.parkingAreaPickMode,
  });

  static (int r, int c, int edge)? _parseEdgeKey(String key) {
    final parts = key.split('|');
    if (parts.length != 3) return null;
    final r = int.tryParse(parts[0]);
    final c = int.tryParse(parts[1]);
    final e = int.tryParse(parts[2]);
    if (r == null || c == null || e == null) return null;
    if (e < 0 || e > 3) return null;
    return (r, c, e);
  }

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
    final isSelectedArea = selectedParkingAreaIds.contains(a.id);
    final isDisabledArea = disabledParkingAreaIds.contains(a.id);
    final fillColor = isDisabledArea
        ? cs.surfaceVariant.withOpacity(0.28)
        : isSelectedArea
            ? style.fill
            : parkingAreaPickMode
                ? style.fill.withOpacity(0.18)
                : style.fill;
    final strokeColor = isDisabledArea
        ? cs.outline.withOpacity(0.45)
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
      ..strokeWidth = isSelectedArea ? max(1.8, cell * 0.10) : max(1.2, cell * 0.07)
      ..color = strokeColor;

    final rr = RRect.fromRectAndRadius(rect, Radius.circular(max(4.0, cell * 0.18)));
    canvas.drawRRect(rr, fill);
    canvas.drawRRect(rr, stroke);

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

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        final t = (idx >= 0 && idx < grid.cells.length) ? grid.cells[idx] : ParkingGridCellType.empty;

        final rect = Rect.fromLTWH(c * cell, r * cell, cell, cell);
        if (t == ParkingGridCellType.road) {
          canvas.drawRect(rect, pRoad);
        } else if (t == ParkingGridCellType.pillar) {
          canvas.drawRect(rect, pPillar);
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

      final left = c0 * cell;
      final top = r0 * cell;
      final width = (c1 - c0 + 1) * cell;
      final height = (r1 - r0 + 1) * cell;

      final fill = Paint()..color = cs.primary.withOpacity(0.18);
      final stroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(1.2, cell * 0.06)
        ..color = cs.primary.withOpacity(0.85);

      final rr = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, top, width, height),
        Radius.circular(max(4, cell * 0.12)),
      );

      canvas.drawRRect(rr, fill);
      canvas.drawRRect(rr, stroke);
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

    final wallPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(2.0, cell * 0.12)
      ..color = cs.secondary.withOpacity(0.80);

    for (final e in grid.walls.entries) {
      final key = e.key;
      final parsed = _parseEdgeKey(key);
      if (parsed == null) continue;
      final r = parsed.$1;
      final c = parsed.$2;
      final edge = parsed.$3;

      final onPerimeter = r == 0 || r == rows - 1 || c == 0 || c == cols - 1;
      if (!onPerimeter) continue;

      Offset a, b;
      final x = c * cell;
      final y = r * cell;

      switch (edge) {
        case 0:
          if (r != 0) continue;
          a = Offset(x, y);
          b = Offset(x + cell, y);
          break;
        case 1:
          if (c != cols - 1) continue;
          a = Offset(x + cell, y);
          b = Offset(x + cell, y + cell);
          break;
        case 2:
          if (r != rows - 1) continue;
          a = Offset(x, y + cell);
          b = Offset(x + cell, y + cell);
          break;
        case 3:
          if (c != 0) continue;
          a = Offset(x, y);
          b = Offset(x, y + cell);
          break;
        default:
          continue;
      }

      canvas.drawLine(a, b, wallPaint);
    }

    void drawGate(String? key, Paint paint) {
      final k = key?.trim();
      if (k == null || k.isEmpty) return;
      final parsed = _parseEdgeKey(k);
      if (parsed == null) return;
      final r = parsed.$1;
      final c = parsed.$2;
      final edge = parsed.$3;

      final x = c * cell;
      final y = r * cell;

      Offset a, b;
      switch (edge) {
        case 0:
          a = Offset(x, y);
          b = Offset(x + cell, y);
          break;
        case 1:
          a = Offset(x + cell, y);
          b = Offset(x + cell, y + cell);
          break;
        case 2:
          a = Offset(x, y + cell);
          b = Offset(x + cell, y + cell);
          break;
        case 3:
          a = Offset(x, y);
          b = Offset(x, y + cell);
          break;
        default:
          return;
      }
      canvas.drawLine(a, b, paint);
    }

    final entrancePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(3.0, cell * 0.16)
      ..color = cs.primary.withOpacity(0.88);

    final exitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(3.0, cell * 0.16)
      ..color = cs.error.withOpacity(0.88);

    drawGate(grid.entranceGateKey, entrancePaint);
    drawGate(grid.exitGateKey, exitPaint);

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
        oldDelegate.parkingAreaPickMode != parkingAreaPickMode;
  }
}
