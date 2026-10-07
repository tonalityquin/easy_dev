import '../services/sensor_object_detector_service.dart';
import 'sensor_occupancy_models.dart';

class SensorRecognitionDecision {
  const SensorRecognitionDecision({
    required this.candidate,
    required this.weakOccupancyEvidence,
    required this.minimumOccupancyEvidence,
    required this.strongMlEvidence,
    required this.spatialEntryEvidence,
    required this.reason,
  });

  final bool candidate;
  final bool weakOccupancyEvidence;
  final bool minimumOccupancyEvidence;
  final bool strongMlEvidence;
  final bool spatialEntryEvidence;
  final String reason;
}

class SensorRecognitionGate {
  const SensorRecognitionGate();

  static const double weakStructureThreshold = 0.10;
  static const double weakChangedCellThreshold = 0.11;
  static const double minimumStrongStructureThreshold = 0.04;
  static const double minimumStrongChangedCellThreshold = 0.05;
  static const double strongMlCoverageThreshold = 0.70;
  static const double strongMlBoundingBoxThreshold = 0.14;

  SensorRecognitionDecision evaluate(
    SensorOccupancyAnalysis occupancy,
    SensorObjectZoneMatch mlMatch,
  ) {
    final weakOccupancyEvidence =
        occupancy.structureChangeScore >= weakStructureThreshold ||
            occupancy.changedCellRatio >= weakChangedCellThreshold;
    final minimumOccupancyEvidence =
        occupancy.structureChangeScore >= minimumStrongStructureThreshold ||
            occupancy.changedCellRatio >= minimumStrongChangedCellThreshold;
    final strongMlEvidence = mlMatch.evidences.any(
      (evidence) =>
          evidence.polygonCoverage >= strongMlCoverageThreshold &&
          evidence.boundingBoxAreaRatio >= strongMlBoundingBoxThreshold,
    );
    final spatialEntryEvidence = mlMatch.bottomCenterMatched;
    final candidate = mlMatch.matched &&
        (weakOccupancyEvidence ||
            (strongMlEvidence && minimumOccupancyEvidence));
    final reason = candidate
        ? strongMlEvidence && !weakOccupancyEvidence
            ? 'ml_strong_with_minimum_baseline_change'
            : spatialEntryEvidence
                ? 'ml_spatial_with_baseline_change'
                : 'ml_with_baseline_change'
        : mlMatch.matched
            ? strongMlEvidence && !minimumOccupancyEvidence
                ? 'ml_strong_without_baseline_change'
                : spatialEntryEvidence
                    ? 'ml_spatial_without_baseline_change'
                    : 'ml_without_baseline_change'
            : weakOccupancyEvidence
                ? 'baseline_change_without_ml'
                : occupancy.clearLike
                    ? 'baseline_clear'
                    : 'hold';
    return SensorRecognitionDecision(
      candidate: candidate,
      weakOccupancyEvidence: weakOccupancyEvidence,
      minimumOccupancyEvidence: minimumOccupancyEvidence,
      strongMlEvidence: strongMlEvidence,
      spatialEntryEvidence: spatialEntryEvidence,
      reason: reason,
    );
  }
}
