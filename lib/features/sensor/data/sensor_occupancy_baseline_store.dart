import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';

import '../applications/sensor_occupancy_models.dart';
import '../applications/sensor_trigger_zone.dart';

class SensorOccupancyBaselineStore {
  static const String _prefix = 'sensor_occupancy_baseline_v3';

  String _key(String area) {
    return '${_prefix}_${Uri.encodeComponent(area.trim())}';
  }

  Future<SensorOccupancyBaseline?> load(String area) async {
    final normalized = area.trim();
    if (normalized.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(normalized));
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
    final entryEdge = SensorTriggerZone.parseEntryEdge(decoded['entryEdge']);
    if (entryEdge == null) return null;
    final zone = SensorTriggerZone.tryFromPoints(
      points,
      entryEdgeType: entryEdge,
    );
    if (zone == null) return null;
    final width = decoded['width'];
    final height = decoded['height'];
    final grayBase64 = decoded['gray'];
    final edgeBase64 = decoded['edge'];
    final savedAtRaw = decoded['savedAt'];
    if (width is! num ||
        height is! num ||
        grayBase64 is! String ||
        edgeBase64 is! String ||
        savedAtRaw is! String) {
      return null;
    }
    final gray = base64Decode(grayBase64);
    final edge = base64Decode(edgeBase64);
    final featureWidth = width.toInt();
    final featureHeight = height.toInt();
    if (featureWidth <= 0 ||
        featureHeight <= 0 ||
        gray.length != featureWidth * featureHeight ||
        edge.length != featureWidth * featureHeight) {
      return null;
    }
    final savedAt = DateTime.tryParse(savedAtRaw);
    if (savedAt == null) return null;
    return SensorOccupancyBaseline(
      area: normalized,
      zone: zone,
      feature: SensorOccupancyFeature(
        width: featureWidth,
        height: featureHeight,
        gray: List<int>.unmodifiable(gray),
        edge: List<int>.unmodifiable(edge),
      ),
      savedAt: savedAt,
    );
  }

  Future<bool> save(SensorOccupancyBaseline baseline) async {
    final normalized = baseline.area.trim();
    if (normalized.isEmpty || !baseline.zone.isValid) return false;
    final prefs = await SharedPreferences.getInstance();
    return prefs.setString(
      _key(normalized),
      jsonEncode(<String, Object>{
        'p1x': baseline.zone.point1.dx,
        'p1y': baseline.zone.point1.dy,
        'p2x': baseline.zone.point2.dx,
        'p2y': baseline.zone.point2.dy,
        'p3x': baseline.zone.point3.dx,
        'p3y': baseline.zone.point3.dy,
        'p4x': baseline.zone.point4.dx,
        'p4y': baseline.zone.point4.dy,
        'entryEdge': baseline.zone.entryEdgeType.name,
        'width': baseline.feature.width,
        'height': baseline.feature.height,
        'gray': base64Encode(Uint8List.fromList(baseline.feature.gray)),
        'edge': base64Encode(Uint8List.fromList(baseline.feature.edge)),
        'savedAt': baseline.savedAt.toIso8601String(),
      }),
    );
  }

  Future<bool> clear(String area) async {
    final normalized = area.trim();
    if (normalized.isEmpty) return true;
    final prefs = await SharedPreferences.getInstance();
    return prefs.remove(_key(normalized));
  }
}
