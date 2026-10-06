import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'sensor_polygon_geometry.dart';

enum SensorTriggerZoneHandle {
  point1,
  point2,
  point3,
  point4,
}

@immutable
class SensorTriggerZone {
  const SensorTriggerZone._(this.points);

  static const double defaultWidth = 0.36;
  static const double defaultHeight = 0.24;
  static const double minimumArea = 0.012;
  static const double minimumEdgeLength = 0.06;
  static const double recognitionExpansionFactor = 0.65;

  final List<Offset> points;

  Offset get point1 => points[0];
  Offset get point2 => points[1];
  Offset get point3 => points[2];
  Offset get point4 => points[3];
  Offset get center => SensorPolygonGeometry.center(points);
  Rect get rect => SensorPolygonGeometry.bounds(points);
  double get left => rect.left;
  double get top => rect.top;
  double get right => rect.right;
  double get bottom => rect.bottom;
  double get width => rect.width;
  double get height => rect.height;
  double get area => SensorPolygonGeometry.area(points);
  double get minEdge => SensorPolygonGeometry.minimumEdgeLength(points);
  bool get isConvex => SensorPolygonGeometry.isConvex(points);
  bool get selfIntersecting => SensorPolygonGeometry.hasSelfIntersection(points);
  bool get isValid =>
      points.length == 4 &&
      !selfIntersecting &&
      isConvex &&
      area >= minimumArea &&
      minEdge >= minimumEdgeLength &&
      points.every((point) =>
          point.dx >= 0 && point.dx <= 1 && point.dy >= 0 && point.dy <= 1);

  SensorTriggerZone get recognitionZone {
    final edge12Y = (point1.dy + point2.dy) / 2;
    final edge34Y = (point3.dy + point4.dy) / 2;
    final next = List<Offset>.from(points);
    if (edge12Y <= edge34Y) {
      next[0] = _expandedPoint(point1, point4);
      next[1] = _expandedPoint(point2, point3);
    } else {
      next[2] = _expandedPoint(point3, point2);
      next[3] = _expandedPoint(point4, point1);
    }
    final candidate = SensorTriggerZone.fromPoints(next);
    return candidate.isValid ? candidate : this;
  }

  factory SensorTriggerZone.fromCenter(
    Offset center, {
    double width = defaultWidth,
    double height = defaultHeight,
  }) {
    final safeWidth = width.clamp(minimumEdgeLength, 1.0).toDouble();
    final safeHeight = height.clamp(minimumEdgeLength, 1.0).toDouble();
    final halfWidth = safeWidth / 2;
    final halfHeight = safeHeight / 2;
    final safeCenter = Offset(
      center.dx.clamp(halfWidth, 1.0 - halfWidth).toDouble(),
      center.dy.clamp(halfHeight, 1.0 - halfHeight).toDouble(),
    );
    return SensorTriggerZone.fromPoints(<Offset>[
      Offset(safeCenter.dx - halfWidth, safeCenter.dy - halfHeight),
      Offset(safeCenter.dx + halfWidth, safeCenter.dy - halfHeight),
      Offset(safeCenter.dx + halfWidth, safeCenter.dy + halfHeight),
      Offset(safeCenter.dx - halfWidth, safeCenter.dy + halfHeight),
    ]);
  }

  factory SensorTriggerZone.fromRect(Rect value) {
    final rect = Rect.fromLTRB(
      value.left.clamp(0.0, 1.0).toDouble(),
      value.top.clamp(0.0, 1.0).toDouble(),
      value.right.clamp(0.0, 1.0).toDouble(),
      value.bottom.clamp(0.0, 1.0).toDouble(),
    );
    return SensorTriggerZone.fromPoints(<Offset>[
      rect.topLeft,
      rect.topRight,
      rect.bottomRight,
      rect.bottomLeft,
    ]);
  }

  factory SensorTriggerZone.fromPoints(List<Offset> value) {
    if (value.length != 4) {
      throw ArgumentError.value(value.length, 'points.length');
    }
    final clamped = value
        .map(
          (point) => Offset(
            point.dx.clamp(0.0, 1.0).toDouble(),
            point.dy.clamp(0.0, 1.0).toDouble(),
          ),
        )
        .toList(growable: false);
    return SensorTriggerZone._(List<Offset>.unmodifiable(clamped));
  }

  static SensorTriggerZone? tryFromPoints(List<Offset> value) {
    if (value.length != 4) return null;
    final zone = SensorTriggerZone.fromPoints(value);
    return zone.isValid ? zone : null;
  }

  SensorTriggerZone moveCenter(Offset nextCenter) {
    final delta = nextCenter - center;
    return moveBy(delta);
  }

  SensorTriggerZone moveBy(Offset delta) {
    var dx = delta.dx;
    var dy = delta.dy;
    final bounds = rect;
    if (bounds.left + dx < 0) dx = -bounds.left;
    if (bounds.right + dx > 1) dx = 1 - bounds.right;
    if (bounds.top + dy < 0) dy = -bounds.top;
    if (bounds.bottom + dy > 1) dy = 1 - bounds.bottom;
    return SensorTriggerZone.fromPoints(
      points.map((point) => point + Offset(dx, dy)).toList(growable: false),
    );
  }

  SensorTriggerZone resizeCorner(
    SensorTriggerZoneHandle handle,
    Offset cameraPoint,
  ) {
    final index = handle.index;
    final next = List<Offset>.from(points);
    next[index] = Offset(
      cameraPoint.dx.clamp(0.0, 1.0).toDouble(),
      cameraPoint.dy.clamp(0.0, 1.0).toDouble(),
    );
    final candidate = SensorTriggerZone.fromPoints(next);
    return candidate.isValid ? candidate : this;
  }

  bool contains(Offset point) => SensorPolygonGeometry.containsPoint(points, point);

  bool roughlyEquals(
    SensorTriggerZone other, {
    double epsilon = 0.002,
  }) {
    for (var index = 0; index < 4; index++) {
      if ((points[index].dx - other.points[index].dx).abs() > epsilon ||
          (points[index].dy - other.points[index].dy).abs() > epsilon) {
        return false;
      }
    }
    return true;
  }

  String get fingerprint => points
      .expand(
        (point) => <String>[
          point.dx.toStringAsFixed(4),
          point.dy.toStringAsFixed(4),
        ],
      )
      .join(':');

  Offset _expandedPoint(Offset near, Offset far) {
    final dx = near.dx + (near.dx - far.dx) * recognitionExpansionFactor;
    final dy = near.dy + (near.dy - far.dy) * recognitionExpansionFactor;
    return Offset(
      dx.clamp(0.0, 1.0).toDouble(),
      dy.clamp(0.0, 1.0).toDouble(),
    );
  }
}
