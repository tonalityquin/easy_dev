import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../shared/page/input/pages/live_ocr_page.dart';
import '../../../../shared/page/input/widgets/live_ocr_source_rect_route.dart';
import '../../applications/sensor_debug_trace.dart';
import '../../applications/sensor_detection_state.dart';
import '../../applications/sensor_entry_gate.dart';
import '../../applications/sensor_entry_geometry.dart';
import '../../applications/sensor_occupancy_models.dart';
import '../../applications/sensor_recognition_gate.dart';
import '../../applications/sensor_trigger_point_state.dart';
import '../../applications/sensor_trigger_zone.dart';
import '../../../selector/application/dev_auth.dart';
import '../../applications/sensor_work_session_state.dart';
import '../../data/sensor_occupancy_baseline_store.dart';
import '../../services/sensor_camera_coordinate_mapper.dart';
import '../../services/sensor_camera_image_geometry_reader.dart';
import '../../services/sensor_object_detector_service.dart';
import '../../services/sensor_parking_occupancy_analyzer.dart';
import 'sensor_debug_status_banner.dart';
import 'sensor_detection_debug_overlay.dart';
import 'sensor_plate_success_snackbar.dart';
import 'sensor_trigger_point_overlay.dart';

class SensorDetectionContent extends StatefulWidget {
  const SensorDetectionContent({super.key});

  @override
  State<SensorDetectionContent> createState() =>
      _SensorDetectionContentState();
}

