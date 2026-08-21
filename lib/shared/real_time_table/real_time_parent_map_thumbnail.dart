import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../design_system/common_ui/common_ui_theme.dart';
import '../../features/location/domain/models/grid_rect.dart';
import '../../features/location/domain/models/parking_grid_model.dart';
import '../parking_dot_map/parking_status_dot_map_surface.dart';

class RealTimeParentMapThumbnail extends StatelessWidget {
  const RealTimeParentMapThumbnail({
    super.key,
    required this.grid,
    required this.childRects,
    required this.selected,
  });

  final ParkingGridModel? grid;
  final List<GridRect> childRects;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    Widget preview;
    final resolvedGrid = grid;
    if (resolvedGrid != null &&
        resolvedGrid.rows > 0 &&
        resolvedGrid.cols > 0) {
      preview = Stack(
        fit: StackFit.expand,
        children: [
          ParkingStatusDotMapSurface(
            grid: resolvedGrid,
            framed: false,
            padding: 2,
          ),
          if (childRects.isNotEmpty)
            CustomPaint(
              painter: _ParentChildRectGridOverlayPainter(
                grid: resolvedGrid,
                rects: childRects,
                color: selected ? tokens.accent : tokens.textSecondary,
                selected: selected,
              ),
              child: const SizedBox.expand(),
            ),
        ],
      );
    } else if (childRects.isNotEmpty) {
      preview = CustomPaint(
        painter: _ParentChildRectThumbnailPainter(
          rects: childRects,
          color: selected ? tokens.accent : tokens.textSecondary,
          selected: selected,
        ),
        child: const SizedBox.expand(),
      );
    } else {
      preview = Center(
        child: Icon(
          Icons.local_parking_outlined,
          size: 24,
          color: selected
              ? tokens.accent
              : tokens.textSecondary.withOpacity(.68),
        ),
      );
    }
    return AnimatedOpacity(
      opacity: selected ? 1 : .82,
      duration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 140),
      curve: Curves.easeOutCubic,
      child: preview,
    );
  }
}

class _ParentChildRectGridOverlayPainter extends CustomPainter {
  const _ParentChildRectGridOverlayPainter({
    required this.grid,
    required this.rects,
    required this.color,
    required this.selected,
  });

  final ParkingGridModel grid;
  final List<GridRect> rects;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = ParkingStatusDotMapLayout.resolve(
      size: size,
      grid: grid,
      padding: 2,
    );
    if (layout == null) return;
    canvas.save();
    canvas.clipRect(layout.mapRect);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(selected ? .055 : .025);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.15 : .8
      ..color = color.withOpacity(selected ? .58 : .30);
    for (final raw in rects) {
      final screen = layout.rectFor(raw.normalized());
      final radius = math
          .min(2.5, math.min(screen.width, screen.height) * .14)
          .toDouble();
      final rrect = RRect.fromRectAndRadius(
        screen,
        Radius.circular(radius),
      );
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(
    covariant _ParentChildRectGridOverlayPainter oldDelegate,
  ) {
    return oldDelegate.grid != grid ||
        oldDelegate.rects != rects ||
        oldDelegate.color != color ||
        oldDelegate.selected != selected;
  }
}

class _ParentChildRectThumbnailPainter extends CustomPainter {
  const _ParentChildRectThumbnailPainter({
    required this.rects,
    required this.color,
    required this.selected,
  });

  final List<GridRect> rects;
  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || rects.isEmpty) return;
    final normalized = rects.map((rect) => rect.normalized()).toList();
    var top = normalized.first.top;
    var left = normalized.first.left;
    var bottom = normalized.first.bottom;
    var right = normalized.first.right;
    for (final rect in normalized.skip(1)) {
      top = math.min(top, rect.top).toInt();
      left = math.min(left, rect.left).toInt();
      bottom = math.max(bottom, rect.bottom).toInt();
      right = math.max(right, rect.right).toInt();
    }
    final logicalWidth = math.max(1, right - left + 1).toDouble();
    final logicalHeight = math.max(1, bottom - top + 1).toDouble();
    const padding = 2.0;
    final availableWidth = math.max(1.0, size.width - padding * 2).toDouble();
    final availableHeight =
        math.max(1.0, size.height - padding * 2).toDouble();
    final scale = math.min(
      availableWidth / logicalWidth,
      availableHeight / logicalHeight,
    );
    final drawnWidth = logicalWidth * scale;
    final drawnHeight = logicalHeight * scale;
    final origin = Offset(
      padding + (availableWidth - drawnWidth) / 2 - left * scale,
      padding + (availableHeight - drawnHeight) / 2 - top * scale,
    );
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(selected ? .10 : .055);
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = selected ? 1.4 : 1
      ..color = color.withOpacity(selected ? .82 : .48);
    for (final rect in normalized) {
      final screen = Rect.fromLTRB(
        origin.dx + rect.left * scale,
        origin.dy + rect.top * scale,
        origin.dx + (rect.right + 1) * scale,
        origin.dy + (rect.bottom + 1) * scale,
      );
      final radius = math
          .min(3.0, math.min(screen.width, screen.height) * .18)
          .toDouble();
      final rrect = RRect.fromRectAndRadius(
        screen,
        Radius.circular(radius),
      );
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);
    }
  }

  @override
  bool shouldRepaint(covariant _ParentChildRectThumbnailPainter oldDelegate) {
    return oldDelegate.rects != rects ||
        oldDelegate.color != color ||
        oldDelegate.selected != selected;
  }
}
