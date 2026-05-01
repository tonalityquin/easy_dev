import 'dart:convert';
import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../../../location/domain/models/grid_rect.dart';
import '../../../../location/domain/models/location_model.dart';
import '../../../../location/domain/models/parking_grid_model.dart';
import 'tablet_grid_2d_view_picker_dialog.dart';

part 'tablet_grid_2d_preview_text.dart';

part 'tablet_grid_2d_preview_structured.dart';

enum ParkingSlotStatus { empty, parkingRequest, parked, departureRequest }

enum _PreviewEntryKind { structured, text }

int _slotStatusPriority(ParkingSlotStatus s) {
  switch (s) {
    case ParkingSlotStatus.departureRequest:
      return 3;
    case ParkingSlotStatus.parkingRequest:
      return 2;
    case ParkingSlotStatus.parked:
      return 1;
    case ParkingSlotStatus.empty:
      return 0;
  }
}

ParkingSlotStatus _mergeSlotStatus(ParkingSlotStatus a, ParkingSlotStatus b) {
  return _slotStatusPriority(b) > _slotStatusPriority(a) ? b : a;
}

@immutable
class TextParkingPreviewMetrics {
  final int parkingCompletedCount;
  final int departureRequestCount;

  const TextParkingPreviewMetrics({
    this.parkingCompletedCount = 0,
    this.departureRequestCount = 0,
  });

  TextParkingPreviewMetrics copyWith({
    int? parkingCompletedCount,
    int? departureRequestCount,
  }) {
    return TextParkingPreviewMetrics(
      parkingCompletedCount:
      parkingCompletedCount ?? this.parkingCompletedCount,
      departureRequestCount:
      departureRequestCount ?? this.departureRequestCount,
    );
  }
}

@immutable
class ParkingGridOverlay {
  final Map<String, ParkingSlotStatus> slotStatusByKey;
  final Map<String, ParkingSlotStatus> groupStatusByKey;

  const ParkingGridOverlay({
    required this.slotStatusByKey,
    required this.groupStatusByKey,
  });

  const ParkingGridOverlay.empty()
      : slotStatusByKey = const <String, ParkingSlotStatus>{},
        groupStatusByKey = const <String, ParkingSlotStatus>{};

  bool get isEmpty => slotStatusByKey.isEmpty && groupStatusByKey.isEmpty;

  ParkingGridOverlay forParent(String parentName) {
    final pk = _nameKey(parentName);
    if (pk.isEmpty || isEmpty) return const ParkingGridOverlay.empty();

    final slotOut = <String, ParkingSlotStatus>{};
    final groupOut = <String, ParkingSlotStatus>{};

    for (final e in slotStatusByKey.entries) {
      final parts = e.key.split('|');
      if (parts.length < 3) continue;
      if (parts[0] != pk) continue;

      final childKey = parts[1];
      final no = parts[2];

      final k = '$childKey|$no';
      final prev = slotOut[k] ?? ParkingSlotStatus.empty;
      slotOut[k] = _mergeSlotStatus(prev, e.value);
    }

    for (final e in groupStatusByKey.entries) {
      final parts = e.key.split('|');
      if (parts.length < 2) continue;
      if (parts[0] != pk) continue;

      final childKey = parts[1];
      final prev = groupOut[childKey] ?? ParkingSlotStatus.empty;
      groupOut[childKey] = _mergeSlotStatus(prev, e.value);
    }

    return ParkingGridOverlay(
      slotStatusByKey: slotOut,
      groupStatusByKey: groupOut,
    );
  }

  ParkingSlotStatus statusForSlot({
    required String childName,
    int? no,
  }) {
    final ck = _nameKey(childName);
    if (ck.isEmpty) return ParkingSlotStatus.empty;

    if (no != null) {
      final sk = '$ck|$no';
      final s = slotStatusByKey[sk];
      if (s != null) return s;
    }
    return groupStatusByKey[ck] ?? ParkingSlotStatus.empty;
  }

  bool isFromGroupOnly({
    required String childName,
    int? no,
  }) {
    final ck = _nameKey(childName);
    if (ck.isEmpty) return false;
    if (no == null) return true;

    final sk = '$ck|$no';
    if (slotStatusByKey.containsKey(sk)) return false;
    return groupStatusByKey.containsKey(ck);
  }

  ParkingSlotStatus statusForChildAny({required String childName}) {
    final ck = _nameKey(childName);
    if (ck.isEmpty) return ParkingSlotStatus.empty;

    ParkingSlotStatus best = groupStatusByKey[ck] ?? ParkingSlotStatus.empty;
    final prefix = '$ck|';
    for (final e in slotStatusByKey.entries) {
      if (e.key.startsWith(prefix)) {
        best = _mergeSlotStatus(best, e.value);
      }
    }
    return best;
  }

  bool hasAnyForChild({required String childName}) {
    final ck = _nameKey(childName);
    if (ck.isEmpty) return false;
    if (groupStatusByKey.containsKey(ck)) return true;
    final prefix = '$ck|';
    for (final k in slotStatusByKey.keys) {
      if (k.startsWith(prefix)) return true;
    }
    return false;
  }
}

@immutable
class _PreviewEntry {
  final _PreviewEntryKind kind;
  final LocationModel location;
  final String title;
  final String subtitle;

  const _PreviewEntry({
    required this.kind,
    required this.location,
    required this.title,
    required this.subtitle,
  });

  bool get isStructured => kind == _PreviewEntryKind.structured;

  bool get isText => kind == _PreviewEntryKind.text;
}

int? _asInt(Object? v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString().trim());
}

double? _asDouble(Object? v) {
  if (v == null) return null;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString().trim());
}

