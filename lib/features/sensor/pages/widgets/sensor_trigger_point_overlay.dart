import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../applications/sensor_debug_trace.dart';
import '../../applications/sensor_trigger_zone.dart';

class SensorTriggerPointOverlay extends StatefulWidget {
  const SensorTriggerPointOverlay({
    super.key,
    required this.viewportCorners,
    required this.isEditing,
    required this.isSaving,
    required this.isPreparingGeometry,
    required this.isDragging,
    required this.reduceMotion,
    required this.baselineReady,
    required this.baselineSaving,
    required this.feedbackCornerIndex,
    required this.feedbackCornerSerial,
    required this.rejectedCornerIndex,
    required this.rejectedCornerSerial,
    required this.entryEdgeType,
    required this.onEdit,
    required this.onSave,
    required this.onCancel,
    required this.onSaveBaseline,
    required this.onResizeStart,
    required this.onResizeUpdate,
    required this.onResizeEnd,
  });

  final List<Offset> viewportCorners;
  final bool isEditing;
  final bool isSaving;
  final bool isPreparingGeometry;
  final bool isDragging;
  final bool reduceMotion;
  final bool baselineReady;
  final bool baselineSaving;
  final int? feedbackCornerIndex;
  final int feedbackCornerSerial;
  final int? rejectedCornerIndex;
  final int rejectedCornerSerial;
  final SensorTriggerZoneEdge? entryEdgeType;
  final VoidCallback? onEdit;
  final VoidCallback? onSave;
  final VoidCallback? onCancel;
  final VoidCallback? onSaveBaseline;
  final ValueChanged<SensorTriggerZoneHandle>? onResizeStart;
  final void Function(SensorTriggerZoneHandle handle, Offset delta)?
      onResizeUpdate;
  final VoidCallback? onResizeEnd;

  @override
  State<SensorTriggerPointOverlay> createState() =>
      _SensorTriggerPointOverlayState();
}

