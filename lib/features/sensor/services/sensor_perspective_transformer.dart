import 'dart:math' as math;
import 'dart:ui';

import 'package:image/image.dart' as img;

import '../applications/sensor_trigger_zone.dart';

class SensorPerspectiveTransformer {
  const SensorPerspectiveTransformer();

  img.Image warp(
    img.Image source,
    SensorTriggerZone zone, {
    required int width,
    required int height,
  }) {
    final destination = img.Image(width: width, height: height);
    final points = zone.entryOrderedPoints
        .map(
          (point) => Offset(
            point.dx * (source.width - 1),
            point.dy * (source.height - 1),
          ),
        )
        .toList(growable: false);
    final p0 = points[0];
    final p1 = points[1];
    final p2 = points[2];
    final p3 = points[3];
    final dx1 = p1.dx - p2.dx;
    final dx2 = p3.dx - p2.dx;
    final dx3 = p0.dx - p1.dx + p2.dx - p3.dx;
    final dy1 = p1.dy - p2.dy;
    final dy2 = p3.dy - p2.dy;
    final dy3 = p0.dy - p1.dy + p2.dy - p3.dy;
    final denominator = dx1 * dy2 - dx2 * dy1;
    double g;
    double h;
    if (dx3.abs() < 1e-9 && dy3.abs() < 1e-9) {
      g = 0;
      h = 0;
    } else if (denominator.abs() < 1e-9) {
      g = 0;
      h = 0;
    } else {
      g = (dx3 * dy2 - dx2 * dy3) / denominator;
      h = (dx1 * dy3 - dx3 * dy1) / denominator;
    }
    final a = p1.dx - p0.dx + g * p1.dx;
    final b = p3.dx - p0.dx + h * p3.dx;
    final c = p0.dx;
    final d = p1.dy - p0.dy + g * p1.dy;
    final e = p3.dy - p0.dy + h * p3.dy;
    final f = p0.dy;
    for (var y = 0; y < height; y++) {
      final v = height <= 1 ? 0.0 : y / (height - 1);
      for (var x = 0; x < width; x++) {
        final u = width <= 1 ? 0.0 : x / (width - 1);
        final w = g * u + h * v + 1.0;
        final sourceX = ((a * u + b * v + c) / w)
            .clamp(0.0, source.width - 1.0)
            .toDouble();
        final sourceY = ((d * u + e * v + f) / w)
            .clamp(0.0, source.height - 1.0)
            .toDouble();
        final sx = sourceX.round().clamp(0, source.width - 1).toInt();
        final sy = sourceY.round().clamp(0, source.height - 1).toInt();
        final pixel = source.getPixel(sx, sy);
        destination.setPixelRgba(
          x,
          y,
          pixel.r,
          pixel.g,
          pixel.b,
          pixel.a,
        );
      }
    }
    return destination;
  }

  double estimatedAspectRatio(SensorTriggerZone zone) {
    final points = zone.entryOrderedPoints;
    final entry = (points[1] - points[0]).distance;
    final far = (points[2] - points[3]).distance;
    final left = (points[3] - points[0]).distance;
    final right = (points[2] - points[1]).distance;
    final horizontal = math.max(0.001, (entry + far) / 2);
    final vertical = math.max(0.001, (left + right) / 2);
    return horizontal / vertical;
  }
}