class _SensorDetectionContentState extends State<SensorDetectionContent>
    with TickerProviderStateMixin {
  static const Duration _sampleInterval = Duration(milliseconds: 850);
  static const Duration _approachSampleInterval = Duration(milliseconds: 180);
  static const Duration _cameraInitializeTimeout = Duration(seconds: 8);
  static const int _captureErrorBackoffThreshold = 2;
  static const int _captureErrorRecoverThreshold = 4;

  Size? _lastPreviewViewportSize;
  final SensorCameraImageGeometryReader _geometryReader =
      const SensorCameraImageGeometryReader();
  final SensorObjectDetectorService _detector = SensorObjectDetectorService();
  final SensorParkingOccupancyAnalyzer _occupancyAnalyzer =
      const SensorParkingOccupancyAnalyzer();
  final SensorRecognitionGate _recognitionGate = const SensorRecognitionGate();
  final SensorEntryGate _entryGate = SensorEntryGate();
  final SensorOccupancyBaselineStore _baselineStore =
      SensorOccupancyBaselineStore();
  final Uuid _uuid = const Uuid();

  CameraController? _cameraController;
  CameraDescription? _cameraDescription;
  ResolutionPreset? _activePreset;
  late final AnimationController _scanController;
  int _loopGeneration = 0;
  int _captureErrorStreak = 0;
  bool _capturing = false;
  bool _triggerGeometryPreparing = false;
  bool _runtimeInitializing = false;
  bool _routeActive = false;
  bool _torch = false;
  bool _triggerMissingStatusPublished = false;
  String? _runtimeError;
  Size? _lastCameraImageSize;
  String? _cameraGeometrySource;
  Uint8List? _triggerCalibrationFrameBytes;
  Size? _triggerCalibrationFrameSize;
  List<Offset> _triggerEditViewportCorners = const <Offset>[];
  bool _movingTriggerPolygon = false;
  bool _triggerDragging = false;
  SensorTriggerZoneHandle? _activeTriggerResizeHandle;
  bool _triggerResizeRejectedDuringGesture = false;
  int? _triggerCornerFeedbackIndex;
  int _triggerCornerFeedbackSerial = 0;
  int? _triggerCornerRejectedIndex;
  int _triggerCornerRejectedSerial = 0;
  List<Rect> _lastDetectionBoxes = const <Rect>[];
  Set<int> _lastMatchedBoxIndexes = const <int>{};
  Set<int> _lastBottomCenterMatchedBoxIndexes = const <int>{};
  bool _lastEntryActive = false;
  bool _lastEntryTriggered = false;
  String? _lastCoordinateSignature;
  SensorOccupancyBaseline? _occupancyBaseline;
  String? _baselineLoadKey;
  bool _baselineLoading = false;
  bool _baselineSaving = false;
  bool _baselineMissingStatusPublished = false;
  bool? _scanEnabledCache;

  @override
  void initState() {
    super.initState();
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<SensorDetectionState>().reset(source: 'sensor_content');
      unawaited(_initializeRuntime(source: 'sensor_content'));
    });
    SensorDebugTrace.record('SensorDetectionContent', 'mounted');
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _scanController.stop();
      _scanController.value = 0.5;
      _scanEnabledCache = false;
    } else {
      _scanEnabledCache = null;
    }
  }

  void _syncScanState({
    required bool enabled,
    required bool reduceMotion,
  }) {
    final effective = enabled && !reduceMotion && !_routeActive;
    if (_scanEnabledCache == effective) return;
    _scanEnabledCache = effective;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (effective) {
        if (!_scanController.isAnimating) {
          _scanController.repeat();
        }
      } else {
        _scanController.stop();
        _scanController.value = 0.5;
      }
    });
  }

  @override
  void dispose() {
    _loopGeneration++;
    _scanController.dispose();
    final controller = _cameraController;
    _cameraController = null;
    unawaited(controller?.dispose() ?? Future<void>.value());
    unawaited(_detector.close());
    SensorDebugTrace.record('SensorDetectionContent', 'disposed');
    super.dispose();
  }

  Future<void> _initializeRuntime({required String source}) async {
    if (!mounted || _runtimeInitializing || _routeActive) return;
    _runtimeInitializing = true;
    _runtimeError = null;
    final detectionState = context.read<SensorDetectionState>();
    detectionState.setRuntimeAvailability(
      cameraReady: false,
      detectorReady: false,
      source: '${source}_start',
    );
    SensorDebugTrace.publishStatus(
      'SensorDetectionContent',
      'runtime_initialize_requested',
      title: source == 'ocr_return' ? '센서 감지 복구 중' : '센서 초기화 중',
      detail: source == 'ocr_return'
          ? detectionState.lastRecognizedPlate
          : null,
      tone: SensorDebugStatusTone.progress,
      sticky: true,
      details: <String, Object?>{'source': source},
    );

    try {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        throw StateError('Camera permission denied.');
      }

      await _detector.initialize();

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw StateError('No camera is available.');
      }
      final back = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      _cameraDescription = back;
      await _initializeCameraWithFallback(back);
      await _meterTo(const Offset(0.5, 0.5));
      _captureErrorStreak = 0;

      if (!mounted) return;
      detectionState.setRuntimeAvailability(
        cameraReady: true,
        detectorReady: _detector.isReady,
        source: '${source}_ready',
      );
      setState(() {
        _runtimeError = null;
      });
      SensorDebugTrace.publishStatus(
        'SensorDetectionContent',
        'runtime_initialized',
        title: source == 'ocr_return'
            ? detectionState.phase == SensorDetectionPhase.waitForClear
                ? '차량 이탈 대기'
                : '센서 감지 재개'
            : '센서 감지 준비 완료',
        detail: source == 'ocr_return'
            ? detectionState.lastRecognizedPlate
            : _activePreset?.name,
        tone: source == 'ocr_return' &&
                detectionState.phase == SensorDetectionPhase.waitForClear
            ? SensorDebugStatusTone.info
            : SensorDebugStatusTone.success,
        sticky: source == 'ocr_return' &&
            detectionState.phase == SensorDetectionPhase.waitForClear,
        details: <String, Object?>{
          'source': source,
          'preset': _activePreset?.name,
          'camera': back.name,
          'phase': detectionState.phase.name,
        },
      );
      _startDetectionLoop(source: source);
    } catch (error, stackTrace) {
      SensorDebugTrace.publishStatus(
        'SensorDetectionContent',
        'runtime_initialize_failed',
        title: '센서 초기화 실패',
        detail: error.toString(),
        tone: SensorDebugStatusTone.error,
        sticky: true,
        details: <String, Object?>{
          'source': source,
          'error': error,
          'stack': stackTrace,
        },
      );
      if (mounted) {
        detectionState.fail(error, source: '${source}_initialize');
        setState(() {
          _runtimeError = error.toString();
        });
      }
      await _disposeRuntimeResources(
        source: '${source}_failed',
        closeDetector: true,
      );
    } finally {
      _runtimeInitializing = false;
    }
  }

  Future<void> _initializeCameraWithFallback(
    CameraDescription camera,
  ) async {
    CameraController? controller;
    try {
      controller = CameraController(
        camera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize().timeout(_cameraInitializeTimeout);
      _activePreset = ResolutionPreset.high;
    } catch (_) {
      await controller?.dispose();
      controller = CameraController(
        camera,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );
      await controller.initialize().timeout(_cameraInitializeTimeout);
      _activePreset = ResolutionPreset.medium;
    }

    try {
      await controller.setFocusMode(FocusMode.auto);
      await controller.setExposureMode(ExposureMode.auto);
      await controller.setFlashMode(FlashMode.off);
    } catch (_) {}

    _torch = false;
    _cameraController = controller;
    _lastCameraImageSize = null;
    _cameraGeometrySource = null;
    _triggerCalibrationFrameBytes = null;
    _triggerCalibrationFrameSize = null;
    _triggerEditViewportCorners = const <Offset>[];
    _triggerDragging = false;
    _lastDetectionBoxes = const <Rect>[];
    _lastMatchedBoxIndexes = const <int>{};
    _lastBottomCenterMatchedBoxIndexes = const <int>{};
    _lastEntryActive = false;
    _lastEntryTriggered = false;
    _entryGate.reset();
    _lastCoordinateSignature = null;
    if (mounted) {
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _publishCoordinateGeometry(source: 'camera_preview_ready');
      });
    }
  }

  Future<void> _meterTo(Offset point) async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    try {
      await controller.setFocusPoint(point);
      SensorDebugTrace.record(
        'SensorDetectionContent',
        'focus_point_changed',
        <String, Object?>{
          'dx': point.dx.toStringAsFixed(2),
          'dy': point.dy.toStringAsFixed(2),
        },
      );
    } catch (error) {
      SensorDebugTrace.record(
        'SensorDetectionContent',
        'focus_point_failed',
        <String, Object?>{'error': error},
      );
    }
  }

  Size? _orientedPreviewSourceSize(Size viewportSize) {
    final controller = _cameraController;
    final previewSize = controller?.value.previewSize;
    if (previewSize == null ||
        previewSize.width <= 0 ||
        previewSize.height <= 0 ||
        viewportSize.width <= 0 ||
        viewportSize.height <= 0) {
      return null;
    }
    final viewportPortrait = viewportSize.height >= viewportSize.width;
    final previewPortrait = previewSize.height >= previewSize.width;
    if (viewportPortrait == previewPortrait) return previewSize;
    return Size(previewSize.height, previewSize.width);
  }

  SensorCameraCoordinateMapper? _coordinateMapper(Size viewportSize) {
    if (viewportSize.width <= 0 || viewportSize.height <= 0) return null;
    final previewSourceSize = _orientedPreviewSourceSize(viewportSize);
    if (previewSourceSize == null ||
        previewSourceSize.width <= 0 ||
        previewSourceSize.height <= 0) {
      return null;
    }
    return SensorCameraCoordinateMapper(
      previewSourceSize: previewSourceSize,
      cameraImageSize: _lastCameraImageSize,
      viewportSize: viewportSize,
      fit: BoxFit.cover,
    );
  }

  Size? _currentPreviewViewportSize() {
    if (mounted) {
      final box = context.findRenderObject();
      if (box is RenderBox &&
          box.hasSize &&
          box.size.width > 0 &&
          box.size.height > 0) {
        return box.size;
      }
    }
    final cached = _lastPreviewViewportSize;
    if (cached != null && cached.width > 0 && cached.height > 0) {
      return cached;
    }
    return null;
  }

  void _releaseTriggerEditVisuals({required String source}) {
    final hadFrame = _triggerCalibrationFrameBytes != null;
    final hadViewportZone = _triggerEditViewportCorners.isNotEmpty;
    if (mounted) {
      setState(() {
        _triggerCalibrationFrameBytes = null;
        _triggerCalibrationFrameSize = null;
        _triggerEditViewportCorners = const <Offset>[];
        _triggerDragging = false;
        _movingTriggerPolygon = false;
        _activeTriggerResizeHandle = null;
        _triggerResizeRejectedDuringGesture = false;
        _triggerCornerFeedbackIndex = null;
        _triggerCornerRejectedIndex = null;
      });
    } else {
      _triggerCalibrationFrameBytes = null;
      _triggerCalibrationFrameSize = null;
      _triggerEditViewportCorners = const <Offset>[];
      _triggerDragging = false;
      _movingTriggerPolygon = false;
      _activeTriggerResizeHandle = null;
      _triggerResizeRejectedDuringGesture = false;
      _triggerCornerFeedbackIndex = null;
      _triggerCornerRejectedIndex = null;
    }
    SensorDebugTrace.record(
      'SensorTrigger',
      'edit_visuals_released',
      <String, Object?>{
        'source': source,
        'hadFrame': hadFrame,
        'hadViewportPolygon': hadViewportZone,
      },
    );
  }

  void _publishCoordinateGeometry({required String source}) {
    if (!mounted) return;
    final viewportSize = _currentPreviewViewportSize();
    final description = _cameraDescription;
    if (viewportSize == null || description == null) return;
    final previewSourceSize = _orientedPreviewSourceSize(viewportSize);
    if (previewSourceSize == null) return;
    final mapper = SensorCameraCoordinateMapper(
      previewSourceSize: previewSourceSize,
      cameraImageSize: _lastCameraImageSize,
      viewportSize: viewportSize,
      fit: BoxFit.cover,
    );
    final imageSize = _lastCameraImageSize;
    final signature = <Object?>[
      viewportSize.width.round(),
      viewportSize.height.round(),
      previewSourceSize.width.round(),
      previewSourceSize.height.round(),
      imageSize?.width.round(),
      imageSize?.height.round(),
      _cameraGeometrySource,
      description.sensorOrientation,
      description.lensDirection.name,
    ].join(':');
    if (_lastCoordinateSignature != signature) {
      _lastCoordinateSignature = signature;
      SensorDebugTrace.record(
        'SensorCoordinate',
        'mapper_snapshot',
        <String, Object?>{
          ...mapper.diagnostics(),
          'geometrySource': _cameraGeometrySource,
          'sensorOrientation': description.sensorOrientation,
          'lensDirection': description.lensDirection.name,
          'source': source,
        },
      );
    }
    context.read<SensorDetectionState>().updateCoordinateGeometry(
          previewViewportSize: viewportSize,
          cameraPreviewSourceSize: previewSourceSize,
          cameraImageSize: imageSize,
          coordinateFit: BoxFit.cover.name,
          sensorOrientation: description.sensorOrientation,
          lensDirection: description.lensDirection.name,
          cameraGeometrySource: _cameraGeometrySource,
          source: source,
        );
  }

  Future<bool> _ensureTriggerCameraGeometry() async {
    if (_triggerCalibrationFrameBytes != null &&
        _triggerCalibrationFrameSize != null &&
        _lastCameraImageSize != null) {
      return true;
    }
    if (_triggerGeometryPreparing || !mounted) return false;
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      SensorDebugTrace.record(
        'SensorCoordinate',
        'calibration_rejected_camera_unavailable',
      );
      return false;
    }

    setState(() {
      _triggerGeometryPreparing = true;
    });
    SensorDebugTrace.publishStatus(
      'SensorCoordinate',
      'calibration_started',
      title: '카메라 좌표 보정 중',
      detail: _activePreset?.name,
      tone: SensorDebugStatusTone.progress,
      sticky: true,
      details: <String, Object?>{
        'preset': _activePreset?.name,
        'camera': _cameraDescription?.name,
      },
    );

    var waitCount = 0;
    while (mounted && _capturing && waitCount < 80) {
      await Future<void>.delayed(const Duration(milliseconds: 25));
      waitCount++;
    }
    if (!mounted) return false;
    if (_capturing) {
      SensorDebugTrace.publishStatus(
        'SensorCoordinate',
        'calibration_capture_busy_timeout',
        title: '카메라 좌표 보정 지연',
        detail: '캡처 사용 중',
        tone: SensorDebugStatusTone.warning,
        details: <String, Object?>{'waitCount': waitCount},
      );
      setState(() {
        _triggerGeometryPreparing = false;
      });
      return false;
    }

    _capturing = true;
    String? capturedPath;
    try {
      final captured = await controller.takePicture();
      capturedPath = captured.path;
      final frame = await _geometryReader.readOrientedFrame(captured.path);
      final imageSize = frame.size;
      _lastCameraImageSize = imageSize;
      _cameraGeometrySource = 'trigger_calibration_capture';
      _lastCoordinateSignature = null;
      if (mounted) {
        setState(() {
          _triggerCalibrationFrameBytes = frame.bytes;
          _triggerCalibrationFrameSize = frame.size;
        });
        _publishCoordinateGeometry(source: 'trigger_calibration_capture');
      }
      SensorDebugTrace.publishStatus(
        'SensorCoordinate',
        'calibration_completed',
        title: '카메라 좌표 보정 완료',
        detail: '${imageSize.width.round()}×${imageSize.height.round()}',
        tone: SensorDebugStatusTone.success,
        details: <String, Object?>{
          'imageWidth': imageSize.width.round(),
          'imageHeight': imageSize.height.round(),
          'frameBytes': frame.bytes.length,
          'waitCount': waitCount,
        },
      );
      return true;
    } catch (error, stackTrace) {
      if (mounted) {
        setState(() {
          _triggerCalibrationFrameBytes = null;
          _triggerCalibrationFrameSize = null;
        });
      }
      SensorDebugTrace.publishStatus(
        'SensorCoordinate',
        'calibration_failed',
        title: '카메라 좌표 보정 실패',
        detail: error.toString(),
        tone: SensorDebugStatusTone.error,
        sticky: true,
        details: <String, Object?>{
          'error': error,
          'stack': stackTrace,
        },
      );
      return false;
    } finally {
      if (capturedPath != null) {
        try {
          final file = File(capturedPath);
          if (file.existsSync()) {
            file.deleteSync();
          }
        } catch (_) {}
      }
      _capturing = false;
      if (mounted) {
        setState(() {
          _triggerGeometryPreparing = false;
        });
      }
    }
  }

  List<Offset> _cameraZoneToViewport(
    SensorCameraCoordinateMapper mapper,
    SensorTriggerZone zone,
  ) {
    return mapper.cameraImageNormalizedPolygonToViewport(zone.points);
  }

  void _publishTriggerEditStatus({
    required SensorTriggerZone? zone,
    required List<Offset> viewportCorners,
    required String source,
    required int placementCount,
  }) {
    final title = placementCount < 4
        ? '주차 구역 꼭짓점 ${placementCount}/4'
        : '주차 구역 조정 중';
    SensorDebugTrace.publishStatus(
      'SensorTrigger',
      'edit_active',
      title: title,
      detail: zone == null
          ? null
          : '면적 ${(zone.area * 100).toStringAsFixed(1)}% · 최소변 ${(zone.minEdge * 100).toStringAsFixed(1)}%',
      tone: SensorDebugStatusTone.info,
      sticky: true,
      details: <String, Object?>{
        'source': source,
        'placementCount': placementCount,
        'polygonValid': zone?.isValid,
        'polygonArea': zone?.area.toStringAsFixed(4),
        'polygonMinEdge': zone?.minEdge.toStringAsFixed(4),
        'entryEdge': zone?.entryEdgeType.name,
        'p1x': zone?.point1.dx.toStringAsFixed(4),
        'p1y': zone?.point1.dy.toStringAsFixed(4),
        'p2x': zone?.point2.dx.toStringAsFixed(4),
        'p2y': zone?.point2.dy.toStringAsFixed(4),
        'p3x': zone?.point3.dx.toStringAsFixed(4),
        'p3y': zone?.point3.dy.toStringAsFixed(4),
        'p4x': zone?.point4.dx.toStringAsFixed(4),
        'p4y': zone?.point4.dy.toStringAsFixed(4),
        'viewportCorners': viewportCorners
            .map((point) => '${point.dx.toStringAsFixed(1)},${point.dy.toStringAsFixed(1)}')
            .join('|'),
        'frameWidth': _triggerCalibrationFrameSize?.width.round(),
        'frameHeight': _triggerCalibrationFrameSize?.height.round(),
      },
    );
  }

  Future<void> _beginTriggerEdit(Size viewportSize) async {
    final detectionState = context.read<SensorDetectionState>();
    if (detectionState.ocrActive ||
        detectionState.phase == SensorDetectionPhase.detected ||
        detectionState.phase == SensorDetectionPhase.ocrActive ||
        _triggerGeometryPreparing) {
      SensorDebugTrace.record(
        'SensorTrigger',
        'edit_rejected_detection_phase',
        <String, Object?>{
          'phase': detectionState.phase.name,
          'ocrActive': detectionState.ocrActive,
          'geometryPreparing': _triggerGeometryPreparing,
        },
      );
      return;
    }
    final geometryReady = await _ensureTriggerCameraGeometry();
    if (!geometryReady || !mounted) {
      await HapticFeedback.heavyImpact();
      return;
    }
    final resolvedViewportSize = _currentPreviewViewportSize() ?? viewportSize;
    final mapper = _coordinateMapper(resolvedViewportSize);
    if (mapper == null || !mapper.isCameraImageReady) {
      SensorDebugTrace.record(
        'SensorTrigger',
        'edit_rejected_mapper_unavailable',
        <String, Object?>{
          'geometryReady': geometryReady,
          'viewportWidth': resolvedViewportSize.width.round(),
          'viewportHeight': resolvedViewportSize.height.round(),
        },
      );
      _releaseTriggerEditVisuals(source: 'mapper_unavailable');
      await HapticFeedback.heavyImpact();
      return;
    }
    final triggerState = context.read<SensorTriggerPointState>();
    final savedZone = triggerState.savedCameraZone;
    final legacyZone = triggerState.legacyCameraZone;
    final initialZone = savedZone ?? legacyZone;
    final initialSource = savedZone != null
        ? 'saved_polygon_visible'
        : legacyZone != null
            ? 'legacy_zone_edit_seed'
            : 'four_corner_placement';
    final started = triggerState.beginEdit(
      initialCameraZone: initialZone,
      initialSource: initialSource,
    );
    if (!started) {
      _releaseTriggerEditVisuals(source: 'edit_rejected_state');
      return;
    }
    final viewportCorners = initialZone == null
        ? const <Offset>[]
        : _cameraZoneToViewport(mapper, initialZone);
    setState(() {
      _triggerEditViewportCorners = viewportCorners;
      _triggerDragging = false;
      _movingTriggerPolygon = false;
      _activeTriggerResizeHandle = null;
      _triggerResizeRejectedDuringGesture = false;
      _triggerCornerFeedbackIndex = null;
      _triggerCornerRejectedIndex = null;
    });
    _publishTriggerEditStatus(
      zone: initialZone,
      viewportCorners: viewportCorners,
      source: initialSource,
      placementCount: triggerState.placementCount,
    );
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    detectionState.resetSamplingCounters(source: 'trigger_edit_started');
    _scanController.stop();
    _scanController.value = 0.5;
  }

  Future<void> _saveTrigger() async {
    final triggerState = context.read<SensorTriggerPointState>();
    if (triggerState.draftCameraZone == null ||
        !triggerState.draftCameraZone!.isValid) {
      SensorDebugTrace.publishStatus(
        'SensorTrigger',
        'save_rejected_polygon_incomplete',
        title: '주차 구역 설정 필요',
        detail: '${triggerState.placementCount}/4',
        tone: SensorDebugStatusTone.warning,
        sticky: true,
      );
      await HapticFeedback.heavyImpact();
      return;
    }
    SensorDebugTrace.publishStatus(
      'SensorTrigger',
      'save_in_progress',
      title: '주차 구역 저장 중',
      tone: SensorDebugStatusTone.progress,
      sticky: true,
    );
    final saved = await triggerState.saveDraft();
    if (!mounted) return;
    if (saved) {
      await _baselineStore.clear(triggerState.area);
      _baselineLoadKey = null;
      _occupancyBaseline = null;
      _baselineMissingStatusPublished = false;
      context.read<SensorDetectionState>().updateBaselineDiagnostics(
            ready: false,
            source: 'trigger_polygon_saved',
          );
      SensorDebugTrace.publishStatus(
        'SensorTrigger',
        'save_completed',
        title: '주차 구역 저장 완료',
        detail: triggerState.area,
        tone: SensorDebugStatusTone.success,
      );
      await HapticFeedback.mediumImpact();
      if (!mounted) return;
      _releaseTriggerEditVisuals(source: 'save');
      context.read<SensorDetectionState>().resetSamplingCounters(
            source: 'trigger_saved',
          );
      _scanController.stop();
      _scanController.value = 0.5;
      _scanEnabledCache = false;
    } else {
      SensorDebugTrace.publishStatus(
        'SensorTrigger',
        'save_failed_status',
        title: '주차 구역 저장 실패',
        detail: triggerState.lastError,
        tone: SensorDebugStatusTone.error,
        sticky: true,
      );
      await HapticFeedback.heavyImpact();
    }
  }

  Future<void> _cancelTriggerEdit() async {
    final triggerState = context.read<SensorTriggerPointState>();
    if (!triggerState.isEditing) return;
    triggerState.cancelEdit();
    SensorDebugTrace.publishStatus(
      'SensorTrigger',
      'edit_cancelled_status',
      title: '주차 구역 편집 취소',
      tone: SensorDebugStatusTone.info,
    );
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    _releaseTriggerEditVisuals(source: 'cancel');
    context.read<SensorDetectionState>().resetSamplingCounters(
          source: 'trigger_edit_cancelled',
        );
    _scanEnabledCache = null;
  }

  void _handleTriggerTap(
    Offset localPosition,
    SensorCameraCoordinateMapper mapper,
  ) {
    final triggerState = context.read<SensorTriggerPointState>();
    if (!triggerState.isEditing) return;
    if (triggerState.placementComplete) {
      final zone = triggerState.draftCameraZone;
      if (zone == null) return;
      final viewportCorners = _cameraZoneToViewport(mapper, zone);
      final entryEdge = _nearestTriggerEdge(
        localPosition,
        viewportCorners,
      );
      if (entryEdge == null) return;
      final changed = triggerState.selectDraftEntryEdge(entryEdge);
      if (!changed) return;
      final nextZone = triggerState.draftCameraZone;
      if (nextZone == null) return;
      setState(() {
        _triggerEditViewportCorners = _cameraZoneToViewport(mapper, nextZone);
      });
      SensorDebugTrace.record(
        'SensorTrigger',
        'entry_edge_tapped',
        <String, Object?>{
          'entryEdge': entryEdge.name,
          'tapX': localPosition.dx.toStringAsFixed(1),
          'tapY': localPosition.dy.toStringAsFixed(1),
          'zone': nextZone.fingerprint,
        },
      );
      if (DevAuth.devModeEnabled.value) {
        SensorDebugTrace.publishStatus(
          'SensorTrigger',
          'entry_edge_selected_status',
          title: '진입 변 변경',
          detail: entryEdge.name,
          tone: SensorDebugStatusTone.info,
          details: <String, Object?>{
            'entryEdge': entryEdge.name,
            'zone': nextZone.fingerprint,
          },
        );
      }
      _publishTriggerEditStatus(
        zone: nextZone,
        viewportCorners: _triggerEditViewportCorners,
        source: 'entry_edge_tap',
        placementCount: 4,
      );
      unawaited(HapticFeedback.selectionClick());
      return;
    }
    final cameraPoint = mapper.viewportToCameraImageNormalized(localPosition);
    final added = triggerState.addDraftCameraCorner(cameraPoint);
    if (!added) {
      SensorDebugTrace.publishStatus(
        'SensorTrigger',
        'corner_rejected',
        title: '주차 구역 꼭짓점 다시 지정',
        detail: '${triggerState.placementCount}/4',
        tone: SensorDebugStatusTone.warning,
        sticky: true,
      );
      unawaited(HapticFeedback.heavyImpact());
      return;
    }
    final viewportCorners = triggerState.draftCameraCorners
        .map(mapper.cameraImageNormalizedToViewport)
        .toList(growable: false);
    setState(() {
      _triggerEditViewportCorners = viewportCorners;
    });
    final zone = triggerState.draftCameraZone;
    final placementCount = triggerState.placementCount;
    final viewportPoint = viewportCorners.isEmpty ? null : viewportCorners.last;
    SensorDebugTrace.record(
      'SensorTrigger',
      'corner_set',
      <String, Object?>{
        'corner': placementCount,
        'cameraX': cameraPoint.dx.toStringAsFixed(4),
        'cameraY': cameraPoint.dy.toStringAsFixed(4),
        'viewportX': viewportPoint == null ? null : viewportPoint.dx.toStringAsFixed(1),
        'viewportY': viewportPoint == null ? null : viewportPoint.dy.toStringAsFixed(1),
        'placementCount': placementCount,
        'polygonComplete': triggerState.placementComplete,
        'polygonArea': zone?.area.toStringAsFixed(4),
        'polygonValid': zone?.isValid,
        'entryEdge': zone?.entryEdgeType.name,
      },
    );
    if (triggerState.placementComplete && zone != null) {
      SensorDebugTrace.record(
        'SensorTrigger',
        'polygon_completed',
        <String, Object?>{
          'polygonArea': zone.area.toStringAsFixed(4),
          'polygonMinEdge': zone.minEdge.toStringAsFixed(4),
          'polygonConvex': zone.isConvex,
          'polygonSelfIntersecting': zone.selfIntersecting,
          'entryEdge': zone.entryEdgeType.name,
        },
      );
    }
    _publishTriggerEditStatus(
      zone: zone,
      viewportCorners: viewportCorners,
      source: 'corner_tap',
      placementCount: triggerState.placementCount,
    );
    unawaited(HapticFeedback.selectionClick());
  }

  SensorTriggerZoneEdge? _nearestTriggerEdge(
    Offset point,
    List<Offset> corners, {
    double maximumDistance = 30,
  }) {
    if (corners.length != 4) return null;
    final candidates = <SensorTriggerZoneEdge, List<int>>{
      SensorTriggerZoneEdge.edge12: const <int>[0, 1],
      SensorTriggerZoneEdge.edge23: const <int>[1, 2],
      SensorTriggerZoneEdge.edge34: const <int>[2, 3],
      SensorTriggerZoneEdge.edge41: const <int>[3, 0],
    };
    SensorTriggerZoneEdge? best;
    var bestDistance = maximumDistance;
    for (final entry in candidates.entries) {
      final start = corners[entry.value[0]];
      final end = corners[entry.value[1]];
      final segment = end - start;
      final lengthSquared = segment.dx * segment.dx + segment.dy * segment.dy;
      if (lengthSquared <= 0.0001) continue;
      final relative = point - start;
      final projection =
          ((relative.dx * segment.dx + relative.dy * segment.dy) / lengthSquared)
              .clamp(0.0, 1.0)
              .toDouble();
      final projected = start + segment * projection;
      final distance = (point - projected).distance;
      if (distance <= bestDistance) {
        bestDistance = distance;
        best = entry.key;
      }
    }
    return best;
  }

  void _beginTriggerMove(
    Offset localPosition,
    List<Offset> viewportCorners,
  ) {
    if (viewportCorners.length != 4) return;
    final path = Path()..moveTo(viewportCorners.first.dx, viewportCorners.first.dy);
    for (final point in viewportCorners.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    if (!path.contains(localPosition)) return;
    setState(() {
      _triggerDragging = true;
      _movingTriggerPolygon = true;
    });
    SensorDebugTrace.record('SensorTrigger', 'polygon_move_started');
  }

  void _updateTriggerMove(
    Offset delta,
    SensorCameraCoordinateMapper mapper,
  ) {
    if (!_movingTriggerPolygon) return;
    final triggerState = context.read<SensorTriggerPointState>();
    final zone = triggerState.draftCameraZone;
    if (zone == null) return;
    final currentViewport = _cameraZoneToViewport(mapper, zone);
    if (currentViewport.length != 4) return;
    final nextViewport = currentViewport.map((point) => point + delta).toList();
    final nextCamera = mapper.viewportPolygonToCameraImageNormalized(nextViewport);
    final candidate = SensorTriggerZone.tryFromPoints(
      nextCamera,
      entryEdgeType: zone.entryEdgeType,
    );
    if (candidate == null) return;
    triggerState.updateDraftCameraZone(candidate);
    setState(() {
      _triggerEditViewportCorners = _cameraZoneToViewport(mapper, candidate);
    });
  }

  void _endTriggerMove() {
    final triggerState = context.read<SensorTriggerPointState>();
    final zone = triggerState.draftCameraZone;
    final corners = _triggerEditViewportCorners;
    if (mounted) {
      setState(() {
        _triggerDragging = false;
        _movingTriggerPolygon = false;
      });
    }
    if (zone != null) {
      _publishTriggerEditStatus(
        zone: zone,
        viewportCorners: corners,
        source: 'polygon_move_end',
        placementCount: 4,
      );
    }
  }

  void _beginTriggerResize(SensorTriggerZoneHandle handle) {
    if (!mounted) return;
    setState(() {
      _triggerDragging = true;
      _movingTriggerPolygon = false;
      _activeTriggerResizeHandle = handle;
      _triggerResizeRejectedDuringGesture = false;
      _triggerCornerRejectedIndex = null;
    });
    SensorDebugTrace.record(
      'SensorTrigger',
      'corner_drag_started',
      <String, Object?>{'corner': handle.index + 1},
    );
  }

  void _updateTriggerResize(
    SensorTriggerZoneHandle handle,
    Offset delta,
    SensorCameraCoordinateMapper mapper,
  ) {
    final triggerState = context.read<SensorTriggerPointState>();
    final currentZone = triggerState.draftCameraZone;
    if (!triggerState.isEditing || currentZone == null) return;
    final viewportCorners = _cameraZoneToViewport(mapper, currentZone);
    if (viewportCorners.length != 4) return;
    final index = handle.index;
    final nextPoint = viewportCorners[index] + delta;
    final cameraPoint = mapper.viewportToCameraImageNormalized(nextPoint);
    final nextZone = currentZone.resizeCorner(handle, cameraPoint);
    final rejected = identical(nextZone, currentZone) ||
        nextZone.fingerprint == currentZone.fingerprint;
    if (rejected) {
      if (!_triggerResizeRejectedDuringGesture && mounted) {
        setState(() {
          _triggerResizeRejectedDuringGesture = true;
          _triggerCornerRejectedIndex = handle.index;
          _triggerCornerRejectedSerial++;
        });
        unawaited(HapticFeedback.heavyImpact());
      }
      return;
    }
    triggerState.updateDraftCameraZone(nextZone);
    setState(() {
      _triggerEditViewportCorners = _cameraZoneToViewport(mapper, nextZone);
    });
  }

  void _endTriggerResize() {
    final triggerState = context.read<SensorTriggerPointState>();
    final zone = triggerState.draftCameraZone;
    final handle = _activeTriggerResizeHandle;
    final rejected = _triggerResizeRejectedDuringGesture;
    if (mounted) {
      setState(() {
        _triggerDragging = false;
        if (handle != null && !rejected) {
          _triggerCornerFeedbackIndex = handle.index;
          _triggerCornerFeedbackSerial++;
        }
        _activeTriggerResizeHandle = null;
        _triggerResizeRejectedDuringGesture = false;
      });
    }
    if (zone != null) {
      SensorDebugTrace.record(
        'SensorTrigger',
        rejected ? 'corner_drag_limited' : 'corner_drag_end',
        <String, Object?>{
          'corner': handle == null ? null : handle.index + 1,
          'limited': rejected,
          'polygonArea': zone.area.toStringAsFixed(4),
          'polygonMinEdge': zone.minEdge.toStringAsFixed(4),
          'polygonValid': zone.isValid,
          'polygonConvex': zone.isConvex,
          'polygonSelfIntersecting': zone.selfIntersecting,
        },
      );
      _publishTriggerEditStatus(
        zone: zone,
        viewportCorners: _triggerEditViewportCorners,
        source: rejected ? 'corner_drag_limited' : 'corner_drag_end',
        placementCount: 4,
      );
    }
  }

  Future<void> _ensureBaselineLoaded(
    String area,
    SensorTriggerZone zone,
  ) async {
    final key = '${area.trim()}|${zone.fingerprint}';
    if (_baselineLoading || _baselineLoadKey == key) return;
    if (_baselineLoadKey != key) {
      _baselineMissingStatusPublished = false;
    }
    _baselineLoading = true;
    _baselineLoadKey = key;
    try {
      final loaded = await _baselineStore.load(area);
      final compatibleBaseline = loaded != null && loaded.zone.roughlyEquals(zone)
          ? loaded
          : null;
      if (!mounted || _baselineLoadKey != key) return;
      setState(() {
        _occupancyBaseline = compatibleBaseline;
      });
      if (compatibleBaseline != null) {
        _baselineMissingStatusPublished = false;
        context.read<SensorDetectionState>().updateBaselineDiagnostics(
              ready: true,
              savedAt: compatibleBaseline.savedAt.toIso8601String(),
              source: 'baseline_loaded',
            );
        SensorDebugTrace.record(
          'SensorOccupancy',
          'baseline_loaded',
          <String, Object?>{
            'area': area,
            'zone': zone.fingerprint,
            'savedAt': compatibleBaseline.savedAt.toIso8601String(),
          },
        );
      } else {
        context.read<SensorDetectionState>().updateBaselineDiagnostics(
              ready: false,
              source: 'baseline_missing_or_incompatible',
            );
        if (!_baselineMissingStatusPublished) {
          _baselineMissingStatusPublished = true;
        SensorDebugTrace.publishStatus(
          'SensorOccupancy',
          'baseline_required',
          title: '빈 주차면 기준 필요',
          detail: area,
          tone: SensorDebugStatusTone.warning,
          sticky: true,
          details: <String, Object?>{
            'area': area,
            'zone': zone.fingerprint,
            'storedBaseline': loaded != null,
            'zoneCompatible': compatibleBaseline != null,
          },
        );
        }
      }
    } catch (error, stackTrace) {
      if (!mounted || _baselineLoadKey != key) return;
      setState(() {
        _occupancyBaseline = null;
      });
      context.read<SensorDetectionState>().updateBaselineDiagnostics(
            ready: false,
            source: 'baseline_load_failed',
          );
      SensorDebugTrace.publishStatus(
        'SensorOccupancy',
        'baseline_load_failed',
        title: '빈 주차면 기준 불러오기 실패',
        detail: error.toString(),
        tone: SensorDebugStatusTone.error,
        sticky: true,
        details: <String, Object?>{
          'error': error,
          'stack': stackTrace,
        },
      );
    } finally {
      _baselineLoading = false;
    }
  }

  Future<void> _saveEmptyBaseline() async {
    if (!mounted || _baselineSaving || _routeActive) return;
    if (_capturing) {
      SensorDebugTrace.publishStatus(
        'SensorOccupancy',
        'baseline_save_capture_busy',
        title: '빈 주차면 기준 저장 대기',
        detail: '카메라 캡처 사용 중',
        tone: SensorDebugStatusTone.info,
      );
      return;
    }
    final triggerState = context.read<SensorTriggerPointState>();
    final zone = triggerState.savedCameraZone;
    final area = triggerState.area.trim();
    final controller = _cameraController;
    if (zone == null ||
        area.isEmpty ||
        controller == null ||
        !controller.value.isInitialized) {
      SensorDebugTrace.publishStatus(
        'SensorOccupancy',
        'baseline_save_rejected',
        title: '빈 주차면 기준 저장 불가',
        tone: SensorDebugStatusTone.warning,
        details: <String, Object?>{
          'area': area,
          'zoneReady': zone != null,
          'cameraReady': controller?.value.isInitialized ?? false,
        },
      );
      return;
    }
    if (controller.value.isTakingPicture) {
      SensorDebugTrace.publishStatus(
        'SensorOccupancy',
        'baseline_save_camera_busy',
        title: '빈 주차면 기준 저장 대기',
        detail: '카메라 캡처 사용 중',
        tone: SensorDebugStatusTone.info,
      );
      return;
    }
    final currentBaseline = _occupancyBaseline;
    if (currentBaseline != null && currentBaseline.zone.roughlyEquals(zone)) {
      SensorDebugTrace.publishStatus(
        'SensorOccupancy',
        'baseline_save_ignored_ready',
        title: '빈 주차면 기준 저장 완료',
        detail: area,
        tone: SensorDebugStatusTone.success,
        details: <String, Object?>{
          'savedAt': currentBaseline.savedAt.toIso8601String(),
          'zone': zone.fingerprint,
        },
      );
      return;
    }
    setState(() {
      _baselineSaving = true;
    });
    _capturing = true;
    _scanController.stop();
    _scanController.value = 0.5;
    _scanEnabledCache = false;
    SensorDebugTrace.publishStatus(
      'SensorOccupancy',
      'baseline_save_started',
      title: '빈 주차면 기준 저장 중',
      detail: area,
      tone: SensorDebugStatusTone.progress,
      sticky: true,
      details: <String, Object?>{
        'zone': zone.fingerprint,
        'sampleTarget': 3,
      },
    );
    try {
      final features = <SensorOccupancyFeature>[];
      for (var index = 0; index < 3; index++) {
        String? capturedPath;
        try {
          final captured = await controller.takePicture();
          capturedPath = captured.path;
          final objectResult = await _detector.detectFile(captured.path);
          final baselineObjectMatch =
              objectResult.matchZone(zone);
          _updateDetectionVisualization(
            objectResult,
            baselineObjectMatch.matchedIndexes,
            bottomCenterMatchedIndexes:
                baselineObjectMatch.bottomCenterMatchedIndexes,
          );
          final strongBaselineEvidence = baselineObjectMatch.evidences.any(
            (evidence) =>
                evidence.polygonCoverage >=
                    SensorRecognitionGate.strongMlCoverageThreshold &&
                evidence.boundingBoxAreaRatio >=
                    SensorRecognitionGate.strongMlBoundingBoxThreshold,
          );
          SensorDebugTrace.record(
            'SensorOccupancy',
            'baseline_object_check',
            <String, Object?>{
              'sample': index + 1,
              'objectCount': objectResult.objectCount,
              'matchedCount': baselineObjectMatch.matchedCount,
              'bottomCenterMatched':
                  baselineObjectMatch.bottomCenterMatched,
              'bottomCenterMatchedCount':
                  baselineObjectMatch.bottomCenterMatchedCount,
              'strongMlEvidence': strongBaselineEvidence,
              'polygonCoverage':
                  baselineObjectMatch.maxPolygonCoverage.toStringAsFixed(4),
              'bboxAreaRatio': baselineObjectMatch.maxBoundingBoxAreaRatio
                  .toStringAsFixed(4),
            },
          );
          if (DevAuth.devModeEnabled.value) {
            for (final evidence in baselineObjectMatch.evidences) {
              final box = evidence.boundingBox;
              final point = evidence.bottomCenter;
              SensorDebugTrace.record(
                'SensorOccupancy',
                'baseline_object_detail',
                <String, Object?>{
                  'sample': index + 1,
                  'index': evidence.index,
                  'left': box.left.toStringAsFixed(4),
                  'top': box.top.toStringAsFixed(4),
                  'right': box.right.toStringAsFixed(4),
                  'bottom': box.bottom.toStringAsFixed(4),
                  'bottomCenterX': point.dx.toStringAsFixed(4),
                  'bottomCenterY': point.dy.toStringAsFixed(4),
                  'polygonCoverage':
                      evidence.polygonCoverage.toStringAsFixed(4),
                  'bboxAreaRatio':
                      evidence.boundingBoxAreaRatio.toStringAsFixed(4),
                  'bottomCenterInside': evidence.bottomCenterInside,
                  'closeOverlap': evidence.closeOverlap,
                  'largeOverlap': evidence.largeOverlap,
                  'bottomCenterEntry': evidence.bottomCenterEntry,
                  'matched': evidence.matched,
                },
              );
            }
          }
          if (baselineObjectMatch.matched) {
            final evidenceDetails = <String, Object?>{
              'sample': index + 1,
              'objectCount': objectResult.objectCount,
              'matchedCount': baselineObjectMatch.matchedCount,
              'strongMlEvidence': strongBaselineEvidence,
              'bottomCenterMatched':
                  baselineObjectMatch.bottomCenterMatched,
              'bottomCenterMatchedCount':
                  baselineObjectMatch.bottomCenterMatchedCount,
              'polygonCoverage':
                  baselineObjectMatch.maxPolygonCoverage.toStringAsFixed(4),
              'bboxAreaRatio': baselineObjectMatch.maxBoundingBoxAreaRatio
                  .toStringAsFixed(4),
            };
            SensorDebugTrace.record(
              'SensorOccupancy',
              'baseline_object_evidence_ignored',
              evidenceDetails,
            );
            if (DevAuth.devModeEnabled.value) {
              SensorDebugTrace.publishStatus(
                'SensorOccupancy',
                'baseline_object_evidence_warning',
                title: '기준 저장 객체 감지',
                detail:
                    '샘플 ${index + 1} · 겹침 ${(baselineObjectMatch.maxPolygonCoverage * 100).toStringAsFixed(1)}%',
                tone: SensorDebugStatusTone.warning,
                sticky: false,
                details: evidenceDetails,
              );
            }
          }
          final feature =
              await _occupancyAnalyzer.extractFeature(captured.path, zone);
          if (features.isNotEmpty) {
            final stability = _occupancyAnalyzer.compare(features.first, feature);
            SensorDebugTrace.record(
              'SensorOccupancy',
              'baseline_stability_sample',
              <String, Object?>{
                'sample': index + 1,
                'structureChange':
                    stability.structureChangeScore.toStringAsFixed(4),
                'changedCellRatio':
                    stability.changedCellRatio.toStringAsFixed(4),
                'baselineSimilarity':
                    stability.baselineSimilarity.toStringAsFixed(4),
                'stable': stability.clearLike,
              },
            );
            if (!stability.clearLike) {
              throw StateError('Sensor occupancy baseline is unstable.');
            }
          }
          features.add(feature);
        } finally {
          if (capturedPath != null) {
            try {
              final file = File(capturedPath);
              if (file.existsSync()) {
                file.deleteSync();
              }
            } catch (_) {}
          }
        }
        if (index < 2) {
          await Future<void>.delayed(const Duration(milliseconds: 280));
        }
      }
      final mergedFeature = _occupancyAnalyzer.mergeFeatures(features);
      final baseline = SensorOccupancyBaseline(
        area: area,
        zone: zone,
        feature: mergedFeature,
        savedAt: DateTime.now(),
      );
      final saved = await _baselineStore.save(baseline);
      if (!saved) {
        throw StateError('Sensor occupancy baseline persistence failed.');
      }
      if (!mounted) return;
      setState(() {
        _occupancyBaseline = baseline;
        _baselineLoadKey = '$area|${zone.fingerprint}';
        _baselineMissingStatusPublished = false;
      });
      context.read<SensorDetectionState>()
        ..updateBaselineDiagnostics(
          ready: true,
          savedAt: baseline.savedAt.toIso8601String(),
          source: 'baseline_saved',
        )
        ..resetSamplingCounters(
          source: 'occupancy_baseline_saved',
        );
      _scanEnabledCache = null;
      SensorDebugTrace.publishStatus(
        'SensorOccupancy',
        'baseline_saved',
        title: '빈 주차면 기준 저장 완료',
        detail: area,
        tone: SensorDebugStatusTone.success,
        details: <String, Object?>{
          'zone': zone.fingerprint,
          'featureWidth': mergedFeature.width,
          'featureHeight': mergedFeature.height,
          'sampleCount': features.length,
          'savedAt': baseline.savedAt.toIso8601String(),
        },
      );
      await HapticFeedback.mediumImpact();
    } catch (error, stackTrace) {
      SensorDebugTrace.publishStatus(
        'SensorOccupancy',
        'baseline_save_failed',
        title: '빈 주차면 기준 저장 실패',
        detail: error.toString(),
        tone: SensorDebugStatusTone.error,
        sticky: true,
        details: <String, Object?>{
          'error': error,
          'stack': stackTrace,
        },
      );
      await HapticFeedback.heavyImpact();
    } finally {
      _capturing = false;
      if (mounted) {
        setState(() {
          _baselineSaving = false;
        });
        _scanEnabledCache = null;
      }
    }
  }

  void _updateDetectionVisualization(
    SensorObjectDetectionResult result,
    List<int> matchedIndexes, {
    List<int> bottomCenterMatchedIndexes = const <int>[],
    bool entryActive = false,
    bool entryTriggered = false,
  }) {
    final nextImageSize = Size(
      result.imageWidth.toDouble(),
      result.imageHeight.toDouble(),
    );
    final sizeChanged = _lastCameraImageSize != nextImageSize;
    final devMode = DevAuth.devModeEnabled.value;
    _lastCameraImageSize = nextImageSize;
    _cameraGeometrySource = 'detector_result';
    if (devMode) {
      final boxes = result.normalizedBoundingBoxes
          .map(
            (rect) =>
                '${rect.left.toStringAsFixed(3)},${rect.top.toStringAsFixed(3)},${rect.right.toStringAsFixed(3)},${rect.bottom.toStringAsFixed(3)}',
          )
          .join(';');
      SensorDebugTrace.record(
        'SensorCoordinate',
        'bbox_sample',
        <String, Object?>{
          'imageWidth': result.imageWidth,
          'imageHeight': result.imageHeight,
          'boxes': boxes,
          'matchedIndexes': matchedIndexes.join(','),
          'bottomCenterMatchedIndexes':
              bottomCenterMatchedIndexes.join(','),
          'entryActive': entryActive,
          'entryTriggered': entryTriggered,
        },
      );
    }
    if (mounted && (sizeChanged || devMode)) {
      setState(() {
        _lastCameraImageSize = nextImageSize;
        if (devMode) {
          _lastDetectionBoxes = result.normalizedBoundingBoxes;
          _lastMatchedBoxIndexes = matchedIndexes.toSet();
          _lastBottomCenterMatchedBoxIndexes =
              bottomCenterMatchedIndexes.toSet();
          _lastEntryActive = entryActive;
          _lastEntryTriggered = entryTriggered;
        }
      });
    }
    _publishCoordinateGeometry(source: 'detector_result');
  }

  void _publishDetectionSampleStatus({
    required SensorDetectionState detectionState,
    required SensorDetectionPhase phaseBefore,
    required SensorOccupancyEvidence evidence,
    required int detectedStreakBefore,
    required int clearStreakBefore,
    required SensorDetectionSampleOutcome outcome,
  }) {
    final structurePercent =
        (evidence.structureChangeScore * 100).toStringAsFixed(0);
    final overlapPercent =
        (evidence.mlPolygonCoverage * 100).toStringAsFixed(0);
    if (phaseBefore == SensorDetectionPhase.waitForClear) {
      if (outcome == SensorDetectionSampleOutcome.clearedStable) {
        SensorDebugTrace.publishStatus(
          'SensorDetection',
          'clear_stable_status',
          title: '다음 차량 감지 준비',
          detail:
              '${SensorDetectionState.minimumClearDuration.inSeconds}초 연속 비움 확인',
          tone: SensorDebugStatusTone.success,
          details: <String, Object?>{
            'structureChange':
                evidence.structureChangeScore.toStringAsFixed(4),
            'changedCellRatio':
                evidence.changedCellRatio.toStringAsFixed(4),
            'baselineSimilarity':
                evidence.baselineSimilarity.toStringAsFixed(4),
            'mlMatched': evidence.mlMatched,
            'reason': evidence.reason,
          },
        );
        return;
      }
      if (evidence.clearCandidate && detectionState.clearStreak > 0) {
        final elapsedSeconds =
            detectionState.clearElapsedMilliseconds / 1000.0;
        final requiredSeconds =
            SensorDetectionState.minimumClearDuration.inMilliseconds / 1000.0;
        SensorDebugTrace.publishStatus(
          'SensorDetection',
          'clear_progress_status',
          title:
              '차량 이탈 확인 ${detectionState.clearStreak}/${SensorDetectionState.clearThreshold}',
          detail:
              '${elapsedSeconds.toStringAsFixed(1)} / ${requiredSeconds.toStringAsFixed(1)}초 · 변화 $structurePercent%',
          tone: SensorDebugStatusTone.info,
          details: <String, Object?>{
            'structureChange':
                evidence.structureChangeScore.toStringAsFixed(4),
            'changedCellRatio':
                evidence.changedCellRatio.toStringAsFixed(4),
            'mlMatched': evidence.mlMatched,
            'reason': evidence.reason,
          },
        );
        return;
      }
      if (!evidence.clearCandidate && clearStreakBefore > 0) {
        SensorDebugTrace.publishStatus(
          'SensorDetection',
          'clear_progress_reset_status',
          title: '차량 이탈 확인 초기화',
          detail: evidence.reason,
          tone: SensorDebugStatusTone.warning,
          details: <String, Object?>{
            'structureChange':
                evidence.structureChangeScore.toStringAsFixed(4),
            'changedCellRatio':
                evidence.changedCellRatio.toStringAsFixed(4),
            'mlMatched': evidence.mlMatched,
          },
        );
      }
      return;
    }

    if (outcome == SensorDetectionSampleOutcome.detectedStable) {
      SensorDebugTrace.publishStatus(
        'SensorDetection',
        'detected_stable_status',
        title: '차량 인식 시작',
        detail: '변화 $structurePercent% · ML 겹침 $overlapPercent%',
        tone: SensorDebugStatusTone.success,
        details: <String, Object?>{
          'structureChange':
              evidence.structureChangeScore.toStringAsFixed(4),
          'changedCellRatio':
              evidence.changedCellRatio.toStringAsFixed(4),
          'mlBottomCenterMatched': evidence.mlBottomCenterMatched,
          'mlPolygonCoverage': evidence.mlPolygonCoverage.toStringAsFixed(4),
          'bboxAreaRatio':
              evidence.mlBoundingBoxAreaRatio.toStringAsFixed(4),
          'windowCount': detectionState.detectionWindowCount,
          'positiveCount': detectionState.detectionPositiveCount,
          'reason': evidence.reason,
        },
      );
      return;
    }
    if (detectionState.detectionPositiveCount > 0) {
      SensorDebugTrace.publishStatus(
        'SensorDetection',
        'detected_progress_status',
        title:
            '인식 후보 ${detectionState.detectionPositiveCount}/${SensorDetectionState.detectionRequiredPositives}',
        detail:
            '창 ${detectionState.detectionWindowCount}/${SensorDetectionState.detectionWindowSize} · 변화 $structurePercent% · ML $overlapPercent%',
        tone: SensorDebugStatusTone.info,
        details: <String, Object?>{
          'structureChange':
              evidence.structureChangeScore.toStringAsFixed(4),
          'changedCellRatio':
              evidence.changedCellRatio.toStringAsFixed(4),
          'mlBottomCenterMatched': evidence.mlBottomCenterMatched,
          'mlPolygonCoverage': evidence.mlPolygonCoverage.toStringAsFixed(4),
          'bboxAreaRatio':
              evidence.mlBoundingBoxAreaRatio.toStringAsFixed(4),
          'window': detectionState.recentDetectionSamples
              .map((value) => value ? 1 : 0)
              .join(','),
          'reason': evidence.reason,
        },
      );
      return;
    }
    if (detectedStreakBefore > 0) {
      SensorDebugTrace.publishStatus(
        'SensorDetection',
        'detected_progress_reset_status',
        title: '인식 후보 해제',
        detail: evidence.reason,
        tone: SensorDebugStatusTone.info,
        details: <String, Object?>{
          'structureChange':
              evidence.structureChangeScore.toStringAsFixed(4),
          'changedCellRatio':
              evidence.changedCellRatio.toStringAsFixed(4),
          'mlMatched': evidence.mlMatched,
          'mlBottomCenterMatched': evidence.mlBottomCenterMatched,
          'mlPolygonCoverage': evidence.mlPolygonCoverage.toStringAsFixed(4),
        },
      );
    }
  }

  void _startDetectionLoop({required String source}) {
    _loopGeneration++;
    final generation = _loopGeneration;
    SensorDebugTrace.record(
      'SensorDetectionContent',
      'loop_started',
      <String, Object?>{
        'generation': generation,
        'source': source,
        'intervalMs': _sampleInterval.inMilliseconds,
        'approachIntervalMs': _approachSampleInterval.inMilliseconds,
      },
    );
    unawaited(_detectionLoop(generation));
  }

  Future<void> _detectionLoop(int generation) async {
    while (mounted && generation == _loopGeneration && !_routeActive) {
      final workState = context.read<SensorWorkSessionState>();
      if (!workState.isActive) {
        _entryGate.reset();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        continue;
      }
      final triggerState = context.read<SensorTriggerPointState>();
      final triggerZone = triggerState.savedCameraZone;
      if (!triggerState.isReady || triggerState.isEditing) {
        _entryGate.reset();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        continue;
      }
      if (triggerZone == null) {
        _entryGate.reset();
        if (!_triggerMissingStatusPublished) {
          _triggerMissingStatusPublished = true;
          SensorDebugTrace.publishStatus(
            'SensorTrigger',
            'configuration_required',
            title: '트리거 영역 설정 필요',
            detail: triggerState.legacyCameraPoint == null
                ? null
                : '기존 트리거 위치를 영역으로 저장',
            tone: SensorDebugStatusTone.warning,
            sticky: true,
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 120));
        continue;
      }
      _triggerMissingStatusPublished = false;
      final area = triggerState.area.trim();
      await _ensureBaselineLoaded(area, triggerZone);
      if (!mounted || generation != _loopGeneration) return;
      final baseline = _occupancyBaseline;
      if (baseline == null || !baseline.zone.roughlyEquals(triggerZone)) {
        _entryGate.reset();
        await Future<void>.delayed(const Duration(milliseconds: 160));
        continue;
      }
      if (_capturing ||
          _runtimeInitializing ||
          _triggerGeometryPreparing ||
          _baselineSaving) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        continue;
      }

      final controller = _cameraController;
      if (controller == null || !controller.value.isInitialized) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
        continue;
      }
      if (controller.value.isTakingPicture) {
        await Future<void>.delayed(const Duration(milliseconds: 160));
        continue;
      }

      final detectionState = context.read<SensorDetectionState>();
      if (!detectionState.canSample) {
        _entryGate.reset();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        continue;
      }
      if (detectionState.phase != SensorDetectionPhase.armed) {
        _entryGate.reset();
      }

      _capturing = true;
      String? capturedPath;
      var launchOcr = false;
      var launchEarlyEntryOcr = false;
      var launchSource = 'stable_occupancy';
      var approachActive = false;

      try {
        final sampleStopwatch = Stopwatch()..start();
        final captured = await controller.takePicture();
        capturedPath = captured.path;
        _captureErrorStreak = 0;
        final result = await _detector.detectFile(captured.path);
        final currentFeature =
            await _occupancyAnalyzer.extractFeature(captured.path, triggerZone);
        final currentTriggerState = context.read<SensorTriggerPointState>();
        final currentZone = currentTriggerState.savedCameraZone;
        if (_triggerGeometryPreparing ||
            currentTriggerState.isEditing ||
            currentZone == null ||
            currentZone.fingerprint != triggerZone.fingerprint) {
          _entryGate.reset();
          SensorDebugTrace.record(
            'SensorTrigger',
            'sample_discarded',
            <String, Object?>{
              'editing': currentTriggerState.isEditing,
              'geometryPreparing': _triggerGeometryPreparing,
              'triggerChanged':
                  currentZone?.fingerprint != triggerZone.fingerprint,
            },
          );
          continue;
        }
        final occupancy = _occupancyAnalyzer.compare(
          baseline.feature,
          currentFeature,
        );
        final entryChange = _occupancyAnalyzer.analyzeEntryChange(
          baseline.feature,
          currentFeature,
        );
        final phaseBeforeSample = detectionState.phase;
        final recognitionZone = triggerZone.recognitionZone;
        final approachMlMatch = result.matchZone(recognitionZone);
        final mlMatch = result.matchZone(triggerZone);
        final recognitionDecision =
            _recognitionGate.evaluate(occupancy, mlMatch);
        final entryDecision = phaseBeforeSample == SensorDetectionPhase.armed
            ? _entryGate.evaluate(
                zone: triggerZone,
                entryChange: entryChange,
                occupancy: occupancy,
                mlMatch: mlMatch,
              )
            : null;
        approachActive = entryDecision?.active ?? false;
        final occupiedCandidate = recognitionDecision.candidate;
        final clearCandidate = occupancy.clearLike && !occupiedCandidate;
        final reason = clearCandidate
            ? 'baseline_clear'
            : recognitionDecision.reason;
        final evidence = SensorOccupancyEvidence(
          baselineReady: true,
          occupiedCandidate: occupiedCandidate,
          clearCandidate: clearCandidate,
          structureChangeScore: occupancy.structureChangeScore,
          changedCellRatio: occupancy.changedCellRatio,
          baselineSimilarity: occupancy.baselineSimilarity,
          mlMatched: mlMatch.matched,
          mlBottomCenterMatched: mlMatch.bottomCenterMatched,
          mlObjectCount: result.objectCount,
          mlMatchedCount: mlMatch.matchedCount,
          mlPolygonCoverage: mlMatch.maxPolygonCoverage,
          mlBoundingBoxAreaRatio: mlMatch.maxBoundingBoxAreaRatio,
          reason: reason,
        );
        sampleStopwatch.stop();
        _updateDetectionVisualization(
          result,
          mlMatch.matchedIndexes,
          bottomCenterMatchedIndexes: mlMatch.bottomCenterMatchedIndexes,
          entryActive: entryDecision?.active ?? false,
          entryTriggered: entryDecision?.triggered ?? false,
        );
        if (entryDecision != null &&
            (entryDecision.active || entryDecision.triggered)) {
          SensorDebugTrace.record(
            'SensorEntry',
            'entry_evidence',
            <String, Object?>{
              'sampleAge': entryDecision.sampleAge,
              'mlSupport': entryDecision.mlSupport,
              'changedCellRatio':
                  entryDecision.changedCellRatio.toStringAsFixed(4),
              'frontChangedCellRatio':
                  entryDecision.frontChangedCellRatio.toStringAsFixed(4),
              'spanRatio': entryDecision.spanRatio.toStringAsFixed(4),
              'depthRatio': entryDecision.depthRatio.toStringAsFixed(4),
              'coreChangedCellRatio':
                  entryDecision.coreChangedCellRatio.toStringAsFixed(4),
              'sideGuardChangedCellRatio':
                  entryDecision.sideGuardChangedCellRatio.toStringAsFixed(4),
              'coreSpanRatio': entryDecision.coreSpanRatio.toStringAsFixed(4),
              'connectedDepthRatio':
                  entryDecision.connectedDepthRatio.toStringAsFixed(4),
              'entryRootedRatio':
                  entryDecision.entryRootedRatio.toStringAsFixed(4),
              'meanDifference':
                  entryDecision.meanDifference.toStringAsFixed(4),
              'changedCellDelta':
                  entryDecision.changedCellDelta.toStringAsFixed(4),
              'frontChangedCellDelta':
                  entryDecision.frontChangedCellDelta.toStringAsFixed(4),
              'spanDelta': entryDecision.spanDelta.toStringAsFixed(4),
              'depthDelta': entryDecision.depthDelta.toStringAsFixed(4),
              'active': entryDecision.active,
              'triggered': entryDecision.triggered,
              'triggerKind': entryDecision.triggerKind.name,
              'structureChange':
                  occupancy.structureChangeScore.toStringAsFixed(4),
              'globalChangedCellRatio':
                  occupancy.changedCellRatio.toStringAsFixed(4),
            },
          );
          if (entryDecision.triggered && DevAuth.devModeEnabled.value) {
            SensorDebugTrace.publishStatus(
              'SensorEntry',
              'entry_triggered_status',
              title: '진입 감지',
              detail:
                  '${entryDecision.triggerKind.name} · 폭 ${(entryDecision.spanRatio * 100).toStringAsFixed(0)}% · 변화 ${(entryDecision.changedCellRatio * 100).toStringAsFixed(0)}%',
              tone: SensorDebugStatusTone.success,
              details: <String, Object?>{
                'triggerKind': entryDecision.triggerKind.name,
                'sampleAge': entryDecision.sampleAge,
                'mlSupport': entryDecision.mlSupport,
                'changedCellRatio':
                    entryDecision.changedCellRatio.toStringAsFixed(4),
                'frontChangedCellRatio':
                    entryDecision.frontChangedCellRatio.toStringAsFixed(4),
                'spanRatio': entryDecision.spanRatio.toStringAsFixed(4),
                'depthRatio': entryDecision.depthRatio.toStringAsFixed(4),
                'coreChangedCellRatio':
                    entryDecision.coreChangedCellRatio.toStringAsFixed(4),
                'sideGuardChangedCellRatio':
                    entryDecision.sideGuardChangedCellRatio.toStringAsFixed(4),
                'coreSpanRatio':
                    entryDecision.coreSpanRatio.toStringAsFixed(4),
                'connectedDepthRatio':
                    entryDecision.connectedDepthRatio.toStringAsFixed(4),
                'entryRootedRatio':
                    entryDecision.entryRootedRatio.toStringAsFixed(4),
                'changedCellDelta':
                    entryDecision.changedCellDelta.toStringAsFixed(4),
                'spanDelta': entryDecision.spanDelta.toStringAsFixed(4),
                'depthDelta': entryDecision.depthDelta.toStringAsFixed(4),
              },
            );
          }
        }
        if (DevAuth.devModeEnabled.value) {
          SensorDebugTrace.record(
            'SensorOccupancy',
            'evidence',
            <String, Object?>{
              'baselineReady': true,
              'occupiedCandidate': occupiedCandidate,
              'clearCandidate': clearCandidate,
              'structureChange':
                  occupancy.structureChangeScore.toStringAsFixed(4),
              'changedCellRatio':
                  occupancy.changedCellRatio.toStringAsFixed(4),
              'baselineSimilarity':
                  occupancy.baselineSimilarity.toStringAsFixed(4),
              'mlObjectCount': result.objectCount,
              'mlMatchedCount': mlMatch.matchedCount,
              'mlBottomCenterMatched': mlMatch.bottomCenterMatched,
              'mlBottomCenterMatchedCount': mlMatch.bottomCenterMatchedCount,
              'mlPolygonCoverage':
                  mlMatch.maxPolygonCoverage.toStringAsFixed(4),
              'bboxAreaRatio':
                  mlMatch.maxBoundingBoxAreaRatio.toStringAsFixed(4),
              'weakOccupancyEvidence':
                  recognitionDecision.weakOccupancyEvidence,
              'minimumOccupancyEvidence':
                  recognitionDecision.minimumOccupancyEvidence,
              'strongMlEvidence': recognitionDecision.strongMlEvidence,
              'spatialEntryEvidence':
                  recognitionDecision.spatialEntryEvidence,
              'entryActive': entryDecision?.active ?? false,
              'entryTriggered': entryDecision?.triggered ?? false,
              'entryTriggerKind': entryDecision?.triggerKind.name,
              'reason': reason,
              'elapsedMs': sampleStopwatch.elapsedMilliseconds,
              'zone': triggerZone.fingerprint,
              'recognitionZone': recognitionZone.fingerprint,
              'approachMlMatched': approachMlMatch.matched,
              'approachMlMatchedCount': approachMlMatch.matchedCount,
              'approachMlPolygonCoverage':
                  approachMlMatch.maxPolygonCoverage.toStringAsFixed(4),
            },
          );
        }
        final detectedStreakBefore = detectionState.detectedStreak;
        final clearStreakBefore = detectionState.clearStreak;
        final outcome = detectionState.registerOccupancySample(
          evidence,
          elapsedMilliseconds: sampleStopwatch.elapsedMilliseconds,
          triggerX: triggerZone.center.dx,
          triggerY: triggerZone.center.dy,
          source: 'camera_capture',
        );
        _publishDetectionSampleStatus(
          detectionState: detectionState,
          phaseBefore: phaseBeforeSample,
          evidence: evidence,
          detectedStreakBefore: detectedStreakBefore,
          clearStreakBefore: clearStreakBefore,
          outcome: outcome,
        );
        if (entryDecision?.triggered ?? false) {
          launchOcr = true;
          launchEarlyEntryOcr =
              outcome != SensorDetectionSampleOutcome.detectedStable;
          launchSource = 'entry_${entryDecision!.triggerKind.name}';
          SensorDebugTrace.record(
            'SensorEntry',
            'ocr_entry_triggered',
            <String, Object?>{
              'source': launchSource,
              'earlyEntry': launchEarlyEntryOcr,
              'sampleAge': entryDecision.sampleAge,
              'mlSupport': entryDecision.mlSupport,
              'changedCellRatio':
                  entryDecision.changedCellRatio.toStringAsFixed(4),
              'frontChangedCellRatio':
                  entryDecision.frontChangedCellRatio.toStringAsFixed(4),
              'spanRatio': entryDecision.spanRatio.toStringAsFixed(4),
              'depthRatio': entryDecision.depthRatio.toStringAsFixed(4),
              'coreChangedCellRatio':
                  entryDecision.coreChangedCellRatio.toStringAsFixed(4),
              'sideGuardChangedCellRatio':
                  entryDecision.sideGuardChangedCellRatio.toStringAsFixed(4),
              'coreSpanRatio': entryDecision.coreSpanRatio.toStringAsFixed(4),
              'connectedDepthRatio':
                  entryDecision.connectedDepthRatio.toStringAsFixed(4),
              'entryRootedRatio':
                  entryDecision.entryRootedRatio.toStringAsFixed(4),
              'changedCellDelta':
                  entryDecision.changedCellDelta.toStringAsFixed(4),
              'spanDelta': entryDecision.spanDelta.toStringAsFixed(4),
              'depthDelta': entryDecision.depthDelta.toStringAsFixed(4),
              'occupancyOutcome': outcome.name,
            },
          );
        } else if (outcome == SensorDetectionSampleOutcome.detectedStable) {
          launchOcr = true;
          launchEarlyEntryOcr = false;
          launchSource = 'stable_occupancy';
        }
      } catch (error, stackTrace) {
        final message = error.toString();
        final cameraFailure = error is CameraException ||
            message.contains('ImageCaptureException');
        if (cameraFailure) {
          _captureErrorStreak++;
        }
        SensorDebugTrace.record(
          'SensorDetectionContent',
          'sample_failed',
          <String, Object?>{
            'error': error,
            'stack': stackTrace,
            'cameraFailure': cameraFailure,
            'captureErrorStreak': _captureErrorStreak,
          },
        );
        if (cameraFailure &&
            _captureErrorStreak >= _captureErrorBackoffThreshold &&
            _captureErrorStreak < _captureErrorRecoverThreshold) {
          SensorDebugTrace.publishStatus(
            'SensorDetectionContent',
            'camera_capture_unstable_status',
            title: '카메라 캡처 불안정',
            detail:
                '$_captureErrorStreak/$_captureErrorRecoverThreshold',
            tone: SensorDebugStatusTone.warning,
          );
        }
        if (cameraFailure &&
            _captureErrorStreak >= _captureErrorRecoverThreshold) {
          await _recoverCamera();
        } else if (cameraFailure &&
            _captureErrorStreak >= _captureErrorBackoffThreshold) {
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
      } finally {
        if (capturedPath != null) {
          try {
            final file = File(capturedPath);
            if (file.existsSync()) {
              file.deleteSync();
            }
          } catch (_) {}
        }
        _capturing = false;
      }

      if (launchOcr && mounted && generation == _loopGeneration) {
        await _launchLiveOcr(
          source: launchSource,
          earlyEntry: launchEarlyEntryOcr,
        );
        return;
      }

      await Future<void>.delayed(
        approachActive ? _approachSampleInterval : _sampleInterval,
      );
    }
  }

  Future<void> _recoverCamera() async {
    final description = _cameraDescription;
    if (description == null || _routeActive || !mounted) return;
    SensorDebugTrace.publishStatus(
      'SensorDetectionContent',
      'camera_recovery_started',
      title: '카메라 복구 중',
      detail: '오류 $_captureErrorStreak회',
      tone: SensorDebugStatusTone.progress,
      sticky: true,
      details: <String, Object?>{'streak': _captureErrorStreak},
    );
    context.read<SensorDetectionState>().setRuntimeAvailability(
          cameraReady: false,
          detectorReady: _detector.isReady,
          source: 'camera_recovery',
        );
    final old = _cameraController;
    _cameraController = null;
    if (old != null) {
      try {
        await old.dispose().timeout(const Duration(seconds: 3));
      } catch (error) {
        SensorDebugTrace.record(
          'SensorDetectionContent',
          'camera_recovery_dispose_failed',
          <String, Object?>{'error': error},
        );
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 500));
    try {
      await _initializeCameraWithFallback(description);
      await _meterTo(const Offset(0.5, 0.5));
      _captureErrorStreak = 0;
      if (!mounted) return;
      context.read<SensorDetectionState>().setRuntimeAvailability(
            cameraReady: true,
            detectorReady: _detector.isReady,
            source: 'camera_recovery_complete',
          );
      SensorDebugTrace.publishStatus(
        'SensorDetectionContent',
        'camera_recovery_completed',
        title: '카메라 복구 완료',
        tone: SensorDebugStatusTone.success,
      );
    } catch (error, stackTrace) {
      SensorDebugTrace.publishStatus(
        'SensorDetectionContent',
        'camera_recovery_failed',
        title: '카메라 복구 실패',
        detail: error.toString(),
        tone: SensorDebugStatusTone.error,
        sticky: true,
        details: <String, Object?>{
          'error': error,
          'stack': stackTrace,
        },
      );
      if (mounted) {
        context.read<SensorDetectionState>().fail(
              error,
              source: 'camera_recovery',
            );
        setState(() {
          _runtimeError = error.toString();
        });
      }
    }
  }

  Future<void> _launchLiveOcr({
    required String source,
    required bool earlyEntry,
  }) async {
    if (!mounted || _routeActive) return;
    final detectionState = context.read<SensorDetectionState>();
    final started = earlyEntry
        ? detectionState.beginEntryOcr(source: source)
        : detectionState.beginOcr(source: source);
    if (!started) return;
    _entryGate.reset();
    SensorDebugTrace.publishStatus(
      'SensorOCR',
      'handoff_started',
      title: 'Live OCR 전환 준비',
      tone: SensorDebugStatusTone.progress,
      sticky: true,
      details: <String, Object?>{
        'source': source,
        'earlyEntry': earlyEntry,
      },
    );

    _routeActive = true;
    _loopGeneration++;
    final sourceRect = _resolvePreviewRect();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final routeController =
        LiveOcrSourceRectRouteController<LiveOcrSessionResult>(
      entrySourceRect: sourceRect,
      reduceMotion: reduceMotion,
    );
    final sessionId = _uuid.v4();
    LiveOcrSessionResult? result;

    SensorDebugTrace.publishStatus(
      'SensorOCR',
      'launch_requested',
      title: '센서 카메라 해제 중',
      detail: sessionId,
      tone: SensorDebugStatusTone.progress,
      sticky: true,
      details: <String, Object?>{
        'sessionId': sessionId,
        'sourceLeft': sourceRect.left.toStringAsFixed(1),
        'sourceTop': sourceRect.top.toStringAsFixed(1),
        'sourceWidth': sourceRect.width.toStringAsFixed(1),
        'sourceHeight': sourceRect.height.toStringAsFixed(1),
        'triggerSource': source,
        'earlyEntry': earlyEntry,
      },
    );

    await _disposeRuntimeResources(
      source: 'ocr_launch',
      closeDetector: true,
    );

    if (!mounted) {
      routeController.dispose();
      return;
    }

    SensorDebugTrace.publishStatus(
      'SensorOCR',
      'route_starting',
      title: 'Live OCR 시작',
      detail: sessionId,
      tone: SensorDebugStatusTone.progress,
      sticky: true,
    );

    try {
      final route = routeController.buildRoute(
        builder: (_) => LiveOcrPage(
          sessionId: sessionId,
          onExitPreparing: (_) async {
            if (!mounted) return;
            routeController.setExitTargetRect(
              _resolvePreviewRect(fallback: sourceRect),
            );
          },
        ),
      );
      final navigator = Navigator.of(context);
      result = await navigator.push<LiveOcrSessionResult>(route);
      await route.completed;
      final routePlate = result?.plate?.trim();
      SensorDebugTrace.publishStatus(
        'SensorOCR',
        'route_closed',
        title: 'Live OCR 종료',
        detail: routePlate == null || routePlate.isEmpty
            ? '결과 없음'
            : routePlate,
        tone: SensorDebugStatusTone.info,
        details: <String, Object?>{
          'sessionId': sessionId,
          'hasResult': result != null,
          'plate': result?.plate,
          'exitType': result?.exitType.name,
          'attemptCount': result?.attemptCount,
        },
      );
    } catch (error, stackTrace) {
      SensorDebugTrace.publishStatus(
        'SensorOCR',
        'route_failed',
        title: 'Live OCR 실행 실패',
        detail: error.toString(),
        tone: SensorDebugStatusTone.error,
        sticky: true,
        details: <String, Object?>{
          'sessionId': sessionId,
          'error': error,
          'stack': stackTrace,
        },
      );
    } finally {
      routeController.dispose();
    }

    if (!mounted) return;

    final plate = result?.plate?.trim();
    final recognizedPlate =
        plate == null || plate.isEmpty ? null : plate;
    detectionState.completeOcr(
      plate: recognizedPlate,
      exitType: result?.exitType.name ?? 'route_without_result',
      source: 'live_ocr',
    );

    if (recognizedPlate != null) {
      final acceptance = detectionState.evaluatePlateAcceptance(
        recognizedPlate,
        source: 'live_ocr',
      );
      if (acceptance.accepted) {
        await HapticFeedback.mediumImpact();
        SensorDebugTrace.publishStatus(
          'SensorOCR',
          'plate_recognized',
          title: '번호판 인식 완료',
          detail: acceptance.normalizedPlate,
          tone: SensorDebugStatusTone.success,
          details: <String, Object?>{
            'plate': acceptance.normalizedPlate,
            'sessionId': sessionId,
            'exitType': result?.exitType.name,
            'duplicateSuppressed': false,
          },
        );
        SensorPlateSuccessSnackbar.show(
          context,
          plate: acceptance.normalizedPlate,
        );
      } else {
        final elapsedSeconds =
            (acceptance.elapsedMilliseconds ?? 0) / 1000.0;
        final windowSeconds =
            SensorDetectionState.duplicatePlateWindow.inMilliseconds / 1000.0;
        SensorDebugTrace.publishStatus(
          'SensorOCR',
          'plate_duplicate_suppressed_status',
          title: '중복 번호판 억제',
          detail:
              '${acceptance.normalizedPlate} · ${elapsedSeconds.toStringAsFixed(1)} / ${windowSeconds.toStringAsFixed(0)}초',
          tone: SensorDebugStatusTone.warning,
          details: <String, Object?>{
            'plate': acceptance.normalizedPlate,
            'sessionId': sessionId,
            'elapsedMs': acceptance.elapsedMilliseconds,
            'windowMs': SensorDetectionState.duplicatePlateWindow.inMilliseconds,
            'duplicateSuppressed': true,
          },
        );
      }
    } else {
      SensorDebugTrace.publishStatus(
        'SensorOCR',
        'plate_not_recognized',
        title: '번호판 결과 없음',
        tone: SensorDebugStatusTone.warning,
      );
    }

    _routeActive = false;
    if (!reduceMotion && !_scanController.isAnimating) {
      _scanController.repeat();
    }
    await _initializeRuntime(source: 'ocr_return');
  }

  Rect _resolvePreviewRect({Rect? fallback}) {
    final previewBox = mounted ? context.findRenderObject() : null;
    final overlay = Overlay.maybeOf(context);
    final overlayBox = overlay?.context.findRenderObject();
    if (previewBox is RenderBox &&
        overlayBox is RenderBox &&
        previewBox.hasSize &&
        previewBox.size.width > 0 &&
        previewBox.size.height > 0) {
      final origin = previewBox.localToGlobal(
        Offset.zero,
        ancestor: overlayBox,
      );
      return origin & previewBox.size;
    }
    if (fallback != null && !fallback.isEmpty && fallback.isFinite) {
      return fallback;
    }
    final cached = _lastPreviewViewportSize;
    final size = cached != null && cached.width > 0 && cached.height > 0
        ? cached
        : overlayBox is RenderBox
            ? overlayBox.size
            : MediaQuery.sizeOf(context);
    return Rect.fromLTWH(
      size.width * 0.18,
      size.height * 0.18,
      size.width * 0.64,
      size.height * 0.64,
    );
  }

  Future<void> _disposeRuntimeResources({
    required String source,
    required bool closeDetector,
  }) async {
    _entryGate.reset();
    final controller = _cameraController;
    _cameraController = null;
    if (mounted) {
      context.read<SensorDetectionState>().setRuntimeAvailability(
            cameraReady: false,
            detectorReady: closeDetector ? false : _detector.isReady,
            source: source,
          );
      setState(() {});
    }
    try {
      if (_torch && controller != null && controller.value.isInitialized) {
        await controller.setFlashMode(FlashMode.off);
      }
    } catch (_) {}
    _torch = false;
    try {
      await controller?.dispose();
    } catch (error) {
      SensorDebugTrace.record(
        'SensorDetectionContent',
        'camera_dispose_failed',
        <String, Object?>{
          'source': source,
          'error': error,
        },
      );
    }
    if (closeDetector) {
      await _detector.close();
    }
    SensorDebugTrace.record(
      'SensorDetectionContent',
      'runtime_disposed',
      <String, Object?>{
        'source': source,
        'detectorClosed': closeDetector,
      },
    );
  }

  Future<void> _toggleTorch() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    await HapticFeedback.selectionClick();
    try {
      final next = !_torch;
      await controller.setFlashMode(next ? FlashMode.torch : FlashMode.off);
      if (!mounted) return;
      setState(() {
        _torch = next;
      });
      SensorDebugTrace.record(
        'SensorDetectionContent',
        'torch_changed',
        <String, Object?>{'enabled': next},
      );
    } catch (error) {
      SensorDebugTrace.record(
        'SensorDetectionContent',
        'torch_failed',
        <String, Object?>{'error': error},
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final detectionState = context.watch<SensorDetectionState>();
    final triggerState = context.watch<SensorTriggerPointState>();
    final controller = _cameraController;
    final initialized =
        controller != null && controller.value.isInitialized;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final baselineReady = _occupancyBaseline != null &&
        triggerState.savedCameraZone != null &&
        _occupancyBaseline!.zone.roughlyEquals(
          triggerState.savedCameraZone!,
        );

    Widget preview;
    if (initialized) {
      preview = LayoutBuilder(
        builder: (context, constraints) {
          final viewportSize = Size(
            constraints.maxWidth,
            constraints.maxHeight,
          );
          _lastPreviewViewportSize = viewportSize;
          final mapper = _coordinateMapper(viewportSize);
          final previewSourceSize = mapper?.previewSourceSize ?? viewportSize;
          final displayCameraZone = triggerState.displayCameraZone;
          final calibrationFrameBytes = triggerState.isEditing &&
                  _triggerCalibrationFrameSize != null
              ? _triggerCalibrationFrameBytes
              : null;
          final mappedCameraCorners = mapper == null ||
                  !mapper.isCameraImageReady ||
                  displayCameraZone == null
              ? const <Offset>[]
              : mapper.cameraImageNormalizedPolygonToViewport(
                  displayCameraZone.points,
                );
          final viewportTriggerCorners = triggerState.isEditing
              ? (_triggerEditViewportCorners.isNotEmpty
                  ? _triggerEditViewportCorners
                  : mappedCameraCorners)
              : mappedCameraCorners;
          final editEnabled = triggerState.isReady &&
              !_triggerGeometryPreparing &&
              !detectionState.ocrActive &&
              detectionState.phase != SensorDetectionPhase.detected &&
              detectionState.phase != SensorDetectionPhase.ocrActive;
          final sensorReady = triggerState.isConfigured &&
              baselineReady &&
              detectionState.runtimeReady &&
              _runtimeError == null;
          final scanEnabled = sensorReady &&
              !triggerState.isEditing &&
              detectionState.phase != SensorDetectionPhase.error;
          _syncScanState(
            enabled: scanEnabled,
            reduceMotion: reduceMotion,
          );

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: mapper == null || triggerState.isEditing
                    ? null
                    : (details) {
                        final previewPoint = mapper.viewportToPreviewNormalized(
                          details.localPosition,
                        );
                        unawaited(_meterTo(previewPoint));
                      },
                onTapUp: mapper == null || !triggerState.isEditing
                    ? null
                    : (details) {
                        _handleTriggerTap(details.localPosition, mapper);
                      },
                onPanStart: triggerState.isEditing && mapper != null
                    ? (details) {
                        if (!triggerState.placementComplete) return;
                        _beginTriggerMove(
                          details.localPosition,
                          viewportTriggerCorners,
                        );
                      }
                    : null,
                onPanUpdate: triggerState.isEditing && mapper != null
                    ? (details) {
                        _updateTriggerMove(details.delta, mapper);
                      }
                    : null,
                onPanEnd: triggerState.isEditing
                    ? (_) => _endTriggerMove()
                    : null,
                onPanCancel: triggerState.isEditing
                    ? _endTriggerMove
                    : null,
                child: ClipRect(
                  child: calibrationFrameBytes != null
                      ? SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: (_triggerCalibrationFrameSize ??
                                      previewSourceSize)
                                  .width,
                              height: (_triggerCalibrationFrameSize ??
                                      previewSourceSize)
                                  .height,
                              child: Image.memory(
                                calibrationFrameBytes,
                                fit: BoxFit.cover,
                                alignment: Alignment.center,
                                filterQuality: FilterQuality.high,
                                gaplessPlayback: true,
                              ),
                            ),
                          ),
                        )
                      : SizedBox.expand(
                          child: FittedBox(
                            fit: BoxFit.cover,
                            alignment: Alignment.center,
                            clipBehavior: Clip.hardEdge,
                            child: SizedBox(
                              width: previewSourceSize.width,
                              height: previewSourceSize.height,
                              child: CameraPreview(controller),
                            ),
                          ),
                        ),
                ),
              ),
              IgnorePointer(
                child: AnimatedOpacity(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  opacity: triggerState.isEditing || !sensorReady ? 0.0 : 1.0,
                  child: _SensorDetectionScanOverlay(
                    animation: _scanController,
                    detected: detectionState.objectDetected,
                    reduceMotion: reduceMotion,
                  ),
                ),
              ),
              if (!triggerState.isEditing &&
                  mapper != null &&
                  mapper.isCameraImageReady)
                ValueListenableBuilder<bool>(
                  valueListenable: DevAuth.devModeEnabled,
                  builder: (context, enabled, child) {
                    if (!enabled) return const SizedBox.shrink();
                    return IgnorePointer(
                      child: SensorDetectionDebugOverlay(
                        mapper: mapper,
                        cameraBoundingBoxes: _lastDetectionBoxes,
                        matchedIndexes: _lastMatchedBoxIndexes,
                        bottomCenterMatchedIndexes:
                            _lastBottomCenterMatchedBoxIndexes,
                        entryActive: _lastEntryActive,
                        entryTriggered: _lastEntryTriggered,
                        entryGeometry: triggerState.savedCameraZone == null
                            ? null
                            : SensorEntryBandGeometry.fromZone(
                                triggerState.savedCameraZone!,
                              ),
                        triggerZone: triggerState.savedCameraZone,
                        recognitionZone:
                            triggerState.savedCameraZone?.recognitionZone,
                        reduceMotion: reduceMotion,
                      ),
                    );
                  },
                ),
              SensorTriggerPointOverlay(
                viewportCorners: viewportTriggerCorners,
                isEditing: triggerState.isEditing,
                isSaving: triggerState.isSaving,
                isPreparingGeometry: _triggerGeometryPreparing,
                isDragging: _triggerDragging,
                reduceMotion: reduceMotion,
                baselineReady: baselineReady,
                baselineSaving: _baselineSaving,
                feedbackCornerIndex: _triggerCornerFeedbackIndex,
                feedbackCornerSerial: _triggerCornerFeedbackSerial,
                rejectedCornerIndex: _triggerCornerRejectedIndex,
                rejectedCornerSerial: _triggerCornerRejectedSerial,
                entryEdgeType: triggerState.displayCameraZone?.entryEdgeType,
                onEdit: editEnabled
                    ? () => unawaited(_beginTriggerEdit(viewportSize))
                    : null,
                onSave: triggerState.draftCameraZone != null
                    ? () => unawaited(_saveTrigger())
                    : null,
                onCancel: () => unawaited(_cancelTriggerEdit()),
                onSaveBaseline: triggerState.savedCameraZone != null &&
                        !baselineReady
                    ? () => unawaited(_saveEmptyBaseline())
                    : null,
                onResizeStart: _beginTriggerResize,
                onResizeUpdate: mapper == null
                    ? null
                    : (handle, delta) => _updateTriggerResize(
                          handle,
                          delta,
                          mapper,
                        ),
                onResizeEnd: _endTriggerResize,
              ),
              Positioned(
                right: 12,
                bottom: 12,
                child: AnimatedScale(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  scale: _torch ? 1.06 : 1,
                  child: IconButton.filledTonal(
                    onPressed: () => unawaited(_toggleTorch()),
                    icon: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: Icon(
                        _torch ? Icons.flash_on : Icons.flash_off,
                        key: ValueKey<bool>(_torch),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );
    } else if (_runtimeError != null) {
      preview = Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: AnimatedSwitcher(
          duration: reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 240),
          child: Column(
            key: const ValueKey<String>('sensor-runtime-error'),
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.videocam_off_rounded,
                size: 42,
                color: tokens.textSecondary,
              ),
              const SizedBox(height: 12),
              Text(
                '카메라 오류',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
                    ),
              ),
            ],
          ),
        ),
      );
    } else {
      preview = Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(tokens.accent),
        ),
      );
    }

    return ColoredBox(
      color: Colors.black,
      child: SizedBox.expand(
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            preview,
            if (initialized)
              Positioned(
                top: 12,
                left: 12,
                child: IgnorePointer(
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    switchInCurve: Curves.linear,
                    switchOutCurve: Curves.linear,
                    transitionBuilder: (child, animation) {
                      final fade = CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                        reverseCurve: Curves.easeInCubic,
                      );
                      final scale = Tween<double>(
                        begin: 0.94,
                        end: 1.0,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutBack,
                          reverseCurve: Curves.easeInCubic,
                        ),
                      );
                      return FadeTransition(
                        opacity: fade,
                        child: ScaleTransition(
                          scale: scale,
                          child: child,
                        ),
                      );
                    },
                    child: triggerState.isEditing
                        ? const SizedBox.shrink(
                            key: ValueKey<String>('sensor-status-hidden'),
                          )
                        : _SensorDetectionStatusBadge(
                            key: const ValueKey<String>('sensor-status-visible'),
                            detected: detectionState.objectDetected,
                            phase: detectionState.phase,
                            triggerConfigured: triggerState.isConfigured,
                            baselineReady: baselineReady,
                            cameraReady: detectionState.cameraReady,
                            detectorReady: detectionState.detectorReady,
                            reduceMotion: reduceMotion,
                          ),
                  ),
                ),
              ),
            const SensorDebugStatusBanner(),
          ],
        ),
      ),
    );
  }
}

