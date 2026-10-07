import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'sensor_polygon_geometry.dart';

enum SensorTriggerZoneHandle {
  point1,
  point2,
  point3,
  point4,
}

enum SensorTriggerZoneEdge {
  edge12,
  edge23,
  edge34,
  edge41,
}

@immutable
class SensorTriggerZoneEntryEdge {
  const SensorTriggerZoneEntryEdge({
    required this.type,
    required this.startIndex,
    required this.endIndex,
    required this.oppositeStartIndex,
    required this.oppositeEndIndex,
  });

  final SensorTriggerZoneEdge type;
  final int startIndex;
  final int endIndex;
  final int oppositeStartIndex;
  final int oppositeEndIndex;
}

@immutable
class SensorTriggerZone {
  const SensorTriggerZone._(
    this.points,
    this.entryEdgeType,
  );

  static const double defaultWidth = 0.36;
  static const double defaultHeight = 0.24;
  static const double minimumArea = 0.012;
  static const double minimumEdgeLength = 0.06;
  static const double recognitionExpansionFactor = 0.65;

  final List<Offset> points;
  final SensorTriggerZoneEdge entryEdgeType;

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

  SensorTriggerZoneEntryEdge get entryEdge {
    switch (entryEdgeType) {
      case SensorTriggerZoneEdge.edge12:
        return const SensorTriggerZoneEntryEdge(
          type: SensorTriggerZoneEdge.edge12,
          startIndex: 0,
          endIndex: 1,
          oppositeStartIndex: 3,
          oppositeEndIndex: 2,
        );
      case SensorTriggerZoneEdge.edge23:
        return const SensorTriggerZoneEntryEdge(
          type: SensorTriggerZoneEdge.edge23,
          startIndex: 1,
          endIndex: 2,
          oppositeStartIndex: 0,
          oppositeEndIndex: 3,
        );
      case SensorTriggerZoneEdge.edge34:
        return const SensorTriggerZoneEntryEdge(
          type: SensorTriggerZoneEdge.edge34,
          startIndex: 2,
          endIndex: 3,
          oppositeStartIndex: 1,
          oppositeEndIndex: 0,
        );
      case SensorTriggerZoneEdge.edge41:
        return const SensorTriggerZoneEntryEdge(
          type: SensorTriggerZoneEdge.edge41,
          startIndex: 3,
          endIndex: 0,
          oppositeStartIndex: 2,
          oppositeEndIndex: 1,
        );
    }
  }

  List<Offset> get entryOrderedPoints {
    final edge = entryEdge;
    return List<Offset>.unmodifiable(<Offset>[
      points[edge.startIndex],
      points[edge.endIndex],
      points[edge.oppositeEndIndex],
      points[edge.oppositeStartIndex],
    ]);
  }

  SensorTriggerZone get recognitionZone {
    final edge = entryEdge;
    final next = List<Offset>.from(points);
    next[edge.startIndex] = _expandedPoint(
      points[edge.startIndex],
      points[edge.oppositeStartIndex],
    );
    next[edge.endIndex] = _expandedPoint(
      points[edge.endIndex],
      points[edge.oppositeEndIndex],
    );
    final candidate = SensorTriggerZone.fromPoints(
      next,
      entryEdgeType: entryEdgeType,
    );
    return candidate.isValid ? candidate : this;
  }

  factory SensorTriggerZone.fromCenter(
    Offset center, {
    double width = defaultWidth,
    double height = defaultHeight,
    SensorTriggerZoneEdge entryEdgeType = SensorTriggerZoneEdge.edge12,
  }) {
    final safeWidth = width.clamp(minimumEdgeLength, 1.0).toDouble();
    final safeHeight = height.clamp(minimumEdgeLength, 1.0).toDouble();
    final halfWidth = safeWidth / 2;
    final halfHeight = safeHeight / 2;
    final safeCenter = Offset(
      center.dx.clamp(halfWidth, 1.0 - halfWidth).toDouble(),
      center.dy.clamp(halfHeight, 1.0 - halfHeight).toDouble(),
    );
    return SensorTriggerZone.fromPoints(
      <Offset>[
        Offset(safeCenter.dx - halfWidth, safeCenter.dy - halfHeight),
        Offset(safeCenter.dx + halfWidth, safeCenter.dy - halfHeight),
        Offset(safeCenter.dx + halfWidth, safeCenter.dy + halfHeight),
        Offset(safeCenter.dx - halfWidth, safeCenter.dy + halfHeight),
      ],
      entryEdgeType: entryEdgeType,
    );
  }

