import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../domain/models/grid_rect.dart';
import '../../../domain/models/location_model.dart';
import '../../../domain/models/parking_grid_model.dart';

class ChildRegionOverlay {
  final GridRect rect;
  final String label;
  final bool isSelected;

  const ChildRegionOverlay({
    required this.rect,
    required this.label,
    required this.isSelected,
  });
}

class ParkingGridPreview extends StatelessWidget {
  final ParkingGridModel grid;
  final double maxExtent;

  final bool showLegend;
  final bool showWalls;
  final bool showGates;
  final bool showTowers;
  final bool showWallNames;

  final bool showParkingAreas;
  final bool showParkingAreaLabels;

  final bool showChildRegions;
  final bool showChildRegionLabels;
  final bool showAllChildRegionLabels;
  final List<ChildRegionOverlay> childRegions;

  final bool showChildSlotNumbers;
  final List<ChildSlot> childSlotsToLabel;

  const ParkingGridPreview({
    super.key,
    required this.grid,
    this.maxExtent = 280,
    this.showLegend = true,
    this.showWalls = true,
    this.showGates = true,
    this.showTowers = true,
    this.showWallNames = true,
    this.showParkingAreas = true,
    this.showParkingAreaLabels = true,
    this.showChildRegions = true,
    this.showChildRegionLabels = true,
    this.showAllChildRegionLabels = false,
    this.childRegions = const <ChildRegionOverlay>[],
    this.showChildSlotNumbers = true,
    this.childSlotsToLabel = const <ChildSlot>[],
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    Color road1Color() => cs.surfaceVariant.withOpacity(0.95);
    Color road2Color() => cs.tertiaryContainer.withOpacity(0.70);

    Color cellColor(ParkingGridCellType t) {
      switch (t) {
        case ParkingGridCellType.road:
          return road1Color();
        case ParkingGridCellType.pillar:
          return cs.errorContainer.withOpacity(0.75);
        case ParkingGridCellType.empty:
          return cs.primaryContainer.withOpacity(0.55);
      }
    }

    Widget legendDot(Color c, String label) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: c,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(color: cs.outlineVariant.withOpacity(0.65)),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: cs.onSurfaceVariant.withOpacity(0.85),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      );
    }

    Widget pill(String text) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: cs.surfaceVariant.withOpacity(.55),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: cs.outlineVariant.withOpacity(.85)),
        ),
        child: Text(
          text,
          style: TextStyle(
            fontSize: 11.5,
            color: cs.onSurfaceVariant,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }

    final ratio = (grid.rows > 0) ? (grid.cols / grid.rows) : 1.0;

    final wallCount = grid.walls.length;
    final groupCount = grid.wallGroups.length;

    final rectGateCount = grid.entranceRects.length + grid.exitRects.length;
    final towerCount = grid.towerRects.length;
    final legacyGateCount =
        (grid.entranceGate != null ? 1 : 0) + (grid.exitGate != null ? 1 : 0);
    final gateCount = rectGateCount > 0 ? rectGateCount : legacyGateCount;

    final parkingAreaCount = grid.parkingAreas.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: maxExtent,
            maxHeight: maxExtent,
          ),
          child: AspectRatio(
            aspectRatio: ratio.isFinite && ratio > 0 ? ratio : 1.0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: CustomPaint(
                painter: _ParkingGridPainter(
                  grid: grid,
                  colorScheme: cs,
                  showWalls: showWalls,
                  showGates: showGates,
                  showTowers: showTowers,
                  showWallNames: showWallNames,
                  showParkingAreas: showParkingAreas,
                  showParkingAreaLabels: showParkingAreaLabels,
                  showChildRegions: showChildRegions,
                  childRegions: childRegions,
                  showChildRegionLabels: showChildRegionLabels,
                  showAllChildRegionLabels: showAllChildRegionLabels,
                  showChildSlotNumbers: showChildSlotNumbers,
                  childSlotsToLabel: childSlotsToLabel,
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
        ),
        if (showLegend) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              legendDot(cellColor(ParkingGridCellType.empty), '빈칸'),
              legendDot(road1Color(), '도로1'),
              legendDot(road2Color(), '도로2'),
              legendDot(cellColor(ParkingGridCellType.pillar), '기둥'),
              pill('${grid.rows}×${grid.cols}'),
              if (showParkingAreas && parkingAreaCount > 0)
                pill('주차면적 $parkingAreaCount'),
              if (showWalls && wallCount > 0) pill('벽 $wallCount'),
              if (showGates && gateCount > 0) pill('게이트 $gateCount'),
              if (showTowers && towerCount > 0) pill('주차 타워 $towerCount'),
              if (showWalls && groupCount > 0) pill('그룹 $groupCount'),
              if (showChildRegions && childRegions.isNotEmpty)
                pill('자식영역 ${childRegions.length}'),
              if (showChildSlotNumbers && childSlotsToLabel.isNotEmpty)
                pill('슬롯번호 ${childSlotsToLabel.length}'),
            ],
          ),
        ],
      ],
    );
  }
}

