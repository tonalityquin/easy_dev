import 'package:flutter/material.dart';

import '../../design_system/common_ui/common_ui_theme.dart';
import 'parking_spatial_child_regions.dart';

class ParkingSpatialChildRegionVisual<T> extends StatefulWidget {
  const ParkingSpatialChildRegionVisual({
    super.key,
    required this.entry,
    required this.selected,
    required this.peeked,
    required this.reduceMotion,
  });

  final ParkingSpatialChildRegion<T> entry;
  final bool selected;
  final bool peeked;
  final bool reduceMotion;

  @override
  State<ParkingSpatialChildRegionVisual<T>> createState() =>
      _ParkingSpatialChildRegionVisualState<T>();
}

class _ParkingSpatialChildRegionVisualState<T>
    extends State<ParkingSpatialChildRegionVisual<T>>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _highlightController;

  bool get _highlighted => widget.selected || widget.peeked;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: widget.reduceMotion ? 1 : 0,
    );
    _highlightController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 170),
      value: _highlighted ? 1 : 0,
    );
    if (!widget.reduceMotion) {
      _entryController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant ParkingSpatialChildRegionVisual<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion) {
      _entryController.value = 1;
      _highlightController.value = _highlighted ? 1 : 0;
      return;
    }
    if (oldWidget.reduceMotion && !widget.reduceMotion) {
      _entryController.value = 1;
    }
    final target = _highlighted ? 1.0 : 0.0;
    if (_highlightController.value != target) {
      _highlightController.animateTo(target, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _entryController.dispose();
    _highlightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final localPath = widget.entry.effectivePath.shift(
      -widget.entry.nominalRect.topLeft,
    );
    final localNominalRect = Offset.zero & widget.entry.nominalRect.size;

    return Positioned.fromRect(
      rect: widget.entry.nominalRect,
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _entryController,
          builder: (context, _) {
            final entryProgress = Curves.easeOutCubic.transform(
              _entryController.value.clamp(0.0, 1.0).toDouble(),
            );
            return AnimatedBuilder(
              animation: _highlightController,
              builder: (context, _) {
                final highlightProgress = Curves.easeOutCubic.transform(
                  _highlightController.value.clamp(0.0, 1.0).toDouble(),
                );
                final scale =
                    (.97 + .03 * entryProgress) * (1 + .012 * highlightProgress);
                return Opacity(
                  opacity: entryProgress,
                  child: Transform.scale(
                    scale: scale,
                    alignment: Alignment.center,
                    child: CustomPaint(
                      painter: _ParkingSpatialChildRegionPainter(
                        nominalRect: localNominalRect,
                        effectivePath: localPath,
                        useEffectiveShape: widget.entry.useEffectiveShape,
                        highlightProgress: highlightProgress,
                        fillColor: tokens.accent,
                        strokeColor: tokens.accent,
                        nominalStrokeColor: tokens.borderStrong,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

class _ParkingSpatialChildRegionPainter extends CustomPainter {
  const _ParkingSpatialChildRegionPainter({
    required this.nominalRect,
    required this.effectivePath,
    required this.useEffectiveShape,
    required this.highlightProgress,
    required this.fillColor,
    required this.strokeColor,
    required this.nominalStrokeColor,
  });

  final Rect nominalRect;
  final Path effectivePath;
  final bool useEffectiveShape;
  final double highlightProgress;
  final Color fillColor;
  final Color strokeColor;
  final Color nominalStrokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final highlight = highlightProgress.clamp(0.0, 1.0).toDouble();
    if (useEffectiveShape) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(nominalRect, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = nominalStrokeColor.withOpacity(.32 + .12 * highlight),
      );
    }
    if (highlight > 0) {
      canvas.drawShadow(
        effectivePath,
        strokeColor.withOpacity(.16 * highlight),
        6 + 4 * highlight,
        false,
      );
    }
    canvas.drawPath(
      effectivePath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor.withOpacity(.018 + .035 * highlight),
    );
    canvas.drawPath(
      effectivePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8 + .6 * highlight
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(
          nominalStrokeColor,
          strokeColor,
          .18 + .82 * highlight,
        )!.withOpacity(.92 + .08 * highlight),
    );
  }

  @override
  bool shouldRepaint(covariant _ParkingSpatialChildRegionPainter oldDelegate) {
    return oldDelegate.nominalRect != nominalRect ||
        oldDelegate.effectivePath != effectivePath ||
        oldDelegate.useEffectiveShape != useEffectiveShape ||
        oldDelegate.highlightProgress != highlightProgress ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.nominalStrokeColor != nominalStrokeColor;
  }
}

class ParkingSpatialChildRegionHitTarget<T> extends StatelessWidget {
  const ParkingSpatialChildRegionHitTarget({
    super.key,
    required this.entry,
    required this.semanticsLabel,
    required this.onTap,
    this.onLongPressStart,
    this.onLongPressEnd,
    this.onLongPressCancel,
  });

  final ParkingSpatialChildRegion<T> entry;
  final String semanticsLabel;
  final VoidCallback onTap;
  final ValueChanged<Offset>? onLongPressStart;
  final VoidCallback? onLongPressEnd;
  final VoidCallback? onLongPressCancel;

  @override
  Widget build(BuildContext context) {
    final localPath = entry.effectivePath.shift(-entry.hitRect.topLeft);
    return Positioned.fromRect(
      rect: entry.hitRect,
      child: Semantics(
        button: true,
        label: semanticsLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.deferToChild,
          onTap: onTap,
          onLongPressStart: onLongPressStart == null
              ? null
              : (details) => onLongPressStart!(details.localPosition),
          onLongPressEnd:
              onLongPressEnd == null ? null : (_) => onLongPressEnd!(),
          onLongPressCancel: onLongPressCancel,
          child: CustomPaint(
            painter: _ParkingSpatialChildRegionHitPainter(localPath),
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
  }
}

class _ParkingSpatialChildRegionHitPainter extends CustomPainter {
  const _ParkingSpatialChildRegionHitPainter(this.path);

  final Path path;

  @override
  void paint(Canvas canvas, Size size) {}

  @override
  bool? hitTest(Offset position) => path.contains(position);

  @override
  bool shouldRepaint(
    covariant _ParkingSpatialChildRegionHitPainter oldDelegate,
  ) {
    return oldDelegate.path != path;
  }
}

class ParkingSpatialChildFocusRegionVisual extends StatelessWidget {
  const ParkingSpatialChildFocusRegionVisual({
    super.key,
    required this.nominalRect,
    required this.effectivePath,
    required this.useEffectiveShape,
    required this.progress,
  });

  final Rect nominalRect;
  final Path effectivePath;
  final bool useEffectiveShape;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Positioned.fill(
      child: IgnorePointer(
        child: CustomPaint(
          painter: _ParkingSpatialChildFocusRegionPainter(
            nominalRect: nominalRect,
            effectivePath: effectivePath,
            useEffectiveShape: useEffectiveShape,
            progress: progress,
            fillColor: tokens.accent,
            strokeColor: tokens.accent,
            nominalStrokeColor: tokens.borderStrong,
          ),
        ),
      ),
    );
  }
}

class _ParkingSpatialChildFocusRegionPainter extends CustomPainter {
  const _ParkingSpatialChildFocusRegionPainter({
    required this.nominalRect,
    required this.effectivePath,
    required this.useEffectiveShape,
    required this.progress,
    required this.fillColor,
    required this.strokeColor,
    required this.nominalStrokeColor,
  });

  final Rect nominalRect;
  final Path effectivePath;
  final bool useEffectiveShape;
  final double progress;
  final Color fillColor;
  final Color strokeColor;
  final Color nominalStrokeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final eased = Curves.easeOutCubic.transform(
      progress.clamp(0.0, 1.0).toDouble(),
    );
    if (eased <= 0) return;
    final center = nominalRect.center;
    final scale = .985 + .015 * eased;
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale, scale);
    canvas.translate(-center.dx, -center.dy);
    if (useEffectiveShape) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(nominalRect, const Radius.circular(8)),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = nominalStrokeColor.withOpacity(.34 * eased),
      );
    }
    canvas.drawPath(
      effectivePath,
      Paint()
        ..style = PaintingStyle.fill
        ..color = fillColor.withOpacity(.018 * eased),
    );
    canvas.drawPath(
      effectivePath,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8 + .4 * eased
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round
        ..color = Color.lerp(
          nominalStrokeColor,
          strokeColor,
          .26 + .44 * eased,
        )!.withOpacity(.9 * eased),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(
    covariant _ParkingSpatialChildFocusRegionPainter oldDelegate,
  ) {
    return oldDelegate.nominalRect != nominalRect ||
        oldDelegate.effectivePath != effectivePath ||
        oldDelegate.useEffectiveShape != useEffectiveShape ||
        oldDelegate.progress != progress ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.strokeColor != strokeColor ||
        oldDelegate.nominalStrokeColor != nominalStrokeColor;
  }
}
