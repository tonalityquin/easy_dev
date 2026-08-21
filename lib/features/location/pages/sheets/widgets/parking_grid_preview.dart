import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../../domain/models/grid_rect.dart';
import '../../../domain/models/location_model.dart';
import '../../../domain/models/parking_grid_model.dart';

class ChildRegionOverlay {
  final String id;
  final GridRect rect;
  final String label;
  final bool isSelected;

  const ChildRegionOverlay({
    required this.id,
    required this.rect,
    required this.label,
    required this.isSelected,
  });
}

class ParkingGridPreview extends StatelessWidget {
  final ParkingGridModel grid;
  final double maxExtent;

  final bool showLegend;
  final bool showGates;
  final bool showTowers;

  final bool showParkingAreas;
  final bool showParkingAreaLabels;

  final bool showChildRegions;
  final bool showChildRegionLabels;
  final bool showAllChildRegionLabels;
  final List<ChildRegionOverlay> childRegions;

  final bool showChildSlotNumbers;
  final List<ChildSlot> childSlotsToLabel;
  final ValueChanged<String>? onTapChildRegion;

  const ParkingGridPreview({
    super.key,
    required this.grid,
    this.maxExtent = 280,
    this.showLegend = true,
    this.showGates = true,
    this.showTowers = true,
    this.showParkingAreas = true,
    this.showParkingAreaLabels = true,
    this.showChildRegions = true,
    this.showChildRegionLabels = true,
    this.showAllChildRegionLabels = false,
    this.childRegions = const <ChildRegionOverlay>[],
    this.showChildSlotNumbers = true,
    this.childSlotsToLabel = const <ChildSlot>[],
    this.onTapChildRegion,
  });

  String? _selectedRegionId() {
    for (final region in childRegions) {
      if (region.isSelected) return region.id;
    }
    return null;
  }

  String? _regionIdAt(Size size, Offset position) {
    if (grid.rows <= 0 || grid.cols <= 0) return null;
    final layout = _GridLayout.fit(
      size: size,
      rows: grid.rows,
      cols: grid.cols,
      padding: 10,
      gap: 2,
    );
    for (final region in childRegions.reversed) {
      final rect = region.rect.normalized();
      if (rect.r0 < 0 ||
          rect.c0 < 0 ||
          rect.r1 >= layout.rows ||
          rect.c1 >= layout.cols) {
        continue;
      }
      final hitRect = layout
          .rectForCellRange(
            r0: rect.r0,
            r1: rect.r1,
            c0: rect.c0,
            c1: rect.c1,
          )
          .deflate(math.max(1.0, layout.cell * 0.06));
      if (hitRect.contains(position)) return region.id;
    }
    return null;
  }

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
        case ParkingGridCellType.wall:
          return cs.onSurface.withOpacity(0.72);
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


    final rectGateCount = grid.entranceRects.length + grid.exitRects.length;
    final towerCount = grid.towerRects.length;
    final gateCount = rectGateCount;

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
            child: LayoutBuilder(
              builder: (context, constraints) {
                final size = Size(constraints.maxWidth, constraints.maxHeight);
                final selectedRegionId = _selectedRegionId();
                final tapChildRegion = onTapChildRegion;
                final reduceMotion =
                    MediaQuery.maybeOf(context)?.disableAnimations ?? false;
                return ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapUp: !showChildRegions || tapChildRegion == null
                        ? null
                        : (details) {
                            final id = _regionIdAt(size, details.localPosition);
                            if (id != null) tapChildRegion(id);
                          },
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey<String>(
                        'parking-grid-selection-${selectedRegionId ?? 'none'}',
                      ),
                      tween: Tween<double>(
                        begin: selectedRegionId == null ? 1 : 0,
                        end: 1,
                      ),
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 170),
                      curve: Curves.easeOutCubic,
                      builder: (context, selectionProgress, _) {
                        return CustomPaint(
                          painter: _ParkingGridPainter(
                            grid: grid,
                            colorScheme: cs,
                            showGates: showGates,
                            showTowers: showTowers,
                            showParkingAreas: showParkingAreas,
                            showParkingAreaLabels: showParkingAreaLabels,
                            showChildRegions: showChildRegions,
                            childRegions: childRegions,
                            showChildRegionLabels: showChildRegionLabels,
                            showAllChildRegionLabels: showAllChildRegionLabels,
                            showChildSlotNumbers: showChildSlotNumbers,
                            childSlotsToLabel: childSlotsToLabel,
                            selectionProgress: selectionProgress,
                          ),
                          child: const SizedBox.expand(),
                        );
                      },
                    ),
                  ),
                );
              },
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
              legendDot(cellColor(ParkingGridCellType.wall), '벽'),
              pill('${grid.rows}×${grid.cols}'),
              if (showParkingAreas && parkingAreaCount > 0)
                pill('주차면적 $parkingAreaCount'),
              if (showGates && gateCount > 0) pill('게이트 $gateCount'),
              if (showTowers && towerCount > 0) pill('주차 타워 $towerCount'),
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

