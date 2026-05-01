import 'dart:math' as math;
import 'package:flutter/foundation.dart';

import 'grid_rect.dart';

enum ParkingGridCellType { empty, road, pillar }

String parkingGridCellTypeLabel(ParkingGridCellType t) {
  switch (t) {
    case ParkingGridCellType.empty:
      return '빈칸';
    case ParkingGridCellType.road:
      return '도로';
    case ParkingGridCellType.pillar:
      return '기둥';
  }
}

enum EdgeSide { north, east, south, west }

String edgeSideLabel(EdgeSide s) {
  switch (s) {
    case EdgeSide.north:
      return '북';
    case EdgeSide.east:
      return '동';
    case EdgeSide.south:
      return '남';
    case EdgeSide.west:
      return '서';
  }
}

@immutable
class EdgePlacement {
  final int r;
  final int c;
  final EdgeSide side;

  const EdgePlacement({required this.r, required this.c, required this.side});

  String toKey() => '$r|$c|${side.index}';

  static EdgePlacement fromKey(String key) {
    final parts = key.split('|');
    return EdgePlacement(
      r: int.parse(parts[0]),
      c: int.parse(parts[1]),
      side: EdgeSide.values[int.parse(parts[2])],
    );
  }

  @override
  bool operator ==(Object other) {
    return other is EdgePlacement && other.r == r && other.c == c && other.side == side;
  }

  @override
  int get hashCode => Object.hash(r, c, side);
}

bool isEdgeValid(EdgePlacement e, int rows, int cols) {
  if (rows <= 0 || cols <= 0) return false;
  if (e.r < 0 || e.r >= rows || e.c < 0 || e.c >= cols) return false;

  final onPerimeter = e.r == 0 || e.r == rows - 1 || e.c == 0 || e.c == cols - 1;
  if (!onPerimeter) return false;

  switch (e.side) {
    case EdgeSide.north:
      return e.r == 0;
    case EdgeSide.south:
      return e.r == rows - 1;
    case EdgeSide.west:
      return e.c == 0;
    case EdgeSide.east:
      return e.c == cols - 1;
  }
}

int edgeSortKey(EdgePlacement e) => (e.r * 100000) + (e.c * 10) + e.side.index;

typedef WallGroupId = String;

enum ParkingAreaKind {
  compact1x2,
  compact2x1,
  standard1x2,
  standard2x1,
  extendedA1x2,
  extendedA2x1,
  extendedB2x2,
}

extension ParkingAreaKindX on ParkingAreaKind {
  int get w {
    switch (this) {
      case ParkingAreaKind.compact1x2:
      case ParkingAreaKind.standard1x2:
      case ParkingAreaKind.extendedA1x2:
      case ParkingAreaKind.extendedB2x2:
        return 2;
      case ParkingAreaKind.compact2x1:
      case ParkingAreaKind.standard2x1:
      case ParkingAreaKind.extendedA2x1:
        return 1;
    }
  }

  int get h {
    switch (this) {
      case ParkingAreaKind.compact1x2:
      case ParkingAreaKind.standard1x2:
      case ParkingAreaKind.extendedA1x2:
        return 1;
      case ParkingAreaKind.compact2x1:
      case ParkingAreaKind.standard2x1:
      case ParkingAreaKind.extendedA2x1:
      case ParkingAreaKind.extendedB2x2:
        return 2;
    }
  }

  String get footprintLabel => '${h}×${w}';

  String get categoryKey {
    switch (this) {
      case ParkingAreaKind.compact1x2:
      case ParkingAreaKind.compact2x1:
        return 'compact';
      case ParkingAreaKind.standard1x2:
      case ParkingAreaKind.standard2x1:
        return 'standard';
      case ParkingAreaKind.extendedA1x2:
      case ParkingAreaKind.extendedA2x1:
        return 'extendedA';
      case ParkingAreaKind.extendedB2x2:
        return 'extendedB';
    }
  }

  String get categoryLabel {
    switch (this) {
      case ParkingAreaKind.compact1x2:
      case ParkingAreaKind.compact2x1:
        return '경형';
      case ParkingAreaKind.standard1x2:
      case ParkingAreaKind.standard2x1:
        return '일반형';
      case ParkingAreaKind.extendedA1x2:
      case ParkingAreaKind.extendedA2x1:
        return '확장형 A';
      case ParkingAreaKind.extendedB2x2:
        return '확장형 B';
    }
  }