String _trimOrEmpty(Object? v) => (v ?? '').toString().trim();

String _normalizeName(String raw) => raw.trim().replaceAll(RegExp(r'\s+'), ' ');

String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

const String kParkingOverlayTowerChildKey = 'tower';

String parkingOverlayCanonicalChildKey(String raw) {
  final nk = _nameKey(raw);
  if (nk.isEmpty) return '';
  final packed = nk.replaceAll(RegExp(r'[_\-\s]'), '');

  if (packed == 'tower' || packed == 'parkingtower' || packed == 'parktower') {
    return kParkingOverlayTowerChildKey;
  }

  if (packed == '주차타워' || packed == '주차탑') {
    return kParkingOverlayTowerChildKey;
  }

  final rawLower = raw.toLowerCase();
  if (packed == '타워' && (raw.contains('주차') || rawLower.contains('parking'))) {
    return kParkingOverlayTowerChildKey;
  }

  return nk;
}

bool _isCompositeParentType(String? t) {
  final x = (t ?? '').trim().toLowerCase();
  return x == 'composite_parent' ||
      x.replaceAll(RegExp(r'[_\-\s]'), '') == 'compositeparent';
}

bool _isCompositeChildType(String? t) {
  final x = (t ?? '').trim().toLowerCase();
  if (x == 'composite_child' || x == 'composite') return true;
  final packed = x.replaceAll(RegExp(r'[_\-\s]'), '');
  return packed == 'compositechild' || packed == 'composite';
}

bool _isPlainTextType(String? t) {
  final x = (t ?? '').trim().toLowerCase();
  if (x.isEmpty) return false;
  if (_isCompositeParentType(t) || _isCompositeChildType(t)) return false;
  final packed = x.replaceAll(RegExp(r'[_\-\s]'), '');
  return packed == 'plaintext' ||
      packed == 'plainlocation' ||
      packed == 'text' ||
      packed == 'textonly' ||
      packed == 'textlocation' ||
      packed == 'single' ||
      packed == 'singlelocation' ||
      packed == 'simple' ||
      packed == 'simplelocation';
}

bool _isSelectedLoose(LocationModel l) {
  try {
    return l.isSelected;
  } catch (_) {
    return false;
  }
}

Map<String, Object?> _locationLooseMap(LocationModel l) {
  final out = <String, Object?>{};
  final loose = _toLooseMap(l);
  if (loose != null) out.addAll(loose);
  return out;
}

Object? _locationLooseValue(LocationModel l, List<String> keys) {
  final m = _locationLooseMap(l);
  for (final key in keys) {
    if (m.containsKey(key)) return m[key];
    final lower = key.trim().toLowerCase();
    for (final e in m.entries) {
      if (e.key.trim().toLowerCase() == lower) return e.value;
    }
  }
  return null;
}

String _locationLooseText(LocationModel l, List<String> keys) {
  return _trimOrEmpty(_locationLooseValue(l, keys));
}

int? _locationLooseInt(LocationModel l, List<String> keys) {
  return _asInt(_locationLooseValue(l, keys));
}

bool _isTextPreviewCandidate(LocationModel l) {
  if (_isCompositeParentType(l.type) || _isCompositeChildType(l.type)) {
    return false;
  }
  if (_isPlainTextType(l.type)) return true;
  if (l.parkingGrid != null) return false;
  if (_readChildRectFallback(l) != null) return false;
  final parentRef = _trimOrEmpty(
    _locationLooseValue(l, ['parent', 'parentName', 'parentId', 'parentKey']),
  );
  if (parentRef.isNotEmpty) return false;
  return _trimOrEmpty(l.locationName).isNotEmpty;
}

List<String> parkingPreviewLocationAliases(String raw) {
  final normalized = _normalizeName(raw);
  if (normalized.isEmpty) return const <String>[];

  final parts = normalized
      .split(' - ')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);

  final out = <String>[];

  void addAlias(String value) {
    final key = _nameKey(value);
    if (key.isEmpty || out.contains(key)) return;
    out.add(key);
  }

  addAlias(normalized);
  if (parts.length >= 2) {
    addAlias(parts.sublist(parts.length - 2).join(' - '));
  }
  if (parts.isNotEmpty) {
    addAlias(parts.last);
  }

  return out;
}

TextParkingPreviewMetrics? resolveTextParkingPreviewMetrics({
  required LocationModel location,
  required Map<String, TextParkingPreviewMetrics> metricsByLocation,
}) {
  if (metricsByLocation.isEmpty) return null;
  for (final alias in parkingPreviewLocationAliases(location.locationName)) {
    final metrics = metricsByLocation[alias];
    if (metrics != null) return metrics;
  }
  return null;
}

Map<String, TextParkingPreviewMetrics>
buildTextParkingPreviewMetricsByLocations({
  required List<LocationModel> locations,
  Iterable<String> parkingCompletedLocations = const <String>[],
  Iterable<String> departureRequestLocations = const <String>[],
}) {
  final aliasToCanonicals = <String, Set<String>>{};
  final result = <String, TextParkingPreviewMetrics>{};

  void registerAlias(String alias, String canonical) {
    if (alias.isEmpty || canonical.isEmpty) return;
    aliasToCanonicals.putIfAbsent(alias, () => <String>{}).add(canonical);
  }

  for (final location in locations) {
    if (!_isTextPreviewCandidate(location)) continue;
    final aliases = parkingPreviewLocationAliases(location.locationName);
    if (aliases.isEmpty) continue;

    final canonical = aliases.first;
    result.putIfAbsent(canonical, () => const TextParkingPreviewMetrics());
    for (final alias in aliases) {
      registerAlias(alias, canonical);
    }
  }

  if (result.isEmpty) return result;

  String? resolveCanonical(String raw) {
    for (final alias in parkingPreviewLocationAliases(raw)) {
      final canonicals = aliasToCanonicals[alias];
      if (canonicals == null || canonicals.isEmpty) continue;
      if (canonicals.length == 1) return canonicals.first;
    }
    return null;
  }

  void accumulate(
      Iterable<String> rawLocations, {
        required bool isDepartureRequest,
      }) {
    for (final raw in rawLocations) {
      final canonical = resolveCanonical(raw);
      if (canonical == null) continue;
      final current = result[canonical] ?? const TextParkingPreviewMetrics();
      result[canonical] = isDepartureRequest
          ? current.copyWith(
        departureRequestCount: current.departureRequestCount + 1,
      )
          : current.copyWith(
        parkingCompletedCount: current.parkingCompletedCount + 1,
      );
    }
  }

  accumulate(parkingCompletedLocations, isDepartureRequest: false);
  accumulate(departureRequestLocations, isDepartureRequest: true);

  return result;
}

