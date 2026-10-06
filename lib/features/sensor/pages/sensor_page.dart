import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../dev/application/area_state.dart';
import '../../selector/application/dev_auth.dart';
import '../applications/sensor_debug_trace.dart';
import '../applications/sensor_detection_state.dart';
import '../applications/sensor_recognition_gate.dart';
import '../applications/sensor_side_dock_state.dart';
import '../applications/sensor_trigger_point_state.dart';
import '../applications/sensor_work_session_state.dart';
import '../services/sensor_object_detector_service.dart';
import 'widgets/sensor_content_navigator.dart';
import 'widgets/sensor_mode_rail.dart';

class SensorPage extends StatefulWidget {
  const SensorPage({super.key});

  @override
  State<SensorPage> createState() => _SensorPageState();
}

class _SensorPageState extends State<SensorPage> {
  final GlobalKey<NavigatorState> _contentNavigatorKey =
      GlobalKey<NavigatorState>();
  String? _areaCache;

  @override
  void initState() {
    super.initState();
    SensorDebugTrace.clear();
    SensorDebugTrace.record('SensorPage', 'initialized');
    unawaited(DevAuth.isDevModeEnabled());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_startWorkSession());
    });
  }

  Future<void> _startWorkSession() async {
    if (!mounted) return;
    SensorDebugTrace.record(
      'SensorPage',
      'work_start_requested',
      <String, Object?>{'source': 'sensor_page'},
    );
    await context
        .read<SensorWorkSessionState>()
        .startWork(source: 'sensor_page');
  }

  @override
  void dispose() {
    SensorDebugTrace.record('SensorPage', 'disposed');
    super.dispose();
  }

  Future<void> _openSideDock() async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    SensorDebugTrace.record(
      'SensorSideDock',
      'open_requested',
      <String, Object?>{'source': 'edge_tap'},
    );
    await context.read<SensorSideDockState>().open(source: 'edge_tap');
  }

  Future<void> _closeSideDock(String source) async {
    if (!mounted) return;
    SensorDebugTrace.record(
      'SensorSideDock',
      'close_requested',
      <String, Object?>{'source': source},
    );
    await context.read<SensorSideDockState>().close(source: source);
  }

  Future<void> _toggleSideDockFromSensorButton() async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    final state = context.read<SensorSideDockState>();
    SensorDebugTrace.record(
      'SensorSideDock',
      'sensor_button_toggle_requested',
      <String, Object?>{
        'from': state.isOpen,
        'to': !state.isOpen,
        'source': 'sensor_button',
      },
    );
    await state.toggle(source: 'sensor_button');
  }

  Future<void> _showDeveloperStatus() async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    final dockState = context.read<SensorSideDockState>();
    final workState = context.read<SensorWorkSessionState>();
    final detectionState = context.read<SensorDetectionState>();
    final triggerState = context.read<SensorTriggerPointState>();
    final media = MediaQuery.maybeOf(context);
    final size = media?.size ?? Size.zero;
    final area = context.read<AreaState>().currentArea.trim();
    final debugStatus = SensorDebugTrace.currentStatus.value;
    SensorDebugTrace.record(
      'SensorPage',
      'developer_status_requested',
      <String, Object?>{
        'area': area,
        'dockReady': dockState.isReady,
        'sideDockOpen': dockState.isOpen,
        'workSessionReady': workState.isReady,
        'workSessionActive': workState.isActive,
        'detectionPhase': detectionState.phase.name,
        'objectDetected': detectionState.objectDetected,
        'cameraReady': detectionState.cameraReady,
        'detectorReady': detectionState.detectorReady,
        'ocrActive': detectionState.ocrActive,
        'detectedStreak': detectionState.detectedStreak,
        'detectionWindowCount': detectionState.detectionWindowCount,
        'detectionPositiveCount': detectionState.detectionPositiveCount,
        'detectionWindow': detectionState.recentDetectionSamples
            .map((value) => value ? 1 : 0)
            .join(','),
        'detectionWindowSize': SensorDetectionState.detectionWindowSize,
        'detectionRequiredPositives':
            SensorDetectionState.detectionRequiredPositives,
        'clearStreak': detectionState.clearStreak,
        'clearElapsedMs': detectionState.clearElapsedMilliseconds,
        'clearMinimumMs':
            SensorDetectionState.minimumClearDuration.inMilliseconds,
        'clearTimeSatisfied': detectionState.clearTimeSatisfied,
        'sampleCount': detectionState.sampleCount,
        'lastRecognizedPlate': detectionState.lastRecognizedPlate,
        'lastAcceptedPlate': detectionState.lastAcceptedPlate,
        'lastAcceptedPlateAt': detectionState.lastAcceptedPlateAt?.toIso8601String(),
        'duplicateWindowMs':
            SensorDetectionState.duplicatePlateWindow.inMilliseconds,
        'lastDuplicatePlate': detectionState.lastDuplicatePlate,
        'lastDuplicateElapsedMs':
            detectionState.lastDuplicateElapsedMilliseconds,
        'lastDetectionError': detectionState.lastError,
        'triggerReady': triggerState.isReady,
        'triggerConfigured': triggerState.isConfigured,
        'triggerEditing': triggerState.isEditing,
        'triggerSaving': triggerState.isSaving,
        'triggerCenterX':
            triggerState.savedCameraZone?.center.dx.toStringAsFixed(4),
        'triggerCenterY':
            triggerState.savedCameraZone?.center.dy.toStringAsFixed(4),
        'triggerP1X': triggerState.savedCameraZone?.point1.dx.toStringAsFixed(4),
        'triggerP1Y': triggerState.savedCameraZone?.point1.dy.toStringAsFixed(4),
        'triggerP2X': triggerState.savedCameraZone?.point2.dx.toStringAsFixed(4),
        'triggerP2Y': triggerState.savedCameraZone?.point2.dy.toStringAsFixed(4),
        'triggerP3X': triggerState.savedCameraZone?.point3.dx.toStringAsFixed(4),
        'triggerP3Y': triggerState.savedCameraZone?.point3.dy.toStringAsFixed(4),
        'triggerP4X': triggerState.savedCameraZone?.point4.dx.toStringAsFixed(4),
        'triggerP4Y': triggerState.savedCameraZone?.point4.dy.toStringAsFixed(4),
        'triggerPolygonArea':
            triggerState.savedCameraZone?.area.toStringAsFixed(4),
        'triggerPolygonMinEdge':
            triggerState.savedCameraZone?.minEdge.toStringAsFixed(4),
        'triggerPolygonValid': triggerState.savedCameraZone?.isValid,
        'triggerPolygonConvex': triggerState.savedCameraZone?.isConvex,
        'triggerPolygonSelfIntersecting':
            triggerState.savedCameraZone?.selfIntersecting,
        'triggerPlacementCount': triggerState.placementCount,
        'legacyZoneAvailable': triggerState.legacyCameraZone != null,
        'legacyTriggerAvailable': triggerState.legacyCameraPoint != null,
        'baselineReady': detectionState.baselineReady,
        'baselineSavedAt': detectionState.baselineSavedAt,
        'sensorReady': triggerState.isConfigured &&
            detectionState.baselineReady &&
            detectionState.runtimeReady,
        'recognitionZone':
            triggerState.savedCameraZone?.recognitionZone.fingerprint,
        'recognitionWeakStructureThreshold':
            SensorRecognitionGate.weakStructureThreshold,
        'recognitionWeakChangedCellThreshold':
            SensorRecognitionGate.weakChangedCellThreshold,
        'recognitionStrongMlCoverageThreshold':
            SensorRecognitionGate.strongMlCoverageThreshold,
        'recognitionStrongMlBoundingBoxThreshold':
            SensorRecognitionGate.strongMlBoundingBoxThreshold,
        'mlClosePolygonCoverage':
            SensorObjectDetectionResult.closePolygonCoverage,
        'mlCloseBoundingBoxAreaRatio':
            SensorObjectDetectionResult.closeBoundingBoxAreaRatio,
        'mlLargePolygonCoverage':
            SensorObjectDetectionResult.largePolygonCoverage,
        'mlLargeBoundingBoxAreaRatio':
            SensorObjectDetectionResult.largeBoundingBoxAreaRatio,
        'mlBottomCenterBoundingBoxAreaRatio':
            SensorObjectDetectionResult.bottomCenterBoundingBoxAreaRatio,
        'occupancyCandidate':
            detectionState.lastOccupancyEvidence?.occupiedCandidate,
        'clearCandidate':
            detectionState.lastOccupancyEvidence?.clearCandidate,
        'structureChangeScore': detectionState
            .lastOccupancyEvidence?.structureChangeScore
            .toStringAsFixed(4),
        'changedCellRatio': detectionState
            .lastOccupancyEvidence?.changedCellRatio
            .toStringAsFixed(4),
        'baselineSimilarity': detectionState
            .lastOccupancyEvidence?.baselineSimilarity
            .toStringAsFixed(4),
        'mlMatched': detectionState.lastOccupancyEvidence?.mlMatched,
        'mlBottomCenterMatched':
            detectionState.lastOccupancyEvidence?.mlBottomCenterMatched,
        'mlObjectCount':
            detectionState.lastOccupancyEvidence?.mlObjectCount,
        'mlMatchedCount':
            detectionState.lastOccupancyEvidence?.mlMatchedCount,
        'mlPolygonCoverage': detectionState
            .lastOccupancyEvidence?.mlPolygonCoverage
            .toStringAsFixed(4),
        'mlBBoxAreaRatio': detectionState
            .lastOccupancyEvidence?.mlBoundingBoxAreaRatio
            .toStringAsFixed(4),
        'occupancyReason':
            detectionState.lastOccupancyEvidence?.reason,
        'coordinateFit': detectionState.coordinateFit,
        'cameraGeometryReady': detectionState.cameraGeometryReady,
        'cameraGeometrySource': detectionState.cameraGeometrySource,
        'previewAspect': detectionState.previewAspect?.toStringAsFixed(4),
        'cameraImageAspect':
            detectionState.cameraImageAspect?.toStringAsFixed(4),
        'coordinateAspectDelta':
            detectionState.coordinateAspectDelta?.toStringAsFixed(4),
        'previewWidth':
            detectionState.previewViewportSize?.width.round(),
        'previewHeight':
            detectionState.previewViewportSize?.height.round(),
        'previewSourceWidth':
            detectionState.cameraPreviewSourceSize?.width.round(),
        'previewSourceHeight':
            detectionState.cameraPreviewSourceSize?.height.round(),
        'cameraImageWidth':
            detectionState.cameraImageSize?.width.round(),
        'cameraImageHeight':
            detectionState.cameraImageSize?.height.round(),
        'sensorOrientation': detectionState.sensorOrientation,
        'lensDirection': detectionState.lensDirection,
        'triggerError': triggerState.lastError,
        'triggerEditInitialSource': triggerState.lastEditInitialSource,
        'debugStatusSequence': debugStatus?.sequence,
        'debugStatusSource': debugStatus?.source,
        'debugStatusEvent': debugStatus?.event,
        'debugStatusTitle': debugStatus?.title,
        'debugStatusDetail': debugStatus?.detail,
        'debugStatusTone': debugStatus?.tone.name,
        'debugStatusSticky': debugStatus?.sticky,
        'debugLineCount': SensorDebugTrace.lines.length,
        'contentNavigatorCanPop':
            _contentNavigatorKey.currentState?.canPop() ?? false,
        'viewportWidth': size.width.round(),
        'viewportHeight': size.height.round(),
        'reduceMotion': media?.disableAnimations ?? false,
      },
    );
    await SensorDebugTrace.showStatusDialog(
      context,
      title: '센서 개발자 상태',
    );
  }

  Future<void> _handleSystemBack({required bool dockOpen}) async {
    if (!mounted) return;
    final navigator = _contentNavigatorKey.currentState;
    if (navigator != null && navigator.canPop()) {
      SensorDebugTrace.record(
        'SensorContentNavigator',
        'system_back_requested',
        <String, Object?>{
          'canPop': true,
        },
      );
      await navigator.maybePop();
      return;
    }
    if (dockOpen) {
      await _closeSideDock('system_back');
    }
  }

  Widget _buildContent(BuildContext context) {
    return SensorContentNavigator(
      navigatorKey: _contentNavigatorKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final area = context.select<AreaState, String>(
            (state) => state.currentArea,
          );
          final dockState = context.watch<SensorSideDockState>();
          final dockReady = dockState.isReady;
          final dockOpen = dockReady && dockState.isOpen;

          if (_areaCache != area) {
            final previous = _areaCache;
            _areaCache = area;
            SensorDebugTrace.record(
              'SensorPage',
              'area_changed',
              <String, Object?>{
                'from': previous ?? '',
                'to': area,
              },
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted || _areaCache != area) return;
              context.read<SensorDetectionState>().resetSampling(
                    source: 'area_trigger_reload',
                  );
              unawaited(
                context
                    .read<SensorTriggerPointState>()
                    .loadForArea(area),
              );
            });
          }

          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) {
              if (didPop) return;
              unawaited(
                _handleSystemBack(
                  dockOpen: dockOpen,
                ),
              );
            },
            child: Scaffold(
              backgroundColor: Colors.black,
              body: SafeArea(
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          if (dockReady)
                            _SensorSideDockShell(
                              open: dockOpen,
                              rail: const SensorModeRail(),
                            ),
                          Expanded(child: _buildContent(context)),
                        ],
                      ),
                    ),
                    if (dockReady && !dockOpen)
                      Positioned(
                        left: 0,
                        top: 0,
                        bottom: 0,
                        width: 24,
                        child: GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onTap: () => unawaited(_openSideDock()),
                        ),
                      ),
                    if (dockReady)
                      Positioned(
                        left: 0,
                        bottom: SensorModeRail.sensorToggleBottomInset,
                        width: SensorModeRail.width,
                        height: SensorModeRail.sensorToggleHeight,
                        child: _SensorDockToggleButton(
                          open: dockOpen,
                          onPressed: () => unawaited(
                            _toggleSideDockFromSensorButton(),
                          ),
                        ),
                      ),
                    Align(
                      alignment: Alignment.topRight,
                      child: ValueListenableBuilder<bool>(
                        valueListenable: DevAuth.devModeEnabled,
                        builder: (context, enabled, child) {
                          return AnimatedSwitcher(
                            duration: MediaQuery.maybeOf(context)
                                        ?.disableAnimations ==
                                    true
                                ? Duration.zero
                                : const Duration(milliseconds: 220),
                            switchInCurve: Curves.easeOutCubic,
                            switchOutCurve: Curves.easeInCubic,
                            transitionBuilder: (child, animation) {
                              return FadeTransition(
                                opacity: animation,
                                child: ScaleTransition(
                                  scale: Tween<double>(begin: 0.9, end: 1)
                                      .animate(animation),
                                  child: child,
                                ),
                              );
                            },
                            child: enabled
                                ? Padding(
                                    key: const ValueKey<String>(
                                      'sensor-debug-visible',
                                    ),
                                    padding: const EdgeInsets.all(12),
                                    child: IconButton.filledTonal(
                                      onPressed: () =>
                                          unawaited(_showDeveloperStatus()),
                                      icon: const Icon(
                                        Icons.bug_report_outlined,
                                      ),
                                    ),
                                  )
                                : const SizedBox.shrink(
                                    key: ValueKey<String>(
                                      'sensor-debug-hidden',
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SensorDockToggleButton extends StatefulWidget {
  const _SensorDockToggleButton({
    required this.open,
    required this.onPressed,
  });

  final bool open;
  final VoidCallback onPressed;

  @override
  State<_SensorDockToggleButton> createState() =>
      _SensorDockToggleButtonState();
}

class _SensorDockToggleButtonState extends State<_SensorDockToggleButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selectionDuration =
        reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final pressDuration = reduceMotion ? Duration.zero : CommonUiMotion.press;

    return Semantics(
      button: true,
      selected: widget.open,
      label: '센서',
      child: AnimatedScale(
        duration: pressDuration,
        curve: CommonUiMotion.standard,
        scale: _pressed ? 0.96 : 1.0,
        child: AnimatedContainer(
          duration: selectionDuration,
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            color: widget.open ? tokens.surfaceSelected : tokens.surface,
            border: Border(
              right: BorderSide(
                color: widget.open ? tokens.accent : tokens.borderSubtle,
                width: widget.open ? 2.0 : 1.0,
              ),
            ),
          ),
          child: Material(
            color: tokens.transparent,
            child: InkWell(
              onHighlightChanged: (value) {
                if (!mounted) return;
                setState(() {
                  _pressed = value;
                });
              },
              onTap: widget.onPressed,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  children: <Widget>[
                    AnimatedRotation(
                      duration: selectionDuration,
                      curve: Curves.easeOutCubic,
                      turns: widget.open ? 0.0 : -0.04,
                      child: Icon(
                        Icons.sensors_rounded,
                        size: 21,
                        color: widget.open
                            ? tokens.accent
                            : tokens.iconSecondary,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: AnimatedDefaultTextStyle(
                        duration: selectionDuration,
                        curve: Curves.easeOutCubic,
                        style: (text.labelSmall ?? const TextStyle()).copyWith(
                          color: widget.open
                              ? tokens.textPrimary
                              : tokens.textSecondary,
                          fontSize: 10.5,
                          fontWeight:
                              widget.open ? FontWeight.w800 : FontWeight.w600,
                          height: 1,
                        ),
                        child: const Text(
                          '센서',
                          maxLines: 1,
                          overflow: TextOverflow.fade,
                          softWrap: false,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      duration: selectionDuration,
                      curve: Curves.easeOutCubic,
                      turns: widget.open ? 0.5 : 0.0,
                      child: Icon(
                        Icons.keyboard_arrow_right_rounded,
                        size: 18,
                        color: widget.open
                            ? tokens.accent
                            : tokens.iconSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SensorSideDockShell extends StatefulWidget {
  const _SensorSideDockShell({
    required this.open,
    required this.rail,
  });

  final bool open;
  final Widget rail;

  @override
  State<_SensorSideDockShell> createState() => _SensorSideDockShellState();
}

class _SensorSideDockShellState extends State<_SensorSideDockShell>
    with SingleTickerProviderStateMixin {
  static const double _railWidth = SensorModeRail.width;
  static const double _dividerWidth = 1;
  static const Duration _duration = Duration(milliseconds: 220);

  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.open ? 1 : 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextReduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == nextReduceMotion) return;
    _reduceMotion = nextReduceMotion;
    if (_reduceMotion) {
      _controller.value = widget.open ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(covariant _SensorSideDockShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open == widget.open) return;
    final target = widget.open ? 1.0 : 0.0;
    if (_reduceMotion) {
      _controller.value = target;
      return;
    }
    _controller.animateTo(
      target,
      duration: _duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final fullWidth = _railWidth + _dividerWidth;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        final opacity = ((value - 0.12) / 0.88).clamp(0.0, 1.0).toDouble();
        return SizedBox(
          width: fullWidth * value,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: <Widget>[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: fullWidth,
                  child: Opacity(
                    opacity: opacity,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        widget.rail,
                        VerticalDivider(
                          width: _dividerWidth,
                          thickness: _dividerWidth,
                          color: tokens.borderSubtle,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
