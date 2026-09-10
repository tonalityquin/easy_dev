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

@immutable
class ParkingGuidanceMarker {
  const ParkingGuidanceMarker({
    required this.rect,
    required this.exact,
    required this.attention,
    required this.selected,
  });

  final GridRect rect;
  final bool exact;
  final bool attention;
  final bool selected;
}

class ParkingGuidanceMapSurface extends StatelessWidget {
  const ParkingGuidanceMapSurface({
    super.key,
    required this.grid,
    this.markers = const <ParkingGuidanceMarker>[],
    this.targetRect,
    this.viewport,
    this.visibleParkingAreaIds,
    this.exact = false,
    this.pulse = 1,
    this.framed = true,
    this.padding = 9,
  });

  final ParkingGridModel grid;
  final List<ParkingGuidanceMarker> markers;
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
    return ColoredBox(
      color: tokens.canvas,
      child: CustomPaint(
        painter: ParkingGuidanceMapPainter(
          grid: grid,
          markers: markers,
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
      ),
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
    return ParkingGuidanceMapSurface(
      grid: grid,
      targetRect: targetRect,
      viewport: viewport,
      visibleParkingAreaIds: visibleParkingAreaIds,
      exact: exact,
      pulse: pulse,
      framed: framed,
      padding: padding,
    );
  }
}

class ParkingGuidanceMapPainter extends CustomPainter {
  const ParkingGuidanceMapPainter({
    required this.grid,
    required this.markers,
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
  final List<ParkingGuidanceMarker> markers;
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

    final mapRect = layout.mapRect;
    final boundary = RRect.fromRectAndRadius(
      mapRect,
      Radius.circular(framed ? 12 : 8),
    );
    canvas.save();
    if (framed) {
      canvas.clipRRect(boundary);
    } else {
      canvas.clipRect(mapRect);
    }
    _drawRoads(canvas, layout);
    _drawParkingBays(canvas, layout);
    _drawStructures(canvas, layout);
    _drawMarkers(canvas, layout);
    _drawTarget(canvas, layout);
    canvas.restore();

    if (framed) {
      final boundaryPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = tokens.borderStrong;
      canvas.drawRRect(boundary, boundaryPaint);
    }
  }

  void _drawRoads(Canvas canvas, ParkingStatusDotMapLayout layout) {
    final road = Paint()
      ..style = PaintingStyle.fill
      ..color = tokens.textSecondary.withOpacity(.13);
    final roadSecondary = Paint()
      ..style = PaintingStyle.fill
      ..color = tokens.info.withOpacity(.16);
    final pillar = Paint()
      ..style = PaintingStyle.fill
      ..color = tokens.textSecondary.withOpacity(.42);
    final wall = Paint()
      ..style = PaintingStyle.fill
      ..color = tokens.textPrimary.withOpacity(.58);
    final road2 = grid.road2Cells.toSet();
    final view = layout.viewport;
    final scale = layout.scale;
    final origin = layout.origin;

    for (var row = view.top; row <= view.bottom; row++) {
      for (var col = view.left; col <= view.right; col++) {
        final index = row * grid.cols + col;
        if (index < 0 || index >= grid.cells.length) continue;
        final cell = grid.cells[index];
        if (cell == ParkingGridCellType.empty) continue;
        final rect = Rect.fromLTWH(
          origin.dx + col * scale,
          origin.dy + row * scale,
          scale,
          scale,
        );
        switch (cell) {
          case ParkingGridCellType.empty:
            break;
          case ParkingGridCellType.road:
            canvas.drawRect(rect, road2.contains(index) ? roadSecondary : road);
            break;
          case ParkingGridCellType.pillar:
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                rect.deflate(math.min(scale * .16, 1.8)),
                const Radius.circular(2),
              ),
              pillar,
            );
            break;
          case ParkingGridCellType.wall:
            canvas.drawRect(rect.deflate(math.min(scale * .05, .7)), wall);
            break;
        }
      }
    }
  }

