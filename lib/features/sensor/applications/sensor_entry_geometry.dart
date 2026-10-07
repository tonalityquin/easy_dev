import 'dart:ui';

import 'sensor_trigger_zone.dart';

class SensorEntryBandGeometry {
  const SensorEntryBandGeometry({
    required this.entryStart,
    required this.entryEnd,
    required this.farStart,
    required this.farEnd,
  });

  static const double stripDepth = 0.25;
  static const double deepLineDepth = 0.16;
  static const double sideGuardRatio = 0.125;

  final Offset entryStart;
  final Offset entryEnd;
  final Offset farStart;
  final Offset farEnd;

  factory SensorEntryBandGeometry.fromZone(SensorTriggerZone zone) {
    final edge = zone.entryEdge;
    return SensorEntryBandGeometry(
      entryStart: zone.points[edge.startIndex],
      entryEnd: zone.points[edge.endIndex],
      farStart: zone.points[edge.oppositeStartIndex],
      farEnd: zone.points[edge.oppositeEndIndex],
    );
  }

  List<Offset> lineAt(double depth) {
    return <Offset>[
      _project(entryStart, farStart, depth),
      _project(entryEnd, farEnd, depth),
    ];
  }

  List<Offset> band(double fromDepth, double toDepth) {
    final from = lineAt(fromDepth);
    final to = lineAt(toDepth);
    return <Offset>[from[0], from[1], to[1], to[0]];
  }

  List<Offset> lateralLine(double ratio) {
    final entry = lineAt(0);
    final inner = lineAt(stripDepth);
    return <Offset>[
      Offset.lerp(entry[0], entry[1], ratio)!,
      Offset.lerp(inner[0], inner[1], ratio)!,
    ];
  }

  List<Offset> get entryLine => lineAt(0);
  List<Offset> get entryBand => band(0, stripDepth);
  List<Offset> get deepLine => lineAt(deepLineDepth);
  List<Offset> get leftGuardLine => lateralLine(sideGuardRatio);
  List<Offset> get rightGuardLine => lateralLine(1 - sideGuardRatio);

  Offset _project(Offset near, Offset far, double depth) {
    return near + (far - near) * depth;
  }
}
