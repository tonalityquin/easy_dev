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

class LocationManagement extends StatefulWidget {
  const LocationManagement({super.key});

  @override
  State<LocationManagement> createState() => _LocationManagementState();
}

class _LocationManagementState extends State<LocationManagement> {
  String _filter = 'all';

  bool _showOnlySelectedChild = false;

  bool _showSelectedChildSlotNumbers = true;

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

  static const double _fabBottomGap = 48.0;
  static const double _fabSpacing = 10.0;

  static const String _miscGroupKey = '__misc__';

  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.labelSmall;

    final style = (base ??
            const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ))
        .copyWith(
      color: cs.onSurfaceVariant.withOpacity(.72),
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return SafeArea(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: location management',
              child: Text('location management', style: style),
            ),
          ),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('삭제 확인'),
            content: const Text('선택한 주차 구역을 삭제하시겠습니까?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('삭제'),
              ),
            ],
          ),
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

  @override
  Widget build(BuildContext context) {
    final locationState = context.watch<LocationState>();
    final cs = Theme.of(context).colorScheme;
    final currentArea = context.watch<AreaState>().currentArea.trim();

    final storageKeyPrefix = 'location_management_${currentArea.toString()}';

    final allInArea = locationState.locations
        .where((l) => l.area.trim() == currentArea)
        .toList();

    final legacySingles = allInArea.where((loc) {
      final t = loc.type;
      return t == null || t == 'single';
    }).toList();

    final parents = allInArea.where(_isCompositeParent).toList();
    final children = allInArea.where(_isCompositeChild).toList();

    final Map<String, LocationModel> parentByKey = {
      for (final p in parents) _nameKey(p.locationName): p,
    };

    final Map<String, String> groupDisplayNameByKey = {
      for (final p in parents)
        _nameKey(p.locationName): _normalizeName(p.locationName),
    };

    final Map<String, List<LocationModel>> groupedChildren = {};
    for (final child in children) {
      final rawParent = (child.parent ?? '');
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

    final hasSelection = locationState.selectedLocationId != null;

    LocationModel? selectedLocation;
    if (hasSelection) {
      final id = locationState.selectedLocationId;
      for (final l in locationState.locations) {
        if (l.id == id) {
          selectedLocation = l;
          break;
        }
      }
    }

    final canEditParent = selectedLocation != null &&
        _isCompositeParent(selectedLocation) &&
        selectedLocation.parkingGrid != null;

    final canEditChild = selectedLocation != null &&
        _isCompositeChild(selectedLocation) &&
        selectedLocation.childRect != null;
    final canEditPlainText = selectedLocation != null &&
        !_isCompositeParent(selectedLocation) &&
        !_isCompositeChild(selectedLocation);

    final canEdit = canEditParent || canEditChild || canEditPlainText;
    final isEmptyAll =
        legacySingles.isEmpty && parents.isEmpty && children.isEmpty;

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        backgroundColor: cs.surface,
        elevation: 0,
        foregroundColor: cs.onSurface,
        surfaceTintColor: Colors.transparent,
        flexibleSpace: _buildScreenTag(context),
        title:
            const Text('주차구역', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: '기존 자식 슬롯 재계산',
            onPressed: () => _handleRebuildChildSlots(context),
            icon: const Icon(Icons.sync_alt),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: () => _handleRefresh(context),
            icon: const Icon(Icons.refresh),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child:
              Container(height: 1, color: cs.outlineVariant.withOpacity(.75)),
        ),
      ),
      body: locationState.isLoading
          ? Center(
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
              ),
            )
          : isEmptyAll
              ? const Center(child: Text('현재 지역에 주차 구역이 없습니다.'))
              : Column(
                  children: [
                    Container(
                      width: double.infinity,
                      color: cs.surface,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _FilterChip(
                                label: '전체',
                                selected: _filter == 'all',
                                onSelected: () =>
                                    setState(() => _filter = 'all'),
                              ),
                              const SizedBox(width: 8),
                              _FilterChip(
                                label: '복합',
                                selected: _filter == 'composite',
                                onSelected: () =>
                                    setState(() => _filter = 'composite'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Wrap(
                              spacing: 10,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                FilterChip(
                                  label: const Text('선택 자식만 표시'),
                                  selected: _showOnlySelectedChild,
                                  onSelected: (v) => setState(
                                      () => _showOnlySelectedChild = v),
                                ),
                                FilterChip(
                                  label: const Text('선택 자식 슬롯번호'),
                                  selected: _showSelectedChildSlotNumbers,
                                  onSelected: (v) => setState(
                                      () => _showSelectedChildSlotNumbers = v),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Divider(
                        height: 1, color: cs.outlineVariant.withOpacity(.75)),
                    Expanded(
                      child: _filter == 'composite'
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
                    ),
                  ],
                ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      floatingActionButton: _FabStack(
        bottomGap: _fabBottomGap,
        spacing: _fabSpacing,
        hasSelection: hasSelection,
        onAdd: () => _handleAdd(context),
        onEdit: !canEdit
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
        onDelete: hasSelection ? () => _handleDelete(context) : null,
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

    if (groupedChildren.isNotEmpty) {
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

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        color: cs.surface,
        elevation: isSelected ? 3 : 1,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: isSelected ? cs.primary : cs.outlineVariant.withOpacity(.65),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: ListTile(
          title: const Text(' ', style: TextStyle(fontSize: 0)),
          subtitle: DefaultTextStyle(
            style: TextStyle(color: cs.onSurfaceVariant, height: 1.2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  loc.locationName,
                  style: TextStyle(
                      fontWeight: FontWeight.w800, color: cs.onSurface),
                ),
                if (loc.capacity > 0) Text('공간 ${loc.capacity}대'),
              ],
            ),
          ),
          leading: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withOpacity(.55),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
            ),
            child: Icon(Icons.location_on, color: cs.primary, size: 20),
          ),
          trailing: isSelected
              ? Icon(Icons.check_circle, color: cs.primary)
              : Icon(Icons.chevron_right,
                  color: cs.onSurfaceVariant.withOpacity(.75)),
          selected: isSelected,
          onTap: () => state.toggleLocationSelection(loc.id),
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

    final remainingKeys =
        groupedChildren.keys.where((k) => !parentByKey.containsKey(k)).toList()
          ..sort((a, b) {
            final ad = groupDisplayNameByKey[a] ?? a;
            final bd = groupDisplayNameByKey[b] ?? b;
            return ad.compareTo(bd);
          });

    final groupKeys = [...parentKeysOrdered, ...remainingKeys];

    final selectedId = state.selectedLocationId;
    final selectedLoc = (selectedId == null)
        ? null
        : state.locations.cast<LocationModel?>().firstWhere(
              (l) => l != null && l.id == selectedId,
              orElse: () => null,
            );

    return groupKeys.map((gKey) {
      final groupName = groupDisplayNameByKey[gKey] ?? gKey;

      final children = (groupedChildren[gKey] ?? <LocationModel>[])
        ..sort((a, b) => a.locationName.compareTo(b.locationName));

      final totalCapacity =
          children.fold<int>(0, (sum, loc) => sum + loc.capacity);

      final parentModel = parentByKey[gKey];
      final parentId = parentModel?.id;
      final parentSelected =
          parentId != null && state.selectedLocationId == parentId;

      final grid = parentModel?.parkingGrid;

      LocationModel? selectedChildInThisGroup;
      if (selectedLoc != null && _isCompositeChild(selectedLoc)) {
        final pk = _nameKey((selectedLoc.parent ?? '').trim());
        if (pk == gKey) {
          selectedChildInThisGroup = selectedLoc;
        }
      }

      final overlaysAll = <ChildRegionOverlay>[];
      for (final c in children) {
        final rect = c.childRect;
        if (rect == null) continue;
        overlaysAll.add(
          ChildRegionOverlay(
            rect: rect,
            label: c.locationName.trim(),
            isSelected: (selectedId != null && c.id == selectedId),
          ),
        );
      }

      final overlays =
          (_showOnlySelectedChild && selectedChildInThisGroup != null)
              ? overlaysAll.where((o) => o.isSelected).toList()
              : overlaysAll;

      final childSlotsToLabel =
          (selectedChildInThisGroup != null && _showSelectedChildSlotNumbers)
              ? selectedChildInThisGroup.childSlots
              : const <ChildSlot>[];

      final emptyCells = (grid != null) ? _countEmptyCells(grid) : null;
      final parkingAreas = (grid != null) ? _countParkingAreas(grid) : null;
      final parkingAreaCells =
          (grid != null) ? _countParkingAreaCells(grid) : null;

      final layoutMeta = (grid == null)
          ? ''
          : ' · 빈칸 $emptyCells'
              '${(parkingAreas ?? 0) > 0 ? ' · 주차면적 $parkingAreas' : ''}'
              '${(parkingAreaCells ?? 0) > 0 ? ' · 면적셀 $parkingAreaCells' : ''}';

      final parkingKindSummary =
          grid == null ? '' : _parkingAreaKindSummary(grid);
      final selectedChildSlotSummary = selectedChildInThisGroup == null
          ? ''
          : _slotSummaryText(selectedChildInThisGroup.childSlots);

      final childrenForList = (_showOnlySelectedChild &&
              selectedChildInThisGroup != null)
          ? children.where((c) => c.id == selectedChildInThisGroup!.id).toList()
          : children;

      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: cs.outlineVariant.withOpacity(.65)),
        ),
        color: cs.surface,
        elevation: 1,
        surfaceTintColor: Colors.transparent,
        child: Theme(
          data: Theme.of(context).copyWith(
            dividerColor: Colors.transparent,
            expansionTileTheme: ExpansionTileThemeData(
              iconColor: cs.primary,
              collapsedIconColor: cs.onSurfaceVariant,
              textColor: cs.onSurface,
              collapsedTextColor: cs.onSurface,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              collapsedShape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
          child: ExpansionTile(
            key: PageStorageKey<String>('${storageKeyPrefix}_exp_$gKey'),
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '부모 구역: $groupName (공간 $totalCapacity대)',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, color: cs.onSurface),
                  ),
                ),
                if (parentId != null)
                  IconButton(
                    tooltip: parentSelected ? '부모 선택 해제' : '부모 선택',
                    icon: Icon(
                      parentSelected
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      color: parentSelected ? cs.primary : cs.onSurfaceVariant,
                    ),
                    onPressed: () => state.toggleLocationSelection(parentId),
                  ),
              ],
            ),
            childrenPadding: const EdgeInsets.only(bottom: 8),
            children: [
              if (grid != null) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '레이아웃 그리드 (${grid.rows}×${grid.cols})$layoutMeta',
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (parkingKindSummary.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          parkingKindSummary,
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      if (selectedChildSlotSummary.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '선택 자식 슬롯: $selectedChildSlotSummary',
                          style: TextStyle(
                            color: cs.primary,
                            fontWeight: FontWeight.w800,
                            fontSize: 12,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      ParkingGridPreview(
                        grid: grid,
                        maxExtent: 320,
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
                ),
                Divider(height: 1, color: cs.outlineVariant.withOpacity(.55)),
              ] else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: Text(
                    '⚠️ 이 부모 구역은 parkingGrid가 없습니다. (저장/마이그레이션 확인 필요)',
                    style: TextStyle(
                      color: cs.onSurfaceVariant.withOpacity(.85),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant.withOpacity(.55)),
              ],
              ...childrenForList.map((loc) {
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

                return ListTile(
                  title: Text(
                    loc.locationName,
                    style: TextStyle(
                        fontWeight: FontWeight.w700, color: cs.onSurface),
                  ),
                  subtitle: subtitleParts.isNotEmpty
                      ? Text(
                          subtitleParts.join(' · '),
                          style: TextStyle(color: cs.onSurfaceVariant),
                        )
                      : null,
                  leading: Icon(Icons.subdirectory_arrow_right,
                      color: cs.onSurfaceVariant),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: cs.primary)
                      : null,
                  selected: isSelected,
                  onTap: () => state.toggleLocationSelection(loc.id),
                );
              }).toList(),
            ],
          ),
        ),
      );
    }).toList();
  }
}

