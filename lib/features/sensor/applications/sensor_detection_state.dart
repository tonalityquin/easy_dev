import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'sensor_debug_trace.dart';
import 'sensor_occupancy_models.dart';

enum SensorDetectionPhase {
  initializing,
  armed,
  detected,
  ocrActive,
  waitForClear,
  error,
}

enum SensorDetectionSampleOutcome {
  unchanged,
  detectedStable,
  clearedStable,
}

enum SensorPlateAcceptanceKind {
  accepted,
  duplicate,
}

class SensorPlateAcceptanceResult {
  const SensorPlateAcceptanceResult({
    required this.kind,
    required this.normalizedPlate,
    required this.elapsedMilliseconds,
  });

  final SensorPlateAcceptanceKind kind;
  final String normalizedPlate;
  final int? elapsedMilliseconds;

  bool get accepted => kind == SensorPlateAcceptanceKind.accepted;
  bool get duplicate => kind == SensorPlateAcceptanceKind.duplicate;
}

class SensorDetectionState extends ChangeNotifier {
  static const int detectionWindowSize = 3;
  static const int detectionRequiredPositives = 2;
  static const int detectedThreshold = detectionRequiredPositives;
  static const int clearThreshold = 3;
  static const Duration minimumClearDuration = Duration(seconds: 6);
  static const Duration duplicatePlateWindow = Duration(seconds: 30);

  SensorDetectionPhase _phase = SensorDetectionPhase.initializing;
  bool _objectDetected = false;
  bool _cameraReady = false;
  bool _detectorReady = false;
  bool _ocrActive = false;
  int _detectedStreak = 0;
  final List<bool> _recentDetectionSamples = <bool>[];
  int _clearStreak = 0;
  int _sampleCount = 0;
  Stopwatch? _clearStopwatch;
  String? _lastRecognizedPlate;
  String? _lastAcceptedPlate;
  DateTime? _lastAcceptedPlateAt;
  String? _lastDuplicatePlate;
  int? _lastDuplicateElapsedMilliseconds;
  SensorOccupancyEvidence? _lastOccupancyEvidence;
  bool _baselineReady = false;
  String? _baselineSavedAt;
  String? _lastError;
  Size? _previewViewportSize;
  Size? _cameraImageSize;
  Size? _cameraPreviewSourceSize;
  String? _coordinateFit;
  int? _sensorOrientation;
  String? _lensDirection;
  String? _cameraGeometrySource;

  SensorDetectionPhase get phase => _phase;
  bool get objectDetected => _objectDetected;
  bool get cameraReady => _cameraReady;
  bool get detectorReady => _detectorReady;
  bool get ocrActive => _ocrActive;
  int get detectedStreak => _detectedStreak;
  int get detectionWindowCount => _recentDetectionSamples.length;
  int get detectionPositiveCount =>
      _recentDetectionSamples.where((value) => value).length;
  List<bool> get recentDetectionSamples =>
      List<bool>.unmodifiable(_recentDetectionSamples);
  int get clearStreak => _clearStreak;
  int get sampleCount => _sampleCount;
  int get clearElapsedMilliseconds =>
      _clearStopwatch?.elapsedMilliseconds ?? 0;
  bool get clearTimeSatisfied =>
      clearElapsedMilliseconds >= minimumClearDuration.inMilliseconds;
  String? get lastRecognizedPlate => _lastRecognizedPlate;
  String? get lastAcceptedPlate => _lastAcceptedPlate;
  DateTime? get lastAcceptedPlateAt => _lastAcceptedPlateAt;
  String? get lastDuplicatePlate => _lastDuplicatePlate;
  int? get lastDuplicateElapsedMilliseconds =>
      _lastDuplicateElapsedMilliseconds;
  SensorOccupancyEvidence? get lastOccupancyEvidence => _lastOccupancyEvidence;
  bool get baselineReady => _baselineReady;
  String? get baselineSavedAt => _baselineSavedAt;
  String? get lastError => _lastError;
  Size? get previewViewportSize => _previewViewportSize;
  Size? get cameraImageSize => _cameraImageSize;
  Size? get cameraPreviewSourceSize => _cameraPreviewSourceSize;
  String? get coordinateFit => _coordinateFit;
  int? get sensorOrientation => _sensorOrientation;
  String? get lensDirection => _lensDirection;
  bool get cameraGeometryReady => _cameraImageSize != null;
  String? get cameraGeometrySource => _cameraGeometrySource;

