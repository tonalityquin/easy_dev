import 'package:flutter/foundation.dart';

import 'sensor_trigger_zone.dart';

@immutable
class SensorOccupancyFeature {
  const SensorOccupancyFeature({
    required this.width,
    required this.height,
    required this.gray,
    required this.edge,
  });

  final int width;
  final int height;
  final List<int> gray;
  final List<int> edge;
}

@immutable
class SensorOccupancyBaseline {
  const SensorOccupancyBaseline({
    required this.area,
    required this.zone,
    required this.feature,
    required this.savedAt,
  });

  final String area;
  final SensorTriggerZone zone;
  final SensorOccupancyFeature feature;
  final DateTime savedAt;
}

@immutable
class SensorOccupancyAnalysis {
  const SensorOccupancyAnalysis({
    required this.structureChangeScore,
    required this.changedCellRatio,
    required this.baselineSimilarity,
    required this.enterChanged,
    required this.clearLike,
  });

  final double structureChangeScore;
  final double changedCellRatio;
  final double baselineSimilarity;
  final bool enterChanged;
  final bool clearLike;
}

@immutable
class SensorOccupancyEvidence {
  const SensorOccupancyEvidence({
    required this.baselineReady,
    required this.occupiedCandidate,
    required this.clearCandidate,
    required this.structureChangeScore,
    required this.changedCellRatio,
    required this.baselineSimilarity,
    required this.mlMatched,
    required this.mlBottomCenterMatched,
    required this.mlObjectCount,
    required this.mlMatchedCount,
    required this.mlPolygonCoverage,
    required this.mlBoundingBoxAreaRatio,
    required this.reason,
  });

  final bool baselineReady;
  final bool occupiedCandidate;
  final bool clearCandidate;
  final double structureChangeScore;
  final double changedCellRatio;
  final double baselineSimilarity;
  final bool mlMatched;
  final bool mlBottomCenterMatched;
  final int mlObjectCount;
  final int mlMatchedCount;
  final double mlPolygonCoverage;
  final double mlBoundingBoxAreaRatio;
  final String reason;
}