  double get minWidthMeters {
    switch (this) {
      case ParkingAreaKind.compact1x2:
      case ParkingAreaKind.compact2x1:
        return 2.0;
      case ParkingAreaKind.standard1x2:
      case ParkingAreaKind.standard2x1:
        return 2.5;
      case ParkingAreaKind.extendedA1x2:
      case ParkingAreaKind.extendedA2x1:
      case ParkingAreaKind.extendedB2x2:
        return 2.6;
    }
  }

  double get minLengthMeters {
    switch (this) {
      case ParkingAreaKind.compact1x2:
      case ParkingAreaKind.compact2x1:
        return 3.6;
      case ParkingAreaKind.standard1x2:
      case ParkingAreaKind.standard2x1:
        return 5.0;
      case ParkingAreaKind.extendedA1x2:
      case ParkingAreaKind.extendedA2x1:
      case ParkingAreaKind.extendedB2x2:
        return 5.2;
    }
  }

  String get wireName {
    switch (this) {
      case ParkingAreaKind.compact1x2:
        return 'compact1x2';
      case ParkingAreaKind.compact2x1:
        return 'compact2x1';
      case ParkingAreaKind.standard1x2:
        return 'standard1x2';
      case ParkingAreaKind.standard2x1:
        return 'standard2x1';
      case ParkingAreaKind.extendedA1x2:
        return 'extendedA1x2';
      case ParkingAreaKind.extendedA2x1:
        return 'extendedA2x1';
      case ParkingAreaKind.extendedB2x2:
        return 'extendedB2x2';
    }
  }

  String get label => '$categoryLabel $footprintLabel';

  static String _normalizeToken(dynamic raw) {
    if (raw == null) return '';
    return raw
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll('×', 'x')
        .replaceAll(RegExp(r'[\s_\-()]'), '');
  }

  static ParkingAreaKind? tryParse(dynamic raw) {
    final s = _normalizeToken(raw);
    if (s.isEmpty) return null;

    if (s == 'compact1x2' || s == 'light1x2' || s == 'small1x2' || s == '경형1x2') return ParkingAreaKind.compact1x2;
    if (s == 'compact2x1' || s == 'light2x1' || s == 'small2x1' || s == '경형2x1') return ParkingAreaKind.compact2x1;
    if (s == 'standard1x2' || s == 'normal1x2' || s == 'general1x2' || s == '일반형1x2' || s == '일반1x2') return ParkingAreaKind.standard1x2;
    if (s == 'standard2x1' || s == 'normal2x1' || s == 'general2x1' || s == '일반형2x1' || s == '일반2x1') return ParkingAreaKind.standard2x1;
    if (s == 'extendeda1x2' || s == 'expandeda1x2' || s == '확장형a1x2' || s == '확장a1x2') return ParkingAreaKind.extendedA1x2;
    if (s == 'extendeda2x1' || s == 'expandeda2x1' || s == '확장형a2x1' || s == '확장a2x1') return ParkingAreaKind.extendedA2x1;
    if (s == 'extendedb2x2' || s == 'extended2x2' || s == 'expandedb2x2' || s == '확장형b2x2' || s == '확장b2x2') return ParkingAreaKind.extendedB2x2;

    if (s == 'h1x2' || s == '1x2') return ParkingAreaKind.standard1x2;
    if (s == 'v2x1' || s == '2x1') return ParkingAreaKind.standard2x1;
    if (s == 'b2x2' || s == '2x2') return ParkingAreaKind.extendedB2x2;

    if (s.contains('경형') && s.contains('1x2')) return ParkingAreaKind.compact1x2;
    if (s.contains('경형') && s.contains('2x1')) return ParkingAreaKind.compact2x1;
    if ((s.contains('일반형') || s.contains('일반')) && s.contains('1x2')) return ParkingAreaKind.standard1x2;
    if ((s.contains('일반형') || s.contains('일반')) && s.contains('2x1')) return ParkingAreaKind.standard2x1;
    if ((s.contains('확장형a') || s.contains('확장a') || s.contains('extendeda') || s.contains('expandeda')) && s.contains('1x2')) return ParkingAreaKind.extendedA1x2;
    if ((s.contains('확장형a') || s.contains('확장a') || s.contains('extendeda') || s.contains('expandeda')) && s.contains('2x1')) return ParkingAreaKind.extendedA2x1;
    if ((s.contains('확장형b') || s.contains('확장b') || s.contains('extendedb') || s.contains('expandedb')) && s.contains('2x2')) return ParkingAreaKind.extendedB2x2;

    return null;
  }

