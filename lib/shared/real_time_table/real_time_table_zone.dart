import '../../../features/location/domain/models/location_model.dart';
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

  const ZoneVM({
    required this.fullName,
    required this.group,
    required this.displayName,
    required this.child,
    required this.capacity,
    required this.current,
    required this.remaining,
    required this.rows,
  });
}

class ZoneGroupVM {
  final String group;
  final List<ZoneVM> zones;
  final int totalCapacity;
  final int totalCurrent;
  final int? totalRemaining;

  const ZoneGroupVM({
    required this.group,
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

int capacityForChild(LocationModel childLoc) {
  if (childLoc.childSlots.isNotEmpty) return childLoc.childSlots.length;
  return childLoc.capacity;
}

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

int _naturalCompareToken(String a, String b) {
  final ai = int.tryParse(a);
  final bi = int.tryParse(b);

  if (ai != null && bi != null) {
    final c = ai.compareTo(bi);
    if (c != 0) return c;
    return a.length.compareTo(b.length);
  }

  final al = a.toLowerCase();
  final bl = b.toLowerCase();
  final ci = al.compareTo(bl);
  if (ci != 0) return ci;
  return a.compareTo(b);
}

List<String> _naturalTokens(String value) {
  final out = <String>[];
  final buffer = StringBuffer();
  bool? numeric;

  for (var i = 0; i < value.length; i++) {
    final ch = value[i];
    final isDigit = RegExp(r'\d').hasMatch(ch);

    if (numeric == null || numeric == isDigit) {
      buffer.write(ch);
      numeric = isDigit;
      continue;
    }

    out.add(buffer.toString());
    buffer
      ..clear()
      ..write(ch);
    numeric = isDigit;
  }

  if (buffer.isNotEmpty) out.add(buffer.toString());
  return out;
}

int naturalLocationCompare(String a, String b) {
  final at = _naturalTokens(a.trim());
  final bt = _naturalTokens(b.trim());
  final n = at.length < bt.length ? at.length : bt.length;

  for (var i = 0; i < n; i++) {
    final c = _naturalCompareToken(at[i], bt[i]);
    if (c != 0) return c;
  }

  return at.length.compareTo(bt.length);
}

List<String> normalizedLocationFilterOptions(List<String> plateLocations) {
  final parents = <String>{};
  final children = <String>{};

  for (final raw in plateLocations) {
    final seg = splitLocationSegments(raw);
    if (seg.isEmpty) continue;

    parents.add(seg[0]);

    if (seg.length >= 2) {
      children.add('${seg[0]}$kRealTimeSegSep${seg[1]}');
    }
  }

  final parentList = parents.toList()..sort(naturalLocationCompare);
  final childList = children.toList()..sort(naturalLocationCompare);
  return <String>[...parentList, ...childList];
}

List<String> locationFilterOptions({
  required List<LocationModel> meta,
  required List<String> plateLocations,
}) {
  final fromRows = normalizedLocationFilterOptions(plateLocations);
  if (fromRows.isNotEmpty) return fromRows;

  if (meta.isEmpty) return const <String>[];

  final parents = extractParentsFromMeta(meta).toList()
    ..sort(naturalLocationCompare);

  final children = <String>{};
  for (final loc in meta) {
    final k = childKeyFromLocation(loc);
    if (k.isNotEmpty) children.add(k);
  }

  final childList = children.toList()..sort(naturalLocationCompare);
  return <String>[...parents, ...childList];
}

List<ZoneGroupVM> buildZoneGroups({
  required List<RealTimeRowVM> rows,
  required List<LocationModel> meta,
  required String selected,
  required String search,
}) {
  final childKeyRows = <String, List<RealTimeRowVM>>{};

  for (final r in rows) {
    final ck = zoneKeyFromRowLocation(r.location);
    if (ck.isEmpty) continue;
    childKeyRows.putIfAbsent(ck, () => <RealTimeRowVM>[]).add(r);
  }

  final childrenByParent = <String, List<LocationModel>>{};
  final parents = extractParentsFromMeta(meta);

  for (final loc in meta) {
    final t = (loc.type ?? 'single').trim();
    if (t != 'composite_child' && t != 'composite') continue;

    final parent = (loc.parent ?? '').trim();
    final child = loc.locationName.trim();
    if (parent.isEmpty || child.isEmpty) continue;

    parents.add(parent);
    childrenByParent.putIfAbsent(parent, () => <LocationModel>[]).add(loc);
  }

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

  final parentList = parents.toList()..sort(naturalLocationCompare);
  for (final p in parentList) {
    if (selectedTrimmed != kRealTimeLocationAll &&
        !selectedIsChildKey &&
        selectedParent.isNotEmpty &&
        p != selectedParent) {
      continue;
    }
    if (selectedIsChildKey && selectedParent.isNotEmpty && p != selectedParent) {
      continue;
    }

    final children = List<LocationModel>.of(childrenByParent[p] ?? const <LocationModel>[])
      ..sort((a, b) => naturalLocationCompare(a.locationName, b.locationName));
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
      if (!matchSearch(p, childKey, childName)) continue;

      final childRows = List<RealTimeRowVM>.unmodifiable(
        childKeyRows[childKey] ?? const <RealTimeRowVM>[],
      );
      final cap = capacityForChild(childLoc);
      final cur = childRows.length;
      final rem = cap > 0 ? (cap - cur) : null;

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
        ),
      );
    }

    if (zoneVms.isEmpty) continue;

    zoneVms.sort(
      (a, b) => naturalLocationCompare(a.displayName, b.displayName),
    );

    final totalCap = zoneVms.fold<int>(0, (s, z) => s + z.capacity);
    final totalCur = zoneVms.fold<int>(0, (s, z) => s + z.current);
    final totalRem = totalCap > 0 ? (totalCap - totalCur) : null;

    out.add(
      ZoneGroupVM(
        group: p,
        zones: zoneVms,
        totalCapacity: totalCap,
        totalCurrent: totalCur,
        totalRemaining: totalRem,
      ),
    );
  }

  out.sort((a, b) => naturalLocationCompare(a.group, b.group));
  return out;
}
