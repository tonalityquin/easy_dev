import 'dart:math';
import 'package:flutter/material.dart';

import '../../../app/di/routes.dart';

part 'parking_visualization_lab_2d_editor.dart';

enum ParkingCellState { empty, road, occupied, blocked, pillar }

enum _ViewPreset { north, east, south, west, top }

enum _CanvasMode { edit2d, preview3d }

enum _EdgeSide { north, east, south, west }

enum _GateKind { entrance, exit, mixed }

@immutable
class _EdgePlacement {
  final int r;
  final int c;
  final _EdgeSide side;

  const _EdgePlacement({required this.r, required this.c, required this.side});

  @override
  bool operator ==(Object other) {
    return other is _EdgePlacement &&
        other.r == r &&
        other.c == c &&
        other.side == side;
  }

  @override
  int get hashCode => Object.hash(r, c, side);
}

bool _isEdgeValid(_EdgePlacement e, int rows, int cols) {
  if (rows <= 0 || cols <= 0) return false;
  if (e.r < 0 || e.r >= rows || e.c < 0 || e.c >= cols) return false;

  final onPerimeter =
      e.r == 0 || e.r == rows - 1 || e.c == 0 || e.c == cols - 1;
  if (!onPerimeter) return false;

  switch (e.side) {
    case _EdgeSide.north:
      return e.r == 0;
    case _EdgeSide.south:
      return e.r == rows - 1;
    case _EdgeSide.west:
      return e.c == 0;
    case _EdgeSide.east:
      return e.c == cols - 1;
  }
}

String _edgeSideLabel(_EdgeSide s) {
  switch (s) {
    case _EdgeSide.north:
      return '북';
    case _EdgeSide.south:
      return '남';
    case _EdgeSide.west:
      return '서';
    case _EdgeSide.east:
      return '동';
  }
}

int _edgeSortKey(_EdgePlacement e) {
  return (e.r * 100000) + (e.c * 10) + e.side.index;
}

typedef _WallGroupId = String;

String _cellStateLabel(ParkingCellState st) {
  switch (st) {
    case ParkingCellState.empty:
      return '빈칸';
    case ParkingCellState.road:
      return '도로';
    case ParkingCellState.occupied:
      return '점유';
    case ParkingCellState.blocked:
      return '차단';
    case ParkingCellState.pillar:
      return '기둥';
  }
}

bool _isParkingZoneState(ParkingCellState s) {
  switch (s) {
    case ParkingCellState.empty:
    case ParkingCellState.occupied:
    case ParkingCellState.blocked:
      return true;
    case ParkingCellState.road:
    case ParkingCellState.pillar:
      return false;
  }
}

int _spotRepCol(int c) => (c ~/ 2) * 2;

int _spotRepIndex(int idx, int cols) {
  if (cols <= 0) return idx;
  final r = idx ~/ cols;
  final c = idx % cols;
  return r * cols + _spotRepCol(c);
}

List<int> _spotIndicesForIndex(int idx, int rows, int cols) {
  if (rows <= 0 || cols <= 0) return const [];
  final total = rows * cols;
  if (idx < 0 || idx >= total) return const [];

  final rep = _spotRepIndex(idx, cols);
  if (rep < 0 || rep >= total) return const [];

  final r = rep ~/ cols;
  final c0 = rep % cols;
  if (r < 0 || r >= rows) return const [];

  final list = <int>[rep];
  if (c0 + 1 < cols) list.add(rep + 1);
  return list;
}

class ParkingVisualizationLabScreen extends StatefulWidget {
  const ParkingVisualizationLabScreen({super.key});

  @override
  State<ParkingVisualizationLabScreen> createState() =>
      _ParkingVisualizationLabScreenState();
}

