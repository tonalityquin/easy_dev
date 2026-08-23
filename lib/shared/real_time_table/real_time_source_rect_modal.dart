import 'package:flutter/material.dart';

import '../parking_spatial/parking_spatial_transition.dart';

typedef RealTimeSourceRectModalBuilder = Widget Function(
  BuildContext context,
  double progress,
  bool interactionEnabled,
);

class RealTimeSourceRectModalCollapseInfo {
  const RealTimeSourceRectModalCollapseInfo({
    required this.expandedBeforeCollapse,
    required this.maxRawProgress,
  });

  final bool expandedBeforeCollapse;
  final double maxRawProgress;

  bool get earlyCollapse => !expandedBeforeCollapse;
}

Rect realTimeSourceRectModalTargetRect(
  BuildContext context, {
  double compactHeightFactor = .74,
  double wideHeightFactor = .78,
  double compactMaxHeight = 720,
  double wideMaxHeight = 800,
}) {
  return parkingSpatialTargetRect(
    context,
    compactHeightFactor: compactHeightFactor,
    wideHeightFactor: wideHeightFactor,
    compactMaxHeight: compactMaxHeight,
    wideMaxHeight: wideMaxHeight,
  );
}

String realTimeSourceRectDebug(Rect rect) => parkingSpatialRectDebug(rect);

class RealTimeSourceRectModalTransition extends StatelessWidget {
  const RealTimeSourceRectModalTransition({
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
  final ValueChanged<RealTimeSourceRectModalCollapseInfo>? onCollapseLifecycle;
  final RealTimeSourceRectModalBuilder builder;

  @override
  Widget build(BuildContext context) {
    return ParkingSpatialSourceRectTransition(
      animation: animation,
      sourceRect: sourceRect,
      targetRect: targetRect,
      reduceMotion: reduceMotion,
      closeSemanticsLabel: closeSemanticsLabel,
      onCloseRequested: onCloseRequested,
      onSystemPop: onSystemPop,
      onExpanded: onExpanded,
      onCollapsed: onCollapsed,
      onCollapseLifecycle: onCollapseLifecycle == null
          ? null
          : (info) => onCollapseLifecycle!(
                RealTimeSourceRectModalCollapseInfo(
                  expandedBeforeCollapse: info.expandedBeforeCollapse,
                  maxRawProgress: info.maxRawProgress,
                ),
              ),
      builder: builder,
    );
  }
}