String _plainTypeLabelFromLocation(LocationModel l) {
  final t = _trimOrEmpty(l.type);
  final packed = t.toLowerCase().replaceAll(RegExp(r'[_\-\s]'), '');
  if (packed == 'plaintext' ||
      packed == 'plainlocation' ||
      packed == 'text' ||
      packed == 'textonly' ||
      packed == 'textlocation') {
    return '텍스트형';
  }
  if (packed == 'single' || packed == 'singlelocation' || packed == 'simple') {
    return '단일형';
  }
  return '텍스트형';
}

String _previewSubtitleForLocation(LocationModel l, _PreviewEntryKind kind) {
  final area = _trimOrEmpty(() {
    try {
      return (l as dynamic).area;
    } catch (_) {
      return _locationLooseText(l, ['area', 'zone', 'section']);
    }
  }());
  final parent =
  _locationLooseText(l, ['parentDisplayName', 'parentName', 'parent']);
  final cap = _locationLooseInt(l, [
    'capacity',
    'carLimit',
    'vehicleLimit',
    'maxCars',
    'maxCount',
    'parkingLimit',
  ]);

  final parts = <String>[];
  if (kind == _PreviewEntryKind.structured) {
    parts.add('구조형 레이아웃');
  } else {
    parts.add(_plainTypeLabelFromLocation(l));
  }
  if (area.isNotEmpty) parts.add(area);
  if (parent.isNotEmpty) parts.add('상위 $parent');
  if (cap != null && cap > 0) parts.add('${cap}대');
  return parts.join(' · ');
}

String _edgeKeyToString(Object? k) {
  if (k == null) return '';
  if (k is String) return k.trim();
  try {
    final d = k as dynamic;
    final v = d.toKey();
    if (v is String) return v.trim();
  } catch (_) {}
  return k.toString().trim();
}

Map<String, Object?>? _toLooseMap(Object? it) {
  if (it == null) return null;

  if (it is Map) {
    return it.map((k, v) => MapEntry(k.toString(), v));
  }

  try {
    final d = it as dynamic;
    final tj = d.toJson();
    if (tj is Map) {
      return tj.map((k, v) => MapEntry(k.toString(), v));
    }
  } catch (_) {}

  return null;
}

(int spanR, int spanC)? _parseSpanString(Object? v) {
  if (v == null) return null;
  final s = v.toString().trim();
  if (s.isEmpty) return null;
  final m = RegExp(r'^\s*(\d+)\s*([xX\*])\s*(\d+)\s*$').firstMatch(s);
  if (m == null) return null;
  final a = int.tryParse(m.group(1) ?? '');
  final b = int.tryParse(m.group(3) ?? '');
  if (a == null || b == null) return null;
  return (a, b);
}

(int spanR, int spanC) _normalizeSpan(int? spanR, int? spanC) {
  final sr = (spanR ?? 1).clamp(1, 2);
  final sc = (spanC ?? 1).clamp(1, 2);
  return (sr, sc);
}

String _slotToken(Object? value) {
  return _trimOrEmpty(value)
      .toLowerCase()
      .replaceAll('×', 'x')
      .replaceAll('*', 'x')
      .replaceAll(RegExp(r'\s+'), '');
}

(int spanR, int spanC)? _spanFromKind(Object? kindLike) {
  final s = _slotToken(kindLike);
  if (s.isEmpty) return null;

  final parsed = _parseSpanString(s);
  if (parsed != null) return parsed;

  if (s.contains('2x2')) return (2, 2);
  if (s.contains('2x1')) return (2, 1);
  if (s.contains('1x2')) return (1, 2);
  if (s.contains('h1')) return (1, 2);
  if (s.contains('v2')) return (2, 1);

  return null;
}

String _slotCategoryShort({
  required String kind,
  required String label,
  required String category,
  required String categoryLabel,
}) {
  final k = _slotToken(kind);
  final l = _slotToken(label);
  final c = _slotToken(category);
  final cl = _slotToken(categoryLabel);

  bool hasAny(String token) =>
      k.contains(token) || l.contains(token) || c.contains(token) || cl.contains(token);

  if (hasAny('extendedb') ||
      hasAny('확장형b') ||
      hasAny('확장b')) {
    return '확B';
  }
  if (hasAny('extendeda') ||
      hasAny('확장형a') ||
      hasAny('확장a')) {
    return '확A';
  }
  if (hasAny('compact') || hasAny('경형') || hasAny('경차')) {
    return '경';
  }
  if (hasAny('standard') || hasAny('일반형') || hasAny('일반')) {
    return '일';
  }
  return '';
}

class _Unset {
  const _Unset();
}

const _unset = _Unset();

