import 'dart:math' as math;

import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';

import '../../design_system/common_ui/common_ui_theme.dart';
import '../../features/location/domain/models/grid_rect.dart';
import '../../features/location/domain/models/parking_grid_model.dart';

class ParkingStatusDotMapLayout {
  const ParkingStatusDotMapLayout({
    required this.origin,
    required this.scale,
    required this.mapRect,
    required this.viewport,
  });

  final Offset origin;
  final double scale;
  final Rect mapRect;
  final GridRect viewport;

  static ParkingStatusDotMapLayout? resolve({
    required Size size,
    required ParkingGridModel grid,
    GridRect? viewport,
    double padding = 9,
  }) {
    if (grid.rows <= 0 || grid.cols <= 0 || size.isEmpty) return null;
    final screenViewport = Rect.fromLTWH(
      padding,
      padding,
      math.max(0.0, size.width - padding * 2).toDouble(),
      math.max(0.0, size.height - padding * 2).toDouble(),
    );
    if (screenViewport.width <= 0 || screenViewport.height <= 0) return null;
    final fullViewport = GridRect(
      r0: 0,
      c0: 0,
      r1: grid.rows - 1,
      c1: grid.cols - 1,
    );
    final rawViewport = (viewport ?? fullViewport).normalized();
    final logicalViewport = GridRect(
      r0: rawViewport.top.clamp(0, grid.rows - 1).toInt(),
      c0: rawViewport.left.clamp(0, grid.cols - 1).toInt(),
      r1: rawViewport.bottom.clamp(0, grid.rows - 1).toInt(),
      c1: rawViewport.right.clamp(0, grid.cols - 1).toInt(),
    ).normalized();
    if (logicalViewport.width <= 0 || logicalViewport.height <= 0) return null;
    final scale = math.min(
      screenViewport.width / logicalViewport.width,
      screenViewport.height / logicalViewport.height,
    );
    if (!scale.isFinite || scale <= 0) return null;
    final mapWidth = logicalViewport.width * scale;
    final mapHeight = logicalViewport.height * scale;
    final visibleOrigin = Offset(
      screenViewport.left + (screenViewport.width - mapWidth) / 2,
      screenViewport.top + (screenViewport.height - mapHeight) / 2,
    );
    final logicalOrigin = Offset(
      visibleOrigin.dx - logicalViewport.left * scale,
      visibleOrigin.dy - logicalViewport.top * scale,
    );
    return ParkingStatusDotMapLayout(
      origin: logicalOrigin,
      scale: scale,
      mapRect: Rect.fromLTWH(
        visibleOrigin.dx,
        visibleOrigin.dy,
        mapWidth,
        mapHeight,
      ),
      viewport: logicalViewport,
    );
  }

  Rect rectFor(GridRect raw) {
    final rect = raw.normalized();
    return Rect.fromLTRB(
      origin.dx + rect.left * scale,
      origin.dy + rect.top * scale,
      origin.dx + (rect.right + 1) * scale,
      origin.dy + (rect.bottom + 1) * scale,
    );
  }
}

class ParkingStatusDotMapSurface extends StatelessWidget {
  const ParkingStatusDotMapSurface({
    super.key,
    required this.grid,
    this.targetRect,
    this.viewport,
    this.visibleParkingAreaIds,
    this.exact = false,
    this.pulse = 1,
    this.framed = true,
    this.padding = 9,
  });

  final ParkingGridModel grid;
  final GridRect? targetRect;
  final GridRect? viewport;
  final Set<String>? visibleParkingAreaIds;
  final bool exact;
  final double pulse;
  final bool framed;
  final double padding;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final content = CustomPaint(
      painter: ParkingStatusDotMapPainter(
        grid: grid,
        targetRect: targetRect,
        viewport: viewport,
        visibleParkingAreaIds: visibleParkingAreaIds,
        exact: exact,
        pulse: pulse,
        framed: framed,
        padding: padding,
        tokens: tokens,
      ),
      child: const SizedBox.expand(),
    );
    if (!framed) return content;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay.withOpacity(.38),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(11),
        child: content,
      ),
    );
  }
}