class _SensorTriggerPointOverlayState extends State<SensorTriggerPointOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _edgeRevealController;
  late final AnimationController _completionController;
  late final AnimationController _entryEdgeController;
  int? _revealingFromCount;
  int? _newCornerIndex;
  int _cornerEntranceSerial = 0;
  bool _completionPending = false;
  int _pulseSyncRevision = 0;
  int _transitionSyncRevision = 0;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _edgeRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 190),
      value: 1,
    );
    _completionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    _entryEdgeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      value: 1,
    );
    _edgeRevealController.addStatusListener(_handleEdgeRevealStatus);
    _syncPulse();
  }

  @override
  void didUpdateWidget(covariant SensorTriggerPointOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isEditing != widget.isEditing ||
        oldWidget.reduceMotion != widget.reduceMotion) {
      _schedulePulseSync();
    }
    if (oldWidget.entryEdgeType != widget.entryEdgeType &&
        widget.entryEdgeType != null) {
      if (widget.reduceMotion) {
        _scheduleTransitionSync(
          event: 'entry_edge_animation_reduced',
          details: <String, Object?>{
            'entryEdge': widget.entryEdgeType?.name,
          },
          action: () {
            _entryEdgeController.stop();
            if (_entryEdgeController.value != 1.0) {
              _entryEdgeController.value = 1.0;
            }
          },
        );
      } else {
        _scheduleTransitionSync(
          event: 'entry_edge_animation_started',
          details: <String, Object?>{
            'entryEdge': widget.entryEdgeType?.name,
          },
          action: () {
            _entryEdgeController.forward(from: 0.0);
          },
        );
      }
    }

    if (!widget.isEditing) {
      _newCornerIndex = null;
      _revealingFromCount = null;
      _completionPending = false;
      final transitionNeedsReset = oldWidget.isEditing ||
          _edgeRevealController.isAnimating ||
          _completionController.isAnimating ||
          _edgeRevealController.value != 1.0 ||
          _completionController.value != 0.0;
      if (transitionNeedsReset) {
        _scheduleTransitionSync(
          event: 'trigger_overlay_idle_sync',
          action: () {
            _edgeRevealController.stop();
            _completionController.stop();
            if (_edgeRevealController.value != 1.0) {
              _edgeRevealController.value = 1.0;
            }
            if (_completionController.value != 0.0) {
              _completionController.value = 0.0;
            }
          },
        );
      }
      return;
    }

    final oldCount = oldWidget.viewportCorners.length;
    final newCount = widget.viewportCorners.length;
    final addedCorner = oldWidget.isEditing &&
        newCount == oldCount + 1 &&
        newCount >= 1 &&
        newCount <= 4;
    if (!addedCorner) {
      if (oldWidget.isEditing != widget.isEditing) {
        _newCornerIndex = null;
      }
      return;
    }

    _newCornerIndex = newCount - 1;
    _cornerEntranceSerial++;
    SensorDebugTrace.record(
      'SensorTriggerAnimation',
      'corner_added',
      <String, Object?>{
        'oldCount': oldCount,
        'newCount': newCount,
        'reduceMotion': widget.reduceMotion,
      },
    );

    if (widget.reduceMotion || newCount == 1) {
      _revealingFromCount = null;
      _completionPending = false;
      _scheduleTransitionSync(
        event: 'corner_transition_reset',
        action: () {
          _edgeRevealController.stop();
          _completionController.stop();
          if (_edgeRevealController.value != 1.0) {
            _edgeRevealController.value = 1.0;
          }
          if (_completionController.value != 0.0) {
            _completionController.value = 0.0;
          }
        },
      );
      return;
    }

    _revealingFromCount = oldCount;
    _completionPending = newCount == 4;
    final revealDuration = Duration(
      milliseconds: newCount == 4 ? 320 : 190,
    );
    _scheduleTransitionSync(
      event: 'edge_reveal_started',
      details: <String, Object?>{
        'fromCount': oldCount,
        'toCount': newCount,
        'durationMs': revealDuration.inMilliseconds,
      },
      action: () {
        _edgeRevealController.duration = revealDuration;
        _completionController.stop();
        if (_completionController.value != 0.0) {
          _completionController.value = 0.0;
        }
        _edgeRevealController.forward(from: 0.0);
      },
    );
  }

  void _handleEdgeRevealStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !_completionPending) return;
    _completionPending = false;
    if (!mounted || widget.reduceMotion || widget.viewportCorners.length != 4) {
      return;
    }
    _scheduleTransitionSync(
      event: 'completion_pulse_started',
      details: <String, Object?>{'cornerCount': widget.viewportCorners.length},
      action: () {
        _completionController.forward(from: 0.0);
      },
    );
  }

  void _schedulePulseSync() {
    final revision = ++_pulseSyncRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _pulseSyncRevision) return;
      _syncPulse();
    });
  }

  void _scheduleTransitionSync({
    required String event,
    required VoidCallback action,
    Map<String, Object?> details = const <String, Object?>{},
  }) {
    final revision = ++_transitionSyncRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _transitionSyncRevision) return;
      action();
      SensorDebugTrace.record(
        'SensorTriggerAnimation',
        event,
        <String, Object?>{
          ...details,
          'edgeValue': _edgeRevealController.value.toStringAsFixed(3),
          'completionValue': _completionController.value.toStringAsFixed(3),
        },
      );
    });
  }

  void _syncPulse() {
    final shouldPulse = widget.isEditing && !widget.reduceMotion;
    if (shouldPulse) {
      if (!_pulseController.isAnimating) {
        _pulseController.repeat(reverse: true);
        SensorDebugTrace.record(
          'SensorTriggerAnimation',
          'pulse_started',
        );
      }
      return;
    }

    final wasAnimating = _pulseController.isAnimating;
    _pulseController.stop();
    if (_pulseController.value != 0.0) {
      _pulseController.value = 0.0;
    }
    if (wasAnimating) {
      SensorDebugTrace.record(
        'SensorTriggerAnimation',
        'pulse_stopped',
      );
    }
  }

  Widget _fadeScaleTransition({
    required Widget child,
    required Animation<double> animation,
    required double beginScale,
  }) {
    final fade = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final scale = Tween<double>(
      begin: beginScale,
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
  }

  double _completionStrength() {
    if (widget.reduceMotion) return 0;
    final value = _completionController.value;
    if (value <= 0.5) return value * 2;
    return (1 - value) * 2;
  }

  double _entryEdgeStrength() {
    if (widget.reduceMotion) return 0;
    final value = _entryEdgeController.value;
    if (value <= 0.5) return value * 2;
    return (1 - value) * 2;
  }

  @override
  void dispose() {
    _edgeRevealController.removeStatusListener(_handleEdgeRevealStatus);
    _pulseController.dispose();
    _edgeRevealController.dispose();
    _completionController.dispose();
    _entryEdgeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final corners = widget.viewportCorners;
    final visualDuration =
        widget.reduceMotion ? Duration.zero : const Duration(milliseconds: 180);
    return Stack(
      fit: StackFit.expand,
      children: <Widget>[
        if (corners.isNotEmpty)
          IgnorePointer(
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[
                _pulseController,
                _edgeRevealController,
                _completionController,
                _entryEdgeController,
              ]),
              builder: (context, child) {
                return CustomPaint(
                  painter: _TriggerPolygonPainter(
                    points: corners,
                    color: tokens.accent,
                    editing: widget.isEditing,
                    pulse: widget.reduceMotion ? 0 : _pulseController.value,
                    revealingFromCount: _revealingFromCount,
                    edgeProgress:
                        widget.reduceMotion ? 1 : _edgeRevealController.value,
                    completion: _completionStrength(),
                    entryEdgeType: widget.entryEdgeType,
                    entryColor: tokens.warning,
                    entrySelection: _entryEdgeStrength(),
                  ),
                );
              },
            ),
          ),
        if (widget.isEditing)
          ...List<Widget>.generate(
            corners.length,
            (index) => _CornerHandle(
              index: index,
              point: corners[index],
              handle: SensorTriggerZoneHandle.values[index],
              reduceMotion: widget.reduceMotion,
              entranceSerial:
                  _newCornerIndex == index ? _cornerEntranceSerial : 0,
              feedbackSerial: widget.feedbackCornerIndex == index
                  ? widget.feedbackCornerSerial
                  : 0,
              rejectionSerial: widget.rejectedCornerIndex == index
                  ? widget.rejectedCornerSerial
                  : 0,
              onStart: widget.onResizeStart,
              onUpdate: widget.onResizeUpdate,
              onEnd: widget.onResizeEnd,
            ),
          ),
        Positioned(
          right: 12,
          top: 64,
          child: AnimatedSwitcher(
            duration: widget.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 220),
            switchInCurve: Curves.linear,
            switchOutCurve: Curves.linear,
            transitionBuilder: (child, animation) {
              return _fadeScaleTransition(
                child: child,
                animation: animation,
                beginScale: 0.88,
              );
            },
            child: widget.isEditing
                ? Row(
                    key: const ValueKey<String>('trigger-edit-controls'),
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      IconButton.filledTonal(
                        onPressed: widget.isSaving ? null : widget.onCancel,
                        icon: const Icon(Icons.close_rounded),
                      ),
                      const SizedBox(width: 8),
                      AnimatedScale(
                        duration: visualDuration,
                        curve: Curves.easeOutCubic,
                        scale: widget.isSaving ? 0.94 : 1,
                        child: IconButton.filled(
                          onPressed: widget.isSaving ? null : widget.onSave,
                          icon: AnimatedSwitcher(
                            duration: widget.reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 160),
                            child: widget.isSaving
                                ? const SizedBox(
                                    key: ValueKey<String>('trigger-saving'),
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_rounded,
                                    key: ValueKey<String>('trigger-save'),
                                  ),
                          ),
                        ),
                      ),
                    ],
                  )
                : IconButton.filledTonal(
                    key: ValueKey<String>(
                      widget.isPreparingGeometry
                          ? 'trigger-geometry-preparing'
                          : 'trigger-edit',
                    ),
                    onPressed: widget.isPreparingGeometry ? null : widget.onEdit,
                    icon: AnimatedSwitcher(
                      duration: widget.reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      child: widget.isPreparingGeometry
                          ? const SizedBox(
                              key: ValueKey<String>('trigger-geometry-progress'),
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.polyline_rounded,
                              key: ValueKey<String>('trigger-geometry-ready'),
                            ),
                    ),
                  ),
          ),
        ),
        Positioned(
          right: 12,
          top: 116,
          child: AnimatedSwitcher(
            duration: widget.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 260),
            switchInCurve: Curves.linear,
            switchOutCurve: Curves.linear,
            transitionBuilder: (child, animation) {
              return _fadeScaleTransition(
                child: child,
                animation: animation,
                beginScale: 0.86,
              );
            },
            child: widget.isEditing ||
                    (widget.onSaveBaseline == null && !widget.baselineSaving) ||
                    (widget.baselineReady && !widget.baselineSaving)
                ? const SizedBox.shrink(
                    key: ValueKey<String>('baseline-action-hidden'),
                  )
                : AnimatedScale(
                    key: const ValueKey<String>('baseline-action-visible'),
                    duration: visualDuration,
                    curve: Curves.easeOutCubic,
                    scale: widget.baselineSaving ? 0.95 : 1,
                    child: FilledButton.tonalIcon(
                      onPressed: widget.baselineSaving
                          ? null
                          : widget.onSaveBaseline,
                      icon: AnimatedSwitcher(
                        duration: widget.reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        child: widget.baselineSaving
                            ? const SizedBox(
                                key: ValueKey<String>('baseline-saving'),
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.add_photo_alternate_outlined,
                                key: ValueKey<String>('baseline-save'),
                                size: 18,
                              ),
                      ),
                      label: const Text('기준 저장'),
                    ),
                  ),
          ),
        ),
      ],
    );
  }
}

