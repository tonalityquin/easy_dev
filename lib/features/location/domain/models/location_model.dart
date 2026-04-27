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

  const ChildSlot({
    required this.no,
    required this.areaId,
    required this.r0,
    required this.c0,
    required this.r1,
    required this.c1,
    required this.kind,
  });

  factory ChildSlot.fromJson(Map<String, dynamic> json) {
    return ChildSlot(
      no: (json['no'] as num?)?.toInt() ?? 0,
      areaId: (json['areaId'] ?? '').toString(),
      r0: (json['r0'] as num?)?.toInt() ?? 0,
      c0: (json['c0'] as num?)?.toInt() ?? 0,
      r1: (json['r1'] as num?)?.toInt() ?? 0,
      c1: (json['c1'] as num?)?.toInt() ?? 0,
      kind: (json['kind'] ?? '').toString(),
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