  factory SensorTriggerZone.fromRect(
    Rect value, {
    SensorTriggerZoneEdge entryEdgeType = SensorTriggerZoneEdge.edge12,
  }) {
    final rect = Rect.fromLTRB(
      value.left.clamp(0.0, 1.0).toDouble(),
      value.top.clamp(0.0, 1.0).toDouble(),
      value.right.clamp(0.0, 1.0).toDouble(),
      value.bottom.clamp(0.0, 1.0).toDouble(),
    );
    return SensorTriggerZone.fromPoints(
      <Offset>[
        rect.topLeft,
        rect.topRight,
        rect.bottomRight,
        rect.bottomLeft,
      ],
      entryEdgeType: entryEdgeType,
    );
  }

  factory SensorTriggerZone.fromPoints(
    List<Offset> value, {
    SensorTriggerZoneEdge? entryEdgeType,
  }) {
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
    return SensorTriggerZone._(
      List<Offset>.unmodifiable(clamped),
      entryEdgeType ?? inferLegacyEntryEdge(clamped),
    );
  }

  static SensorTriggerZone? tryFromPoints(
    List<Offset> value, {
    SensorTriggerZoneEdge? entryEdgeType,
  }) {
    if (value.length != 4) return null;
    final zone = SensorTriggerZone.fromPoints(
      value,
      entryEdgeType: entryEdgeType,
    );
    return zone.isValid ? zone : null;
  }

  static SensorTriggerZoneEdge inferLegacyEntryEdge(List<Offset> points) {
    if (points.length != 4) return SensorTriggerZoneEdge.edge12;
    final edge12Y = (points[0].dy + points[1].dy) / 2;
    final edge34Y = (points[2].dy + points[3].dy) / 2;
    return edge12Y <= edge34Y
        ? SensorTriggerZoneEdge.edge12
        : SensorTriggerZoneEdge.edge34;
  }

  static SensorTriggerZoneEdge? parseEntryEdge(Object? value) {
    if (value is String) {
      for (final edge in SensorTriggerZoneEdge.values) {
        if (edge.name == value) return edge;
      }
    }
    if (value is num) {
      final index = value.toInt();
      if (index >= 0 && index < SensorTriggerZoneEdge.values.length) {
        return SensorTriggerZoneEdge.values[index];
      }
    }
    return null;
  }

  SensorTriggerZone withEntryEdge(SensorTriggerZoneEdge nextEntryEdge) {
    if (nextEntryEdge == entryEdgeType) return this;
    return SensorTriggerZone.fromPoints(
      points,
      entryEdgeType: nextEntryEdge,
    );
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
      entryEdgeType: entryEdgeType,
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
    final candidate = SensorTriggerZone.fromPoints(
      next,
      entryEdgeType: entryEdgeType,
    );
    return candidate.isValid ? candidate : this;
  }

  bool contains(Offset point) => SensorPolygonGeometry.containsPoint(points, point);

  bool roughlyEquals(
    SensorTriggerZone other, {
    double epsilon = 0.002,
  }) {
    if (entryEdgeType != other.entryEdgeType) return false;
    for (var index = 0; index < 4; index++) {
      if ((points[index].dx - other.points[index].dx).abs() > epsilon ||
          (points[index].dy - other.points[index].dy).abs() > epsilon) {
        return false;
      }
    }
    return true;
  }

  String get fingerprint {
    final coordinates = points
        .expand(
          (point) => <String>[
            point.dx.toStringAsFixed(4),
            point.dy.toStringAsFixed(4),
          ],
        )
        .join(':');
    return '$coordinates:${entryEdgeType.name}';
  }

  Offset _expandedPoint(Offset near, Offset far) {
    final dx = near.dx + (near.dx - far.dx) * recognitionExpansionFactor;
    final dy = near.dy + (near.dy - far.dy) * recognitionExpansionFactor;
    return Offset(
      dx.clamp(0.0, 1.0).toDouble(),
      dy.clamp(0.0, 1.0).toDouble(),
    );
  }
}
