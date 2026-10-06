import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../applications/sensor_trigger_zone.dart';

class SensorTriggerPointStore {
  static const String _polygonPrefix = 'sensor_trigger_polygon_v4';
  static const String _legacyZonePrefix = 'sensor_trigger_zone_v3';
  static const String _legacyPointPrefix = 'sensor_trigger_point_v2';

  String _polygonKey(String area) {
    final normalized = area.trim();
    return '${_polygonPrefix}_${Uri.encodeComponent(normalized)}';
  }

  String _legacyZoneKey(String area) {
    final normalized = area.trim();
    return '${_legacyZonePrefix}_${Uri.encodeComponent(normalized)}';
  }

  String _legacyPointKey(String area) {
    final normalized = area.trim();
    return '${_legacyPointPrefix}_${Uri.encodeComponent(normalized)}';
  }

  Future<SensorTriggerZone?> loadZone(String area) async {
    final normalized = area.trim();
    if (normalized.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_polygonKey(normalized));
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final points = <Offset>[];
    for (var index = 1; index <= 4; index++) {
      final x = decoded['p${index}x'];
      final y = decoded['p${index}y'];
      if (x is! num || y is! num) return null;
      points.add(Offset(x.toDouble(), y.toDouble()));
    }
    return SensorTriggerZone.tryFromPoints(points);
  }

  Future<SensorTriggerZone?> loadLegacyZone(String area) async {
    final normalized = area.trim();
    if (normalized.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyZoneKey(normalized));
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final left = decoded['left'];
    final top = decoded['top'];
    final right = decoded['right'];
    final bottom = decoded['bottom'];
    if (left is! num || top is! num || right is! num || bottom is! num) {
      return null;
    }
    return SensorTriggerZone.fromRect(
      Rect.fromLTRB(
        left.toDouble(),
        top.toDouble(),
        right.toDouble(),
        bottom.toDouble(),
      ),
    );
  }

  Future<Offset?> loadLegacyPoint(String area) async {
    final normalized = area.trim();
    if (normalized.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyPointKey(normalized));
    if (raw == null || raw.trim().isEmpty) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) return null;
    final x = decoded['x'];
    final y = decoded['y'];
    if (x is! num || y is! num) return null;
    return Offset(
      x.toDouble().clamp(0.0, 1.0).toDouble(),
      y.toDouble().clamp(0.0, 1.0).toDouble(),
    );
  }

  Future<bool> saveZone(String area, SensorTriggerZone zone) async {
    final normalized = area.trim();
    if (normalized.isEmpty || !zone.isValid) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(
      _polygonKey(normalized),
      jsonEncode(<String, double>{
        'p1x': zone.point1.dx,
        'p1y': zone.point1.dy,
        'p2x': zone.point2.dx,
        'p2y': zone.point2.dy,
        'p3x': zone.point3.dx,
        'p3y': zone.point3.dy,
        'p4x': zone.point4.dx,
        'p4y': zone.point4.dy,
      }),
    );
  }

  Future<bool> clear(String area) async {
    final normalized = area.trim();
    if (normalized.isEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.remove(_polygonKey(normalized));
  }
}
