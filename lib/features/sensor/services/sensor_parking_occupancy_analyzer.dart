import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

import '../applications/sensor_occupancy_models.dart';
import '../applications/sensor_trigger_zone.dart';
import 'sensor_perspective_transformer.dart';

class SensorParkingOccupancyAnalyzer {
  const SensorParkingOccupancyAnalyzer({
    SensorPerspectiveTransformer transformer = const SensorPerspectiveTransformer(),
  }) : _transformer = transformer;

  static const int featureWidth = 24;
  static const int featureHeight = 24;
  static const int warpWidth = 96;
  static const int warpHeight = 144;
  static const double enterStructureThreshold = 0.20;
  static const double enterChangedCellThreshold = 0.25;
  static const double clearStructureThreshold = 0.10;
  static const double clearChangedCellThreshold = 0.12;

  final SensorPerspectiveTransformer _transformer;

  Future<SensorOccupancyFeature> extractFeature(
    String path,
    SensorTriggerZone zone,
  ) async {
    if (!zone.isValid) {
      throw StateError('Sensor parking polygon is invalid.');
    }
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Sensor occupancy image decode failed.');
    }
    final oriented = img.bakeOrientation(decoded);
    final warped = _transformer.warp(
      oriented,
      zone,
      width: warpWidth,
      height: warpHeight,
    );
    final resized = img.copyResize(
      warped,
      width: featureWidth,
      height: featureHeight,
      interpolation: img.Interpolation.linear,
    );
    final rawGray = List<double>.filled(featureWidth * featureHeight, 0);
    var sum = 0.0;
    for (var y = 0; y < featureHeight; y++) {
      for (var x = 0; x < featureWidth; x++) {
        final pixel = resized.getPixel(x, y);
        final value = (0.2126 * pixel.r.toDouble() +
                0.7152 * pixel.g.toDouble() +
                0.0722 * pixel.b.toDouble()) /
            255.0;
        rawGray[y * featureWidth + x] = value;
        sum += value;
      }
    }
    final mean = sum / rawGray.length;
    var variance = 0.0;
    for (final value in rawGray) {
      final delta = value - mean;
      variance += delta * delta;
    }
    variance /= rawGray.length;
    final standardDeviation = math.max(0.04, math.sqrt(variance));
    final normalized = List<double>.filled(rawGray.length, 0);
    for (var index = 0; index < rawGray.length; index++) {
      final z = (rawGray[index] - mean) / standardDeviation;
      normalized[index] = (0.5 + z / 6.0).clamp(0.0, 1.0).toDouble();
    }
    final gray = List<int>.filled(normalized.length, 0);
    final edge = List<int>.filled(normalized.length, 0);
    for (var y = 0; y < featureHeight; y++) {
      for (var x = 0; x < featureWidth; x++) {
        final index = y * featureWidth + x;
        gray[index] = (normalized[index] * 255).round().clamp(0, 255).toInt();
        final rightIndex =
            y * featureWidth + (x + 1).clamp(0, featureWidth - 1).toInt();
        final bottomIndex =
            (y + 1).clamp(0, featureHeight - 1).toInt() * featureWidth + x;
        final gradient = ((normalized[index] - normalized[rightIndex]).abs() +
                (normalized[index] - normalized[bottomIndex]).abs()) /
            2.0;
        edge[index] = (gradient * 255).round().clamp(0, 255).toInt();
      }
    }
    return SensorOccupancyFeature(
      width: featureWidth,
      height: featureHeight,
      gray: List<int>.unmodifiable(gray),
      edge: List<int>.unmodifiable(edge),
    );
  }

  SensorOccupancyFeature mergeFeatures(
    List<SensorOccupancyFeature> features,
  ) {
    if (features.isEmpty) {
      throw StateError('Sensor occupancy baseline samples are empty.');
    }
    final first = features.first;
    for (final feature in features.skip(1)) {
      if (feature.width != first.width ||
          feature.height != first.height ||
          feature.gray.length != first.gray.length ||
          feature.edge.length != first.edge.length) {
        throw StateError('Sensor occupancy baseline sample size mismatch.');
      }
    }
    final gray = List<int>.filled(first.gray.length, 0);
    final edge = List<int>.filled(first.edge.length, 0);
    for (var index = 0; index < gray.length; index++) {
      var graySum = 0;
      var edgeSum = 0;
      for (final feature in features) {
        graySum += feature.gray[index];
        edgeSum += feature.edge[index];
      }
      gray[index] = (graySum / features.length).round();
      edge[index] = (edgeSum / features.length).round();
    }
    return SensorOccupancyFeature(
      width: first.width,
      height: first.height,
      gray: List<int>.unmodifiable(gray),
      edge: List<int>.unmodifiable(edge),
    );
  }

  SensorOccupancyAnalysis compare(
    SensorOccupancyFeature baseline,
    SensorOccupancyFeature current,
  ) {
    if (baseline.width != current.width ||
        baseline.height != current.height ||
        baseline.gray.length != current.gray.length ||
        baseline.edge.length != current.edge.length) {
      throw StateError('Sensor occupancy feature size mismatch.');
    }
    var grayDifference = 0.0;
    var edgeDifference = 0.0;
    var changedCells = 0;
    for (var index = 0; index < current.gray.length; index++) {
      final grayDelta =
          (baseline.gray[index] - current.gray[index]).abs() / 255.0;
      final edgeDelta =
          (baseline.edge[index] - current.edge[index]).abs() / 255.0;
      grayDifference += grayDelta;
      edgeDifference += edgeDelta;
      final cellDifference = grayDelta * 0.35 + edgeDelta * 0.65;
      if (cellDifference >= 0.18) changedCells++;
    }
    final count = current.gray.length;
    final meanGrayDifference = grayDifference / count;
    final meanEdgeDifference = edgeDifference / count;
    final structureChangeScore =
        (meanGrayDifference * 0.35 + meanEdgeDifference * 0.65)
            .clamp(0.0, 1.0)
            .toDouble();
    final changedCellRatio =
        (changedCells / count).clamp(0.0, 1.0).toDouble();
    final baselineSimilarity =
        (1.0 - structureChangeScore).clamp(0.0, 1.0).toDouble();
    return SensorOccupancyAnalysis(
      structureChangeScore: structureChangeScore,
      changedCellRatio: changedCellRatio,
      baselineSimilarity: baselineSimilarity,
      enterChanged: structureChangeScore >= enterStructureThreshold &&
          changedCellRatio >= enterChangedCellThreshold,
      clearLike: structureChangeScore <= clearStructureThreshold &&
          changedCellRatio <= clearChangedCellThreshold,
    );
  }
}
