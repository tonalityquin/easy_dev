import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../dev/application/area_state.dart';
import '../applications/location_state.dart';
import '../domain/models/grid_rect.dart';
import '../domain/models/location_model.dart';
import '../domain/models/parking_grid_model.dart';
import 'sheets/location_setting.dart';
import 'sheets/widgets/location_draft.dart';
import 'sheets/widgets/parking_grid_preview.dart';
import '../../../shared/secondary/widgets/ops_console_widgets.dart';

class LocationManagement extends StatefulWidget {
  const LocationManagement({super.key});

  @override
  State<LocationManagement> createState() => _LocationManagementState();
}

class _LocationManagementState extends State<LocationManagement> {
  String _filter = 'all';

  String _query = '';

  bool _showOnlySelectedChild = false;

  bool _showSelectedChildSlotNumbers = true;

  String? _focusedParentKey;

  static String _normalizeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

  static String _childCompositeKey(String parent, String child) =>
      '${_nameKey(parent)}|${_nameKey(child)}';

  static List<String> _childAreaIds(LocationModel loc) {
    final out = <String>[];
    final seen = <String>{};

    for (final id in loc.childSlotAreaIds) {
      final v = id.trim();
      if (v.isEmpty) continue;
      if (seen.add(v)) out.add(v);
    }

    if (out.isNotEmpty) return out;

    for (final slot in loc.childSlots) {
      final v = slot.areaId.trim();
      if (v.isEmpty) continue;
      if (seen.add(v)) out.add(v);
    }

    return out;
  }


  static Map<String, int> _childSlotNumbersByAreaId(LocationModel loc) {
    final out = <String, int>{};
    for (final slot in loc.childSlots) {
      final id = slot.areaId.trim();
      if (id.isEmpty) continue;
      final no = slot.no;
      if (no <= 0) continue;
      out[id] = no;
    }
    return out;
  }


  static const String _miscGroupKey = '__misc__';


  void _openFocusedParent(String key) {
    setState(() => _focusedParentKey = key);
  }

  void _closeFocusedParent() {
    if (_focusedParentKey == null) return;
    setState(() => _focusedParentKey = null);
  }

