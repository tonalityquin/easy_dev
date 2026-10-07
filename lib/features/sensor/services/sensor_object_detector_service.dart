import 'dart:ui';

import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';

import '../applications/sensor_debug_trace.dart';
import '../applications/sensor_polygon_geometry.dart';
import '../applications/sensor_trigger_zone.dart';
import 'sensor_camera_image_geometry_reader.dart';

class SensorObjectZoneEvidence {
  const SensorObjectZoneEvidence({
    required this.index,
    required this.boundingBox,
    required this.bottomCenter,
    required this.polygonCoverage,
    required this.boundingBoxAreaRatio,
    required this.bottomCenterInside,
    required this.closeOverlap,
    required this.largeOverlap,
    required this.bottomCenterEntry,
  });

  final int index;
  final Rect boundingBox;
  final Offset bottomCenter;
  final double polygonCoverage;
  final double boundingBoxAreaRatio;
  final bool bottomCenterInside;
  final bool closeOverlap;
  final bool largeOverlap;
  final bool bottomCenterEntry;

  bool get matched => closeOverlap || largeOverlap || bottomCenterEntry;
}

class SensorObjectZoneMatch {
  const SensorObjectZoneMatch({
    required this.matchedIndexes,
    required this.bottomCenterMatchedIndexes,
    required this.evidences,
    required this.maxPolygonCoverage,
    required this.maxBoundingBoxAreaRatio,
  });

  final List<int> matchedIndexes;
  final List<int> bottomCenterMatchedIndexes;
  final List<SensorObjectZoneEvidence> evidences;
  final double maxPolygonCoverage;
  final double maxBoundingBoxAreaRatio;

  bool get matched => matchedIndexes.isNotEmpty;
  bool get bottomCenterMatched => bottomCenterMatchedIndexes.isNotEmpty;
  int get matchedCount => matchedIndexes.length;
  int get bottomCenterMatchedCount => bottomCenterMatchedIndexes.length;
}

class SensorObjectDetectionResult {
  const SensorObjectDetectionResult({
    required this.detected,
    required this.objectCount,
    required this.elapsedMilliseconds,
    required this.normalizedBoundingBoxes,
    required this.imageWidth,
    required this.imageHeight,
  });

  static const double closePolygonCoverage = 0.45;
  static const double closeBoundingBoxAreaRatio = 0.06;
  static const double largePolygonCoverage = 0.25;
  static const double largeBoundingBoxAreaRatio = 0.12;
  static const double bottomCenterBoundingBoxAreaRatio = 0.06;

  final bool detected;
  final int objectCount;
  final int elapsedMilliseconds;
  final List<Rect> normalizedBoundingBoxes;
  final int imageWidth;
  final int imageHeight;

  SensorObjectZoneMatch matchZone(SensorTriggerZone zone) {
    final polygonArea = zone.area;
    final matches = <int>[];
    final bottomCenterMatches = <int>[];
    final evidences = <SensorObjectZoneEvidence>[];
    var maxPolygonCoverage = 0.0;
    var maxBoundingBoxAreaRatio = 0.0;
    for (var index = 0; index < normalizedBoundingBoxes.length; index++) {
      final box = normalizedBoundingBoxes[index];
      final clipped =
          SensorPolygonGeometry.clipPolygonWithRect(zone.points, box);
      final intersectionArea = SensorPolygonGeometry.area(clipped);
      final polygonCoverage =
          polygonArea <= 0 ? 0.0 : intersectionArea / polygonArea;
      final boxAreaRatio = box.width * box.height;
      final bottomCenter = Offset(box.center.dx, box.bottom);
      final bottomCenterInside = zone.contains(bottomCenter);
      if (polygonCoverage > maxPolygonCoverage) {
        maxPolygonCoverage = polygonCoverage;
      }
      if (polygonCoverage > 0 && boxAreaRatio > maxBoundingBoxAreaRatio) {
        maxBoundingBoxAreaRatio = boxAreaRatio;
      }
      final closeOverlap = polygonCoverage >= closePolygonCoverage &&
          boxAreaRatio >= closeBoundingBoxAreaRatio;
      final largeOverlap = polygonCoverage >= largePolygonCoverage &&
          boxAreaRatio >= largeBoundingBoxAreaRatio;
      final bottomCenterEntry = bottomCenterInside &&
          boxAreaRatio >= bottomCenterBoundingBoxAreaRatio;
      final evidence = SensorObjectZoneEvidence(
        index: index,
        boundingBox: box,
        bottomCenter: bottomCenter,
        polygonCoverage: polygonCoverage.clamp(0.0, 1.0).toDouble(),
        boundingBoxAreaRatio: boxAreaRatio.clamp(0.0, 1.0).toDouble(),
        bottomCenterInside: bottomCenterInside,
        closeOverlap: closeOverlap,
        largeOverlap: largeOverlap,
        bottomCenterEntry: bottomCenterEntry,
      );
      evidences.add(evidence);
      if (bottomCenterEntry) {
        bottomCenterMatches.add(index);
      }
      if (evidence.matched) {
        matches.add(index);
      }
    }
    return SensorObjectZoneMatch(
      matchedIndexes: List<int>.unmodifiable(matches),
      bottomCenterMatchedIndexes:
          List<int>.unmodifiable(bottomCenterMatches),
      evidences: List<SensorObjectZoneEvidence>.unmodifiable(evidences),
      maxPolygonCoverage: maxPolygonCoverage.clamp(0.0, 1.0).toDouble(),
      maxBoundingBoxAreaRatio:
          maxBoundingBoxAreaRatio.clamp(0.0, 1.0).toDouble(),
    );
  }
}