class _TriggerPolygonPainter extends CustomPainter {
  const _TriggerPolygonPainter({
    required this.points,
    required this.color,
    required this.editing,
    required this.pulse,
    required this.revealingFromCount,
    required this.edgeProgress,
    required this.completion,
    required this.entryEdgeType,
    required this.entryColor,
    required this.entrySelection,
  });

  final List<Offset> points;
  final Color color;
  final bool editing;
  final double pulse;
  final int? revealingFromCount;
  final double edgeProgress;
  final double completion;
  final SensorTriggerZoneEdge? entryEdgeType;
  final Color entryColor;
  final double entrySelection;

  void _drawSegment(
    Canvas canvas,
    Paint paint,
    Offset start,
    Offset end, {
    double progress = 1,
  }) {
    final safeProgress = progress.clamp(0.0, 1.0).toDouble();
    if (safeProgress <= 0) return;
    canvas.drawLine(start, Offset.lerp(start, end, safeProgress)!, paint);
  }

  void _drawPolygonStroke(Canvas canvas, Paint paint) {
    final count = points.length;
    if (count < 2) return;
    final revealFrom = revealingFromCount;
    if (revealFrom == null || edgeProgress >= 1 || revealFrom >= count) {
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      if (count == 4) path.close();
      canvas.drawPath(path, paint);
      return;
    }
    if (count == 2 && revealFrom == 1) {
      _drawSegment(
        canvas,
        paint,
        points[0],
        points[1],
        progress: edgeProgress,
      );
      return;
    }
    if (count == 3 && revealFrom == 2) {
      _drawSegment(canvas, paint, points[0], points[1]);
      _drawSegment(
        canvas,
        paint,
        points[1],
        points[2],
        progress: edgeProgress,
      );
      return;
    }
    if (count == 4 && revealFrom == 3) {
      _drawSegment(canvas, paint, points[0], points[1]);
      _drawSegment(canvas, paint, points[1], points[2]);
      const firstPart = 0.56;
      if (edgeProgress <= firstPart) {
        _drawSegment(
          canvas,
          paint,
          points[2],
          points[3],
          progress: edgeProgress / firstPart,
        );
      } else {
        _drawSegment(canvas, paint, points[2], points[3]);
        _drawSegment(
          canvas,
          paint,
          points[3],
          points[0],
          progress: (edgeProgress - firstPart) / (1 - firstPart),
        );
      }
      return;
    }
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    if (count == 4) path.close();
    canvas.drawPath(path, paint);
  }

