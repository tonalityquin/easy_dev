import 'dart:math' as math;
import 'dart:ui';

class SensorPolygonGeometry {
  const SensorPolygonGeometry._();

  static double signedArea(List<Offset> points) {
    if (points.length < 3) return 0;
    var sum = 0.0;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum / 2;
  }

  static double area(List<Offset> points) => signedArea(points).abs();

  static Rect bounds(List<Offset> points) {
    if (points.isEmpty) return Rect.zero;
    var left = points.first.dx;
    var top = points.first.dy;
    var right = points.first.dx;
    var bottom = points.first.dy;
    for (final point in points.skip(1)) {
      left = math.min(left, point.dx);
      top = math.min(top, point.dy);
      right = math.max(right, point.dx);
      bottom = math.max(bottom, point.dy);
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static Offset center(List<Offset> points) {
    if (points.isEmpty) return Offset.zero;
    var x = 0.0;
    var y = 0.0;
    for (final point in points) {
      x += point.dx;
      y += point.dy;
    }
    return Offset(x / points.length, y / points.length);
  }

  static bool containsPoint(List<Offset> polygon, Offset point) {
    if (polygon.length < 3) return false;
    var inside = false;
    for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      final a = polygon[i];
      final b = polygon[j];
      final intersects = ((a.dy > point.dy) != (b.dy > point.dy)) &&
          (point.dx <
              (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx);
      if (intersects) inside = !inside;
    }
    return inside;
  }

  static bool isConvex(List<Offset> points) {
    if (points.length != 4) return false;
    double? sign;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      final c = points[(i + 2) % points.length];
      final cross = _cross(a, b, c);
      if (cross.abs() < 1e-8) return false;
      final current = cross.sign;
      sign ??= current;
      if (current != sign) return false;
    }
    return true;
  }

  static bool hasSelfIntersection(List<Offset> points) {
    if (points.length != 4) return true;
    return _segmentsIntersect(points[0], points[1], points[2], points[3]) ||
        _segmentsIntersect(points[1], points[2], points[3], points[0]);
  }

  static double minimumEdgeLength(List<Offset> points) {
    if (points.length < 2) return 0;
    var minimum = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final length = (points[i] - points[(i + 1) % points.length]).distance;
      minimum = math.min(minimum, length);
    }
    return minimum.isFinite ? minimum : 0;
  }

  static List<Offset> clipPolygonWithRect(List<Offset> polygon, Rect rect) {
    var output = List<Offset>.from(polygon);
    output = _clip(output, (p) => p.dx >= rect.left,
        (a, b) => _verticalIntersection(a, b, rect.left));
    output = _clip(output, (p) => p.dx <= rect.right,
        (a, b) => _verticalIntersection(a, b, rect.right));
    output = _clip(output, (p) => p.dy >= rect.top,
        (a, b) => _horizontalIntersection(a, b, rect.top));
    output = _clip(output, (p) => p.dy <= rect.bottom,
        (a, b) => _horizontalIntersection(a, b, rect.bottom));
    return output;
  }

  static List<Offset> _clip(
    List<Offset> input,
    bool Function(Offset) inside,
    Offset Function(Offset, Offset) intersection,
  ) {
    if (input.isEmpty) return const <Offset>[];
    final output = <Offset>[];
    var previous = input.last;
    var previousInside = inside(previous);
    for (final current in input) {
      final currentInside = inside(current);
      if (currentInside) {
        if (!previousInside) output.add(intersection(previous, current));
        output.add(current);
      } else if (previousInside) {
        output.add(intersection(previous, current));
      }
      previous = current;
      previousInside = currentInside;
    }
    return output;
  }

  static Offset _verticalIntersection(Offset a, Offset b, double x) {
    final dx = b.dx - a.dx;
    if (dx.abs() < 1e-9) return Offset(x, a.dy);
    final t = (x - a.dx) / dx;
    return Offset(x, a.dy + (b.dy - a.dy) * t);
  }

  static Offset _horizontalIntersection(Offset a, Offset b, double y) {
    final dy = b.dy - a.dy;
    if (dy.abs() < 1e-9) return Offset(a.dx, y);
    final t = (y - a.dy) / dy;
    return Offset(a.dx + (b.dx - a.dx) * t, y);
  }

  static double _cross(Offset a, Offset b, Offset c) {
    return (b.dx - a.dx) * (c.dy - b.dy) -
        (b.dy - a.dy) * (c.dx - b.dx);
  }

  static bool _segmentsIntersect(Offset a, Offset b, Offset c, Offset d) {
    final o1 = _orientation(a, b, c);
    final o2 = _orientation(a, b, d);
    final o3 = _orientation(c, d, a);
    final o4 = _orientation(c, d, b);
    return o1 != o2 && o3 != o4;
  }

  static int _orientation(Offset a, Offset b, Offset c) {
    final value = (b.dy - a.dy) * (c.dx - b.dx) -
        (b.dx - a.dx) * (c.dy - b.dy);
    if (value.abs() < 1e-9) return 0;
    return value > 0 ? 1 : 2;
  }
}