class _SensorDetectionStatusBadge extends StatelessWidget {
  const _SensorDetectionStatusBadge({
    super.key,
    required this.detected,
    required this.phase,
    required this.triggerConfigured,
    required this.baselineReady,
    required this.cameraReady,
    required this.detectorReady,
    required this.reduceMotion,
  });

  final bool detected;
  final SensorDetectionPhase phase;
  final bool triggerConfigured;
  final bool baselineReady;
  final bool cameraReady;
  final bool detectorReady;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    late final String label;
    late final IconData icon;
    late final Color foreground;
    late final Color background;

    if (phase == SensorDetectionPhase.error) {
      label = '오류';
      icon = Icons.error_outline_rounded;
      foreground = tokens.onDangerContainer;
      background = tokens.dangerContainer;
    } else if (!cameraReady || !detectorReady) {
      label = '준비 중';
      icon = Icons.sync_rounded;
      foreground = tokens.onInfoContainer;
      background = tokens.infoContainer;
    } else if (!triggerConfigured) {
      label = '영역 설정';
      icon = Icons.polyline_rounded;
      foreground = tokens.onWarningContainer;
      background = tokens.warningContainer;
    } else if (!baselineReady) {
      label = '기준 저장';
      icon = Icons.add_photo_alternate_outlined;
      foreground = tokens.onWarningContainer;
      background = tokens.warningContainer;
    } else if (phase == SensorDetectionPhase.ocrActive) {
      label = '번호판 인식';
      icon = Icons.document_scanner_rounded;
      foreground = tokens.onSuccessContainer;
      background = tokens.successContainer;
    } else if (phase == SensorDetectionPhase.waitForClear) {
      label = '이탈 대기';
      icon = Icons.hourglass_bottom_rounded;
      foreground = tokens.onInfoContainer;
      background = tokens.infoContainer;
    } else if (detected || phase == SensorDetectionPhase.detected) {
      label = '차량 감지';
      icon = Icons.directions_car_filled_rounded;
      foreground = tokens.onSuccessContainer;
      background = tokens.successContainer;
    } else {
      label = '감지 중';
      icon = Icons.sensors_rounded;
      foreground = tokens.onAccentContainer;
      background = tokens.accentContainer;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: background.withOpacity(0.94),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: foreground.withOpacity(0.54)),
      ),
      child: AnimatedSwitcher(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 200),
        switchInCurve: Curves.linear,
        switchOutCurve: Curves.linear,
        transitionBuilder: (child, animation) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          final scale = Tween<double>(
            begin: 0.84,
            end: 1.0,
          ).animate(
            CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutBack,
              reverseCurve: Curves.easeInCubic,
            ),
          );
          return FadeTransition(
            opacity: fade,
            child: ScaleTransition(
              scale: scale,
              child: child,
            ),
          );
        },
        child: Row(
          key: ValueKey<String>(label),
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 18, color: foreground),
            const SizedBox(width: 7),
            Text(
              label,
              style: textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SensorDetectionScanOverlay extends StatelessWidget {
  const _SensorDetectionScanOverlay({
    required this.animation,
    required this.detected,
    required this.reduceMotion,
  });

  final Animation<double> animation;
  final bool detected;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final color = detected ? tokens.success : tokens.accent;
    if (reduceMotion) {
      return CustomPaint(
        painter: _SensorScanPainter(
          progress: 0.5,
          color: color,
          detected: detected,
        ),
      );
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        return CustomPaint(
          painter: _SensorScanPainter(
            progress: animation.value,
            color: color,
            detected: detected,
          ),
        );
      },
    );
  }
}