  double? get previewAspect {
    final size = _cameraPreviewSourceSize;
    if (size == null || size.height == 0) return null;
    return size.width / size.height;
  }

  double? get cameraImageAspect {
    final size = _cameraImageSize;
    if (size == null || size.height == 0) return null;
    return size.width / size.height;
  }

  double? get coordinateAspectDelta {
    final preview = previewAspect;
    final image = cameraImageAspect;
    if (preview == null || image == null) return null;
    return (preview - image).abs();
  }

  bool get runtimeReady => _cameraReady && _detectorReady;
  bool get canSample =>
      runtimeReady &&
      !_ocrActive &&
      (_phase == SensorDetectionPhase.armed ||
          _phase == SensorDetectionPhase.waitForClear);

  void reset({String source = 'unknown'}) {
    _phase = SensorDetectionPhase.initializing;
    _objectDetected = false;
    _cameraReady = false;
    _detectorReady = false;
    _ocrActive = false;
    _detectedStreak = 0;
    _recentDetectionSamples.clear();
    _clearStreak = 0;
    _sampleCount = 0;
    _clearStopwatch?.stop();
    _clearStopwatch = null;
    _lastRecognizedPlate = null;
    _lastAcceptedPlate = null;
    _lastAcceptedPlateAt = null;
    _lastDuplicatePlate = null;
    _lastDuplicateElapsedMilliseconds = null;
    _lastOccupancyEvidence = null;
    _baselineReady = false;
    _baselineSavedAt = null;
    _lastError = null;
    _previewViewportSize = null;
    _cameraImageSize = null;
    _cameraPreviewSourceSize = null;
    _coordinateFit = null;
    _sensorOrientation = null;
    _lensDirection = null;
    _cameraGeometrySource = null;
    SensorDebugTrace.record(
      'SensorDetection',
      'reset',
      <String, Object?>{'source': source},
    );
    notifyListeners();
  }

  void resetSampling({String source = 'unknown'}) {
    final previousPhase = _phase;
    _objectDetected = false;
    _detectedStreak = 0;
    _recentDetectionSamples.clear();
    _clearStreak = 0;
    _clearStopwatch?.stop();
    _clearStopwatch = null;
    _lastRecognizedPlate = null;
    _lastAcceptedPlate = null;
    _lastAcceptedPlateAt = null;
    _lastDuplicatePlate = null;
    _lastDuplicateElapsedMilliseconds = null;
    _lastOccupancyEvidence = null;
    _baselineReady = false;
    _baselineSavedAt = null;
    _lastError = null;
    if (!_ocrActive) {
      _phase = runtimeReady
          ? SensorDetectionPhase.armed
          : SensorDetectionPhase.initializing;
    }
    SensorDebugTrace.record(
      'SensorDetection',
      'sampling_reset',
      <String, Object?>{
        'fromPhase': previousPhase.name,
        'toPhase': _phase.name,
        'runtimeReady': runtimeReady,
        'source': source,
      },
    );
    notifyListeners();
  }

  void resetSamplingCounters({String source = 'unknown'}) {
    _detectedStreak = 0;
    _recentDetectionSamples.clear();
    _clearStreak = 0;
    _clearStopwatch?.stop();
    _clearStopwatch = null;
    _lastOccupancyEvidence = null;
    _lastError = null;
    SensorDebugTrace.record(
      'SensorDetection',
      'sampling_counters_reset',
      <String, Object?>{
        'phase': _phase.name,
        'objectDetected': _objectDetected,
        'runtimeReady': runtimeReady,
        'source': source,
      },
    );
    notifyListeners();
  }

