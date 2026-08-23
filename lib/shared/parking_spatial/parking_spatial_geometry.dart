import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/location/domain/models/grid_rect.dart';
import '../../features/location/domain/models/location_model.dart';
import '../../features/location/domain/models/parking_grid_model.dart';

const double parkingSpatialMinimumTouchTarget = 44.0;

GridRect? resolveParkingSpatialChildRect(
  LocationModel child,
  ParkingGridModel grid,
) {
  GridRect? raw = child.childRect?.normalized();
  if (raw == null && child.childSlots.isNotEmpty) {
    var top = child.childSlots.first.r0;
    var left = child.childSlots.first.c0;
    var bottom = child.childSlots.first.r1;
    var right = child.childSlots.first.c1;
    for (final slot in child.childSlots.skip(1)) {
      top = math.min(top, math.min(slot.r0, slot.r1));
      left = math.min(left, math.min(slot.c0, slot.c1));
      bottom = math.max(bottom, math.max(slot.r0, slot.r1));
      right = math.max(right, math.max(slot.c0, slot.c1));
    }
    raw = GridRect(r0: top, c0: left, r1: bottom, c1: right);
  }
  if (raw == null || grid.rows <= 0 || grid.cols <= 0) return null;
  final normalized = raw.normalized();
  final top = normalized.top.clamp(0, grid.rows - 1).toInt();
  final left = normalized.left.clamp(0, grid.cols - 1).toInt();
  final bottom = normalized.bottom.clamp(0, grid.rows - 1).toInt();
  final right = normalized.right.clamp(0, grid.cols - 1).toInt();
  if (bottom < top || right < left) return null;
  return GridRect(r0: top, c0: left, r1: bottom, c1: right);
}

Rect parkingSpatialMinimumHitRect(
  Rect source,
  Rect bounds,
  double minimum,
) {
  if (!bounds.left.isFinite ||
      !bounds.top.isFinite ||
      !bounds.right.isFinite ||
      !bounds.bottom.isFinite ||
      bounds.isEmpty) {
    return Rect.zero;
  }
  final safeMinimum = minimum.isFinite ? math.max(0.0, minimum) : 0.0;
  final sourceWidth = source.width.isFinite ? math.max(0.0, source.width) : 0.0;
  final sourceHeight = source.height.isFinite ? math.max(0.0, source.height) : 0.0;
  final width = math.min(
    bounds.width,
    math.max(safeMinimum, sourceWidth),
  );
  final height = math.min(
    bounds.height,
    math.max(safeMinimum, sourceHeight),
  );
  final desiredLeft = source.center.dx.isFinite
      ? source.center.dx - width / 2
      : bounds.left;
  final desiredTop = source.center.dy.isFinite
      ? source.center.dy - height / 2
      : bounds.top;
  final maxLeft = bounds.right - width;
  final maxTop = bounds.bottom - height;
  final left = maxLeft <= bounds.left
      ? bounds.left
      : desiredLeft.clamp(bounds.left, maxLeft).toDouble();
  final top = maxTop <= bounds.top
      ? bounds.top
      : desiredTop.clamp(bounds.top, maxTop).toDouble();
  return Rect.fromLTWH(left, top, width, height);
}

