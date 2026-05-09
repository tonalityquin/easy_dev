part of 'tablet_grid_3d_preview.dart';

extension _ParkingGridStructuredPreviewPart on _TabletGrid3dPreviewState {
  List<_ChildRegion> _collectChildRegionsForParent(LocationModel parent) {
    final parentArea = (() {
      try {
        return _trimOrEmpty((parent as dynamic).area);
      } catch (_) {
        return '';
      }
    })();

    final regions = <_ChildRegion>[];

    for (final l in widget.locations) {
      if (!_isCompositeChildType(l.type)) continue;
      if (!_matchesParentRef(parent, l)) continue;

      final childArea = (() {
        try {
          return _trimOrEmpty((l as dynamic).area);
        } catch (_) {
          return '';
        }
      })();

      if (!_matchesAreaLoose(parentArea, childArea)) continue;

      final rect = _readChildRectFallback(l);
      if (rect == null) continue;

      final name = _trimOrEmpty(l.locationName);
      final groupName = name.isEmpty ? 'group' : name;

      regions.add(_ChildRegion(
        name: groupName,
        r0: rect.$1,
        c0: rect.$2,
        r1: rect.$3,
        c1: rect.$4,
      ));
    }

    regions.sort((a, b) => a.areaCells.compareTo(b.areaCells));
    return regions;
  }

  Widget _buildStructuredPreviewBody({
    required _PreviewEntry entry,
    required int index,
    required int count,
    required ColorScheme cs,
    required TextTheme tt,
  }) {
    final loc = entry.location;
    final nameTrimmed = _trimOrEmpty(loc.locationName);
    final ParkingGridModel? pg = loc.parkingGrid;

    if (pg == null) {
      return Column(
        children: [
          Text(
            '이 주차 구역에는 저장된 레이아웃(parkingGrid)이 없습니다.',
            textAlign: TextAlign.center,
            style: (tt.bodyMedium ?? const TextStyle(fontSize: 13))
                .copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      );
    }

    final regionsRaw = _collectChildRegionsForParent(loc);
    final regions = _applyOverlayToRegionsIfNeeded(
      parentName: nameTrimmed,
      overlay: widget.overlay,
      regions: regionsRaw,
    );

    final parentArea = (() {
      try {
        return _trimOrEmpty((loc as dynamic).area);
      } catch (_) {
        return '';
      }
    })();

    final collected = <_ChildSlot>[];
    for (final l in widget.locations) {
      if (!_isCompositeChildType(l.type)) continue;
      if (!_matchesParentRef(loc, l)) continue;

      final childArea = (() {
        try {
          return _trimOrEmpty((l as dynamic).area);
        } catch (_) {
          return '';
        }
      })();

      if (!_matchesAreaLoose(parentArea, childArea)) continue;

      final childNameTrim = _trimOrEmpty(l.locationName);
      final groupName = childNameTrim.isEmpty ? 'group' : childNameTrim;

      final parsed = _readChildSlotsFromLocation(l, groupName: groupName);
      if (parsed.isEmpty) continue;
      collected.addAll(parsed);
    }

    final childSlotByAreaId = <String, _ChildSlot>{};
    for (final s in collected) {
      final id = (s.areaId ?? '').trim();
      if (id.isEmpty) continue;
      if (s.no == null || s.no! <= 0) continue;
      childSlotByAreaId[id] = s;
    }

    final rawParkingAreas = _extractParkingAreasRawFromGrid(pg);
    final parentSlotsRaw =
        _readSlotsFromRaw(rawParkingAreas, groupName: 'parkingAreas');

    List<_ChildSlot> baseSlots;
    if (parentSlotsRaw.isNotEmpty) {
      baseSlots = parentSlotsRaw.map((s) {
        final id = (s.areaId ?? '').trim();
        final childSlot = id.isEmpty ? null : childSlotByAreaId[id];
        if (childSlot == null) {
          return s.copyWith(groupName: _pickGroupForSlot(s, regions));
        }
        return s.copyWith(
          groupName: childSlot.groupName,
          no: childSlot.no,
        );
      }).toList(growable: false);
    } else {
      baseSlots = collected;
    }

    baseSlots = _ensureSlotNumbers(baseSlots);

    final slots = _applyOverlayToSlotsIfNeeded(
      parentName: nameTrimmed,
      overlay: widget.overlay,
      slots: baseSlots,
    );

    final sortedSlots = List<_ChildSlot>.from(slots);
    sortedSlots.sort((a, b) {
      final gn = a.groupName.compareTo(b.groupName);
      if (gn != 0) return gn;
      final dr = a.r.compareTo(b.r);
      if (dr != 0) return dr;
      final dc = a.c.compareTo(b.c);
      if (dc != 0) return dc;
      final asr = a.spanR.compareTo(b.spanR);
      if (asr != 0) return asr;
      return a.spanC.compareTo(b.spanC);
    });

    final parentOverlay = widget.overlay.forParent(nameTrimmed);
    final towerStatus = parentOverlay.statusForChildAny(
      childName: kParkingOverlayTowerChildKey,
    );

    final model = _ParkingGridModel.fromParkingGridModel(
      pg,
      childSlots: sortedSlots,
      childRegions: regions,
      towerStatus: towerStatus,
    );
    final palette = _ModelPalette.fromColorScheme(cs);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [palette.canvasBgA, palette.canvasBgB],
          ),
          border: Border.all(
            color: palette.frame.withOpacity(0.85),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: _withSwipeAffordance(
          index: index,
          count: count,
          child: _TabletGrid3DView(
            model: model,
            palette: palette,
            initialViewStep: _storedViewStepForEntry(entry),
            onViewStepChanged: (step) => _storeViewStepForEntry(entry, step),
          ),
        ),
      ),
    );
  }
}

class _ModelPalette {
  final Color canvasBgA;
  final Color canvasBgB;

  final Color floorTop;
  final Color floorSideA;
  final Color floorSideB;

  final Color roadTop;
  final Color roadSideA;
  final Color roadSideB;
  final Color roadMark;

  final Color road2Top;
  final Color road2SideA;
  final Color road2SideB;
  final Color road2Mark;

  final Color parkingSlotTop;
  final Color parkingSlotSideA;
  final Color parkingSlotSideB;
  final Color parkingSlotOutline;

  final Color pillarTop;
  final Color pillarSideA;
  final Color pillarSideB;

  final Color wallTop;
  final Color wallSideA;
  final Color wallSideB;

  final Color outline;
  final Color frame;

  final Color entrance;
  final Color exit;

  final Color towerTop;
  final Color towerSideA;
  final Color towerSideB;
  final Color towerMark;

  final Color labelBorder;

  final Color regionFillA;
  final Color regionFillB;
  final Color regionBorder;

  const _ModelPalette({
    required this.canvasBgA,
    required this.canvasBgB,
    required this.floorTop,
    required this.floorSideA,
    required this.floorSideB,
    required this.roadTop,
    required this.roadSideA,
    required this.roadSideB,
    required this.roadMark,
    required this.road2Top,
    required this.road2SideA,
    required this.road2SideB,
    required this.road2Mark,
    required this.parkingSlotTop,
    required this.parkingSlotSideA,
    required this.parkingSlotSideB,
    required this.parkingSlotOutline,
    required this.pillarTop,
    required this.pillarSideA,
    required this.pillarSideB,
    required this.wallTop,
    required this.wallSideA,
    required this.wallSideB,
    required this.outline,
    required this.frame,
    required this.entrance,
    required this.exit,
    required this.towerTop,
    required this.towerSideA,
    required this.towerSideB,
    required this.towerMark,
    required this.labelBorder,
    required this.regionFillA,
    required this.regionFillB,
    required this.regionBorder,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is _ModelPalette &&
            other.canvasBgA == canvasBgA &&
            other.canvasBgB == canvasBgB &&
            other.floorTop == floorTop &&
            other.floorSideA == floorSideA &&
            other.floorSideB == floorSideB &&
            other.roadTop == roadTop &&
            other.roadSideA == roadSideA &&
            other.roadSideB == roadSideB &&
            other.roadMark == roadMark &&
            other.road2Top == road2Top &&
            other.road2SideA == road2SideA &&
            other.road2SideB == road2SideB &&
            other.road2Mark == road2Mark &&
            other.parkingSlotTop == parkingSlotTop &&
            other.parkingSlotSideA == parkingSlotSideA &&
            other.parkingSlotSideB == parkingSlotSideB &&
            other.parkingSlotOutline == parkingSlotOutline &&
            other.pillarTop == pillarTop &&
            other.pillarSideA == pillarSideA &&
            other.pillarSideB == pillarSideB &&
            other.wallTop == wallTop &&
            other.wallSideA == wallSideA &&
            other.wallSideB == wallSideB &&
            other.outline == outline &&
            other.frame == frame &&
            other.entrance == entrance &&
            other.exit == exit &&
            other.towerTop == towerTop &&
            other.towerSideA == towerSideA &&
            other.towerSideB == towerSideB &&
            other.towerMark == towerMark &&
            other.labelBorder == labelBorder &&
            other.regionFillA == regionFillA &&
            other.regionFillB == regionFillB &&
            other.regionBorder == regionBorder;
  }

  @override
  int get hashCode => Object.hashAll([
        canvasBgA,
        canvasBgB,
        floorTop,
        floorSideA,
        floorSideB,
        roadTop,
        roadSideA,
        roadSideB,
        roadMark,
        road2Top,
        road2SideA,
        road2SideB,
        road2Mark,
        parkingSlotTop,
        parkingSlotSideA,
        parkingSlotSideB,
        parkingSlotOutline,
        pillarTop,
        pillarSideA,
        pillarSideB,
        wallTop,
        wallSideA,
        wallSideB,
        outline,
        frame,
        entrance,
        exit,
        towerTop,
        towerSideA,
        towerSideB,
        towerMark,
        labelBorder,
        regionFillA,
        regionFillB,
        regionBorder,
      ]);

  factory _ModelPalette.fromColorScheme(ColorScheme cs) {
    final bg = cs.surfaceContainerLowest;
    final isLight = bg.computeLuminance() > 0.5;

    final ivory =
        _ColorUtil.mix(bg, const Color(0xFFF5F1E7), isLight ? 0.56 : 0.18);
    final warmStone =
        _ColorUtil.mix(bg, const Color(0xFFD9D2C4), isLight ? 0.44 : 0.20);
    final neutralConcrete =
        _ColorUtil.mix(bg, cs.onSurface, isLight ? 0.18 : 0.24);
    final accentBlue = _ColorUtil.ensureContrast(
      _ColorUtil.mix(cs.primary, const Color(0xFF2F6FA8), 0.52),
      bg,
      fallback: cs.primary,
      target: 2.1,
    );
    final accentBlueSoft =
        _ColorUtil.mix(accentBlue, ivory, isLight ? 0.54 : 0.28);
    final amber = _ColorUtil.ensureContrast(
      const Color(0xFFF1B824),
      bg,
      fallback: cs.tertiary,
      target: 1.9,
    );

    final canvasA = _ColorUtil.shiftLightness(ivory, isLight ? 0.01 : -0.03)
        .withOpacity(0.98);
    final canvasB = _ColorUtil.mix(ivory, warmStone, isLight ? 0.36 : 0.22)
        .withOpacity(0.98);

    final floorTop =
        _ColorUtil.mix(ivory, neutralConcrete, isLight ? 0.12 : 0.18)
            .withOpacity(0.98);
    final floorSideA =
        _ColorUtil.shiftLightness(floorTop, isLight ? -0.06 : 0.08)
            .withOpacity(0.94);
    final floorSideB =
        _ColorUtil.shiftLightness(floorTop, isLight ? -0.10 : 0.12)
            .withOpacity(0.92);

    final entryGuide = _ColorUtil.ensureContrast(
      const Color(0xFF2E9B54),
      bg,
      fallback: cs.primary,
      target: 2.4,
    ).withOpacity(0.90);
    final exitGuide = _ColorUtil.ensureContrast(
      const Color(0xFFD84A3A),
      bg,
      fallback: cs.error,
      target: 2.4,
    ).withOpacity(0.90);

    final roadTop =
        _ColorUtil.mix(floorTop, const Color(0xFFD4E1DA), isLight ? 0.52 : 0.22)
            .withOpacity(0.97);
    final roadSideA = _ColorUtil.shiftLightness(roadTop, isLight ? -0.08 : 0.10)
        .withOpacity(0.90);
    final roadSideB = _ColorUtil.shiftLightness(roadTop, isLight ? -0.13 : 0.14)
        .withOpacity(0.86);
    final roadMark = _ColorUtil.ensureContrast(
      _ColorUtil.mix(entryGuide, const Color(0xFFF7FFFA), 0.62),
      roadTop,
      fallback: entryGuide,
      target: 2.3,
    ).withOpacity(0.94);

    final road2Top =
        _ColorUtil.mix(floorTop, const Color(0xFFE5D5CD), isLight ? 0.48 : 0.20)
            .withOpacity(0.96);
    final road2SideA =
        _ColorUtil.shiftLightness(road2Top, isLight ? -0.09 : 0.08)
            .withOpacity(0.84);
    final road2SideB =
        _ColorUtil.shiftLightness(road2Top, isLight ? -0.14 : 0.12)
            .withOpacity(0.80);
    final road2Mark = _ColorUtil.ensureContrast(
      _ColorUtil.mix(exitGuide, const Color(0xFFFFF4EE), 0.28),
      road2Top,
      fallback: exitGuide,
      target: 2.2,
    ).withOpacity(0.92);

    final parkingSlotTop =
        _ColorUtil.mix(ivory, const Color(0xFFFFFFFF), isLight ? 0.48 : 0.12)
            .withOpacity(0.98);
    final parkingSlotSideA =
        _ColorUtil.shiftLightness(parkingSlotTop, isLight ? -0.05 : 0.07)
            .withOpacity(0.78);
    final parkingSlotSideB =
        _ColorUtil.shiftLightness(parkingSlotTop, isLight ? -0.09 : 0.10)
            .withOpacity(0.74);
    final parkingSlotOutline = _ColorUtil.ensureContrast(
      const Color(0xFFF9F8F5),
      parkingSlotTop,
      fallback: cs.onSurface,
      target: 1.65,
    ).withOpacity(0.98);

    final pillarTop = _ColorUtil.mix(
            const Color(0xFFCDD3D8), accentBlueSoft, isLight ? 0.16 : 0.08)
        .withOpacity(0.98);
    final pillarSideA =
        _ColorUtil.shiftLightness(pillarTop, isLight ? -0.08 : 0.10)
            .withOpacity(0.92);
    final pillarSideB =
        _ColorUtil.shiftLightness(pillarTop, isLight ? -0.13 : 0.14)
            .withOpacity(0.88);

    final wallTop =
        _ColorUtil.mix(ivory, const Color(0xFFFFFFFF), isLight ? 0.18 : 0.06)
            .withOpacity(0.98);
    final wallSideA = _ColorUtil.shiftLightness(wallTop, isLight ? -0.08 : 0.08)
        .withOpacity(0.94);
    final wallSideB = _ColorUtil.shiftLightness(wallTop, isLight ? -0.12 : 0.12)
        .withOpacity(0.90);

    final outline = _ColorUtil.ensureContrast(
      _ColorUtil.mix(
          cs.outlineVariant, const Color(0xFF4E5965), isLight ? 0.42 : 0.18),
      bg,
      fallback: cs.onSurface,
      target: 1.8,
    ).withOpacity(0.58);

    final frame = _ColorUtil.ensureContrast(
      accentBlue,
      bg,
      fallback: cs.onSurface,
      target: 2.0,
    ).withOpacity(0.28);

    final entrance = entryGuide;
    final exit = exitGuide;

    final towerTop = _ColorUtil.mix(
            accentBlueSoft, const Color(0xFFB9C8D7), isLight ? 0.24 : 0.10)
        .withOpacity(0.95);
    final towerSideA =
        _ColorUtil.shiftLightness(towerTop, isLight ? -0.08 : 0.08)
            .withOpacity(0.86);
    final towerSideB =
        _ColorUtil.shiftLightness(towerTop, isLight ? -0.12 : 0.12)
            .withOpacity(0.82);
    final towerMark = _ColorUtil.ensureContrast(
      accentBlue,
      towerTop,
      fallback: cs.primary,
      target: 2.0,
    ).withOpacity(0.92);

    final labelBorder = _ColorUtil.ensureContrast(
      accentBlue.withOpacity(0.55),
      bg,
      fallback: cs.onSurface,
      target: 1.7,
    ).withOpacity(0.55);

    final regionFillA = _ColorUtil.mix(
        const Color(0xFFDCEBFA), accentBlueSoft, isLight ? 0.46 : 0.22);
    final regionFillB =
        _ColorUtil.mix(const Color(0xFFF7E7C7), amber, isLight ? 0.28 : 0.16);
    final regionBorder = _ColorUtil.ensureContrast(
      accentBlue,
      bg,
      fallback: cs.onSurface,
      target: 2.0,
    ).withOpacity(0.42);

    return _ModelPalette(
      canvasBgA: canvasA,
      canvasBgB: canvasB,
      floorTop: floorTop,
      floorSideA: floorSideA,
      floorSideB: floorSideB,
      roadTop: roadTop,
      roadSideA: roadSideA,
      roadSideB: roadSideB,
      roadMark: roadMark,
      road2Top: road2Top,
      road2SideA: road2SideA,
      road2SideB: road2SideB,
      road2Mark: road2Mark,
      parkingSlotTop: parkingSlotTop,
      parkingSlotSideA: parkingSlotSideA,
      parkingSlotSideB: parkingSlotSideB,
      parkingSlotOutline: parkingSlotOutline,
      pillarTop: pillarTop,
      pillarSideA: pillarSideA,
      pillarSideB: pillarSideB,
      wallTop: wallTop,
      wallSideA: wallSideA,
      wallSideB: wallSideB,
      outline: outline,
      frame: frame,
      entrance: entrance,
      exit: exit,
      towerTop: towerTop,
      towerSideA: towerSideA,
      towerSideB: towerSideB,
      towerMark: towerMark,
      labelBorder: labelBorder,
      regionFillA: regionFillA,
      regionFillB: regionFillB,
      regionBorder: regionBorder,
    );
  }
}

class _ColorUtil {
  static Color mix(Color a, Color b, double t) {
    final v = t.clamp(0.0, 1.0);
    return Color.lerp(a, b, v) ?? a;
  }

  static Color shiftLightness(Color c, double delta) {
    final hsl = HSLColor.fromColor(c);
    final nextL = (hsl.lightness + delta).clamp(0.0, 1.0);
    return hsl.withLightness(nextL).toColor();
  }