  List<int>? _entryIndexes() {
    switch (entryEdgeType) {
      case SensorTriggerZoneEdge.edge12:
        return const <int>[0, 1];
      case SensorTriggerZoneEdge.edge23:
        return const <int>[1, 2];
      case SensorTriggerZoneEdge.edge34:
        return const <int>[2, 3];
      case SensorTriggerZoneEdge.edge41:
        return const <int>[3, 0];
      case null:
        return null;
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final stroke = Paint()
      ..color = color.withOpacity(editing ? 0.95 : 0.62)
      ..style = PaintingStyle.stroke
      ..strokeWidth = editing ? 2.6 + pulse * 0.7 + completion * 0.9 : 1.8
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    _drawPolygonStroke(canvas, stroke);
    if (editing && points.length == 4 && edgeProgress >= 1) {
      final glow = Paint()
        ..color = color.withOpacity(
          0.08 + pulse * 0.05 + completion * 0.10,
        )
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8 + pulse * 4 + completion * 6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round;
      _drawPolygonStroke(canvas, glow);
      final indexes = _entryIndexes();
      if (indexes != null) {
        final entryGlow = Paint()
          ..color = entryColor.withOpacity(
            0.14 + pulse * 0.08 + entrySelection * 0.18,
          )
          ..style = PaintingStyle.stroke
          ..strokeWidth = 10 + pulse * 4 + entrySelection * 8
          ..strokeCap = StrokeCap.round;
        final entryStroke = Paint()
          ..color = entryColor.withOpacity(0.92)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.6 + pulse * 0.8 + entrySelection * 1.8
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(points[indexes[0]], points[indexes[1]], entryGlow);
        canvas.drawLine(points[indexes[0]], points[indexes[1]], entryStroke);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TriggerPolygonPainter oldDelegate) {
    return oldDelegate.points != points ||
        oldDelegate.color != color ||
        oldDelegate.editing != editing ||
        oldDelegate.pulse != pulse ||
        oldDelegate.revealingFromCount != revealingFromCount ||
        oldDelegate.edgeProgress != edgeProgress ||
        oldDelegate.completion != completion ||
        oldDelegate.entryEdgeType != entryEdgeType ||
        oldDelegate.entryColor != entryColor ||
        oldDelegate.entrySelection != entrySelection;
  }
}

class _CornerHandle extends StatefulWidget {
  const _CornerHandle({
    required this.index,
    required this.point,
    required this.handle,
    required this.reduceMotion,
    required this.entranceSerial,
    required this.feedbackSerial,
    required this.rejectionSerial,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final int index;
  final Offset point;
  final SensorTriggerZoneHandle handle;
  final bool reduceMotion;
  final int entranceSerial;
  final int feedbackSerial;
  final int rejectionSerial;
  final ValueChanged<SensorTriggerZoneHandle>? onStart;
  final void Function(SensorTriggerZoneHandle handle, Offset delta)? onUpdate;
  final VoidCallback? onEnd;

  @override
  State<_CornerHandle> createState() => _CornerHandleState();
}

class _CornerHandleState extends State<_CornerHandle>
    with TickerProviderStateMixin {
  late final AnimationController _entranceController;
  late final AnimationController _feedbackController;
  late final AnimationController _rejectionController;
  late final Animation<double> _entranceScale;
  late final Animation<double> _feedbackScale;
  late final Animation<double> _rejectionOffset;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );
    _feedbackController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 175),
      value: 1,
    );
    _rejectionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 155),
      value: 1,
    );
    _entranceScale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 0.72, end: 1.14)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 62,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.14, end: 1)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 38,
      ),
    ]).animate(_entranceController);
    _feedbackScale = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1, end: 1.16)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 52,
      ),
      TweenSequenceItem<double>(
        tween: Tween<double>(begin: 1.16, end: 1)
            .chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 48,
      ),
    ]).animate(_feedbackController);
    _rejectionOffset = TweenSequence<double>(<TweenSequenceItem<double>>[
      TweenSequenceItem<double>(tween: Tween<double>(begin: 0, end: -3), weight: 20),
      TweenSequenceItem<double>(tween: Tween<double>(begin: -3, end: 3), weight: 25),
      TweenSequenceItem<double>(tween: Tween<double>(begin: 3, end: -2), weight: 25),
      TweenSequenceItem<double>(tween: Tween<double>(begin: -2, end: 0), weight: 30),
    ]).animate(_rejectionController);
    if (!widget.reduceMotion && widget.entranceSerial > 0) {
      _entranceController.forward(from: 0);
    }
  }

  int _animationSyncRevision = 0;

  @override
  void didUpdateWidget(covariant _CornerHandle oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reduceMotion = widget.reduceMotion;
    final playEntrance = oldWidget.entranceSerial != widget.entranceSerial &&
        widget.entranceSerial > 0;
    final playFeedback = oldWidget.feedbackSerial != widget.feedbackSerial &&
        widget.feedbackSerial > 0;
    final playRejection = oldWidget.rejectionSerial != widget.rejectionSerial &&
        widget.rejectionSerial > 0;
    if (!reduceMotion && !playEntrance && !playFeedback && !playRejection) {
      return;
    }

    final revision = ++_animationSyncRevision;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || revision != _animationSyncRevision) return;
      if (reduceMotion) {
        _entranceController.stop();
        _feedbackController.stop();
        _rejectionController.stop();
        if (_entranceController.value != 1.0) {
          _entranceController.value = 1.0;
        }
        if (_feedbackController.value != 1.0) {
          _feedbackController.value = 1.0;
        }
        if (_rejectionController.value != 1.0) {
          _rejectionController.value = 1.0;
        }
        return;
      }
      if (playEntrance) {
        _entranceController.forward(from: 0.0);
      }
      if (playFeedback) {
        _feedbackController.forward(from: 0.0);
      }
      if (playRejection) {
        _rejectionController.forward(from: 0.0);
      }
    });
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _feedbackController.dispose();
    _rejectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    const hitSize = 40.0;
    const visualSize = 18.0;
    return Positioned(
      left: widget.point.dx - hitSize / 2,
      top: widget.point.dy - hitSize / 2,
      width: hitSize,
      height: hitSize,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (_) => widget.onStart?.call(widget.handle),
        onPanUpdate: (details) =>
            widget.onUpdate?.call(widget.handle, details.delta),
        onPanEnd: (_) => widget.onEnd?.call(),
        onPanCancel: widget.onEnd,
        child: Center(
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              _entranceController,
              _feedbackController,
              _rejectionController,
            ]),
            builder: (context, child) {
              final scale = widget.reduceMotion
                  ? 1.0
                  : _entranceScale.value * _feedbackScale.value;
              final offsetX = widget.reduceMotion ? 0.0 : _rejectionOffset.value;
              return Transform.translate(
                offset: Offset(offsetX, 0),
                child: Transform.scale(
                  scale: scale,
                  child: child,
                ),
              );
            },
            child: Container(
              width: visualSize,
              height: visualSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tokens.accent,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: tokens.accent.withOpacity(0.28),
                    blurRadius: 9,
                  ),
                ],
              ),
              child: Text(
                '${widget.index + 1}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