(Rect, Rect) parkingSpatialSeparateHitRects({
  required Rect firstVisual,
  required Rect secondVisual,
  required Rect firstHit,
  required Rect secondHit,
}) {
  if (firstVisual.right <= secondVisual.left) {
    final boundary = (firstVisual.right + secondVisual.left) / 2;
    return (
      Rect.fromLTRB(
        firstHit.left,
        firstHit.top,
        math.max(firstVisual.right, math.min(firstHit.right, boundary)),
        firstHit.bottom,
      ),
      Rect.fromLTRB(
        math.min(secondVisual.left, math.max(secondHit.left, boundary)),
        secondHit.top,
        secondHit.right,
        secondHit.bottom,
      ),
    );
  }
  if (secondVisual.right <= firstVisual.left) {
    final boundary = (secondVisual.right + firstVisual.left) / 2;
    return (
      Rect.fromLTRB(
        math.min(firstVisual.left, math.max(firstHit.left, boundary)),
        firstHit.top,
        firstHit.right,
        firstHit.bottom,
      ),
      Rect.fromLTRB(
        secondHit.left,
        secondHit.top,
        math.max(secondVisual.right, math.min(secondHit.right, boundary)),
        secondHit.bottom,
      ),
    );
  }
  if (firstVisual.bottom <= secondVisual.top) {
    final boundary = (firstVisual.bottom + secondVisual.top) / 2;
    return (
      Rect.fromLTRB(
        firstHit.left,
        firstHit.top,
        firstHit.right,
        math.max(firstVisual.bottom, math.min(firstHit.bottom, boundary)),
      ),
      Rect.fromLTRB(
        secondHit.left,
        math.min(secondVisual.top, math.max(secondHit.top, boundary)),
        secondHit.right,
        secondHit.bottom,
      ),
    );
  }
  if (secondVisual.bottom <= firstVisual.top) {
    final boundary = (secondVisual.bottom + firstVisual.top) / 2;
    return (
      Rect.fromLTRB(
        firstHit.left,
        math.min(firstVisual.top, math.max(firstHit.top, boundary)),
        firstHit.right,
        firstHit.bottom,
      ),
      Rect.fromLTRB(
        secondHit.left,
        secondHit.top,
        secondHit.right,
        math.max(secondVisual.bottom, math.min(secondHit.bottom, boundary)),
      ),
    );
  }
  final dx = secondVisual.center.dx - firstVisual.center.dx;
  final dy = secondVisual.center.dy - firstVisual.center.dy;
  if (dx.abs() >= dy.abs()) {
    final boundary = (firstVisual.center.dx + secondVisual.center.dx) / 2;
    if (dx >= 0) {
      return (
        Rect.fromLTRB(
          firstHit.left,
          firstHit.top,
          math.max(firstHit.left, math.min(firstHit.right, boundary)),
          firstHit.bottom,
        ),
        Rect.fromLTRB(
          math.min(secondHit.right, math.max(secondHit.left, boundary)),
          secondHit.top,
          secondHit.right,
          secondHit.bottom,
        ),
      );
    }
    return (
      Rect.fromLTRB(
        math.min(firstHit.right, math.max(firstHit.left, boundary)),
        firstHit.top,
        firstHit.right,
        firstHit.bottom,
      ),
      Rect.fromLTRB(
        secondHit.left,
        secondHit.top,
        math.max(secondHit.left, math.min(secondHit.right, boundary)),
        secondHit.bottom,
      ),
    );
  }
  final boundary = (firstVisual.center.dy + secondVisual.center.dy) / 2;
  if (dy >= 0) {
    return (
      Rect.fromLTRB(
        firstHit.left,
        firstHit.top,
        firstHit.right,
        math.max(firstHit.top, math.min(firstHit.bottom, boundary)),
      ),
      Rect.fromLTRB(
        secondHit.left,
        math.min(secondHit.bottom, math.max(secondHit.top, boundary)),
        secondHit.right,
        secondHit.bottom,
      ),
    );
  }
  return (
    Rect.fromLTRB(
      firstHit.left,
      math.min(firstHit.bottom, math.max(firstHit.top, boundary)),
      firstHit.right,
      firstHit.bottom,
    ),
    Rect.fromLTRB(
      secondHit.left,
      secondHit.top,
      secondHit.right,
      math.max(secondHit.top, math.min(secondHit.bottom, boundary)),
    ),
  );
}

List<Rect> resolveParkingSpatialHitRects({
  required List<Rect> visualRects,
  required Rect bounds,
  double minimum = parkingSpatialMinimumTouchTarget,
}) {
  final hits = <Rect>[
    for (final visual in visualRects)
      parkingSpatialMinimumHitRect(visual, bounds, minimum),
  ];
  for (var i = 0; i < hits.length; i++) {
    for (var j = i + 1; j < hits.length; j++) {
      if (!hits[i].overlaps(hits[j])) continue;
      final separated = parkingSpatialSeparateHitRects(
        firstVisual: visualRects[i],
        secondVisual: visualRects[j],
        firstHit: hits[i],
        secondHit: hits[j],
      );
      hits[i] = separated.$1.intersect(bounds);
      hits[j] = separated.$2.intersect(bounds);
    }
  }
  return hits;
}