class _FabStack extends StatelessWidget {
  const _FabStack({
    required this.bottomGap,
    required this.spacing,
    required this.hasSelection,
    required this.onAdd,
    this.onEdit,
    required this.onDelete,
  });

  final double bottomGap;
  final double spacing;
  final bool hasSelection;
  final VoidCallback onAdd;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final ButtonStyle primaryStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      elevation: 3,
      shadowColor: cs.primary.withOpacity(0.25),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    final ButtonStyle deleteStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.error,
      foregroundColor: cs.onError,
      elevation: 3,
      shadowColor: cs.error.withOpacity(0.35),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    final ButtonStyle editStyle = ElevatedButton.styleFrom(
      backgroundColor: cs.secondary,
      foregroundColor: cs.onSecondary,
      elevation: 3,
      shadowColor: cs.secondary.withOpacity(0.25),
      shape: const StadiumBorder(),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      textStyle: const TextStyle(fontWeight: FontWeight.w700),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        _ElevatedPillButton.icon(
          icon: Icons.add,
          label: '추가',
          style: primaryStyle,
          onPressed: onAdd,
        ),
        if (onEdit != null) ...[
          SizedBox(height: spacing),
          _ElevatedPillButton.icon(
            icon: Icons.edit,
            label: '수정',
            style: editStyle,
            onPressed: onEdit!,
          ),
        ],
        if (hasSelection) ...[
          SizedBox(height: spacing),
          _ElevatedPillButton.icon(
            icon: Icons.delete,
            label: '삭제',
            style: deleteStyle,
            onPressed: onDelete!,
          ),
        ],
        SizedBox(height: bottomGap),
      ],
    );
  }
}

class _ElevatedPillButton extends StatelessWidget {
  const _ElevatedPillButton({
    required this.child,
    required this.onPressed,
    required this.style,
  });

  factory _ElevatedPillButton.icon({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required ButtonStyle style,
  }) {
    return _ElevatedPillButton(
      onPressed: onPressed,
      style: style,
      child: _FabLabel(icon: icon, label: label),
    );
  }

  final Widget child;
  final VoidCallback onPressed;
  final ButtonStyle style;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: style,
      child: child,
    );
  }
}

class _FabLabel extends StatelessWidget {
  const _FabLabel({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 8),
        Text(label),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ChoiceChip(
      label: Text(label),
      selected: selected,
      labelStyle: TextStyle(
        fontWeight: FontWeight.w800,
        color: selected ? cs.onPrimary : cs.onSurfaceVariant,
      ),
      selectedColor: cs.primary,
      backgroundColor: cs.surface,
      side: BorderSide(
        color: selected ? cs.primary : cs.outlineVariant.withOpacity(.6),
      ),
      onSelected: (_) => onSelected(),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    );
  }
}
