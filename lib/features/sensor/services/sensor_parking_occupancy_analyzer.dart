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

  SensorEntryChangeAnalysis analyzeEntryChange(
    SensorOccupancyFeature baseline,
    SensorOccupancyFeature current,
  ) {
    if (baseline.width != current.width ||
        baseline.height != current.height ||
        baseline.gray.length != current.gray.length ||
        baseline.edge.length != current.edge.length) {
      throw StateError('Sensor occupancy feature size mismatch.');
    }
    final width = current.width;
    final height = current.height;
    final stripRows = math.max(3, (height * 0.25).round()).clamp(1, height).toInt();
    final frontRows = math.min(2, stripRows);
    final guardColumns =
        math.max(2, (width * 0.125).round()).clamp(1, math.max(1, width ~/ 3)).toInt();
    final coreStart = guardColumns;
    final coreEnd = math.max(coreStart, width - guardColumns);
    final coreWidth = math.max(1, coreEnd - coreStart);
    final columnChanges = List<int>.filled(width, 0);
    final frontColumnChanges = List<int>.filled(width, 0);
    final changedMask = List<bool>.filled(width * stripRows, false);
    var changedCells = 0;
    var frontChangedCells = 0;
    var coreChangedCells = 0;
    var guardChangedCells = 0;
    var maxDepthIndex = -1;
    var differenceSum = 0.0;
    for (var depthIndex = 0; depthIndex < stripRows; depthIndex++) {
      final y = depthIndex;
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        final grayDelta =
            (baseline.gray[index] - current.gray[index]).abs() / 255.0;
        final edgeDelta =
            (baseline.edge[index] - current.edge[index]).abs() / 255.0;
        final cellDifference = grayDelta * 0.35 + edgeDelta * 0.65;
        differenceSum += cellDifference;
        if (cellDifference >= 0.18) {
          changedCells++;
          columnChanges[x]++;
          changedMask[depthIndex * width + x] = true;
          if (depthIndex < frontRows) {
            frontChangedCells++;
            frontColumnChanges[x]++;
          }
          if (x >= coreStart && x < coreEnd) {
            coreChangedCells++;
          } else {
            guardChangedCells++;
          }
          if (depthIndex > maxDepthIndex) {
            maxDepthIndex = depthIndex;
          }
        }
      }
    }
    final minimumColumnChanges = math.max(1, (stripRows * 0.25).ceil());
    var activeColumns = 0;
    var activeCoreColumns = 0;
    for (var x = 0; x < width; x++) {
      final active = frontColumnChanges[x] > 0 ||
          columnChanges[x] >= minimumColumnChanges;
      if (active) {
        activeColumns++;
        if (x >= coreStart && x < coreEnd) {
          activeCoreColumns++;
        }
      }
    }
    final visited = List<bool>.filled(changedMask.length, false);
    final queue = <int>[];
    for (var y = 0; y < frontRows; y++) {
      for (var x = 0; x < width; x++) {
        final localIndex = y * width + x;
        if (changedMask[localIndex] && !visited[localIndex]) {
          visited[localIndex] = true;
          queue.add(localIndex);
        }
      }
    }
    var queueIndex = 0;
    var connectedChangedCells = 0;
    var maxConnectedDepth = -1;
    while (queueIndex < queue.length) {
      final localIndex = queue[queueIndex++];
      final y = localIndex ~/ width;
      final x = localIndex % width;
      connectedChangedCells++;
      if (y > maxConnectedDepth) maxConnectedDepth = y;
      final neighbors = <int>[
        if (x > 0) localIndex - 1,
        if (x + 1 < width) localIndex + 1,
        if (y > 0) localIndex - width,
        if (y + 1 < stripRows) localIndex + width,
      ];
      for (final neighbor in neighbors) {
        if (!visited[neighbor] && changedMask[neighbor]) {
          visited[neighbor] = true;
          queue.add(neighbor);
        }
      }
    }
    final stripCellCount = width * stripRows;
    final frontCellCount = width * frontRows;
    final coreCellCount = coreWidth * stripRows;
    final guardCellCount = math.max(1, stripCellCount - coreCellCount);
    final changedCellRatio = stripCellCount == 0
        ? 0.0
        : (changedCells / stripCellCount).clamp(0.0, 1.0).toDouble();
    final frontChangedCellRatio = frontCellCount == 0
        ? 0.0
        : (frontChangedCells / frontCellCount).clamp(0.0, 1.0).toDouble();
    final spanRatio = width == 0
        ? 0.0
        : (activeColumns / width).clamp(0.0, 1.0).toDouble();
    final depthRatio = maxDepthIndex < 0 || height == 0
        ? 0.0
        : ((maxDepthIndex + 1) / height).clamp(0.0, 1.0).toDouble();
    final meanDifference = stripCellCount == 0
        ? 0.0
        : (differenceSum / stripCellCount).clamp(0.0, 1.0).toDouble();
    final coreChangedCellRatio =
        (coreChangedCells / coreCellCount).clamp(0.0, 1.0).toDouble();
    final sideGuardChangedCellRatio =
        (guardChangedCells / guardCellCount).clamp(0.0, 1.0).toDouble();
    final coreSpanRatio =
        (activeCoreColumns / coreWidth).clamp(0.0, 1.0).toDouble();
    final connectedDepthRatio = maxConnectedDepth < 0 || height == 0
        ? 0.0
        : ((maxConnectedDepth + 1) / height).clamp(0.0, 1.0).toDouble();
    final entryRootedRatio = changedCells == 0
        ? 0.0
        : (connectedChangedCells / changedCells).clamp(0.0, 1.0).toDouble();
    return SensorEntryChangeAnalysis(
      changedCellRatio: changedCellRatio,
      frontChangedCellRatio: frontChangedCellRatio,
      spanRatio: spanRatio,
      depthRatio: depthRatio,
      meanDifference: meanDifference,
      changedCellCount: changedCells,
      activeColumnCount: activeColumns,
      coreChangedCellRatio: coreChangedCellRatio,
      sideGuardChangedCellRatio: sideGuardChangedCellRatio,
      coreSpanRatio: coreSpanRatio,
      connectedDepthRatio: connectedDepthRatio,
      entryRootedRatio: entryRootedRatio,
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