  static double contrastRatio(Color a, Color b) {
    final la = a.computeLuminance();
    final lb = b.computeLuminance();
    final bright = max(la, lb);
    final dark = min(la, lb);
    return (bright + 0.05) / (dark + 0.05);
  }

  static Color ensureContrast(Color candidate, Color bg,
      {required Color fallback, double target = 2.0}) {
    if (contrastRatio(candidate, bg) >= target) return candidate;
    final isLight = bg.computeLuminance() > 0.5;
    final nudged = shiftLightness(candidate, isLight ? -0.12 : 0.12);
    if (contrastRatio(nudged, bg) >= target) return nudged;
    return fallback;
  }
}

enum _CellKind { empty, road, road2, pillar }

class _ParkingGridModel {
  static const String kUngroupedWall = '__ungrouped_wall__';

  final int rows;
  final int cols;
  final List<_CellKind> cells;
  final Map<String, String?> wallGroupIdByKey;

  final String? entranceGateKey;
  final String? exitGateKey;

  final List<GridRect> entranceRects;
  final List<GridRect> exitRects;
  final List<GridRect> towerRects;

  final ParkingSlotStatus towerStatus;

  final List<_ChildSlot> childSlots;
  final List<_ChildRegion> childRegions;

  _ParkingGridModel({
    required this.rows,
    required this.cols,
    required this.cells,
    required this.wallGroupIdByKey,
    required this.entranceGateKey,
    required this.exitGateKey,
    required this.entranceRects,
    required this.exitRects,
    required this.towerRects,
    required this.towerStatus,
    required this.childSlots,
    required this.childRegions,
  });

  int get renderSignature => Object.hash(
        rows,
        cols,
        Object.hashAll(cells),
        Object.hashAll(
            wallGroupIdByKey.entries.map((e) => Object.hash(e.key, e.value))),
        entranceGateKey,
        exitGateKey,
        Object.hashAll(
            entranceRects.map((r) => Object.hash(r.r0, r.c0, r.r1, r.c1))),
        Object.hashAll(
            exitRects.map((r) => Object.hash(r.r0, r.c0, r.r1, r.c1))),
        Object.hashAll(
            towerRects.map((r) => Object.hash(r.r0, r.c0, r.r1, r.c1))),
        towerStatus,
        Object.hashAll(childSlots.map((s) => Object.hash(
              s.groupName,
              s.kindNorm,
              s.rr0,
              s.rr1,
              s.cc0,
              s.cc1,
              s.no,
              s.status,
              s.statusFromGroup,
            ))),
        Object.hashAll(childRegions.map((r) => Object.hash(
              r.name,
              r.rr0,
              r.rr1,
              r.cc0,
              r.cc1,
              r.status,
            ))),
      );

  int idx(int r, int c) => r * cols + c;

  _CellKind cellAt(int r, int c) {
    if (r < 0 || c < 0 || r >= rows || c >= cols) return _CellKind.empty;
    final i = idx(r, c);
    if (i < 0 || i >= cells.length) return _CellKind.empty;
    return cells[i];
  }

  bool isRoadAt(int r, int c) {
    final k = cellAt(r, c);
    return k == _CellKind.road || k == _CellKind.road2;
  }

  bool isRoad2At(int r, int c) => cellAt(r, c) == _CellKind.road2;

  factory _ParkingGridModel.fromParkingGridModel(
    ParkingGridModel pg, {
    List<_ChildSlot> childSlots = const <_ChildSlot>[],
    List<_ChildRegion> childRegions = const <_ChildRegion>[],
    ParkingSlotStatus towerStatus = ParkingSlotStatus.empty,
  }) {
    final road2Set = pg.road2Cells.toSet();

    final cells = <_CellKind>[];
    for (int i = 0; i < pg.cells.length; i++) {
      final c = pg.cells[i];
      if (c == ParkingGridCellType.road) {
        cells.add(road2Set.contains(i) ? _CellKind.road2 : _CellKind.road);
      } else if (c == ParkingGridCellType.pillar) {
        cells.add(_CellKind.pillar);
      } else {
        cells.add(_CellKind.empty);
      }
    }

    final wallGroupIdByKey = <String, String?>{};
    for (final e in pg.walls.entries) {
      final key = _edgeKeyToString(e.key);
      if (key.isEmpty) continue;
      wallGroupIdByKey[key] = e.value?.toString();
    }

    return _ParkingGridModel(
      rows: pg.rows,
      cols: pg.cols,
      cells: cells,
      wallGroupIdByKey: wallGroupIdByKey,
      entranceGateKey: pg.entranceGateKey,
      exitGateKey: pg.exitGateKey,
      entranceRects: List<GridRect>.from(pg.entranceRects),
      exitRects: List<GridRect>.from(pg.exitRects),
      towerRects: List<GridRect>.from(pg.towerRects),
      towerStatus: towerStatus,
      childSlots: childSlots,
      childRegions: childRegions,
    );
  }
}

@immutable
class _Recommended3DViewConfig {
  final Mat3 rotation;
  final bool isOrtho;

  const _Recommended3DViewConfig({
    required this.rotation,
    this.isOrtho = false,
  });
}

(int r, int c, int edge)? _parseParkingGridEdgeKey(String? raw) {
  final value = (raw ?? '').trim();
  if (value.isEmpty) return null;

  final parts = value.split('|');
  if (parts.length != 3) return null;

  final r = int.tryParse(parts[0]);
  final c = int.tryParse(parts[1]);
  final edge = int.tryParse(parts[2]);
  if (r == null || c == null || edge == null) return null;
  if (edge < 0 || edge > 3) return null;
  return (r, c, edge);
}

Vec3? _parkingGridGateCenterFromEdgeKey(String? raw) {
  final parsed = _parseParkingGridEdgeKey(raw);
  if (parsed == null) return null;

  final r = parsed.$1;
  final c = parsed.$2;
  final edge = parsed.$3;

  switch (edge) {
    case 0:
      return Vec3(c + 0.5, 0, r.toDouble());
    case 1:
      return Vec3(c + 1.0, 0, r + 0.5);
    case 2:
      return Vec3(c + 0.5, 0, r + 1.0);
    case 3:
      return Vec3(c.toDouble(), 0, r + 0.5);
  }
  return null;
}

Iterable<Vec3> _parkingGridGateCentersFromRects(List<GridRect> rects) sync* {
  for (final rect in rects) {
    final normalized = rect.normalized();
    yield Vec3(
      (normalized.c0 + normalized.c1 + 1) * 0.5,
      0,
      (normalized.r0 + normalized.r1 + 1) * 0.5,
    );
  }
}

double _stabilizeSignedAxis(double value, double minAbs, double fallbackValue) {
  if (value.abs() >= minAbs) return value;
  if (value.abs() > 0.0001) {
    return value.isNegative ? -minAbs : minAbs;
  }
  return fallbackValue.isNegative ? -minAbs : minAbs;
}

Vec3 _preferredParkingGridHorizontalLook(_ParkingGridModel model) {
  final pivotX = model.cols * 0.5;
  final pivotZ = model.rows * 0.5;
  const fallback = Vec3(-0.62, 0, 0.78);

  final samples = <Vec3>[
    ..._parkingGridGateCentersFromRects(model.entranceRects),
    ..._parkingGridGateCentersFromRects(model.exitRects),
  ];

  final entranceEdgeCenter =
      _parkingGridGateCenterFromEdgeKey(model.entranceGateKey);
  if (entranceEdgeCenter != null) samples.add(entranceEdgeCenter);

  final exitEdgeCenter = _parkingGridGateCenterFromEdgeKey(model.exitGateKey);
  if (exitEdgeCenter != null) samples.add(exitEdgeCenter);

  if (samples.isEmpty) return fallback.normalized;

  double dx = 0;
  double dz = 0;
  for (final sample in samples) {
    dx += sample.x - pivotX;
    dz += sample.z - pivotZ;
  }

  dx /= samples.length;
  dz /= samples.length;

  final stabilizedX = _stabilizeSignedAxis(dx, 0.60, fallback.x);
  final stabilizedZ = _stabilizeSignedAxis(dz, 0.60, fallback.z);
  return Vec3(stabilizedX, 0, stabilizedZ).normalized;
}

int _preferredParkingGridViewStep(_ParkingGridModel model) {
  final preferred = _preferredParkingGridHorizontalLook(model);
  var bestStep = 0;
  var bestScore = double.negativeInfinity;

  for (var step = 0; step < 4; step++) {
    final forward = const Vec3(-0.78, 0.58, 0.92)
        .normalized
        .rotatedAround(const Vec3(0, -1, 0), step * (pi / 2))
        .normalized;
    final horizontal = Vec3(forward.x, 0, forward.z).normalized;
    final score = horizontal.dot(preferred);
    if (score > bestScore) {
      bestScore = score;
      bestStep = step;
    }
  }

  return bestStep;
}

_Recommended3DViewConfig _parkingGrid3DViewForYaw(double yawRadians) {
  const sceneUp = Vec3(0, -1, 0);
  final forward = const Vec3(-0.78, 0.58, 0.92)
      .normalized
      .rotatedAround(const Vec3(0, -1, 0), yawRadians)
      .normalized;

  Vec3 right = forward.cross(sceneUp);
  if (right.length <= 0.000001) {
    right = const Vec3(1, 0, 0);
  } else {
    right = right.normalized;
  }

  Vec3 up = forward.cross(right);
  if (up.length <= 0.000001) {
    up = const Vec3(0, 0, 1);
  } else {
    up = up.normalized;
  }

  return _Recommended3DViewConfig(
    rotation: Mat3.fromRows(right, up, forward),
    isOrtho: false,
  );
}

class _TabletGrid3DView extends StatefulWidget {
  final _ParkingGridModel model;
  final _ModelPalette palette;
  final int? initialViewStep;
  final ValueChanged<int>? onViewStepChanged;

  const _TabletGrid3DView({
    required this.model,
    required this.palette,
    this.initialViewStep,
    this.onViewStepChanged,
  });

  @override
  State<_TabletGrid3DView> createState() => _TabletGrid3DViewState();
}

class _TabletGrid3DViewState extends State<_TabletGrid3DView> {
  static const int _viewStepCount = 4;
  static const double _viewStepAngle = pi / 2;

  int _viewStep = 0;

  int _coerceViewStep(int value) {
    final mod = value % _viewStepCount;
    return mod < 0 ? mod + _viewStepCount : mod;
  }

  int get _normalizedViewIndex {
    final mod = _viewStep % _viewStepCount;
    return mod < 0 ? mod + _viewStepCount : mod;
  }

  void _shiftView(int delta) {
    if (!mounted) return;
    final next = _coerceViewStep(_viewStep + delta);
    if (next == _viewStep) return;
    setState(() {
      _viewStep = next;
    });
    widget.onViewStepChanged?.call(_viewStep);
  }

  void _handleViewSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0.0;
    if (velocity.abs() < 180) return;
    _shiftView(velocity < 0 ? 1 : -1);
  }

  @override
  void initState() {
    super.initState();
    _viewStep = _coerceViewStep(
      widget.initialViewStep ?? _preferredParkingGridViewStep(widget.model),
    );
  }

