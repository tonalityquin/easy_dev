import '../../features/location/domain/models/location_model.dart';
import '../parking_spatial/parking_spatial_hierarchy.dart';
import 'real_time_table_row_vm.dart';

const String kRealTimeLocationAll = '전체';
const String kRealTimeSegSep = ' - ';

class ZoneVM {
  final String fullName;
  final String group;
  final String displayName;
  final String child;
  final int capacity;
  final int current;
  final int? remaining;
  final List<RealTimeRowVM> rows;
  final LocationModel source;

  const ZoneVM({
    required this.fullName,
    required this.group,
    required this.displayName,
    required this.child,
    required this.capacity,
    required this.current,
    required this.remaining,
    required this.rows,
    required this.source,
  });
}

class ZoneGroupVM {
  final String group;
  final LocationModel? parentSource;
  final List<ZoneVM> zones;
  final int totalCapacity;
  final int totalCurrent;
  final int? totalRemaining;

  const ZoneGroupVM({
    required this.group,
    required this.parentSource,
    required this.zones,
    required this.totalCapacity,
    required this.totalCurrent,
    required this.totalRemaining,
  });
}

List<String> splitLocationSegments(String raw) {
  final v = raw.trim();
  if (v.isEmpty) return const <String>[];
  return v
      .split(kRealTimeSegSep)
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

String zoneKeyFromRowLocation(String raw) {
  final seg = splitLocationSegments(raw);
  if (seg.length < 2) return '';
  return '${seg[0]}$kRealTimeSegSep${seg[1]}';
}

String parentFromRowLocation(String raw) {
  final seg = splitLocationSegments(raw);
  if (seg.isEmpty) return '';
  return seg[0];
}

String childFromRowLocation(String raw) {
  final seg = splitLocationSegments(raw);
  if (seg.length < 2) return '';
  return seg[1];
}

String slotFromRowLocation(String raw) {
  final seg = splitLocationSegments(raw);
  if (seg.length < 3) return '';
  return seg.sublist(2).join(kRealTimeSegSep);
}

int? slotNumberFromRowLocation(String raw) {
  final slot = slotFromRowLocation(raw);
  if (slot.isEmpty) return null;
  final match = RegExp(r'\d+').firstMatch(slot);
  if (match == null) return null;
  return int.tryParse(match.group(0) ?? '');
}

int compareRowsByLocationSlot(RealTimeRowVM a, RealTimeRowVM b) {
  final aSlot = slotFromRowLocation(a.location);
  final bSlot = slotFromRowLocation(b.location);
  if (aSlot.isEmpty && bSlot.isNotEmpty) return 1;
  if (aSlot.isNotEmpty && bSlot.isEmpty) return -1;
  final slotCompare = naturalLocationCompare(aSlot, bSlot);
  if (slotCompare != 0) return slotCompare;
  final locationCompare = naturalLocationCompare(a.location, b.location);
  if (locationCompare != 0) return locationCompare;
  return naturalLocationCompare(a.plateNumber, b.plateNumber);
}

String childKeyFromLocation(LocationModel loc) {
  final t = (loc.type ?? 'single').trim();
  if (t != 'composite_child' && t != 'composite') return '';
  final parent = (loc.parent ?? '').trim();
  final child = loc.locationName.trim();
  if (parent.isEmpty || child.isEmpty) return '';
  return '$parent$kRealTimeSegSep$child';
}

Set<String> extractParentsFromMeta(List<LocationModel> meta) {
  final out = <String>{};
  for (final loc in meta) {
    final t = (loc.type ?? 'single').trim();
    if (t == 'composite_parent') {
      final p = loc.locationName.trim();
      if (p.isNotEmpty) out.add(p);
    } else if (t == 'composite_child' || t == 'composite') {
      final p = (loc.parent ?? '').trim();
      if (p.isNotEmpty) out.add(p);
    }
  }
  return out;
}

int capacityForChild(LocationModel childLoc) =>
    parkingSpatialCapacityForChild(childLoc);

int compositeChildTotalCapacity(List<LocationModel> meta) {
  var sum = 0;
  for (final loc in meta) {
    final t = (loc.type ?? 'single').trim();
    if (t == 'composite_child' || t == 'composite') {
      sum += capacityForChild(loc);
    }
  }
  return sum;
}

int naturalLocationCompare(String a, String b) =>
    parkingSpatialNaturalCompare(a, b);

List<ZoneGroupVM> buildZoneGroups({
  required List<RealTimeRowVM> rows,
  required List<LocationModel> meta,
  required String selected,
  required String search,
  Comparator<String>? parentComparator,
}) {
  final childKeyRows = <String, List<RealTimeRowVM>>{};

  for (final r in rows) {
    final ck = zoneKeyFromRowLocation(r.location);
    if (ck.isEmpty) continue;
    childKeyRows.putIfAbsent(ck, () => <RealTimeRowVM>[]).add(r);
  }

  final hierarchy = resolveParkingSpatialHierarchy(
    meta,
    parentComparator: parentComparator,
  );

  final selectedTrimmed = selected.trim();
  final searchTrimmed = search.trim().toLowerCase();

  final selectedIsChildKey = selectedTrimmed.contains(kRealTimeSegSep);

  String selectedParent = '';
  String selectedChildKey = '';

  if (selectedTrimmed.isNotEmpty && selectedTrimmed != kRealTimeLocationAll) {
    if (selectedIsChildKey) {
      selectedChildKey = selectedTrimmed;
      final seg = splitLocationSegments(selectedTrimmed);
      selectedParent = seg.isNotEmpty ? seg[0] : '';
    } else {
      selectedParent = selectedTrimmed;
    }
  }

  bool matchSearch(String parent, String childKey, String childName) {
    if (searchTrimmed.isEmpty) return true;
    final p = parent.toLowerCase();
    final ck = childKey.toLowerCase();
    final c = childName.toLowerCase();
    return p.contains(searchTrimmed) ||
        ck.contains(searchTrimmed) ||
        c.contains(searchTrimmed);
  }

  final out = <ZoneGroupVM>[];

  final compareParent = parentComparator ?? naturalLocationCompare;
  for (final spatialGroup in hierarchy) {
    final p = spatialGroup.parentName;
    if (selectedTrimmed != kRealTimeLocationAll &&
        !selectedIsChildKey &&
        selectedParent.isNotEmpty &&
        p != selectedParent) {
      continue;
    }
    if (selectedIsChildKey && selectedParent.isNotEmpty && p != selectedParent) {
      continue;
    }

    final children = spatialGroup.children;
    if (children.isEmpty) continue;

    final zoneVms = <ZoneVM>[];
    for (final childLoc in children) {
      final childKey = childKeyFromLocation(childLoc);
      if (childKey.isEmpty) continue;

      if (selectedIsChildKey &&
          selectedChildKey.isNotEmpty &&
          childKey != selectedChildKey) {
        continue;
      }

      final childName = childLoc.locationName.trim();

      final childRows = List<RealTimeRowVM>.of(
        childKeyRows[childKey] ?? const <RealTimeRowVM>[],
      )..sort(compareRowsByLocationSlot);
      final locationMatch = matchSearch(p, childKey, childName);
      final rowMatch = searchTrimmed.isEmpty || childRows.any((row) {
        return row.plateNumber.toLowerCase().contains(searchTrimmed) ||
            row.location.toLowerCase().contains(searchTrimmed);
      });
      if (!locationMatch && !rowMatch) continue;
      final cap = capacityForChild(childLoc);
      final cur = childRows.length;
      final rem = cap > 0 ? ((cap - cur) < 0 ? 0 : cap - cur) : null;

      zoneVms.add(
        ZoneVM(
          fullName: childKey,
          group: p,
          displayName: childName,
          child: childName,
          capacity: cap,
          current: cur,
          remaining: rem,
          rows: childRows,
          source: childLoc,
        ),
      );
    }

    if (zoneVms.isEmpty) continue;

    zoneVms.sort(
      (a, b) => naturalLocationCompare(a.displayName, b.displayName),
    );

    final totalCap = zoneVms.fold<int>(0, (s, z) => s + z.capacity);
    final totalCur = zoneVms.fold<int>(0, (s, z) => s + z.current);
    final totalRem = totalCap > 0
        ? ((totalCap - totalCur) < 0 ? 0 : totalCap - totalCur)
        : null;

    out.add(
      ZoneGroupVM(
        group: p,
        parentSource: spatialGroup.parentSource,
        zones: zoneVms,
        totalCapacity: totalCap,
        totalCurrent: totalCur,
        totalRemaining: totalRem,
      ),
    );
  }

  out.sort((a, b) => compareParent(a.group, b.group));
  return out;
}