class _ChildSlot {
  final String groupName;
  final int r0;
  final int c0;
  final int r1;
  final int c1;
  final String kind;
  final String label;
  final String category;
  final String categoryLabel;
  final String footprint;
  final double? minWidthMeters;
  final double? minLengthMeters;
  final String? areaId;
  final int? no;
  final ParkingSlotStatus status;
  final bool statusFromGroup;

  const _ChildSlot({
    required this.groupName,
    required this.r0,
    required this.c0,
    required this.r1,
    required this.c1,
    required this.kind,
    this.label = '',
    this.category = '',
    this.categoryLabel = '',
    this.footprint = '',
    this.minWidthMeters,
    this.minLengthMeters,
    this.areaId,
    this.no,
    this.status = ParkingSlotStatus.empty,
    this.statusFromGroup = false,
  });

  _ChildSlot copyWith({
    String? groupName,
    Object? no = _unset,
    ParkingSlotStatus? status,
    bool? statusFromGroup,
  }) {
    final nextNo = identical(no, _unset) ? this.no : (no as int?);
    return _ChildSlot(
      groupName: groupName ?? this.groupName,
      r0: r0,
      c0: c0,
      r1: r1,
      c1: c1,
      kind: kind,
      label: label,
      category: category,
      categoryLabel: categoryLabel,
      footprint: footprint,
      minWidthMeters: minWidthMeters,
      minLengthMeters: minLengthMeters,
      areaId: areaId,
      no: nextNo,
      status: status ?? this.status,
      statusFromGroup: statusFromGroup ?? this.statusFromGroup,
    );
  }

  int get rr0 => min(r0, r1);

  int get rr1 => max(r0, r1);

  int get cc0 => min(c0, c1);

  int get cc1 => max(c0, c1);

  int get r => rr0;

  int get c => cc0;

  int get spanR => (rr1 - rr0 + 1).abs();

  int get spanC => (cc1 - cc0 + 1).abs();

  String get kindNorm {
    final span = _spanFromKind(kind) ??
        _spanFromKind(label) ??
        _spanFromKind(footprint) ??
        _spanFromKind(categoryLabel);
    if (span != null) {
      if (span.$1 == 2 && span.$2 == 2) return '2x2';
      if (span.$1 == 2 && span.$2 == 1) return 'v2x1';
      if (span.$1 == 1 && span.$2 == 2) return 'h1x2';
    }
    if (spanR == 1 && spanC == 2) return 'h1x2';
    if (spanR == 2 && spanC == 1) return 'v2x1';
    if (spanR == 2 && spanC == 2) return '2x2';
    return 'unknown';
  }

  String get shortKindLabel {
    return _slotCategoryShort(
      kind: kind,
      label: label,
      category: category,
      categoryLabel: categoryLabel,
    );
  }

  String get badgeLabel {
    final n = no != null && no! > 0 ? no.toString() : '';
    return n;
  }

  (int sr, int sc) get normalizedSpan {
    int sr = spanR.clamp(1, 2);
    int sc = spanC.clamp(1, 2);

    final kn = kindNorm;
    if (kn == 'h1x2') return (1, 2);
    if (kn == 'v2x1') return (2, 1);
    if (kn == '2x2') return (2, 2);
    return (sr, sc);
  }

  double get centerR => (rr0 + rr1) * 0.5;

  double get centerC => (cc0 + cc1) * 0.5;
}

class _ChildRegion {
  final String name;
  final int r0;
  final int c0;
  final int r1;
  final int c1;
  final ParkingSlotStatus status;
  final bool statusFromGroup;

  const _ChildRegion({
    required this.name,
    required this.r0,
    required this.c0,
    required this.r1,
    required this.c1,
    this.status = ParkingSlotStatus.empty,
    this.statusFromGroup = false,
  });

  _ChildRegion copyWith({
    ParkingSlotStatus? status,
    bool? statusFromGroup,
  }) {
    return _ChildRegion(
      name: name,
      r0: r0,
      c0: c0,
      r1: r1,
      c1: c1,
      status: status ?? this.status,
      statusFromGroup: statusFromGroup ?? this.statusFromGroup,
    );
  }

  int get rr0 => min(r0, r1);

  int get rr1 => max(r0, r1);

  int get cc0 => min(c0, c1);

  int get cc1 => max(c0, c1);

  int get areaCells => (rr1 - rr0 + 1).abs() * (cc1 - cc0 + 1).abs();

  bool containsPoint(double r, double c) {
    return r >= rr0 && r <= rr1 && c >= cc0 && c <= cc1;
  }
}

(int r0, int c0, int r1, int c1)? _readChildRectFallback(LocationModel l) {
  dynamic cr;
  try {
    cr = (l as dynamic).childRect;
  } catch (_) {
    cr = null;
  }
  if (cr == null) return null;

  int? r0, c0, r1, c1;

  if (cr is List && cr.length >= 4) {
    r0 = _asInt(cr[0]);
    c0 = _asInt(cr[1]);
    r1 = _asInt(cr[2]);
    c1 = _asInt(cr[3]);
  } else if (cr is Map) {
    r0 = _asInt(cr['r0'] ?? cr['top'] ?? cr['row0'] ?? cr['minR']);
    c0 = _asInt(cr['c0'] ?? cr['left'] ?? cr['col0'] ?? cr['minC']);
    r1 = _asInt(cr['r1'] ?? cr['bottom'] ?? cr['row1'] ?? cr['maxR']);
    c1 = _asInt(cr['c1'] ?? cr['right'] ?? cr['maxC']);
  } else {
    try {
      final d = cr as dynamic;
      r0 = _asInt(d.r0);
      c0 = _asInt(d.c0);
      r1 = _asInt(d.r1);
      c1 = _asInt(d.c1);
    } catch (_) {
      return null;
    }
  }

  if (r0 == null || c0 == null || r1 == null || c1 == null) return null;
  return (r0, c0, r1, c1);
}