class ParkingStatusDotMapPainter extends CustomPainter {
  const ParkingStatusDotMapPainter({
    required this.grid,
    required this.targetRect,
    required this.viewport,
    required this.visibleParkingAreaIds,
    required this.exact,
    required this.pulse,
    required this.framed,
    required this.padding,
    required this.tokens,
  });

  final ParkingGridModel grid;
  final GridRect? targetRect;
  final GridRect? viewport;
  final Set<String>? visibleParkingAreaIds;
  final bool exact;
  final double pulse;
  final bool framed;
  final double padding;
  final CommonUiTokens tokens;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = ParkingStatusDotMapLayout.resolve(
      size: size,
      grid: grid,
      viewport: viewport,
      padding: padding,
    );
    if (layout == null) return;
    final scale = layout.scale;
    final origin = layout.origin;
    final mapRect = layout.mapRect;

    canvas.save();
    if (framed) {
      final framePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = tokens.borderSubtle.withOpacity(.75);
      canvas.drawRRect(
        RRect.fromRectAndRadius(mapRect, const Radius.circular(8)),
        framePaint,
      );
      canvas.clipRRect(
        RRect.fromRectAndRadius(mapRect, const Radius.circular(8)),
      );
    } else {
      canvas.clipRect(mapRect);
    }

    final totalCells = grid.rows * grid.cols;
    final visibleCells = layout.viewport.area;
    final drawCellDetails = visibleCells <= 12000 && scale >= .45;
    if (drawCellDetails) {
      final roadPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = tokens.textSecondary.withOpacity(.08);
      final road2Paint = Paint()
        ..style = PaintingStyle.fill
        ..color = tokens.info.withOpacity(.11);
      final pillarPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = tokens.textSecondary.withOpacity(.34);
      final wallPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = tokens.textPrimary.withOpacity(.52);
      final road2Cells = grid.road2Cells.toSet();
      final view = layout.viewport;
      for (var row = view.top; row <= view.bottom; row++) {
        for (var col = view.left; col <= view.right; col++) {
          final index = row * grid.cols + col;
          if (index < 0 || index >= grid.cells.length || index >= totalCells) {
            continue;
          }
          final type = grid.cells[index];
          if (type == ParkingGridCellType.empty) continue;
          final rect = Rect.fromLTWH(
            origin.dx + col * scale,
            origin.dy + row * scale,
            scale,
            scale,
          );
          if (type == ParkingGridCellType.road) {
            canvas.drawRect(
              rect,
              road2Cells.contains(index) ? road2Paint : roadPaint,
            );
          } else if (type == ParkingGridCellType.pillar) {
            final inset = math.min(scale * .22, 1.6);
            canvas.drawRect(rect.deflate(inset), pillarPaint);
          } else if (type == ParkingGridCellType.wall) {
            final inset = math.min(scale * .08, .8);
            canvas.drawRect(rect.deflate(inset), wallPaint);
          }
        }
      }
    }

    final dotRadius = (scale * .2).clamp(1.0, 2.7).toDouble();
    final parkingPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = tokens.textSecondary.withOpacity(.46);
    for (final area in grid.parkingAreas) {
      final visibleIds = visibleParkingAreaIds;
      if (visibleIds != null) {
        final id = area.id.trim();
        if (id.isEmpty || !visibleIds.contains(id)) continue;
      }
      final center = _logicalCenter(
        origin: origin,
        scale: scale,
        r0: area.r0,
        c0: area.c0,
        r1: area.r1,
        c1: area.c1,
      );
      canvas.drawCircle(center, dotRadius, parkingPaint);
    }

    _drawStructureRects(
      canvas: canvas,
      rects: grid.towerRects,
      origin: origin,
      scale: scale,
      color: tokens.textSecondary.withOpacity(.38),
      fillOpacity: .06,
    );
    _drawStructureRects(
      canvas: canvas,
      rects: grid.entranceRects,
      origin: origin,
      scale: scale,
      color: tokens.success.withOpacity(.8),
      fillOpacity: .08,
    );
    _drawStructureRects(
      canvas: canvas,
      rects: grid.exitRects,
      origin: origin,
      scale: scale,
      color: tokens.danger.withOpacity(.72),
      fillOpacity: .06,
    );

