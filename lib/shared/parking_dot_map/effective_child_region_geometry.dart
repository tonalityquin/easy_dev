import 'package:flutter/material.dart';

import '../../features/location/domain/models/grid_rect.dart';
import '../../features/location/domain/models/location_model.dart';
import '../../features/location/domain/models/parking_grid_model.dart';

class EffectiveChildRegionStats {
  const EffectiveChildRegionStats({
    required this.containedParkingAreaCount,
    required this.ownedParkingAreaCount,
    required this.cutParkingAreaCount,
  });

  final int containedParkingAreaCount;
  final int ownedParkingAreaCount;
  final int cutParkingAreaCount;
}

Set<String> resolvedChildParkingAreaIds(LocationModel location) {
  final ids = <String>{};
  for (final raw in location.childSlotAreaIds) {
    final id = raw.trim();
    if (id.isNotEmpty) ids.add(id);
  }
  if (ids.isNotEmpty) return ids;
  for (final slot in location.childSlots) {
    final id = slot.areaId.trim();
    if (id.isNotEmpty) ids.add(id);
  }
  return ids;
}

bool parkingAreaContainedInGridRect(ParkingArea area, GridRect rect) {
  final normalized = rect.normalized();
  return area.r0 >= normalized.r0 &&
      area.r1 <= normalized.r1 &&
      area.c0 >= normalized.c0 &&
      area.c1 <= normalized.c1;
}

EffectiveChildRegionStats effectiveChildRegionStats({
  required ParkingGridModel grid,
  required GridRect childRect,
  required Set<String> effectiveParkingAreaIds,
}) {
  var contained = 0;
  var owned = 0;
  for (final area in grid.parkingAreas) {
    if (!parkingAreaContainedInGridRect(area, childRect)) continue;
    contained++;
    final id = area.id.trim();
    if (id.isNotEmpty && effectiveParkingAreaIds.contains(id)) {
      owned++;
    }
  }
  return EffectiveChildRegionStats(
    containedParkingAreaCount: contained,
    ownedParkingAreaCount: owned,
    cutParkingAreaCount: contained - owned,
  );
}

Path buildEffectiveChildRegionPath({
  required ParkingGridModel grid,
  required GridRect childRect,
  required Set<String> effectiveParkingAreaIds,
  required RRect nominalRegion,
  required Rect Function(ParkingArea area) parkingAreaRect,
  bool useEffectiveShape = true,
  double cutInflate = 0,
  double cutRadius = 0,
}) {
  var path = Path()..addRRect(nominalRegion);
  if (!useEffectiveShape) return path;
  for (final area in grid.parkingAreas) {
    final id = area.id.trim();
    if (id.isEmpty ||
        effectiveParkingAreaIds.contains(id) ||
        !parkingAreaContainedInGridRect(area, childRect)) {
      continue;
    }
    final rawCutRect = parkingAreaRect(area);
    if (rawCutRect.isEmpty) continue;
    final cutRect = cutInflate > 0 ? rawCutRect.inflate(cutInflate) : rawCutRect;
    final cutPath = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          cutRect,
          Radius.circular(cutRadius.clamp(0.0, double.infinity).toDouble()),
        ),
      );
    path = Path.combine(PathOperation.difference, path, cutPath);
  }
  return path;
}
