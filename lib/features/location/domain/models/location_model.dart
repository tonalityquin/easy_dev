import 'package:cloud_firestore/cloud_firestore.dart';

import 'parking_grid_model.dart';
import 'grid_rect.dart';

class ChildSlot {
  final int no;
  final String areaId;
  final int r0;
  final int c0;
  final int r1;
  final int c1;
  final String kind;
  final String label;
  final String category;
  final String categoryLabel;
  final String footprint;
  final double minWidthMeters;
  final double minLengthMeters;

  const ChildSlot({
    required this.no,
    required this.areaId,
    required this.r0,
    required this.c0,
    required this.r1,
    required this.c1,
    required this.kind,
    required this.label,
    required this.category,
    required this.categoryLabel,
    required this.footprint,
    required this.minWidthMeters,
    required this.minLengthMeters,
  });

  factory ChildSlot.fromParkingArea({
    required int no,
    required ParkingArea area,
  }) {
    return ChildSlot(
      no: no,
      areaId: area.id,
      r0: area.r0,
      c0: area.c0,
      r1: area.r1,
      c1: area.c1,
      kind: area.kind.wireName,
      label: area.kind.label,
      category: area.kind.categoryKey,
      categoryLabel: area.kind.categoryLabel,
      footprint: area.kind.footprintLabel,
      minWidthMeters: area.kind.minWidthMeters,
      minLengthMeters: area.kind.minLengthMeters,
    );
  }

  static String _text(Object? raw) => raw == null ? '' : raw.toString().trim();