    if (size.width >= 220 && scale >= .75) {
      _drawRectLabel(
        canvas: canvas,
        rects: grid.entranceRects,
        origin: origin,
        scale: scale,
        text: 'IN',
        color: tokens.success,
      );
      _drawRectLabel(
        canvas: canvas,
        rects: grid.exitRects,
        origin: origin,
        scale: scale,
        text: 'OUT',
        color: tokens.danger,
      );
    }

    final target = targetRect?.normalized();
    if (target == null) {
      canvas.restore();
      return;
    }
    final targetScreenRect = Rect.fromLTRB(
      origin.dx + target.left * scale,
      origin.dy + target.top * scale,
      origin.dx + (target.right + 1) * scale,
      origin.dy + (target.bottom + 1) * scale,
    );
    final targetCenter = targetScreenRect.center;

    if (!exact) {
      final regionPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = tokens.accent.withOpacity(.88);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          targetScreenRect.inflate(math.max(1.5, scale * .12)),
          const Radius.circular(5),
        ),
        regionPaint,
      );
    }

    final markerRadius = (size.width * .018).clamp(5.5, 7.5).toDouble();
    final pulseValue = pulse.clamp(0.0, 1.0).toDouble();
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = tokens.accent.withOpacity(.48 * (1 - pulseValue));
    canvas.drawCircle(
      targetCenter,
      markerRadius + 3 + pulseValue * 7,
      ringPaint,
    );

    if (exact) {
      final markerPaint = Paint()
        ..style = PaintingStyle.fill
        ..color = tokens.accent;
      canvas.drawCircle(targetCenter, markerRadius, markerPaint);
      final corePaint = Paint()
        ..style = PaintingStyle.fill
        ..color = tokens.onAccentContainer;
      canvas.drawCircle(
        targetCenter,
        math.max(1.7, markerRadius * .34),
        corePaint,
      );
    } else {
      final markerPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = tokens.accent;
      canvas.drawCircle(targetCenter, markerRadius * .72, markerPaint);
    }
    canvas.restore();
  }

  Offset _logicalCenter({
    required Offset origin,
    required double scale,
    required int r0,
    required int c0,
    required int r1,
    required int c1,
  }) {
    return Offset(
      origin.dx + ((c0 + c1 + 1) / 2) * scale,
      origin.dy + ((r0 + r1 + 1) / 2) * scale,
    );
  }

  void _drawStructureRects({
    required Canvas canvas,
    required List<GridRect> rects,
    required Offset origin,
    required double scale,
    required Color color,
    required double fillOpacity,
  }) {
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(fillOpacity);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = color;
    for (final raw in rects) {
      final rect = raw.normalized();
      final screen = Rect.fromLTRB(
        origin.dx + rect.left * scale,
        origin.dy + rect.top * scale,
        origin.dx + (rect.right + 1) * scale,
        origin.dy + (rect.bottom + 1) * scale,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(screen, const Radius.circular(3)),
        fill,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(screen, const Radius.circular(3)),
        stroke,
      );
    }
  }

  void _drawRectLabel({
    required Canvas canvas,
    required List<GridRect> rects,
    required Offset origin,
    required double scale,
    required String text,
    required Color color,
  }) {
    if (rects.isEmpty) return;
    final rect = rects.first.normalized();
    final center = _logicalCenter(
      origin: origin,
      scale: scale,
      r0: rect.top,
      c0: rect.left,
      r1: rect.bottom,
      c1: rect.right,
    );
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 7,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(
      canvas,
      Offset(center.dx - painter.width / 2, center.dy - painter.height / 2),
    );
  }

  @override
  bool shouldRepaint(covariant ParkingStatusDotMapPainter oldDelegate) {
    return oldDelegate.grid != grid ||
        oldDelegate.targetRect != targetRect ||
        oldDelegate.viewport != viewport ||
        !setEquals(
          oldDelegate.visibleParkingAreaIds,
          visibleParkingAreaIds,
        ) ||
        oldDelegate.exact != exact ||
        oldDelegate.pulse != pulse ||
        oldDelegate.framed != framed ||
        oldDelegate.padding != padding ||
        oldDelegate.tokens != tokens;
  }
}