class SensorObjectDetectorService {
  SensorObjectDetectorService({
    SensorCameraImageGeometryReader geometryReader =
        const SensorCameraImageGeometryReader(),
  }) : _geometryReader = geometryReader;

  final SensorCameraImageGeometryReader _geometryReader;
  ObjectDetector? _detector;

  bool get isReady => _detector != null;

  Future<void> initialize() async {
    if (_detector != null) return;
    _detector = ObjectDetector(
      options: ObjectDetectorOptions(
        mode: DetectionMode.single,
        classifyObjects: false,
        multipleObjects: true,
      ),
    );
    SensorDebugTrace.record(
      'SensorObjectDetector',
      'initialized',
      <String, Object?>{
        'mode': DetectionMode.single.name,
        'classifyObjects': false,
        'multipleObjects': true,
      },
    );
  }

  Future<SensorObjectDetectionResult> detectFile(String path) async {
    final detector = _detector;
    if (detector == null) {
      throw StateError('Sensor object detector is not initialized.');
    }
    final stopwatch = Stopwatch()..start();
    final objects = await detector.processImage(InputImage.fromFilePath(path));
    final size = await _geometryReader.readOrientedSize(path);
    final width = size.width.round();
    final height = size.height.round();
    final normalizedBoxes = objects
        .map(
          (object) => _normalizeRect(
            object.boundingBox,
            width: width,
            height: height,
          ),
        )
        .where((rect) => !rect.isEmpty)
        .toList(growable: false);
    stopwatch.stop();
    return SensorObjectDetectionResult(
      detected: objects.isNotEmpty,
      objectCount: objects.length,
      elapsedMilliseconds: stopwatch.elapsedMilliseconds,
      normalizedBoundingBoxes: normalizedBoxes,
      imageWidth: width,
      imageHeight: height,
    );
  }

  Rect _normalizeRect(
    Rect rect, {
    required int width,
    required int height,
  }) {
    final normalizedLeft = (rect.left / width).clamp(0.0, 1.0).toDouble();
    final normalizedTop = (rect.top / height).clamp(0.0, 1.0).toDouble();
    final normalizedRight = (rect.right / width).clamp(0.0, 1.0).toDouble();
    final normalizedBottom = (rect.bottom / height).clamp(0.0, 1.0).toDouble();
    final left = normalizedLeft < normalizedRight
        ? normalizedLeft
        : normalizedRight;
    final right = normalizedLeft < normalizedRight
        ? normalizedRight
        : normalizedLeft;
    final top = normalizedTop < normalizedBottom
        ? normalizedTop
        : normalizedBottom;
    final bottom = normalizedTop < normalizedBottom
        ? normalizedBottom
        : normalizedTop;
    return Rect.fromLTRB(left, top, right, bottom);
  }

  Future<void> close() async {
    final detector = _detector;
    _detector = null;
    if (detector == null) return;
    try {
      await detector.close();
      SensorDebugTrace.record('SensorObjectDetector', 'closed');
    } catch (error) {
      SensorDebugTrace.record(
        'SensorObjectDetector',
        'close_failed',
        <String, Object?>{'error': error},
      );
    }
  }
}