class _ParkingGridPainter extends CustomPainter {
  final ParkingGridModel grid;
  final ColorScheme colorScheme;
  final bool showGates;
  final bool showTowers;
  final bool showParkingAreas;
  final bool showParkingAreaLabels;

  final bool showChildRegions;
  final List<ChildRegionOverlay> childRegions;
  final bool showChildRegionLabels;
  final bool showAllChildRegionLabels;

  final bool showChildSlotNumbers;
  final List<ChildSlot> childSlotsToLabel;
  final double selectionProgress;

  _ParkingGridPainter({
    required this.grid,
    required this.colorScheme,
    required this.showGates,
    required this.showTowers,
    required this.showParkingAreas,
    required this.showParkingAreaLabels,
    required this.showChildRegions,
    required this.childRegions,
    required this.showChildRegionLabels,
    required this.showAllChildRegionLabels,
    required this.showChildSlotNumbers,
    required this.childSlotsToLabel,
    required this.selectionProgress,
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
      case ParkingGridCellType.wall:
        return cs.onSurface.withOpacity(0.72);
      case ParkingGridCellType.empty:
        return cs.primaryContainer.withOpacity(0.55);
    }
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

  void _drawParkingArea(Canvas canvas, _GridLayout layout, ParkingArea a,
      {required bool drawLabel}) {
    final h = a.kind.h;
    final w = a.kind.w;
    final top = a.r0;
    final left = a.c0;
    final bottom = a.r0 + h - 1;
    final right = a.c0 + w - 1;

    if (top < 0 || left < 0 || bottom >= layout.rows || right >= layout.cols)
      return;

    final rect = layout
        .rectForCellRange(r0: top, r1: bottom, c0: left, c1: right)
        .deflate(math.max(1.0, layout.cell * 0.10));

    final style = _parkingAreaStyle(a.kind);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = style.fill;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.1, layout.cell * 0.07)
      ..color = style.stroke;

    canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect, Radius.circular(math.max(4.0, layout.cell * 0.18))),
        fill);
    canvas.drawRRect(
        RRect.fromRectAndRadius(
            rect, Radius.circular(math.max(4.0, layout.cell * 0.18))),
        stroke);
  }

  ({Color fill, Color stroke}) _parkingAreaStyle(ParkingAreaKind kind) {
    final cs = colorScheme;
    switch (kind.categoryKey) {
      case 'compact':
        return (
          fill: const Color(0xFF64B5F6).withOpacity(0.52),
          stroke: const Color(0xFF1565C0).withOpacity(0.88),
        );
      case 'standard':
        return (
          fill: cs.secondaryContainer.withOpacity(0.48),
          stroke: cs.secondary.withOpacity(0.88),
        );
      case 'extendedA':
      case 'extendedB':
        return (
          fill: const Color(0xFFFFD54F).withOpacity(0.58),
          stroke: const Color(0xFFF9A825).withOpacity(0.88),
        );
      case 'evCompact':
      case 'evStandard':
      case 'evExtendedA':
      case 'evExtendedB':
        return (
          fill: const Color(0xFFA5D6A7).withOpacity(0.58),
          stroke: const Color(0xFF2E7D32).withOpacity(0.88),
        );
      case 'pregnantExtendedA':
      case 'pregnantExtendedB':
        return (
          fill: const Color(0xFFF8BBD0).withOpacity(0.58),
          stroke: const Color(0xFFC2185B).withOpacity(0.88),
        );
      case 'disabledStandard':
      case 'disabledExtendedA':
      case 'disabledExtendedB':
        return (
          fill: const Color(0xFFB39DDB).withOpacity(0.58),
          stroke: const Color(0xFF512DA8).withOpacity(0.88),
        );
      default:
        return (
          fill: cs.secondaryContainer.withOpacity(0.42),
          stroke: cs.secondary.withOpacity(0.90),
        );
    }
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

    final progress = ov.isSelected
        ? selectionProgress.clamp(0.0, 1.0).toDouble()
        : 0.0;
    final baseFill = cs.surfaceVariant.withOpacity(0.10);
    final selectedFill = cs.tertiaryContainer.withOpacity(0.22);
    final baseStroke = cs.outlineVariant.withOpacity(0.85);
    final selectedStroke = cs.tertiary.withOpacity(0.95);
    final baseStrokeWidth = math.max(1.4, layout.cell * 0.07);
    final selectedStrokeWidth = math.max(2.2, layout.cell * 0.10);

    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = Color.lerp(baseFill, selectedFill, progress) ?? baseFill;

    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = baseStrokeWidth +
          (selectedStrokeWidth - baseStrokeWidth) * progress
      ..color = Color.lerp(baseStroke, selectedStroke, progress) ?? baseStroke;

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
              ? cs.onTertiaryContainer.withOpacity(0.95 * progress)
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
      ..color = cs.surface.withOpacity(0.86);

    final bd = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = math.max(1.0, layout.cell * 0.06)
      ..color = cs.primary.withOpacity(0.85);

    final text = '${s.no}';

    final fontSize = math.max(9.0, math.min(layout.cell * 0.27, 13.0));
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          color: cs.primary.withOpacity(0.95),
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(12.0, rect.width - 4));

    final badgeW = math.min(rect.width, math.max(18.0, tp.width + 8));
    final badgeH = math.min(rect.height, math.max(14.0, tp.height + 5));
    final badge = Rect.fromCenter(
      center: rect.center,
      width: badgeW,
      height: badgeH,
    );

    canvas.drawRRect(
        RRect.fromRectAndRadius(badge, Radius.circular(badge.height * 0.30)),
        bg);
    canvas.drawRRect(
        RRect.fromRectAndRadius(badge, Radius.circular(badge.height * 0.30)),
        bd);

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
      _drawRectGates(canvas, layout);
    }

    if (showTowers && grid.towerRects.isNotEmpty) {
      _drawTowerRects(canvas, layout);
    }

    if (showChildRegions && childRegions.isNotEmpty) {
      for (final ov in childRegions) {
        _drawChildRegion(canvas, layout, ov);
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
        oldDelegate.showGates != showGates ||
        oldDelegate.showTowers != showTowers ||
        oldDelegate.showParkingAreas != showParkingAreas ||
        oldDelegate.showParkingAreaLabels != showParkingAreaLabels ||
        oldDelegate.showChildRegions != showChildRegions ||
        oldDelegate.childRegions != childRegions ||
        oldDelegate.showChildRegionLabels != showChildRegionLabels ||
        oldDelegate.showAllChildRegionLabels != showAllChildRegionLabels ||
        oldDelegate.showChildSlotNumbers != showChildSlotNumbers ||
        oldDelegate.childSlotsToLabel != childSlotsToLabel ||
        oldDelegate.selectionProgress != selectionProgress;
  }
}