@immutable
class _GridLayout {
  final int rows;
  final int cols;
  final double gap;
  final double cell;
  final Offset origin;

  const _GridLayout({
    required this.rows,
    required this.cols,
    required this.gap,
    required this.cell,
    required this.origin,
  });

  factory _GridLayout.fit({
    required Size size,
    required int rows,
    required int cols,
    double padding = 10,
    double gap = 2,
  }) {
    final usableW = math.max(40.0, size.width - 2 * padding);
    final usableH = math.max(40.0, size.height - 2 * padding);

    final cellW = (usableW - gap * (cols - 1)) / cols;
    final cellH = (usableH - gap * (rows - 1)) / rows;
    final cell = math.min(cellW, cellH).clamp(6.0, 120.0);

    final gridW = cell * cols + gap * (cols - 1);
    final gridH = cell * rows + gap * (rows - 1);

    final ox = (size.width - gridW) / 2;
    final oy = (size.height - gridH) / 2;

    return _GridLayout(
      rows: rows,
      cols: cols,
      gap: gap,
      cell: cell,
      origin: Offset(ox, oy),
    );
  }

  Rect cellRect(int r, int c) {
    final dx = origin.dx + c * (cell + gap);
    final dy = origin.dy + r * (cell + gap);
    return Rect.fromLTWH(dx, dy, cell, cell);
  }

  Rect gridRect() {
    final w = cell * cols + gap * (cols - 1);
    final h = cell * rows + gap * (rows - 1);
    return Rect.fromLTWH(origin.dx, origin.dy, w, h);
  }

  Rect rectForCellRange({
    required int r0,
    required int r1,
    required int c0,
    required int c1,
  }) {
    final rr0 = math.min(r0, r1);
    final rr1 = math.max(r0, r1);
    final cc0 = math.min(c0, c1);
    final cc1 = math.max(c0, c1);

    final left = origin.dx + cc0 * (cell + gap);
    final top = origin.dy + rr0 * (cell + gap);

    final spanCols = (cc1 - cc0 + 1);
    final spanRows = (rr1 - rr0 + 1);

    final width = spanCols * cell + (spanCols - 1) * gap;
    final height = spanRows * cell + (spanRows - 1) * gap;

    return Rect.fromLTWH(left, top, width, height);
  }
}

enum _LegacyGateKind { entrance, exit, mixed }

class _ParkingGridPainter extends CustomPainter {
  final ParkingGridModel grid;
  final ColorScheme colorScheme;
  final bool showWalls;
  final bool showGates;
  final bool showTowers;
  final bool showWallNames;
  final bool showParkingAreas;
  final bool showParkingAreaLabels;

  final bool showChildRegions;
  final List<ChildRegionOverlay> childRegions;
  final bool showChildRegionLabels;
  final bool showAllChildRegionLabels;