dynamic _extractChildSlotsRawFromLocation(LocationModel l) {
  dynamic raw;

  for (final getter in <dynamic Function()>[
        () => (l as dynamic).childSlots,
        () => (l as dynamic).childSlot,
        () => (l as dynamic).slots,
        () => (l as dynamic).children,
  ]) {
    try {
      raw = getter();
      if (raw != null) break;
    } catch (_) {}
  }

  if (raw != null) return raw;

  try {
    final pg = (l as dynamic).parkingGrid;
    if (pg != null) {
      try {
        raw = (pg as dynamic).childSlots;
      } catch (_) {}
      raw ??= (() {
        try {
          return (pg as dynamic).parkingAreas;
        } catch (_) {
          return null;
        }
      })();
    }
  } catch (_) {}

  if (raw != null) return raw;

  try {
    raw = (l as dynamic).parkingAreas;
  } catch (_) {}

  return raw;
}

dynamic _extractParkingAreasRawFromGrid(ParkingGridModel pg) {
  try {
    return (pg as dynamic).parkingAreas;
  } catch (_) {
    return null;
  }
}

List<_ChildSlot> _readSlotsFromRaw(dynamic raw, {required String groupName}) {
  if (raw == null) return const <_ChildSlot>[];

  if (raw is String) {
    final s = raw.trim();
    if (s.isNotEmpty) {
      try {
        raw = jsonDecode(s);
      } catch (_) {}
    }
  }

  if (raw is Map) {
    final inner =
        raw['slots'] ?? raw['children'] ?? raw['items'] ?? raw['parkingAreas'];
    if (inner is List) raw = inner;
  }

  final out = <_ChildSlot>[];

  if (raw is List) {
    for (final it in raw) {
      if (it is List) {
        if (it.length < 2) continue;
        final r = _asInt(it[0]);
        final c = _asInt(it[1]);
        if (r == null || c == null) continue;

        int? spanR;
        int? spanC;

        if (it.length >= 3) {
          final parsed = _parseSpanString(it[2]);
          if (parsed != null) {
            spanR = parsed.$1;
            spanC = parsed.$2;
          }
        }
        if (it.length >= 4) {
          final sr = _asInt(it[2]);
          final sc = _asInt(it[3]);
          if (sr != null && sc != null) {
            spanR = sr;
            spanC = sc;
          }
        }

        final (sr, sc) = _normalizeSpan(spanR, spanC);
        out.add(_ChildSlot(
          groupName: groupName,
          r0: r,
          c0: c,
          r1: r + (sr - 1),
          c1: c + (sc - 1),
          kind: 'unknown',
        ));
        continue;
      }

      final m = _toLooseMap(it);
      if (m == null) continue;

      final fr0 = _asInt(m['r0'] ?? m['row0'] ?? m['top'] ?? m['minR']);
      final fc0 = _asInt(m['c0'] ?? m['col0'] ?? m['left'] ?? m['minC']);
      final fr1 = _asInt(m['r1'] ?? m['row1'] ?? m['bottom'] ?? m['maxR']);
      final fc1 = _asInt(m['c1'] ?? m['col1'] ?? m['right'] ?? m['maxC']);

      final kindRaw = _trimOrEmpty(m['kind'] ?? m['type'] ?? m['shape'] ?? m['size']);
      final kind = kindRaw.isEmpty ? 'unknown' : kindRaw;
      final label = _trimOrEmpty(m['label'] ?? m['slotLabel'] ?? m['name']);
      final category = _trimOrEmpty(
          m['category'] ?? m['categoryKey'] ?? m['slotCategory'] ?? m['regulation']);
      final categoryLabel = _trimOrEmpty(
          m['categoryLabel'] ?? m['slotCategoryLabel'] ?? m['regulationLabel']);
      final footprint =
          _trimOrEmpty(m['footprint'] ?? m['footprintLabel'] ?? m['size'] ?? m['shape']);

      final areaIdRaw = _trimOrEmpty(m['areaId'] ?? m['id'] ?? m['area_id']);
      final areaId = areaIdRaw.isEmpty ? null : areaIdRaw;

      final no = _asInt(m['no'] ?? m['num'] ?? m['number']);
      final minWidthMeters = _asDouble(
          m['minWidthMeters'] ?? m['minWidth'] ?? m['widthMeters'] ?? m['width']);
      final minLengthMeters = _asDouble(
          m['minLengthMeters'] ?? m['minLength'] ?? m['lengthMeters'] ?? m['length']);

      if (fr0 != null && fr1 != null && fc0 != null && fc1 != null) {
        out.add(_ChildSlot(
          groupName: groupName,
          r0: fr0,
          c0: fc0,
          r1: fr1,
          c1: fc1,
          kind: kind,
          label: label,
          category: category,
          categoryLabel: categoryLabel,
          footprint: footprint,
          minWidthMeters: minWidthMeters,
          minLengthMeters: minLengthMeters,
          areaId: areaId,
          no: no,
        ));
        continue;
      }

      final r = _asInt(m['r'] ?? m['row'] ?? m['z'] ?? m['y'] ?? fr0);
      final c = _asInt(m['c'] ?? m['col'] ?? m['x'] ?? fc0);
      if (r == null || c == null) continue;

      int? spanR = _asInt(m['spanR'] ??
          m['sr'] ??
          m['rowSpan'] ??
          m['rows'] ??
          m['h'] ??
          m['height']);
      int? spanC = _asInt(m['spanC'] ??
          m['sc'] ??
          m['colSpan'] ??
          m['cols'] ??
          m['w'] ??
          m['width']);

      if (spanR == null || spanC == null) {
        final parsed = _parseSpanString(
            m['size'] ?? m['dim'] ?? m['type'] ?? m['shape'] ?? m['kind']);
        if (parsed != null) {
          spanR = parsed.$1;
          spanC = parsed.$2;
        }
      }

      final kSpan = _spanFromKind(kind);
      if (kSpan != null) {
        spanR = kSpan.$1;
        spanC = kSpan.$2;
      }

      final (sr, sc) = _normalizeSpan(spanR, spanC);

      out.add(_ChildSlot(
        groupName: groupName,
        r0: r,
        c0: c,
        r1: r + (sr - 1),
        c1: c + (sc - 1),
        kind: kind,
        label: label,
        category: category,
        categoryLabel: categoryLabel,
        footprint: footprint,
        minWidthMeters: minWidthMeters,
        minLengthMeters: minLengthMeters,
        areaId: areaId,
        no: no,
      ));
    }
  }

  return out;
}

