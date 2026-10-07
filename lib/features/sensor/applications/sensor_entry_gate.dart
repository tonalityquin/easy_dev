import '../services/sensor_object_detector_service.dart';
import 'sensor_occupancy_models.dart';
import 'sensor_trigger_zone.dart';

enum SensorEntryTriggerKind {
  none,
  fast,
  progressive,
  deep,
  persistent,
}

class SensorEntryDecision {
  const SensorEntryDecision({
    required this.active,
    required this.triggered,
    required this.triggerKind,
    required this.mlSupport,
    required this.sampleAge,
    required this.changedCellRatio,
    required this.frontChangedCellRatio,
    required this.spanRatio,
    required this.depthRatio,
    required this.meanDifference,
    required this.changedCellDelta,
    required this.frontChangedCellDelta,
    required this.spanDelta,
    required this.depthDelta,
    required this.coreChangedCellRatio,
    required this.sideGuardChangedCellRatio,
    required this.coreSpanRatio,
    required this.connectedDepthRatio,
    required this.entryRootedRatio,
  });

  final bool active;
  final bool triggered;
  final SensorEntryTriggerKind triggerKind;
  final bool mlSupport;
  final int sampleAge;
  final double changedCellRatio;
  final double frontChangedCellRatio;
  final double spanRatio;
  final double depthRatio;
  final double meanDifference;
  final double changedCellDelta;
  final double frontChangedCellDelta;
  final double spanDelta;
  final double depthDelta;
  final double coreChangedCellRatio;
  final double sideGuardChangedCellRatio;
  final double coreSpanRatio;
  final double connectedDepthRatio;
  final double entryRootedRatio;
}

class SensorEntryGate {
  static const double minimumMlBoundingBoxAreaRatio = 0.055;
  static const double minimumMlPolygonCoverage = 0.05;
  static const double activeChangedCellRatio = 0.06;
  static const double activeFrontChangedCellRatio = 0.08;
  static const double activeSpanRatio = 0.10;
  static const double activeCoreChangedCellRatio = 0.04;
  static const double activeMinimumCoreChangedCellRatio = 0.02;
  static const double activeCoreSpanRatio = 0.08;
  static const double activeEntryRootedRatio = 0.35;
  static const double fastChangedCellRatio = 0.08;
  static const double fastFrontChangedCellRatio = 0.28;
  static const double fastSpanRatio = 0.45;
  static const double fastDepthRatio = 0.04;
  static const double fastCoreChangedCellRatio = 0.06;
  static const double fastCoreSpanRatio = 0.34;
  static const double minimumEntryRootedRatio = 0.45;
  static const double fastEntryRootedRatio = 0.55;
  static const double progressiveChangedCellRatio = 0.08;
  static const double progressiveFrontChangedCellRatio = 0.10;
  static const double progressiveSpanRatio = 0.18;
  static const double progressiveDepthRatio = 0.04;
  static const double progressiveCoreChangedCellRatio = 0.045;
  static const double progressiveCoreSpanRatio = 0.12;
  static const double progressiveChangedCellDelta = 0.055;
  static const double progressiveFrontDelta = 0.055;
  static const double progressiveSpanDelta = 0.08;
  static const double progressiveDepthDelta = 0.035;
  static const double deepChangedCellRatio = 0.10;
  static const double deepSpanRatio = 0.14;
  static const double deepDepthRatio = 0.16;
  static const double deepDepthDelta = 0.035;
  static const double deepCoreChangedCellRatio = 0.05;
  static const double persistentChangedCellRatio = 0.09;
  static const double persistentFrontChangedCellRatio = 0.12;
  static const double persistentCoreChangedCellRatio = 0.06;
  static const double persistentCoreSpanRatio = 0.16;
  static const double persistentConnectedDepthRatio = 0.08;
  static const int minimumProgressiveAge = 2;
  static const int minimumPersistentAge = 2;

  String? _zoneFingerprint;
  DateTime? _lastEvaluationAt;
  SensorEntryChangeAnalysis? _previous;
  int _sampleAge = 0;
  bool _latched = false;

  void reset() {
    _zoneFingerprint = null;
    _lastEvaluationAt = null;
    _previous = null;
    _sampleAge = 0;
    _latched = false;
  }