  final bool showChildSlotNumbers;
  final List<ChildSlot> childSlotsToLabel;

  _ParkingGridPainter({
    required this.grid,
    required this.colorScheme,
    required this.showWalls,
    required this.showGates,
    required this.showTowers,
    required this.showWallNames,
    required this.showParkingAreas,
    required this.showParkingAreaLabels,
    required this.showChildRegions,
    required this.childRegions,
    required this.showChildRegionLabels,
    required this.showAllChildRegionLabels,
    required this.showChildSlotNumbers,
    required this.childSlotsToLabel,
  });

  Color _cellColor(int idx, ParkingGridCellType t) {
    final cs = colorScheme;
    switch (t) {
      case ParkingGridCellType.road:
        return grid.road2Cells.contains(idx)
            ? cs.tertiaryContainer.withOpacity(0.70)
            : cs.surfaceVariant.withOpacity(0.95);
      case ParkingGridCellType.pillar:
        return cs.errorContainer.withOpacity(0.75);
      case ParkingGridCellType.empty:
        return cs.primaryContainer.withOpacity(0.55);
    }
  }

  _LegacyGateKind _gateKindFor(EdgePlacement g) {
    final e = grid.entranceGate;
    final x = grid.exitGate;
    final isE = (e != null && e == g);
    final isX = (x != null && x == g);
    if (isE && isX) return _LegacyGateKind.mixed;
    if (isE) return _LegacyGateKind.entrance;
    return _LegacyGateKind.exit;
  }

  Color _gateAccent(_LegacyGateKind k) {
    switch (k) {
      case _LegacyGateKind.entrance:
        return Colors.green;
      case _LegacyGateKind.exit:
        return Colors.red;
      case _LegacyGateKind.mixed:
        return Colors.amber;
    }
  }

  String _gateLabel(_LegacyGateKind k) {
    switch (k) {
      case _LegacyGateKind.entrance:
        return '입구';
      case _LegacyGateKind.exit:
        return '출구';
      case _LegacyGateKind.mixed:
        return '입/출';
    }
  }

  void _drawLegacyGate(Canvas canvas, _GridLayout layout, EdgePlacement g,
      _LegacyGateKind kind) {
    final cs = colorScheme;
    final rect = layout.cellRect(g.r, g.c);
    final cell = layout.cell;

    Offset edgeCenter;
    Offset outward;
    switch (g.side) {
      case EdgeSide.north:
        edgeCenter = Offset(rect.center.dx, rect.top);
        outward = const Offset(0, -1);
        break;
      case EdgeSide.south:
        edgeCenter = Offset(rect.center.dx, rect.bottom);
        outward = const Offset(0, 1);
        break;
      case EdgeSide.west:
        edgeCenter = Offset(rect.left, rect.center.dy);
        outward = const Offset(-1, 0);
        break;
      case EdgeSide.east:
        edgeCenter = Offset(rect.right, rect.center.dy);
        outward = const Offset(1, 0);
        break;
    }

    final accent = _gateAccent(kind);
    final th = math.max(5.0, cell * 0.12);
    final len = cell * 0.78;
    final out = math.max(4.0, cell * 0.10);

    Rect barRect;
    if (g.side == EdgeSide.north || g.side == EdgeSide.south) {
      barRect = Rect.fromCenter(
        center: edgeCenter + outward * out,
        width: len,
        height: th,
      );
    } else {
      barRect = Rect.fromCenter(
        center: edgeCenter + outward * out,
        width: th,
        height: len,
      );
    }

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.surface.withOpacity(0.96);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.1, th * 0.12)
      ..color = accent.withOpacity(0.95);

    canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, Radius.circular(th * 0.45)), fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(barRect, Radius.circular(th * 0.45)), stroke);

    final tp = TextPainter(
      text: TextSpan(
        text: _gateLabel(kind),
        style: TextStyle(
          fontSize: math.max(9.0, cell * 0.18),
          fontWeight: FontWeight.w900,
          color: accent.withOpacity(0.95),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: 60);

    final labelPos = barRect.topLeft + Offset(2, -math.max(14.0, cell * 0.24));
    tp.paint(canvas, labelPos);
  }

  void _drawRectList(
    Canvas canvas,
    _GridLayout layout,
    List<GridRect> rects, {
    required String text,
    required Color fillColor,
    required Color strokeColor,
  }) {
    if (rects.isEmpty) return;
    final cell = layout.cell;

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = fillColor;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.4, cell * 0.07)
      ..color = strokeColor;

    final style = TextStyle(
      fontSize: math.max(10.0, cell * 0.18),
      fontWeight: FontWeight.w900,
      color: strokeColor.withOpacity(0.95),
    );

    for (final raw in rects) {
      final r = raw.normalized();
      if (r.r0 < 0 || r.c0 < 0 || r.r1 >= layout.rows || r.c1 >= layout.cols)
        continue;

      final rect = layout
          .rectForCellRange(r0: r.r0, r1: r.r1, c0: r.c0, c1: r.c1)
          .deflate(math.max(1.0, cell * 0.08));

      canvas.drawRRect(
          RRect.fromRectAndRadius(
              rect, Radius.circular(math.max(6.0, cell * 0.22))),
          fill);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              rect, Radius.circular(math.max(6.0, cell * 0.22))),
          stroke);

      if (rect.width < 24 || rect.height < 18) continue;

      final tp = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: rect.width - 6);

      tp.paint(
          canvas,
          Offset(rect.center.dx - tp.width / 2,
              rect.top + math.max(2.0, cell * 0.06)));
    }
  }

  void _drawRectGates(Canvas canvas, _GridLayout layout) {
    final cs = colorScheme;
    _drawRectList(
      canvas,
      layout,
      grid.entranceRects,
      text: '입구',
      fillColor: cs.primaryContainer.withOpacity(0.22),
      strokeColor: cs.primary.withOpacity(0.92),
    );
    _drawRectList(
      canvas,
      layout,
      grid.exitRects,
      text: '출구',
      fillColor: cs.errorContainer.withOpacity(0.22),
      strokeColor: cs.error.withOpacity(0.92),
    );
  }

  void _drawTowerRects(Canvas canvas, _GridLayout layout) {
    final cs = colorScheme;
    _drawRectList(
      canvas,
      layout,
      grid.towerRects,
      text: '주차 타워',
      fillColor: cs.tertiaryContainer.withOpacity(0.18),
      strokeColor: cs.tertiary.withOpacity(0.92),
    );
  }

  void _drawWall(Canvas canvas, _GridLayout layout, EdgePlacement w,
      {required bool named}) {
    final cs = colorScheme;
    final rect = layout.cellRect(w.r, w.c);
    final cell = layout.cell;

    final th = math.max(2.6, cell * 0.11);
    final out = math.max(3.5, cell * 0.10);

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
      ..color = cs.onSurface.withOpacity(0.35);

    final hi = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = th + 1.0
      ..color = named
          ? cs.primary.withOpacity(0.90)
          : cs.outlineVariant.withOpacity(0.80);

    canvas.drawLine(a, b, base);
    canvas.drawLine(a, b, hi);
  }

  void _drawWallName(
      Canvas canvas, _GridLayout layout, EdgePlacement w, String name) {
    final cs = colorScheme;
    final rect = layout.cellRect(w.r, w.c);
    final cell = layout.cell;

    Offset pos;
    switch (w.side) {
      case EdgeSide.north:
        pos = Offset(rect.center.dx, rect.top - math.max(18.0, cell * 0.28));
        break;
      case EdgeSide.south:
        pos = Offset(rect.center.dx, rect.bottom + math.max(6.0, cell * 0.12));
        break;
      case EdgeSide.west:
        pos =
            Offset(rect.left - math.max(60.0, cell * 0.80), rect.center.dy - 8);
        break;
      case EdgeSide.east:
        pos =
            Offset(rect.right + math.max(6.0, cell * 0.12), rect.center.dy - 8);
        break;
    }

    final tp = TextPainter(
      text: TextSpan(
        text: name,
        style: TextStyle(
          fontSize: math.max(10.0, cell * 0.18),
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

  void _drawParkingArea(Canvas canvas, _GridLayout layout, ParkingArea a,
      {required bool drawLabel}) {
    final cs = colorScheme;

    final (h, w) = _parkingSizeForKind(a.kind);
    final top = a.r0;
    final left = a.c0;
    final bottom = a.r0 + h - 1;
    final right = a.c0 + w - 1;

    if (top < 0 || left < 0 || bottom >= layout.rows || right >= layout.cols)
      return;

    final rect = layout
        .rectForCellRange(r0: top, r1: bottom, c0: left, c1: right)
        .deflate(math.max(1.0, layout.cell * 0.10));

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.secondaryContainer.withOpacity(0.42);

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.1, layout.cell * 0.07)
      ..color = cs.secondary.withOpacity(0.90);

    canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect, Radius.circular(math.max(4.0, layout.cell * 0.18))),
        fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect, Radius.circular(math.max(4.0, layout.cell * 0.18))),
        stroke);

    if (!drawLabel) return;
    if (rect.width < 14 || rect.height < 14) return;

    final tp = TextPainter(
      text: TextSpan(
        text: 'P',
        style: TextStyle(
          fontSize: math.max(10.0, math.min(layout.cell * 0.55, 18.0)),
          fontWeight: FontWeight.w900,
          color: cs.onSecondaryContainer.withOpacity(0.90),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    tp.paint(canvas,
        Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
  }

  void _drawChildRegion(
      Canvas canvas, _GridLayout layout, ChildRegionOverlay ov) {
    final cs = colorScheme;
    final rr = ov.rect.normalized();

    if (rr.r0 < 0 || rr.c0 < 0 || rr.r1 >= layout.rows || rr.c1 >= layout.cols)
      return;

    final rect = layout
        .rectForCellRange(r0: rr.r0, r1: rr.r1, c0: rr.c0, c1: rr.c1)
        .deflate(math.max(1.0, layout.cell * 0.06));

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = (ov.isSelected
          ? cs.tertiaryContainer.withOpacity(0.22)
          : cs.surfaceVariant.withOpacity(0.10));

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ov.isSelected
          ? math.max(2.2, layout.cell * 0.10)
          : math.max(1.4, layout.cell * 0.07)
      ..color = (ov.isSelected
          ? cs.tertiary.withOpacity(0.95)
          : cs.outlineVariant.withOpacity(0.85));

    canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect, Radius.circular(math.max(6.0, layout.cell * 0.22))),
        fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect, Radius.circular(math.max(6.0, layout.cell * 0.22))),
        stroke);

    final shouldLabel =
        showChildRegionLabels && (showAllChildRegionLabels || ov.isSelected);
    if (!shouldLabel) return;
    if (rect.width < 24 || rect.height < 18) return;

    final tp = TextPainter(
      text: TextSpan(
        text: ov.label,
        style: TextStyle(
          fontSize: math.max(11.0, math.min(layout.cell * 0.65, 18.0)),
          fontWeight: FontWeight.w900,
          color: ov.isSelected
              ? cs.onTertiaryContainer.withOpacity(0.95)
              : cs.onSurface.withOpacity(0.80),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: rect.width - 6);

    tp.paint(canvas,
        Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
  }

  void _drawChildSlotNumber(Canvas canvas, _GridLayout layout, ChildSlot s) {
    final cs = colorScheme;

    final top = math.min(s.r0, s.r1);
    final bottom = math.max(s.r0, s.r1);
    final left = math.min(s.c0, s.c1);
    final right = math.max(s.c0, s.c1);

    if (top < 0 || left < 0 || bottom >= layout.rows || right >= layout.cols)
      return;

    final rect = layout
        .rectForCellRange(r0: top, r1: bottom, c0: left, c1: right)
        .deflate(math.max(1.0, layout.cell * 0.18));

    if (rect.width < 12 || rect.height < 12) return;

    final bg = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.surface.withOpacity(0.80);

    final bd = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, layout.cell * 0.06)
      ..color = cs.primary.withOpacity(0.85);

    final badgeSize = math.min(rect.width, rect.height) * 0.55;
    final badge = Rect.fromCenter(
      center: rect.center,
      width: badgeSize.clamp(12.0, 28.0),
      height: badgeSize.clamp(12.0, 28.0),
    );

    canvas.drawRRect(
        RRect.fromRectAndRadius(badge, Radius.circular(badge.height * 0.30)),
        bg);
    canvas.drawRRect(
        RRect.fromRectAndRadius(badge, Radius.circular(badge.height * 0.30)),
        bd);

    final tp = TextPainter(
      text: TextSpan(
        text: '${s.no}',
        style: TextStyle(
          fontSize: math.max(10.0, badge.height * 0.55),
          fontWeight: FontWeight.w900,
          color: cs.primary.withOpacity(0.95),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: badge.width);

    tp.paint(
        canvas,
        Offset(
            badge.center.dx - tp.width / 2, badge.center.dy - tp.height / 2));
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cs = colorScheme;

    final rows = grid.rows;
    final cols = grid.cols;

    if (rows <= 0 || cols <= 0) return;

    final layout = _GridLayout.fit(
        size: size, rows: rows, cols: cols, padding: 10, gap: 2);
    final gridRect = layout.gridRect();

    final bg = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.surfaceContainerLow.withOpacity(0.85);

    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = cs.outlineVariant.withOpacity(0.95);

    canvas.drawRRect(
        RRect.fromRectAndRadius(gridRect, const Radius.circular(12)), bg);
    canvas.drawRRect(
        RRect.fromRectAndRadius(gridRect, const Radius.circular(12)), border);

    final cellBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6
      ..color = cs.outlineVariant.withOpacity(0.65);

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final idx = r * cols + c;
        if (idx < 0 || idx >= grid.cells.length) continue;

        final t = grid.cells[idx];
        final rect = layout.cellRect(r, c);

        final fill = Paint()
          ..style = PaintingStyle.fill
          ..color = _cellColor(idx, t);

        final rr = RRect.fromRectAndRadius(rect, const Radius.circular(6));
        canvas.drawRRect(rr, fill);
        canvas.drawRRect(rr, cellBorder);

        if (t == ParkingGridCellType.pillar) {
          final center = rect.center;
          final rad = math.max(3.0, layout.cell * 0.18);
          final pFill = Paint()..color = cs.onSurface.withOpacity(0.18);
          final pStroke = Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.max(1.1, layout.cell * 0.035)
            ..color = cs.onSurface.withOpacity(0.52);
          canvas.drawCircle(center, rad, pFill);
          canvas.drawCircle(center, rad, pStroke);
        }

        if (t == ParkingGridCellType.road) {
          final paint = Paint()
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeWidth = math.max(1.1, layout.cell * 0.04)
            ..color = cs.surface.withOpacity(0.70);

          final a = Offset(rect.center.dx, rect.top + rect.height * 0.18);
          final b = Offset(rect.center.dx, rect.bottom - rect.height * 0.18);

          final dash = math.max(4.0, layout.cell * 0.12);
          final gap = math.max(3.0, layout.cell * 0.08);

          double t0 = 0;
          final dx = b.dx - a.dx;
          final dy = b.dy - a.dy;
          final len = math.sqrt(dx * dx + dy * dy);
          if (len > 1e-6) {
            final ux = dx / len;
            final uy = dy / len;
            while (t0 < len) {
              final t1 = math.min(len, t0 + dash);
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

    if (showParkingAreas && grid.parkingAreas.isNotEmpty) {
      for (final a in grid.parkingAreas) {
        _drawParkingArea(canvas, layout, a, drawLabel: false);
      }
    }

    if (showGates) {
      if (grid.entranceRects.isNotEmpty || grid.exitRects.isNotEmpty) {
        _drawRectGates(canvas, layout);
      } else {
        final gateSet = <EdgePlacement>{};
        final entrance = grid.entranceGate;
        final exit = grid.exitGate;

        if (entrance != null && isEdgeValid(entrance, rows, cols))
          gateSet.add(entrance);
        if (exit != null && isEdgeValid(exit, rows, cols)) gateSet.add(exit);

        for (final g in gateSet) {
          _drawLegacyGate(canvas, layout, g, _gateKindFor(g));
        }
      }
    }

    if (showTowers && grid.towerRects.isNotEmpty) {
      _drawTowerRects(canvas, layout);
    }

    if (showChildRegions && childRegions.isNotEmpty) {
      for (final ov in childRegions) {
        _drawChildRegion(canvas, layout, ov);
      }
    }

    Map<EdgePlacement, WallGroupId?> parsedWalls = const {};
    if (showWalls && grid.walls.isNotEmpty) {
      final tmp = <EdgePlacement, WallGroupId?>{};
      for (final e in grid.walls.entries) {
        try {
          final edge = EdgePlacement.fromKey(e.key);
          if (!isEdgeValid(edge, rows, cols)) continue;
          tmp[edge] = e.value;
        } catch (_) {}
      }
      parsedWalls = tmp;

      for (final w in parsedWalls.entries) {
        final gid = w.value;
        final named =
            (gid != null) && (grid.wallGroups[gid]?.trim().isNotEmpty ?? false);
        _drawWall(canvas, layout, w.key, named: named);
      }

      if (showWallNames &&
          grid.wallGroups.isNotEmpty &&
          parsedWalls.isNotEmpty) {
        final reps = <WallGroupId, EdgePlacement>{};
        for (final e in parsedWalls.entries) {
          final gid = e.value;
          if (gid == null) continue;

          final name = grid.wallGroups[gid]?.trim();
          if (name == null || name.isEmpty) continue;

          if (!reps.containsKey(gid)) {
            reps[gid] = e.key;
          } else {
            final cur = reps[gid]!;
            if (edgeSortKey(e.key) < edgeSortKey(cur)) {
              reps[gid] = e.key;
            }
          }
        }

        for (final entry in reps.entries) {
          final name = grid.wallGroups[entry.key]?.trim() ?? '';
          if (name.isNotEmpty) _drawWallName(canvas, layout, entry.value, name);
        }
      }
    }

    if (showParkingAreas && grid.parkingAreas.isNotEmpty) {
      for (final a in grid.parkingAreas) {
        _drawParkingArea(canvas, layout, a, drawLabel: showParkingAreaLabels);
      }
    }

    if (showChildSlotNumbers && childSlotsToLabel.isNotEmpty) {
      for (final s in childSlotsToLabel) {
        _drawChildSlotNumber(canvas, layout, s);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ParkingGridPainter oldDelegate) {
    return oldDelegate.grid != grid ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.showWalls != showWalls ||
        oldDelegate.showGates != showGates ||
        oldDelegate.showTowers != showTowers ||
        oldDelegate.showWallNames != showWallNames ||
        oldDelegate.showParkingAreas != showParkingAreas ||
        oldDelegate.showParkingAreaLabels != showParkingAreaLabels ||
        oldDelegate.showChildRegions != showChildRegions ||
        oldDelegate.childRegions != childRegions ||
        oldDelegate.showChildRegionLabels != showChildRegionLabels ||
        oldDelegate.showAllChildRegionLabels != showAllChildRegionLabels ||
        oldDelegate.showChildSlotNumbers != showChildSlotNumbers ||
        oldDelegate.childSlotsToLabel != childSlotsToLabel;
  }
}
