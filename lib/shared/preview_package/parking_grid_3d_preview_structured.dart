part of 'parking_grid_3d_preview.dart';

extension _ParkingGridStructuredPreviewPart on _ParkingGrid3DPreviewCardState {
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

    return Column(
      children: [
        SizedBox(
          height: _ParkingGrid3DPreviewCardState._previewHeight,
          child: ClipRRect(
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
                child: _ParkingGrid3DView(model: model, palette: palette),
              ),
            ),
          ),
        ),
        const SizedBox(height: _ParkingGrid3DPreviewCardState._footerGap),
        _footerButtons(cs: cs, tt: tt),
      ],
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

  factory _ModelPalette.fromColorScheme(ColorScheme cs) {
    final bg = cs.surfaceContainerLowest;
    final isLight = bg.computeLuminance() > 0.5;

    final canvasA = _ColorUtil.shiftLightness(bg, isLight ? 0.02 : -0.02);
    final canvasB =
        _ColorUtil.mix(bg, cs.surfaceContainerHigh, isLight ? 0.22 : 0.16);

    Color floorTop = _ColorUtil.mix(bg, cs.onSurface, isLight ? 0.12 : 0.16);
    floorTop = _ColorUtil.shiftLightness(floorTop, isLight ? -0.02 : 0.02);
    final floorSideA = _ColorUtil.mix(bg, cs.onSurface, isLight ? 0.18 : 0.22);
    final floorSideB = _ColorUtil.mix(bg, cs.onSurface, isLight ? 0.22 : 0.26);
    final roadBase = _ColorUtil.ensureContrast(cs.primaryContainer, bg,
        fallback: cs.primary, target: 2.2);
    final roadTop = _ColorUtil.shiftLightness(roadBase, isLight ? -0.03 : 0.03)
        .withOpacity(0.88);
    final roadSideA =
        _ColorUtil.shiftLightness(roadBase, isLight ? -0.10 : 0.10)
            .withOpacity(0.62);
    final roadSideB =
        _ColorUtil.shiftLightness(roadBase, isLight ? -0.14 : 0.14)
            .withOpacity(0.58);

    const _road1MarkBase = Color(0xFFFFD54F);
    final roadMark = _ColorUtil.ensureContrast(_road1MarkBase, roadTop,
            fallback: cs.onSurface, target: 2.0)
        .withOpacity(0.55);

    final road2Top = roadTop;
    final road2SideA = roadSideA;
    final road2SideB = roadSideB;
    final road2Mark = _ColorUtil.ensureContrast(Colors.white, roadTop,
            fallback: cs.onSurface, target: 2.0)
        .withOpacity(0.55);

    final pillarBase = _ColorUtil.ensureContrast(cs.tertiaryContainer, bg,
        fallback: cs.tertiary, target: 2.1);
    final pillarTop =
        _ColorUtil.shiftLightness(pillarBase, isLight ? -0.02 : 0.03)
            .withOpacity(0.98);
    final pillarSideA =
        _ColorUtil.shiftLightness(pillarBase, isLight ? -0.12 : 0.12)
            .withOpacity(0.92);
    final pillarSideB =
        _ColorUtil.shiftLightness(pillarBase, isLight ? -0.16 : 0.16)
            .withOpacity(0.88);

    final wallBase = _ColorUtil.ensureContrast(cs.secondaryContainer, bg,
        fallback: cs.secondary, target: 2.0);
    final wallTop = _ColorUtil.shiftLightness(wallBase, isLight ? -0.03 : 0.03)
        .withOpacity(0.84);
    final wallSideA =
        _ColorUtil.shiftLightness(wallBase, isLight ? -0.13 : 0.13)
            .withOpacity(0.68);
    final wallSideB =
        _ColorUtil.shiftLightness(wallBase, isLight ? -0.10 : 0.10)
            .withOpacity(0.72);

    final outline = _ColorUtil.ensureContrast(cs.outlineVariant, bg,
            fallback: cs.onSurface, target: 1.8)
        .withOpacity(0.65);

    final frame = _ColorUtil.ensureContrast(
      _ColorUtil.mix(cs.primary, cs.onSurface, 0.25),
      bg,
      fallback: cs.onSurface,
      target: 2.0,
    ).withOpacity(0.42);

    final entrance = _ColorUtil.ensureContrast(cs.primary, bg,
            fallback: cs.onSurface, target: 2.6)
        .withOpacity(0.86);
    final exit = _ColorUtil.ensureContrast(cs.error, bg,
            fallback: cs.onSurface, target: 2.6)
        .withOpacity(0.86);

    final towerBase = _ColorUtil.ensureContrast(cs.tertiary, bg,
        fallback: cs.tertiaryContainer, target: 2.2);
    final towerTop =
        _ColorUtil.shiftLightness(towerBase, isLight ? -0.02 : 0.02)
            .withOpacity(0.86);
    final towerSideA =
        _ColorUtil.shiftLightness(towerBase, isLight ? -0.12 : 0.12)
            .withOpacity(0.62);
    final towerSideB =
        _ColorUtil.shiftLightness(towerBase, isLight ? -0.16 : 0.16)
            .withOpacity(0.58);
    final towerMark = _ColorUtil.ensureContrast(Colors.white, towerTop,
            fallback: cs.onSurface, target: 2.0)
        .withOpacity(0.58);

    final labelBorder = _ColorUtil.ensureContrast(
      cs.onSurface.withOpacity(0.35),
      bg,
      fallback: cs.onSurface,
      target: 1.8,
    ).withOpacity(0.55);

    final regionFillA = _ColorUtil.ensureContrast(cs.secondaryContainer, bg,
        fallback: cs.secondary, target: 1.8);
    final regionFillB = _ColorUtil.ensureContrast(cs.tertiaryContainer, bg,
        fallback: cs.tertiary, target: 1.8);
    final regionBorder = _ColorUtil.ensureContrast(cs.outline, bg,
            fallback: cs.onSurface, target: 2.0)
        .withOpacity(0.48);

    return _ModelPalette(
      canvasBgA: canvasA,
      canvasBgB: canvasB,
      floorTop: floorTop.withOpacity(0.97),
      floorSideA: floorSideA.withOpacity(0.90),
      floorSideB: floorSideB.withOpacity(0.90),
      roadTop: roadTop,
      roadSideA: roadSideA,
      roadSideB: roadSideB,
      roadMark: roadMark,
      road2Top: road2Top,
      road2SideA: road2SideA,
      road2SideB: road2SideB,
      road2Mark: road2Mark,
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

class _ParkingGrid3DView extends StatefulWidget {
  final _ParkingGridModel model;
  final _ModelPalette palette;

  const _ParkingGrid3DView({
    required this.model,
    required this.palette,
  });

  @override
  State<_ParkingGrid3DView> createState() => _ParkingGrid3DViewState();
}

class _ParkingGrid3DViewState extends State<_ParkingGrid3DView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _alertCtrl;
  late final Animation<double> _alertAnim;

  bool get _hasDepartureAlert {
    if (widget.model.towerStatus == ParkingSlotStatus.departureRequest) {
      return true;
    }
    for (final s in widget.model.childSlots) {
      if (s.status == ParkingSlotStatus.departureRequest) return true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _alertCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 820),
    );
    _alertAnim = CurvedAnimation(parent: _alertCtrl, curve: Curves.easeInOut);
    if (_hasDepartureAlert) _alertCtrl.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _ParkingGrid3DView oldWidget) {
    super.didUpdateWidget(oldWidget);

    bool had = false;
    if (oldWidget.model.towerStatus == ParkingSlotStatus.departureRequest) {
      had = true;
    } else {
      for (final s in oldWidget.model.childSlots) {
        if (s.status == ParkingSlotStatus.departureRequest) {
          had = true;
          break;
        }
      }
    }

    final has = _hasDepartureAlert;
    final disableAnims =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    if (disableAnims) {
      if (_alertCtrl.isAnimating) _alertCtrl.stop();
      _alertCtrl.value = 0.0;
      return;
    }

    if (!had && has) {
      _alertCtrl.repeat(reverse: true);
    } else if (had && !has) {
      _alertCtrl.stop();
      _alertCtrl.value = 0.0;
    }
  }

  @override
  void dispose() {
    _alertCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final right = const Vec3(1, 0, 0);
    final up = const Vec3(0, 0, 1);
    final forward = const Vec3(0, 1, 0);
    final rot = Mat3.fromRows(right, up, forward);

    final disableAnims =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final anim = (!_hasDepartureAlert || disableAnims)
        ? const AlwaysStoppedAnimation<double>(0.0)
        : _alertAnim;

    return CustomPaint(
      painter: _ParkingGrid3DPainter(
        model: widget.model,
        viewRot: rot,
        cs: cs,
        isOrtho: true,
        palette: widget.palette,
        alertAnim: anim,
      ),
      child: const SizedBox.expand(),
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
  final Animation<double> alertAnim;

  _ParkingGrid3DPainter({
    required this.model,
    required this.viewRot,
    required this.cs,
    required this.isOrtho,
    required this.palette,
    required this.alertAnim,
  }) : super(repaint: alertAnim);

  static const double _fitPadding = 14.0;

  static const double _yFloorBottom = 0.0;
  static const double _floorThickness = 0.10;
  static const double _yFloorTop = _yFloorBottom - _floorThickness;
  static const double _ySurfaceEps = 0.001;

  static const double _roadHeight = 0.04;
  static const double _pillarHeightFull = 0.80;
  static const double _pillarHeightLod = 0.12;
  static const double _wallHeightFull = 0.55;
  static const double _wallHeightLod = 0.08;

  static const double _towerHeightFull = 0.72;
  static const double _towerHeightLod = 0.14;

  static const double _childSlotHeight = 0.06;
  static const double _childSlotInset = 0.22;
  static const double _childSlotZBias = 0.0017;

  static const double _wallBaseThickness = 0.06;
  static const double _wallTopHighlightStripPx = 1.6;
  static const double _wallTopViewMinThicknessPx = 3.0;

  late Mat3 _r;
  late double _fitScale;
  late Offset _fitOffset;

  late Vec3 _pivot;
  late double _cameraZ;

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
    _cameraZ = max(8.0, maxDim * 2.2);

    const topY = 0.0;
    final bottomY = isOrtho ? -0.34 : -1.10;

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

    _fitScale = min(availW / spanX, availH / spanY);

    final midX = (minX + maxX) * 0.5;
    final midY = (minY2 + maxY2) * 0.5;

    final center = Offset(size.width * 0.5, size.height * 0.5);
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
      faces.addAll(_buildTowerRects().faces);
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

    _drawFootprintFrame(canvas);

    if (alerts.isNotEmpty) {
      _paintDepartureAlerts(canvas, alerts);
    }

    labels.sort((a, b) => b.zKey.compareTo(a.zKey));
    for (final a in labels) {
      _paintLabel(canvas, a);
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

    double alertStrength(double t) {
      final x = ((t - 0.12) / 0.88).clamp(0.0, 1.0);
      return x * x * (3 - 2 * x);
    }

    final alertT = alertStrength(alertAnim.value.clamp(0.0, 1.0));

    final bg = cs.surfaceContainerLowest;
    final isLightTheme = bg.computeLuminance() > 0.5;

    final baseA = _ColorUtil.ensureContrast(cs.secondaryContainer, bg,
        fallback: cs.secondary, target: 2.0);
    final baseB = _ColorUtil.ensureContrast(cs.tertiaryContainer, bg,
        fallback: cs.tertiary, target: 2.0);

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

    Color markColorFor(Color topColor) {
      final c = _ColorUtil.ensureContrast(cs.onSurface, topColor,
          fallback: cs.onSurface, target: 1.6);
      return c.withOpacity(isOrtho ? 0.22 : 0.20);
    }

    void addStripeOnTop({
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

    const parkedGreen = Color(0xFF2E7D32);
    const departRed = Color(0xFFC62828);
    const reqOrange = Color(0xFFFFA000);

    Color statusBaseColor(ParkingSlotStatus s) {
      switch (s) {
        case ParkingSlotStatus.parked:
          return parkedGreen;
        case ParkingSlotStatus.departureRequest:
          return departRed;
        case ParkingSlotStatus.parkingRequest:
          return reqOrange;
        case ParkingSlotStatus.empty:
          return cs.surfaceContainerLow;
      }
    }


    Color slotCategoryBaseColor(_ChildSlot slot, double fallbackT) {
      switch (slot.shortKindLabel) {
        case '경':
          return _ColorUtil.ensureContrast(
            const Color(0xFF64B5F6),
            bg,
            fallback: const Color(0xFF1565C0),
            target: 1.6,
          );
        case '일':
          return _ColorUtil.ensureContrast(
            cs.secondary,
            bg,
            fallback: cs.secondary,
            target: 1.6,
          );
        case '확A':
        case '확B':
          return _ColorUtil.ensureContrast(
            const Color(0xFFFFD54F),
            bg,
            fallback: const Color(0xFFF9A825),
            target: 1.6,
          );
        case 'EV':
        case 'EV경':
        case 'EV일':
        case 'EV확A':
        case 'EV확B':
          return _ColorUtil.ensureContrast(
            const Color(0xFF66BB6A),
            bg,
            fallback: const Color(0xFF2E7D32),
            target: 1.6,
          );
        case '임A':
        case '임B':
          return _ColorUtil.ensureContrast(
            const Color(0xFFF48FB1),
            bg,
            fallback: const Color(0xFFC2185B),
            target: 1.6,
          );
        case '장':
        case '장일':
        case '장확A':
        case '장확B':
          return _ColorUtil.ensureContrast(
            const Color(0xFF9575CD),
            bg,
            fallback: const Color(0xFF512DA8),
            target: 1.6,
          );
        default:
          return _ColorUtil.mix(baseA, baseB, fallbackT);
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

      final bool isOccupied = s.status != ParkingSlotStatus.empty;
      final bool fromGroupHint = s.statusFromGroup;
      final bool isDeparture = s.status == ParkingSlotStatus.departureRequest;

      final gT = _stableHash01(s.groupName);

      final groupBase = isOccupied
          ? _ColorUtil.ensureContrast(
              statusBaseColor(s.status),
              bg,
              fallback: cs.primary,
              target: 2.0,
            )
          : slotCategoryBaseColor(s, gT);

      double typeDelta;
      if (srN == 1 && scN == 2) {
        typeDelta = isLightTheme ? -0.010 : 0.010;
      } else if (srN == 2 && scN == 1) {
        typeDelta = isLightTheme ? 0.010 : -0.010;
      } else if (srN == 2 && scN == 2) {
        typeDelta = isLightTheme ? 0.030 : -0.030;
      } else {
        typeDelta = 0.0;
      }

      if (isDeparture) {
        typeDelta += (isLightTheme ? -0.10 : 0.10) * alertT;
      }

      final localJitter = ((i % 7) - 3) / 140.0;
      final double emptyOpacity = isOrtho ? 0.46 : 0.36;
      final double occOpacityBase = isOrtho ? 0.62 : 0.52;
      final double occOpacity =
          fromGroupHint ? (occOpacityBase * 0.55) : occOpacityBase;

      double topOpacity = isOccupied ? occOpacity : emptyOpacity;
      if (isDeparture) {
        final base = fromGroupHint ? 0.88 : 1.0;
        topOpacity = (ui.lerpDouble(0.32, 0.98, alertT) ?? 0.32) * base;
      }

      final topColor = _ColorUtil.shiftLightness(groupBase,
              typeDelta + (isLightTheme ? localJitter : -localJitter))
          .withOpacity(topOpacity);

      double sideAOpacity =
          isOccupied ? (isOrtho ? 0.30 : 0.30) : (isOrtho ? 0.20 : 0.22);
      double sideBOpacity =
          isOccupied ? (isOrtho ? 0.26 : 0.28) : (isOrtho ? 0.18 : 0.20);
      if (fromGroupHint) {
        sideAOpacity *= 0.65;
        sideBOpacity *= 0.65;
      }

      final sideA =
          _ColorUtil.shiftLightness(topColor, isLightTheme ? -0.10 : 0.10)
              .withOpacity(sideAOpacity);
      final sideB =
          _ColorUtil.shiftLightness(topColor, isLightTheme ? -0.14 : 0.14)
              .withOpacity(sideBOpacity);

      final cellX0 = cc0.toDouble();
      final cellX1 = (cc1 + 1).toDouble();
      final cellZ0 = rr0.toDouble();
      final cellZ1 = (rr1 + 1).toDouble();

      final spanMin = min(cellX1 - cellX0, cellZ1 - cellZ0);
      final inset = min(_childSlotInset, spanMin * 0.18);

      double x0 = cellX0 + inset;
      double x1 = cellX1 - inset;
      double z0 = cellZ0 + inset;
      double z1 = cellZ1 - inset;

      if (x1 <= x0 + 0.08 || z1 <= z0 + 0.08) {
        final inset2 = min(0.12, spanMin * 0.14);
        x0 = cellX0 + inset2;
        x1 = cellX1 - inset2;
        z0 = cellZ0 + inset2;
        z1 = cellZ1 - inset2;
      }
      if (x1 <= x0 + 0.02 || z1 <= z0 + 0.02) continue;

      final lift = isDeparture ? (0.016 * alertT) : 0.0;
      final yBase = _yFloorTop - 0.0007 - lift;
      final h = _childSlotHeight.abs() + (isDeparture ? (0.010 * alertT) : 0.0);

      final v0 = Vec3(x0, yBase, z0);
      final v1 = Vec3(x1, yBase, z0);
      final v2 = Vec3(x1, yBase, z1);

      final v0t = Vec3(x0, yBase - h, z0);
      final v1t = Vec3(x1, yBase - h, z0);
      final v2t = Vec3(x1, yBase - h, z1);
      final v3t = Vec3(x0, yBase - h, z1);

      final topZ = _avgDepth([v0t, v1t, v2t, v3t]) + _childSlotZBias;

      final topPts2 = [
        _project(v0t),
        _project(v1t),
        _project(v2t),
        _project(v3t)
      ];

      faces.add(_FacePaint(
        pts2: topPts2,
        fill: topColor,
        zKey: topZ,
      ));

      if (isDeparture) {
        final cx2 = (x0 + x1) * 0.5;
        final cz2 = (z0 + z1) * 0.5;
        final center2 = _project(Vec3(cx2, (yBase - h) - 0.0012, cz2));
        alerts.add(
            _AlertOverlay(pts2: topPts2, center2: center2, zKey: topZ + 0.020));
      }

      if (!isOrtho && h > 0.00001) {
        faces.add(_FacePaint(
          pts2: [_project(v0), _project(v1), _project(v1t), _project(v0t)],
          fill: sideA,
          zKey: _avgDepth([v0, v1, v1t, v0t]) + (_childSlotZBias * 0.7),
        ));
        faces.add(_FacePaint(
          pts2: [_project(v1), _project(v2), _project(v2t), _project(v1t)],
          fill: sideB,
          zKey: _avgDepth([v1, v2, v2t, v1t]) + (_childSlotZBias * 0.6),
        ));
      }

      final mark = markColorFor(topColor);
      final yMark = (yBase - h) - 0.0010;

      final spanW = (x1 - x0);
      final spanH = (z1 - z0);
      final thin = min(spanW, spanH) * 0.18;
      final stripe = thin.clamp(0.03, 0.10);

      final cx = (x0 + x1) * 0.5;
      final cz = (z0 + z1) * 0.5;

      if (srN == 1 && scN == 2) {
        addStripeOnTop(
          x0: x0 + 0.06,
          x1: x1 - 0.06,
          z0: cz - stripe * 0.5,
          z1: cz + stripe * 0.5,
          y: yMark,
          fill: mark,
          zKey: topZ + 0.00055,
        );
      } else if (srN == 2 && scN == 1) {
        addStripeOnTop(
          x0: cx - stripe * 0.5,
          x1: cx + stripe * 0.5,
          z0: z0 + 0.06,
          z1: z1 - 0.06,
          y: yMark,
          fill: mark,
          zKey: topZ + 0.00055,
        );
      } else if (srN == 2 && scN == 2) {
        addStripeOnTop(
          x0: x0 + 0.06,
          x1: x1 - 0.06,
          z0: cz - stripe * 0.5,
          z1: cz + stripe * 0.5,
          y: yMark,
          fill: mark,
          zKey: topZ + 0.00060,
        );
        addStripeOnTop(
          x0: cx - stripe * 0.5,
          x1: cx + stripe * 0.5,
          z0: z0 + 0.06,
          z1: z1 - 0.06,
          y: yMark,
          fill: mark,
          zKey: topZ + 0.00062,
        );
      } else {
        final dotW = stripe.clamp(0.03, 0.08);
        addStripeOnTop(
          x0: cx - dotW * 0.5,
          x1: cx + dotW * 0.5,
          z0: cz - dotW * 0.5,
          z1: cz + dotW * 0.5,
          y: yMark,
          fill: mark,
          zKey: topZ + 0.00055,
        );
      }

      final slotLabel = s.badgeLabel;
      if (slotLabel.isNotEmpty) {
        final labelPos = _project(Vec3(cx, (yBase - h) - 0.0022, cz));
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
    }

    return _EdgeResult(faces: faces, labels: labels, alerts: alerts);
  }

  void _paintDepartureAlerts(Canvas canvas, List<_AlertOverlay> overlays) {
    final t0 = alertAnim.value.clamp(0.0, 1.0);
    final x = ((t0 - 0.12) / 0.88).clamp(0.0, 1.0);
    final a = x * x * (3 - 2 * x);
    if (a <= 0.0001) return;

    final bg = cs.surfaceContainerLowest;
    final base = _ColorUtil.ensureContrast(const Color(0xFFFF1744), bg,
        fallback: cs.error, target: 2.6);

    final glowSigma = ui.lerpDouble(2.0, 9.0, a) ?? 6.0;
    final strokeW = ui.lerpDouble(1.8, isOrtho ? 4.0 : 3.2, a) ?? 2.6;
    final coreW = strokeW * 0.62;

    final glowPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW
      ..color = base.withOpacity(ui.lerpDouble(0.10, 0.46, a) ?? 0.22)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round
      ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, glowSigma);

    final corePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = coreW
      ..color = base.withOpacity(ui.lerpDouble(0.28, 0.98, a) ?? 0.60)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;

    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final sorted = List<_AlertOverlay>.from(overlays)
      ..sort((a1, b1) => b1.zKey.compareTo(a1.zKey));

    for (final o in sorted) {
      final path = Path()..addPolygon(o.pts2, true);
      canvas.drawPath(path, glowPaint);
      canvas.drawPath(path, corePaint);

      final r1 = ui.lerpDouble(10.0, 22.0, a) ?? 14.0;
      ringPaint
        ..strokeWidth = ui.lerpDouble(1.2, 2.8, a) ?? 1.8
        ..color = base.withOpacity(ui.lerpDouble(0.00, 0.68, a) ?? 0.25);
      canvas.drawCircle(o.center2, r1, ringPaint);

      final r2 = ui.lerpDouble(22.0, 34.0, a) ?? 26.0;
      ringPaint
        ..strokeWidth = ui.lerpDouble(0.8, 2.0, a) ?? 1.2
        ..color = base.withOpacity(ui.lerpDouble(0.00, 0.36, a) ?? 0.12);
      canvas.drawCircle(o.center2, r2, ringPaint);
    }
  }

  void _paintLabel(Canvas canvas, _TextAnchor a) {
    final tp = TextPainter(
      text: TextSpan(
        text: a.text,
        style: TextStyle(
          color: a.textColor,
          fontWeight: FontWeight.w900,
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
    tp.paint(canvas, a.pos - Offset(tp.width * 0.5, tp.height * 0.5));
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

    if (!isOrtho) {
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

    void addLaneStripe({
      required double x0,
      required double x1,
      required double z0,
      required double z1,
      required double zKeyBias,
    }) {
      final s0 = baseAt + Vec3(x0, laneY, z0);
      final s1 = baseAt + Vec3(x1, laneY, z0);
      final s2 = baseAt + Vec3(x1, laneY, z1);
      final s3 = baseAt + Vec3(x0, laneY, z1);

      faces.add(_FacePaint(
        pts2: [_project(s0), _project(s1), _project(s2), _project(s3)],
        fill: laneColor,
        zKey: _avgDepth([s0, s1, s2, s3]) + zKeyBias,
      ));
    }

    void addArrow({
      required bool alongZ,
      required bool forwardPositive,
      required double zKeyBias,
    }) {
      final y = laneY - 0.0005;
      final arrowFill = laneColor.withOpacity(0.98);

      if (alongZ) {
        final tipZ = forwardPositive ? 0.88 : 0.12;
        final baseZ = forwardPositive ? 0.70 : 0.30;

        final tip = baseAt + Vec3(0.50, y, tipZ);
        final b1 = baseAt + Vec3(0.40, y, baseZ);
        final b2 = baseAt + Vec3(0.60, y, baseZ);

        faces.add(_FacePaint(
          pts2: [_project(tip), _project(b1), _project(b2)],
          fill: arrowFill,
          zKey: _avgDepth([tip, b1, b2]) + zKeyBias,
        ));
      } else {
        final tipX = forwardPositive ? 0.88 : 0.12;
        final baseX = forwardPositive ? 0.70 : 0.30;

        final tip = baseAt + Vec3(tipX, y, 0.50);
        final b1 = baseAt + Vec3(baseX, y, 0.40);
        final b2 = baseAt + Vec3(baseX, y, 0.60);

        faces.add(_FacePaint(
          pts2: [_project(tip), _project(b1), _project(b2)],
          fill: arrowFill,
          zKey: _avgDepth([tip, b1, b2]) + zKeyBias,
        ));
      }
    }

    if (axis == _RoadAxis.z) {
      addLaneStripe(x0: 0.42, x1: 0.58, z0: 0.10, z1: 0.90, zKeyBias: 0.001);
      addArrow(alongZ: true, forwardPositive: true, zKeyBias: 0.0015);
    } else if (axis == _RoadAxis.x) {
      addLaneStripe(x0: 0.10, x1: 0.90, z0: 0.42, z1: 0.58, zKeyBias: 0.001);
      addArrow(alongZ: false, forwardPositive: true, zKeyBias: 0.0015);
    } else if (axis == _RoadAxis.cross) {
      addLaneStripe(x0: 0.42, x1: 0.58, z0: 0.10, z1: 0.90, zKeyBias: 0.001);
      addLaneStripe(x0: 0.10, x1: 0.90, z0: 0.42, z1: 0.58, zKeyBias: 0.0012);
    }

    return _TileResult(faces: faces);
  }

  _TileResult _buildPillarFaces({required Vec3 base}) {
    const w = 0.34;

    final h = (isOrtho ? _pillarHeightLod : _pillarHeightFull).abs();

    final cx = base.x + 0.5;
    final cz = base.z + 0.5;

    final faces = <_FacePaint>[];

    faces.addAll(_buildAxisBox(
      center: Vec3(cx, 0, cz),
      halfX: w,
      halfZ: w,
      yBase: _yFloorTop,
      height: h,
      top: palette.pillarTop,
      sideA: palette.pillarSideA,
      sideB: palette.pillarSideB,
      zKeyBias: 0.0002,
    ).faces);

    final wi = w * 0.66;
    final yTop = _yFloorTop - h - 0.0006;

    final it0 = Vec3(cx - wi, yTop, cz - wi);
    final it1 = Vec3(cx + wi, yTop, cz - wi);
    final it2 = Vec3(cx + wi, yTop, cz + wi);
    final it3 = Vec3(cx - wi, yTop, cz + wi);

    final isLight = cs.surfaceContainerLowest.computeLuminance() > 0.5;
    final insetFill =
        _ColorUtil.shiftLightness(palette.pillarTop, isLight ? 0.05 : -0.05)
            .withOpacity(0.96);
    faces.add(_FacePaint(
      pts2: [_project(it0), _project(it1), _project(it2), _project(it3)],
      fill: insetFill,
      zKey: _avgDepth([it0, it1, it2, it3]) + 0.00018,
    ));

    return _TileResult(faces: faces);
  }

  _TileResult _buildWallRunFaces({required Vec3 a, required Vec3 b}) {
    final h = (isOrtho ? _wallHeightLod : _wallHeightFull).abs();
    final yBase = _yFloorTop - _ySurfaceEps;

    final runLen = (b - a).length;
    if (runLen <= 0.00001) return const _TileResult(faces: []);

    final thickness = _wallThicknessForView();

    final baseRes = _buildEdgePrism(
      a: a,
      b: b,
      yBase: yBase,
      thickness: thickness,
      height: h,
      top: palette.wallTop,
      sideA: palette.wallSideA,
      sideB: palette.wallSideB,
      zKeyBias: 0.0,
    );

    final faces = <_FacePaint>[]..addAll(baseRes.faces);

    final dir = (b - a).normalized;
    final n = Vec3(-dir.z, 0, dir.x);

    final yTop = yBase - h;
    final yTopLift = yTop - 0.0006;

    final a0t = Vec3(a.x, yTopLift, a.z) + n * (thickness * 0.5);
    final a1t = Vec3(a.x, yTopLift, a.z) - n * (thickness * 0.5);
    final b0t = Vec3(b.x, yTopLift, b.z) + n * (thickness * 0.5);
    final b1t = Vec3(b.x, yTopLift, b.z) - n * (thickness * 0.5);

    final isLightTheme = cs.surfaceContainerLowest.computeLuminance() > 0.5;
    final stripW = _wallHighlightStripWorld(thickness);

    final hiFill =
        _ColorUtil.shiftLightness(palette.wallTop, isLightTheme ? 0.08 : -0.08)
            .withOpacity(0.92);
    final loFill =
        _ColorUtil.shiftLightness(palette.wallTop, isLightTheme ? -0.10 : 0.10)
            .withOpacity(0.70);

    final a0i = a0t - n * stripW;
    final b0i = b0t - n * stripW;
    faces.add(_FacePaint(
      pts2: [_project(a0t), _project(b0t), _project(b0i), _project(a0i)],
      fill: hiFill,
      zKey: _avgDepth([a0t, b0t, b0i, a0i]) + 0.0008,
    ));

    final a1i = a1t + n * stripW;
    final b1i = b1t + n * stripW;
    faces.add(_FacePaint(
      pts2: [_project(a1i), _project(b1i), _project(b1t), _project(a1t)],
      fill: loFill,
      zKey: _avgDepth([a1i, b1i, b1t, a1t]) + 0.00075,
    ));

    final bevelLenBase = max(thickness * 0.95, 0.06);
    final bevelLen = min(bevelLenBase, runLen * 0.35);
    final bevelDrop = isOrtho ? 0.0 : 0.035;
    final bevelFillA =
        _ColorUtil.shiftLightness(palette.wallTop, isLightTheme ? 0.06 : -0.06)
            .withOpacity(0.90);
    final bevelFillB =
        _ColorUtil.shiftLightness(palette.wallTop, isLightTheme ? -0.06 : 0.06)
            .withOpacity(0.86);

    if (bevelLen > 0.0001) {
      final s0 = a0t;
      final s1 = a1t;
      final s2 = a1t + dir * bevelLen + Vec3(0, bevelDrop, 0);
      final s3 = a0t + dir * bevelLen + Vec3(0, bevelDrop, 0);

      faces.add(_FacePaint(
        pts2: [_project(s0), _project(s1), _project(s2), _project(s3)],
        fill: bevelFillA,
        zKey: _avgDepth([s0, s1, s2, s3]) + 0.0011,
      ));
    }

    if (bevelLen > 0.0001) {
      final e0 = b0t;
      final e1 = b1t;
      final e2 = b1t - dir * bevelLen + Vec3(0, bevelDrop, 0);
      final e3 = b0t - dir * bevelLen + Vec3(0, bevelDrop, 0);

      faces.add(_FacePaint(
        pts2: [_project(e3), _project(e2), _project(e1), _project(e0)],
        fill: bevelFillB,
        zKey: _avgDepth([e3, e2, e1, e0]) + 0.00105,
      ));
    }

    return _TileResult(faces: faces);
  }

  _TileResult _buildTowerRects() {
    final faces = <_FacePaint>[];
    if (model.towerRects.isEmpty) return _TileResult(faces: faces);

    final bg = cs.surfaceContainerLowest;
    final isLightTheme = bg.computeLuminance() > 0.5;

    Color topFill = palette.towerTop;
    Color sideA = palette.towerSideA;
    Color sideB = palette.towerSideB;
    Color markFill = palette.towerMark;

    final ts = model.towerStatus;
    if (ts != ParkingSlotStatus.empty) {
      const parkedGreen = Color(0xFF2E7D32);
      const departRed = Color(0xFFC62828);
      const reqOrange = Color(0xFFFFA000);

      Color statusBase(ParkingSlotStatus s) {
        switch (s) {
          case ParkingSlotStatus.parked:
            return parkedGreen;
          case ParkingSlotStatus.departureRequest:
            return departRed;
          case ParkingSlotStatus.parkingRequest:
            return reqOrange;
          case ParkingSlotStatus.empty:
            return palette.towerTop;
        }
      }

      final base = _ColorUtil.ensureContrast(
        statusBase(ts),
        bg,
        fallback: cs.onSurface,
        target: 2.0,
      );

      topFill = _ColorUtil.shiftLightness(base, isLightTheme ? -0.02 : 0.02)
          .withOpacity(0.86);
      sideA = _ColorUtil.shiftLightness(base, isLightTheme ? -0.12 : 0.12)
          .withOpacity(0.62);
      sideB = _ColorUtil.shiftLightness(base, isLightTheme ? -0.16 : 0.16)
          .withOpacity(0.58);
      markFill = _ColorUtil.ensureContrast(Colors.white, topFill,
              fallback: cs.onSurface, target: 2.0)
          .withOpacity(0.58);
    }

    final yBase = _yFloorTop - _ySurfaceEps;
    final height = (isOrtho ? _towerHeightLod : _towerHeightFull).abs();

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

      final inset = isOrtho ? 0.10 : 0.12;
      final hx = max(0.05, (x1 - x0) * 0.5 - inset);
      final hz = max(0.05, (z1 - z0) * 0.5 - inset);

      final box = _buildAxisBox(
        center: Vec3(cx, 0, cz),
        halfX: hx,
        halfZ: hz,
        yBase: yBase,
        height: height,
        top: topFill,
        sideA: sideA,
        sideB: sideB,
        zKeyBias: 0.008,
      );
      faces.addAll(box.faces);

      final yTop = (yBase - height) - 0.0011;

      final stripeW = min(hx, hz) * 0.34;
      final stripe = stripeW.clamp(0.06, 0.16);
      final innerX = hx * 0.74;
      final innerZ = hz * 0.74;

      if (innerX > 0.04) {
        final p0 = Vec3(cx - innerX, yTop, cz - stripe * 0.5);
        final p1 = Vec3(cx + innerX, yTop, cz - stripe * 0.5);
        final p2 = Vec3(cx + innerX, yTop, cz + stripe * 0.5);
        final p3 = Vec3(cx - innerX, yTop, cz + stripe * 0.5);

        faces.add(_FacePaint(
          pts2: [_project(p0), _project(p1), _project(p2), _project(p3)],
          fill: markFill,
          zKey: _avgDepth([p0, p1, p2, p3]) + 0.0092,
        ));
      }

      if (innerZ > 0.04) {
        final p0 = Vec3(cx - stripe * 0.5, yTop, cz - innerZ);
        final p1 = Vec3(cx + stripe * 0.5, yTop, cz - innerZ);
        final p2 = Vec3(cx + stripe * 0.5, yTop, cz + innerZ);
        final p3 = Vec3(cx - stripe * 0.5, yTop, cz + innerZ);

        faces.add(_FacePaint(
          pts2: [_project(p0), _project(p1), _project(p2), _project(p3)],
          fill: markFill,
          zKey: _avgDepth([p0, p1, p2, p3]) + 0.0093,
        ));
      }
    }

    return _TileResult(faces: faces);
  }

  _EdgeResult _buildGateRects(
      {required List<GridRect> rects, required _EdgeKind kind}) {
    final faces = <_FacePaint>[];

    final labels = <_TextAnchor>[];

    if (rects.isEmpty) return _EdgeResult(faces: faces, labels: labels);

    final baseFill =
        (kind == _EdgeKind.entrance) ? palette.entrance : palette.exit;
    final iconBase = (kind == _EdgeKind.entrance) ? cs.onPrimary : cs.onError;
    final iconFill = _ColorUtil.ensureContrast(iconBase, baseFill,
            fallback: cs.onSurface, target: 2.0)
        .withOpacity(isOrtho ? 0.78 : 0.74);

    final double tileInset = isOrtho ? 0.06 : 0.08;
    final double opacity = isOrtho ? 0.46 : 0.40;

    double topYForCell(int r, int c) {
      final k = model.cellAt(r, c);
      if (k == _CellKind.road || k == _CellKind.road2) {
        return (_yFloorTop - _roadHeight) - 0.0012;
      }
      return _yFloorTop - 0.0012;
    }

    void addGateArrowIcon(
        {required double midX, required double midZ, required double size}) {
      final toCenter =
          (Vec3(_pivot.x, 0, _pivot.z) - Vec3(midX, 0, midZ)).normalized;
      final d = (kind == _EdgeKind.entrance) ? toCenter : (toCenter * -1.0);
      final perp = Vec3(-d.z, 0, d.x);

      final y = _yFloorTop - 0.00135;

      final tip = Vec3(midX, y, midZ) + d * (size * 0.55);
      final baseC = Vec3(midX, y, midZ) - d * (size * 0.12);
      final b1 = baseC + perp * (size * 0.30);
      final b2 = baseC - perp * (size * 0.30);

      faces.add(_FacePaint(
        pts2: [_project(tip), _project(b1), _project(b2)],
        fill: iconFill,
        zKey: _avgDepth([tip, b1, b2]) + 0.011,
      ));
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
          final x0 = c.toDouble() + tileInset;
          final x1 = (c + 1).toDouble() - tileInset;
          final z0 = r.toDouble() + tileInset;
          final z1 = (r + 1).toDouble() - tileInset;
          if (x1 <= x0 + 0.02 || z1 <= z0 + 0.02) continue;

          final p0 = Vec3(x0, y, z0);
          final p1 = Vec3(x1, y, z0);
          final p2 = Vec3(x1, y, z1);
          final p3 = Vec3(x0, y, z1);

          faces.add(_FacePaint(
            pts2: [_project(p0), _project(p1), _project(p2), _project(p3)],
            fill: baseFill.withOpacity(opacity),
            zKey: _avgDepth([p0, p1, p2, p3]) + 0.0095,
          ));
        }
      }

      final midX = (cc0 + cc1 + 1) * 0.5;
      final midZ = (rr0 + rr1 + 1) * 0.5;
      final rectW = (cc1 - cc0 + 1).toDouble();
      final rectH = (rr1 - rr0 + 1).toDouble();
      final size = (min(rectW, rectH) * 0.34).clamp(0.18, 0.42);
      addGateArrowIcon(midX: midX, midZ: midZ, size: size);
    }

    return _EdgeResult(faces: faces, labels: labels);
  }

  _EdgeResult _buildGate({required _Edge3D edge, required _EdgeKind kind}) {
    final faces = <_FacePaint>[];

    final labels = <_TextAnchor>[];

    final baseFill =
        (kind == _EdgeKind.entrance) ? palette.entrance : palette.exit;
    final baseSide = baseFill.withOpacity(0.90);

    final iconBase = (kind == _EdgeKind.entrance) ? cs.onPrimary : cs.onError;
    final iconFill = _ColorUtil.ensureContrast(iconBase, baseFill,
            fallback: cs.onSurface, target: 2.0)
        .withOpacity(0.80);

    final dir = (edge.b - edge.a).normalized;
    final len = (edge.b - edge.a).length;
    final n = Vec3(-dir.z, 0, dir.x);

    final postHalf = isOrtho ? 0.070 : 0.055;

    final postH = (isOrtho ? 0.34 : 0.45).abs();
    final plateH = (isOrtho ? 0.05 : 0.06).abs();
    final ctrlH = (isOrtho ? 0.16 : 0.20).abs();

    final armT = (isOrtho ? 0.10 : 0.075).abs();
    final armH = (isOrtho ? 0.07 : 0.08).abs();

    final armYBase = (_yFloorTop - _ySurfaceEps) - (isOrtho ? 0.26 : 0.34);

    Vec3 postPos(double t) => edge.a + dir * (len * t);

    final pA = postPos(0.18);
    final pB = postPos(0.82);

    faces.addAll(_buildAxisBox(
      center: Vec3(pA.x, 0, pA.z) + n * (isOrtho ? 0.00 : 0.02),
      halfX: postHalf * 1.55,
      halfZ: postHalf * 1.55,
      yBase: _yFloorTop - _ySurfaceEps,
      height: plateH,
      top: baseFill.withOpacity(0.92),
      sideA: baseSide,
      sideB: baseSide,
      zKeyBias: 0.004,
    ).faces);

    faces.addAll(_buildAxisBox(
      center: Vec3(pB.x, 0, pB.z) + n * (isOrtho ? 0.00 : 0.02),
      halfX: postHalf * 1.55,
      halfZ: postHalf * 1.55,
      yBase: _yFloorTop - _ySurfaceEps,
      height: plateH,
      top: baseFill.withOpacity(0.92),
      sideA: baseSide,
      sideB: baseSide,
      zKeyBias: 0.004,
    ).faces);

    faces.addAll(_buildAxisBox(
      center: pA,
      halfX: postHalf,
      halfZ: postHalf,
      yBase: _yFloorTop - _ySurfaceEps,
      height: postH,
      top: baseFill.withOpacity(0.96),
      sideA: baseSide,
      sideB: baseSide,
      zKeyBias: 0.005,
    ).faces);

    faces.addAll(_buildAxisBox(
      center: pB,
      halfX: postHalf,
      halfZ: postHalf,
      yBase: _yFloorTop - _ySurfaceEps,
      height: postH,
      top: baseFill.withOpacity(0.96),
      sideA: baseSide,
      sideB: baseSide,
      zKeyBias: 0.005,
    ).faces);

    final ctrlCenter =
        pA + n * (isOrtho ? 0.16 : 0.18) + dir * (isOrtho ? 0.00 : 0.02);
    faces.addAll(_buildAxisBox(
      center: ctrlCenter,
      halfX: isOrtho ? 0.11 : 0.12,
      halfZ: isOrtho ? 0.07 : 0.08,
      yBase: _yFloorTop - _ySurfaceEps,
      height: ctrlH,
      top: _ColorUtil.shiftLightness(baseFill, 0.08).withOpacity(0.94),
      sideA: _ColorUtil.shiftLightness(baseSide, -0.06).withOpacity(0.90),
      sideB: _ColorUtil.shiftLightness(baseSide, -0.02).withOpacity(0.90),
      zKeyBias: 0.006,
    ).faces);

    final armStart = edge.a + dir * (len * 0.22);
    final armEnd = edge.b - dir * (len * 0.22);

    final arm = _buildEdgePrism(
      a: armStart,
      b: armEnd,
      yBase: armYBase,
      thickness: armT,
      height: armH,
      top: baseFill.withOpacity(0.99),
      sideA: baseSide,
      sideB: baseSide,
      zKeyBias: 0.007,
    );
    faces.addAll(arm.faces);

    final armLen = (armEnd - armStart).length;
    final stripeHalfLen = armLen * 0.07;
    final stripeHalfW = armT * 0.55;
    final stripeY = (armYBase - armH) - 0.001;

    for (final t in const [0.25, 0.50, 0.75]) {
      final c = armStart + dir * (armLen * t);
      final p0 =
          c - dir * stripeHalfLen - n * stripeHalfW + Vec3(0, stripeY, 0);
      final p1 =
          c + dir * stripeHalfLen - n * stripeHalfW + Vec3(0, stripeY, 0);
      final p2 =
          c + dir * stripeHalfLen + n * stripeHalfW + Vec3(0, stripeY, 0);
      final p3 =
          c - dir * stripeHalfLen + n * stripeHalfW + Vec3(0, stripeY, 0);

      faces.add(_FacePaint(
        pts2: [_project(p0), _project(p1), _project(p2), _project(p3)],
        fill: cs.surface.withOpacity(0.58),
        zKey: _avgDepth([p0, p1, p2, p3]) + 0.008,
      ));
    }

    final mid = (edge.a + edge.b) * 0.5;
    final toCenter =
        (Vec3(_pivot.x, 0, _pivot.z) - Vec3(mid.x, 0, mid.z)).normalized;
    final d = (kind == _EdgeKind.entrance) ? toCenter : (toCenter * -1.0);
    final perp = Vec3(-d.z, 0, d.x);

    final floorY = _yFloorTop - _ySurfaceEps;
    final tip = Vec3(mid.x, floorY, mid.z) + d * 0.52;
    final baseC = Vec3(mid.x, floorY, mid.z) + d * 0.26;
    final b1 = baseC + perp * 0.22;
    final b2 = baseC - perp * 0.22;

    faces.add(_FacePaint(
      pts2: [_project(tip), _project(b1), _project(b2)],
      fill: iconFill,
      zKey: _avgDepth([tip, b1, b2]) + 0.009,
    ));

    return _EdgeResult(faces: faces, labels: labels);
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
        oldDelegate.model != model ||
        oldDelegate.cs != cs ||
        oldDelegate.palette != palette ||
        oldDelegate.alertAnim != alertAnim;
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