  static ParkingAreaKind? tryParseParts({dynamic category, dynamic footprint}) {
    final c = _normalizeToken(category);
    final f = _normalizeToken(footprint);
    if (c.isEmpty || f.isEmpty) return null;
    return tryParse('$c$f');
  }
}

@immutable
class ParkingArea {
  final String id;
  final int r0;
  final int c0;
  final ParkingAreaKind kind;

  const ParkingArea({
    required this.id,
    required this.r0,
    required this.c0,
    required this.kind,
  });

  int get w => kind.w;
  int get h => kind.h;

  int get r1 => r0 + h - 1;
  int get c1 => c0 + w - 1;

  String get label => kind.label;
  String get categoryKey => kind.categoryKey;
  String get categoryLabel => kind.categoryLabel;
  String get footprintLabel => kind.footprintLabel;
  double get minWidthMeters => kind.minWidthMeters;
  double get minLengthMeters => kind.minLengthMeters;

  bool containsCell(int r, int c) => (r >= r0 && r <= r1 && c >= c0 && c <= c1);

  Map<String, dynamic> toJson() => {
    'id': id,
    'r0': r0,
    'c0': c0,
    'kind': kind.wireName,
    'label': kind.label,
    'category': kind.categoryKey,
    'categoryLabel': kind.categoryLabel,
    'footprint': kind.footprintLabel,
    'minWidthMeters': kind.minWidthMeters,
    'minLengthMeters': kind.minLengthMeters,
  };

  static ParkingArea? tryFromJson(dynamic json) {
    if (json is! Map) return null;

    int? readInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    final id = (json['id'] ?? '').toString().trim();
    final r0 = readInt(json['r0'] ?? json['r'] ?? json['row']);
    final c0 = readInt(json['c0'] ?? json['c'] ?? json['col']);
    final kind = ParkingAreaKindX.tryParse(json['kind'] ?? json['type'] ?? json['size'] ?? json['label']) ??
        ParkingAreaKindX.tryParseParts(
          category: json['category'] ?? json['categoryLabel'] ?? json['regulation'] ?? json['slotCategory'],
          footprint: json['footprint'] ?? json['footprintLabel'] ?? json['size'],
        );
    if (id.isEmpty || r0 == null || c0 == null || kind == null) return null;

    return ParkingArea(id: id, r0: r0, c0: c0, kind: kind);
  }

  @override
  bool operator ==(Object other) => other is ParkingArea && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

@immutable
class ParkingGridModel {
  final int rows;
  final int cols;
  final List<ParkingGridCellType> cells;

  final String? entranceGateKey;
  final String? exitGateKey;

  final Map<String, WallGroupId?> walls;
  final Map<WallGroupId, String> wallGroups;

  final List<ParkingArea> parkingAreas;

  final List<GridRect> entranceRects;
  final List<GridRect> exitRects;

  final List<GridRect> towerRects;

  final List<int> road2Cells;

  const ParkingGridModel({
    required this.rows,
    required this.cols,
    required this.cells,
    this.entranceGateKey,
    this.exitGateKey,
    this.walls = const {},
    this.wallGroups = const {},
    this.parkingAreas = const <ParkingArea>[],
    this.entranceRects = const <GridRect>[],
    this.exitRects = const <GridRect>[],
    this.towerRects = const <GridRect>[],
    this.road2Cells = const <int>[],
  });

  factory ParkingGridModel.fromEnumCells({
    required int rows,
    required int cols,
    required List<ParkingGridCellType> cells,
    String? entranceGateKey,
    String? exitGateKey,
    Map<String, WallGroupId?>? walls,
    Map<WallGroupId, String>? wallGroups,
    List<ParkingArea>? parkingAreas,
    List<GridRect>? entranceRects,
    List<GridRect>? exitRects,
    List<GridRect>? towerRects,
    List<int>? road2Cells,
  }) {
    return ParkingGridModel(
      rows: rows,
      cols: cols,
      cells: List.unmodifiable(cells),
      entranceGateKey: entranceGateKey,
      exitGateKey: exitGateKey,
      walls: Map.unmodifiable(walls ?? const {}),
      wallGroups: Map.unmodifiable(wallGroups ?? const {}),
      parkingAreas: List.unmodifiable(parkingAreas ?? const <ParkingArea>[]),
      entranceRects: List.unmodifiable(entranceRects ?? const <GridRect>[]),
      exitRects: List.unmodifiable(exitRects ?? const <GridRect>[]),
      towerRects: List.unmodifiable(towerRects ?? const <GridRect>[]),
      road2Cells: List.unmodifiable(road2Cells ?? const <int>[]),
    );
  }