class _SensorScanPainter extends CustomPainter {
  const _SensorScanPainter({
    required this.progress,
    required this.color,
    required this.detected,
  });

  final double progress;
  final Color color;
  final bool detected;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final inset = size.shortestSide * 0.08;
    final rect = Rect.fromLTRB(
      inset,
      inset,
      size.width - inset,
      size.height - inset,
    );
    final corner = size.shortestSide * 0.055;
    final stroke = Paint()
      ..color = color.withOpacity(detected ? 0.92 : 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = detected ? 3 : 2.2
      ..strokeCap = StrokeCap.round;

    final segments = <List<Offset>>[
      <Offset>[
        Offset(rect.left, rect.top + corner),
        Offset(rect.left, rect.top),
        Offset(rect.left + corner, rect.top),
      ],
      <Offset>[
        Offset(rect.right - corner, rect.top),
        Offset(rect.right, rect.top),
        Offset(rect.right, rect.top + corner),
      ],
      <Offset>[
        Offset(rect.left, rect.bottom - corner),
        Offset(rect.left, rect.bottom),
        Offset(rect.left + corner, rect.bottom),
      ],
      <Offset>[
        Offset(rect.right - corner, rect.bottom),
        Offset(rect.right, rect.bottom),
        Offset(rect.right, rect.bottom - corner),
      ],
    ];

    for (final points in segments) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, stroke);
    }

    if (!detected) {
      final y = rect.top + (rect.height * progress);
      final linePaint = Paint()
        ..shader = LinearGradient(
          colors: <Color>[
            color.withOpacity(0),
            color.withOpacity(0.82),
            color.withOpacity(0),
          ],
        ).createShader(Rect.fromLTWH(rect.left, y - 1, rect.width, 2))
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(rect.left, y),
        Offset(rect.right, y),
        linePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SensorScanPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.detected != detected;
  }
}
