import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../features/location/domain/models/grid_rect.dart';
import '../../features/location/domain/models/location_model.dart';
import '../../features/location/domain/models/parking_grid_model.dart';
import '../parking_dot_map/effective_child_region_geometry.dart';
import '../parking_dot_map/parking_status_dot_map_surface.dart';
import 'parking_spatial_geometry.dart';

class ParkingSpatialChildRegion<T> {
  const ParkingSpatialChildRegion({
    required this.zone,
    required this.source,
    required this.childRect,
    required this.nominalRect,
    required this.effectivePath,
    required this.hitRect,
    required this.useEffectiveShape,
    required this.effectiveParkingAreaIds,
    required this.containedParkingAreaCount,
    required this.ownedParkingAreaCount,
    required this.cutParkingAreaCount,
  });

  final T zone;
  final LocationModel source;
  final GridRect childRect;
  final Rect nominalRect;
  final Path effectivePath;
  final Rect hitRect;
  final bool useEffectiveShape;
  final Set<String> effectiveParkingAreaIds;
  final int containedParkingAreaCount;
  final int ownedParkingAreaCount;
  final int cutParkingAreaCount;
}

List<ParkingSpatialChildRegion<T>> resolveParkingSpatialChildRegions<T>({
  required List<T> zones,
  required LocationModel Function(T zone) sourceOf,
  required ParkingGridModel grid,
  required ParkingStatusDotMapLayout layout,
  double minimum = parkingSpatialMinimumTouchTarget,
}) {
  final mapped = <T>[];
  final sources = <LocationModel>[];
  final childRects = <GridRect>[];
  final nominalRects = <Rect>[];
  final effectivePaths = <Path>[];
  final useEffectiveShapes = <bool>[];
  final areaIds = <Set<String>>[];
  final stats = <EffectiveChildRegionStats>[];

  for (final zone in zones) {
    final source = sourceOf(zone);
    final childRect = resolveParkingSpatialChildRect(source, grid);
    if (childRect == null) continue;
    final nominalRect = layout.rectFor(childRect).intersect(layout.mapRect);
    if (nominalRect.isEmpty || nominalRect.width <= 0 || nominalRect.height <= 0) {
      continue;
    }
    final effectiveAreaIds = resolvedChildParkingAreaIds(source);
    final useEffectiveShape = !source.isTowerChild;
    final regionStats = effectiveChildRegionStats(
      grid: grid,
      childRect: childRect,
      effectiveParkingAreaIds: effectiveAreaIds,
    );
    final effectivePath = buildEffectiveChildRegionPath(
      grid: grid,
      childRect: childRect,
      effectiveParkingAreaIds: effectiveAreaIds,
      nominalRegion: RRect.fromRectAndRadius(
        nominalRect,
        const Radius.circular(8),
      ),
      useEffectiveShape: useEffectiveShape,
      parkingAreaRect: (area) => layout.rectFor(
        GridRect(
          r0: area.r0,
          c0: area.c0,
          r1: area.r1,
          c1: area.c1,
        ),
      ),
      cutInflate: math.max(.5, layout.scale * .035),
      cutRadius: math.max(3.0, layout.scale * .13),
    );
    mapped.add(zone);
    sources.add(source);
    childRects.add(childRect);
    nominalRects.add(nominalRect);
    effectivePaths.add(effectivePath);
    useEffectiveShapes.add(useEffectiveShape);
    areaIds.add(Set<String>.unmodifiable(effectiveAreaIds));
    stats.add(regionStats);
  }

  final hitRects = <Rect>[
    for (final nominalRect in nominalRects)
      parkingSpatialMinimumHitRect(
        nominalRect,
        layout.mapRect,
        minimum,
      ),
  ];

  for (var first = 0; first < hitRects.length; first++) {
    for (var second = first + 1; second < hitRects.length; second++) {
      if (!hitRects[first].overlaps(hitRects[second])) continue;
      if (nominalRects[first].overlaps(nominalRects[second])) continue;
      final separated = parkingSpatialSeparateHitRects(
        firstVisual: nominalRects[first],
        secondVisual: nominalRects[second],
        firstHit: hitRects[first],
        secondHit: hitRects[second],
      );
      hitRects[first] = separated.$1.intersect(layout.mapRect);
      hitRects[second] = separated.$2.intersect(layout.mapRect);
    }
  }

  return <ParkingSpatialChildRegion<T>>[
    for (var index = 0; index < mapped.length; index++)
      if (!hitRects[index].isEmpty &&
          hitRects[index].width > 0 &&
          hitRects[index].height > 0)
        ParkingSpatialChildRegion<T>(
          zone: mapped[index],
          source: sources[index],
          childRect: childRects[index],
          nominalRect: nominalRects[index],
          effectivePath: effectivePaths[index],
          hitRect: hitRects[index],
          useEffectiveShape: useEffectiveShapes[index],
          effectiveParkingAreaIds: areaIds[index],
          containedParkingAreaCount: stats[index].containedParkingAreaCount,
          ownedParkingAreaCount: stats[index].ownedParkingAreaCount,
          cutParkingAreaCount: stats[index].cutParkingAreaCount,
        ),
  ];
}