List<_ChildSlot> _readChildSlotsFromLocation(LocationModel l,
    {required String groupName}) {
  final raw = _extractChildSlotsRawFromLocation(l);
  return _readSlotsFromRaw(raw, groupName: groupName);
}

List<String> _parentAliases(LocationModel parent) {
  final out = <String>[];

  final n = _trimOrEmpty(parent.locationName);
  if (n.isNotEmpty) out.add(_nameKey(n));

  for (final getter in <String? Function()>[
        () {
      try {
        final v = (parent as dynamic).id;
        return _trimOrEmpty(v);
      } catch (_) {
        return null;
      }
    },
        () {
      try {
        final v = (parent as dynamic).docId;
        return _trimOrEmpty(v);
      } catch (_) {
        return null;
      }
    },
        () {
      try {
        final v = (parent as dynamic).documentId;
        return _trimOrEmpty(v);
      } catch (_) {
        return null;
      }
    },
        () {
      try {
        final v = (parent as dynamic).key;
        return _trimOrEmpty(v);
      } catch (_) {
        return null;
      }
    },
        () {
      try {
        final v = (parent as dynamic).locationId;
        return _trimOrEmpty(v);
      } catch (_) {
        return null;
      }
    },
  ]) {
    final v = getter();
    if (v != null && v.isNotEmpty) out.add(_nameKey(v));
  }

  return out.toSet().toList();
}

bool _matchesParentRef(LocationModel parent, LocationModel child) {
  String pRef = '';
  try {
    pRef = _trimOrEmpty((child as dynamic).parent);
  } catch (_) {}

  if (pRef.isEmpty) return false;

  final refKey = _nameKey(pRef);
  final aliases = _parentAliases(parent);

  return aliases.contains(refKey);
}

bool _matchesAreaLoose(String parentArea, String childArea) {
  final pa = parentArea.trim();
  final ca = childArea.trim();
  if (pa.isEmpty) return true;
  if (ca.isEmpty) return true;
  return pa == ca;
}

double _stableHash01(String s) {
  const int fnvPrime = 16777619;
  int hash = 2166136261;
  for (int i = 0; i < s.length; i++) {
    hash ^= s.codeUnitAt(i);
    hash = (hash * fnvPrime) & 0xffffffff;
  }
  return (hash / 0xffffffff).clamp(0.0, 1.0);
}

List<_ChildSlot> _applyOverlayToSlotsIfNeeded({
  required String parentName,
  required ParkingGridOverlay overlay,
  required List<_ChildSlot> slots,
}) {
  if (slots.isEmpty || overlay.isEmpty) return slots;

  final o = overlay.forParent(parentName);
  if (o.isEmpty) return slots;

  return slots.map((s) {
    final st = o.statusForSlot(childName: s.groupName, no: s.no);
    final fromGroup = o.isFromGroupOnly(childName: s.groupName, no: s.no);

    return s.copyWith(
      status: st,
      statusFromGroup: fromGroup,
    );
  }).toList(growable: false);
}

List<_ChildRegion> _applyOverlayToRegionsIfNeeded({
  required String parentName,
  required ParkingGridOverlay overlay,
  required List<_ChildRegion> regions,
}) {
  if (regions.isEmpty || overlay.isEmpty) return regions;

  final o = overlay.forParent(parentName);
  if (o.isEmpty) return regions;

  return regions.map((r) {
    final st = o.statusForSlot(childName: r.name, no: null);
    final fromGroup = o.isFromGroupOnly(childName: r.name, no: null);
    return r.copyWith(status: st, statusFromGroup: fromGroup);
  }).toList(growable: false);
}

String _pickGroupForSlot(_ChildSlot s, List<_ChildRegion> regions) {
  if (regions.isEmpty) return s.groupName;
  final cr = s.centerR;
  final cc = s.centerC;

  _ChildRegion? best;
  for (final r in regions) {
    if (!r.containsPoint(cr, cc)) continue;
    if (best == null) {
      best = r;
    } else if (r.areaCells < best.areaCells) {
      best = r;
    }
  }
  return best?.name ?? s.groupName;
}