  void updateCoordinateGeometry({
    required Size previewViewportSize,
    required Size cameraPreviewSourceSize,
    required Size? cameraImageSize,
    required String coordinateFit,
    required int sensorOrientation,
    required String lensDirection,
    required String? cameraGeometrySource,
    String source = 'unknown',
  }) {
    final changed =
        _previewViewportSize != previewViewportSize ||
        _cameraPreviewSourceSize != cameraPreviewSourceSize ||
        _cameraImageSize != cameraImageSize ||
        _coordinateFit != coordinateFit ||
        _sensorOrientation != sensorOrientation ||
        _lensDirection != lensDirection ||
        _cameraGeometrySource != cameraGeometrySource;
    if (!changed) return;
    _previewViewportSize = previewViewportSize;
    _cameraPreviewSourceSize = cameraPreviewSourceSize;
    _cameraImageSize = cameraImageSize;
    _coordinateFit = coordinateFit;
    _sensorOrientation = sensorOrientation;
    _lensDirection = lensDirection;
    _cameraGeometrySource = cameraGeometrySource;
    final previewAspect = cameraPreviewSourceSize.height == 0
        ? null
        : cameraPreviewSourceSize.width / cameraPreviewSourceSize.height;
    final imageAspect = cameraImageSize == null || cameraImageSize.height == 0
        ? null
        : cameraImageSize.width / cameraImageSize.height;
    SensorDebugTrace.record(
      'SensorCoordinate',
      'geometry_changed',
      <String, Object?>{
        'previewWidth': previewViewportSize.width.round(),
        'previewHeight': previewViewportSize.height.round(),
        'previewSourceWidth': cameraPreviewSourceSize.width.round(),
        'previewSourceHeight': cameraPreviewSourceSize.height.round(),
        'imageWidth': cameraImageSize?.width.round(),
        'imageHeight': cameraImageSize?.height.round(),
        'geometryReady': cameraImageSize != null,
        'geometrySource': cameraGeometrySource,
        'previewAspect': previewAspect?.toStringAsFixed(4),
        'imageAspect': imageAspect?.toStringAsFixed(4),
        'aspectDelta': previewAspect == null || imageAspect == null
            ? null
            : (previewAspect - imageAspect).abs().toStringAsFixed(4),
        'fit': coordinateFit,
        'sensorOrientation': sensorOrientation,
        'lensDirection': lensDirection,
        'source': source,
      },
    );
    notifyListeners();
  }

  void updateBaselineDiagnostics({
    required bool ready,
    String? savedAt,
    String source = 'unknown',
  }) {
    final changed = _baselineReady != ready || _baselineSavedAt != savedAt;
    _baselineReady = ready;
    _baselineSavedAt = savedAt;
    if (!changed) return;
    SensorDebugTrace.record(
      'SensorOccupancy',
      'baseline_diagnostics_updated',
      <String, Object?>{
        'ready': ready,
        'savedAt': savedAt,
        'source': source,
      },
    );
    notifyListeners();
  }

  void setRuntimeAvailability({
    required bool cameraReady,
    required bool detectorReady,
    String source = 'unknown',
  }) {
    final changed =
        _cameraReady != cameraReady || _detectorReady != detectorReady;
    _cameraReady = cameraReady;
    _detectorReady = detectorReady;
    if (runtimeReady &&
        (_phase == SensorDetectionPhase.initializing ||
            _phase == SensorDetectionPhase.error)) {
      _phase = SensorDetectionPhase.armed;
      _lastError = null;
    }
    if (changed) {
      SensorDebugTrace.record(
        'SensorDetection',
        'runtime_availability_changed',
        <String, Object?>{
          'cameraReady': _cameraReady,
          'detectorReady': _detectorReady,
          'phase': _phase.name,
          'source': source,
        },
      );
      notifyListeners();
    }
  }

