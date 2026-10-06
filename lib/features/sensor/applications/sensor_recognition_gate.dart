import '../services/sensor_object_detector_service.dart';
import 'sensor_occupancy_models.dart';

class SensorRecognitionDecision {
  const SensorRecognitionDecision({
    required this.candidate,
    required this.weakOccupancyEvidence,
    required this.strongMlEvidence,
    required this.spatialEntryEvidence,
    required this.reason,
  });

  final bool candidate;
  final bool weakOccupancyEvidence;
  final bool strongMlEvidence;
  final bool spatialEntryEvidence;
  final String reason;
}

class SensorRecognitionGate {
  const SensorRecognitionGate();

  static const double weakStructureThreshold = 0.10;
  static const double weakChangedCellThreshold = 0.11;
  static const double strongMlCoverageThreshold = 0.70;
  static const double strongMlBoundingBoxThreshold = 0.14;

  SensorRecognitionDecision evaluate(
    SensorOccupancyAnalysis occupancy,
    SensorObjectZoneMatch mlMatch,
  ) {
    final weakOccupancyEvidence =
        occupancy.structureChangeScore >= weakStructureThreshold ||
            occupancy.changedCellRatio >= weakChangedCellThreshold;
    final strongMlEvidence =
        mlMatch.maxPolygonCoverage >= strongMlCoverageThreshold &&
            mlMatch.maxBoundingBoxAreaRatio >= strongMlBoundingBoxThreshold;
    final spatialEntryEvidence = mlMatch.bottomCenterMatched;
    final candidate = mlMatch.matched &&
        (weakOccupancyEvidence || strongMlEvidence || spatialEntryEvidence);
    final reason = candidate
        ? spatialEntryEvidence
            ? 'ml_spatial_entry'
            : strongMlEvidence
                ? 'ml_strong'
                : 'ml_with_baseline_change'
        : mlMatch.matched
            ? 'ml_without_entry_evidence'
            : weakOccupancyEvidence
                ? 'baseline_change_only'
                : occupancy.clearLike
                    ? 'baseline_clear'
                    : 'hold';
    return SensorRecognitionDecision(
      candidate: candidate,
      weakOccupancyEvidence: weakOccupancyEvidence,
      strongMlEvidence: strongMlEvidence,
      spatialEntryEvidence: spatialEntryEvidence,
      reason: reason,
    );
  }
}