List<_ChildSlot> _ensureSlotNumbers(List<_ChildSlot> slots) {
  if (slots.isEmpty) return slots;

  final groups = <String, List<_ChildSlot>>{};
  for (final s in slots) {
    groups.putIfAbsent(s.groupName, () => <_ChildSlot>[]).add(s);
  }

  int slotCompare(_ChildSlot a, _ChildSlot b) {
    final dr = a.r.compareTo(b.r);
    if (dr != 0) return dr;
    final dc = a.c.compareTo(b.c);
    if (dc != 0) return dc;
    final ar = a.spanR.compareTo(b.spanR);
    if (ar != 0) return ar;
    final ac = a.spanC.compareTo(b.spanC);
    if (ac != 0) return ac;
    final ak = a.kindNorm.compareTo(b.kindNorm);
    if (ak != 0) return ak;
    final aid = (a.areaId ?? '').compareTo(b.areaId ?? '');
    if (aid != 0) return aid;
    return 0;
  }

  final out = <_ChildSlot>[];
  for (final e in groups.entries) {
    final list = List<_ChildSlot>.from(e.value);
    list.sort(slotCompare);

    int next = 1;
    for (final s in list) {
      if (s.no != null) {
        out.add(s);
      } else {
        out.add(s.copyWith(no: next));
        next++;
      }
    }
  }

  out.sort((a, b) {
    final gn = a.groupName.compareTo(b.groupName);
    if (gn != 0) return gn;
    return slotCompare(a, b);
  });

  return out;
}

class TabletGrid2dPreview extends StatefulWidget {
  final List<LocationModel> locations;
  final ParkingGridOverlay overlay;
  final Map<String, TextParkingPreviewMetrics> textMetricsByLocation;

  const TabletGrid2dPreview({
    super.key,
    required this.locations,
    this.overlay = const ParkingGridOverlay.empty(),
    this.textMetricsByLocation = const <String, TextParkingPreviewMetrics>{},
  });

  @override
  State<TabletGrid2dPreview> createState() => _TabletGrid2dPreviewState();
}

class _TabletGrid2dPreviewState extends State<TabletGrid2dPreview> {
  int _index = 0;
  int _navDir = 0;


  List<LocationModel> _readCompositeParents() {
    final parents = <LocationModel>[];
    for (final l in widget.locations) {
      if (_isCompositeParentType(l.type)) parents.add(l);
    }

    parents.sort((a, b) {
      final ai = _isSelectedLoose(a) ? 0 : 1;
      final bi = _isSelectedLoose(b) ? 0 : 1;
      if (ai != bi) return ai - bi;
      final an = _trimOrEmpty(a.locationName);
      final bn = _trimOrEmpty(b.locationName);
      return an.compareTo(bn);
    });

    return parents;
  }

  List<LocationModel> _readTextLocations() {
    final out = <LocationModel>[];
    for (final l in widget.locations) {
      if (_isTextPreviewCandidate(l)) out.add(l);
    }

    out.sort((a, b) {
      final ai = _isSelectedLoose(a) ? 0 : 1;
      final bi = _isSelectedLoose(b) ? 0 : 1;
      if (ai != bi) return ai - bi;
      final an = _trimOrEmpty(a.locationName);
      final bn = _trimOrEmpty(b.locationName);
      return an.compareTo(bn);
    });

    return out;
  }

  List<_PreviewEntry> _readPreviewEntries() {
    final entries = <_PreviewEntry>[];

    for (final p in _readCompositeParents()) {
      final title = _trimOrEmpty(p.locationName).isEmpty
          ? '무명 구역'
          : _trimOrEmpty(p.locationName);
      entries.add(_PreviewEntry(
        kind: _PreviewEntryKind.structured,
        location: p,
        title: title,
        subtitle: _previewSubtitleForLocation(p, _PreviewEntryKind.structured),
      ));
    }

    for (final t in _readTextLocations()) {
      final title = _trimOrEmpty(t.locationName).isEmpty
          ? '무명 텍스트 구역'
          : _trimOrEmpty(t.locationName);
      entries.add(_PreviewEntry(
        kind: _PreviewEntryKind.text,
        location: t,
        title: title,
        subtitle: _previewSubtitleForLocation(t, _PreviewEntryKind.text),
      ));
    }

    entries.sort((a, b) {
      final ai = _isSelectedLoose(a.location) ? 0 : 1;
      final bi = _isSelectedLoose(b.location) ? 0 : 1;
      if (ai != bi) return ai - bi;
      if (a.kind != b.kind) {
        return a.kind == _PreviewEntryKind.structured ? -1 : 1;
      }
      return a.title.compareTo(b.title);
    });

    return entries;
  }

  @override
  void didUpdateWidget(covariant TabletGrid2dPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    final entries = _readPreviewEntries();
    if (entries.isEmpty) {
      if (_index != 0) setState(() => _index = 0);
      return;
    }
    if (_index >= entries.length) setState(() => _index = 0);
  }

  void _setIndex(int next, {required int count}) {
    if (count <= 0) return;
    final safe = ((next % count) + count) % count;
    if (safe == _index) return;
    _navDir = (safe > _index) ? 1 : -1;
    setState(() => _index = safe);
  }

  Future<void> _openPicker(List<_PreviewEntry> entries) async {
    if (!mounted) return;
    if (entries.length <= 1) return;

    final items = <ParkingGridPreviewPickerItem>[];
    for (final entry in entries) {
      items.add(ParkingGridPreviewPickerItem(
        title: entry.title,
        subtitle: entry.subtitle,
        kind: entry.isStructured
            ? ParkingGridPreviewPickerItemKind.structured
            : ParkingGridPreviewPickerItemKind.text,
      ));
    }

    final picked = await showTabletGrid2DViewPickerDialog(
      context: context,
      title: '주차 구역 선택',
      items: items,
      selectedIndex: _index.clamp(0, entries.length - 1),
    );

    if (!mounted) return;
    if (picked == null) return;
    _setIndex(picked, count: entries.length);
  }