  SensorDetectionSampleOutcome registerOccupancySample(
    SensorOccupancyEvidence evidence, {
    int elapsedMilliseconds = 0,
    double? triggerX,
    double? triggerY,
    String source = 'occupancy',
  }) {
    if (!canSample) {
      SensorDebugTrace.record(
        'SensorDetection',
        'sample_ignored',
        <String, Object?>{
          'phase': _phase.name,
          'cameraReady': _cameraReady,
          'detectorReady': _detectorReady,
          'ocrActive': _ocrActive,
          'reason': evidence.reason,
          'source': source,
        },
      );
      return SensorDetectionSampleOutcome.unchanged;
    }

    _sampleCount++;
    _lastOccupancyEvidence = evidence;

    if (_phase == SensorDetectionPhase.waitForClear) {
      final clearCandidate = evidence.clearCandidate;
      if (!clearCandidate) {
        _objectDetected = true;
        _clearStreak = 0;
        _clearStopwatch?.stop();
        _clearStopwatch = null;
      } else {
        _clearStopwatch ??= Stopwatch()..start();
        if (!_clearStopwatch!.isRunning) {
          _clearStopwatch!.start();
        }
        _clearStreak = (_clearStreak + 1).clamp(0, clearThreshold).toInt();
        final clearElapsedMs = _clearStopwatch!.elapsedMilliseconds;
        if (_clearStreak >= clearThreshold &&
            clearElapsedMs >= minimumClearDuration.inMilliseconds) {
          _objectDetected = false;
          _detectedStreak = 0;
          _recentDetectionSamples.clear();
          _clearStreak = 0;
          _clearStopwatch!.stop();
          _clearStopwatch = null;
          _lastRecognizedPlate = null;
          _phase = SensorDetectionPhase.armed;
          SensorDebugTrace.record(
            'SensorDetection',
            'rearmed',
            <String, Object?>{
              'sampleCount': _sampleCount,
              'clearElapsedMs': clearElapsedMs,
              'minimumClearMs': minimumClearDuration.inMilliseconds,
              'structureChange': evidence.structureChangeScore.toStringAsFixed(4),
              'changedCellRatio': evidence.changedCellRatio.toStringAsFixed(4),
              'mlMatched': evidence.mlMatched,
              'mlBottomCenterMatched': evidence.mlBottomCenterMatched,
              'reason': evidence.reason,
              'triggerX': triggerX?.toStringAsFixed(4),
              'triggerY': triggerY?.toStringAsFixed(4),
              'source': source,
            },
          );
          notifyListeners();
          return SensorDetectionSampleOutcome.clearedStable;
        }
      }

      SensorDebugTrace.record(
        'SensorDetection',
        'clear_sample',
        <String, Object?>{
          'clearCandidate': clearCandidate,
          'clearStreak': _clearStreak,
          'threshold': clearThreshold,
          'clearElapsedMs': clearElapsedMilliseconds,
          'minimumClearMs': minimumClearDuration.inMilliseconds,
          'clearTimeSatisfied': clearTimeSatisfied,
          'structureChange': evidence.structureChangeScore.toStringAsFixed(4),
          'changedCellRatio': evidence.changedCellRatio.toStringAsFixed(4),
          'baselineSimilarity': evidence.baselineSimilarity.toStringAsFixed(4),
          'mlMatched': evidence.mlMatched,
          'mlBottomCenterMatched': evidence.mlBottomCenterMatched,
          'mlObjectCount': evidence.mlObjectCount,
          'mlMatchedCount': evidence.mlMatchedCount,
          'mlPolygonCoverage': evidence.mlPolygonCoverage.toStringAsFixed(4),
          'bboxAreaRatio': evidence.mlBoundingBoxAreaRatio.toStringAsFixed(4),
          'reason': evidence.reason,
          'elapsedMs': elapsedMilliseconds,
          'triggerX': triggerX?.toStringAsFixed(4),
          'triggerY': triggerY?.toStringAsFixed(4),
          'source': source,
        },
      );
      notifyListeners();
      return SensorDetectionSampleOutcome.unchanged;
    }

    final occupiedCandidate = evidence.occupiedCandidate;
    _recentDetectionSamples.add(occupiedCandidate);
    if (_recentDetectionSamples.length > detectionWindowSize) {
      _recentDetectionSamples.removeAt(0);
    }
    _detectedStreak = detectionPositiveCount;
    _clearStreak = 0;
    _objectDetected = false;
    final detectionConfirmed =
        _recentDetectionSamples.length >= detectionRequiredPositives &&
            _detectedStreak >= detectionRequiredPositives;
    if (detectionConfirmed) {
      _objectDetected = true;
      _phase = SensorDetectionPhase.detected;
      SensorDebugTrace.record(
        'SensorDetection',
        'detected_stable',
        <String, Object?>{
          'windowSize': detectionWindowSize,
          'windowCount': _recentDetectionSamples.length,
          'requiredPositives': detectionRequiredPositives,
          'positiveCount': _detectedStreak,
          'window': _recentDetectionSamples.map((value) => value ? 1 : 0).join(','),
          'sampleCount': _sampleCount,
          'structureChange': evidence.structureChangeScore.toStringAsFixed(4),
          'changedCellRatio': evidence.changedCellRatio.toStringAsFixed(4),
          'mlObjectCount': evidence.mlObjectCount,
          'mlMatchedCount': evidence.mlMatchedCount,
          'mlBottomCenterMatched': evidence.mlBottomCenterMatched,
          'mlPolygonCoverage': evidence.mlPolygonCoverage.toStringAsFixed(4),
          'bboxAreaRatio': evidence.mlBoundingBoxAreaRatio.toStringAsFixed(4),
          'reason': evidence.reason,
          'elapsedMs': elapsedMilliseconds,
          'triggerX': triggerX?.toStringAsFixed(4),
          'triggerY': triggerY?.toStringAsFixed(4),
          'source': source,
        },
      );
      notifyListeners();
      return SensorDetectionSampleOutcome.detectedStable;
    }

    SensorDebugTrace.record(
      'SensorDetection',
      'sample',
      <String, Object?>{
        'occupiedCandidate': occupiedCandidate,
        'detectedStreak': _detectedStreak,
        'windowSize': detectionWindowSize,
        'windowCount': _recentDetectionSamples.length,
        'requiredPositives': detectionRequiredPositives,
        'positiveCount': _detectedStreak,
        'window': _recentDetectionSamples.map((value) => value ? 1 : 0).join(','),
        'structureChange': evidence.structureChangeScore.toStringAsFixed(4),
        'changedCellRatio': evidence.changedCellRatio.toStringAsFixed(4),
        'baselineSimilarity': evidence.baselineSimilarity.toStringAsFixed(4),
        'mlObjectCount': evidence.mlObjectCount,
        'mlMatchedCount': evidence.mlMatchedCount,
        'mlBottomCenterMatched': evidence.mlBottomCenterMatched,
        'mlPolygonCoverage': evidence.mlPolygonCoverage.toStringAsFixed(4),
        'bboxAreaRatio': evidence.mlBoundingBoxAreaRatio.toStringAsFixed(4),
        'reason': evidence.reason,
        'elapsedMs': elapsedMilliseconds,
        'sampleCount': _sampleCount,
        'triggerX': triggerX?.toStringAsFixed(4),
        'triggerY': triggerY?.toStringAsFixed(4),
        'source': source,
      },
    );
    notifyListeners();
    return SensorDetectionSampleOutcome.unchanged;
  }