  @override
  void didUpdateWidget(covariant _TabletGrid3DView oldWidget) {
    super.didUpdateWidget(oldWidget);

    final incomingViewStep = widget.initialViewStep;
    if (incomingViewStep != null &&
        incomingViewStep != oldWidget.initialViewStep) {
      final coerced = _coerceViewStep(incomingViewStep);
      if (coerced != _viewStep) {
        _viewStep = coerced;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final view = _parkingGrid3DViewForYaw(_viewStep * _viewStepAngle);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: _handleViewSwipe,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(
              painter: _ParkingGrid3DPainter(
                model: widget.model,
                viewRot: view.rotation,
                cs: cs,
                isOrtho: view.isOrtho,
                palette: widget.palette,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surface.withOpacity(0.72),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.28),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.chevron_left_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant.withOpacity(0.80),
                        ),
                        const SizedBox(width: 4),
                        ...List.generate(_viewStepCount, (i) {
                          final active = i == _normalizedViewIndex;
                          return Container(
                            margin: EdgeInsets.only(
                                right: i == _viewStepCount - 1 ? 0 : 6),
                            width: active ? 16 : 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: active
                                  ? cs.primary.withOpacity(0.92)
                                  : cs.onSurfaceVariant.withOpacity(0.28),
                              borderRadius: BorderRadius.circular(999),
                            ),
                          );
                        }),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.chevron_right_rounded,
                          size: 16,
                          color: cs.onSurfaceVariant.withOpacity(0.80),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _EdgeKind { entrance, exit }

enum _RoadAxis { none, x, z, cross }

class _WallRun {
  final Vec3 a;
  final Vec3 b;

  const _WallRun(this.a, this.b);
}

class _RectXZ {
  final int x0, x1;
  final int z0, z1;

  const _RectXZ(
      {required this.x0, required this.x1, required this.z0, required this.z1});
}

class _ParkingGrid3DPainter extends CustomPainter {
  final _ParkingGridModel model;
  final Mat3 viewRot;
  final ColorScheme cs;
  final bool isOrtho;
  final _ModelPalette palette;

  _ParkingGrid3DPainter({
    required this.model,
    required this.viewRot,
    required this.cs,
    required this.isOrtho,
    required this.palette,
  });

  static const double _fitPadding = 12.0;

  static const double _yFloorBottom = 0.0;
  static const double _floorThickness = 0.10;
  static const double _yFloorTop = _yFloorBottom - _floorThickness;
  static const double _ySurfaceEps = 0.001;

  static const double _roadHeight = 0.05;
  static const double _pillarHeightFull = 0.94;
  static const double _pillarHeightLod = 0.12;
  static const double _wallHeightFull = 0.78;
  static const double _wallHeightLod = 0.08;

  static const double _childSlotHeight = 0.16;
  static const double _childSlotInset = 0.18;
  static const double _childSlotZBias = 0.0017;

  static const double _wallBaseThickness = 0.06;
  static const double _wallTopHighlightStripPx = 1.6;
  static const double _wallTopViewMinThicknessPx = 3.0;

  late Mat3 _r;
  late double _fitScale;
  late Offset _fitOffset;

  late Vec3 _pivot;
  late double _cameraZ;

  int get _sceneCellCount => model.rows * model.cols;

  bool get _useMinimalDetailMode =>
      _sceneCellCount >= 120 ||
      model.childSlots.length >= 28 ||
      model.childRegions.length >= 10 ||
      model.towerRects.length >= 2;

  bool get _useCompactRoadMarks =>
      _useMinimalDetailMode || _sceneCellCount >= 90;

  Vec3 _toPivotSpace(Vec3 v) => Vec3(v.x - _pivot.x, v.y, v.z - _pivot.z);

  Offset _project(Vec3 v) {
    final pv = _toPivotSpace(v);
    final p = _r.transform(pv);

    if (isOrtho) {
      return Offset(p.x * _fitScale, p.y * _fitScale) + _fitOffset;
    }

    final z = p.z + _cameraZ;
    final k = 1.0 / max(0.0001, z);
    return Offset(p.x * k * _fitScale, p.y * k * _fitScale) + _fitOffset;
  }

  double _depth(Vec3 v) => _r.transform(_toPivotSpace(v)).z;

  void _computeFit(Size size) {
    _r = viewRot;

    if (model.rows <= 0 || model.cols <= 0) {
      _fitScale = 1.0;
      _fitOffset = Offset(size.width * 0.5, size.height * 0.5);
      _pivot = const Vec3(0, 0, 0);
      _cameraZ = 8.0;
      return;
    }

    final w = model.cols.toDouble();
    final h = model.rows.toDouble();
    _pivot = Vec3(w * 0.5, 0, h * 0.5);

    final maxDim = max(w, h);
    _cameraZ = isOrtho ? max(8.0, maxDim * 2.2) : max(6.0, maxDim * 1.48);

    const topY = 0.0;
    final bottomY = isOrtho ? -0.34 : -1.82;

    final samplesWorld = <Vec3>[
      Vec3(0, topY, 0),
      Vec3(w, topY, 0),
      Vec3(w, topY, h),
      Vec3(0, topY, h),
      Vec3(0, bottomY, 0),
      Vec3(w, bottomY, 0),
      Vec3(w, bottomY, h),
      Vec3(0, bottomY, h),
    ];

    double minX = double.infinity, maxX = -double.infinity;
    double minY2 = double.infinity, maxY2 = -double.infinity;

    for (final vw in samplesWorld) {
      final p = _r.transform(_toPivotSpace(vw));

      double sx, sy;
      if (isOrtho) {
        sx = p.x;
        sy = p.y;
      } else {
        final z = p.z + _cameraZ;
        final k = 1.0 / max(0.0001, z);
        sx = p.x * k;
        sy = p.y * k;
      }

      if (sx < minX) minX = sx;
      if (sx > maxX) maxX = sx;
      if (sy < minY2) minY2 = sy;
      if (sy > maxY2) maxY2 = sy;
    }

    final spanX = max(0.0001, maxX - minX);
    final spanY = max(0.0001, maxY2 - minY2);

    final availW = max(1.0, size.width - _fitPadding * 2);
    final availH = max(1.0, size.height - _fitPadding * 2);

    _fitScale = min(availW / spanX, availH / spanY) * (isOrtho ? 1.0 : 1.08);

    final midX = (minX + maxX) * 0.5;
    final midY = (minY2 + maxY2) * 0.5;

    final center = Offset(
      size.width * 0.5,
      isOrtho ? size.height * 0.5 : size.height * 0.605,
    );
    _fitOffset = center - Offset(midX * _fitScale, midY * _fitScale);
  }

  _RoadAxis _roadAxisForCell(int r, int c) {
    if (!model.isRoadAt(r, c)) return _RoadAxis.none;
    final n = model.isRoadAt(r - 1, c);
    final s = model.isRoadAt(r + 1, c);
    final w = model.isRoadAt(r, c - 1);
    final e = model.isRoadAt(r, c + 1);

    final hasZ = n || s;
    final hasX = w || e;

    if (hasZ && hasX) return _RoadAxis.cross;
    if (hasZ) return _RoadAxis.z;
    if (hasX) return _RoadAxis.x;
    return _RoadAxis.z;
  }

  Vec3 _leftOfTravel(Vec3 d) {
    final n = Vec3(d.z, 0, -d.x);
    return n.length <= 0.000001 ? const Vec3(1, 0, 0) : n.normalized;
  }

  Vec3 _rightOfTravel(Vec3 d) {
    final n = Vec3(-d.z, 0, d.x);
    return n.length <= 0.000001 ? const Vec3(-1, 0, 0) : n.normalized;
  }

  Vec3 _majorAxisDirection(Vec3 v, {required Vec3 fallback}) {
    if (v.length <= 0.000001) return fallback;
    if (v.x.abs() >= v.z.abs()) {
      final sx = v.x >= 0 ? 1.0 : -1.0;
      return Vec3(sx, 0, 0);
    }
    final sz = v.z >= 0 ? 1.0 : -1.0;
    return Vec3(0, 0, sz);
  }

  _RoadAxis _dominantRoadAxisForRect(int rr0, int rr1, int cc0, int cc1) {
    int scoreX = 0;
    int scoreZ = 0;
    for (int r = max(0, rr0 - 1); r <= min(model.rows - 1, rr1 + 1); r++) {
      for (int c = max(0, cc0 - 1); c <= min(model.cols - 1, cc1 + 1); c++) {
        final axis = _roadAxisForCell(r, c);
        switch (axis) {
          case _RoadAxis.x:
            scoreX += 2;
            break;
          case _RoadAxis.z:
            scoreZ += 2;
            break;
          case _RoadAxis.cross:
            scoreX += 1;
            scoreZ += 1;
            break;
          case _RoadAxis.none:
            break;
        }
      }
    }
    if (scoreX == 0 && scoreZ == 0) {
      final rectW = cc1 - cc0 + 1;
      final rectH = rr1 - rr0 + 1;
      return rectW >= rectH ? _RoadAxis.x : _RoadAxis.z;
    }
    return scoreX >= scoreZ ? _RoadAxis.x : _RoadAxis.z;
  }

  int? _adjacentRoadSideIndexForGateRect({
    required int rr0,
    required int rr1,
    required int cc0,
    required int cc1,
  }) {
    int topHits = 0;
    int rightHits = 0;
    int bottomHits = 0;
    int leftHits = 0;

    void addHit(void Function() inc, int r, int c) {
      if (!model.isRoadAt(r, c)) return;
      inc();
    }

    for (int c = cc0; c <= cc1; c++) {
      addHit(() => topHits++, rr0 - 1, c);
      addHit(() => bottomHits++, rr1 + 1, c);
    }
    for (int r = rr0; r <= rr1; r++) {
      addHit(() => leftHits++, r, cc0 - 1);
      addHit(() => rightHits++, r, cc1 + 1);
    }

    final counts = <int>[topHits, rightHits, bottomHits, leftHits];
    final occupied = <int>[];
    for (int i = 0; i < counts.length; i++) {
      if (counts[i] > 0) occupied.add(i);
    }
    if (occupied.length != 1) return null;
    return occupied.first;
  }

  Vec3? _adjacentRoadDirectionForGateRect({
    required int rr0,
    required int rr1,
    required int cc0,
    required int cc1,
  }) {
    final sideIndex = _adjacentRoadSideIndexForGateRect(
      rr0: rr0,
      rr1: rr1,
      cc0: cc0,
      cc1: cc1,
    );
    if (sideIndex == null) return null;
    switch (sideIndex) {
      case 0:
        return const Vec3(0, 0, -1);
      case 1:
        return const Vec3(1, 0, 0);
      case 2:
        return const Vec3(0, 0, 1);
      case 3:
        return const Vec3(-1, 0, 0);
    }
    return null;
  }

  Vec3 _thresholdCenterForGateRect({
    required int rr0,
    required int rr1,
    required int cc0,
    required int cc1,
  }) {
    final midX = (cc0 + cc1 + 1) * 0.5;
    final midZ = (rr0 + rr1 + 1) * 0.5;
    final sideIndex = _adjacentRoadSideIndexForGateRect(
      rr0: rr0,
      rr1: rr1,
      cc0: cc0,
      cc1: cc1,
    );
    switch (sideIndex) {
      case 0:
        return Vec3(midX, 0, rr0.toDouble());
      case 1:
        return Vec3((cc1 + 1).toDouble(), 0, midZ);
      case 2:
        return Vec3(midX, 0, (rr1 + 1).toDouble());
      case 3:
        return Vec3(cc0.toDouble(), 0, midZ);
      default:
        return Vec3(midX, 0, midZ);
    }
  }

  Vec3 _travelDirectionForGateRect({
    required int rr0,
    required int rr1,
    required int cc0,
    required int cc1,
    required _EdgeKind kind,
  }) {
    final adjacentRoad = _adjacentRoadDirectionForGateRect(
      rr0: rr0,
      rr1: rr1,
      cc0: cc0,
      cc1: cc1,
    );
    if (adjacentRoad != null) {
      return kind == _EdgeKind.entrance ? adjacentRoad : adjacentRoad * -1.0;
    }

    final midX = (cc0 + cc1 + 1) * 0.5;
    final midZ = (rr0 + rr1 + 1) * 0.5;
    final axis = _dominantRoadAxisForRect(rr0, rr1, cc0, cc1);
    final topGap = rr0.toDouble();
    final rightGap = (model.cols - 1 - cc1).toDouble();
    final bottomGap = (model.rows - 1 - rr1).toDouble();
    final leftGap = cc0.toDouble();

    final perimeterDistances = <(double, Vec3)>[
      (topGap, const Vec3(0, 0, 1)),
      (rightGap, const Vec3(-1, 0, 0)),
      (bottomGap, const Vec3(0, 0, -1)),
      (leftGap, const Vec3(1, 0, 0)),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    Vec3 inward = perimeterDistances.first.$2;
    final nearestGap = perimeterDistances.first.$1;
    final toCenter = Vec3(_pivot.x - midX, 0, _pivot.z - midZ);

    if (nearestGap > 1.35) {
      if (axis == _RoadAxis.x) {
        final sign = toCenter.x.abs() >= 0.001
            ? (toCenter.x >= 0 ? 1.0 : -1.0)
            : inward.x;
        inward = Vec3(sign == 0 ? 1.0 : sign, 0, 0);
      } else {
        final sign = toCenter.z.abs() >= 0.001
            ? (toCenter.z >= 0 ? 1.0 : -1.0)
            : inward.z;
        inward = Vec3(0, 0, sign == 0 ? 1.0 : sign);
      }
    } else {
      if (axis == _RoadAxis.x && inward.x.abs() < 0.5) {
        final sign =
            toCenter.x.abs() >= 0.001 ? (toCenter.x >= 0 ? 1.0 : -1.0) : 1.0;
        inward = Vec3(sign, 0, 0);
      } else if (axis == _RoadAxis.z && inward.z.abs() < 0.5) {
        final sign =
            toCenter.z.abs() >= 0.001 ? (toCenter.z >= 0 ? 1.0 : -1.0) : 1.0;
        inward = Vec3(0, 0, sign);
      }
    }

    return kind == _EdgeKind.entrance ? inward : inward * -1.0;
  }

  Vec3 _inwardNormalForEdgeKey(String key) {
    final parsed = _parseEdgeKey(key);
    if (parsed == null) return const Vec3(0, 0, 1);
    final edge = parsed.$3;
    switch (edge) {
      case 0:
        return const Vec3(0, 0, 1);
      case 1:
        return const Vec3(-1, 0, 0);
      case 2:
        return const Vec3(0, 0, -1);
      case 3:
        return const Vec3(1, 0, 0);
      default:
        return const Vec3(0, 0, 1);
    }
  }

  Vec3 _towerFrontDirectionForRect(int rr0, int rr1, int cc0, int cc1) {
    final cx = (cc0 + cc1 + 1) * 0.5;
    final cz = (rr0 + rr1 + 1) * 0.5;
    double bestDist2 = double.infinity;
    Vec3? best;
    for (int r = max(0, rr0 - 4); r <= min(model.rows - 1, rr1 + 4); r++) {
      for (int c = max(0, cc0 - 4); c <= min(model.cols - 1, cc1 + 4); c++) {
        if (!model.isRoadAt(r, c)) continue;
        final rcx = c + 0.5;
        final rcz = r + 0.5;
        final dx = rcx - cx;
        final dz = rcz - cz;
        final d2 = dx * dx + dz * dz;
        if (d2 < bestDist2) {
          bestDist2 = d2;
          best = Vec3(dx, 0, dz);
        }
      }
    }
    if (best != null && best.length > 0.000001) {
      return _majorAxisDirection(best, fallback: const Vec3(0, 0, 1));
    }
    final towardCenter = Vec3(_pivot.x - cx, 0, _pivot.z - cz);
    return _majorAxisDirection(towardCenter, fallback: const Vec3(0, 0, 1));
  }

  bool _isPerimeterEdgeValid(int r, int c, int edge) {
    if (model.rows <= 0 || model.cols <= 0) return false;
    if (r < 0 || r >= model.rows || c < 0 || c >= model.cols) return false;

    final onPerimeter =
        r == 0 || r == model.rows - 1 || c == 0 || c == model.cols - 1;
    if (!onPerimeter) return false;

    switch (edge) {
      case 0:
        return r == 0;
      case 1:
        return c == model.cols - 1;
      case 2:
        return r == model.rows - 1;
      case 3:
        return c == 0;
      default:
        return false;
    }
  }

  double _wallThicknessForView() {
    if (!isOrtho) return _wallBaseThickness;
    final needWorld = (_wallTopViewMinThicknessPx / max(0.0001, _fitScale));
    return max(_wallBaseThickness, needWorld);
  }

  double _wallHighlightStripWorld(double thickness) {
    final pxToWorld = _wallTopHighlightStripPx / max(0.0001, _fitScale);
    return (max(pxToWorld, thickness * 0.12)).clamp(0.008, thickness * 0.28);
  }

  bool _isObstacleCell(_CellKind k) =>
      (k == _CellKind.road || k == _CellKind.road2 || k == _CellKind.pillar);

  @override
  void paint(Canvas canvas, Size size) {
    if (model.rows <= 0 || model.cols <= 0) {
      final tp = TextPainter(
        text: TextSpan(
            text: '레이아웃 데이터가 없습니다.',
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12)),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: size.width - 16);
      tp.paint(canvas, Offset(8, size.height * 0.5 - 10));
      return;
    }

    _computeFit(size);

    final groundTopFaces = <_FacePaint>[];
    final faces = <_FacePaint>[];
    final labels = <_TextAnchor>[];
    final alerts = <_AlertOverlay>[];

    final floorRects = _buildFloorRectsExceptRoad();
    for (final r in floorRects) {
      final res = _buildFloorRectFaces(
        x0: r.x0.toDouble(),
        x1: r.x1.toDouble(),
        z0: r.z0.toDouble(),
        z1: r.z1.toDouble(),
      );

      if (res.faces.isNotEmpty) {
        groundTopFaces.add(res.faces.first);
        if (res.faces.length > 1) faces.addAll(res.faces.skip(1));
      }
    }

    for (int r = 0; r < model.rows; r++) {
      for (int c = 0; c < model.cols; c++) {
        final kind = model.cellAt(r, c);
        final base = Vec3(c.toDouble(), 0, r.toDouble());

        if (kind == _CellKind.road || kind == _CellKind.road2) {
          final axis = _roadAxisForCell(r, c);
          faces.addAll(_buildRoadFaces(
                  base: base, axis: axis, isRoad2: kind == _CellKind.road2)
              .faces);
        } else if (kind == _CellKind.pillar) {
          faces.addAll(_buildPillarFaces(base: base).faces);
        }
      }
    }

    if (model.towerRects.isNotEmpty) {
      final res = _buildTowerRects();
      faces.addAll(res.faces);
      labels.addAll(res.labels);
    }

    final wallRuns = _buildWallRunsByGroup();
    for (final run in wallRuns) {
      faces.addAll(_buildWallRunFaces(a: run.a, b: run.b).faces);
    }

    if (model.childRegions.isNotEmpty) {
      faces.addAll(_buildChildRegions().faces);
    }

    if (model.childSlots.isNotEmpty) {
      final res = _buildChildSlots();
      faces.addAll(res.faces);
      labels.addAll(res.labels);
      alerts.addAll(res.alerts);
    }

    final hasGateRects =
        model.entranceRects.isNotEmpty || model.exitRects.isNotEmpty;

    if (model.entranceRects.isNotEmpty) {
      final res =
          _buildGateRects(rects: model.entranceRects, kind: _EdgeKind.entrance);
      faces.addAll(res.faces);
      labels.addAll(res.labels);
    }
    if (model.exitRects.isNotEmpty) {
      final res = _buildGateRects(rects: model.exitRects, kind: _EdgeKind.exit);
      faces.addAll(res.faces);
      labels.addAll(res.labels);
    }

    if (!hasGateRects) {
      final entranceKey = model.entranceGateKey?.trim();
      final exitKey = model.exitGateKey?.trim();

      if (entranceKey != null && entranceKey.isNotEmpty) {
        final edge = _edgeFromKey(entranceKey);
        if (edge != null) {
          final res = _buildGate(edge: edge, kind: _EdgeKind.entrance);
          faces.addAll(res.faces);
          labels.addAll(res.labels);
        }
      }
      if (exitKey != null && exitKey.isNotEmpty) {
        final edge = _edgeFromKey(exitKey);
        if (edge != null) {
          final res = _buildGate(edge: edge, kind: _EdgeKind.exit);
          faces.addAll(res.faces);
          labels.addAll(res.labels);
        }
      }
    }

    final shouldPaintLabels = !_useMinimalDetailMode;
    final fillPaint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = palette.outline;

    for (final f in groundTopFaces) {
      final path = Path()..addPolygon(f.pts2, true);
      fillPaint.color = f.fill;
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }

    faces.sort((a, b) => b.zKey.compareTo(a.zKey));
    for (final f in faces) {
      final path = Path()..addPolygon(f.pts2, true);
      fillPaint.color = f.fill;
      canvas.drawPath(path, fillPaint);
      canvas.drawPath(path, strokePaint);
    }

    if (alerts.isNotEmpty) {
      alerts.sort((a, b) => b.zKey.compareTo(a.zKey));
      final alertFill = Paint()..style = PaintingStyle.fill;
      final alertStroke = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..color = const Color(0x80FFFFFF);
      final alertCore = Paint()..style = PaintingStyle.fill;
      for (final a in alerts) {
        final path = Path()..addPolygon(a.pts2, true);
        alertFill.color = const Color(0xD9FF7A1A);
        canvas.drawPath(path, alertFill);
        canvas.drawPath(path, alertStroke);
        alertCore.color = const Color(0xF5FFF1E0);
        canvas.drawCircle(a.center2, 2.4, alertCore);
      }
    }

    _drawFootprintFrame(canvas);

    if (shouldPaintLabels) {
      labels.sort((a, b) => b.zKey.compareTo(a.zKey));
      for (final a in labels) {
        _paintLabel(canvas, a);
      }
    }
  }

  _TileResult _buildChildRegions() {
    final faces = <_FacePaint>[];

    final bg = cs.surfaceContainerLowest;
    final isLightTheme = bg.computeLuminance() > 0.5;

    for (final r in model.childRegions) {
      final rr0 = r.rr0.clamp(0, model.rows - 1);
      final rr1 = r.rr1.clamp(0, model.rows - 1);
      final cc0 = r.cc0.clamp(0, model.cols - 1);
      final cc1 = r.cc1.clamp(0, model.cols - 1);

      if (rr1 < rr0 || cc1 < cc0) continue;

      final x0 = cc0.toDouble();
      final x1 = (cc1 + 1).toDouble();
      final z0 = rr0.toDouble();
      final z1 = (rr1 + 1).toDouble();

      final t = _stableHash01(r.name);
      final base = _ColorUtil.mix(palette.regionFillA, palette.regionFillB, t);
      final c = _ColorUtil.shiftLightness(base, isLightTheme ? -0.02 : 0.02);

      double opacity;
      switch (r.status) {
        case ParkingSlotStatus.parked:
          opacity = isOrtho ? 0.12 : 0.10;
          break;
        case ParkingSlotStatus.departureRequest:
          opacity = isOrtho ? 0.14 : 0.12;
          break;
        case ParkingSlotStatus.parkingRequest:
          opacity = isOrtho ? 0.13 : 0.11;
          break;
        case ParkingSlotStatus.empty:
          opacity = isOrtho ? 0.08 : 0.07;
          break;
      }

      final y = _yFloorTop - 0.0009;

      final p0 = Vec3(x0, y, z0);
      final p1 = Vec3(x1, y, z0);
      final p2 = Vec3(x1, y, z1);
      final p3 = Vec3(x0, y, z1);

      faces.add(_FacePaint(
        pts2: [_project(p0), _project(p1), _project(p2), _project(p3)],
        fill: c.withOpacity(opacity),
        zKey: _avgDepth([p0, p1, p2, p3]) + 0.00005,
      ));
    }

    return _TileResult(faces: faces);
  }

  _EdgeResult _buildChildSlots() {
    final faces = <_FacePaint>[];
    final labels = <_TextAnchor>[];
    final alerts = <_AlertOverlay>[];

    final bg = cs.surfaceContainerLowest;
    final isLightTheme = bg.computeLuminance() > 0.5;

    bool overlapsObstacleRect({
      required int rr0,
      required int rr1,
      required int cc0,
      required int cc1,
    }) {
      for (int rr = rr0; rr <= rr1; rr++) {
        for (int cc = cc0; cc <= cc1; cc++) {
          final k = model.cellAt(rr, cc);
          if (_isObstacleCell(k)) return true;
        }
      }

      if (model.towerRects.isNotEmpty) {
        for (final raw in model.towerRects) {
          final t = raw.normalized();
          final tr0 = t.r0.clamp(0, model.rows - 1);
          final tr1 = t.r1.clamp(0, model.rows - 1);
          final tc0 = t.c0.clamp(0, model.cols - 1);
          final tc1 = t.c1.clamp(0, model.cols - 1);
          final overlapRow = !(rr1 < tr0 || rr0 > tr1);
          final overlapCol = !(cc1 < tc0 || cc0 > tc1);
          if (overlapRow && overlapCol) return true;
        }
      }

      return false;
    }

    const departRed = Color(0xFFC62828);
    const reqAmber = Color(0xFFE09A00);
    const parkedBlue = Color(0xFF2F6FA8);

    Color statusColor(ParkingSlotStatus s) {
      switch (s) {
        case ParkingSlotStatus.departureRequest:
          return _ColorUtil.ensureContrast(departRed, palette.parkingSlotTop,
                  fallback: cs.error, target: 2.0)
              .withOpacity(0.96);
        case ParkingSlotStatus.parkingRequest:
          return _ColorUtil.ensureContrast(reqAmber, palette.parkingSlotTop,
                  fallback: cs.tertiary, target: 2.0)
              .withOpacity(0.94);
        case ParkingSlotStatus.parked:
          return _ColorUtil.ensureContrast(parkedBlue, palette.parkingSlotTop,
                  fallback: cs.primary, target: 2.0)
              .withOpacity(0.90);
        case ParkingSlotStatus.empty:
          return palette.parkingSlotOutline.withOpacity(0.0);
      }
    }

    void addTopRect({
      required double x0,
      required double x1,
      required double z0,
      required double z1,
      required double y,
      required Color fill,
      required double zKey,
    }) {
      final p0 = Vec3(x0, y, z0);
      final p1 = Vec3(x1, y, z0);
      final p2 = Vec3(x1, y, z1);
      final p3 = Vec3(x0, y, z1);
      faces.add(_FacePaint(
        pts2: [_project(p0), _project(p1), _project(p2), _project(p3)],
        fill: fill,
        zKey: zKey,
      ));
    }


    Color slotCategoryBaseColor(_ChildSlot slot) {
      switch (slot.shortKindLabel) {
        case '경':
          return _ColorUtil.ensureContrast(
            const Color(0xFF64B5F6),
            palette.floorTop,
            fallback: const Color(0xFF1565C0),
            target: 1.5,
          );
        case '일':
          return _ColorUtil.ensureContrast(
            cs.secondary,
            palette.floorTop,
            fallback: cs.secondary,
            target: 1.5,
          );
        case '확A':
        case '확B':
          return _ColorUtil.ensureContrast(
            const Color(0xFFFFD54F),
            palette.floorTop,
            fallback: const Color(0xFFF9A825),
            target: 1.5,
          );
        case 'EV':
        case 'EV경':
        case 'EV일':
        case 'EV확A':
        case 'EV확B':
          return _ColorUtil.ensureContrast(
            const Color(0xFF66BB6A),
            palette.floorTop,
            fallback: const Color(0xFF2E7D32),
            target: 1.5,
          );
        case '임A':
        case '임B':
          return _ColorUtil.ensureContrast(
            const Color(0xFFF48FB1),
            palette.floorTop,
            fallback: const Color(0xFFC2185B),
            target: 1.5,
          );
        case '장':
        case '장일':
        case '장확A':
        case '장확B':
          return _ColorUtil.ensureContrast(
            const Color(0xFF9575CD),
            palette.floorTop,
            fallback: const Color(0xFF512DA8),
            target: 1.5,
          );
        default:
          return palette.parkingSlotTop;
      }
    }

    for (int i = 0; i < model.childSlots.length; i++) {
      final s = model.childSlots[i];

      if (s.rr1 < 0 ||
          s.cc1 < 0 ||
          s.rr0 >= model.rows ||
          s.cc0 >= model.cols) {
        continue;
      }

      final rr0 = s.rr0.clamp(0, model.rows - 1);
      final rr1 = s.rr1.clamp(0, model.rows - 1);
      final cc0 = s.cc0.clamp(0, model.cols - 1);
      final cc1 = s.cc1.clamp(0, model.cols - 1);

      if (overlapsObstacleRect(rr0: rr0, rr1: rr1, cc0: cc0, cc1: cc1)) {
        continue;
      }

      final (srN, scN) = s.normalizedSpan;
      final bool fromGroupHint = s.statusFromGroup;
      final bool isDeparture = s.status == ParkingSlotStatus.departureRequest;
      final bool showVehicle =
          s.status == ParkingSlotStatus.parked || isDeparture;

      final cellX0 = cc0.toDouble();
      final cellX1 = (cc1 + 1).toDouble();
      final cellZ0 = rr0.toDouble();
      final cellZ1 = (rr1 + 1).toDouble();

      final spanMin = min(cellX1 - cellX0, cellZ1 - cellZ0);
      final inset = min(_childSlotInset * 0.94, spanMin * 0.16);

      double x0 = cellX0 + inset;
      double x1 = cellX1 - inset;
      double z0 = cellZ0 + inset;
      double z1 = cellZ1 - inset;

      if (x1 <= x0 + 0.08 || z1 <= z0 + 0.08) {
        final inset2 = min(0.12, spanMin * 0.12);
        x0 = cellX0 + inset2;
        x1 = cellX1 - inset2;
        z0 = cellZ0 + inset2;
        z1 = cellZ1 - inset2;
      }
      if (x1 <= x0 + 0.02 || z1 <= z0 + 0.02) continue;

      final localJitter = ((i % 9) - 4) / 260.0;
      final slotFillBase = _ColorUtil.shiftLightness(
        slotCategoryBaseColor(s),
        (isLightTheme ? 1 : -1) * localJitter,
      );

      double fillOpacity;
      switch (s.status) {
        case ParkingSlotStatus.parked:
          fillOpacity = isOrtho ? 0.28 : 0.22;
          break;
        case ParkingSlotStatus.departureRequest:
          fillOpacity = isOrtho ? 0.34 : 0.28;
          break;
        case ParkingSlotStatus.parkingRequest:
          fillOpacity = isOrtho ? 0.30 : 0.24;
          break;
        case ParkingSlotStatus.empty:
          fillOpacity = isOrtho ? 0.20 : 0.16;
          break;
      }
      if (fromGroupHint) fillOpacity *= 0.82;

      final topColor = slotFillBase.withOpacity(fillOpacity);
      final yTop = _yFloorTop - 0.0010;
      final p0 = Vec3(x0, yTop, z0);
      final p1 = Vec3(x1, yTop, z0);
      final p2 = Vec3(x1, yTop, z1);
      final p3 = Vec3(x0, yTop, z1);
      final topZ = _avgDepth([p0, p1, p2, p3]) + _childSlotZBias;

      faces.add(_FacePaint(
        pts2: [_project(p0), _project(p1), _project(p2), _project(p3)],
        fill: topColor,
        zKey: topZ,
      ));

      final outlineColor = (isDeparture
              ? statusColor(ParkingSlotStatus.departureRequest)
              : palette.parkingSlotOutline)
          .withOpacity(fromGroupHint ? 0.56 : 0.94);
      final border = min(x1 - x0, z1 - z0) * 0.055;
      final borderW = border.clamp(0.016, 0.034);
      final yOutline = yTop - 0.0009;

      addTopRect(
        x0: x0,
        x1: x1,
        z0: z0,
        z1: z0 + borderW,
        y: yOutline,
        fill: outlineColor,
        zKey: topZ + 0.00060,
      );
      addTopRect(
        x0: x0,
        x1: x1,
        z0: z1 - borderW,
        z1: z1,
        y: yOutline,
        fill: outlineColor,
        zKey: topZ + 0.00061,
      );
      addTopRect(
        x0: x0,
        x1: x0 + borderW,
        z0: z0 + borderW,
        z1: z1 - borderW,
        y: yOutline,
        fill: outlineColor,
        zKey: topZ + 0.00062,
      );
      addTopRect(
        x0: x1 - borderW,
        x1: x1,
        z0: z0 + borderW,
        z1: z1 - borderW,
        y: yOutline,
        fill: outlineColor,
        zKey: topZ + 0.00063,
      );

      final headBarColor = s.status == ParkingSlotStatus.empty
          ? _ColorUtil.mix(palette.outline, palette.parkingSlotTop, 0.35)
              .withOpacity(0.34)
          : statusColor(s.status).withOpacity(fromGroupHint ? 0.56 : 0.78);
      final yMark = yTop - 0.0010;
      final spanW = x1 - x0;
      final spanH = z1 - z0;
      final alongX = spanW >= spanH;
      if (alongX) {
        addTopRect(
          x0: x1 - max(0.10, spanW * 0.16),
          x1: x1 - borderW * 0.8,
          z0: z0 + borderW * 1.2,
          z1: z1 - borderW * 1.2,
          y: yMark,
          fill: headBarColor,
          zKey: topZ + 0.00068,
        );
      } else {
        addTopRect(
          x0: x0 + borderW * 1.2,
          x1: x1 - borderW * 1.2,
          z0: z1 - max(0.10, spanH * 0.16),
          z1: z1 - borderW * 0.8,
          y: yMark,
          fill: headBarColor,
          zKey: topZ + 0.00068,
        );
      }

      final centerLine = Colors.white.withOpacity(fromGroupHint ? 0.22 : 0.34);
      if (!showVehicle) {
        if (alongX) {
          addTopRect(
            x0: x0 + spanW * 0.16,
            x1: x1 - spanW * 0.16,
            z0: (z0 + z1) * 0.5 - 0.012,
            z1: (z0 + z1) * 0.5 + 0.012,
            y: yMark,
            fill: centerLine,
            zKey: topZ + 0.00056,
          );
        } else {
          addTopRect(
            x0: (x0 + x1) * 0.5 - 0.012,
            x1: (x0 + x1) * 0.5 + 0.012,
            z0: z0 + spanH * 0.16,
            z1: z1 - spanH * 0.16,
            y: yMark,
            fill: centerLine,
            zKey: topZ + 0.00056,
          );
        }
      }

      if (!showVehicle && s.status == ParkingSlotStatus.parkingRequest) {
        final mark =
            statusColor(s.status).withOpacity(fromGroupHint ? 0.54 : 0.82);
        final cx = (x0 + x1) * 0.5;
        final cz = (z0 + z1) * 0.5;
        final thin = min(spanW, spanH) * 0.18;
        final stripe = thin.clamp(0.03, 0.10);
        if (srN == 1 && scN == 2) {
          addTopRect(
            x0: x0 + 0.06,
            x1: x1 - 0.06,
            z0: cz - stripe * 0.5,
            z1: cz + stripe * 0.5,
            y: yMark,
            fill: mark,
            zKey: topZ + 0.00072,
          );
        } else if (srN == 2 && scN == 1) {
          addTopRect(
            x0: cx - stripe * 0.5,
            x1: cx + stripe * 0.5,
            z0: z0 + 0.06,
            z1: z1 - 0.06,
            y: yMark,
            fill: mark,
            zKey: topZ + 0.00072,
          );
        } else {
          addTopRect(
            x0: cx - stripe * 0.5,
            x1: cx + stripe * 0.5,
            z0: cz - stripe * 0.5,
            z1: cz + stripe * 0.5,
            y: yMark,
            fill: mark,
            zKey: topZ + 0.00072,
          );
        }
      }

      if (showVehicle) {
        final vehicleRes = _buildVehicleOnSlot(
          x0: x0,
          x1: x1,
          z0: z0,
          z1: z1,
          yFloor: yTop,
          spanR: srN,
          spanC: scN,
          seed: '${s.groupName}:${s.no ?? i}:${s.kindNorm}',
          fromGroupHint: fromGroupHint,
          isDeparture: isDeparture,
          lowDetail: _useMinimalDetailMode,
        );
        faces.addAll(vehicleRes.faces);
      }

      final slotLabel = s.badgeLabel;
      if (slotLabel.isNotEmpty) {
        final cxLabel = (x0 + x1) * 0.5;
        final czLabel = (z0 + z1) * 0.5;
        final labelPos = _project(Vec3(cxLabel, yTop - 0.0022, czLabel));
        labels.add(
          _TextAnchor(
            text: slotLabel,
            pos: labelPos,
            zKey: topZ + 0.0020,
            textColor: _ColorUtil.ensureContrast(
              cs.onSurface,
              topColor,
              fallback: cs.onSurface,
              target: 2.0,
            ),
            bgColor: topColor.withOpacity(0.72),
            borderColor: cs.outlineVariant.withOpacity(0.82),
          ),
        );
      }

      if (isDeparture) {
        final cx = (x0 + x1) * 0.5;
        final cz = (z0 + z1) * 0.5;
        final major = max(0.12, min(0.28, (alongX ? spanW : spanH) * 0.22));
        final minor = max(0.05, min(0.12, (alongX ? spanH : spanW) * 0.18));
        final ay = yTop - 0.0014;
        late final List<Vec3> pts3;
        if (alongX) {
          pts3 = <Vec3>[
            Vec3(cx - major * 0.55, ay, cz - minor * 0.55),
            Vec3(cx + major * 0.02, ay, cz - minor * 0.55),
            Vec3(cx + major * 0.02, ay, cz - minor),
            Vec3(cx + major * 0.72, ay, cz),
            Vec3(cx + major * 0.02, ay, cz + minor),
            Vec3(cx + major * 0.02, ay, cz + minor * 0.55),
            Vec3(cx - major * 0.55, ay, cz + minor * 0.55),
          ];
        } else {
          pts3 = <Vec3>[
            Vec3(cx - minor * 0.55, ay, cz - major * 0.55),
            Vec3(cx - minor * 0.55, ay, cz + major * 0.02),
            Vec3(cx - minor, ay, cz + major * 0.02),
            Vec3(cx, ay, cz + major * 0.72),
            Vec3(cx + minor, ay, cz + major * 0.02),
            Vec3(cx + minor * 0.55, ay, cz + major * 0.02),
            Vec3(cx + minor * 0.55, ay, cz - major * 0.55),
          ];
        }
        alerts.add(_AlertOverlay(
          pts2: pts3.map(_project).toList(growable: false),
          center2: _project(Vec3(cx, ay, cz)),
          zKey: _avgDepth(pts3) + _childSlotZBias + 0.0092,
        ));
      }
    }

    return _EdgeResult(faces: faces, labels: labels, alerts: alerts);
  }

  _EdgeResult _buildVehicleOnSlot({
    required double x0,
    required double x1,
    required double z0,
    required double z1,
    required double yFloor,
    required int spanR,
    required int spanC,
    required String seed,
    required bool fromGroupHint,
    required bool isDeparture,
    required bool lowDetail,
  }) {
    final faces = <_FacePaint>[];

    final slotW = x1 - x0;
    final slotH = z1 - z0;
    final alongX =
        spanC > spanR ? true : (spanR > spanC ? false : slotW >= slotH);
    final mainLen = alongX ? slotW : slotH;
    final crossLen = alongX ? slotH : slotW;

    final bodyLongHalf = max(0.20, min(0.50, mainLen * 0.35));
    final bodyCrossHalf = max(0.13, min(0.29, crossLen * 0.255));
    final bodyHeight =
        max(0.050, min(_childSlotHeight * 0.52, min(slotW, slotH) * 0.16));
    final cabinHeight = bodyHeight * (lowDetail ? 0.78 : 0.88);

    final cx = (x0 + x1) * 0.5;
    final cz = (z0 + z1) * 0.5;

    final bodyHalfX = alongX ? bodyLongHalf : bodyCrossHalf;
    final bodyHalfZ = alongX ? bodyCrossHalf : bodyLongHalf;
    final cabinHalf =
        max(0.072, min(bodyCrossHalf * 0.82, bodyLongHalf * 0.42));
    final cabinHalfX = cabinHalf;
    final cabinHalfZ = cabinHalf;

    final bodyYBase = yFloor - 0.0012;
    final cabinYBase = bodyYBase - bodyHeight * 0.48;

    final shadeSeed = _stableUnitFromString(seed);
    final luxA = cs.surfaceContainerLowest.computeLuminance() > 0.5
        ? const Color(0xFFD8DEE5)
        : const Color(0xFF7C8A97);
    final luxB = cs.surfaceContainerLowest.computeLuminance() > 0.5
        ? const Color(0xFF8896A5)
        : const Color(0xFFC3CCD5);
    final luxC = cs.surfaceContainerLowest.computeLuminance() > 0.5
        ? const Color(0xFFEEE7DA)
        : const Color(0xFFA39A8E);

    var bodyTop =
        _ColorUtil.mix(_ColorUtil.mix(luxA, luxB, shadeSeed), luxC, 0.18);
    bodyTop = _ColorUtil.ensureContrast(bodyTop, cs.surfaceContainerLowest,
        fallback: cs.surface, target: 1.6);
    if (isDeparture) {
      bodyTop = _ColorUtil.mix(bodyTop, const Color(0xFFE07867), 0.26);
    }
    final bodyOpacity = fromGroupHint ? 0.62 : 0.96;
    final bodySideA =
        _ColorUtil.shiftLightness(bodyTop, -0.10).withOpacity(bodyOpacity);
    final bodySideB =
        _ColorUtil.shiftLightness(bodyTop, -0.16).withOpacity(bodyOpacity);
    final bodyTopPaint = bodyTop.withOpacity(bodyOpacity);
    final bodyCenter = Vec3(cx, bodyYBase, cz);

    faces.addAll(_buildAxisBox(
      center: bodyCenter,
      halfX: bodyHalfX,
      halfZ: bodyHalfZ,
      yBase: bodyYBase,
      height: bodyHeight,
      top: bodyTopPaint,
      sideA: bodySideA,
      sideB: bodySideB,
      zKeyBias: _childSlotZBias + 0.004,
    ).faces);

    final cabinCenter = Vec3(cx, cabinYBase, cz);
    final cabinTop = _ColorUtil.shiftLightness(bodyTop, 0.10)
        .withOpacity(fromGroupHint ? 0.58 : 0.94);
    final cabinSideA = _ColorUtil.shiftLightness(cabinTop, -0.10)
        .withOpacity(fromGroupHint ? 0.50 : 0.84);
    final cabinSideB = _ColorUtil.shiftLightness(cabinTop, -0.16)
        .withOpacity(fromGroupHint ? 0.46 : 0.80);

    faces.addAll(_buildAxisBox(
      center: cabinCenter,
      halfX: cabinHalfX,
      halfZ: cabinHalfZ,
      yBase: cabinYBase,
      height: cabinHeight,
      top: cabinTop,
      sideA: cabinSideA,
      sideB: cabinSideB,
      zKeyBias: _childSlotZBias + 0.006,
    ).faces);

    final glassFill = _ColorUtil.mix(
            cs.surface, const Color(0xFFE6F2FF), lowDetail ? 0.26 : 0.34)
        .withOpacity(fromGroupHint
            ? (lowDetail ? 0.14 : 0.20)
            : (lowDetail ? 0.26 : 0.38));
    final glassY = cabinYBase - cabinHeight - 0.0008;
    if (alongX) {
      final fx0 = cx + cabinHalfX * 0.18;
      final fx1 = cx + cabinHalfX * 0.72;
      final fz0 = cz - cabinHalfZ * 0.82;
      final fz1 = cz + cabinHalfZ * 0.82;
      final pts = [
        Vec3(fx0, glassY, fz0),
        Vec3(fx1, glassY, fz0),
        Vec3(fx1, glassY, fz1),
        Vec3(fx0, glassY, fz1),
      ];
      faces.add(_FacePaint(
        pts2: pts.map(_project).toList(growable: false),
        fill: glassFill,
        zKey: _avgDepth(pts) + _childSlotZBias + 0.0068,
      ));
      if (!lowDetail) {
        final rearFill =
            const Color(0xFFD84A3A).withOpacity(fromGroupHint ? 0.18 : 0.42);
        final rearPts = [
          Vec3(cx - bodyHalfX * 0.54, glassY, cz - bodyHalfZ * 0.46),
          Vec3(cx - bodyHalfX * 0.47, glassY, cz - bodyHalfZ * 0.46),
          Vec3(cx - bodyHalfX * 0.47, glassY, cz + bodyHalfZ * 0.46),
          Vec3(cx - bodyHalfX * 0.54, glassY, cz + bodyHalfZ * 0.46),
        ];
        faces.add(_FacePaint(
          pts2: rearPts.map(_project).toList(growable: false),
          fill: rearFill,
          zKey: _avgDepth(rearPts) + _childSlotZBias + 0.0069,
        ));
      }
    } else {
      final fx0 = cx - cabinHalfX * 0.82;
      final fx1 = cx + cabinHalfX * 0.82;
      final fz0 = cz + cabinHalfZ * 0.18;
      final fz1 = cz + cabinHalfZ * 0.72;
      final pts = [
        Vec3(fx0, glassY, fz0),
        Vec3(fx1, glassY, fz0),
        Vec3(fx1, glassY, fz1),
        Vec3(fx0, glassY, fz1),
      ];
      faces.add(_FacePaint(
        pts2: pts.map(_project).toList(growable: false),
        fill: glassFill,
        zKey: _avgDepth(pts) + _childSlotZBias + 0.0068,
      ));
      if (!lowDetail) {
        final rearFill =
            const Color(0xFFD84A3A).withOpacity(fromGroupHint ? 0.18 : 0.42);
        final rearPts = [
          Vec3(cx - bodyHalfX * 0.46, glassY, cz - bodyHalfZ * 0.54),
          Vec3(cx + bodyHalfX * 0.46, glassY, cz - bodyHalfZ * 0.54),
          Vec3(cx + bodyHalfX * 0.46, glassY, cz - bodyHalfZ * 0.47),
          Vec3(cx - bodyHalfX * 0.46, glassY, cz - bodyHalfZ * 0.47),
        ];
        faces.add(_FacePaint(
          pts2: rearPts.map(_project).toList(growable: false),
          fill: rearFill,
          zKey: _avgDepth(rearPts) + _childSlotZBias + 0.0069,
        ));
      }
    }

    return _EdgeResult(
        faces: faces,
        labels: const <_TextAnchor>[],
        alerts: const <_AlertOverlay>[]);
  }

  double _stableUnitFromString(String value) {
    var h = 17;
    for (final unit in value.codeUnits) {
      h = 0x1fffffff & (h * 31 + unit);
    }
    return (((h % 997) / 996.0).clamp(0.0, 1.0) as num).toDouble();
  }

  void _paintLabel(Canvas canvas, _TextAnchor a) {
    final tp = TextPainter(
      text: TextSpan(
        text: a.text,
        style: TextStyle(
          color: a.textColor,
          fontWeight: FontWeight.w900,
          fontSize: 12,
          shadows: [
            Shadow(
              blurRadius: 2.8,
              color: cs.onSurface.withOpacity(0.55),
              offset: const Offset(0, 1),
            ),
          ],
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final origin = a.pos - Offset(tp.width * 0.5, tp.height * 0.5);
    if (a.bgColor.opacity > 0.001 || a.borderColor.opacity > 0.001) {
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          origin.dx - 6,
          origin.dy - 2,
          tp.width + 12,
          tp.height + 4,
        ),
        const Radius.circular(8),
      );
      if (a.bgColor.opacity > 0.001) {
        canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.fill
            ..color = a.bgColor,
        );
      }
      if (a.borderColor.opacity > 0.001) {
        canvas.drawRRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1
            ..color = a.borderColor,
        );
      }
    }
    tp.paint(canvas, origin);
  }

  void _drawFootprintFrame(Canvas canvas) {
    final y = _yFloorTop - _ySurfaceEps;
    final w = model.cols.toDouble();
    final h = model.rows.toDouble();

    final p0 = _project(Vec3(0, y, 0));
    final p1 = _project(Vec3(w, y, 0));
    final p2 = _project(Vec3(w, y, h));
    final p3 = _project(Vec3(0, y, h));

    final path = Path()..addPolygon([p0, p1, p2, p3], true);

    final framePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.35
      ..color = palette.frame;

    canvas.drawPath(path, framePaint);
  }

  List<_RectXZ> _buildFloorRectsExceptRoad() {
    final rows = model.rows;
    final cols = model.cols;
    final visited = List.generate(rows, (_) => List<bool>.filled(cols, false));
    final rects = <_RectXZ>[];

    bool isFloorCell(int r, int c) =>
        model.cellAt(r, c) != _CellKind.road &&
        model.cellAt(r, c) != _CellKind.road2;

    for (int z = 0; z < rows; z++) {
      for (int x = 0; x < cols; x++) {
        if (visited[z][x] || !isFloorCell(z, x)) continue;

        int x1 = x;
        while (x1 < cols && !visited[z][x1] && isFloorCell(z, x1)) {
          x1++;
        }

        int z1 = z + 1;
        while (z1 < rows) {
          bool ok = true;
          for (int xx = x; xx < x1; xx++) {
            if (visited[z1][xx] || !isFloorCell(z1, xx)) {
              ok = false;
              break;
            }
          }
          if (!ok) break;
          z1++;
        }

        for (int zz = z; zz < z1; zz++) {
          for (int xx = x; xx < x1; xx++) {
            visited[zz][xx] = true;
          }
        }

        rects.add(_RectXZ(x0: x, x1: x1, z0: z, z1: z1));
        x = x1 - 1;
      }
    }

    return rects;
  }

  List<_WallRun> _buildWallRunsByGroup() {
    final rows = model.rows;
    final cols = model.cols;

    final hGroup =
        List.generate(rows + 1, (_) => List<String?>.filled(cols, null));
    final vGroup =
        List.generate(cols + 1, (_) => List<String?>.filled(rows, null));

    final entranceKey = model.entranceGateKey;
    final exitKey = model.exitGateKey;

    void putH(int z, int x, String groupKey) {
      if (z < 0 || z > rows) return;
      if (x < 0 || x >= cols) return;
      hGroup[z][x] = groupKey;
    }

    void putV(int x, int z, String groupKey) {
      if (x < 0 || x > cols) return;
      if (z < 0 || z >= rows) return;
      vGroup[x][z] = groupKey;
    }

    model.wallGroupIdByKey.forEach((key, gid) {
      if (entranceKey != null && key == entranceKey) return;
      if (exitKey != null && key == exitKey) return;

      final parsed = _parseEdgeKey(key);
      if (parsed == null) return;

      final r = parsed.$1;
      final c = parsed.$2;
      final edge = parsed.$3;

      if (!_isPerimeterEdgeValid(r, c, edge)) return;

      final groupKey = gid ?? _ParkingGridModel.kUngroupedWall;

      if (edge == 0) {
        putH(r, c, groupKey);
      } else if (edge == 2) {
        putH(r + 1, c, groupKey);
      } else if (edge == 1) {
        putV(c + 1, r, groupKey);
      } else if (edge == 3) {
        putV(c, r, groupKey);
      }
    });

    final runs = <_WallRun>[];

    for (int z = 0; z <= rows; z++) {
      int x = 0;
      while (x < cols) {
        final g = hGroup[z][x];
        if (g == null) {
          x++;
          continue;
        }
        final start = x;
        while (x < cols && hGroup[z][x] == g) {
          x++;
        }
        final end = x;
        runs.add(_WallRun(Vec3(start.toDouble(), 0, z.toDouble()),
            Vec3(end.toDouble(), 0, z.toDouble())));
      }
    }

    for (int x = 0; x <= cols; x++) {
      int z = 0;
      while (z < rows) {
        final g = vGroup[x][z];
        if (g == null) {
          z++;
          continue;
        }
        final start = z;
        while (z < rows && vGroup[x][z] == g) {
          z++;
        }
        final end = z;
        runs.add(_WallRun(Vec3(x.toDouble(), 0, start.toDouble()),
            Vec3(x.toDouble(), 0, end.toDouble())));
      }
    }

    return runs;
  }

  (int r, int c, int edge)? _parseEdgeKey(String key) {
    final parts = key.split('|');
    if (parts.length != 3) return null;
    final r = int.tryParse(parts[0]);
    final c = int.tryParse(parts[1]);
    final e = int.tryParse(parts[2]);
    if (r == null || c == null || e == null) return null;
    if (e < 0 || e > 3) return null;
    return (r, c, e);
  }

  _Edge3D? _edgeFromKey(String key) {
    final parsed = _parseEdgeKey(key);
    if (parsed == null) return null;

    final r = parsed.$1;
    final c = parsed.$2;
    final edge = parsed.$3;

    if (!_isPerimeterEdgeValid(r, c, edge)) return null;

    final x = c.toDouble();
    final z = r.toDouble();

    if (edge == 0) {
      return _Edge3D(key: key, a: Vec3(x, 0, z), b: Vec3(x + 1, 0, z));
    } else if (edge == 1) {
      return _Edge3D(key: key, a: Vec3(x + 1, 0, z), b: Vec3(x + 1, 0, z + 1));
    } else if (edge == 2) {
      return _Edge3D(key: key, a: Vec3(x, 0, z + 1), b: Vec3(x + 1, 0, z + 1));
    } else if (edge == 3) {
      return _Edge3D(key: key, a: Vec3(x, 0, z), b: Vec3(x, 0, z + 1));
    }
    return null;
  }

  double _avgDepth(List<Vec3> vs) {
    if (vs.isEmpty) return 0;
    double sum = 0;
    for (final v in vs) {
      sum += _depth(v);
    }
    return sum / vs.length;
  }

  _TileResult _buildFloorRectFaces({
    required double x0,
    required double x1,
    required double z0,
    required double z1,
  }) {
    final topY = _yFloorTop;
    final bottomY = _yFloorBottom;

    final v0b = Vec3(x0, bottomY, z0);
    final v1b = Vec3(x1, bottomY, z0);
    final v2b = Vec3(x1, bottomY, z1);

    final v0t = Vec3(x0, topY, z0);
    final v1t = Vec3(x1, topY, z0);
    final v2t = Vec3(x1, topY, z1);
    final v3t = Vec3(x0, topY, z1);

    final faces = <_FacePaint>[];

    faces.add(_FacePaint(
      pts2: [_project(v0t), _project(v1t), _project(v2t), _project(v3t)],
      fill: palette.floorTop,
      zKey: _avgDepth([v0t, v1t, v2t, v3t]),
    ));

    final seamY = topY - 0.0008;
    final seamFill = _ColorUtil.mix(palette.outline, palette.floorTop, 0.55)
        .withOpacity(isOrtho ? 0.16 : 0.22);
    final width = x1 - x0;
    final depth = z1 - z0;
    if (width >= 0.95) {
      final sx = x0 + width * 0.5;
      final s0 = Vec3(sx - 0.010, seamY, z0 + 0.04);
      final s1 = Vec3(sx + 0.010, seamY, z0 + 0.04);
      final s2 = Vec3(sx + 0.010, seamY, z1 - 0.04);
      final s3 = Vec3(sx - 0.010, seamY, z1 - 0.04);
      faces.add(_FacePaint(
        pts2: [_project(s0), _project(s1), _project(s2), _project(s3)],
        fill: seamFill,
        zKey: _avgDepth([s0, s1, s2, s3]) + 0.0004,
      ));
    }
    if (depth >= 0.95) {
      final sz = z0 + depth * 0.5;
      final s0 = Vec3(x0 + 0.04, seamY, sz - 0.010);
      final s1 = Vec3(x1 - 0.04, seamY, sz - 0.010);
      final s2 = Vec3(x1 - 0.04, seamY, sz + 0.010);
      final s3 = Vec3(x0 + 0.04, seamY, sz + 0.010);
      faces.add(_FacePaint(
        pts2: [_project(s0), _project(s1), _project(s2), _project(s3)],
        fill: seamFill.withOpacity(isOrtho ? 0.12 : 0.18),
        zKey: _avgDepth([s0, s1, s2, s3]) + 0.00042,
      ));
    }

    if (isOrtho) return _TileResult(faces: faces);

    final cols = model.cols.toDouble();
    final touchesNorth = (z0 <= 0.00001);
    final touchesEast = (x1 >= cols - 0.00001);

    if (touchesNorth) {
      faces.add(_FacePaint(
        pts2: [_project(v0b), _project(v1b), _project(v1t), _project(v0t)],
        fill: palette.floorSideA,
        zKey: _avgDepth([v0b, v1b, v1t, v0t]),
      ));
    }
    if (touchesEast) {
      faces.add(_FacePaint(
        pts2: [_project(v1b), _project(v2b), _project(v2t), _project(v1t)],
        fill: palette.floorSideB,
        zKey: _avgDepth([v1b, v2b, v2t, v1t]),
      ));
    }

    return _TileResult(faces: faces);
  }

  _TileResult _buildRoadFaces(
      {required Vec3 base, required _RoadAxis axis, required bool isRoad2}) {
    final h = _roadHeight.abs();
    final baseAt = Vec3(base.x, _yFloorTop, base.z);

    final topFill = isRoad2 ? palette.road2Top : palette.roadTop;
    final sideAFill = isRoad2 ? palette.road2SideA : palette.roadSideA;
    final sideBFill = isRoad2 ? palette.road2SideB : palette.roadSideB;
    final laneColor = isRoad2 ? palette.road2Mark : palette.roadMark;

    final v0 = baseAt;
    final v1 = baseAt + const Vec3(1, 0, 0);
    final v2 = baseAt + const Vec3(1, 0, 1);
    final v3 = baseAt + const Vec3(0, 0, 1);

    final v0t = v0 + Vec3(0, -h, 0);
    final v1t = v1 + Vec3(0, -h, 0);
    final v2t = v2 + Vec3(0, -h, 0);
    final v3t = v3 + Vec3(0, -h, 0);

    final faces = <_FacePaint>[];

    faces.add(_FacePaint(
      pts2: [_project(v0t), _project(v1t), _project(v2t), _project(v3t)],
      fill: topFill,
      zKey: _avgDepth([v0t, v1t, v2t, v3t]) + 0.0001,
    ));

    if (!isOrtho && !_useMinimalDetailMode) {
      faces.add(_FacePaint(
        pts2: [_project(v0), _project(v1), _project(v1t), _project(v0t)],
        fill: sideAFill,
        zKey: _avgDepth([v0, v1, v1t, v0t]),
      ));
      faces.add(_FacePaint(
        pts2: [_project(v1), _project(v2), _project(v2t), _project(v1t)],
        fill: sideBFill,
        zKey: _avgDepth([v1, v2, v2t, v1t]),
      ));
    }

    final laneY = -h - 0.001;

    void addTopRect({
      required double x0,
      required double x1,
      required double z0,
      required double z1,
      required Color fill,
      required double bias,
    }) {
      final s0 = baseAt + Vec3(x0, laneY, z0);
      final s1 = baseAt + Vec3(x1, laneY, z0);
      final s2 = baseAt + Vec3(x1, laneY, z1);
      final s3 = baseAt + Vec3(x0, laneY, z1);
      faces.add(_FacePaint(
        pts2: [_project(s0), _project(s1), _project(s2), _project(s3)],
        fill: fill,
        zKey: _avgDepth([s0, s1, s2, s3]) + bias,
      ));
    }

    final primary = laneColor.withOpacity(_useCompactRoadMarks
        ? (isOrtho ? 0.58 : 0.74)
        : (isOrtho ? 0.72 : 0.88));
    final secondary = laneColor.withOpacity(_useCompactRoadMarks
        ? (isOrtho ? 0.28 : 0.38)
        : (isOrtho ? 0.40 : 0.54));
    final accent = (isRoad2 ? palette.exit : palette.entrance).withOpacity(
        _useCompactRoadMarks
            ? (isOrtho ? 0.34 : 0.42)
            : (isOrtho ? 0.44 : 0.54));

    switch (axis) {
      case _RoadAxis.z:
        if (isRoad2) {
          addTopRect(
              x0: 0.46,
              x1: 0.54,
              z0: 0.12,
              z1: 0.88,
              fill: primary,
              bias: 0.0012);
          addTopRect(
              x0: 0.20,
              x1: 0.80,
              z0: 0.20,
              z1: 0.28,
              fill: secondary,
              bias: 0.0013);
        } else {
          addTopRect(
              x0: 0.47,
              x1: 0.53,
              z0: 0.16,
              z1: 0.84,
              fill: primary,
              bias: 0.0012);
          if (!_useCompactRoadMarks) {
            addTopRect(
                x0: 0.18,
                x1: 0.22,
                z0: 0.08,
                z1: 0.92,
                fill: secondary,
                bias: 0.0010);
            addTopRect(
                x0: 0.78,
                x1: 0.82,
                z0: 0.08,
                z1: 0.92,
                fill: secondary,
                bias: 0.0011);
          }
        }
        break;
      case _RoadAxis.x:
        if (isRoad2) {
          addTopRect(
              x0: 0.12,
              x1: 0.88,
              z0: 0.46,
              z1: 0.54,
              fill: primary,
              bias: 0.0012);
          addTopRect(
              x0: 0.20,
              x1: 0.28,
              z0: 0.20,
              z1: 0.80,
              fill: secondary,
              bias: 0.0013);
        } else {
          addTopRect(
              x0: 0.16,
              x1: 0.84,
              z0: 0.47,
              z1: 0.53,
              fill: primary,
              bias: 0.0012);
          if (!_useCompactRoadMarks) {
            addTopRect(
                x0: 0.08,
                x1: 0.92,
                z0: 0.18,
                z1: 0.22,
                fill: secondary,
                bias: 0.0010);
            addTopRect(
                x0: 0.08,
                x1: 0.92,
                z0: 0.78,
                z1: 0.82,
                fill: secondary,
                bias: 0.0011);
          }
        }
        break;
      case _RoadAxis.cross:
        addTopRect(
            x0: 0.22, x1: 0.78, z0: 0.22, z1: 0.78, fill: accent, bias: 0.0011);
        if (!_useCompactRoadMarks) {
          addTopRect(
              x0: 0.46,
              x1: 0.54,
              z0: 0.12,
              z1: 0.88,
              fill: primary,
              bias: 0.0012);
          addTopRect(
              x0: 0.12,
              x1: 0.88,
              z0: 0.46,
              z1: 0.54,
              fill: primary,
              bias: 0.0013);
        }
        break;
      case _RoadAxis.none:
        break;
    }

    return _TileResult(faces: faces);
  }

  _TileResult _buildPillarFaces({required Vec3 base}) {
    final h = (isOrtho ? _pillarHeightLod : _pillarHeightFull).abs();

    if (_useMinimalDetailMode) {
      final cx = base.x + 0.5;
      final cz = base.z + 0.5;
      return _buildAxisBox(
        center: Vec3(cx, 0, cz),
        halfX: isOrtho ? 0.18 : 0.16,
        halfZ: isOrtho ? 0.18 : 0.16,
        yBase: _yFloorTop,
        height: h,
        top: palette.pillarTop,
        sideA: palette.pillarSideA,
        sideB: palette.pillarSideB,
        zKeyBias: 0.0002,
      );
    }

    final cx = base.x + 0.5;
    final cz = base.z + 0.5;

    final bg = cs.surfaceContainerLowest;
    final isLight = bg.computeLuminance() > 0.5;
    final bodyHalfX = isOrtho ? 0.20 : 0.18;
    final bodyHalfZ = isOrtho ? 0.20 : 0.18;
    final faces = <_FacePaint>[];

    final concreteBase = _ColorUtil.mix(
      const Color(0xFFD6D9DC),
      palette.pillarTop,
      isLight ? 0.42 : 0.28,
    ).withOpacity(0.98);
    final concreteTop =
        _ColorUtil.shiftLightness(concreteBase, isLight ? 0.05 : 0.08)
            .withOpacity(0.98);
    final concreteSideA =
        _ColorUtil.shiftLightness(concreteBase, isLight ? -0.08 : 0.10)
            .withOpacity(0.96);
    final concreteSideB =
        _ColorUtil.shiftLightness(concreteBase, isLight ? -0.12 : 0.14)
            .withOpacity(0.94);

    final plinthHeight = isOrtho ? 0.020 : 0.070;
    faces.addAll(_buildAxisBox(
      center: Vec3(cx, 0, cz),
      halfX: bodyHalfX * 1.28,
      halfZ: bodyHalfZ * 1.28,
      yBase: _yFloorTop,
      height: plinthHeight,
      top: _ColorUtil.shiftLightness(concreteTop, isLight ? -0.03 : 0.04),
      sideA: concreteSideA,
      sideB: concreteSideB,
      zKeyBias: 0.00012,
    ).faces);

    faces.addAll(_buildAxisBox(
      center: Vec3(cx, 0, cz),
      halfX: bodyHalfX,
      halfZ: bodyHalfZ,
      yBase: _yFloorTop,
      height: h,
      top: concreteTop,
      sideA: concreteSideA,
      sideB: concreteSideB,
      zKeyBias: 0.0002,
    ).faces);

    final zoneBlue = _ColorUtil.ensureContrast(
      _ColorUtil.mix(cs.primary, const Color(0xFF2F6FA8), 0.46),
      bg,
      fallback: cs.primary,
      target: 2.0,
    ).withOpacity(0.96);
    final zoneBlueA =
        _ColorUtil.shiftLightness(zoneBlue, isLight ? -0.10 : 0.08)
            .withOpacity(0.94);
    final zoneBlueB =
        _ColorUtil.shiftLightness(zoneBlue, isLight ? -0.16 : 0.12)
            .withOpacity(0.92);
    final bandHeight = isOrtho ? 0.024 : min(0.12, h * 0.18);
    final bandYBase = _yFloorTop - h * 0.46;
    faces.addAll(_buildAxisBox(
      center: Vec3(cx, 0, cz),
      halfX: bodyHalfX * 1.02,
      halfZ: bodyHalfZ * 1.02,
      yBase: bandYBase,
      height: bandHeight,
      top: zoneBlue,
      sideA: zoneBlueA,
      sideB: zoneBlueB,
      zKeyBias: 0.00034,
    ).faces);

    final bumperBase = _ColorUtil.ensureContrast(
      const Color(0xFFF2B72A),
      bg,
      fallback: cs.tertiary,
      target: 1.8,
    ).withOpacity(0.98);
    final bumperSideA =
        _ColorUtil.shiftLightness(bumperBase, isLight ? -0.10 : 0.08)
            .withOpacity(0.96);
    final bumperSideB =
        _ColorUtil.shiftLightness(bumperBase, isLight ? -0.16 : 0.12)
            .withOpacity(0.94);
    final bumperHeight = isOrtho ? 0.032 : min(0.24, h * 0.26);
    final bumperHalfThickness = isOrtho ? 0.020 : 0.038;
    final bumperLongX = bodyHalfX * 1.02;
    final bumperLongZ = bodyHalfZ * 1.02;

    faces.addAll(_buildAxisBox(
      center: Vec3(cx + bodyHalfX + bumperHalfThickness * 0.68, 0, cz),
      halfX: bumperHalfThickness,
      halfZ: bumperLongZ,
      yBase: _yFloorTop,
      height: bumperHeight,
      top: bumperBase,
      sideA: bumperSideA,
      sideB: bumperSideB,
      zKeyBias: 0.00044,
    ).faces);
    faces.addAll(_buildAxisBox(
      center: Vec3(cx - bodyHalfX - bumperHalfThickness * 0.68, 0, cz),
      halfX: bumperHalfThickness,
      halfZ: bumperLongZ,
      yBase: _yFloorTop,
      height: bumperHeight,
      top: bumperBase,
      sideA: bumperSideA,
      sideB: bumperSideB,
      zKeyBias: 0.00045,
    ).faces);
    faces.addAll(_buildAxisBox(
      center: Vec3(cx, 0, cz + bodyHalfZ + bumperHalfThickness * 0.68),
      halfX: bumperLongX,
      halfZ: bumperHalfThickness,
      yBase: _yFloorTop,
      height: bumperHeight,
      top: bumperBase,
      sideA: bumperSideA,
      sideB: bumperSideB,
      zKeyBias: 0.00046,
    ).faces);
    faces.addAll(_buildAxisBox(
      center: Vec3(cx, 0, cz - bodyHalfZ - bumperHalfThickness * 0.68),
      halfX: bumperLongX,
      halfZ: bumperHalfThickness,
      yBase: _yFloorTop,
      height: bumperHeight,
      top: bumperBase,
      sideA: bumperSideA,
      sideB: bumperSideB,
      zKeyBias: 0.00047,
    ).faces);

    final navy = const Color(0xFF1E2D3D).withOpacity(0.96);
    final navyHeight = isOrtho ? 0.010 : min(0.05, bumperHeight * 0.24);
    final navyYBase = _yFloorTop - bumperHeight * 0.54;
    faces.addAll(_buildAxisBox(
      center: Vec3(cx, 0, cz),
      halfX: bodyHalfX + bumperHalfThickness * 0.94,
      halfZ: bodyHalfZ + bumperHalfThickness * 0.94,
      yBase: navyYBase,
      height: navyHeight,
      top: navy,
      sideA: navy,
      sideB: navy,
      zKeyBias: 0.00054,
    ).faces);

    final crownHeight = isOrtho ? 0.014 : 0.032;
    faces.addAll(_buildAxisBox(
      center: Vec3(cx, 0, cz),
      halfX: bodyHalfX * 1.10,
      halfZ: bodyHalfZ * 1.10,
      yBase: _yFloorTop - h + crownHeight,
      height: crownHeight,
      top: _ColorUtil.shiftLightness(concreteTop, isLight ? 0.08 : 0.06),
      sideA: _ColorUtil.shiftLightness(concreteSideA, isLight ? 0.02 : 0.06),
      sideB: _ColorUtil.shiftLightness(concreteSideB, isLight ? 0.02 : 0.06),
      zKeyBias: 0.00062,
    ).faces);

    final signHalfX = bodyHalfX * 0.54;
    final signHalfZ = isOrtho ? 0.016 : 0.026;
    final signHeight = isOrtho ? 0.022 : 0.070;
    final signYBase = _yFloorTop - h * 0.58;
    final signTop =
        _ColorUtil.mix(zoneBlue, Colors.white, 0.24).withOpacity(0.96);
    final signSide = _ColorUtil.shiftLightness(zoneBlue, isLight ? -0.12 : 0.10)
        .withOpacity(0.94);

    faces.addAll(_buildAxisBox(
      center: Vec3(cx, 0, cz - bodyHalfZ - signHalfZ * 0.64),
      halfX: signHalfX,
      halfZ: signHalfZ,
      yBase: signYBase,
      height: signHeight,
      top: signTop,
      sideA: signSide,
      sideB: signSide,
      zKeyBias: 0.00072,
    ).faces);

    final pixelFill = Colors.white.withOpacity(0.96);
    final pxHalfX = signHalfX * 0.16;
    final pxHalfZ = signHalfZ * 0.55;
    final pxHeight = signHeight * 0.22;
    final pxYBase = signYBase - signHeight * 0.42;
    for (final dx in <double>[-signHalfX * 0.38, 0, signHalfX * 0.38]) {
      faces.addAll(_buildAxisBox(
        center: Vec3(cx + dx, 0, cz - bodyHalfZ - signHalfZ * 1.28),
        halfX: pxHalfX,
        halfZ: pxHalfZ,
        yBase: pxYBase,
        height: pxHeight,
        top: pixelFill,
        sideA: pixelFill.withOpacity(0.80),
        sideB: pixelFill.withOpacity(0.76),
        zKeyBias: 0.00078,
      ).faces);
    }

    return _TileResult(faces: faces);
  }

  _TileResult _buildWallRunFaces({required Vec3 a, required Vec3 b}) {
    final h = (isOrtho ? _wallHeightLod : _wallHeightFull).abs();

    if (_useMinimalDetailMode) {
      return _buildEdgePrism(
        a: a,
        b: b,
        yBase: _yFloorTop - _ySurfaceEps,
        thickness: _wallThicknessForView(),
        height: h,
        top: palette.wallTop,
        sideA: palette.wallSideA,
        sideB: palette.wallSideB,
        zKeyBias: 0.0,
      );
    }
    final yBase = _yFloorTop - _ySurfaceEps;

    final runLen = (b - a).length;
    if (runLen <= 0.00001) return const _TileResult(faces: []);

    final thickness = _wallThicknessForView();
    final faces = <_FacePaint>[];

    final dir = (b - a).normalized;
    final n = Vec3(-dir.z, 0, dir.x);
    final mid = Vec3((a.x + b.x) * 0.5, 0, (a.z + b.z) * 0.5);
    final toCenter = Vec3(_pivot.x - mid.x, 0, _pivot.z - mid.z);
    final inward = toCenter.dot(n) >= 0 ? n : n * -1.0;
    final isLightTheme = cs.surfaceContainerLowest.computeLuminance() > 0.5;

    final wallTop = _ColorUtil.mix(palette.wallTop, const Color(0xFFFFFFFF),
            isLightTheme ? 0.16 : 0.04)
        .withOpacity(0.98);
    final wallSideA =
        _ColorUtil.shiftLightness(wallTop, isLightTheme ? -0.08 : 0.08)
            .withOpacity(0.94);
    final wallSideB =
        _ColorUtil.shiftLightness(wallTop, isLightTheme ? -0.12 : 0.12)
            .withOpacity(0.92);
    faces.addAll(_buildEdgePrism(
      a: a,
      b: b,
      yBase: yBase,
      thickness: thickness,
      height: h,
      top: wallTop,
      sideA: wallSideA,
      sideB: wallSideB,
      zKeyBias: 0.0,
    ).faces);

    final capHeight = isOrtho ? 0.016 : 0.032;
    faces.addAll(_buildEdgePrism(
      a: a,
      b: b,
      yBase: yBase - h,
      thickness: thickness * 1.12,
      height: capHeight,
      top: _ColorUtil.shiftLightness(wallTop, isLightTheme ? 0.06 : 0.04),
      sideA: _ColorUtil.shiftLightness(wallSideA, isLightTheme ? 0.02 : 0.04),
      sideB: _ColorUtil.shiftLightness(wallSideB, isLightTheme ? 0.02 : 0.04),
      zKeyBias: 0.0010,
    ).faces);

    final skirtingThickness = thickness * 0.52;
    final skirtingHeight = isOrtho ? 0.034 : min(0.13, h * 0.18);
    final skirtingOffset =
        inward * ((thickness - skirtingThickness) * 0.5 + 0.004);
    final skirtingTop =
        _ColorUtil.mix(const Color(0xFF8B9198), cs.surfaceVariant, 0.34)
            .withOpacity(0.98);
    final skirtingSideA =
        _ColorUtil.shiftLightness(skirtingTop, isLightTheme ? -0.10 : 0.10)
            .withOpacity(0.96);
    final skirtingSideB =
        _ColorUtil.shiftLightness(skirtingTop, isLightTheme ? -0.14 : 0.14)
            .withOpacity(0.94);
    faces.addAll(_buildEdgePrism(
      a: a + skirtingOffset,
      b: b + skirtingOffset,
      yBase: yBase - 0.002,
      thickness: skirtingThickness,
      height: skirtingHeight,
      top: skirtingTop,
      sideA: skirtingSideA,
      sideB: skirtingSideB,
      zKeyBias: 0.0011,
    ).faces);

    final ribbonThickness = thickness * 0.32;
    final ribbonHeight = isOrtho ? 0.022 : min(0.08, h * 0.10);
    final ribbonOffset = inward * ((thickness - ribbonThickness) * 0.5 + 0.008);
    final ribbonBase = yBase - h * 0.58;
    final ribbonTop = _ColorUtil.ensureContrast(
      _ColorUtil.mix(cs.primary, const Color(0xFF2F6FA8), 0.42),
      cs.surfaceContainerLowest,
      fallback: cs.primary,
      target: 2.0,
    ).withOpacity(0.92);
    final ribbonSideA =
        _ColorUtil.shiftLightness(ribbonTop, isLightTheme ? -0.10 : 0.08)
            .withOpacity(0.90);
    final ribbonSideB =
        _ColorUtil.shiftLightness(ribbonTop, isLightTheme ? -0.16 : 0.12)
            .withOpacity(0.88);
    faces.addAll(_buildEdgePrism(
      a: a + ribbonOffset,
      b: b + ribbonOffset,
      yBase: ribbonBase,
      thickness: ribbonThickness,
      height: ribbonHeight,
      top: ribbonTop,
      sideA: ribbonSideA,
      sideB: ribbonSideB,
      zKeyBias: 0.0016,
    ).faces);

    final adThickness = thickness * 0.20;
    final adHeight = isOrtho ? 0.016 : min(0.06, h * 0.08);
    final adOffset = inward * ((thickness - adThickness) * 0.5 + 0.011);
    final adBase = yBase - h * 0.30;
    final adTop = _ColorUtil.mix(const Color(0xFFF0E1B2), Colors.white, 0.38)
        .withOpacity(0.94);
    final adSideA =
        _ColorUtil.shiftLightness(adTop, isLightTheme ? -0.08 : 0.06)
            .withOpacity(0.90);
    final adSideB =
        _ColorUtil.shiftLightness(adTop, isLightTheme ? -0.12 : 0.10)
            .withOpacity(0.88);
    faces.addAll(_buildEdgePrism(
      a: a + adOffset,
      b: b + adOffset,
      yBase: adBase,
      thickness: adThickness,
      height: adHeight,
      top: adTop,
      sideA: adSideA,
      sideB: adSideB,
      zKeyBias: 0.0019,
    ).faces);

    final yTop = yBase - h;
    final stripW = _wallHighlightStripWorld(thickness) * 0.72;
    final a0t = Vec3(a.x, yTop - 0.0006, a.z) + n * (thickness * 0.5);
    final a1t = Vec3(a.x, yTop - 0.0006, a.z) - n * (thickness * 0.5);
    final b0t = Vec3(b.x, yTop - 0.0006, b.z) + n * (thickness * 0.5);
    final b1t = Vec3(b.x, yTop - 0.0006, b.z) - n * (thickness * 0.5);
    final a0i = a0t - n * stripW;
    final b0i = b0t - n * stripW;
    final a1i = a1t + n * stripW;
    final b1i = b1t + n * stripW;
    final hiFill = Colors.white.withOpacity(isOrtho ? 0.18 : 0.24);
    final loFill = _ColorUtil.mix(palette.outline, wallTop, 0.62)
        .withOpacity(isOrtho ? 0.14 : 0.20);

    faces.add(_FacePaint(
      pts2: [_project(a0t), _project(b0t), _project(b0i), _project(a0i)],
      fill: hiFill,
      zKey: _avgDepth([a0t, b0t, b0i, a0i]) + 0.0008,
    ));
    faces.add(_FacePaint(
      pts2: [_project(a1i), _project(b1i), _project(b1t), _project(a1t)],
      fill: loFill,
      zKey: _avgDepth([a1i, b1i, b1t, a1t]) + 0.00075,
    ));

    return _TileResult(faces: faces);
  }

  _EdgeResult _buildTowerRects() {
    final faces = <_FacePaint>[];
    final labels = <_TextAnchor>[];
    if (model.towerRects.isEmpty) {
      return _EdgeResult(faces: faces, labels: labels);
    }

    if (_useMinimalDetailMode) {
      final top = palette.towerTop;
      final sideA = palette.towerSideA;
      final sideB = palette.towerSideB;
      for (final raw in model.towerRects) {
        final rr = raw.normalized();
        final rr0 = rr.r0.clamp(0, model.rows - 1);
        final rr1 = rr.r1.clamp(0, model.rows - 1);
        final cc0 = rr.c0.clamp(0, model.cols - 1);
        final cc1 = rr.c1.clamp(0, model.cols - 1);
        if (rr1 < rr0 || cc1 < cc0) continue;
        final x0 = cc0.toDouble();
        final x1 = (cc1 + 1).toDouble();
        final z0 = rr0.toDouble();
        final z1 = (rr1 + 1).toDouble();
        faces.addAll(_buildAxisBox(
          center: Vec3((x0 + x1) * 0.5, 0, (z0 + z1) * 0.5),
          halfX: (x1 - x0) * 0.5 - 0.06,
          halfZ: (z1 - z0) * 0.5 - 0.06,
          yBase: _yFloorTop,
          height: isOrtho ? 0.14 : 0.42,
          top: top,
          sideA: sideA,
          sideB: sideB,
          zKeyBias: 0.0058,
        ).faces);
      }
      return _EdgeResult(faces: faces, labels: labels);
    }

    final bg = cs.surfaceContainerLowest;
    final isLightTheme = bg.computeLuminance() > 0.5;

    Color accent = palette.towerMark;
    final ts = model.towerStatus;
    if (ts != ParkingSlotStatus.empty) {
      switch (ts) {
        case ParkingSlotStatus.parked:
          accent = const Color(0xFF2E9B54);
          break;
        case ParkingSlotStatus.departureRequest:
          accent = const Color(0xFFD84A3A);
          break;
        case ParkingSlotStatus.parkingRequest:
          accent = const Color(0xFFE09A00);
          break;
        case ParkingSlotStatus.empty:
          accent = palette.towerMark;
          break;
      }
      accent = _ColorUtil.ensureContrast(accent, bg,
          fallback: cs.primary, target: 2.0);
    }

    final stoneTop = _ColorUtil.mix(
            palette.towerTop, Colors.white, isLightTheme ? 0.16 : 0.06)
        .withOpacity(0.96);
    final stoneSideA =
        _ColorUtil.shiftLightness(stoneTop, isLightTheme ? -0.08 : 0.08)
            .withOpacity(0.90);
    final stoneSideB =
        _ColorUtil.shiftLightness(stoneTop, isLightTheme ? -0.12 : 0.12)
            .withOpacity(0.88);
    final metalTop =
        _ColorUtil.mix(const Color(0xFFBCC7D1), accent, 0.18).withOpacity(0.96);
    final metalSideA =
        _ColorUtil.shiftLightness(metalTop, isLightTheme ? -0.10 : 0.08)
            .withOpacity(0.88);
    final metalSideB =
        _ColorUtil.shiftLightness(metalTop, isLightTheme ? -0.14 : 0.12)
            .withOpacity(0.84);
    final glassTop = _ColorUtil.mix(
            cs.surface, const Color(0xFFEAF4FF), isLightTheme ? 0.60 : 0.22)
        .withOpacity(0.88);
    final glassSideA =
        _ColorUtil.shiftLightness(glassTop, isLightTheme ? -0.08 : 0.06)
            .withOpacity(0.72);
    final glassSideB =
        _ColorUtil.shiftLightness(glassTop, isLightTheme ? -0.12 : 0.10)
            .withOpacity(0.68);

    final yBase = _yFloorTop - _ySurfaceEps;

    for (final raw in model.towerRects) {
      final rr = raw.normalized();

      final rr0 = rr.r0.clamp(0, model.rows - 1);
      final rr1 = rr.r1.clamp(0, model.rows - 1);
      final cc0 = rr.c0.clamp(0, model.cols - 1);
      final cc1 = rr.c1.clamp(0, model.cols - 1);

      if (rr1 < rr0 || cc1 < cc0) continue;

      final x0 = cc0.toDouble();
      final x1 = (cc1 + 1).toDouble();
      final z0 = rr0.toDouble();
      final z1 = (rr1 + 1).toDouble();
      final cx = (x0 + x1) * 0.5;
      final cz = (z0 + z1) * 0.5;
      final spanX = x1 - x0;
      final spanZ = z1 - z0;

      final frontDir = _towerFrontDirectionForRect(rr0, rr1, cc0, cc1);
      final frontAlongX = frontDir.x.abs() >= frontDir.z.abs();
      final frontSign = frontAlongX
          ? (frontDir.x >= 0 ? 1.0 : -1.0)
          : (frontDir.z >= 0 ? 1.0 : -1.0);

      Vec3 lc(double depth, double lateral) {
        if (frontAlongX) {
          return Vec3(cx + frontSign * depth, 0, cz + lateral);
        }
        return Vec3(cx + lateral, 0, cz + frontSign * depth);
      }

      void addLocalBox({
        required double depth,
        required double lateral,
        required double halfDepth,
        required double halfLateral,
        required double boxYBase,
        required double height,
        required Color top,
        required Color sideA,
        required Color sideB,
        required double zKeyBias,
      }) {
        final center = lc(depth, lateral);
        final halfX = frontAlongX ? halfDepth : halfLateral;
        final halfZ = frontAlongX ? halfLateral : halfDepth;
        faces.addAll(_buildAxisBox(
          center: center,
          halfX: halfX,
          halfZ: halfZ,
          yBase: boxYBase,
          height: height,
          top: top,
          sideA: sideA,
          sideB: sideB,
          zKeyBias: zKeyBias,
        ).faces);
      }

      final widthSpan = (frontAlongX ? spanZ : spanX).toDouble();
      final depthSpan = (frontAlongX ? spanX : spanZ).toDouble();
      final plinthHeight = isOrtho ? 0.026 : 0.08;
      final coreHeight = isOrtho ? 0.22 : 0.96;
      final coreHalfDepth = max(0.16, depthSpan * 0.28);
      final coreHalfLateral = max(0.18, widthSpan * 0.30);

      addLocalBox(
        depth: 0,
        lateral: 0,
        halfDepth: max(0.16, depthSpan * 0.5 - 0.03),
        halfLateral: max(0.16, widthSpan * 0.5 - 0.03),
        boxYBase: yBase,
        height: plinthHeight,
        top: _ColorUtil.mix(stoneTop, const Color(0xFFF3F0E8), 0.24)
            .withOpacity(0.88),
        sideA: stoneSideA.withOpacity(0.74),
        sideB: stoneSideB.withOpacity(0.72),
        zKeyBias: 0.0072,
      );

      addLocalBox(
        depth: -depthSpan * 0.06,
        lateral: 0,
        halfDepth: coreHalfDepth,
        halfLateral: coreHalfLateral,
        boxYBase: yBase - plinthHeight * 0.2,
        height: coreHeight,
        top: stoneTop,
        sideA: stoneSideA,
        sideB: stoneSideB,
        zKeyBias: 0.0082,
      );

      final canopyHeight = isOrtho ? 0.020 : 0.08;
      addLocalBox(
        depth: depthSpan * 0.12,
        lateral: 0,
        halfDepth: max(0.18, depthSpan * 0.30),
        halfLateral: max(0.20, widthSpan * 0.42),
        boxYBase: yBase - coreHeight + canopyHeight,
        height: canopyHeight,
        top: metalTop,
        sideA: metalSideA,
        sideB: metalSideB,
        zKeyBias: 0.0088,
      );

      final lobbyHeight = isOrtho ? 0.06 : 0.22;
      addLocalBox(
        depth: depthSpan * 0.30,
        lateral: 0,
        halfDepth: max(0.12, depthSpan * 0.18),
        halfLateral: max(0.18, widthSpan * 0.32),
        boxYBase: yBase - plinthHeight * 0.18,
        height: lobbyHeight,
        top: glassTop,
        sideA: glassSideA,
        sideB: glassSideB,
        zKeyBias: 0.0090,
      );

      final accentPanelHeight = isOrtho ? 0.028 : 0.10;
      addLocalBox(
        depth: depthSpan * 0.02,
        lateral: 0,
        halfDepth: max(0.05, coreHalfDepth * 0.26),
        halfLateral: max(0.12, coreHalfLateral * 0.74),
        boxYBase: yBase - coreHeight * 0.56,
        height: accentPanelHeight,
        top: accent.withOpacity(0.92),
        sideA: _ColorUtil.shiftLightness(accent, isLightTheme ? -0.10 : 0.08)
            .withOpacity(0.88),
        sideB: _ColorUtil.shiftLightness(accent, isLightTheme ? -0.16 : 0.12)
            .withOpacity(0.84),
        zKeyBias: 0.0093,
      );

      final sideKioskHalf = max(0.05, widthSpan * 0.10);
      final sideKioskDepth = max(0.08, depthSpan * 0.12);
      final sideOffset = max(0.16, coreHalfLateral + sideKioskHalf * 0.2);
      for (final lateral in <double>[-sideOffset, sideOffset]) {
        addLocalBox(
          depth: depthSpan * 0.18,
          lateral: lateral,
          halfDepth: sideKioskDepth,
          halfLateral: sideKioskHalf,
          boxYBase: yBase,
          height: isOrtho ? 0.08 : 0.26,
          top: metalTop,
          sideA: metalSideA,
          sideB: metalSideB,
          zKeyBias: 0.0091,
        );
      }
    }

    return _EdgeResult(faces: faces, labels: labels);
  }

  _EdgeResult _buildGateRects(
      {required List<GridRect> rects, required _EdgeKind kind}) {
    final faces = <_FacePaint>[];
    final labels = <_TextAnchor>[];

    if (rects.isEmpty) return _EdgeResult(faces: faces, labels: labels);

    double topYForCell(int r, int c) {
      final k = model.cellAt(r, c);
      if (k == _CellKind.road || k == _CellKind.road2) {
        return (_yFloorTop - _roadHeight) - 0.0012;
      }
      return _yFloorTop - 0.0012;
    }

    for (final gr in rects) {
      final rr = gr.normalized();
      final rr0 = rr.r0.clamp(0, model.rows - 1);
      final rr1 = rr.r1.clamp(0, model.rows - 1);
      final cc0 = rr.c0.clamp(0, model.cols - 1);
      final cc1 = rr.c1.clamp(0, model.cols - 1);
      if (rr1 < rr0 || cc1 < cc0) continue;

      for (int r = rr0; r <= rr1; r++) {
        for (int c = cc0; c <= cc1; c++) {
          final y = topYForCell(r, c);
          final x0 = c.toDouble() + 0.06;
          final x1 = (c + 1).toDouble() - 0.06;
          final z0 = r.toDouble() + 0.06;
          final z1 = (r + 1).toDouble() - 0.06;
          if (x1 <= x0 + 0.02 || z1 <= z0 + 0.02) continue;
          final p0 = Vec3(x0, y, z0);
          final p1 = Vec3(x1, y, z0);
          final p2 = Vec3(x1, y, z1);
          final p3 = Vec3(x0, y, z1);
          faces.add(_FacePaint(
            pts2: [_project(p0), _project(p1), _project(p2), _project(p3)],
            fill: cs.surfaceVariant.withOpacity(isOrtho ? 0.08 : 0.06),
            zKey: _avgDepth([p0, p1, p2, p3]) + 0.0092,
          ));
        }
      }

      final rectW = (cc1 - cc0 + 1).toDouble();
      final rectH = (rr1 - rr0 + 1).toDouble();
      final d = _travelDirectionForGateRect(
        rr0: rr0,
        rr1: rr1,
        cc0: cc0,
        cc1: cc1,
        kind: kind,
      );
      final laneWidth =
          ((d.x.abs() >= d.z.abs()) ? rectH : rectW).clamp(1.0, 3.2).toDouble();
      final span = (laneWidth * 0.46).clamp(0.34, 0.94).toDouble();
      final thresholdCenter = _thresholdCenterForGateRect(
        rr0: rr0,
        rr1: rr1,
        cc0: cc0,
        cc1: cc1,
      );

      final gate = _buildBarrierGateScene(
        thresholdCenter: thresholdCenter,
        travelDir: d,
        span: span,
        kind: kind,
        floorBase: _yFloorTop - _ySurfaceEps,
      );
      faces.addAll(gate.faces);
      labels.addAll(gate.labels);
    }

    return _EdgeResult(faces: faces, labels: labels);
  }

  _EdgeResult _buildGate({required _Edge3D edge, required _EdgeKind kind}) {
    final faces = <_FacePaint>[];
    final labels = <_TextAnchor>[];

    final inward = _inwardNormalForEdgeKey(edge.key);
    final d = kind == _EdgeKind.entrance ? inward : inward * -1.0;
    final len = (edge.b - edge.a).length;
    final span = (len * 0.34).clamp(0.36, 0.98).toDouble();
    final gate = _buildBarrierGateScene(
      thresholdCenter: (edge.a + edge.b) * 0.5,
      travelDir: d,
      span: span,
      kind: kind,
      floorBase: _yFloorTop - _ySurfaceEps,
    );
    faces.addAll(gate.faces);
    labels.addAll(gate.labels);

    return _EdgeResult(faces: faces, labels: labels);
  }

  double _perimeterDistanceAlong(Vec3 point, Vec3 dir) {
    if (dir.x > 0.5) return max(0.0, model.cols - point.x);
    if (dir.x < -0.5) return max(0.0, point.x);
    if (dir.z > 0.5) return max(0.0, model.rows - point.z);
    if (dir.z < -0.5) return max(0.0, point.z);
    return min(
      min(point.x, model.cols - point.x),
      min(point.z, model.rows - point.z),
    );
  }

  Vec3 _preferredGateCabinetSide({
    required Vec3 thresholdCenter,
    required Vec3 travelDir,
    required Vec3 left,
    required Vec3 right,
    required double span,
    required double cabinetHalfCross,
  }) {
    Vec3 candidateCenter(Vec3 side) =>
        thresholdCenter +
        side * (span + cabinetHalfCross * 0.84) -
        travelDir * 0.08;

    double scoreFor(Vec3 side) {
      final center = candidateCenter(side);
      double score = -_perimeterDistanceAlong(center, side) * 4.0;

      final c = center.x.floor();
      final r = center.z.floor();
      final k = model.cellAt(r, c);
      switch (k) {
        case _CellKind.pillar:
          score -= 1000.0;
          break;
        case _CellKind.road:
        case _CellKind.road2:
          score -= 0.35;
          break;
        case _CellKind.empty:
          score += 0.16;
          break;
      }

      final towardCenter = Vec3(_pivot.x - center.x, 0, _pivot.z - center.z);
      final dot = towardCenter.x * side.x + towardCenter.z * side.z;
      score -= dot * 0.25;
      return score;
    }

    final leftScore = scoreFor(left);
    final rightScore = scoreFor(right);
    if ((leftScore - rightScore).abs() <= 0.0001) {
      return _perimeterDistanceAlong(candidateCenter(left), left) <=
              _perimeterDistanceAlong(candidateCenter(right), right)
          ? left
          : right;
    }
    return leftScore > rightScore ? left : right;
  }

  _EdgeResult _buildBarrierGateScene({
    required Vec3 thresholdCenter,
    required Vec3 travelDir,
    required double span,
    required _EdgeKind kind,
    required double floorBase,
  }) {
    final faces = <_FacePaint>[];
    final labels = <_TextAnchor>[];

    if (_useMinimalDetailMode) {
      final d = travelDir.length <= 0.000001
          ? const Vec3(0, 0, 1)
          : travelDir.normalized;
      final side = _leftOfTravel(d);
      final gateColor =
          kind == _EdgeKind.entrance ? palette.entrance : palette.exit;
      final cabinetCenter = thresholdCenter + side * (span * 0.78);
      faces.addAll(_buildAxisBox(
        center: cabinetCenter,
        halfX: isOrtho ? 0.08 : 0.10,
        halfZ: isOrtho ? 0.08 : 0.10,
        yBase: floorBase,
        height: isOrtho ? 0.18 : 0.34,
        top: palette.wallTop,
        sideA: palette.wallSideA,
        sideB: palette.wallSideB,
        zKeyBias: 0.0062,
      ).faces);
      faces.addAll(_buildAxisBox(
        center: cabinetCenter - d * 0.08,
        halfX: isOrtho ? 0.04 : 0.05,
        halfZ: isOrtho ? 0.02 : 0.03,
        yBase: floorBase - (isOrtho ? 0.10 : 0.20),
        height: isOrtho ? 0.05 : 0.08,
        top: gateColor,
        sideA: gateColor.withOpacity(0.84),
        sideB: gateColor.withOpacity(0.80),
        zKeyBias: 0.0066,
      ).faces);
      final armStart = cabinetCenter -
          side * (isOrtho ? 0.08 : 0.10) +
          Vec3(0, -(isOrtho ? 0.16 : 0.28), 0);
      final armEnd = armStart + side * -(span * 1.55);
      faces.addAll(_buildSlantedBeam(
        aTopCenter: armStart,
        bTopCenter: armEnd,
        widthDir: d,
        halfWidth: isOrtho ? 0.02 : 0.03,
        depth: isOrtho ? 0.016 : 0.024,
        top: gateColor,
        sideA: gateColor.withOpacity(0.84),
        sideB: gateColor.withOpacity(0.80),
        zKeyBias: 0.0072,
      ).faces);
      return _EdgeResult(faces: faces, labels: labels);
    }

    final d = travelDir.length <= 0.000001
        ? const Vec3(0, 0, 1)
        : travelDir.normalized;
    final left = _leftOfTravel(d);
    final right = _rightOfTravel(d);

    final kioskCream = const Color(0xFFF1E8D9).withOpacity(0.98);
    final kioskCreamA = const Color(0xFFD8CCBA).withOpacity(0.96);
    final kioskCreamB = const Color(0xFFC3B49F).withOpacity(0.92);
    final metallic = const Color(0xFF7B8793).withOpacity(0.96);
    final metallicDark = const Color(0xFF55616D).withOpacity(0.92);
    final boomWhite = const Color(0xFFF6F5F1).withOpacity(0.98);
    final boomWhiteSide = const Color(0xFFD9D6CF).withOpacity(0.96);
    final boomRed = const Color(0xFFE0664D).withOpacity(0.98);
    final boomRedSide = const Color(0xFFC54E39).withOpacity(0.94);
    final ledFace = _ColorUtil.ensureContrast(
      kind == _EdgeKind.entrance
          ? const Color(0xFF2E9B54)
          : const Color(0xFFD84A3A),
      cs.surface,
      fallback: kind == _EdgeKind.entrance ? palette.entrance : palette.exit,
      target: 2.2,
    ).withOpacity(0.94);
    final laneLine = Colors.white.withOpacity(isOrtho ? 0.56 : 0.76);
    final guideFill = _ColorUtil.mix(
      kind == _EdgeKind.entrance ? palette.entrance : palette.exit,
      cs.surface,
      isOrtho ? 0.52 : 0.38,
    ).withOpacity(isOrtho ? 0.34 : 0.30);

    final cabinetHalfCross = isOrtho ? 0.10 : 0.12;
    final cabinetHalfAlong = isOrtho ? 0.10 : 0.12;
    final cabinetHeight = isOrtho ? 0.26 : 0.54;
    final pedestalHeight = isOrtho ? 0.03 : 0.06;
    final mastHeight = isOrtho ? 0.08 : 0.20;
    final armHalfWidth = isOrtho ? 0.030 : 0.040;
    final armDepth = isOrtho ? 0.020 : 0.036;
    final armRise = isOrtho ? 0.10 : 0.26;
    final armReach = (span * 1.92).clamp(0.68, 1.84).toDouble();

    final cabinetSide = _preferredGateCabinetSide(
      thresholdCenter: thresholdCenter,
      travelDir: d,
      left: left,
      right: right,
      span: span,
      cabinetHalfCross: cabinetHalfCross,
    );
    final boomSide = cabinetSide * -1.0;

    final cabinetCenter = thresholdCenter +
        cabinetSide * (span + cabinetHalfCross * 0.86) -
        d * 0.08;
    faces.addAll(_buildAxisBox(
      center: cabinetCenter,
      halfX: cabinetHalfCross,
      halfZ: cabinetHalfAlong,
      yBase: floorBase,
      height: cabinetHeight,
      top: kioskCream,
      sideA: kioskCreamA,
      sideB: kioskCreamB,
      zKeyBias: 0.0062,
    ).faces);

    faces.addAll(_buildAxisBox(
      center: cabinetCenter,
      halfX: cabinetHalfCross * 1.04,
      halfZ: cabinetHalfAlong * 1.06,
      yBase: floorBase + pedestalHeight,
      height: pedestalHeight,
      top: metallic,
      sideA: metallicDark,
      sideB: metallicDark,
      zKeyBias: 0.0060,
    ).faces);

    final screenCenter = cabinetCenter - d * (cabinetHalfAlong * 0.84);
    faces.addAll(_buildAxisBox(
      center: screenCenter,
      halfX: cabinetHalfCross * 0.62,
      halfZ: cabinetHalfAlong * 0.18,
      yBase: floorBase - cabinetHeight * 0.56,
      height: mastHeight,
      top: ledFace,
      sideA: ledFace.withOpacity(0.84),
      sideB: ledFace.withOpacity(0.80),
      zKeyBias: 0.0067,
    ).faces);

    final hingeBase = cabinetCenter - cabinetSide * (cabinetHalfCross * 0.82);
    faces.addAll(_buildAxisBox(
      center: hingeBase,
      halfX: isOrtho ? 0.040 : 0.050,
      halfZ: isOrtho ? 0.040 : 0.050,
      yBase: floorBase - cabinetHeight + 0.001,
      height: isOrtho ? 0.04 : 0.08,
      top: metallicDark,
      sideA: metallicDark,
      sideB: metallicDark,
      zKeyBias: 0.0068,
    ).faces);

    final boomStart = Vec3(
      hingeBase.x,
      floorBase - cabinetHeight - (isOrtho ? 0.03 : 0.06),
      hingeBase.z,
    );
    final boomEnd = boomStart - Vec3(0, armRise, 0) + boomSide * armReach;

    final segments = <({double start, double end, Color top, Color side})>[
      (start: 0.00, end: 0.24, top: boomWhite, side: boomWhiteSide),
      (start: 0.24, end: 0.36, top: boomRed, side: boomRedSide),
      (start: 0.36, end: 0.60, top: boomWhite, side: boomWhiteSide),
      (start: 0.60, end: 0.72, top: boomRed, side: boomRedSide),
      (start: 0.72, end: 0.92, top: boomWhite, side: boomWhiteSide),
      (start: 0.92, end: 1.00, top: metallicDark, side: metallicDark),
    ];
    for (final seg in segments) {
      final aTop = boomStart + (boomEnd - boomStart) * seg.start;
      final bTop = boomStart + (boomEnd - boomStart) * seg.end;
      faces.addAll(_buildSlantedBeam(
        aTopCenter: aTop,
        bTopCenter: bTop,
        widthDir: d,
        halfWidth: armHalfWidth,
        depth: armDepth,
        top: seg.top,
        sideA: seg.side,
        sideB: seg.side,
        zKeyBias: 0.0074 + seg.start * 0.0002,
      ).faces);
    }

    final bollardOffset = cabinetSide * (cabinetHalfCross * 1.8);
    for (final extra in <Vec3>[
      cabinetCenter + bollardOffset - d * 0.12,
      cabinetCenter + bollardOffset + d * 0.12,
    ]) {
      faces.addAll(_buildAxisBox(
        center: extra,
        halfX: isOrtho ? 0.022 : 0.028,
        halfZ: isOrtho ? 0.022 : 0.028,
        yBase: floorBase,
        height: isOrtho ? 0.09 : 0.20,
        top: metallic,
        sideA: metallicDark,
        sideB: metallicDark,
        zKeyBias: 0.0063,
      ).faces);
    }

    final laneCenter = thresholdCenter - d * 0.20;
    final leftEdge = laneCenter + left * (span * 0.74);
    final rightEdge = laneCenter + right * (span * 0.74);
    final laneA = leftEdge - d * 0.44;
    final laneB = leftEdge + d * 0.44;
    final laneC = rightEdge + d * 0.44;
    final laneD = rightEdge - d * 0.44;
    final laneY = floorBase - 0.0012;
    faces.add(_FacePaint(
      pts2: [
        _project(Vec3(laneA.x, laneY, laneA.z)),
        _project(Vec3(laneB.x, laneY, laneB.z)),
        _project(Vec3(laneC.x, laneY, laneC.z)),
        _project(Vec3(laneD.x, laneY, laneD.z)),
      ],
      fill: guideFill,
      zKey: _avgDepth([
            Vec3(laneA.x, laneY, laneA.z),
            Vec3(laneB.x, laneY, laneB.z),
            Vec3(laneC.x, laneY, laneC.z),
            Vec3(laneD.x, laneY, laneD.z),
          ]) +
          0.0056,
    ));

    final stripeHalfW = isOrtho ? 0.016 : 0.022;
    for (final offset in <double>[-0.12, 0.12]) {
      final l0 = thresholdCenter + left * (span * 0.42) + d * offset;
      final l1 = l0 + d * 0.18;
      final r0 = thresholdCenter + right * (span * 0.42) + d * offset;
      final r1 = r0 + d * 0.18;
      faces.addAll(_buildSlantedBeam(
        aTopCenter: Vec3(l0.x, laneY, l0.z),
        bTopCenter: Vec3(l1.x, laneY, l1.z),
        widthDir: left,
        halfWidth: stripeHalfW,
        depth: 0.001,
        top: laneLine,
        sideA: laneLine,
        sideB: laneLine,
        zKeyBias: 0.0059,
      ).faces);
      faces.addAll(_buildSlantedBeam(
        aTopCenter: Vec3(r0.x, laneY, r0.z),
        bTopCenter: Vec3(r1.x, laneY, r1.z),
        widthDir: left,
        halfWidth: stripeHalfW,
        depth: 0.001,
        top: laneLine,
        sideA: laneLine,
        sideB: laneLine,
        zKeyBias: 0.0060,
      ).faces);
    }

    final arrowCenter = thresholdCenter + d * 0.18;
    final arrowY = laneY - 0.0003;
    final len = isOrtho ? 0.18 : 0.24;
    final wing = isOrtho ? 0.08 : 0.10;
    final tip = Vec3(arrowCenter.x + d.x * len * 0.5, arrowY,
        arrowCenter.z + d.z * len * 0.5);
    final back = Vec3(arrowCenter.x - d.x * len * 0.5, arrowY,
        arrowCenter.z - d.z * len * 0.5);
    final lWing = Vec3(back.x + left.x * wing, arrowY, back.z + left.z * wing);
    final rWing =
        Vec3(back.x + right.x * wing, arrowY, back.z + right.z * wing);
    faces.add(_FacePaint(
      pts2: [_project(tip), _project(lWing), _project(back)],
      fill: laneLine,
      zKey: _avgDepth([tip, lWing, back]) + 0.0064,
    ));
    faces.add(_FacePaint(
      pts2: [_project(tip), _project(rWing), _project(back)],
      fill: laneLine,
      zKey: _avgDepth([tip, rWing, back]) + 0.00642,
    ));

    return _EdgeResult(faces: faces, labels: labels);
  }

  _TileResult _buildSlantedBeam({
    required Vec3 aTopCenter,
    required Vec3 bTopCenter,
    required Vec3 widthDir,
    required double halfWidth,
    required double depth,
    required Color top,
    required Color sideA,
    required Color sideB,
    required double zKeyBias,
  }) {
    final w =
        widthDir.length <= 0.000001 ? const Vec3(1, 0, 0) : widthDir.normalized;
    final down = Vec3(0, depth.abs(), 0);

    final a0t = aTopCenter - w * halfWidth;
    final a1t = aTopCenter + w * halfWidth;
    final b0t = bTopCenter + w * halfWidth;
    final b1t = bTopCenter - w * halfWidth;

    final a0 = a0t + down;
    final a1 = a1t + down;
    final b0 = b0t + down;
    final b1 = b1t + down;

    final faces = <_FacePaint>[];
    faces.add(_FacePaint(
      pts2: [_project(a0t), _project(a1t), _project(b0t), _project(b1t)],
      fill: top,
      zKey: _avgDepth([a0t, a1t, b0t, b1t]) + zKeyBias,
    ));

    if (isOrtho) return _TileResult(faces: faces);

    final sA2 =
        _ColorUtil.shiftLightness(sideA, -0.05).withOpacity(sideA.opacity);
    final sB2 =
        _ColorUtil.shiftLightness(sideB, -0.05).withOpacity(sideB.opacity);

    faces.add(_FacePaint(
      pts2: [_project(a0), _project(a1), _project(a1t), _project(a0t)],
      fill: sideA,
      zKey: _avgDepth([a0, a1, a1t, a0t]) + zKeyBias,
    ));
    faces.add(_FacePaint(
      pts2: [_project(a1), _project(b0), _project(b0t), _project(a1t)],
      fill: sideB,
      zKey: _avgDepth([a1, b0, b0t, a1t]) + zKeyBias,
    ));
    faces.add(_FacePaint(
      pts2: [_project(b0), _project(b1), _project(b1t), _project(b0t)],
      fill: sA2,
      zKey: _avgDepth([b0, b1, b1t, b0t]) + zKeyBias,
    ));
    faces.add(_FacePaint(
      pts2: [_project(b1), _project(a0), _project(a0t), _project(b1t)],
      fill: sB2,
      zKey: _avgDepth([b1, a0, a0t, b1t]) + zKeyBias,
    ));

    return _TileResult(faces: faces);
  }

  _TileResult _buildAxisBox({
    required Vec3 center,
    required double halfX,
    required double halfZ,
    required double yBase,
    required double height,
    required Color top,
    required Color sideA,
    required Color sideB,
    required double zKeyBias,
  }) {
    final h = height.abs();

    final v0 = Vec3(center.x - halfX, yBase, center.z - halfZ);
    final v1 = Vec3(center.x + halfX, yBase, center.z - halfZ);
    final v2 = Vec3(center.x + halfX, yBase, center.z + halfZ);
    final v3 = Vec3(center.x - halfX, yBase, center.z + halfZ);

    final v0t = Vec3(v0.x, yBase - h, v0.z);
    final v1t = Vec3(v1.x, yBase - h, v1.z);
    final v2t = Vec3(v2.x, yBase - h, v2.z);
    final v3t = Vec3(v3.x, yBase - h, v3.z);

    final faces = <_FacePaint>[];

    faces.add(_FacePaint(
      pts2: [_project(v0t), _project(v1t), _project(v2t), _project(v3t)],
      fill: top,
      zKey: _avgDepth([v0t, v1t, v2t, v3t]) + zKeyBias,
    ));

    if (isOrtho) return _TileResult(faces: faces);

    final sA2 =
        _ColorUtil.shiftLightness(sideA, -0.06).withOpacity(sideA.opacity);
    final sB2 =
        _ColorUtil.shiftLightness(sideB, -0.06).withOpacity(sideB.opacity);

    faces.add(_FacePaint(
      pts2: [_project(v0), _project(v1), _project(v1t), _project(v0t)],
      fill: sideA,
      zKey: _avgDepth([v0, v1, v1t, v0t]) + zKeyBias,
    ));
    faces.add(_FacePaint(
      pts2: [_project(v1), _project(v2), _project(v2t), _project(v1t)],
      fill: sideB,
      zKey: _avgDepth([v1, v2, v2t, v1t]) + zKeyBias,
    ));
    faces.add(_FacePaint(
      pts2: [_project(v2), _project(v3), _project(v3t), _project(v2t)],
      fill: sA2,
      zKey: _avgDepth([v2, v3, v3t, v2t]) + zKeyBias,
    ));
    faces.add(_FacePaint(
      pts2: [_project(v3), _project(v0), _project(v0t), _project(v3t)],
      fill: sB2,
      zKey: _avgDepth([v3, v0, v0t, v3t]) + zKeyBias,
    ));

    return _TileResult(faces: faces);
  }

  _TileResult _buildEdgePrism({
    required Vec3 a,
    required Vec3 b,
    required double yBase,
    required double thickness,
    required double height,
    required Color top,
    required Color sideA,
    required Color sideB,
    required double zKeyBias,
  }) {
    final h = height.abs();

    final dir = (b - a).normalized;
    final n = Vec3(-dir.z, 0, dir.x);

    final a0 = Vec3(a.x, yBase, a.z) + n * (thickness * 0.5);
    final a1 = Vec3(a.x, yBase, a.z) - n * (thickness * 0.5);
    final b0 = Vec3(b.x, yBase, b.z) + n * (thickness * 0.5);
    final b1 = Vec3(b.x, yBase, b.z) - n * (thickness * 0.5);

    final a0t = Vec3(a0.x, yBase - h, a0.z);
    final a1t = Vec3(a1.x, yBase - h, a1.z);
    final b0t = Vec3(b0.x, yBase - h, b0.z);
    final b1t = Vec3(b1.x, yBase - h, b1.z);

    final faces = <_FacePaint>[];

    faces.add(_FacePaint(
      pts2: [_project(a0t), _project(b0t), _project(b1t), _project(a1t)],
      fill: top,
      zKey: _avgDepth([a0t, b0t, b1t, a1t]) + zKeyBias,
    ));

    if (isOrtho) return _TileResult(faces: faces);

    final sA2 =
        _ColorUtil.shiftLightness(sideA, -0.06).withOpacity(sideA.opacity);
    final sB2 =
        _ColorUtil.shiftLightness(sideB, -0.06).withOpacity(sideB.opacity);

    faces.add(_FacePaint(
      pts2: [_project(a0), _project(b0), _project(b0t), _project(a0t)],
      fill: sideA,
      zKey: _avgDepth([a0, b0, b0t, a0t]) + zKeyBias,
    ));
    faces.add(_FacePaint(
      pts2: [_project(b0), _project(b1), _project(b1t), _project(b0t)],
      fill: sideB,
      zKey: _avgDepth([b0, b1, b1t, b0t]) + zKeyBias,
    ));
    faces.add(_FacePaint(
      pts2: [_project(b1), _project(a1), _project(a1t), _project(b1t)],
      fill: sA2,
      zKey: _avgDepth([b1, a1, a1t, b1t]) + zKeyBias,
    ));
    faces.add(_FacePaint(
      pts2: [_project(a1), _project(a0), _project(a0t), _project(a1t)],
      fill: sB2,
      zKey: _avgDepth([a1, a0, a0t, a1t]) + zKeyBias,
    ));

    return _TileResult(faces: faces);
  }

  @override
  bool shouldRepaint(covariant _ParkingGrid3DPainter oldDelegate) {
    return !oldDelegate.viewRot.nearlyEquals(viewRot) ||
        oldDelegate.isOrtho != isOrtho ||
        oldDelegate.model.renderSignature != model.renderSignature ||
        oldDelegate.cs != cs ||
        oldDelegate.palette != palette;
  }
}

class Vec3 {
  final double x, y, z;

  const Vec3(this.x, this.y, this.z);

  Vec3 operator +(Vec3 o) => Vec3(x + o.x, y + o.y, z + o.z);

  Vec3 operator -(Vec3 o) => Vec3(x - o.x, y - o.y, z - o.z);

  Vec3 operator *(double k) => Vec3(x * k, y * k, z * k);

  Vec3 operator /(double k) => Vec3(x / k, y / k, z / k);

  double dot(Vec3 o) => x * o.x + y * o.y + z * o.z;

  Vec3 cross(Vec3 o) => Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get length => sqrt(x * x + y * y + z * z);

  Vec3 get normalized {
    final l = length;
    if (l <= 0.000001) return const Vec3(0, 0, 0);
    return Vec3(x / l, y / l, z / l);
  }

  Vec3 rotatedAround(Vec3 axis, double angle) {
    final a = axis.normalized;
    final c = cos(angle);
    final s = sin(angle);
    final v = this;

    final term1 = v * c;
    final term2 = a.cross(v) * s;
    final term3 = a * (a.dot(v) * (1 - c));
    return term1 + term2 + term3;
  }
}

class Mat3 {
  final double m00, m01, m02;
  final double m10, m11, m12;
  final double m20, m21, m22;

  const Mat3(this.m00, this.m01, this.m02, this.m10, this.m11, this.m12,
      this.m20, this.m21, this.m22);

  factory Mat3.fromRows(Vec3 r0, Vec3 r1, Vec3 r2) {
    return Mat3(r0.x, r0.y, r0.z, r1.x, r1.y, r1.z, r2.x, r2.y, r2.z);
  }

  Vec3 transform(Vec3 v) {
    return Vec3(
      m00 * v.x + m01 * v.y + m02 * v.z,
      m10 * v.x + m11 * v.y + m12 * v.z,
      m20 * v.x + m21 * v.y + m22 * v.z,
    );
  }

  bool nearlyEquals(Mat3 o, {double eps = 1e-12}) {
    bool eq(double a, double b) => (a - b).abs() <= eps;
    return eq(m00, o.m00) &&
        eq(m01, o.m01) &&
        eq(m02, o.m02) &&
        eq(m10, o.m10) &&
        eq(m11, o.m11) &&
        eq(m12, o.m12) &&
        eq(m20, o.m20) &&
        eq(m21, o.m21) &&
        eq(m22, o.m22);
  }
}

class _TileResult {
  final List<_FacePaint> faces;

  const _TileResult({required this.faces});
}

class _EdgeResult {
  final List<_FacePaint> faces;
  final List<_TextAnchor> labels;
  final List<_AlertOverlay> alerts;

  const _EdgeResult(
      {required this.faces,
      required this.labels,
      this.alerts = const <_AlertOverlay>[]});
}

class _AlertOverlay {
  final List<Offset> pts2;
  final Offset center2;
  final double zKey;

  const _AlertOverlay(
      {required this.pts2, required this.center2, required this.zKey});
}

class _Edge3D {
  final String key;
  final Vec3 a;
  final Vec3 b;

  const _Edge3D({required this.key, required this.a, required this.b});
}

class _FacePaint {
  final List<Offset> pts2;
  final Color fill;
  final double zKey;

  const _FacePaint(
      {required this.pts2, required this.fill, required this.zKey});
}

class _TextAnchor {
  final String text;
  final Offset pos;
  final double zKey;
  final Color textColor;
  final Color bgColor;
  final Color borderColor;

  const _TextAnchor({
    required this.text,
    required this.pos,
    required this.zKey,
    required this.textColor,
    required this.bgColor,
    required this.borderColor,
  });
}