  SensorEntryDecision evaluate({
    required SensorTriggerZone zone,
    required SensorEntryChangeAnalysis entryChange,
    required SensorOccupancyAnalysis occupancy,
    required SensorObjectZoneMatch mlMatch,
  }) {
    final now = DateTime.now();
    final stale = _lastEvaluationAt != null &&
        now.difference(_lastEvaluationAt!) > const Duration(seconds: 4);
    if (_zoneFingerprint != zone.fingerprint || stale) {
      _previous = null;
      _sampleAge = 0;
      _latched = false;
      _zoneFingerprint = zone.fingerprint;
    }
    _lastEvaluationAt = now;
    _sampleAge++;

    final previous = _previous;
    final changedCellDelta = entryChange.changedCellRatio -
        (previous?.changedCellRatio ?? entryChange.changedCellRatio);
    final frontChangedCellDelta = entryChange.frontChangedCellRatio -
        (previous?.frontChangedCellRatio ?? entryChange.frontChangedCellRatio);
    final spanDelta =
        entryChange.spanRatio - (previous?.spanRatio ?? entryChange.spanRatio);
    final depthDelta =
        entryChange.depthRatio - (previous?.depthRatio ?? entryChange.depthRatio);
    final mlSupport = mlMatch.matched ||
        mlMatch.evidences.any(
          (evidence) =>
              evidence.boundingBoxAreaRatio >= minimumMlBoundingBoxAreaRatio &&
              evidence.polygonCoverage >= minimumMlPolygonCoverage,
        );
    final active = entryChange.coreChangedCellRatio >= activeCoreChangedCellRatio ||
        (entryChange.entryRootedRatio >= activeEntryRootedRatio &&
            entryChange.coreSpanRatio >= activeCoreSpanRatio &&
            entryChange.coreChangedCellRatio >=
                activeMinimumCoreChangedCellRatio &&
            (entryChange.changedCellRatio >= activeChangedCellRatio ||
                entryChange.frontChangedCellRatio >=
                    activeFrontChangedCellRatio ||
                entryChange.spanRatio >= activeSpanRatio));

    var triggerKind = SensorEntryTriggerKind.none;
    if (!_latched && active) {
      final rooted = entryChange.entryRootedRatio >= minimumEntryRootedRatio;
      final fast = entryChange.changedCellRatio >= fastChangedCellRatio &&
          entryChange.frontChangedCellRatio >= fastFrontChangedCellRatio &&
          entryChange.spanRatio >= fastSpanRatio &&
          entryChange.depthRatio >= fastDepthRatio &&
          entryChange.coreChangedCellRatio >= fastCoreChangedCellRatio &&
          entryChange.coreSpanRatio >= fastCoreSpanRatio &&
          entryChange.entryRootedRatio >= fastEntryRootedRatio &&
          (mlSupport || occupancy.structureChangeScore >= 0.11);
      final progressiveGrowth =
          changedCellDelta >= progressiveChangedCellDelta ||
              frontChangedCellDelta >= progressiveFrontDelta ||
              spanDelta >= progressiveSpanDelta ||
              depthDelta >= progressiveDepthDelta;
      final progressive = _sampleAge >= minimumProgressiveAge &&
          entryChange.changedCellRatio >= progressiveChangedCellRatio &&
          entryChange.frontChangedCellRatio >=
              progressiveFrontChangedCellRatio &&
          entryChange.spanRatio >= progressiveSpanRatio &&
          entryChange.depthRatio >= progressiveDepthRatio &&
          entryChange.coreChangedCellRatio >=
              progressiveCoreChangedCellRatio &&
          entryChange.coreSpanRatio >= progressiveCoreSpanRatio &&
          rooted &&
          progressiveGrowth &&
          mlSupport;
      final deep = _sampleAge >= minimumProgressiveAge &&
          entryChange.changedCellRatio >= deepChangedCellRatio &&
          entryChange.spanRatio >= deepSpanRatio &&
          entryChange.connectedDepthRatio >= deepDepthRatio &&
          entryChange.coreChangedCellRatio >= deepCoreChangedCellRatio &&
          entryChange.entryRootedRatio >= minimumEntryRootedRatio &&
          depthDelta >= deepDepthDelta &&
          mlSupport;
      final persistent = _sampleAge >= minimumPersistentAge &&
          entryChange.changedCellRatio >= persistentChangedCellRatio &&
          entryChange.frontChangedCellRatio >=
              persistentFrontChangedCellRatio &&
          entryChange.coreChangedCellRatio >= persistentCoreChangedCellRatio &&
          entryChange.coreSpanRatio >= persistentCoreSpanRatio &&
          entryChange.connectedDepthRatio >= persistentConnectedDepthRatio &&
          entryChange.entryRootedRatio >= fastEntryRootedRatio &&
          mlSupport;
      if (fast) {
        triggerKind = SensorEntryTriggerKind.fast;
      } else if (deep) {
        triggerKind = SensorEntryTriggerKind.deep;
      } else if (progressive) {
        triggerKind = SensorEntryTriggerKind.progressive;
      } else if (persistent) {
        triggerKind = SensorEntryTriggerKind.persistent;
      }
    }

    final triggered = triggerKind != SensorEntryTriggerKind.none;
    if (triggered) {
      _latched = true;
    }
    _previous = entryChange;

    return SensorEntryDecision(
      active: active,
      triggered: triggered,
      triggerKind: triggerKind,
      mlSupport: mlSupport,
      sampleAge: _sampleAge,
      changedCellRatio: entryChange.changedCellRatio,
      frontChangedCellRatio: entryChange.frontChangedCellRatio,
      spanRatio: entryChange.spanRatio,
      depthRatio: entryChange.depthRatio,
      meanDifference: entryChange.meanDifference,
      changedCellDelta: changedCellDelta,
      frontChangedCellDelta: frontChangedCellDelta,
      spanDelta: spanDelta,
      depthDelta: depthDelta,
      coreChangedCellRatio: entryChange.coreChangedCellRatio,
      sideGuardChangedCellRatio: entryChange.sideGuardChangedCellRatio,
      coreSpanRatio: entryChange.coreSpanRatio,
      connectedDepthRatio: entryChange.connectedDepthRatio,
      entryRootedRatio: entryChange.entryRootedRatio,
    );
  }
}