  bool beginOcr({String source = 'unknown'}) {
    if (_phase != SensorDetectionPhase.detected || _ocrActive) {
      SensorDebugTrace.record(
        'SensorDetection',
        'ocr_begin_rejected',
        <String, Object?>{
          'phase': _phase.name,
          'ocrActive': _ocrActive,
          'source': source,
        },
      );
      return false;
    }
    _ocrActive = true;
    _phase = SensorDetectionPhase.ocrActive;
    _detectedStreak = 0;
    _recentDetectionSamples.clear();
    _clearStreak = 0;
    _clearStopwatch?.stop();
    _clearStopwatch = null;
    SensorDebugTrace.record(
      'SensorDetection',
      'ocr_begin',
      <String, Object?>{'source': source},
    );
    notifyListeners();
    return true;
  }

  void completeOcr({
    String? plate,
    String? exitType,
    String source = 'unknown',
  }) {
    final normalizedPlate = plate?.trim();
    _ocrActive = false;
    _objectDetected = true;
    _detectedStreak = 0;
    _recentDetectionSamples.clear();
    _clearStreak = 0;
    _clearStopwatch?.stop();
    _clearStopwatch = null;
    _lastRecognizedPlate = normalizedPlate == null || normalizedPlate.isEmpty
        ? null
        : normalizedPlate;
    _phase = SensorDetectionPhase.waitForClear;
    SensorDebugTrace.record(
      'SensorDetection',
      'ocr_complete',
      <String, Object?>{
        'plate': _lastRecognizedPlate,
        'success': _lastRecognizedPlate != null,
        'exitType': exitType,
        'source': source,
      },
    );
    notifyListeners();
  }