  void _drawParkingBays(Canvas canvas, ParkingStatusDotMapLayout layout) {
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = tokens.surfaceRaised.withOpacity(.72);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..color = tokens.borderStrong.withOpacity(.72);
    final guide = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = tokens.textSecondary.withOpacity(.28);
    final visibleIds = visibleParkingAreaIds;

    for (final area in grid.parkingAreas) {
      if (visibleIds != null) {
        final id = area.id.trim();
        if (id.isEmpty || !visibleIds.contains(id)) continue;
      }
      final rawRect = layout
          .rectFor(
            GridRect(
              r0: area.r0,
              c0: area.c0,
              r1: area.r1,
              c1: area.c1,
            ),
          )
          .intersect(layout.mapRect);
      if (rawRect.isEmpty || rawRect.width <= 0 || rawRect.height <= 0) {
        continue;
      }
      final inset = math.min(layout.scale * .07, 1.2);
      final insetRect = rawRect.deflate(
        math.min(
          inset,
          math.max(
            0.0,
            math.min(rawRect.width, rawRect.height) / 2 - .05,
          ),
        ),
      );
      final rect = _minimumVisualRect(
        insetRect.isEmpty ? rawRect : insetRect,
        bounds: layout.mapRect,
        minimumExtent: 2.4,
      );
      final radius = Radius.circular(
        math.min(4.0, math.min(rect.width, rect.height) * .12),
      );
      final rrect = RRect.fromRectAndRadius(rect, radius);
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);

      if (math.min(rect.width, rect.height) >= 8) {
        if (rect.width >= rect.height) {
          final x = rect.left + rect.width * .18;
          canvas.drawLine(
            Offset(x, rect.top + rect.height * .22),
            Offset(x, rect.bottom - rect.height * .22),
            guide,
          );
        } else {
          final y = rect.top + rect.height * .18;
          canvas.drawLine(
            Offset(rect.left + rect.width * .22, y),
            Offset(rect.right - rect.width * .22, y),
            guide,
          );
        }
      }
    }
  }

  Rect _minimumVisualRect(
    Rect rect, {
    required Rect bounds,
    required double minimumExtent,
  }) {
    final width = math.max(rect.width, minimumExtent).toDouble();
    final height = math.max(rect.height, minimumExtent).toDouble();
    var left = rect.center.dx - width / 2;
    var top = rect.center.dy - height / 2;

    if (width <= bounds.width) {
      left = left.clamp(bounds.left, bounds.right - width).toDouble();
    } else {
      left = bounds.left;
    }
    if (height <= bounds.height) {
      top = top.clamp(bounds.top, bounds.bottom - height).toDouble();
    } else {
      top = bounds.top;
    }

    return Rect.fromLTWH(
      left,
      top,
      math.min(width, bounds.width).toDouble(),
      math.min(height, bounds.height).toDouble(),
    );
  }

  void _drawStructures(Canvas canvas, ParkingStatusDotMapLayout layout) {
    _drawStructureRects(
      canvas,
      layout,
      grid.towerRects,
      tokens.textSecondary.withOpacity(.48),
      .09,
    );
    _drawStructureRects(
      canvas,
      layout,
      grid.entranceRects,
      tokens.success,
      .12,
    );
    _drawStructureRects(
      canvas,
      layout,
      grid.exitRects,
      tokens.danger,
      .10,
    );

    if (layout.scale >= .7 && layout.mapRect.width >= 220) {
      _drawStructureLabel(canvas, layout, grid.entranceRects, '입구', tokens.success);
      _drawStructureLabel(canvas, layout, grid.exitRects, '출구', tokens.danger);
    }
  }

  void _drawStructureRects(
    Canvas canvas,
    ParkingStatusDotMapLayout layout,
    List<GridRect> rects,
    Color color,
    double fillOpacity,
  ) {
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(fillOpacity);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = color.withOpacity(.82);
    for (final rect in rects) {
      final screen = layout.rectFor(rect);
      if (!screen.overlaps(layout.mapRect)) continue;
      final rrect = RRect.fromRectAndRadius(screen, const Radius.circular(4));
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);
    }
  }

  void _drawStructureLabel(
    Canvas canvas,
    ParkingStatusDotMapLayout layout,
    List<GridRect> rects,
    String text,
    Color color,
  ) {
    if (rects.isEmpty) return;
    final rect = layout.rectFor(rects.first);
    if (!rect.overlaps(layout.mapRect)) return;
    final painter = TextPainter(
      textDirection: TextDirection.ltr,
      textAlign: TextAlign.center,
      maxLines: 1,
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w900,
          height: 1,
        ),
      ),
    )..layout();
    painter.paint(
      canvas,
      Offset(
        rect.center.dx - painter.width / 2,
        rect.center.dy - painter.height / 2,
      ),
    );
  }

  void _drawMarkers(Canvas canvas, ParkingStatusDotMapLayout layout) {
    for (final marker in markers) {
      final rect = layout.rectFor(marker.rect);
      if (!rect.overlaps(layout.mapRect)) continue;
      if (!marker.exact) {
        final region = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = marker.attention || marker.selected ? 2.2 : 1.4
          ..color = (marker.attention || marker.selected
                  ? tokens.accent
                  : tokens.borderStrong)
              .withOpacity(.78);
        canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.deflate(math.min(1.4, layout.scale * .06)),
            const Radius.circular(6),
          ),
          region,
        );
        continue;
      }

      _drawCar(
        canvas,
        rect,
        color: marker.attention || marker.selected
            ? tokens.accent
            : tokens.textSecondary.withOpacity(.7),
        strong: marker.attention || marker.selected,
      );

      if (marker.attention || marker.selected) {
        _drawPulseBay(
          canvas,
          rect,
          color: tokens.accent,
          pulseValue: marker.attention ? pulse : .35,
        );
      }
    }
  }

  void _drawTarget(Canvas canvas, ParkingStatusDotMapLayout layout) {
    final target = targetRect;
    if (target == null) return;
    final rect = layout.rectFor(target);
    if (!rect.overlaps(layout.mapRect)) return;
    final accentFill = Paint()
      ..style = PaintingStyle.fill
      ..color = tokens.accentContainer.withOpacity(.34);
    final accentStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.4
      ..color = tokens.accent;
    final rrect = RRect.fromRectAndRadius(
      rect.deflate(math.min(1.0, layout.scale * .04)),
      const Radius.circular(6),
    );
    canvas.drawRRect(rrect, accentFill);
    canvas.drawRRect(rrect, accentStroke);
    _drawPulseBay(canvas, rect, color: tokens.accent, pulseValue: pulse);
    if (exact) {
      _drawCar(canvas, rect, color: tokens.accent, strong: true);
    }
  }

  void _drawPulseBay(
    Canvas canvas,
    Rect rect, {
    required Color color,
    required double pulseValue,
  }) {
    final value = pulseValue.clamp(0.0, 1.0).toDouble();
    final inflate = 3 + value * 8;
    final halo = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = color.withOpacity(.5 * (1 - value));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.inflate(inflate),
        Radius.circular(7 + value * 4),
      ),
      halo,
    );
  }

  void _drawCar(
    Canvas canvas,
    Rect bay, {
    required Color color,
    required bool strong,
  }) {
    final horizontal = bay.width >= bay.height;
    final insetX = horizontal ? bay.width * .14 : bay.width * .22;
    final insetY = horizontal ? bay.height * .22 : bay.height * .14;
    final body = Rect.fromLTRB(
      bay.left + insetX,
      bay.top + insetY,
      bay.right - insetX,
      bay.bottom - insetY,
    );
    if (body.width <= 2 || body.height <= 2) return;
    final bodyPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(strong ? .9 : .52);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strong ? 1.6 : 1
      ..color = color;
    final glass = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round
      ..color = tokens.canvas.withOpacity(.72);
    final rrect = RRect.fromRectAndRadius(
      body,
      Radius.circular(math.min(5.0, math.min(body.width, body.height) * .28)),
    );
    canvas.drawRRect(rrect, bodyPaint);
    canvas.drawRRect(rrect, outline);

    if (math.min(body.width, body.height) < 8) return;
    if (horizontal) {
      final x = body.left + body.width * .34;
      canvas.drawLine(
        Offset(x, body.top + body.height * .22),
        Offset(x, body.bottom - body.height * .22),
        glass,
      );
    } else {
      final y = body.top + body.height * .34;
      canvas.drawLine(
        Offset(body.left + body.width * .22, y),
        Offset(body.right - body.width * .22, y),
        glass,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ParkingGuidanceMapPainter oldDelegate) {
    return oldDelegate.grid != grid ||
        oldDelegate.markers != markers ||
        oldDelegate.targetRect != targetRect ||
        oldDelegate.viewport != viewport ||
        !setEquals(oldDelegate.visibleParkingAreaIds, visibleParkingAreaIds) ||
        oldDelegate.exact != exact ||
        oldDelegate.pulse != pulse ||
        oldDelegate.framed != framed ||
        oldDelegate.padding != padding ||
        oldDelegate.tokens != tokens;
  }
}