  static String _firstText(Map<String, dynamic> json, List<String> keys) {
    for (final key in keys) {
      if (!json.containsKey(key)) continue;
      final value = _text(json[key]);
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  static double? _readDouble(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) return double.tryParse(raw.trim());
    return null;
  }

  factory ChildSlot.fromJson(Map<String, dynamic> json) {
    final rawKind = _firstText(json, ['kind', 'type', 'shape', 'size']);
    final rawLabel = _firstText(json, ['label', 'slotLabel', 'name']);
    final rawCategory = _firstText(json, [
      'category',
      'categoryKey',
      'slotCategory',
      'regulation',
      'regulationKey',
    ]);
    final rawCategoryLabel = _firstText(json, [
      'categoryLabel',
      'slotCategoryLabel',
      'regulationLabel',
    ]);
    final rawFootprint = _firstText(json, [
      'footprint',
      'footprintLabel',
      'size',
      'shape',
    ]);

    final parsedKind = ParkingAreaKindX.tryParse(rawKind) ??
        ParkingAreaKindX.tryParse(rawLabel) ??
        ParkingAreaKindX.tryParseParts(
          category: rawCategory.isNotEmpty ? rawCategory : rawCategoryLabel,
          footprint: rawFootprint,
        );

    final resolvedKind = parsedKind?.wireName ??
        (rawKind.isNotEmpty ? rawKind : 'unknown');
    final resolvedLabel = rawLabel.isNotEmpty
        ? rawLabel
        : (parsedKind?.label ?? (rawKind.isNotEmpty ? rawKind : ''));
    final resolvedCategory = rawCategory.isNotEmpty
        ? rawCategory
        : (parsedKind?.categoryKey ?? '');
    final resolvedCategoryLabel = rawCategoryLabel.isNotEmpty
        ? rawCategoryLabel
        : (parsedKind?.categoryLabel ?? '');
    final resolvedFootprint = rawFootprint.isNotEmpty
        ? rawFootprint
        : (parsedKind?.footprintLabel ?? '');

    return ChildSlot(
      no: (json['no'] as num?)?.toInt() ?? 0,
      areaId: (json['areaId'] ?? '').toString(),
      r0: (json['r0'] as num?)?.toInt() ?? 0,
      c0: (json['c0'] as num?)?.toInt() ?? 0,
      r1: (json['r1'] as num?)?.toInt() ?? 0,
      c1: (json['c1'] as num?)?.toInt() ?? 0,
      kind: resolvedKind,
      label: resolvedLabel,
      category: resolvedCategory,
      categoryLabel: resolvedCategoryLabel,
      footprint: resolvedFootprint,
      minWidthMeters: _readDouble(json['minWidthMeters'] ??
              json['minWidth'] ??
              json['widthMeters'] ??
              json['width']) ??
          parsedKind?.minWidthMeters ??
          0,
      minLengthMeters: _readDouble(json['minLengthMeters'] ??
              json['minLength'] ??
              json['lengthMeters'] ??
              json['length']) ??
          parsedKind?.minLengthMeters ??
          0,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'no': no,
        'areaId': areaId,
        'r0': r0,
        'c0': c0,
        'r1': r1,
        'c1': c1,
        'kind': kind,
        'label': label,
        'category': category,
        'categoryLabel': categoryLabel,
        'footprint': footprint,
        'minWidthMeters': minWidthMeters,
        'minLengthMeters': minLengthMeters,
      };
}

class LocationModel {
  final String id;
  final String area;
  final int capacity;
  final bool isSelected;
  final String locationName;
  final String? parent;
  final String? type;
  final int plateCount;

  final ParkingGridModel? parkingGrid;

  final GridRect? childRect;

  final String? childKind;

  final List<ChildSlot> childSlots;

  LocationModel({
    required this.id,
    required this.area,
    required this.capacity,
    required this.isSelected,
    required this.locationName,
    this.parent,
    this.type,
    this.plateCount = 0,
    this.parkingGrid,
    this.childRect,
    this.childKind,
    this.childSlots = const <ChildSlot>[],
  }) : assert(id.isNotEmpty, 'ID cannot be empty');

  bool get isCompositeParent => (type ?? '') == 'composite_parent';

  bool get isCompositeChild {
    final t = type ?? 'single';
    return t == 'composite_child' || t == 'composite';
  }

  bool get isTowerChild {
    final k = (childKind ?? '').trim().toLowerCase();
    return k == 'tower';
  }

  static ParkingGridModel? _parseParkingGrid(Object? rawGrid) {
    if (rawGrid is Map) {
      final gridMap = Map<String, dynamic>.from(rawGrid);
      return ParkingGridModel.fromJson(gridMap);
    }
    return null;
  }

  static GridRect? _parseChildRect(Object? rawRect) {
    if (rawRect is Map) {
      final rectMap = Map<String, dynamic>.from(rawRect);
      return GridRect.fromJson(rectMap).normalized();
    }
    return null;
  }

  static List<ChildSlot> _parseChildSlots(Object? rawSlots) {
    if (rawSlots is! List) return const <ChildSlot>[];
    final out = <ChildSlot>[];
    for (final e in rawSlots) {
      if (e is Map) {
        out.add(ChildSlot.fromJson(Map<String, dynamic>.from(e)));
      }
    }
    return out;
  }

  factory LocationModel.fromMap(String id, Map<String, dynamic> data) {
    final parsedGrid = _parseParkingGrid(data['parkingGrid']);
    final parsedChildRect = _parseChildRect(data['childRect'] ?? data['rect']);
    final parsedChildSlots = _parseChildSlots(data['childSlots']);

    return LocationModel(
      id: id,
      area: (data['area'] ?? '').toString(),
      capacity: (data['capacity'] as num?)?.toInt() ?? 0,
      isSelected: data['isSelected'] == true,
      locationName: (data['locationName'] ?? '').toString(),
      parent: data['parent']?.toString(),
      type: data['type']?.toString(),
      plateCount: (data['plateCount'] as num?)?.toInt() ?? 0,
      parkingGrid: parsedGrid,
      childRect: parsedChildRect,
      childKind: data['childKind']?.toString(),
      childSlots: parsedChildSlots,
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    final resolvedType = (type ?? 'single').toString();

    final resolvedParent = resolvedType == 'composite_parent' ? null : parent;

    final map = <String, dynamic>{
      'area': area,
      'capacity': capacity,
      'isSelected': isSelected,
      'locationName': locationName,
      'parent': resolvedParent,
      'timestamp': FieldValue.serverTimestamp(),
      'type': resolvedType,
      'plateCount': plateCount,
    };

    if (resolvedType == 'composite_parent' && parkingGrid != null) {
      map['parkingGrid'] = parkingGrid!.toJson();
    }

    if ((resolvedType == 'composite_child' || resolvedType == 'composite')) {
      if (childRect != null) {
        map['childRect'] = childRect!.toJson();
      }
      final k = (childKind ?? '').trim();
      if (k.isNotEmpty) {
        map['childKind'] = k;
      }
      if (childSlots.isNotEmpty) {
        map['childSlots'] = childSlots.map((e) => e.toJson()).toList();
      }
    }

    return map;
  }

  Map<String, dynamic> toCacheMap() {
    return {
      'id': id,
      'area': area,
      'capacity': capacity,
      'isSelected': isSelected,
      'locationName': locationName,
      'parent': parent,
      'type': type,
      'plateCount': plateCount,
      if (parkingGrid != null) 'parkingGrid': parkingGrid!.toJson(),
      if (childRect != null) 'childRect': childRect!.toJson(),
      if ((childKind ?? '').trim().isNotEmpty) 'childKind': childKind,
      if (childSlots.isNotEmpty)
        'childSlots': childSlots.map((e) => e.toJson()).toList(),
    };
  }

  factory LocationModel.fromCacheMap(Map<String, dynamic> data) {
    final rawId = (data['id'] ?? '').toString();
    final safeId = rawId.isEmpty ? 'unknown' : rawId;

    final parsedGrid = _parseParkingGrid(data['parkingGrid']);
    final parsedChildRect = _parseChildRect(data['childRect'] ?? data['rect']);
    final parsedChildSlots = _parseChildSlots(data['childSlots']);

    return LocationModel(
      id: safeId,
      area: (data['area'] ?? '').toString(),
      capacity: (data['capacity'] as num?)?.toInt() ?? 0,
      isSelected: data['isSelected'] == true,
      locationName: (data['locationName'] ?? '').toString(),
      parent: data['parent']?.toString(),
      type: data['type']?.toString(),
      plateCount: (data['plateCount'] as num?)?.toInt() ?? 0,
      parkingGrid: parsedGrid,
      childRect: parsedChildRect,
      childKind: data['childKind']?.toString(),
      childSlots: parsedChildSlots,
    );
  }

  LocationModel copyWith({
    String? id,
    String? area,
    int? capacity,
    bool? isSelected,
    String? locationName,
    String? parent,
    String? type,
    int? plateCount,
    ParkingGridModel? parkingGrid,
    GridRect? childRect,
    String? childKind,
    List<ChildSlot>? childSlots,
  }) {
    return LocationModel(
      id: id ?? this.id,
      area: area ?? this.area,
      capacity: capacity ?? this.capacity,
      isSelected: isSelected ?? this.isSelected,
      locationName: locationName ?? this.locationName,
      parent: parent ?? this.parent,
      type: type ?? this.type,
      plateCount: plateCount ?? this.plateCount,
      parkingGrid: parkingGrid ?? this.parkingGrid,
      childRect: childRect ?? this.childRect,
      childKind: childKind ?? this.childKind,
      childSlots: childSlots ?? this.childSlots,
    );
  }
}
