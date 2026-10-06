import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../applications/sensor_debug_trace.dart';
import '../../applications/sensor_polygon_geometry.dart';
import '../../applications/sensor_trigger_zone.dart';
import '../../services/sensor_camera_coordinate_mapper.dart';

class SensorDetectionDebugOverlay extends StatefulWidget {
  const SensorDetectionDebugOverlay({
    super.key,
    required this.mapper,
    required this.cameraBoundingBoxes,
    required this.matchedIndexes,
    required this.triggerZone,
    required this.recognitionZone,
    required this.reduceMotion,
  });

  final SensorCameraCoordinateMapper mapper;
  final List<Rect> cameraBoundingBoxes;
  final Set<int> matchedIndexes;
  final SensorTriggerZone? triggerZone;
  final SensorTriggerZone? recognitionZone;
  final bool reduceMotion;

  @override
  State<SensorDetectionDebugOverlay> createState() =>
      _SensorDetectionDebugOverlayState();
}

class _SensorDetectionDebugOverlayState
    extends State<SensorDetectionDebugOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _animationSyncRevision = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant SensorDetectionDebugOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.matchedIndexes.isEmpty != widget.matchedIndexes.isEmpty ||
        oldWidget.reduceMotion != widget.reduceMotion) {
      _scheduleAnimationSync();
    }
  }

  void _scheduleAnimationSync() {
    final revision = ++_animationSyncRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _animationSyncRevision) return;
      _syncAnimation();
    });
  }

  void _syncAnimation() {
    final shouldAnimate =
        !widget.reduceMotion && widget.matchedIndexes.isNotEmpty;
    if (shouldAnimate) {
      if (!_controller.isAnimating) {
        _controller.repeat(reverse: true);
        SensorDebugTrace.record(
          'SensorDetectionDebugOverlay',
          'matched_pulse_started',
          <String, Object?>{'matchedCount': widget.matchedIndexes.length},
        );
      }
      return;
    }

    final wasAnimating = _controller.isAnimating;
    _controller.stop();
    if (_controller.value != 0.0) {
      _controller.value = 0.0;
    }
    if (wasAnimating) {
      SensorDebugTrace.record(
        'SensorDetectionDebugOverlay',
        'matched_pulse_stopped',
        <String, Object?>{
          'matchedCount': widget.matchedIndexes.length,
          'reduceMotion': widget.reduceMotion,
        },
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: _SensorDetectionDebugPainter(
            mapper: widget.mapper,
            cameraBoundingBoxes: widget.cameraBoundingBoxes,
            matchedIndexes: widget.matchedIndexes,
            triggerZone: widget.triggerZone,
            recognitionZone: widget.recognitionZone,
            normalColor: tokens.info,
            matchedColor: tokens.success,
            zoneColor: tokens.accent,
            recognitionColor: tokens.info,
            pulse: widget.reduceMotion ? 0 : _controller.value,
          ),
        );
      },
    );
  }
}

class _SensorDetectionDebugPainter extends CustomPainter {
  const _SensorDetectionDebugPainter({
    required this.mapper,
    required this.cameraBoundingBoxes,
    required this.matchedIndexes,
    required this.triggerZone,
    required this.recognitionZone,
    required this.normalColor,
    required this.matchedColor,
    required this.zoneColor,
    required this.recognitionColor,
    required this.pulse,
  });

  final SensorCameraCoordinateMapper mapper;
  final List<Rect> cameraBoundingBoxes;
  final Set<int> matchedIndexes;
  final SensorTriggerZone? triggerZone;
  final SensorTriggerZone? recognitionZone;
  final Color normalColor;
  final Color matchedColor;
  final Color zoneColor;
  final Color recognitionColor;
  final double pulse;