class _ParkingVisualizationLabScreenState
    extends State<ParkingVisualizationLabScreen> {
  int _rows = 6;
  int _cols = 10;

  late List<ParkingCellState> _cells;

  Map<_EdgePlacement, _WallGroupId?> _walls = <_EdgePlacement, _WallGroupId?>{};

  Map<_WallGroupId, String> _wallGroups = <_WallGroupId, String>{};

  Set<_EdgePlacement> _selectedWalls = <_EdgePlacement>{};

  static const int _maxDim = 30;

  _CanvasMode _canvasMode = _CanvasMode.edit2d;
  _PaintTool _paintTool = _PaintTool.occupied;

  _EdgePlacement? _entranceGate;
  _EdgePlacement? _exitGate;

  double _garageDepth = 1.0;

  _ViewPreset _viewPreset = _ViewPreset.south;
  late _Quat _worldToCamera;

  static const double _kObliqueElev = 0.70;
  static const double _kTopElev = 1.45;

  double _yawForCardinal = 0.0;

  int _selectedCellIndex = -1;

  final ScrollController _topScrollController = ScrollController();
  final ScrollController _bottomScrollController = ScrollController();

  int _wallGroupSeq = 0;

  @override
  void initState() {
    super.initState();
    _cells =
        List<ParkingCellState>.filled(_rows * _cols, ParkingCellState.empty);

    _yawForCardinal = _yawForPreset(_viewPreset);
    _worldToCamera =
        _worldToCameraForPreset(_viewPreset, yawForTop: _yawForCardinal);
  }

  @override
  void dispose() {
    _topScrollController.dispose();
    _bottomScrollController.dispose();
    super.dispose();
  }

  void _goBackToSelector(BuildContext context) {
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.selector,
      (route) => false,
    );
  }

  void _safeJumpToTop(ScrollController c) {
    if (!c.hasClients) return;
    c.jumpTo(0);
  }

  _WallGroupId _newWallGroupId() {
    _wallGroupSeq++;
    return 'wg_${DateTime.now().microsecondsSinceEpoch}_${_wallGroupSeq}';
  }

  void _cleanupWallGroups() {
    final used = _walls.values.whereType<_WallGroupId>().toSet();
    _wallGroups.removeWhere((id, _) => !used.contains(id));
  }

  _WallGroupId? _findGroupIdByName(String name) {
    final target = name.trim();
    if (target.isEmpty) return null;
    for (final e in _wallGroups.entries) {
      if (e.value.trim() == target) return e.key;
    }
    return null;
  }

  int _normalizeSelectionIndex(int idx) {
    if (idx < 0 || idx >= _cells.length) return -1;
    final st = _cells[idx];
    if (_isParkingZoneState(st)) {
      final rep = _spotRepIndex(idx, _cols);
      if (rep >= 0 && rep < _cells.length) return rep;
    }
    return idx;
  }

  bool _isValidSpotAt(int r, int c0) {
    if (r < 0 || r >= _rows) return false;
    if (c0 < 0 || c0 + 1 >= _cols) return false;
    final idx0 = r * _cols + c0;
    final idx1 = idx0 + 1;
    if (idx0 < 0 || idx1 < 0 || idx1 >= _cells.length) return false;
    final a = _cells[idx0];
    final b = _cells[idx1];
    return _isParkingZoneState(a) && a == b;
  }

  int _totalParkingSpots() => _rows * (_cols ~/ 2);

  int _countParkingSpotsOf(ParkingCellState s) {
    if (!_isParkingZoneState(s)) return 0;
    int cnt = 0;
    for (int r = 0; r < _rows; r++) {
      for (int c0 = 0; c0 + 1 < _cols; c0 += 2) {
        final idx0 = r * _cols + c0;
        final idx1 = idx0 + 1;
        if (idx1 >= _cells.length) continue;
        if (_cells[idx0] == s && _cells[idx1] == s) cnt++;
      }
    }
    return cnt;
  }

  int _countOf(ParkingCellState s) {
    if (_isParkingZoneState(s)) return _countParkingSpotsOf(s);

    return _cells.where((c) => c == s).length;
  }

  void _resetAll() {
    setState(() {
      _cells =
          List<ParkingCellState>.filled(_rows * _cols, ParkingCellState.empty);

      _entranceGate = null;
      _exitGate = null;

      _walls = <_EdgePlacement, _WallGroupId?>{};
      _wallGroups = <_WallGroupId, String>{};
      _selectedWalls = <_EdgePlacement>{};

      _paintTool = _PaintTool.occupied;

      _viewPreset = _ViewPreset.south;
      _yawForCardinal = _yawForPreset(_viewPreset);
      _worldToCamera =
          _worldToCameraForPreset(_viewPreset, yawForTop: _yawForCardinal);

      _selectedCellIndex = -1;
      _garageDepth = 1.0;
      _canvasMode = _CanvasMode.edit2d;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _safeJumpToTop(_topScrollController);
      _safeJumpToTop(_bottomScrollController);
    });
  }

  void _randomFill() {
    final rnd = Random();

    setState(() {
      final next = List<ParkingCellState>.from(_cells);

      for (int r = 0; r < _rows; r++) {
        for (int c0 = 0; c0 < _cols; c0 += 2) {
          final idx0 = r * _cols + c0;
          final idx1 = idx0 + 1;

          final v = rnd.nextInt(100);

          ParkingCellState st;
          if (v < 50) {
            st = ParkingCellState.empty;
          } else if (v < 65) {
            st = ParkingCellState.road;
          } else if (v < 88) {
            st = ParkingCellState.occupied;
          } else if (v < 95) {
            st = ParkingCellState.blocked;
          } else {
            st = ParkingCellState.pillar;
          }

          if (idx0 >= 0 && idx0 < next.length) next[idx0] = st;
          if (c0 + 1 < _cols && idx1 >= 0 && idx1 < next.length)
            next[idx1] = st;
        }
      }

      _cells = next;
      _selectedCellIndex = -1;
    });
  }

  void _resizeGrid({required int rows, required int cols}) {
    rows = rows.clamp(1, _maxDim);
    cols = cols.clamp(1, _maxDim);

    final nextCells =
        List<ParkingCellState>.filled(rows * cols, ParkingCellState.empty);

    final minRows = min(_rows, rows);
    final minCols = min(_cols, cols);

    for (int r = 0; r < minRows; r++) {
      for (int c = 0; c < minCols; c++) {
        final oldIdx = r * _cols + c;
        final newIdx = r * cols + c;
        nextCells[newIdx] = _cells[oldIdx];
      }
    }

    setState(() {
      _rows = rows;
      _cols = cols;
      _cells = nextCells;

      if (_selectedCellIndex >= _cells.length) _selectedCellIndex = -1;
      if (_selectedCellIndex >= 0) {
        _selectedCellIndex = _normalizeSelectionIndex(_selectedCellIndex);
      }

      if (_entranceGate != null &&
          !_isEdgeValid(_entranceGate!, _rows, _cols)) {
        _entranceGate = null;
      }
      if (_exitGate != null && !_isEdgeValid(_exitGate!, _rows, _cols)) {
        _exitGate = null;
      }

      final nextWalls = <_EdgePlacement, _WallGroupId?>{};
      for (final e in _walls.entries) {
        if (_isEdgeValid(e.key, _rows, _cols)) {
          nextWalls[e.key] = e.value;
        }
      }
      _walls = nextWalls;

      _selectedWalls = _selectedWalls
          .where((w) => _walls.containsKey(w) && _isEdgeValid(w, _rows, _cols))
          .toSet();

      _cleanupWallGroups();
    });
  }

  Color _cellBg(ColorScheme cs, ParkingCellState state) {
    switch (state) {
      case ParkingCellState.empty:
        return cs.surfaceVariant;
      case ParkingCellState.road:
        return Color.alphaBlend(
            cs.onSurface.withOpacity(0.12), cs.surfaceVariant);
      case ParkingCellState.occupied:
        return cs.primaryContainer;
      case ParkingCellState.blocked:
        return cs.errorContainer;
      case ParkingCellState.pillar:
        return Color.alphaBlend(
            cs.onSurface.withOpacity(0.08), cs.surfaceVariant);
    }
  }

  void _setCanvasMode(_CanvasMode next) {
    if (next == _canvasMode) return;

    setState(() {
      _canvasMode = next;
    });

    if (next == _CanvasMode.preview3d) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (_canvasMode == _CanvasMode.preview3d) {
          _safeJumpToTop(_topScrollController);
        }
      });
    }
  }

  void _setCellsFromEditor(List<ParkingCellState> next) {
    setState(() {
      _cells = next;

      if (_selectedCellIndex >= 0 && _selectedCellIndex < _cells.length) {
        _selectedCellIndex = _normalizeSelectionIndex(_selectedCellIndex);
      } else {
        _selectedCellIndex = -1;
      }
    });
  }

  void _setSelectedCell(int idx) {
    if (idx < 0 || idx >= _cells.length) return;
    setState(() {
      _selectedCellIndex = _normalizeSelectionIndex(idx);
    });
  }

  void _toggleSelectCell(int idx) {
    if (idx < 0 || idx >= _cells.length) return;
    final norm = _normalizeSelectionIndex(idx);
    setState(() {
      _selectedCellIndex = (_selectedCellIndex == norm) ? -1 : norm;
    });
  }

  void _setGates(_EdgePlacement? entrance, _EdgePlacement? exit) {
    setState(() {
      _entranceGate = entrance;
      _exitGate = exit;
    });
  }

  void _setWalls(Map<_EdgePlacement, _WallGroupId?> nextWalls) {
    setState(() {
      _walls = nextWalls;
      _selectedWalls = _selectedWalls.where(_walls.containsKey).toSet();
      _cleanupWallGroups();
    });
  }

  void _setSelectedWalls(Set<_EdgePlacement> nextSelected) {
    setState(() {
      _selectedWalls = nextSelected.where(_walls.containsKey).toSet();
    });
  }

  String _selectedSummary() {
    final idx = _selectedCellIndex;
    if (idx < 0 || idx >= _cells.length) return '선택: 없음';

    final r = idx ~/ _cols;
    final c = idx % _cols;
    final st = _cells[idx];

    if (_isParkingZoneState(st)) {
      final c0 = _spotRepCol(c);
      final validSpot = _isValidSpotAt(r, c0);
      if (validSpot) {
        final label = _cellStateLabel(_cells[r * _cols + c0]);
        return '선택: (${r + 1}행, ${c0 + 1}~${c0 + 2}열) 구역 · $label';
      }

      return '선택: (${r + 1}행, ${c + 1}열) ${_cellStateLabel(st)}';
    }

    return '선택: (${r + 1}행, ${c + 1}열) ${_cellStateLabel(st)}';
  }

  String _gateSummary() {
    String fmt(_EdgePlacement? g) {
      if (g == null) return '없음';
      return '(${g.r + 1}행, ${g.c + 1}열, ${_edgeSideLabel(g.side)}변)';
    }

    final e = _entranceGate;
    final x = _exitGate;

    final mixed = (e != null && x != null && e == x);
    if (mixed) {
      return '게이트: 입/출 혼용 ${fmt(e)}';
    }
    return '게이트: 입구 ${fmt(e)} · 출구 ${fmt(x)}';
  }

  String _wallSummary() {
    final total = _walls.length;
    final sel = _selectedWalls.length;
    final groups = _wallGroups.length;
    if (sel > 0) {
      return '벽: ${total}개 · 그룹 ${groups}개 · 선택 ${sel}개';
    }
    return '벽: ${total}개 · 그룹 ${groups}개';
  }

  _Quat _worldToCameraFromYawElev({required double yaw, required double elev}) {
    final cy = cos(elev);
    final dir = _Vec3(
      sin(yaw) * cy,
      sin(elev),
      cos(yaw) * cy,
    ).normalized();
    return _worldToCameraFromCamDir(dir);
  }

  _Quat _worldToCameraFromCamDir(_Vec3 camDirFromTarget) {
    final worldUp = const _Vec3(0, 1, 0);

    final forward = (-camDirFromTarget).normalized();
    var right = worldUp.cross(forward);
    if (right.len < 1e-6) {
      right = const _Vec3(1, 0, 0).cross(forward);
    }
    right = right.normalized();
    final up = forward.cross(right).normalized();

    return _Quat.fromRotationRows(right, up, forward);
  }

  double _yawForPreset(_ViewPreset p) {
    switch (p) {
      case _ViewPreset.south:
        return 0.0;
      case _ViewPreset.north:
        return pi;
      case _ViewPreset.east:
        return pi / 2;
      case _ViewPreset.west:
        return -pi / 2;
      case _ViewPreset.top:
        return _yawForCardinal;
    }
  }

  _Quat _worldToCameraForPreset(
    _ViewPreset p, {
    required double yawForTop,
  }) {
    switch (p) {
      case _ViewPreset.south:
        return _worldToCameraFromYawElev(yaw: 0.0, elev: _kObliqueElev);
      case _ViewPreset.north:
        return _worldToCameraFromYawElev(yaw: pi, elev: _kObliqueElev);
      case _ViewPreset.east:
        return _worldToCameraFromYawElev(yaw: pi / 2, elev: _kObliqueElev);
      case _ViewPreset.west:
        return _worldToCameraFromYawElev(yaw: -pi / 2, elev: _kObliqueElev);
      case _ViewPreset.top:
        return _worldToCameraFromYawElev(yaw: yawForTop, elev: _kTopElev);
    }
  }

  void _setViewPreset(_ViewPreset p) {
    if (p == _viewPreset) return;
    setState(() {
      _viewPreset = p;

      if (p != _ViewPreset.top) {
        _yawForCardinal = _yawForPreset(p);
      }

      _worldToCamera =
          _worldToCameraForPreset(_viewPreset, yawForTop: _yawForCardinal);
    });
  }

  void _resetCameraPreset() {
    setState(() {
      _viewPreset = _ViewPreset.south;
      _yawForCardinal = _yawForPreset(_viewPreset);
      _worldToCamera =
          _worldToCameraForPreset(_viewPreset, yawForTop: _yawForCardinal);
    });
  }

  String _presetLabel(_ViewPreset p) {
    switch (p) {
      case _ViewPreset.north:
        return '북';
      case _ViewPreset.east:
        return '동';
      case _ViewPreset.south:
        return '남';
      case _ViewPreset.west:
        return '서';
      case _ViewPreset.top:
        return '상단';
    }
  }

  IconData _presetIcon(_ViewPreset p) {
    switch (p) {
      case _ViewPreset.north:
        return Icons.north_rounded;
      case _ViewPreset.east:
        return Icons.east_rounded;
      case _ViewPreset.south:
        return Icons.south_rounded;
      case _ViewPreset.west:
        return Icons.west_rounded;
      case _ViewPreset.top:
        return Icons.vertical_align_top_rounded;
    }
  }

  Widget _viewPresetChip(BuildContext context, _ViewPreset p) {
    final cs = Theme.of(context).colorScheme;
    final selected = _viewPreset == p;
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(
        _presetIcon(p),
        size: 18,
        color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
      ),
      label: Text(
        _presetLabel(p),
        style: const TextStyle(fontWeight: FontWeight.w900),
      ),
      onSelected: (_) => _setViewPreset(p),
    );
  }

  Widget _buildCanvas(BuildContext context) {
    if (_canvasMode == _CanvasMode.edit2d) {
      return _ParkingGarage2DEditor(
        rows: _rows,
        cols: _cols,
        cells: _cells,
        getCellColor: (cs, s) => _cellBg(cs, s),
        selectedCellIndex: _selectedCellIndex,
        onSelectCell: _setSelectedCell,
        onChangedCells: _setCellsFromEditor,
        entranceGate: _entranceGate,
        exitGate: _exitGate,
        onChangedGates: _setGates,
        tool: _paintTool,
        walls: _walls,
        wallGroups: _wallGroups,
        selectedWalls: _selectedWalls,
        onChangedWalls: _setWalls,
        onChangedSelectedWalls: _setSelectedWalls,
      );
    }

    return _ParkingGarage3DView(
      rows: _rows,
      cols: _cols,
      cells: _cells,
      getCellColor: (cs, s) => _cellBg(cs, s),
      depth: _garageDepth,
      worldToCamera: _worldToCamera,
      zoom: 1.0,
      cameraPresetKey: _viewPreset.index,
      selectedCellIndex: _selectedCellIndex,
      interactive: true,
      onTapCell: _toggleSelectCell,
      onLongPressCell: (idx) {
        setState(() {
          final norm = _normalizeSelectionIndex(idx);
          if (_selectedCellIndex == norm) _selectedCellIndex = -1;
        });
      },
      entranceGate: _entranceGate,
      exitGate: _exitGate,
      walls: _walls,
      wallGroups: _wallGroups,
      selectedWalls: _selectedWalls,
    );
  }

  Widget _buildTopCanvasArea(BuildContext context) {
    if (_canvasMode == _CanvasMode.edit2d) {
      return _buildCanvas(context);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportH = constraints.maxHeight;
        final viewportW = constraints.maxWidth;

        const desiredCell = 52.0;
        const extraPad = 20.0;
        final desiredH = (_rows * desiredCell) + extraPad;
        final contentH = max(viewportH, desiredH);

        return Scrollbar(
          controller: _topScrollController,
          child: SingleChildScrollView(
            controller: _topScrollController,
            scrollDirection: Axis.vertical,
            child: SizedBox(
              width: viewportW,
              height: contentH,
              child: _buildCanvas(context),
            ),
          ),
        );
      },
    );
  }

  Widget _paintToolChip(_PaintTool t, IconData icon, String label) {
    final cs = Theme.of(context).colorScheme;
    final selected = _paintTool == t;
    return ChoiceChip(
      selected: selected,
      showCheckmark: false,
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
      ),
      label: Text(label, style: const TextStyle(fontWeight: FontWeight.w900)),
      onSelected: (_) => setState(() => _paintTool = t),
    );
  }

  Future<String?> _promptWallGroupName(BuildContext context,
      {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final cs = Theme.of(context).colorScheme;

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('벽 이름(그룹명) 지정'),
          content: TextField(
            controller: controller,
            autofocus: true,
            textInputAction: TextInputAction.done,
            decoration: const InputDecoration(
              hintText: '예) 북측 벽, 출구앞 벽, 외곽1 ...',
            ),
            onSubmitted: (_) => Navigator.of(ctx).pop(controller.text.trim()),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(null),
              child: const Text('취소'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: cs.primary,
              ),
              onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
              child: const Text('저장'),
            ),
          ],
        );
      },
    );

    final name = result?.trim();
    if (name == null || name.isEmpty) return null;
    return name;
  }

  void _applyNameToSelectedWalls(String name) {
    if (_selectedWalls.isEmpty) return;

    final trimmed = name.trim();
    if (trimmed.isEmpty) return;

    final nextWalls = Map<_EdgePlacement, _WallGroupId?>.from(_walls);
    final nextGroups = Map<_WallGroupId, String>.from(_wallGroups);

    final existingId = _findGroupIdByName(trimmed);
    final gid = existingId ?? _newWallGroupId();

    if (existingId == null) {
      nextGroups[gid] = trimmed;
    }

    for (final w in _selectedWalls) {
      if (nextWalls.containsKey(w)) nextWalls[w] = gid;
    }

    setState(() {
      _walls = nextWalls;
      _wallGroups = nextGroups;
      _cleanupWallGroups();
    });
  }

  void _clearNameOfSelectedWalls() {
    if (_selectedWalls.isEmpty) return;

    final nextWalls = Map<_EdgePlacement, _WallGroupId?>.from(_walls);
    for (final w in _selectedWalls) {
      if (nextWalls.containsKey(w)) nextWalls[w] = null;
    }

    setState(() {
      _walls = nextWalls;
      _cleanupWallGroups();
    });
  }

  void _deleteSelectedWalls() {
    if (_selectedWalls.isEmpty) return;

    final next = Map<_EdgePlacement, _WallGroupId?>.from(_walls);
    for (final w in _selectedWalls) {
      next.remove(w);
    }

    setState(() {
      _walls = next;
      _selectedWalls = <_EdgePlacement>{};
      _cleanupWallGroups();
    });
  }

  Map<_WallGroupId, List<_EdgePlacement>> _wallGroupsToEdges() {
    final groups = <_WallGroupId, List<_EdgePlacement>>{};
    for (final e in _walls.entries) {
      final gid = e.value;
      if (gid == null) continue;
      final name = _wallGroups[gid]?.trim();
      if (name == null || name.isEmpty) continue;
      groups.putIfAbsent(gid, () => <_EdgePlacement>[]).add(e.key);
    }
    return groups;
  }

  Widget _buildBottomPanel(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    Widget modeSwitch() {
      return SegmentedButton<_CanvasMode>(
        segments: const [
          ButtonSegment<_CanvasMode>(
            value: _CanvasMode.edit2d,
            label: Text('2D 편집'),
            icon: Icon(Icons.grid_on_rounded),
          ),
          ButtonSegment<_CanvasMode>(
            value: _CanvasMode.preview3d,
            label: Text('3D 미리보기'),
            icon: Icon(Icons.view_in_ar_rounded),
          ),
        ],
        selected: {_canvasMode},
        showSelectedIcon: false,
        onSelectionChanged: (s) => _setCanvasMode(s.first),
      );
    }

    Widget toolChips2D() {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Wrap(
          spacing: 8,
          children: [
            _paintToolChip(
                _PaintTool.empty, Icons.layers_clear_rounded, '빈칸(구역)'),
            _paintToolChip(_PaintTool.road, Icons.alt_route_rounded, '도로'),
            _paintToolChip(
                _PaintTool.occupied, Icons.local_parking_rounded, '점유(구역)'),
            _paintToolChip(_PaintTool.blocked, Icons.block_rounded, '차단(구역)'),
            _paintToolChip(_PaintTool.pillar, Icons.view_column_rounded, '기둥'),
            const SizedBox(width: 6),
            _paintToolChip(_PaintTool.wall, Icons.fence_rounded, '벽'),
            _paintToolChip(
                _PaintTool.wallEraser, Icons.delete_outline_rounded, '벽삭제'),
            _paintToolChip(
                _PaintTool.wallSelect, Icons.select_all_rounded, '벽선택'),
            const SizedBox(width: 6),
            _paintToolChip(_PaintTool.entrance, Icons.login_rounded, '입구'),
            _paintToolChip(_PaintTool.exit, Icons.logout_rounded, '출구'),
            _paintToolChip(
                _PaintTool.gateEraser, Icons.delete_forever_rounded, '게이트삭제'),
          ],
        ),
      );
    }

    Widget presetChips3D() {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Wrap(
          spacing: 8,
          children: _ViewPreset.values
              .map((p) => _viewPresetChip(context, p))
              .toList(),
        ),
      );
    }

    final stats = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _StatPill(label: '총셀', value: '${_cells.length}'),
        _StatPill(label: '총구역', value: '${_totalParkingSpots()}'),
        _StatPill(label: '빈구역', value: '${_countOf(ParkingCellState.empty)}'),
        _StatPill(
            label: '점유구역', value: '${_countOf(ParkingCellState.occupied)}'),
        _StatPill(
            label: '차단구역', value: '${_countOf(ParkingCellState.blocked)}'),
        _StatPill(label: '도로(셀)', value: '${_countOf(ParkingCellState.road)}'),
        _StatPill(
            label: '기둥(셀)', value: '${_countOf(ParkingCellState.pillar)}'),
        _StatPill(label: '벽', value: '${_walls.length}'),
        _StatPill(label: '그룹', value: '${_wallGroups.length}'),
      ],
    );

    Widget wallPanel2D() {
      final groups = _wallGroupsToEdges();
      final groupIds = groups.keys.toList()
        ..sort((a, b) {
          final an = (_wallGroups[a] ?? '').trim();
          final bn = (_wallGroups[b] ?? '').trim();
          return an.compareTo(bn);
        });

      final unnamedCount = _walls.values.where((gid) => gid == null).length;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('벽(외곽 변)',
              style: (tt.labelLarge ?? const TextStyle(fontSize: 13))
                  .copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _StatPill(label: '선택', value: '${_selectedWalls.length}'),
              _StatPill(label: '이름없음', value: '$unnamedCount'),
              FilledButton.tonalIcon(
                onPressed: _selectedWalls.isEmpty
                    ? null
                    : () async {
                        final name = await _promptWallGroupName(context);
                        if (name == null) return;
                        _applyNameToSelectedWalls(name);
                      },
                icon: const Icon(Icons.edit_rounded),
                label: const Text('이름 지정'),
              ),
              FilledButton.tonalIcon(
                onPressed:
                    _selectedWalls.isEmpty ? null : _clearNameOfSelectedWalls,
                icon: const Icon(Icons.label_off_rounded),
                label: const Text('이름 제거'),
              ),
              FilledButton.tonalIcon(
                onPressed: _selectedWalls.isEmpty ? null : _deleteSelectedWalls,
                icon: const Icon(Icons.delete_rounded),
                label: const Text('선택 삭제'),
              ),
              FilledButton.tonalIcon(
                onPressed: _selectedWalls.isEmpty
                    ? null
                    : () => setState(() => _selectedWalls = <_EdgePlacement>{}),
                icon: const Icon(Icons.deselect_rounded),
                label: const Text('선택 해제'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (groupIds.isNotEmpty) ...[
            Text('벽 그룹(이름)',
                style: (tt.labelMedium ?? const TextStyle(fontSize: 12))
                    .copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Wrap(
                spacing: 8,
                children: [
                  for (final gid in groupIds)
                    FilterChip(
                      selected: false,
                      label: Text(
                        '${_wallGroups[gid] ?? gid} (${groups[gid]!.length})',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      onSelected: (_) {
                        setState(() {
                          _selectedWalls = groups[gid]!.toSet();
                        });
                      },
                    ),
                ],
              ),
            ),
          ] else ...[
            Text('이름이 지정된 벽 그룹이 없습니다.',
                style: (tt.bodySmall ?? const TextStyle(fontSize: 12))
                    .copyWith(color: cs.onSurfaceVariant)),
          ],
        ],
      );
    }

    Widget scrollBody() {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_canvasMode == _CanvasMode.preview3d) ...[
            Text('3D 설정',
                style: (tt.labelLarge ?? const TextStyle(fontSize: 13))
                    .copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            _SliderRow(
              label: '입체감',
              value: _garageDepth,
              min: 0.6,
              max: 1.4,
              onChanged: (v) => setState(() => _garageDepth = v),
            ),
            const SizedBox(height: 8),
            FilledButton.tonalIcon(
              onPressed: _resetCameraPreset,
              icon: const Icon(Icons.center_focus_strong_rounded),
              label: const Text('기본 시점'),
            ),
            const SizedBox(height: 12),
            Divider(height: 1, color: cs.outlineVariant.withOpacity(0.8)),
            const SizedBox(height: 12),
          ],
          stats,
          const SizedBox(height: 10),
          _InfoBanner(
            tone: _BannerTone.neutral,
            text: '${_selectedSummary()}\n'
                '${_gateSummary()}\n'
                '${_wallSummary()}\n'
                '✅ 주차 구역 규칙: 같은 행에서 “가로 2셀 = 1구역”\n'
                '✅ 빈칸/점유/차단 도구는 “구역 단위(2셀 동시)”로 적용/표시/선택/카운트\n'
                '2D: 탭/드래그=적용 · 롱프레스=상태순환(구역은 2셀 동시 순환)\n'
                '도로: “도로” 도구로 통로 셀 배치(2D/3D 표시)\n'
                '게이트: 외곽 셀 탭(외곽 변 자동선택) 설치/삭제\n'
                '벽: 외곽 변에만 설치 가능(게이트와 같은 변에는 동시 불가)\n'
                '벽선택: 외곽 변 탭으로 멀티선택 → “이름 지정”으로 그룹명 부여\n'
                '기둥: 셀에 배치(2D/3D 표시)\n'
                '색: 입구=초록 · 출구=빨강 · 입/출 혼용=노랑',
          ),
          const SizedBox(height: 10),
          if (_canvasMode == _CanvasMode.edit2d) ...[
            wallPanel2D(),
            const SizedBox(height: 10),
            Divider(height: 1, color: cs.outlineVariant.withOpacity(0.8)),
            const SizedBox(height: 10),
          ],
          Text('그리드',
              style: (tt.labelLarge ?? const TextStyle(fontSize: 13))
                  .copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              _DimControl(
                label: '행',
                value: _rows,
                onMinus: () => _resizeGrid(rows: _rows - 1, cols: _cols),
                onPlus: () => _resizeGrid(rows: _rows + 1, cols: _cols),
              ),
              _DimControl(
                label: '열',
                value: _cols,
                onMinus: () => _resizeGrid(rows: _rows, cols: _cols - 1),
                onPlus: () => _resizeGrid(rows: _rows, cols: _cols + 1),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _randomFill,
                icon: const Icon(Icons.casino_rounded),
                label: const Text('랜덤'),
              ),
              FilledButton.tonalIcon(
                onPressed: _resetAll,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('초기화'),
              ),
              FilledButton.icon(
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Practice Space로 돌아가기'),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '모드',
          style: (tt.titleSmall ?? const TextStyle(fontSize: 14))
              .copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        modeSwitch(),
        const SizedBox(height: 10),
        if (_canvasMode == _CanvasMode.edit2d) ...[
          Text('도구',
              style: (tt.labelLarge ?? const TextStyle(fontSize: 13))
                  .copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          toolChips2D(),
        ] else ...[
          Text('시점(프리셋)',
              style: (tt.labelLarge ?? const TextStyle(fontSize: 13))
                  .copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 6),
          presetChips3D(),
        ],
        const SizedBox(height: 10),
        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.8)),
        const SizedBox(height: 10),
        Expanded(
          child: Scrollbar(
            controller: _bottomScrollController,
            child: SingleChildScrollView(
              controller: _bottomScrollController,
              child: scrollBody(),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('실험: 주차 구역 시각화 (Sandbox)'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'Selector로 이동',
            onPressed: () => _goBackToSelector(context),
            icon: const Icon(Icons.home_rounded),
          ),
        ],
      ),
      backgroundColor: cs.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Expanded(
                flex: 3,
                child: Card(
                  elevation: 1,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildTopCanvasArea(context),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                flex: 7,
                child: Card(
                  elevation: 1,
                  clipBehavior: Clip.antiAlias,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildBottomPanel(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

typedef _CellColorResolver = Color Function(ColorScheme cs, ParkingCellState s);

@immutable
class _Vec3 {
  final double x;
  final double y;
  final double z;

  const _Vec3(this.x, this.y, this.z);

  _Vec3 operator +(_Vec3 o) => _Vec3(x + o.x, y + o.y, z + o.z);

  _Vec3 operator -(_Vec3 o) => _Vec3(x + -o.x, y + -o.y, z + -o.z);

  _Vec3 operator -() => _Vec3(-x, -y, -z);

  _Vec3 operator *(double s) => _Vec3(x * s, y * s, z * s);

  _Vec3 operator /(double s) => _Vec3(x / s, y / s, z / s);

  double dot(_Vec3 o) => x * o.x + y * o.y + z * o.z;

  _Vec3 cross(_Vec3 o) => _Vec3(
        y * o.z - z * o.y,
        z * o.x - x * o.z,
        x * o.y - y * o.x,
      );

  double get len => sqrt(dot(this));

  _Vec3 normalized() {
    final l = len;
    if (l <= 1e-9) return const _Vec3(0, 0, 0);
    return this / l;
  }
}

@immutable
class _Quat {
  final double w;
  final double x;
  final double y;
  final double z;

  const _Quat(this.w, this.x, this.y, this.z);

  static const identity = _Quat(1, 0, 0, 0);

  _Quat conjugate() => _Quat(w, -x, -y, -z);

  _Quat normalized() {
    final n = sqrt(w * w + x * x + y * y + z * z);
    if (n <= 1e-9) return identity;
    return _Quat(w / n, x / n, y / n, z / n);
  }

  _Quat operator *(_Quat o) {
    return _Quat(
      w * o.w - x * o.x - y * o.y - z * o.z,
      w * o.x + x * o.w + y * o.z - z * o.y,
      w * o.y - x * o.z + y * o.w + z * o.x,
      w * o.z + x * o.y - y * o.x + z * o.w,
    );
  }

  _Vec3 rotate(_Vec3 v) {
    final qv = _Quat(0, v.x, v.y, v.z);
    final r = this * qv * conjugate();
    return _Vec3(r.x, r.y, r.z);
  }

  static _Quat fromRotationRows(_Vec3 r, _Vec3 u, _Vec3 f) {
    final r00 = r.x, r01 = r.y, r02 = r.z;
    final r10 = u.x, r11 = u.y, r12 = u.z;
    final r20 = f.x, r21 = f.y, r22 = f.z;

    final trace = r00 + r11 + r22;
    double qw, qx, qy, qz;

    if (trace > 0) {
      final s = sqrt(trace + 1.0) * 2.0;
      qw = 0.25 * s;
      qx = (r21 - r12) / s;
      qy = (r02 - r20) / s;
      qz = (r10 - r01) / s;
    } else if (r00 > r11 && r00 > r22) {
      final s = sqrt(1.0 + r00 - r11 - r22) * 2.0;
      qw = (r21 - r12) / s;
      qx = 0.25 * s;
      qy = (r01 + r10) / s;
      qz = (r02 + r20) / s;
    } else if (r11 > r22) {
      final s = sqrt(1.0 + r11 - r00 - r22) * 2.0;
      qw = (r02 - r20) / s;
      qx = (r01 + r10) / s;
      qy = 0.25 * s;
      qz = (r12 + r21) / s;
    } else {
      final s = sqrt(1.0 + r22 - r00 - r11) * 2.0;
      qw = (r10 - r01) / s;
      qx = (r02 + r20) / s;
      qy = (r12 + r21) / s;
      qz = 0.25 * s;
    }

    return _Quat(qw, qx, qy, qz).normalized();
  }
}

@immutable
class _GarageMetricsKey {
  final int rows;
  final int cols;

  final int depthMilli;
  final int zoomMilli;

  final int presetKey;

  final int qwMicro;
  final int qxMicro;
  final int qyMicro;
  final int qzMicro;

  const _GarageMetricsKey({
    required this.rows,
    required this.cols,
    required this.depthMilli,
    required this.zoomMilli,
    required this.presetKey,
    required this.qwMicro,
    required this.qxMicro,
    required this.qyMicro,
    required this.qzMicro,
  });

  static int _milli(double v) => (v * 1000.0).round();

  static int _micro(double v) => (v * 1000000.0).round();

  factory _GarageMetricsKey.fromInputs({
    required int rows,
    required int cols,
    required double depth,
    required double zoom,
    required int presetKey,
    required _Quat worldToCamera,
  }) {
    return _GarageMetricsKey(
      rows: rows,
      cols: cols,
      depthMilli: _milli(depth),
      zoomMilli: _milli(zoom),
      presetKey: presetKey,
      qwMicro: _micro(worldToCamera.w),
      qxMicro: _micro(worldToCamera.x),
      qyMicro: _micro(worldToCamera.y),
      qzMicro: _micro(worldToCamera.z),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is _GarageMetricsKey &&
        other.rows == rows &&
        other.cols == cols &&
        other.depthMilli == depthMilli &&
        other.zoomMilli == zoomMilli &&
        other.presetKey == presetKey &&
        other.qwMicro == qwMicro &&
        other.qxMicro == qxMicro &&
        other.qyMicro == qyMicro &&
        other.qzMicro == qzMicro;
  }

  @override
  int get hashCode => Object.hash(
        rows,
        cols,
        depthMilli,
        zoomMilli,
        presetKey,
        qwMicro,
        qxMicro,
        qyMicro,
        qzMicro,
      );
}

class _ParkingGarage3DView extends StatelessWidget {
  final int rows;
  final int cols;
  final List<ParkingCellState> cells;
  final _CellColorResolver getCellColor;

  final double depth;

  final _Quat worldToCamera;
  final double zoom;

  final int cameraPresetKey;

  final int selectedCellIndex;

  final bool interactive;
  final ValueChanged<int> onTapCell;
  final ValueChanged<int> onLongPressCell;

  final _EdgePlacement? entranceGate;
  final _EdgePlacement? exitGate;

  final Map<_EdgePlacement, _WallGroupId?> walls;
  final Map<_WallGroupId, String> wallGroups;
  final Set<_EdgePlacement> selectedWalls;

  const _ParkingGarage3DView({
    required this.rows,
    required this.cols,
    required this.cells,
    required this.getCellColor,
    required this.depth,
    required this.worldToCamera,
    required this.zoom,
    required this.cameraPresetKey,
    required this.selectedCellIndex,
    required this.interactive,
    required this.onTapCell,
    required this.onLongPressCell,
    required this.entranceGate,
    required this.exitGate,
    required this.walls,
    required this.wallGroups,
    required this.selectedWalls,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, constraints.maxHeight);
        final metrics = _GarageMetrics.fit(
          size: size,
          rows: rows,
          cols: cols,
          depth: depth,
          worldToCamera: worldToCamera,
          zoom: zoom,
          presetKey: cameraPresetKey,
        );

        final paint = CustomPaint(
          painter: _ParkingGaragePainter(
            rows: rows,
            cols: cols,
            cells: cells,
            colorResolver: getCellColor,
            metrics: metrics,
            colorScheme: cs,
            selectedCellIndex: selectedCellIndex,
            entranceGate: entranceGate,
            exitGate: exitGate,
            walls: walls,
            wallGroups: wallGroups,
            selectedWalls: selectedWalls,
          ),
          child: const SizedBox.expand(),
        );

        if (!interactive) return paint;

        final order = metrics.paintOrder();

        int hitTest(Offset pos) {
          for (int i = order.length - 1; i >= 0; i--) {
            final idx = order[i];
            if (idx < 0 || idx >= cells.length) continue;

            final r = idx ~/ cols;
            final c = idx % cols;
            if (r < 0 || r >= rows || c < 0 || c >= cols) continue;

            final st = cells[idx];
            final h = metrics.tileHeight(st);
            final topPath = metrics.topFacePath(r, c, h);
            if (topPath.contains(pos)) return idx;
          }
          return -1;
        }

        int normalizeSelectionIdx(int idx) {
          if (idx < 0 || idx >= cells.length) return -1;
          final st = cells[idx];
          if (_isParkingZoneState(st)) {
            final rep = _spotRepIndex(idx, cols);
            if (rep >= 0 && rep < cells.length) return rep;
          }
          return idx;
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            final idx = hitTest(d.localPosition);
            final norm = normalizeSelectionIdx(idx);
            if (norm >= 0 && norm < cells.length) onTapCell(norm);
          },
          onLongPressStart: (d) {
            final idx = hitTest(d.localPosition);
            final norm = normalizeSelectionIdx(idx);
            if (norm >= 0 && norm < cells.length) onLongPressCell(norm);
          },
          child: paint,
        );
      },
    );
  }
}

class _GarageMetrics {
  final int rows;
  final int cols;

  final double tileW;

  final double maxExtrude;

  final double depth;

  final Offset origin;

  final _Quat worldToCamera;
  final double zoom;
  final double cameraDist;
  final double focalLen;

  final double centerX;
  final double centerZ;

  final _GarageMetricsKey key;

  const _GarageMetrics({
    required this.rows,
    required this.cols,
    required this.tileW,
    required this.maxExtrude,
    required this.depth,
    required this.origin,
    required this.worldToCamera,
    required this.zoom,
    required this.cameraDist,
    required this.focalLen,
    required this.centerX,
    required this.centerZ,
    required this.key,
  });

  static const double _kTileEmpty = 0.10;
  static const double _kTileRoad = 0.08;
  static const double _kTileOccupied = 0.42;
  static const double _kTileBlocked = 0.30;
  static const double _kPillar = 0.70;

  static const double _kWall = 0.62;

  static _GarageMetrics fit({
    required Size size,
    required int rows,
    required int cols,
    required double depth,
    required _Quat worldToCamera,
    required double zoom,
    required int presetKey,
  }) {
    const padding = 14.0;

    final cx = cols / 2.0;
    final cz = rows / 2.0;

    final span = max(rows, cols).toDouble().clamp(2.0, 60.0);
    final cam = (span * 1.55) / zoom.clamp(0.6, 2.2);
    final f = cam * 0.95;

    _Vec3 toCam(_Vec3 p) {
      final centered = _Vec3(p.x - cx, p.y, p.z - cz);
      return worldToCamera.rotate(centered);
    }

    Offset projUnit(_Vec3 p) {
      final pr = toCam(p);
      final zCam = pr.z + cam;
      final k = f / max(0.15, zCam);
      return Offset(pr.x * k, -pr.y * k);
    }

    final d = depth.clamp(0.6, 1.4);

    final pillarTop = (_kTileEmpty + _kPillar) * d;

    final tileTop =
        max(_kTileEmpty, max(_kTileRoad, max(_kTileOccupied, _kTileBlocked))) *
            d;

    final wallTop = _kWall * d;

    final maxY = max(tileTop, max(pillarTop, wallTop));

    final points = <_Vec3>[
      _Vec3(0, 0, 0),
      _Vec3(cols.toDouble(), 0, 0),
      _Vec3(cols.toDouble(), 0, rows.toDouble()),
      _Vec3(0, 0, rows.toDouble()),
      _Vec3(0, maxY, 0),
      _Vec3(cols.toDouble(), maxY, 0),
      _Vec3(cols.toDouble(), maxY, rows.toDouble()),
      _Vec3(0, maxY, rows.toDouble()),
    ];

    double minX = double.infinity, minY2 = double.infinity;
    double maxX = -double.infinity, maxY2 = -double.infinity;

    for (final p in points) {
      final o = projUnit(p);
      minX = min(minX, o.dx);
      minY2 = min(minY2, o.dy);
      maxX = max(maxX, o.dx);
      maxY2 = max(maxY2, o.dy);
    }

    final boxW = max(1e-6, maxX - minX);
    final boxH = max(1e-6, maxY2 - minY2);

    final availW = max(40.0, size.width - 2 * padding);
    final availH = max(40.0, size.height - 2 * padding);

    final scale = min(availW / boxW, availH / boxH).clamp(10.0, 110.0);

    final wPx = boxW * scale;
    final hPx = boxH * scale;

    final ox = (size.width - wPx) / 2 - minX * scale;
    final oy = (size.height - hPx) / 2 - minY2 * scale;

    final key = _GarageMetricsKey.fromInputs(
      rows: rows,
      cols: cols,
      depth: depth,
      zoom: zoom,
      presetKey: presetKey,
      worldToCamera: worldToCamera,
    );

    return _GarageMetrics(
      rows: rows,
      cols: cols,
      tileW: scale,
      maxExtrude: maxY,
      depth: depth,
      origin: Offset(ox, oy),
      worldToCamera: worldToCamera,
      zoom: zoom,
      cameraDist: cam,
      focalLen: f,
      centerX: cx,
      centerZ: cz,
      key: key,
    );
  }

  _Vec3 _toCamera(_Vec3 p) {
    final centered = _Vec3(p.x - centerX, p.y, p.z - centerZ);
    return worldToCamera.rotate(centered);
  }

  double cameraZ(_Vec3 p) => _toCamera(p).z;

  double _kFor(_Vec3 p) {
    final camP = _toCamera(p);
    final zCam = camP.z + cameraDist;
    return focalLen / max(0.15, zCam);
  }

  Offset project(_Vec3 p) {
    final camP = _toCamera(p);
    final zCam = camP.z + cameraDist;
    final k = focalLen / max(0.15, zCam);
    final u = Offset(camP.x * k, -camP.y * k);
    return Offset(origin.dx + u.dx * tileW, origin.dy + u.dy * tileW);
  }

  double pxUnitAt(_Vec3 p) => tileW * _kFor(p);

  List<_Vec3> tileCorners3D(int r, int c, double y) {
    final x0 = c.toDouble();
    final x1 = (c + 1).toDouble();
    final z0 = r.toDouble();
    final z1 = (r + 1).toDouble();
    return [
      _Vec3(x0, y, z0),
      _Vec3(x1, y, z0),
      _Vec3(x1, y, z1),
      _Vec3(x0, y, z1),
    ];
  }

  List<Offset> tileCorners2D(int r, int c, double y) =>
      tileCorners3D(r, c, y).map(project).toList();

  _Vec3 cellCenter3D(int r, int c, {double y = 0}) =>
      _Vec3(c + 0.5, y, r + 0.5);

  double tileHeight(ParkingCellState s) {
    final d = depth.clamp(0.6, 1.4);
    switch (s) {
      case ParkingCellState.empty:
        return _kTileEmpty * d;
      case ParkingCellState.road:
        return _kTileRoad * d;
      case ParkingCellState.occupied:
        return _kTileOccupied * d;
      case ParkingCellState.blocked:
        return _kTileBlocked * d;
      case ParkingCellState.pillar:
        return _kTileEmpty * d;
    }
  }

  double pillarHeight() => _kPillar * depth.clamp(0.6, 1.4);

  double wallHeight() => _kWall * depth.clamp(0.6, 1.4);

  Path topFacePath(int r, int c, double h) {
    final pts = tileCorners2D(r, c, h);
    return Path()
      ..moveTo(pts[0].dx, pts[0].dy)
      ..lineTo(pts[1].dx, pts[1].dy)
      ..lineTo(pts[2].dx, pts[2].dy)
      ..lineTo(pts[3].dx, pts[3].dy)
      ..close();
  }

  List<int> paintOrder() {
    final total = rows * cols;
    final list = List<int>.generate(total, (i) => i);
    list.sort((a, b) {
      final ar = a ~/ cols, ac = a % cols;
      final br = b ~/ cols, bc = b % cols;
      final za = cameraZ(_Vec3(ac + 0.5, 0, ar + 0.5));
      final zb = cameraZ(_Vec3(bc + 0.5, 0, br + 0.5));
      return zb.compareTo(za);
    });
    return list;
  }

  List<Offset> floorCorners2D() {
    final a = project(const _Vec3(0, 0, 0));
    final b = project(_Vec3(cols.toDouble(), 0, 0));
    final c = project(_Vec3(cols.toDouble(), 0, rows.toDouble()));
    final d = project(_Vec3(0, 0, rows.toDouble()));
    return [a, b, c, d];
  }
}

enum _DrawItemType { cell, wall, gate }

class _DrawItem {
  final _DrawItemType type;
  final double zKey;
  final int cellIndex;
  final _EdgePlacement? edge;
  final _GateKind? gateKind;

  const _DrawItem._(
      {required this.type,
      required this.zKey,
      required this.cellIndex,
      required this.edge,
      required this.gateKind});

  factory _DrawItem.cell({required int idx, required double zKey}) =>
      _DrawItem._(
          type: _DrawItemType.cell,
          zKey: zKey,
          cellIndex: idx,
          edge: null,
          gateKind: null);

  factory _DrawItem.wall({required _EdgePlacement e, required double zKey}) =>
      _DrawItem._(
          type: _DrawItemType.wall,
          zKey: zKey,
          cellIndex: -1,
          edge: e,
          gateKind: null);

  factory _DrawItem.gate(
          {required _EdgePlacement e,
          required _GateKind kind,
          required double zKey}) =>
      _DrawItem._(
          type: _DrawItemType.gate,
          zKey: zKey,
          cellIndex: -1,
          edge: e,
          gateKind: kind);
}

class _WallLabelAnchor3D {
  final Offset pos;
  final double unit;
  final double zKey;

  const _WallLabelAnchor3D({
    required this.pos,
    required this.unit,
    required this.zKey,
  });
}

class _WallGroupLabelItem {
  final _WallGroupId gid;
  final String name;
  final _EdgePlacement rep;
  final bool sel;
  final _WallLabelAnchor3D anchor;

  const _WallGroupLabelItem({
    required this.gid,
    required this.name,
    required this.rep,
    required this.sel,
    required this.anchor,
  });
}

class _ParkingGaragePainter extends CustomPainter {
  final int rows;
  final int cols;
  final List<ParkingCellState> cells;

  final _CellColorResolver colorResolver;
  final _GarageMetrics metrics;
  final ColorScheme colorScheme;

  final int selectedCellIndex;

  final _EdgePlacement? entranceGate;
  final _EdgePlacement? exitGate;

  final Map<_EdgePlacement, _WallGroupId?> walls;
  final Map<_WallGroupId, String> wallGroups;
  final Set<_EdgePlacement> selectedWalls;

  _ParkingGaragePainter({
    required this.rows,
    required this.cols,
    required this.cells,
    required this.colorResolver,
    required this.metrics,
    required this.colorScheme,
    required this.selectedCellIndex,
    required this.entranceGate,
    required this.exitGate,
    required this.walls,
    required this.wallGroups,
    required this.selectedWalls,
  });

  Color _shade(Color c, double deltaLightness) {
    final hsl = HSLColor.fromColor(c);
    final nextL = (hsl.lightness + deltaLightness).clamp(0.0, 1.0);
    return hsl.withLightness(nextL).toColor();
  }

  bool _isValidSpotPair(int r, int c0) {
    if (r < 0 || r >= rows) return false;
    if (c0 < 0 || c0 + 1 >= cols) return false;
    final idx0 = r * cols + c0;
    final idx1 = idx0 + 1;
    if (idx0 < 0 || idx1 < 0 || idx1 >= cells.length) return false;
    final a = cells[idx0];
    final b = cells[idx1];
    return _isParkingZoneState(a) && a == b;
  }

  List<int> _selectedHighlightIndices() {
    final sel = selectedCellIndex;
    if (sel < 0 || sel >= cells.length) return const [];
    final r = sel ~/ cols;
    final c = sel % cols;
    final c0 = _spotRepCol(c);

    if (_isParkingZoneState(cells[sel]) && _isValidSpotPair(r, c0)) {
      final rep = r * cols + c0;
      return [rep, rep + 1];
    }
    return [sel];
  }

  void _drawFloor(Canvas canvas) {
    final cs = colorScheme;
    final corners = metrics.floorCorners2D();

    final floorPath = Path()
      ..moveTo(corners[0].dx, corners[0].dy)
      ..lineTo(corners[1].dx, corners[1].dy)
      ..lineTo(corners[2].dx, corners[2].dy)
      ..lineTo(corners[3].dx, corners[3].dy)
      ..close();

    final baseFloor = _shade(cs.surfaceVariant, 0.04);
    final floorPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = baseFloor;

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = cs.outlineVariant.withOpacity(0.95);

    canvas.drawPath(floorPath, floorPaint);
    canvas.drawPath(floorPath, borderPaint);

    final gridLine = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = cs.outlineVariant.withOpacity(0.22);

    for (int r = 0; r <= rows; r++) {
      final a = metrics.project(_Vec3(0, 0, r.toDouble()));
      final b = metrics.project(_Vec3(cols.toDouble(), 0, r.toDouble()));
      canvas.drawLine(a, b, gridLine);
    }
    for (int c = 0; c <= cols; c++) {
      final a = metrics.project(_Vec3(c.toDouble(), 0, 0));
      final b = metrics.project(_Vec3(c.toDouble(), 0, rows.toDouble()));
      canvas.drawLine(a, b, gridLine);
    }
  }

  _Vec3 _normalToCamera(_Vec3 nWorld) => metrics.worldToCamera.rotate(nWorld);

  _GateKind _gateKindFor(_EdgePlacement g) {
    final isE = (entranceGate != null && entranceGate == g);
    final isX = (exitGate != null && exitGate == g);
    if (isE && isX) return _GateKind.mixed;
    if (isE) return _GateKind.entrance;
    return _GateKind.exit;
  }

  Color _gateAccent(_GateKind k) {
    switch (k) {
      case _GateKind.entrance:
        return Colors.green;
      case _GateKind.exit:
        return Colors.red;
      case _GateKind.mixed:
        return Colors.amber;
    }
  }

  String _gateLabel(_GateKind k) {
    switch (k) {
      case _GateKind.entrance:
        return '입구';
      case _GateKind.exit:
        return '출구';
      case _GateKind.mixed:
        return '입/출';
    }
  }

  void _drawBarrier3D(Canvas canvas, _EdgePlacement g, _GateKind kind) {
    final cs = colorScheme;
    final accent = _gateAccent(kind);

    _Vec3 edgeCenter;
    _Vec3 outward;
    _Vec3 tangent;

    switch (g.side) {
      case _EdgeSide.north:
        edgeCenter = _Vec3(g.c + 0.5, 0, g.r.toDouble());
        outward = const _Vec3(0, 0, -1);
        tangent = const _Vec3(1, 0, 0);
        break;
      case _EdgeSide.south:
        edgeCenter = _Vec3(g.c + 0.5, 0, g.r + 1.0);
        outward = const _Vec3(0, 0, 1);
        tangent = const _Vec3(1, 0, 0);
        break;
      case _EdgeSide.west:
        edgeCenter = _Vec3(g.c.toDouble(), 0, g.r + 0.5);
        outward = const _Vec3(-1, 0, 0);
        tangent = const _Vec3(0, 0, 1);
        break;
      case _EdgeSide.east:
        edgeCenter = _Vec3(g.c + 1.0, 0, g.r + 0.5);
        outward = const _Vec3(1, 0, 0);
        tangent = const _Vec3(0, 0, 1);
        break;
    }

    final unit = metrics.pxUnitAt(edgeCenter).clamp(8.0, 70.0);

    final postCenter3 = edgeCenter + outward * 0.22;
    final postCenter2 = metrics.project(postCenter3);

    final postW = max(6.0, unit * 0.16);
    final postH = max(12.0, unit * 0.28);
    final postRect =
        Rect.fromCenter(center: postCenter2, width: postW, height: postH);

    final postFill = Paint()
      ..style = PaintingStyle.fill
      ..color = cs.onSurface.withOpacity(0.78);

    canvas.drawRRect(
      RRect.fromRectAndRadius(postRect, Radius.circular(postW * 0.35)),
      postFill,
    );

    final armBase = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(5.5, unit * 0.14)
      ..color = cs.surface.withOpacity(0.96);

    final armBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(7.0, unit * 0.18)
      ..color = accent.withOpacity(0.95);

    final armCenter3 = edgeCenter + outward * 0.16;
    final p0 = metrics.project(armCenter3 - tangent * 0.40);
    final p1 = metrics.project(armCenter3 + tangent * 0.40);

    canvas.drawLine(p0, p1, armBorder);
    canvas.drawLine(p0, p1, armBase);

    final tp = TextPainter(
      text: TextSpan(
        text: _gateLabel(kind),
        style: TextStyle(
          fontSize: max(10.0, unit * 0.22),
          fontWeight: FontWeight.w900,
          color: accent.withOpacity(0.95),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    tp.paint(canvas, postRect.topLeft + const Offset(2, -16));
  }

  void _drawWall3D(Canvas canvas, _EdgePlacement w) {
    final cs = colorScheme;

    final h = metrics.wallHeight();

    _Vec3 a0;
    _Vec3 a1;
    _Vec3 outward;

    const double out = 0.03;

    switch (w.side) {
      case _EdgeSide.north:
        outward = const _Vec3(0, 0, -1);
        a0 = _Vec3(w.c.toDouble(), 0, w.r.toDouble());
        a1 = _Vec3((w.c + 1).toDouble(), 0, w.r.toDouble());
        break;
      case _EdgeSide.south:
        outward = const _Vec3(0, 0, 1);
        a0 = _Vec3(w.c.toDouble(), 0, (w.r + 1).toDouble());
        a1 = _Vec3((w.c + 1).toDouble(), 0, (w.r + 1).toDouble());
        break;
      case _EdgeSide.west:
        outward = const _Vec3(-1, 0, 0);
        a0 = _Vec3(w.c.toDouble(), 0, w.r.toDouble());
        a1 = _Vec3(w.c.toDouble(), 0, (w.r + 1).toDouble());
        break;
      case _EdgeSide.east:
        outward = const _Vec3(1, 0, 0);
        a0 = _Vec3((w.c + 1).toDouble(), 0, w.r.toDouble());
        a1 = _Vec3((w.c + 1).toDouble(), 0, (w.r + 1).toDouble());
        break;
    }

    final b0 = a0 + outward * out;
    final b1 = a1 + outward * out;

    final t0 = _Vec3(b0.x, h, b0.z);
    final t1 = _Vec3(b1.x, h, b1.z);

    final pB0 = metrics.project(b0);
    final pB1 = metrics.project(b1);
    final pT0 = metrics.project(t0);
    final pT1 = metrics.project(t1);

    final base =
        Color.alphaBlend(cs.onSurface.withOpacity(0.12), cs.surfaceVariant);
    final fill = Paint()
      ..style = PaintingStyle.fill
      ..color = base;

    final isSel = selectedWalls.contains(w);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSel ? 2.0 : 1.1
      ..color = isSel
          ? cs.primary.withOpacity(0.90)
          : cs.outlineVariant.withOpacity(0.95);

    final path = Path()
      ..moveTo(pT0.dx, pT0.dy)
      ..lineTo(pT1.dx, pT1.dy)
      ..lineTo(pB1.dx, pB1.dy)
      ..lineTo(pB0.dx, pB0.dy)
      ..close();

    canvas.drawPath(path, fill);
    canvas.drawPath(path, outline);

    final cap = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = isSel ? 2.2 : 1.4
      ..strokeCap = StrokeCap.round
      ..color =
          isSel ? cs.primary.withOpacity(0.95) : cs.onSurface.withOpacity(0.35);

    canvas.drawLine(pT0, pT1, cap);
  }

  _WallLabelAnchor3D _wallLabelAnchor(_EdgePlacement w) {
    final h = metrics.wallHeight();

    _Vec3 a0;
    _Vec3 a1;
    _Vec3 outward;

    const double out = 0.03;

    switch (w.side) {
      case _EdgeSide.north:
        outward = const _Vec3(0, 0, -1);
        a0 = _Vec3(w.c.toDouble(), 0, w.r.toDouble());
        a1 = _Vec3((w.c + 1).toDouble(), 0, w.r.toDouble());
        break;
      case _EdgeSide.south:
        outward = const _Vec3(0, 0, 1);
        a0 = _Vec3(w.c.toDouble(), 0, (w.r + 1).toDouble());
        a1 = _Vec3((w.c + 1).toDouble(), 0, (w.r + 1).toDouble());
        break;
      case _EdgeSide.west:
        outward = const _Vec3(-1, 0, 0);
        a0 = _Vec3(w.c.toDouble(), 0, w.r.toDouble());
        a1 = _Vec3(w.c.toDouble(), 0, (w.r + 1).toDouble());
        break;
      case _EdgeSide.east:
        outward = const _Vec3(1, 0, 0);
        a0 = _Vec3((w.c + 1).toDouble(), 0, w.r.toDouble());
        a1 = _Vec3((w.c + 1).toDouble(), 0, (w.r + 1).toDouble());
        break;
    }

    final b0 = a0 + outward * out;
    final b1 = a1 + outward * out;

    final t0 = _Vec3(b0.x, h, b0.z);
    final t1 = _Vec3(b1.x, h, b1.z);

    final mid3 = _Vec3(
          (t0.x + t1.x) / 2,
          h + 0.07,
          (t0.z + t1.z) / 2,
        ) +
        outward * 0.04;

    final pos = metrics.project(mid3);
    final unit = metrics.pxUnitAt(mid3).clamp(8.0, 70.0);
    final zKey = metrics.cameraZ(mid3);

    return _WallLabelAnchor3D(pos: pos, unit: unit, zKey: zKey);
  }

  void _drawWallGroupLabels(Canvas canvas) {
    final cs = colorScheme;

    final grouped = <_WallGroupId, List<_EdgePlacement>>{};
    for (final e in walls.entries) {
      final gid = e.value;
      if (gid == null) continue;
      final name = wallGroups[gid]?.trim();
      if (name == null || name.isEmpty) continue;
      grouped.putIfAbsent(gid, () => <_EdgePlacement>[]).add(e.key);
    }
    if (grouped.isEmpty) return;

    final labels = <_WallGroupLabelItem>[];

    for (final entry in grouped.entries) {
      final gid = entry.key;
      final name = wallGroups[gid]?.trim();
      if (name == null || name.isEmpty) continue;

      _EdgePlacement rep = entry.value.first;
      int best = _edgeSortKey(rep);
      for (final w in entry.value) {
        final k = _edgeSortKey(w);
        if (k < best) {
          best = k;
          rep = w;
        }
      }

      final sel = entry.value.any(selectedWalls.contains);
      final anchor = _wallLabelAnchor(rep);

      labels.add(_WallGroupLabelItem(
        gid: gid,
        name: name,
        rep: rep,
        sel: sel,
        anchor: anchor,
      ));
    }

    labels.sort((a, b) => a.anchor.zKey.compareTo(b.anchor.zKey));

    for (final it in labels) {
      final name = it.name;
      final sel = it.sel;
      final anchor = it.anchor;

      final tp = TextPainter(
        text: TextSpan(
          text: name,
          style: TextStyle(
            fontSize: max(10.0, anchor.unit * 0.20),
            fontWeight: FontWeight.w900,
            color: (sel ? cs.primary : cs.onSurface).withOpacity(0.92),
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
        ellipsis: '…',
      )..layout(maxWidth: 220);

      const padX = 8.0;
      const padY = 5.0;

      final boxW = tp.width + padX * 2;
      final boxH = tp.height + padY * 2;

      final boxRect = Rect.fromLTWH(
        anchor.pos.dx - boxW / 2,
        anchor.pos.dy - boxH - 6,
        boxW,
        boxH,
      );

      final bg = Paint()
        ..style = PaintingStyle.fill
        ..color = Color.alphaBlend(
          (sel ? cs.primary.withOpacity(0.10) : cs.surface.withOpacity(0.72)),
          cs.surface,
        );

      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = sel ? 1.4 : 1.0
        ..color = (sel ? cs.primary : cs.outlineVariant).withOpacity(0.85);

      canvas.drawRRect(
        RRect.fromRectAndRadius(boxRect, const Radius.circular(10)),
        bg,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(boxRect, const Radius.circular(10)),
        border,
      );

      tp.paint(canvas, boxRect.topLeft + const Offset(padX, padY));
    }
  }

  void _drawPillar3D(Canvas canvas, int r, int c,
      {required double baseY, required double height}) {
    final cs = colorScheme;

    const int seg = 10;
    const double radius = 0.18;

    final cx = c + 0.5;
    final cz = r + 0.5;

    List<_Vec3> ring(double y) {
      return List.generate(seg, (i) {
        final a = 2 * pi * i / seg;
        return _Vec3(cx + cos(a) * radius, y, cz + sin(a) * radius);
      });
    }

    final bot3 = ring(baseY);
    final top3 = ring(baseY + height);

    final bot2 = bot3.map(metrics.project).toList();
    final top2 = top3.map(metrics.project).toList();

    final pillarBase =
        Color.alphaBlend(cs.onSurface.withOpacity(0.14), cs.surfaceVariant);
    final pillarTop = _shade(pillarBase, 0.10);

    final light = const _Vec3(-0.35, 0.80, -0.45).normalized();

    final faces = <_FacePaint>[];

    for (int i = 0; i < seg; i++) {
      final j = (i + 1) % seg;

      final midA = 2 * pi * (i + 0.5) / seg;
      final normalWorld = _Vec3(cos(midA), 0, sin(midA));

      final nCam = _normalToCamera(normalWorld);
      if (nCam.z >= 0) continue;

      final bright = nCam.normalized().dot(light).clamp(-1.0, 1.0);
      final delta = (-0.16 + 0.14 * ((bright + 1) / 2)).clamp(-0.20, 0.06);

      final pts3 = [top3[i], top3[j], bot3[j], bot3[i]];
      final pts2 = [top2[i], top2[j], bot2[j], bot2[i]];

      final zKey =
          pts3.map(metrics.cameraZ).reduce((a, b) => a + b) / pts3.length;

      faces.add(_FacePaint(
        pts2: pts2,
        fill: _shade(pillarBase, delta),
        zKey: zKey,
      ));
    }

    faces.sort((a, b) => b.zKey.compareTo(a.zKey));

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9
      ..color = cs.outlineVariant.withOpacity(0.95);

    for (final fp in faces) {
      final p = fp.pts2;
      final path = Path()
        ..moveTo(p[0].dx, p[0].dy)
        ..lineTo(p[1].dx, p[1].dy)
        ..lineTo(p[2].dx, p[2].dy)
        ..lineTo(p[3].dx, p[3].dy)
        ..close();
      canvas.drawPath(path, Paint()..color = fp.fill);
      canvas.drawPath(path, outline);
    }

    final topPath = Path()..moveTo(top2[0].dx, top2[0].dy);
    for (int i = 1; i < seg; i++) {
      topPath.lineTo(top2[i].dx, top2[i].dy);
    }
    topPath.close();

    canvas.drawPath(topPath, Paint()..color = pillarTop);
    canvas.drawPath(topPath, outline);
  }

  void _drawDashedLine(
    Canvas canvas,
    Offset a,
    Offset b,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = sqrt(dx * dx + dy * dy);
    if (len <= 1e-6) return;

    final ux = dx / len;
    final uy = dy / len;

    double t = 0;
    while (t < len) {
      final t2 = min(len, t + dash);
      canvas.drawLine(
        Offset(a.dx + ux * t, a.dy + uy * t),
        Offset(a.dx + ux * t2, a.dy + uy * t2),
        paint,
      );
      t = t2 + gap;
    }
  }

  void _drawRoadMark3D(Canvas canvas, List<Offset> top2, double unit) {
    final cs = colorScheme;
    final p0 = top2[0], p1 = top2[1], p2 = top2[2], p3 = top2[3];

    Offset mid(Offset a, Offset b) =>
        Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);

    final m01 = mid(p0, p1);
    final m12 = mid(p1, p2);
    final m23 = mid(p2, p3);
    final m30 = mid(p3, p0);

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = max(1.2, unit * 0.025)
      ..color = cs.surface.withOpacity(0.70);

    final dash = max(4.0, unit * 0.08);
    final gap = max(3.0, unit * 0.06);

    _drawDashedLine(canvas, m01, m23, paint, dash: dash, gap: gap);
    _drawDashedLine(canvas, m12, m30, paint, dash: dash, gap: gap);
  }

  void _drawCell(Canvas canvas, int r, int c, int idx) {
    final cs = colorScheme;
    final st = cells[idx];

    final tileH = metrics.tileHeight(st);

    final base3 = metrics.tileCorners3D(r, c, 0);
    final top3 = metrics.tileCorners3D(r, c, tileH);

    final base2 = base3.map(metrics.project).toList();
    final top2 = top3.map(metrics.project).toList();

    final baseColor = colorResolver(cs, st);
    final topColor = _shade(baseColor, 0.10);

    final light = const _Vec3(-0.35, 0.80, -0.45).normalized();

    final faces = <_Face3D>[
      _Face3D(
        normalWorld: const _Vec3(0, 0, -1),
        pts3: [top3[0], top3[1], base3[1], base3[0]],
        pts2: [top2[0], top2[1], base2[1], base2[0]],
      ),
      _Face3D(
        normalWorld: const _Vec3(1, 0, 0),
        pts3: [top3[1], top3[2], base3[2], base3[1]],
        pts2: [top2[1], top2[2], base2[2], base2[1]],
      ),
      _Face3D(
        normalWorld: const _Vec3(0, 0, 1),
        pts3: [top3[2], top3[3], base3[3], base3[2]],
        pts2: [top2[2], top2[3], base2[3], base2[2]],
      ),
      _Face3D(
        normalWorld: const _Vec3(-1, 0, 0),
        pts3: [top3[3], top3[0], base3[0], base3[3]],
        pts2: [top2[3], top2[0], base2[0], base2[3]],
      ),
    ];

    final visible = <_FacePaint>[];
    for (final fce in faces) {
      final nCam = _normalToCamera(fce.normalWorld);
      if (nCam.z >= 0) continue;

      final bright = nCam.normalized().dot(light).clamp(-1.0, 1.0);
      final delta = (-0.18 + 0.16 * ((bright + 1) / 2)).clamp(-0.22, 0.06);

      final zKey = fce.pts3.map(metrics.cameraZ).reduce((a, b) => a + b) /
          fce.pts3.length;

      visible.add(_FacePaint(
        pts2: fce.pts2,
        fill: _shade(baseColor, delta),
        zKey: zKey,
      ));
    }
    visible.sort((a, b) => b.zKey.compareTo(a.zKey));

    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.95
      ..color = cs.outlineVariant.withOpacity(0.92);

    for (final fp in visible) {
      final p = fp.pts2;
      final path = Path()
        ..moveTo(p[0].dx, p[0].dy)
        ..lineTo(p[1].dx, p[1].dy)
        ..lineTo(p[2].dx, p[2].dy)
        ..lineTo(p[3].dx, p[3].dy)
        ..close();
      canvas.drawPath(path, Paint()..color = fp.fill);
      canvas.drawPath(path, outline);
    }

    final topFace = Path()
      ..moveTo(top2[0].dx, top2[0].dy)
      ..lineTo(top2[1].dx, top2[1].dy)
      ..lineTo(top2[2].dx, top2[2].dy)
      ..lineTo(top2[3].dx, top2[3].dy)
      ..close();

    canvas.drawPath(topFace, Paint()..color = topColor);
    canvas.drawPath(topFace, outline);

    final center3 = metrics.cellCenter3D(r, c, y: tileH);
    final unit = metrics.pxUnitAt(center3);
    if (st == ParkingCellState.road) {
      _drawRoadMark3D(canvas, top2, unit);
    }

    if (st == ParkingCellState.pillar) {
      _drawPillar3D(
        canvas,
        r,
        c,
        baseY: tileH,
        height: metrics.pillarHeight(),
      );
    }

    if (st == ParkingCellState.occupied || st == ParkingCellState.blocked) {
      final c0 = _spotRepCol(c);
      final repIdx = r * cols + c0;
      final validSpot = _isValidSpotPair(r, c0);

      if (validSpot) {
        if (idx == repIdx) {
          final spotSt = cells[repIdx];
          final h = metrics.tileHeight(spotSt);
          final spotCenter3 = _Vec3(c0 + 1.0, h, r + 0.5);
          final center = metrics.project(spotCenter3);
          final unit2 = metrics.pxUnitAt(spotCenter3);

          final mark = (spotSt == ParkingCellState.occupied) ? 'P' : '×';
          final tp = TextPainter(
            text: TextSpan(
              text: mark,
              style: TextStyle(
                fontSize: unit2 * 0.24,
                fontWeight: FontWeight.w900,
                color: (spotSt == ParkingCellState.occupied)
                    ? cs.onPrimaryContainer.withOpacity(0.92)
                    : cs.onErrorContainer.withOpacity(0.92),
              ),
            ),
            textDirection: TextDirection.ltr,
          )..layout();
          tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
        }
      } else {
        final mark = st == ParkingCellState.occupied ? 'P' : '×';
        final center = metrics.project(center3);
        final tp = TextPainter(
          text: TextSpan(
            text: mark,
            style: TextStyle(
              fontSize: unit * 0.22,
              fontWeight: FontWeight.w900,
              color: st == ParkingCellState.occupied
                  ? cs.onPrimaryContainer.withOpacity(0.92)
                  : cs.onErrorContainer.withOpacity(0.92),
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  void _drawSelectedEmphasis(Canvas canvas) {
    final idxs = _selectedHighlightIndices();
    if (idxs.isEmpty) return;

    final cs = colorScheme;

    for (final idx in idxs) {
      if (idx < 0 || idx >= cells.length) continue;
      final r = idx ~/ cols;
      final c = idx % cols;
      if (r < 0 || r >= rows || c < 0 || c >= cols) continue;

      final st = cells[idx];
      final h = metrics.tileHeight(st);

      final topFace = metrics.topFacePath(r, c, h);
      final center3 = metrics.cellCenter3D(r, c, y: h);
      final unit = metrics.pxUnitAt(center3);

      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(4.0, unit * 0.09)
        ..color = cs.primary.withOpacity(0.18)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);

      final border = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = max(2.0, unit * 0.05)
        ..color = cs.primary.withOpacity(0.95);

      canvas.drawPath(topFace, glow);
      canvas.drawPath(topFace, border);
    }
  }

  double _zKeyForWall(_EdgePlacement w) {
    _Vec3 edgeCenter;
    _Vec3 outward;

    switch (w.side) {
      case _EdgeSide.north:
        edgeCenter =
            _Vec3(w.c + 0.5, metrics.wallHeight() * 0.5, w.r.toDouble());
        outward = const _Vec3(0, 0, -1);
        break;
      case _EdgeSide.south:
        edgeCenter =
            _Vec3(w.c + 0.5, metrics.wallHeight() * 0.5, (w.r + 1).toDouble());
        outward = const _Vec3(0, 0, 1);
        break;
      case _EdgeSide.west:
        edgeCenter =
            _Vec3(w.c.toDouble(), metrics.wallHeight() * 0.5, w.r + 0.5);
        outward = const _Vec3(-1, 0, 0);
        break;
      case _EdgeSide.east:
        edgeCenter =
            _Vec3((w.c + 1).toDouble(), metrics.wallHeight() * 0.5, w.r + 0.5);
        outward = const _Vec3(1, 0, 0);
        break;
    }

    final p = edgeCenter + outward * 0.05;
    return metrics.cameraZ(p);
  }

  double _zKeyForGate(_EdgePlacement g) {
    _Vec3 edgeCenter;
    _Vec3 outward;

    switch (g.side) {
      case _EdgeSide.north:
        edgeCenter = _Vec3(g.c + 0.5, 0.18, g.r.toDouble());
        outward = const _Vec3(0, 0, -1);
        break;
      case _EdgeSide.south:
        edgeCenter = _Vec3(g.c + 0.5, 0.18, (g.r + 1).toDouble());
        outward = const _Vec3(0, 0, 1);
        break;
      case _EdgeSide.west:
        edgeCenter = _Vec3(g.c.toDouble(), 0.18, g.r + 0.5);
        outward = const _Vec3(-1, 0, 0);
        break;
      case _EdgeSide.east:
        edgeCenter = _Vec3((g.c + 1).toDouble(), 0.18, g.r + 0.5);
        outward = const _Vec3(1, 0, 0);
        break;
    }

    return metrics.cameraZ(edgeCenter + outward * 0.08);
  }

  @override
  void paint(Canvas canvas, Size size) {
    _drawFloor(canvas);

    final items = <_DrawItem>[];

    for (final w in walls.keys) {
      items.add(_DrawItem.wall(e: w, zKey: _zKeyForWall(w)));
    }

    final gateSet = <_EdgePlacement>{};
    if (entranceGate != null) gateSet.add(entranceGate!);
    if (exitGate != null) gateSet.add(exitGate!);
    for (final g in gateSet) {
      items.add(
          _DrawItem.gate(e: g, kind: _gateKindFor(g), zKey: _zKeyForGate(g)));
    }

    for (int idx = 0; idx < rows * cols; idx++) {
      final r = idx ~/ cols;
      final c = idx % cols;
      if (r < 0 || r >= rows || c < 0 || c >= cols) continue;
      if (idx < 0 || idx >= cells.length) continue;
      final z = metrics.cameraZ(_Vec3(c + 0.5, 0, r + 0.5));
      items.add(_DrawItem.cell(idx: idx, zKey: z));
    }

    items.sort((a, b) => b.zKey.compareTo(a.zKey));

    for (final it in items) {
      switch (it.type) {
        case _DrawItemType.wall:
          _drawWall3D(canvas, it.edge!);
          break;
        case _DrawItemType.gate:
          _drawBarrier3D(canvas, it.edge!, it.gateKind!);
          break;
        case _DrawItemType.cell:
          final idx = it.cellIndex;
          final r = idx ~/ cols;
          final c = idx % cols;
          _drawCell(canvas, r, c, idx);
          break;
      }
    }

    _drawSelectedEmphasis(canvas);

    _drawWallGroupLabels(canvas);
  }

  @override
  bool shouldRepaint(covariant _ParkingGaragePainter oldDelegate) {
    return oldDelegate.rows != rows ||
        oldDelegate.cols != cols ||
        oldDelegate.metrics.key != metrics.key ||
        oldDelegate.cells != cells ||
        oldDelegate.selectedCellIndex != selectedCellIndex ||
        oldDelegate.colorScheme != colorScheme ||
        oldDelegate.entranceGate != entranceGate ||
        oldDelegate.exitGate != exitGate ||
        oldDelegate.walls != walls ||
        oldDelegate.wallGroups != wallGroups ||
        oldDelegate.selectedWalls != selectedWalls;
  }
}

class _Face3D {
  final _Vec3 normalWorld;
  final List<_Vec3> pts3;
  final List<Offset> pts2;

  _Face3D({
    required this.normalWorld,
    required this.pts3,
    required this.pts2,
  });
}

class _FacePaint {
  final List<Offset> pts2;
  final Color fill;
  final double zKey;

  _FacePaint({required this.pts2, required this.fill, required this.zKey});
}

class _DimControl extends StatelessWidget {
  final String label;
  final int value;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _DimControl({
    required this.label,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: '$label 감소',
            onPressed: onMinus,
            icon: const Icon(Icons.remove_circle_outline_rounded),
          ),
          IconButton(
            tooltip: '$label 증가',
            onPressed: onPlus,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String value;

  const _StatPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.9)),
      ),
      child: Text(
        '$label $value',
        style: (tt.labelSmall ?? const TextStyle(fontSize: 11.5)).copyWith(
          fontWeight: FontWeight.w800,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Row(
      children: [
        SizedBox(
          width: 72,
          child: Text(
            label,
            style: (tt.bodySmall ?? const TextStyle(fontSize: 12.5)).copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

enum _BannerTone { neutral, warning }

class _InfoBanner extends StatelessWidget {
  final String text;
  final _BannerTone tone;

  const _InfoBanner({
    required this.text,
    this.tone = _BannerTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    late final Color bg;
    late final Color border;
    late final Color fg;
    late final IconData icon;

    switch (tone) {
      case _BannerTone.warning:
        bg = Color.alphaBlend(Colors.amber.withOpacity(0.16), cs.surface);
        border = Colors.amber.withOpacity(0.45);
        fg = cs.onSurface;
        icon = Icons.warning_amber_rounded;
        break;
      case _BannerTone.neutral:
        bg = cs.surfaceVariant.withOpacity(0.35);
        border = cs.outlineVariant.withOpacity(0.9);
        fg = cs.onSurface;
        icon = Icons.info_outline_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: fg))),
        ],
      ),
    );
  }
}
