import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../../shared/parking_dot_map/parking_status_dot_map_surface.dart';
import '../../../../location/domain/models/grid_rect.dart';
import '../../../../location/domain/models/parking_grid_model.dart';

@immutable
class TabletParkingGuidanceMarker extends ParkingGuidanceMarker {
  const TabletParkingGuidanceMarker({
    required super.rect,
    required super.exact,
    required super.attention,
    required super.selected,
  });
}

class TabletParkingGuidanceMapSurface extends StatelessWidget {
  final ParkingGridModel grid;
  final List<TabletParkingGuidanceMarker> markers;
  final GridRect? targetRect;
  final bool exactTarget;
  final Animation<double>? pulseAnimation;
  final bool framed;
  final double padding;

  const TabletParkingGuidanceMapSurface({
    super.key,
    required this.grid,
    this.markers = const <TabletParkingGuidanceMarker>[],
    this.targetRect,
    this.exactTarget = false,
    this.pulseAnimation,
    this.framed = false,
    this.padding = 14,
  });

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final pulse = pulseAnimation ?? const AlwaysStoppedAnimation<double>(1);
    final map = AnimatedBuilder(
      animation: pulse,
      builder: (context, _) {
        return ParkingGuidanceMapSurface(
          grid: grid,
          markers: markers,
          targetRect: targetRect,
          exact: exactTarget,
          pulse: pulse.value.clamp(0.0, 1.0).toDouble(),
          framed: framed,
          padding: padding,
        );
      },
    );

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: reduceMotion ? Duration.zero : CommonUiMotion.overlay,
      curve: CommonUiMotion.enter,
      child: map,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.scale(
            scale: 0.985 + 0.015 * value,
            child: child!,
          ),
        );
      },
    );
  }
}
