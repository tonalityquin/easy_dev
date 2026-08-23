import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

typedef ParkingSpatialSourceRectBuilder = Widget Function(
  BuildContext context,
  double progress,
  bool interactionEnabled,
);

class ParkingSpatialCollapseInfo {
  const ParkingSpatialCollapseInfo({
    required this.expandedBeforeCollapse,
    required this.maxRawProgress,
  });

  final bool expandedBeforeCollapse;
  final double maxRawProgress;

  bool get earlyCollapse => !expandedBeforeCollapse;
}

Rect parkingSpatialTargetRect(
  BuildContext context, {
  double compactHeightFactor = .74,
  double wideHeightFactor = .78,
  double compactMaxHeight = 720,
  double wideMaxHeight = 800,
}) {
  final media = MediaQuery.of(context);
  final size = media.size;
  final safeTop = media.padding.top;
  final safeBottom = media.padding.bottom;
  final safeLeft = media.padding.left;
  final safeRight = media.padding.right;
  final availableWidth =
      math.max(220.0, size.width - safeLeft - safeRight).toDouble();
  final availableHeight =
      math.max(220.0, size.height - safeTop - safeBottom).toDouble();
  final compact = availableWidth < 600;
  final widthFactor = compact ? .92 : .76;
  final heightFactor = compact ? compactHeightFactor : wideHeightFactor;
  final maxWidth = compact ? 620.0 : 760.0;
  final maxHeight = compact ? compactMaxHeight : wideMaxHeight;
  final width = math.min(maxWidth, availableWidth * widthFactor).toDouble();
  final height = math.min(maxHeight, availableHeight * heightFactor).toDouble();
  final left = safeLeft + (availableWidth - width) / 2;
  final top = safeTop + (availableHeight - height) / 2;
  return Rect.fromLTWH(left, top, width, height);
}

String parkingSpatialRectDebug(Rect rect) {
  return '${rect.left.toStringAsFixed(1)},${rect.top.toStringAsFixed(1)},'
      '${rect.width.toStringAsFixed(1)},${rect.height.toStringAsFixed(1)}';
}

class ParkingSpatialSourceRectTransition extends StatefulWidget {
  const ParkingSpatialSourceRectTransition({
    super.key,
    required this.animation,
    required this.sourceRect,
    required this.targetRect,
    required this.reduceMotion,
    required this.closeSemanticsLabel,
    required this.onCloseRequested,
    required this.onSystemPop,
    required this.onExpanded,
    required this.onCollapsed,
    this.onCollapseLifecycle,
    required this.builder,
  });

  final Animation<double> animation;
  final Rect sourceRect;
  final Rect targetRect;
  final bool reduceMotion;
  final String closeSemanticsLabel;
  final ValueChanged<String> onCloseRequested;
  final VoidCallback onSystemPop;
  final VoidCallback onExpanded;
  final VoidCallback onCollapsed;
  final ValueChanged<ParkingSpatialCollapseInfo>? onCollapseLifecycle;
  final ParkingSpatialSourceRectBuilder builder;

  @override
  State<ParkingSpatialSourceRectTransition> createState() =>
      _ParkingSpatialSourceRectTransitionState();
}

class _ParkingSpatialSourceRectTransitionState
    extends State<ParkingSpatialSourceRectTransition> {
  bool _expandedReported = false;
  bool _collapsedReported = false;
  bool _transitionActivated = false;
  bool _reverseInputBlocked = false;
  double _maxRawProgress = 0;

  @override
  void initState() {
    super.initState();
    _maxRawProgress =
        widget.animation.value.clamp(0.0, 1.0).toDouble();
    _transitionActivated =
        widget.animation.status != AnimationStatus.dismissed ||
            widget.animation.value > 0;
    _reverseInputBlocked =
        widget.animation.status == AnimationStatus.reverse;
    widget.animation.addStatusListener(_onAnimationStatus);
    if (widget.animation.status == AnimationStatus.completed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || widget.animation.status != AnimationStatus.completed) {
          return;
        }
        _onAnimationStatus(AnimationStatus.completed);
      });
    }
  }

  @override
  void didUpdateWidget(covariant ParkingSpatialSourceRectTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation == widget.animation) return;
    oldWidget.animation.removeStatusListener(_onAnimationStatus);
    _expandedReported = false;
    _collapsedReported = false;
    _maxRawProgress =
        widget.animation.value.clamp(0.0, 1.0).toDouble();
    _transitionActivated =
        widget.animation.status != AnimationStatus.dismissed ||
            widget.animation.value > 0;
    _reverseInputBlocked =
        widget.animation.status == AnimationStatus.reverse;
    widget.animation.addStatusListener(_onAnimationStatus);
  }

  @override
  void dispose() {
    widget.animation.removeStatusListener(_onAnimationStatus);
    super.dispose();
  }

  void _onAnimationStatus(AnimationStatus status) {
    final reverseInputBlocked = status == AnimationStatus.reverse;
    if (_reverseInputBlocked != reverseInputBlocked) {
      _reverseInputBlocked = reverseInputBlocked;
      if (mounted) {
        setState(() {});
      }
    }
    if (status != AnimationStatus.dismissed) {
      _transitionActivated = true;
    }
    if (status == AnimationStatus.completed && !_expandedReported) {
      _expandedReported = true;
      widget.onExpanded();
    }
    if (status == AnimationStatus.dismissed &&
        _transitionActivated &&
        !_collapsedReported) {
      _collapsedReported = true;
      final info = ParkingSpatialCollapseInfo(
        expandedBeforeCollapse: _expandedReported,
        maxRawProgress: _maxRawProgress,
      );
      widget.onCollapseLifecycle?.call(info);
      widget.onCollapsed();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: !_reverseInputBlocked,
      onPopInvoked: (didPop) {
        if (!didPop) return;
        widget.onSystemPop();
      },
      child: Material(
        type: MaterialType.transparency,
        child: AnimatedBuilder(
          animation: widget.animation,
          builder: (context, _) {
            final raw = widget.reduceMotion
                ? 1.0
                : widget.animation.value.clamp(0.0, 1.0).toDouble();
            if (raw > _maxRawProgress) {
              _maxRawProgress = raw;
            }
            final reversing =
                widget.animation.status == AnimationStatus.reverse;
            final progress = widget.reduceMotion
                ? 1.0
                : reversing && _expandedReported
                    ? Curves.easeInOutCubic.transform(raw)
                    : Curves.easeOutCubic.transform(raw);
            final rect =
                Rect.lerp(widget.sourceRect, widget.targetRect, progress) ??
                    widget.targetRect;
            final sigma = 4.5 * progress;
            final radius = 8 + 12 * progress;
            return Stack(
              children: [
                Positioned.fill(
                  child: AbsorbPointer(
                    absorbing: reversing,
                    child: ExcludeSemantics(
                      excluding: reversing,
                      child: Semantics(
                        button: true,
                        label: widget.closeSemanticsLabel,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => widget.onCloseRequested('scrim'),
                          child: BackdropFilter(
                            filter: ImageFilter.blur(
                              sigmaX: sigma,
                              sigmaY: sigma,
                            ),
                            child: ColoredBox(
                              color: cs.scrim.withOpacity(.26 * progress),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fromRect(
                  rect: rect,
                  child: Opacity(
                    opacity: (.88 + .12 * progress)
                        .clamp(0.0, 1.0)
                        .toDouble(),
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(radius),
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withOpacity(.14 * progress),
                            blurRadius: 22 * progress,
                            offset: Offset(0, 7 * progress),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(radius),
                        child: widget.builder(
                          context,
                          progress,
                          !reversing && progress >= .94,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