  ParkingGridCellType cellTypeAt(int idx) => cells[idx];

  EdgePlacement? get entranceGate => entranceGateKey == null ? null : EdgePlacement.fromKey(entranceGateKey!);
  EdgePlacement? get exitGate => exitGateKey == null ? null : EdgePlacement.fromKey(exitGateKey!);

  ParkingGridModel copyWith({
    int? rows,
    int? cols,
    List<ParkingGridCellType>? cells,
    String? entranceGateKey,
    String? exitGateKey,
    Map<String, WallGroupId?>? walls,
    Map<WallGroupId, String>? wallGroups,
    List<ParkingArea>? parkingAreas,
    List<GridRect>? entranceRects,
    List<GridRect>? exitRects,
    List<GridRect>? towerRects,
    List<int>? road2Cells,
  }) {
    return ParkingGridModel(
      rows: rows ?? this.rows,
      cols: cols ?? this.cols,
      cells: List.unmodifiable(cells ?? this.cells),
      entranceGateKey: entranceGateKey ?? this.entranceGateKey,
      exitGateKey: exitGateKey ?? this.exitGateKey,
      walls: Map.unmodifiable(walls ?? this.walls),
      wallGroups: Map.unmodifiable(wallGroups ?? this.wallGroups),
      parkingAreas: List.unmodifiable(parkingAreas ?? this.parkingAreas),
      entranceRects: List.unmodifiable(entranceRects ?? this.entranceRects),
      exitRects: List.unmodifiable(exitRects ?? this.exitRects),
      towerRects: List.unmodifiable(towerRects ?? this.towerRects),
      road2Cells: List.unmodifiable(road2Cells ?? this.road2Cells),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'rows': rows,
      'cols': cols,
      'cells': cells.map((e) => e.index).toList(),
      'entranceGateKey': entranceGateKey,
      'exitGateKey': exitGateKey,
      'walls': walls,
      'wallGroups': wallGroups,
      'parkingAreas': parkingAreas.map((e) => e.toJson()).toList(),
      'entranceRects': entranceRects.map((e) => e.toJson()).toList(),
      'exitRects': exitRects.map((e) => e.toJson()).toList(),
      'towerRects': towerRects.map((e) => e.toJson()).toList(),
      'road2Cells': road2Cells,
    };
  }

  factory ParkingGridModel.fromJson(Map<String, dynamic> json) {
    int? readInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v.trim());
      return null;
    }

    List<dynamic>? readList(dynamic v) => v is List ? v : null;
    Map? readMap(dynamic v) => v is Map ? v : null;

    dynamic pickFirst(List<String> keys) {
      for (final k in keys) {
        if (json.containsKey(k)) return json[k];
      }
      return null;
    }

    int clampInt(int v, int lo, int hi) {
      if (v < lo) return lo;
      if (v > hi) return hi;
      return v;
    }

    int inferSquareSizeFromCells(List<dynamic> rawCells) {
      final len = rawCells.length;
      if (len <= 0) return 1;

      final n = math.sqrt(len.toDouble()).round();
      if (n > 0 && n * n == len) return n;

      final ceilN = math.sqrt(len.toDouble()).ceil();
      return clampInt(ceilN, 1, 200);
    }

    final rawCellsList = readList(json['cells']) ?? readList(json['gridCells']) ?? readList(json['cellTypes']) ?? const <dynamic>[];

    final int? rowsFromJson = readInt(json['rows']);
    final int? colsFromJson = readInt(json['cols']);
    final int? sizeFromJson = readInt(json['size']);

    final int inferred = inferSquareSizeFromCells(rawCellsList);

    late final int resolvedRows;
    late final int resolvedCols;

    if (sizeFromJson != null && sizeFromJson > 0 && (rowsFromJson == null || colsFromJson == null)) {
      final base = sizeFromJson;
      resolvedRows = clampInt(base, 1, 500);
      resolvedCols = clampInt(base, 1, 500);
    } else {
      final baseRows = rowsFromJson ?? inferred;
      final baseCols = colsFromJson ?? inferred;
      resolvedRows = clampInt(baseRows, 1, 500);
      resolvedCols = clampInt(baseCols, 1, 500);
    }