  SensorPlateAcceptanceResult evaluatePlateAcceptance(
    String plate, {
    DateTime? now,
    String source = 'unknown',
  }) {
    final normalizedPlate = _normalizePlate(plate);
    final evaluatedAt = now ?? DateTime.now();
    final previousPlate = _lastAcceptedPlate;
    final previousAt = _lastAcceptedPlateAt;
    final elapsedMs = previousAt == null
        ? null
        : evaluatedAt.difference(previousAt).inMilliseconds;
    final duplicate = previousPlate == normalizedPlate &&
        elapsedMs != null &&
        elapsedMs >= 0 &&
        elapsedMs < duplicatePlateWindow.inMilliseconds;
    if (duplicate) {
      _lastDuplicatePlate = normalizedPlate;
      _lastDuplicateElapsedMilliseconds = elapsedMs;
      SensorDebugTrace.record(
        'SensorDetection',
        'plate_duplicate_suppressed',
        <String, Object?>{
          'plate': normalizedPlate,
          'elapsedMs': elapsedMs,
          'windowMs': duplicatePlateWindow.inMilliseconds,
          'source': source,
        },
      );
      notifyListeners();
      return SensorPlateAcceptanceResult(
        kind: SensorPlateAcceptanceKind.duplicate,
        normalizedPlate: normalizedPlate,
        elapsedMilliseconds: elapsedMs,
      );
    }
    _lastAcceptedPlate = normalizedPlate;
    _lastAcceptedPlateAt = evaluatedAt;
    _lastDuplicatePlate = null;
    _lastDuplicateElapsedMilliseconds = null;
    SensorDebugTrace.record(
      'SensorDetection',
      'plate_accepted',
      <String, Object?>{
        'plate': normalizedPlate,
        'elapsedMs': elapsedMs,
        'windowMs': duplicatePlateWindow.inMilliseconds,
        'source': source,
      },
    );
    notifyListeners();
    return SensorPlateAcceptanceResult(
      kind: SensorPlateAcceptanceKind.accepted,
      normalizedPlate: normalizedPlate,
      elapsedMilliseconds: elapsedMs,
    );
  }

  String _normalizePlate(String plate) {
    return plate.replaceAll(RegExp(r'[\s\-]'), '').trim();
  }

  void fail(
    Object error, {
    String source = 'unknown',
  }) {
    _ocrActive = false;
    _clearStopwatch?.stop();
    _clearStopwatch = null;
    _phase = SensorDetectionPhase.error;
    _lastError = error.toString();
    SensorDebugTrace.record(
      'SensorDetection',
      'error',
      <String, Object?>{
        'error': error,
        'source': source,
      },
    );
    notifyListeners();
  }
}