  void _handleSwipe(DragEndDetails details, int count) {
    final v = details.primaryVelocity ?? 0;
    if (v.abs() < 250) return;
    if (v < 0) {
      _navDir = 1;
      setState(() => _index = (_index + 1) % count);
    } else {
      _navDir = -1;
      setState(() => _index = (_index - 1 + count) % count);
    }
  }

  Widget _wrapSwipe({required int count, required Widget child}) {
    if (count <= 1) return child;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (d) => _handleSwipe(d, count),
      child: child,
    );
  }

  Widget _withSwipeAffordance({
    required int index,
    required int count,
    required Widget child,
  }) {
    if (count <= 1) return child;

    final cs = Theme.of(context).colorScheme;
    final on = cs.onSurface.withOpacity(0.42);

    Widget chevron(IconData icon) => Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.10),
        shape: BoxShape.circle,
        border: Border.all(color: cs.outlineVariant.withOpacity(0.35)),
      ),
      child: Icon(icon, size: 26, color: on),
    );

    Widget pageBadge() => Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Text(
        '${index + 1}/$count',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: cs.onSurface.withOpacity(0.78),
        ),
      ),
    );

    Widget dots() => Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(count, (i) {
        final selected = i == index;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          width: selected ? 16 : 6,
          height: 6,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: cs.onSurface.withOpacity(selected ? 0.52 : 0.22),
            borderRadius: BorderRadius.circular(999),
          ),
        );
      }),
    );

    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned(
          left: 8,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
              child: Center(child: chevron(Icons.chevron_left_rounded))),
        ),
        Positioned(
          right: 8,
          top: 0,
          bottom: 0,
          child: IgnorePointer(
              child: Center(child: chevron(Icons.chevron_right_rounded))),
        ),
        Positioned(
          right: 10,
          top: 10,
          child: IgnorePointer(child: pageBadge()),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 10,
          child: IgnorePointer(
            child: Center(child: dots()),
          ),
        ),
      ],
    );
  }

  Widget _animatedBody({required Key key, required Widget child}) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 240),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (c, anim) {
        final dx = (_navDir >= 0) ? 0.20 : -0.20;
        final slide =
        Tween<Offset>(begin: Offset(dx, 0), end: Offset.zero).animate(anim);
        return ClipRect(
          child: SlideTransition(
            position: slide,
            child: FadeTransition(opacity: anim, child: c),
          ),
        );
      },
      child: KeyedSubtree(key: key, child: child),
    );
  }

  Widget _cardShell({
    required Widget child,
    EdgeInsets padding =
    const EdgeInsets.symmetric(vertical: 14, horizontal: 14),
  }) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      color: cs.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.55)),
      ),
      child: Padding(padding: padding, child: child),
    );
  }

  Widget _kindBadge({
    required ColorScheme cs,
    required TextTheme tt,
    required String label,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: (tt.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
              fontWeight: FontWeight.w900,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerRow({
    required String title,
    required VoidCallback? onPick,
    String? kindLabel,
    IconData? kindIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final btnStyle = OutlinedButton.styleFrom(
      foregroundColor: cs.onSurface,
      side: BorderSide(color: cs.outlineVariant.withOpacity(0.75)),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );

    Widget actionButtons() {
      return IntrinsicWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 44,
              child: OutlinedButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.layers_rounded, size: 18),
                label: const Text('구역 선택'),
                style: btnStyle,
              ),
            ),
          ],
        ),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.view_in_ar, color: cs.onSurfaceVariant, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style:
                (tt.titleMedium ?? const TextStyle(fontSize: 16)).copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
              ),
              if (kindLabel != null && kindLabel.trim().isNotEmpty) ...[
                const SizedBox(height: 6),
                _kindBadge(
                  cs: cs,
                  tt: tt,
                  label: kindLabel,
                  icon: kindIcon ?? Icons.label_rounded,
                ),
              ],
            ],
          ),
        ),
        actionButtons(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final entries = _readPreviewEntries();
    final count = entries.length;

    if (entries.isEmpty) {
      return _cardShell(
        child: Column(
          children: [
            _headerRow(title: '선택 : 주차 구역', onPick: null),
            const SizedBox(height: 10),
            Text(
              '표시할 구조형 또는 텍스트형 주차 구역이 없습니다.',
              textAlign: TextAlign.center,
              style: (tt.bodyMedium ?? const TextStyle(fontSize: 13)).copyWith(
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    final idx = (_index < 0 || _index >= count) ? 0 : _index;
    final entry = entries[idx];
    final loc = entry.location;

    final nameTrimmed = _trimOrEmpty(loc.locationName);
    final displayName = nameTrimmed.isEmpty ? '무명 구역' : nameTrimmed;
    final headerTitle = '선택 : $displayName';

    final pickBtn = count <= 1 ? null : () => _openPicker(entries);

    final kindLabel = entry.isStructured ? '구조형 주차 구역' : '텍스트형 주차 구역';
    final kindIcon = entry.isStructured
        ? Icons.account_tree_rounded
        : Icons.text_fields_rounded;

    final body = entry.isStructured
        ? _buildStructuredPreviewBody(
      entry: entry,
      index: idx,
      count: count,
      cs: cs,
      tt: tt,
    )
        : _buildTextPreviewPanel(
      entry: entry,
      index: idx,
      count: count,
      cs: cs,
      tt: tt,
    );

    final contentKey = ValueKey<String>(
      '${entry.kind.name}_${idx}_${_nameKey(nameTrimmed)}',
    );

    return _wrapSwipe(
      count: count,
      child: _cardShell(
        child: Column(
          children: [
            _headerRow(
              title: headerTitle,
              onPick: pickBtn,
              kindLabel: kindLabel,
              kindIcon: kindIcon,
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _animatedBody(key: contentKey, child: body),
            ),
          ],
        ),
      ),
    );
  }
}