    ParkingGridCellType parseCell(dynamic v) {
      if (v is num) {
        final i = v.toInt();
        if (i >= 0 && i < ParkingGridCellType.values.length) {
          return ParkingGridCellType.values[i];
        }
        return ParkingGridCellType.empty;
      }
      if (v is String) {
        final s = v.trim().toLowerCase();
        if (s == 'road') return ParkingGridCellType.road;
        if (s == 'pillar') return ParkingGridCellType.pillar;
        if (s == 'empty') return ParkingGridCellType.empty;
        final i = int.tryParse(s);
        if (i != null && i >= 0 && i < ParkingGridCellType.values.length) {
          return ParkingGridCellType.values[i];
        }
        return ParkingGridCellType.empty;
      }
      return ParkingGridCellType.empty;
    }

    final targetLen = resolvedRows * resolvedCols;
    final cells = List<ParkingGridCellType>.filled(targetLen, ParkingGridCellType.empty, growable: false);
    for (int i = 0; i < targetLen && i < rawCellsList.length; i++) {
      cells[i] = parseCell(rawCellsList[i]);
    }

    EdgePlacement? tryParseGate(dynamic v) {
      if (v == null) return null;

      if (v is String) {
        try {
          final e = EdgePlacement.fromKey(v);
          return isEdgeValid(e, resolvedRows, resolvedCols) ? e : null;
        } catch (_) {
          return null;
        }
      }

      final m = readMap(v);
      if (m != null) {
        final r = readInt(m['r']);
        final c = readInt(m['c']);
        final sideIdx = readInt(m['side']);
        if (r == null || c == null || sideIdx == null) return null;
        if (sideIdx < 0 || sideIdx >= EdgeSide.values.length) return null;
        final e = EdgePlacement(r: r, c: c, side: EdgeSide.values[sideIdx]);
        return isEdgeValid(e, resolvedRows, resolvedCols) ? e : null;
      }

      return null;
    }

    final entranceRaw = pickFirst(['entranceGateKey', 'entranceGate', 'entrance', 'entryGateKey', 'entryGate']);
    final exitRaw = pickFirst(['exitGateKey', 'exitGate', 'exit', 'outGateKey', 'outGate']);

    final entrance = tryParseGate(entranceRaw);
    final exit = tryParseGate(exitRaw);

    EdgePlacement? tryParseEdgeKey(String key) {
      try {
        final e = EdgePlacement.fromKey(key);
        return isEdgeValid(e, resolvedRows, resolvedCols) ? e : null;
      } catch (_) {
        return null;
      }
    }

    final wallsRaw = pickFirst(['walls', 'wallEdges', 'wallEdgeKeys']);
    final Map<String, WallGroupId?> walls = {};

    final asMap = readMap(wallsRaw);
    if (asMap != null) {
      asMap.forEach((k, v) {
        final keyStr = k.toString();
        final e = tryParseEdgeKey(keyStr);
        if (e == null) return;

        WallGroupId? gid;
        if (v == null) {
          gid = null;
        } else if (v is String) {
          gid = v;
        } else if (v is Map) {
          final g = v['groupId'] ?? v['id'];
          gid = g == null ? null : g.toString();
        } else {
          gid = v.toString();
        }

        walls[e.toKey()] = gid;
      });
    } else {
      final asList = readList(wallsRaw);
      if (asList != null) {
        for (final it in asList) {
          final keyStr = it.toString();
          final e = tryParseEdgeKey(keyStr);
          if (e == null) continue;
          walls[e.toKey()] = null;
        }
      }
    }

    final wallGroupsRaw = readMap(pickFirst(['wallGroups', 'wallGroupNames'])) ?? const {};
    final Map<WallGroupId, String> wallGroups = {};
    wallGroupsRaw.forEach((k, v) {
      final id = k.toString();
      final name = v?.toString() ?? '';
      if (id.trim().isEmpty) return;
      wallGroups[id] = name;
    });

    final usedIds = walls.values.whereType<WallGroupId>().toSet();
    wallGroups.removeWhere((id, _) => !usedIds.contains(id));

    final entranceKey = entrance?.toKey();
    final exitKey = exit?.toKey();
    if (entranceKey != null && walls.containsKey(entranceKey)) {
      walls.remove(entranceKey);
    }
    if (exitKey != null && walls.containsKey(exitKey)) {
      walls.remove(exitKey);
    }

    final rawAreas = pickFirst(['parkingAreas', 'parkingAreaList', 'areas']);
    final list = readList(rawAreas) ?? const <dynamic>[];