  @override
  void paint(Canvas canvas, Size size) {
    if (!mapper.isValid || size.isEmpty) return;
    final trigger = triggerZone;
    final recognition = recognitionZone;
    final cameraPolygon = recognition?.points ?? const <Offset>[];
    final triggerViewport = trigger == null
        ? const <Offset>[]
        : mapper.cameraImageNormalizedPolygonToViewport(trigger.points);
    final recognitionViewport = recognition == null
        ? const <Offset>[]
        : mapper.cameraImageNormalizedPolygonToViewport(recognition.points);
    if (recognitionViewport.length == 4) {
      final path = _path(recognitionViewport, close: true);
      final fill = Paint()
        ..color = recognitionColor.withOpacity(0.035 + pulse * 0.025)
        ..style = PaintingStyle.fill;
      final stroke = Paint()
        ..color = recognitionColor.withOpacity(0.46 + pulse * 0.12)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5 + pulse * 0.5;
      canvas.drawPath(path, fill);
      canvas.drawPath(path, stroke);
    }
    if (triggerViewport.length == 4) {
      final path = _path(triggerViewport, close: true);
      final stroke = Paint()
        ..color = zoneColor.withOpacity(0.78)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      canvas.drawPath(path, stroke);
    }
    for (var index = 0; index < cameraBoundingBoxes.length; index++) {
      final cameraRect = cameraBoundingBoxes[index];
      final rect = mapper.cameraImageNormalizedRectToViewport(cameraRect);
      if (rect.isEmpty) continue;
      final matched = matchedIndexes.contains(index);
      final color = matched ? matchedColor : normalColor;
      final strokeWidth = matched ? 3.0 + pulse * 1.5 : 2.0;
      final fill = Paint()
        ..color = color.withOpacity(matched ? 0.10 + pulse * 0.06 : 0.04)
        ..style = PaintingStyle.fill;
      final stroke = Paint()
        ..color = color.withOpacity(matched ? 0.95 : 0.72)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;
      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(matched ? 14 : 10),
      );
      canvas.drawRRect(rrect, fill);
      canvas.drawRRect(rrect, stroke);
      final bottomCenter = mapper.cameraImageNormalizedToViewport(
        Offset(cameraRect.center.dx, cameraRect.bottom),
      );
      final pointPaint = Paint()
        ..color = color.withOpacity(matched ? 1 : 0.72)
        ..style = PaintingStyle.fill;
      canvas.drawCircle(bottomCenter, matched ? 4.5 + pulse : 3.0, pointPaint);
      if (matched && cameraPolygon.length == 4) {
        final clipped =
            SensorPolygonGeometry.clipPolygonWithRect(cameraPolygon, cameraRect);
        if (clipped.length >= 3) {
          final overlapViewport = mapper.cameraImageNormalizedPolygonToViewport(
            clipped,
          );
          final overlapPaint = Paint()
            ..color = matchedColor.withOpacity(0.20 + pulse * 0.08)
            ..style = PaintingStyle.fill;
          canvas.drawPath(_path(overlapViewport, close: true), overlapPaint);
        }
      }
    }
  }

  Path _path(List<Offset> points, {required bool close}) {
    final path = Path();
    if (points.isEmpty) return path;
    path.moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (close) path.close();
    return path;
  }

  @override
  bool shouldRepaint(covariant _SensorDetectionDebugPainter oldDelegate) {
    return oldDelegate.mapper.previewSourceSize != mapper.previewSourceSize ||
        oldDelegate.mapper.cameraImageSize != mapper.cameraImageSize ||
        oldDelegate.mapper.viewportSize != mapper.viewportSize ||
        oldDelegate.mapper.fit != mapper.fit ||
        oldDelegate.cameraBoundingBoxes != cameraBoundingBoxes ||
        oldDelegate.matchedIndexes != matchedIndexes ||
        oldDelegate.triggerZone?.fingerprint != triggerZone?.fingerprint ||
        oldDelegate.recognitionZone?.fingerprint != recognitionZone?.fingerprint ||
        oldDelegate.normalColor != normalColor ||
        oldDelegate.matchedColor != matchedColor ||
        oldDelegate.zoneColor != zoneColor ||
        oldDelegate.recognitionColor != recognitionColor ||
        oldDelegate.pulse != pulse;
  }
}
