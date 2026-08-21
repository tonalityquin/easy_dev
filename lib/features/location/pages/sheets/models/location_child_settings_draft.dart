import '../../../domain/models/grid_rect.dart';
import '../../../domain/models/location_model.dart';
import '../../../domain/models/parking_grid_model.dart';

class LocationChildAllocationSnapshot {
  const LocationChildAllocationSnapshot({
    required this.childId,
    required this.childName,
    required this.rect,
    required this.ownedSlotAreaIds,
    required this.isTower,
  });

  final String childId;
  final String childName;
  final GridRect? rect;
  final Set<String> ownedSlotAreaIds;
  final bool isTower;
}

class LocationChildAllocationFeedback {
  const LocationChildAllocationFeedback({
    required this.candidateSlotAreaIds,
    required this.occupiedByOtherChildAreaIds,
    required this.reusableOverlapAreaIds,
    required this.userExcludedAreaIds,
    required this.effectiveSlotAreaIds,
  });

  final Set<String> candidateSlotAreaIds;
  final Set<String> occupiedByOtherChildAreaIds;
  final Set<String> reusableOverlapAreaIds;
  final Set<String> userExcludedAreaIds;
  final Set<String> effectiveSlotAreaIds;

  int get candidateCount => candidateSlotAreaIds.length;
  int get occupiedCount => occupiedByOtherChildAreaIds.length;
  int get reusableOverlapCount => reusableOverlapAreaIds.length;
  int get userExcludedCount => userExcludedAreaIds.length;
  int get effectiveCount => effectiveSlotAreaIds.length;
}

class LocationChildSettingsDraft {
  const LocationChildSettingsDraft({
    required this.name,
    required this.parentId,
    required this.parentName,
    required this.rect,
    required this.userExcludedSlotAreaIds,
    required this.slotNumbersByAreaId,
    required this.isTower,
    required this.towerCapacity,
  });

  final String name;
  final String parentId;
  final String parentName;
  final GridRect? rect;
  final Set<String> userExcludedSlotAreaIds;
  final Map<String, int> slotNumbersByAreaId;
  final bool isTower;
  final int towerCapacity;

  LocationChildSettingsDraft copyWith({
    String? name,
    String? parentId,
    String? parentName,
    GridRect? rect,
    bool clearRect = false,
    Set<String>? userExcludedSlotAreaIds,
    Map<String, int>? slotNumbersByAreaId,
    bool? isTower,
    int? towerCapacity,
  }) {
    return LocationChildSettingsDraft(
      name: name ?? this.name,
      parentId: parentId ?? this.parentId,
      parentName: parentName ?? this.parentName,
      rect: clearRect ? null : rect ?? this.rect,
      userExcludedSlotAreaIds:
          userExcludedSlotAreaIds ?? this.userExcludedSlotAreaIds,
      slotNumbersByAreaId: slotNumbersByAreaId ?? this.slotNumbersByAreaId,
      isTower: isTower ?? this.isTower,
      towerCapacity: towerCapacity ?? this.towerCapacity,
    );
  }

  LocationChildSettingsDraft detached() {
    return LocationChildSettingsDraft(
      name: name,
      parentId: parentId,
      parentName: parentName,
      rect: rect == null
          ? null
          : GridRect(
              r0: rect!.r0,
              c0: rect!.c0,
              r1: rect!.r1,
              c1: rect!.c1,
            ),
      userExcludedSlotAreaIds: Set<String>.from(userExcludedSlotAreaIds),
      slotNumbersByAreaId: Map<String, int>.from(slotNumbersByAreaId),
      isTower: isTower,
      towerCapacity: towerCapacity,
    );
  }

  LocationChildAllocationFeedback feedback({
    required ParkingGridModel parentGrid,
    required List<LocationChildAllocationSnapshot> siblings,
  }) {
    if (isTower || rect == null) {
      return const LocationChildAllocationFeedback(
        candidateSlotAreaIds: <String>{},
        occupiedByOtherChildAreaIds: <String>{},
        reusableOverlapAreaIds: <String>{},
        userExcludedAreaIds: <String>{},
        effectiveSlotAreaIds: <String>{},
      );
    }

    final normalized = rect!.normalized();
    final candidate = <String>{};
    final byId = <String, ParkingArea>{};
    for (final area in parentGrid.parkingAreas) {
      final id = area.id.trim();
      if (id.isEmpty) continue;
      byId[id] = area;
      if (_parkingAreaFullyContainedInRect(area, normalized)) {
        candidate.add(id);
      }
    }

    final occupied = <String>{};
    for (final sibling in siblings) {
      occupied.addAll(sibling.ownedSlotAreaIds.where(candidate.contains));
    }

    final reusable = <String>{};
    for (final sibling in siblings) {
      if (sibling.isTower) continue;
      final siblingRect = sibling.rect?.normalized();
      if (siblingRect == null) continue;
      for (final id in candidate) {
        if (occupied.contains(id) || sibling.ownedSlotAreaIds.contains(id)) {
          continue;
        }
        final area = byId[id];
        if (area == null) continue;
        if (_parkingAreaFullyContainedInRect(area, siblingRect)) {
          reusable.add(id);
        }
      }
    }

    final excluded = userExcludedSlotAreaIds
        .where(candidate.contains)
        .where((id) => !occupied.contains(id))
        .toSet();
    final effective = candidate
        .where((id) => !occupied.contains(id) && !excluded.contains(id))
        .toSet();

    return LocationChildAllocationFeedback(
      candidateSlotAreaIds: Set<String>.unmodifiable(candidate),
      occupiedByOtherChildAreaIds: Set<String>.unmodifiable(occupied),
      reusableOverlapAreaIds: Set<String>.unmodifiable(reusable),
      userExcludedAreaIds: Set<String>.unmodifiable(excluded),
      effectiveSlotAreaIds: Set<String>.unmodifiable(effective),
    );
  }

  LocationChildSettingsDraft reconciled({
    required ParkingGridModel parentGrid,
    required List<LocationChildAllocationSnapshot> siblings,
  }) {
    final current = feedback(parentGrid: parentGrid, siblings: siblings);
    final nextNumbers = <String, int>{};
    for (final entry in slotNumbersByAreaId.entries) {
      if (!current.effectiveSlotAreaIds.contains(entry.key)) continue;
      if (entry.value <= 0) continue;
      nextNumbers[entry.key] = entry.value;
    }
    return copyWith(
      userExcludedSlotAreaIds: current.userExcludedAreaIds,
      slotNumbersByAreaId: nextNumbers,
    );
  }

  List<ChildSlot> numberedSlots({
    required ParkingGridModel parentGrid,
    required List<LocationChildAllocationSnapshot> siblings,
  }) {
    final current = feedback(parentGrid: parentGrid, siblings: siblings);
    final byId = <String, ParkingArea>{
      for (final area in parentGrid.parkingAreas) area.id.trim(): area,
    };
    final out = <ChildSlot>[];
    for (final id in current.effectiveSlotAreaIds) {
      final area = byId[id];
      final number = slotNumbersByAreaId[id];
      if (area == null || number == null || number <= 0) continue;
      out.add(ChildSlot.fromParkingArea(no: number, area: area));
    }
    out.sort((a, b) => a.no.compareTo(b.no));
    return out;
  }

  static bool _parkingAreaFullyContainedInRect(
    ParkingArea area,
    GridRect rect,
  ) {
    final normalized = rect.normalized();
    return area.r0 >= normalized.r0 &&
        area.r1 <= normalized.r1 &&
        area.c0 >= normalized.c0 &&
        area.c1 <= normalized.c1;
  }
}