    final parsedAreas = <ParkingArea>[];
    for (final item in list) {
      final a = ParkingArea.tryFromJson(item);
      if (a == null) continue;
      if (a.r0 < 0 || a.c0 < 0) continue;
      if (a.r1 >= resolvedRows || a.c1 >= resolvedCols) continue;
      if (a.id.trim().isEmpty) continue;
      parsedAreas.add(a);
    }

    GridRect? parseRect(dynamic v) {
      if (v == null) return null;
      if (v is Map<String, dynamic>) {
        return GridRect.fromJson(v).normalized();
      }
      final m = readMap(v);
      if (m != null) {
        final rr0 = readInt(m['r0'] ?? m['top'] ?? m['r'] ?? m['row0']);
        final cc0 = readInt(m['c0'] ?? m['left'] ?? m['c'] ?? m['col0']);
        final rr1 = readInt(m['r1'] ?? m['bottom'] ?? m['row1']);
        final cc1 = readInt(m['c1'] ?? m['right'] ?? m['col1']);
        if (rr0 == null || cc0 == null || rr1 == null || cc1 == null) return null;
        return GridRect(r0: rr0, c0: cc0, r1: rr1, c1: cc1).normalized();
      }
      if (v is String) {
        final s = v.trim();
        final r = GridRect.tryFromKey(s);
        if (r != null) return r.normalized();
      }
      return null;
    }

    bool rectInBounds(GridRect r) {
      final n = r.normalized();
      if (n.r0 < 0 || n.c0 < 0) return false;
      if (n.r1 >= resolvedRows || n.c1 >= resolvedCols) return false;
      return true;
    }

    List<GridRect> parseRectList(dynamic raw) {
      final l = readList(raw);
      if (l == null) return const <GridRect>[];
      final out = <GridRect>[];
      for (final it in l) {
        final r = parseRect(it);
        if (r == null) continue;
        if (!rectInBounds(r)) continue;
        out.add(r.normalized());
      }
      final uniq = <GridRect>{...out};
      return uniq.toList(growable: false);
    }

    final entranceRectsRaw = pickFirst(['entranceRects', 'entrances', 'entranceAreas', 'entranceRegions', 'entranceRectKeys']);
    final exitRectsRaw = pickFirst(['exitRects', 'exits', 'exitAreas', 'exitRegions', 'exitRectKeys']);
    final towerRectsRaw = pickFirst([
      'towerRects',
      'parkingTowerRects',
      'towers',
      'towerAreas',
      'towerRegions',
      'towerRectKeys',
      'parkingTowers',
    ]);

    var entranceRects = parseRectList(entranceRectsRaw);
    var exitRects = parseRectList(exitRectsRaw);
    final towerRects = parseRectList(towerRectsRaw);

    if (entranceRects.isEmpty && entrance != null) {
      entranceRects = <GridRect>[GridRect(r0: entrance.r, c0: entrance.c, r1: entrance.r, c1: entrance.c)];
    }
    if (exitRects.isEmpty && exit != null) {
      exitRects = <GridRect>[GridRect(r0: exit.r, c0: exit.c, r1: exit.r, c1: exit.c)];
    }

    final road2Raw = pickFirst(['road2Cells', 'roadBCells', 'roadLane2Cells']);
    final road2List = readList(road2Raw) ?? const <dynamic>[];
    final road2 = <int>{};
    for (final it in road2List) {
      final v = readInt(it) ?? int.tryParse(it.toString().trim());
      if (v == null) continue;
      if (v < 0 || v >= targetLen) continue;
      if (cells[v] != ParkingGridCellType.road) continue;
      road2.add(v);
    }

    return ParkingGridModel(
      rows: resolvedRows,
      cols: resolvedCols,
      cells: List.unmodifiable(cells),
      entranceGateKey: entranceKey,
      exitGateKey: exitKey,
      walls: Map.unmodifiable(walls),
      wallGroups: Map.unmodifiable(wallGroups),
      parkingAreas: List.unmodifiable(parsedAreas),
      entranceRects: List.unmodifiable(entranceRects.map((e) => e.normalized()).toList()),
      exitRects: List.unmodifiable(exitRects.map((e) => e.normalized()).toList()),
      towerRects: List.unmodifiable(towerRects.map((e) => e.normalized()).toList()),
      road2Cells: List.unmodifiable(road2.toList()..sort()),
    );
  }
}