  LocationModel? _selectedLocation(LocationState state) {
    final id = state.selectedLocationId;
    if (id == null) return null;
    for (final loc in state.locations) {
      if (loc.id == id) return loc;
    }
    return null;
  }



  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          barrierColor: Theme.of(context).colorScheme.scrim.withOpacity(.42),
          builder: (ctx) {
            final cs = Theme.of(ctx).colorScheme;
            final tt = Theme.of(ctx).textTheme;
            return Dialog(
              elevation: 0,
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: OpsPanel(
                  margin: EdgeInsets.zero,
                  padding: EdgeInsets.zero,
                  accentColor: cs.error,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                        decoration: BoxDecoration(
                          color: cs.inverseSurface,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: cs.error,
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(Icons.delete_forever_rounded, color: cs.onError, size: 21),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '구역 삭제 확인',
                                    style: (tt.titleMedium ?? const TextStyle(fontSize: 17)).copyWith(
                                      color: cs.onInverseSurface,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: -.2,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '선택한 현장 구역을 삭제하기 전 마지막으로 확인합니다.',
                                    style: (tt.bodySmall ?? const TextStyle(fontSize: 12)).copyWith(
                                      color: cs.onInverseSurface.withOpacity(.72),
                                      fontWeight: FontWeight.w800,
                                      height: 1.25,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton.filledTonal(
                              tooltip: '닫기',
                              onPressed: () => Navigator.of(ctx).pop(false),
                              icon: const Icon(Icons.close_rounded),
                            ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
                        child: OpsInlineMessage(
                          message: '삭제하면 선택한 주차 구역이 운영 목록에서 제거됩니다. 연결된 운영 데이터와 화면 배치를 확인한 뒤 진행하세요.',
                          icon: Icons.warning_amber_rounded,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: FilledButton.tonalIcon(
                                onPressed: () => Navigator.of(ctx).pop(false),
                                icon: const Icon(Icons.close_rounded, size: 18),
                                label: const Text('취소'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(46),
                                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => Navigator.of(ctx).pop(true),
                                icon: const Icon(Icons.delete_forever_rounded, size: 18),
                                label: const Text('삭제'),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(46),
                                  backgroundColor: cs.error,
                                  foregroundColor: cs.onError,
                                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ) ??
        false;
  }

  bool _isCompositeParent(LocationModel loc) =>
      (loc.type ?? '') == 'composite_parent';

  bool _isCompositeChild(LocationModel loc) {
    final t = loc.type ?? 'single';
    return t == 'composite_child' || t == 'composite';
  }

  int _countEmptyCells(ParkingGridModel grid) {
    var count = 0;
    for (var i = 0; i < grid.cells.length; i++) {
      if (grid.cellTypeAt(i) == ParkingGridCellType.empty) count++;
    }
    return count;
  }

  int _countParkingAreas(ParkingGridModel grid) => grid.parkingAreas.length;

  int _countParkingAreaCells(ParkingGridModel grid) {
    var sum = 0;
    for (final a in grid.parkingAreas) {
      final r0 = a.r0 < a.r1 ? a.r0 : a.r1;
      final r1 = a.r0 < a.r1 ? a.r1 : a.r0;
      final c0 = a.c0 < a.c1 ? a.c0 : a.c1;
      final c1 = a.c0 < a.c1 ? a.c1 : a.c0;

      final h = (r1 - r0 + 1);
      final w = (c1 - c0 + 1);
      if (h > 0 && w > 0) sum += h * w;
    }
    return sum;
  }

  String _slotLabelForSummary(ChildSlot s) {
    final label = s.label.trim();
    if (label.isNotEmpty) return label;

    final category = s.categoryLabel.trim();
    final footprint = s.footprint.trim();
    if (category.isNotEmpty && footprint.isNotEmpty) {
      return '$category $footprint';
    }
    if (category.isNotEmpty) return category;
    if (footprint.isNotEmpty) return footprint;

    final kind = s.kind.trim();
    return kind.isEmpty ? '미지정' : kind;
  }

  String _slotSummaryText(Iterable<ChildSlot> slots) {
    final counts = <String, int>{};
    for (final s in slots) {
      final label = _slotLabelForSummary(s);
      counts[label] = (counts[label] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key} ${e.value}').join(' · ');
  }

  String _parkingAreaKindSummary(ParkingGridModel grid) {
    final counts = <String, int>{};
    for (final a in grid.parkingAreas) {
      final label = a.kind.label;
      counts[label] = (counts[label] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    final entries = counts.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return entries.map((e) => '${e.key} ${e.value}').join(' · ');
  }

  Future<void> _handleRebuildChildSlots(BuildContext context) async {
    final state = context.read<LocationState>();
    String? errorMessage;

    final ok = await state.refreshChildSlotsForCurrentArea(
      onError: (msg) => errorMessage = msg,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? '기존 자식 슬롯을 최신 주차면적으로 재계산했습니다.' : (errorMessage ?? '자식 슬롯 재계산에 실패했습니다.'),
        ),
      ),
    );
  }

  Future<void> _handleAdd(BuildContext context) async {
    final locationState = context.read<LocationState>();
    final currentArea = context.read<AreaState>().currentArea.trim();

    final allInArea = locationState.locations
        .where((loc) => loc.area.trim() == currentArea)
        .toList();

    final existingNameKeysInArea =
        allInArea.map((loc) => _nameKey(loc.locationName)).toSet();

    final existingChildCompositeKeysInArea = allInArea
        .where((loc) =>
            _isCompositeChild(loc) && (loc.parent ?? '').trim().isNotEmpty)
        .map((loc) => _childCompositeKey(loc.parent!, loc.locationName))
        .toSet();

    final parentNamesInArea = allInArea
        .where(_isCompositeParent)
        .map((p) => p.locationName)
        .toList()
      ..sort();

    final Map<String, ParkingGridModel> parentParkingGridsByParentKey = {};
    for (final p in allInArea.where(_isCompositeParent)) {
      final grid = p.parkingGrid;
      if (grid == null) continue;
      parentParkingGridsByParentKey[_nameKey(p.locationName)] = grid;
    }

    final Map<String, List<GridRect>> existingChildRectsByParentKey = {};
    final Map<String, Set<String>> existingChildAreaIdsByParentKey = {};
    for (final c in allInArea.where(_isCompositeChild)) {
      final pName = (c.parent ?? '').trim();
      if (pName.isEmpty) continue;

      final pk = _nameKey(pName);
      final areaIds = _childAreaIds(c);
      if (areaIds.isNotEmpty) {
        existingChildAreaIdsByParentKey
            .putIfAbsent(pk, () => <String>{})
            .addAll(areaIds);
      }

      final cr = c.childRect;
      if (cr == null) continue;

      existingChildRectsByParentKey
          .putIfAbsent(pk, () => <GridRect>[])
          .add(cr.normalized());
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 1,
          child: LocationSettingBottomSheet(
            existingNameKeysInArea: existingNameKeysInArea,
            existingChildCompositeKeysInArea: existingChildCompositeKeysInArea,
            parentNamesInArea: parentNamesInArea,
            parentParkingGridsByParentKey: parentParkingGridsByParentKey,
            existingChildRectsByParentKey: existingChildRectsByParentKey,
            existingChildAreaIdsByParentKey: existingChildAreaIdsByParentKey,
            onSave: (draft) async {
              final area = context.read<AreaState>().currentArea.trim();

              if (draft is CompositeParentDraft) {
                await locationState.addCompositeParent(
                  draft.parent,
                  area,
                  parkingGrid: draft.parkingGrid,
                  onError: (_) {},
                );
                if (!mounted) return;
                return;
              }

              if (draft is CompositeChildDraft) {
                await locationState.addCompositeChild(
                  parent: draft.parent,
                  child: draft.child,
                  capacity: draft.capacity,
                  area: area,
                  rect: draft.rect,
                  childSlotAreaIds: draft.childSlotAreaIds,
                  childSlotNumbersByAreaId: draft.childSlotNumbersByAreaId,
                  isTower: draft.isTower,
                  onError: (_) {},
                );
                if (!mounted) return;
                return;
              }

              if (draft is PlainTextLocationDraft) {
                await locationState.addPlainTextLocation(
                  name: draft.name,
                  capacity: draft.capacity,
                  area: area,
                  onError: (_) {},
                );
                if (!mounted) return;
                return;
              }

              if (!mounted) return;
            },
          ),
        );
      },
    );
  }

  Future<void> _handleEditParent(BuildContext context) async {
    final locationState = context.read<LocationState>();
    final currentArea = context.read<AreaState>().currentArea.trim();

    final selectedId = locationState.selectedLocationId;
    if (selectedId == null) {
      return;
    }

    LocationModel? selected;
    for (final l in locationState.locations) {
      if (l.id == selectedId) {
        selected = l;
        break;
      }
    }

    if (selected == null) {
      return;
    }

    if (!_isCompositeParent(selected)) {
      return;
    }

    final parentGrid = selected.parkingGrid;
    if (parentGrid == null) {
      return;
    }

    final allInArea = locationState.locations
        .where((l) => l.area.trim() == currentArea)
        .toList();

    final existingNameKeysInArea =
        allInArea.map((l) => _nameKey(l.locationName)).toSet();

    final existingChildCompositeKeysInArea = allInArea
        .where((loc) =>
            _isCompositeChild(loc) && (loc.parent ?? '').trim().isNotEmpty)
        .map((loc) => _childCompositeKey(loc.parent!, loc.locationName))
        .toSet();

    final parentNamesInArea = allInArea
        .where(_isCompositeParent)
        .map((p) => p.locationName)
        .toList()
      ..sort();

    final Map<String, ParkingGridModel> parentParkingGridsByParentKey = {};
    for (final p in allInArea.where(_isCompositeParent)) {
      final grid = p.parkingGrid;
      if (grid == null) continue;
      parentParkingGridsByParentKey[_nameKey(p.locationName)] = grid;
    }

    final Map<String, List<GridRect>> existingChildRectsByParentKey = {};
    final Map<String, Set<String>> existingChildAreaIdsByParentKey = {};
    for (final c in allInArea.where(_isCompositeChild)) {
      final pName = (c.parent ?? '').trim();
      if (pName.isEmpty) continue;

      final pk = _nameKey(pName);
      final areaIds = _childAreaIds(c);
      if (areaIds.isNotEmpty) {
        existingChildAreaIdsByParentKey
            .putIfAbsent(pk, () => <String>{})
            .addAll(areaIds);
      }

      final cr = c.childRect;
      if (cr == null) continue;

      existingChildRectsByParentKey
          .putIfAbsent(pk, () => <GridRect>[])
          .add(cr.normalized());
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 1,
          child: LocationSettingBottomSheet(
            existingNameKeysInArea: existingNameKeysInArea,
            existingChildCompositeKeysInArea: existingChildCompositeKeysInArea,
            parentNamesInArea: parentNamesInArea,
            parentParkingGridsByParentKey: parentParkingGridsByParentKey,
            existingChildRectsByParentKey: existingChildRectsByParentKey,
            existingChildAreaIdsByParentKey: existingChildAreaIdsByParentKey,
            editingParentName: selected!.locationName,
            editingParentParkingGrid: parentGrid,
            onSave: (draft) async {
              final area = context.read<AreaState>().currentArea.trim();

              if (draft is CompositeParentUpdateDraft) {
                await locationState.saveCompositeParentGrid(
                  parent: draft.parent,
                  area: area,
                  parkingGrid: draft.parkingGrid,
                  onError: (_) {},
                );
                if (!mounted) return;
                return;
              }

              if (draft is CompositeChildDraft) {
                await locationState.addCompositeChild(
                  parent: draft.parent,
                  child: draft.child,
                  capacity: draft.capacity,
                  area: area,
                  rect: draft.rect,
                  childSlotAreaIds: draft.childSlotAreaIds,
                  childSlotNumbersByAreaId: draft.childSlotNumbersByAreaId,
                  isTower: draft.isTower,
                  onError: (_) {},
                );
                if (!mounted) return;
                return;
              }

              if (draft is CompositeParentDraft) {
                await locationState.addCompositeParent(
                  draft.parent,
                  area,
                  parkingGrid: draft.parkingGrid,
                  onError: (_) {},
                );
                if (!mounted) return;
                return;
              }

              if (!mounted) return;
            },
          ),
        );
      },
    );
  }

  Future<void> _handleEditChild(BuildContext context) async {
    final locationState = context.read<LocationState>();
    final currentArea = context.read<AreaState>().currentArea.trim();

    final selectedId = locationState.selectedLocationId;
    if (selectedId == null) {
      return;
    }

    LocationModel? selected;
    for (final l in locationState.locations) {
      if (l.id == selectedId) {
        selected = l;
        break;
      }
    }

    if (selected == null) {
      return;
    }

    if (!_isCompositeChild(selected)) {
      return;
    }

    final parentName = (selected.parent ?? '').trim();
    if (parentName.isEmpty) {
      return;
    }

    final rect = selected.childRect;
    if (rect == null) {
      return;
    }

    final allInArea = locationState.locations
        .where((l) => l.area.trim() == currentArea)
        .toList();

    final existingNameKeysInArea =
        allInArea.map((l) => _nameKey(l.locationName)).toSet();

    final existingChildCompositeKeysInArea = allInArea
        .where((loc) =>
            _isCompositeChild(loc) && (loc.parent ?? '').trim().isNotEmpty)
        .map((loc) => _childCompositeKey(loc.parent!, loc.locationName))
        .toSet();

    final parentNamesInArea = allInArea
        .where(_isCompositeParent)
        .map((p) => p.locationName)
        .toList()
      ..sort();

    final Map<String, ParkingGridModel> parentParkingGridsByParentKey = {};
    for (final p in allInArea.where(_isCompositeParent)) {
      final grid = p.parkingGrid;
      if (grid == null) continue;
      parentParkingGridsByParentKey[_nameKey(p.locationName)] = grid;
    }

    final Map<String, List<GridRect>> existingChildRectsByParentKey = {};
    final Map<String, Set<String>> existingChildAreaIdsByParentKey = {};
    for (final c in allInArea.where(_isCompositeChild)) {
      final pName = (c.parent ?? '').trim();
      if (pName.isEmpty) continue;

      final pk = _nameKey(pName);
      final areaIds = _childAreaIds(c);
      if (areaIds.isNotEmpty) {
        existingChildAreaIdsByParentKey
            .putIfAbsent(pk, () => <String>{})
            .addAll(areaIds);
      }

      final cr = c.childRect;
      if (cr == null) continue;

      existingChildRectsByParentKey
          .putIfAbsent(pk, () => <GridRect>[])
          .add(cr.normalized());
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 1,
          child: LocationSettingBottomSheet(
            existingNameKeysInArea: existingNameKeysInArea,
            existingChildCompositeKeysInArea: existingChildCompositeKeysInArea,
            parentNamesInArea: parentNamesInArea,
            parentParkingGridsByParentKey: parentParkingGridsByParentKey,
            existingChildRectsByParentKey: existingChildRectsByParentKey,
            existingChildAreaIdsByParentKey: existingChildAreaIdsByParentKey,
            editingChildId: selected!.id,
            editingChildParentName: parentName,
            editingChildName: selected.locationName,
            editingChildCapacity: selected.capacity,
            editingChildRect: rect,
            editingChildIsTower: selected.isTowerChild,
            editingChildSlotAreaIds: _childAreaIds(selected),
            editingChildSlotNumbersByAreaId: _childSlotNumbersByAreaId(selected),
            onSave: (draft) async {
              final area = context.read<AreaState>().currentArea.trim();

              if (draft is CompositeChildUpdateDraft) {
                await locationState.saveCompositeChild(
                  id: draft.id,
                  parent: draft.parent,
                  child: draft.child,
                  capacity: draft.capacity,
                  area: area,
                  rect: draft.rect,
                  childSlotAreaIds: draft.childSlotAreaIds,
                  childSlotNumbersByAreaId: draft.childSlotNumbersByAreaId,
                  isTower: draft.isTower,
                  onError: (_) {},
                );
                if (!mounted) return;
                return;
              }

              if (draft is CompositeChildDraft) {
                await locationState.addCompositeChild(
                  parent: draft.parent,
                  child: draft.child,
                  capacity: draft.capacity,
                  area: area,
                  rect: draft.rect,
                  childSlotAreaIds: draft.childSlotAreaIds,
                  childSlotNumbersByAreaId: draft.childSlotNumbersByAreaId,
                  isTower: draft.isTower,
                  onError: (_) {},
                );
                if (!mounted) return;
                return;
              }

              if (draft is PlainTextLocationDraft) {
                await locationState.addPlainTextLocation(
                  name: draft.name,
                  capacity: draft.capacity,
                  area: area,
                  onError: (_) {},
                );
                if (!mounted) return;
                return;
              }

              if (!mounted) return;
            },
          ),
        );
      },
    );
  }

  Future<void> _handleEditPlainText(BuildContext context) async {
    final locationState = context.read<LocationState>();
    final currentArea = context.read<AreaState>().currentArea.trim();

    final selectedId = locationState.selectedLocationId;
    if (selectedId == null) {
      return;
    }

    LocationModel? selected;
    for (final l in locationState.locations) {
      if (l.id == selectedId) {
        selected = l;
        break;
      }
    }

    if (selected == null) {
      return;
    }

    if (_isCompositeParent(selected) || _isCompositeChild(selected)) {
      return;
    }

    final allInArea = locationState.locations
        .where((l) => l.area.trim() == currentArea)
        .toList();

    final existingNameKeysInArea =
        allInArea.map((l) => _nameKey(l.locationName)).toSet();

    final existingChildCompositeKeysInArea = allInArea
        .where((loc) =>
            _isCompositeChild(loc) && (loc.parent ?? '').trim().isNotEmpty)
        .map((loc) => _childCompositeKey(loc.parent!, loc.locationName))
        .toSet();

    final parentNamesInArea = allInArea
        .where(_isCompositeParent)
        .map((p) => p.locationName)
        .toList()
      ..sort();

    final Map<String, ParkingGridModel> parentParkingGridsByParentKey = {};
    for (final p in allInArea.where(_isCompositeParent)) {
      final grid = p.parkingGrid;
      if (grid == null) continue;
      parentParkingGridsByParentKey[_nameKey(p.locationName)] = grid;
    }

    final Map<String, List<GridRect>> existingChildRectsByParentKey = {};
    final Map<String, Set<String>> existingChildAreaIdsByParentKey = {};
    for (final c in allInArea.where(_isCompositeChild)) {
      final pName = (c.parent ?? '').trim();
      if (pName.isEmpty) continue;

      final pk = _nameKey(pName);
      final areaIds = _childAreaIds(c);
      if (areaIds.isNotEmpty) {
        existingChildAreaIdsByParentKey
            .putIfAbsent(pk, () => <String>{})
            .addAll(areaIds);
      }

      final cr = c.childRect;
      if (cr == null) continue;

      existingChildRectsByParentKey
          .putIfAbsent(pk, () => <GridRect>[])
          .add(cr.normalized());
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) {
        return FractionallySizedBox(
          heightFactor: 1,
          child: LocationSettingBottomSheet(
            existingNameKeysInArea: existingNameKeysInArea,
            existingChildCompositeKeysInArea: existingChildCompositeKeysInArea,
            parentNamesInArea: parentNamesInArea,
            parentParkingGridsByParentKey: parentParkingGridsByParentKey,
            existingChildRectsByParentKey: existingChildRectsByParentKey,
            existingChildAreaIdsByParentKey: existingChildAreaIdsByParentKey,
            editingPlainTextId: selected!.id,
            editingPlainTextName: selected.locationName,
            editingPlainTextCapacity: selected.capacity,
            onSave: (draft) async {
              final area = context.read<AreaState>().currentArea.trim();

              if (draft is PlainTextLocationUpdateDraft) {
                await locationState.savePlainTextLocation(
                  id: draft.id,
                  name: draft.name,
                  capacity: draft.capacity,
                  area: area,
                  onError: (_) {},
                );
                if (!mounted) return;
                return;
              }

              if (draft is PlainTextLocationDraft) {
                await locationState.addPlainTextLocation(
                  name: draft.name,
                  capacity: draft.capacity,
                  area: area,
                  onError: (_) {},
                );
                if (!mounted) return;
                return;
              }

              if (!mounted) return;
            },
          ),
        );
      },
    );
  }

  Future<void> _handleDelete(BuildContext context) async {
    final locationState = context.read<LocationState>();
    final selectedId = locationState.selectedLocationId;

    if (selectedId == null) {
      return;
    }

    final confirmed = await _confirmDelete(context);
    if (!confirmed) return;

    await locationState.deleteLocations(
      [selectedId],
      onError: (_) {},
    );

    if (!mounted) return;
  }

  Future<void> _handleRefresh(BuildContext context) async {
    final state = context.read<LocationState>();
    await state.manualLocationRefresh();
    if (!mounted) return;
  }

  bool _matchesLocationQuery(LocationModel loc) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final parts = <String>[
      loc.locationName,
      loc.area,
      loc.type ?? '',
      loc.parent ?? '',
      loc.capacity.toString(),
      loc.isTowerChild ? '타워' : '',
      _slotSummaryText(loc.childSlots),
    ];
    return parts.join(' ').toLowerCase().contains(q);
  }

  Widget _buildCommandBar(BuildContext context, int visible, int total) {
    final cs = Theme.of(context).colorScheme;
    return OpsCommandPanel(
      children: [
        OpsSearchField(
          hint: '구역명 · 부모 구역 · 슬롯 타입 검색',
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OpsFilterChip(
              label: '전체',
              selected: _filter == 'all',
              icon: Icons.grid_view_rounded,
              onSelected: () => setState(() => _filter = 'all'),
            ),
            OpsFilterChip(
              label: '복합',
              selected: _filter == 'composite',
              icon: Icons.account_tree_rounded,
              onSelected: () => setState(() => _filter = 'composite'),
            ),
            OpsFilterChip(
              label: '선택 자식만',
              selected: _showOnlySelectedChild,
              icon: Icons.center_focus_strong_rounded,
              onSelected: () => setState(() => _showOnlySelectedChild = !_showOnlySelectedChild),
            ),
            OpsFilterChip(
              label: '슬롯번호',
              selected: _showSelectedChildSlotNumbers,
              icon: Icons.tag_rounded,
              onSelected: () => setState(() => _showSelectedChildSlotNumbers = !_showSelectedChildSlotNumbers),
            ),
            OpsFilterChip(
              label: '$visible/$total',
              selected: false,
              icon: Icons.filter_alt_rounded,
              onSelected: () {},
            ),
            IconButton.filledTonal(
              tooltip: '자식 슬롯 재계산',
              onPressed: () => _handleRebuildChildSlots(context),
              icon: Icon(Icons.sync_alt_rounded, color: cs.primary),
            ),
            IconButton.filledTonal(
              tooltip: '새로고침',
              onPressed: () => _handleRefresh(context),
              icon: Icon(Icons.refresh_rounded, color: cs.primary),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context, bool hasSelection, bool canEdit, bool canEditParent, bool canEditChild) {
    if (!hasSelection) {
      return OpsBottomActionBar(
        children: [
          Expanded(
            child: OpsActionButton(
              label: '구역 추가',
              icon: Icons.add_location_alt_rounded,
              onPressed: () => _handleAdd(context),
            ),
          ),
        ],
      );
    }

    final editLabel = canEditParent ? '부모 수정' : (canEditChild ? '자식 수정' : '구역 수정');
    return OpsBottomActionBar(
      children: [
        Expanded(
          child: OpsActionButton(
            label: '추가',
            icon: Icons.add_location_alt_rounded,
            onPressed: () => _handleAdd(context),
            tonal: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OpsActionButton(
            label: editLabel,
            icon: Icons.edit_location_alt_rounded,
            onPressed: !canEdit
                ? null
                : () {
                    if (canEditParent) {
                      _handleEditParent(context);
                      return;
                    }
                    if (canEditChild) {
                      _handleEditChild(context);
                      return;
                    }
                    _handleEditPlainText(context);
                  },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OpsActionButton(
            label: '삭제',
            icon: Icons.delete_forever_rounded,
            onPressed: () => _handleDelete(context),
            danger: true,
          ),
        ),
      ],
    );
  }

  Widget _buildFocusedBottomBar({
    required BuildContext context,
    required LocationModel? parentModel,
    required List<LocationModel> children,
    required LocationModel? selectedLocation,
  }) {
    final selectedId = selectedLocation?.id;
    final parentSelected = parentModel != null && selectedId == parentModel.id;
    final childSelected = selectedId != null && children.any((child) => child.id == selectedId);
    final canEditParent = parentModel != null && parentSelected && parentModel.parkingGrid != null;
    final canEditChild = childSelected && selectedLocation != null && selectedLocation.childRect != null;
    final hasFocusedSelection = parentSelected || childSelected;

    if (!hasFocusedSelection) {
      return OpsBottomActionBar(
        children: [
          Expanded(
            child: OpsActionButton(
              label: '자식 추가',
              icon: Icons.add_location_alt_rounded,
              onPressed: () => _handleAdd(context),
              tonal: true,
            ),
          ),
          if (parentModel != null) ...[
            const SizedBox(width: 8),
            Expanded(
              child: OpsActionButton(
                label: '부모 선택',
                icon: Icons.account_tree_rounded,
                onPressed: () => context.read<LocationState>().toggleLocationSelection(parentModel.id),
              ),
            ),
          ],
        ],
      );
    }

    return OpsBottomActionBar(
      children: [
        Expanded(
          child: OpsActionButton(
            label: '추가',
            icon: Icons.add_location_alt_rounded,
            onPressed: () => _handleAdd(context),
            tonal: true,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OpsActionButton(
            label: parentSelected ? '부모 수정' : '자식 수정',
            icon: Icons.edit_location_alt_rounded,
            onPressed: parentSelected
                ? (canEditParent ? () => _handleEditParent(context) : null)
                : (canEditChild ? () => _handleEditChild(context) : null),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OpsActionButton(
            label: '삭제',
            icon: Icons.delete_forever_rounded,
            onPressed: () => _handleDelete(context),
            danger: true,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final locationState = context.watch<LocationState>();
    final cs = Theme.of(context).colorScheme;
    final currentArea = context.watch<AreaState>().currentArea.trim();
    final storageKeyPrefix = 'location_management_${currentArea.toString()}';

    final allInArea = locationState.locations.where((l) => l.area.trim() == currentArea).toList();
    final queriedInArea = allInArea.where(_matchesLocationQuery).toList();

    final legacySingles = queriedInArea.where((loc) {
      final t = loc.type;
      return t == null || t == 'single';
    }).toList();

    final parents = queriedInArea.where(_isCompositeParent).toList();
    final children = queriedInArea.where(_isCompositeChild).toList();
    final allParents = allInArea.where(_isCompositeParent).toList();
    final allChildren = allInArea.where(_isCompositeChild).toList();

    final Map<String, LocationModel> parentByKey = {
      for (final p in allParents) _nameKey(p.locationName): p,
    };

    final Map<String, String> groupDisplayNameByKey = {
      for (final p in allParents) _nameKey(p.locationName): _normalizeName(p.locationName),
    };

    final Map<String, List<LocationModel>> groupedChildren = {};
    for (final child in children) {
      final rawParent = child.parent ?? '';
      final parentTrim = rawParent.trim();

      if (parentTrim.isEmpty) {
        groupedChildren.putIfAbsent(_miscGroupKey, () => []).add(child);
        groupDisplayNameByKey.putIfAbsent(_miscGroupKey, () => '기타');
        continue;
      }

      final pKey = _nameKey(parentTrim);
      final pDisplay = _normalizeName(parentTrim);

      groupedChildren.putIfAbsent(pKey, () => []).add(child);
      groupDisplayNameByKey.putIfAbsent(pKey, () => pDisplay);
    }

    final selectedLocation = _selectedLocation(locationState);
    final hasSelection = selectedLocation != null;
    final canEditParent = selectedLocation != null && _isCompositeParent(selectedLocation) && selectedLocation.parkingGrid != null;
    final canEditChild = selectedLocation != null && _isCompositeChild(selectedLocation) && selectedLocation.childRect != null;
    final canEditPlainText = selectedLocation != null && !_isCompositeParent(selectedLocation) && !_isCompositeChild(selectedLocation);
    final canEdit = canEditParent || canEditChild || canEditPlainText;
    final isEmptyAll = allInArea.isEmpty;
    final visibleCount = legacySingles.length + parents.length + children.length;
    final totalCount = allInArea.length;
    final totalCapacity = allInArea.fold<int>(0, (sum, loc) => sum + loc.capacity);
    final areaLabel = currentArea.isEmpty ? '지역 미설정' : currentArea;
    final rawFocusedParentKey = _focusedParentKey;
    final focusedParentKey = rawFocusedParentKey != null && (parentByKey.containsKey(rawFocusedParentKey) || groupedChildren.containsKey(rawFocusedParentKey))
        ? rawFocusedParentKey
        : null;

    final listScaffold = OpsConsoleScaffold(
      key: const ValueKey<String>('location-management-list'),
      title: '구역 관리',
      icon: Icons.location_on_rounded,
      areaLabel: areaLabel,
      loading: locationState.isLoading,
      metrics: [
        OpsMetric(label: '전체', value: '$totalCount', icon: Icons.location_on_rounded, color: cs.onInverseSurface),
        OpsMetric(label: '부모', value: '${allParents.length}', icon: Icons.account_tree_rounded, color: cs.primary),
        OpsMetric(label: '자식', value: '${allChildren.length}', icon: Icons.subdirectory_arrow_right_rounded, color: cs.secondary),
        OpsMetric(label: '공간', value: '$totalCapacity', icon: Icons.local_parking_rounded, color: cs.primary),
      ],
      commandBar: _buildCommandBar(context, visibleCount, totalCount),
      bottomBar: _buildBottomBar(context, hasSelection, canEdit, canEditParent, canEditChild),
      body: locationState.isLoading
          ? const SizedBox.shrink()
          : isEmptyAll
              ? OpsEmptyState(
                  icon: Icons.add_location_alt_rounded,
                  title: '현재 지역에 주차 구역이 없습니다',
                  message: '구역을 추가해 현장 주차면과 복합 슬롯 구조를 등록하세요.',
                  action: FilledButton.icon(
                    onPressed: () => _handleAdd(context),
                    icon: const Icon(Icons.add_location_alt_rounded),
                    label: const Text('구역 추가'),
                  ),
                )
              : visibleCount == 0
                  ? const OpsEmptyState(
                      icon: Icons.search_off_rounded,
                      title: '검색 결과가 없습니다',
                      message: '검색어와 필터를 조정하세요.',
                    )
                  : _filter == 'composite'
                      ? _buildCompositeList(
                          parentByKey: parentByKey,
                          groupedChildren: groupedChildren,
                          groupDisplayNameByKey: groupDisplayNameByKey,
                          state: locationState,
                          cs: cs,
                          storageKeyPrefix: storageKeyPrefix,
                        )
                      : _buildAllListView(
                          legacySingles: legacySingles,
                          parentByKey: parentByKey,
                          groupedChildren: groupedChildren,
                          groupDisplayNameByKey: groupDisplayNameByKey,
                          state: locationState,
                          cs: cs,
                          storageKeyPrefix: storageKeyPrefix,
                        ),
    );

    final focusedScaffold = focusedParentKey == null
        ? null
        : _buildFocusedParentScaffold(
            context: context,
            keyValue: focusedParentKey,
            groupName: groupDisplayNameByKey[focusedParentKey] ?? focusedParentKey,
            parentModel: parentByKey[focusedParentKey],
            children: [...(groupedChildren[focusedParentKey] ?? const <LocationModel>[])],
            state: locationState,
            selectedLocation: selectedLocation,
            cs: cs,
            areaLabel: areaLabel,
            storageKeyPrefix: storageKeyPrefix,
          );

    return PopScope(
      canPop: focusedParentKey == null,
      onPopInvoked: (didPop) {
        if (didPop) return;
        if (_focusedParentKey != null) _closeFocusedParent();
      },
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        reverseDuration: const Duration(milliseconds: 220),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final position = Tween<Offset>(
            begin: const Offset(.07, 0),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: position,
              child: child,
            ),
          );
        },
        child: focusedScaffold ?? listScaffold,
      ),
    );
  }

  Widget _buildFocusedParentScaffold({
    required BuildContext context,
    required String keyValue,
    required String groupName,
    required LocationModel? parentModel,
    required List<LocationModel> children,
    required LocationState state,
    required LocationModel? selectedLocation,
    required ColorScheme cs,
    required String areaLabel,
    required String storageKeyPrefix,
  }) {
    children.sort((a, b) => a.locationName.compareTo(b.locationName));
    final totalCapacity = children.fold<int>(0, (sum, loc) => sum + loc.capacity);
    final grid = parentModel?.parkingGrid;
    final selectedInFocus = selectedLocation != null && (selectedLocation.id == parentModel?.id || children.any((child) => child.id == selectedLocation.id));
    final selectedLabel = selectedInFocus ? '선택됨' : '미선택';

    return OpsConsoleScaffold(
      key: ValueKey<String>('location-focused-$keyValue'),
      title: groupName,
      icon: Icons.account_tree_rounded,
      areaLabel: areaLabel,
      loading: state.isLoading,
      trailing: IconButton.filledTonal(
        tooltip: '목록으로 돌아가기',
        onPressed: _closeFocusedParent,
        icon: const Icon(Icons.close_rounded),
      ),
      metrics: [
        OpsMetric(label: '자식', value: '${children.length}', icon: Icons.subdirectory_arrow_right_rounded, color: cs.secondary),
        OpsMetric(label: '공간', value: '$totalCapacity', icon: Icons.local_parking_rounded, color: cs.primary),
        OpsMetric(label: '그리드', value: grid == null ? '없음' : '${grid.rows}×${grid.cols}', icon: Icons.grid_on_rounded, color: cs.primary),
        OpsMetric(label: '선택', value: selectedLabel, icon: Icons.check_circle_rounded, color: selectedInFocus ? cs.primary : cs.onInverseSurface),
      ],
      bottomBar: _buildFocusedBottomBar(
        context: context,
        parentModel: parentModel,
        children: children,
        selectedLocation: selectedLocation,
      ),
      body: _buildFocusedParentView(
        groupKey: keyValue,
        groupName: groupName,
        parentModel: parentModel,
        children: children,
        state: state,
        cs: cs,
        storageKeyPrefix: storageKeyPrefix,
      ),
    );
  }

  Widget _buildAllListView({
    required List<LocationModel> legacySingles,
    required Map<String, LocationModel> parentByKey,
    required Map<String, List<LocationModel>> groupedChildren,
    required Map<String, String> groupDisplayNameByKey,
    required LocationState state,
    required ColorScheme cs,
    required String storageKeyPrefix,
  }) {
    final tiles = <Widget>[];

    if (legacySingles.isNotEmpty) {
      tiles.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Text(
            '텍스트형/단일 주차 구역',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
          ),
        ),
      );
      tiles.addAll(_buildLegacySingleTiles(legacySingles, state, cs));
    }

    if (legacySingles.isNotEmpty && groupedChildren.isNotEmpty) {
      tiles.add(Divider(color: cs.outlineVariant.withOpacity(.55)));
    }

    if (groupedChildren.isNotEmpty || parentByKey.isNotEmpty) {
      tiles.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Text(
            '복합 주차 구역',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: cs.onSurface,
                ),
          ),
        ),
      );

      tiles.addAll(_buildCompositeTiles(
        parentByKey: parentByKey,
        groupedChildren: groupedChildren,
        groupDisplayNameByKey: groupDisplayNameByKey,
        state: state,
        cs: cs,
        storageKeyPrefix: storageKeyPrefix,
      ));
    }

    return ListView(
      key: PageStorageKey<String>('${storageKeyPrefix}_all_list'),
      children: tiles,
    );
  }

  Widget _buildCompositeList({
    required Map<String, LocationModel> parentByKey,
    required Map<String, List<LocationModel>> groupedChildren,
    required Map<String, String> groupDisplayNameByKey,
    required LocationState state,
    required ColorScheme cs,
    required String storageKeyPrefix,
  }) {
    return ListView(
      key: PageStorageKey<String>('${storageKeyPrefix}_composite_list'),
      padding: const EdgeInsets.only(top: 10),
      children: _buildCompositeTiles(
        parentByKey: parentByKey,
        groupedChildren: groupedChildren,
        groupDisplayNameByKey: groupDisplayNameByKey,
        state: state,
        cs: cs,
        storageKeyPrefix: storageKeyPrefix,
      ),
    );
  }

  List<Widget> _buildLegacySingleTiles(
    List<LocationModel> list,
    LocationState state,
    ColorScheme cs,
  ) {
    return List<Widget>.generate(list.length, (index) {
      final loc = list[index];
      final isSelected = state.selectedLocationId == loc.id;

      return InkWell(
        onTap: () => state.toggleLocationSelection(loc.id),
        borderRadius: BorderRadius.circular(16),
        child: OpsPanel(
          selected: isSelected,
          padding: EdgeInsets.zero,
          child: Row(
            children: [
              Container(
                width: 6,
                height: 96,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              loc.locationName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface, fontSize: 16),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OpsStatusBadge(label: '단일', color: cs.primary, icon: Icons.location_on_rounded),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          OpsInfoPill(text: loc.capacity > 0 ? '공간 ${loc.capacity}대' : '공간 미지정', icon: Icons.local_parking_rounded),
                          OpsInfoPill(text: loc.area.isEmpty ? '지역 미설정' : loc.area, icon: Icons.business_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Icon(
                  isSelected ? Icons.check_circle_rounded : Icons.chevron_right_rounded,
                  color: isSelected ? cs.primary : cs.onSurfaceVariant.withOpacity(.7),
                ),
              ),
            ],
          ),
        ),
      );
    });
  }

  List<Widget> _buildCompositeTiles({
    required Map<String, LocationModel> parentByKey,
    required Map<String, List<LocationModel>> groupedChildren,
    required Map<String, String> groupDisplayNameByKey,
    required LocationState state,
    required ColorScheme cs,
    required String storageKeyPrefix,
  }) {
    final parentKeysOrdered = parentByKey.keys.toList()
      ..sort((a, b) {
        final ad = groupDisplayNameByKey[a] ?? a;
        final bd = groupDisplayNameByKey[b] ?? b;
        return ad.compareTo(bd);
      });

    final remainingKeys = groupedChildren.keys.where((k) => !parentByKey.containsKey(k)).toList()
      ..sort((a, b) {
        final ad = groupDisplayNameByKey[a] ?? a;
        final bd = groupDisplayNameByKey[b] ?? b;
        return ad.compareTo(bd);
      });

    final groupKeys = [...parentKeysOrdered, ...remainingKeys];

    return groupKeys.map((gKey) {
      final groupName = groupDisplayNameByKey[gKey] ?? gKey;
      final children = [...(groupedChildren[gKey] ?? const <LocationModel>[])]..sort((a, b) => a.locationName.compareTo(b.locationName));
      final totalCapacity = children.fold<int>(0, (sum, loc) => sum + loc.capacity);
      final parentModel = parentByKey[gKey];
      final parentId = parentModel?.id;
      final parentSelected = parentId != null && state.selectedLocationId == parentId;
      final grid = parentModel?.parkingGrid;
      final selectedChildCount = children.where((child) => state.selectedLocationId == child.id).length;
      final accent = selectedChildCount > 0 ? cs.secondary : cs.primary;

      return InkWell(
        onTap: () => _openFocusedParent(gKey),
        borderRadius: BorderRadius.circular(16),
        child: OpsPanel(
          selected: parentSelected || selectedChildCount > 0,
          padding: EdgeInsets.zero,
          accentColor: accent,
          margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 112,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 13, 10, 13),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              groupName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w900,
                                fontSize: 16.5,
                                letterSpacing: -.2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          OpsStatusBadge(
                            label: grid == null ? '도면 없음' : '도면',
                            color: grid == null ? cs.onSurfaceVariant : cs.primary,
                            icon: grid == null ? Icons.grid_off_rounded : Icons.grid_on_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          OpsInfoPill(text: '자식 ${children.length}개', icon: Icons.subdirectory_arrow_right_rounded),
                          OpsInfoPill(text: '공간 $totalCapacity대', icon: Icons.local_parking_rounded),
                          OpsInfoPill(text: grid == null ? '그리드 미지정' : '${grid.rows}×${grid.cols}', icon: Icons.grid_view_rounded),
                          if (selectedChildCount > 0) OpsInfoPill(text: '자식 선택됨', icon: Icons.check_circle_rounded),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton.filledTonal(
                    tooltip: parentSelected ? '부모 선택 해제' : '부모 선택',
                    onPressed: parentId == null ? null : () => state.toggleLocationSelection(parentId),
                    icon: Icon(parentSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded),
                  ),
                  const SizedBox(height: 5),
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: Icon(Icons.open_in_full_rounded, color: cs.primary, size: 20),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  Widget _buildFocusedParentView({
    required String groupKey,
    required String groupName,
    required LocationModel? parentModel,
    required List<LocationModel> children,
    required LocationState state,
    required ColorScheme cs,
    required String storageKeyPrefix,
  }) {
    final selectedId = state.selectedLocationId;
    final selectedLoc = _selectedLocation(state);
    final grid = parentModel?.parkingGrid;

    LocationModel? selectedChildInThisGroup;
    if (selectedLoc != null && _isCompositeChild(selectedLoc)) {
      final pk = _nameKey((selectedLoc.parent ?? '').trim());
      if (pk == groupKey) {
        selectedChildInThisGroup = selectedLoc;
      }
    }

    final overlaysAll = <ChildRegionOverlay>[];
    for (final child in children) {
      final rect = child.childRect;
      if (rect == null) continue;
      overlaysAll.add(
        ChildRegionOverlay(
          rect: rect,
          label: child.locationName.trim(),
          isSelected: selectedId != null && child.id == selectedId,
        ),
      );
    }

    final overlays = (_showOnlySelectedChild && selectedChildInThisGroup != null) ? overlaysAll.where((o) => o.isSelected).toList() : overlaysAll;
    final childSlotsToLabel = (selectedChildInThisGroup != null && _showSelectedChildSlotNumbers) ? selectedChildInThisGroup.childSlots : const <ChildSlot>[];
    final childrenForList = (_showOnlySelectedChild && selectedChildInThisGroup != null) ? children.where((c) => c.id == selectedChildInThisGroup!.id).toList() : children;
    final emptyCells = grid == null ? null : _countEmptyCells(grid);
    final parkingAreas = grid == null ? null : _countParkingAreas(grid);
    final parkingAreaCells = grid == null ? null : _countParkingAreaCells(grid);
    final parkingKindSummary = grid == null ? '' : _parkingAreaKindSummary(grid);
    final selectedChildSlotSummary = selectedChildInThisGroup == null ? '' : _slotSummaryText(selectedChildInThisGroup.childSlots);

    return ListView(
      key: PageStorageKey<String>('${storageKeyPrefix}_focused_$groupKey'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
      children: [
        OpsCommandPanel(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    '부모 구역 작업 화면',
                    style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900, fontSize: 14.5, letterSpacing: -.15),
                  ),
                ),
                TextButton.icon(
                  onPressed: _closeFocusedParent,
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('목록'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OpsFilterChip(
                  label: '선택 자식만',
                  selected: _showOnlySelectedChild,
                  icon: Icons.center_focus_strong_rounded,
                  onSelected: () => setState(() => _showOnlySelectedChild = !_showOnlySelectedChild),
                ),
                OpsFilterChip(
                  label: '슬롯번호',
                  selected: _showSelectedChildSlotNumbers,
                  icon: Icons.tag_rounded,
                  onSelected: () => setState(() => _showSelectedChildSlotNumbers = !_showSelectedChildSlotNumbers),
                ),
                if (parentModel != null)
                  OpsFilterChip(
                    label: state.selectedLocationId == parentModel.id ? '부모 선택됨' : '부모 선택',
                    selected: state.selectedLocationId == parentModel.id,
                    icon: Icons.account_tree_rounded,
                    onSelected: () => state.toggleLocationSelection(parentModel.id),
                  ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (grid != null)
          OpsPanel(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        '레이아웃 그리드 ${grid.rows}×${grid.cols}',
                        style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900, fontSize: 15.5),
                      ),
                    ),
                    OpsStatusBadge(label: '도면', color: cs.primary, icon: Icons.grid_on_rounded),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    OpsInfoPill(text: '빈칸 $emptyCells', icon: Icons.crop_free_rounded),
                    if ((parkingAreas ?? 0) > 0) OpsInfoPill(text: '주차면적 $parkingAreas', icon: Icons.local_parking_rounded),
                    if ((parkingAreaCells ?? 0) > 0) OpsInfoPill(text: '면적셀 $parkingAreaCells', icon: Icons.grid_4x4_rounded),
                  ],
                ),
                if (parkingKindSummary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    parkingKindSummary,
                    style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                ],
                if (selectedChildSlotSummary.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    '선택 자식 슬롯: $selectedChildSlotSummary',
                    style: TextStyle(color: cs.primary, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                ParkingGridPreview(
                  grid: grid,
                  maxExtent: 360,
                  showLegend: true,
                  showChildRegions: true,
                  childRegions: overlays,
                  showChildRegionLabels: true,
                  showAllChildRegionLabels: false,
                  showChildSlotNumbers: _showSelectedChildSlotNumbers,
                  childSlotsToLabel: childSlotsToLabel,
                ),
              ],
            ),
          )
        else
          OpsPanel(
            accentColor: cs.error,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.grid_off_rounded, color: cs.error),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '이 부모 구역은 parkingGrid가 없습니다. 저장 상태나 마이그레이션 결과를 확인하세요.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800, height: 1.28),
                  ),
                ),
              ],
            ),
          ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.fromLTRB(2, 8, 2, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '자식 주차 구역',
                  style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900, fontSize: 15.5, letterSpacing: -.15),
                ),
              ),
              OpsStatusBadge(label: '${childrenForList.length}/${children.length}', color: cs.secondary, icon: Icons.segment_rounded),
            ],
          ),
        ),
        if (childrenForList.isEmpty)
          OpsPanel(
            child: Column(
              children: [
                Icon(Icons.subdirectory_arrow_right_rounded, color: cs.onSurfaceVariant, size: 30),
                const SizedBox(height: 8),
                Text(
                  _showOnlySelectedChild ? '선택된 자식 구역이 없습니다' : '등록된 자식 구역이 없습니다',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900),
                ),
              ],
            ),
          )
        else
          ...childrenForList.map((loc) => _buildFocusedChildTile(loc, state, cs)).toList(),
      ],
    );
  }

  Widget _buildFocusedChildTile(LocationModel loc, LocationState state, ColorScheme cs) {
    final isSelected = state.selectedLocationId == loc.id;
    final subtitleParts = <String>[];
    if (loc.isTowerChild) {
      subtitleParts.add('타워');
    }
    if (loc.capacity > 0) {
      subtitleParts.add('공간 ${loc.capacity}대');
    }
    final slotSummary = _slotSummaryText(loc.childSlots);
    if (!loc.isTowerChild && slotSummary.isNotEmpty) {
      subtitleParts.add(slotSummary);
    }

    return InkWell(
      onTap: () => state.toggleLocationSelection(loc.id),
      borderRadius: BorderRadius.circular(16),
      child: OpsPanel(
        selected: isSelected,
        accentColor: cs.secondary,
        padding: EdgeInsets.zero,
        child: Row(
          children: [
            Container(
              width: 6,
              height: 94,
              decoration: BoxDecoration(
                color: isSelected ? cs.secondary : cs.outlineVariant,
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 10, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            loc.locationName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900, fontSize: 15.5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OpsStatusBadge(
                          label: loc.isTowerChild ? '타워' : '자식',
                          color: isSelected ? cs.secondary : cs.onSurfaceVariant,
                          icon: loc.isTowerChild ? Icons.view_in_ar_rounded : Icons.subdirectory_arrow_right_rounded,
                        ),
                      ],
                    ),
                    if (subtitleParts.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: subtitleParts.map((part) => OpsInfoPill(text: part, icon: Icons.info_outline_rounded)).toList(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                isSelected ? Icons.check_circle_rounded : Icons.touch_app_rounded,
                color: isSelected ? cs.secondary : cs.onSurfaceVariant.withOpacity(.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
