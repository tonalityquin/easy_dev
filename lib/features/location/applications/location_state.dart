import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dev/application/area_state.dart';
import '../domain/models/grid_rect.dart';
import '../domain/models/location_model.dart';
import '../domain/models/parking_grid_model.dart';
import '../domain/repositories/location_repository.dart';

class LocationState extends ChangeNotifier {
  static const String _cacheLocationsPrefix = 'cached_locations_';
  static const String _cacheTotalCapacityPrefix = 'total_capacity_';

  final LocationRepository _repository;
  final AreaState _areaState;

  List<LocationModel> _locations = [];
  String? _selectedLocationId;
  String _previousArea = '';
  bool _isLoading = true;

  Map<String, int> _plateCountsByDisplayName = <String, int>{};

  bool _disposed = false;

  int _cacheLoadSeq = 0;
  int _repoSyncSeq = 0;

  bool _cacheLoadScheduled = false;

  final Map<String, Future<void>> _cacheLoadInFlightByArea =
      <String, Future<void>>{};
  final Map<String, Future<void>> _repoSyncInFlightByArea =
      <String, Future<void>>{};
  final Map<String, Future<List<LocationModel>>> _areaSnapshotInFlightByArea =
      <String, Future<List<LocationModel>>>{};

  List<LocationModel> get locations => _locations;

  String? get selectedLocationId => _selectedLocationId;

  bool get isLoading => _isLoading;

  Map<String, int> get plateCountsByDisplayName => _plateCountsByDisplayName;

  LocationState(this._repository, this._areaState) {
    Future.microtask(loadFromLocationCache);
    _areaState.addListener(_handleAreaChange);
  }

  @override
  void dispose() {
    _disposed = true;
    _areaState.removeListener(_handleAreaChange);
    super.dispose();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _resetLocationsStateForEmptyArea() {
    _locations = [];
    _selectedLocationId = null;
    _previousArea = '';
    _isLoading = false;
    _safeNotify();
  }

  static List<Map<String, dynamic>> _decodeCachedLocationsToMaps(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return <Map<String, dynamic>>[];

    final decoded = jsonDecode(trimmed);
    if (decoded is! List) {
      throw const FormatException('cached_locations is not a List');
    }

    final out = <Map<String, dynamic>>[];
    for (final item in decoded) {
      if (item is Map) {
        out.add(Map<String, dynamic>.from(item));
      }
    }
    return out;
  }

  static String _cacheKeyForArea(String area) =>
      '$_cacheLocationsPrefix${area.trim()}';

  static String _capacityKeyForArea(String area) =>
      '$_cacheTotalCapacityPrefix${area.trim()}';

  bool _shouldDropCacheResult({
    required int seq,
    required String requestedArea,
  }) {
    if (_disposed) return true;
    if (seq != _cacheLoadSeq) return true;
    final nowArea = _areaState.currentArea.trim();
    if (nowArea != requestedArea) return true;
    return false;
  }

  bool _shouldDropRepoResult({
    required int seq,
    required String requestedArea,
  }) {
    if (_disposed) return true;
    if (seq != _repoSyncSeq) return true;
    final nowArea = _areaState.currentArea.trim();
    if (nowArea != requestedArea) return true;
    return false;
  }

  void _handleAreaChange() {
    final currentArea = _areaState.currentArea.trim();
    if (currentArea == _previousArea) return;

    _previousArea = currentArea;

    if (_cacheLoadScheduled) return;
    _cacheLoadScheduled = true;

    Future.microtask(() async {
      _cacheLoadScheduled = false;
      if (_disposed) return;
      await loadFromLocationCache();
    });
  }

  static String _normalizeName(String raw) =>
      raw.trim().replaceAll(RegExp(r'\s+'), ' ');

  static String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

  static String _safeIdSeg(String v) => _normalizeName(v).replaceAll('/', '_');

  static String _parentDocId({required String parent, required String area}) =>
      '${_safeIdSeg(parent)}_${area.trim()}';

  static String _childDocId({
    required String parent,
    required String child,
    required String area,
  }) =>
      '${_safeIdSeg(parent)}__${_safeIdSeg(child)}_${area.trim()}';

  static String _plainTextDocId({
    required String name,
    required String area,
  }) =>
      'single__${_safeIdSeg(name)}_${area.trim()}';

  static String _childCompositeKey(String parent, String child) =>
      '${_nameKey(parent)}|${_nameKey(child)}';

  bool _isCompositeParent(LocationModel loc) =>
      (loc.type ?? '') == 'composite_parent';

  bool _isCompositeChild(LocationModel loc) {
    final t = loc.type ?? 'single';
    return t == 'composite_child' || t == 'composite';
  }

  String _displayNameForCounts(LocationModel loc) {
    final leaf = loc.locationName.trim();
    final parent = (loc.parent ?? '').trim();
    if (_isCompositeChild(loc) && parent.isNotEmpty) {
      return '$parent - $leaf';
    }
    return leaf;
  }

  ({
    Set<String> allNameKeys,
    Set<String> parentKeys,
    Set<String> childCompositeKeys,
  }) _buildExistingKeysFromSnapshot(List<LocationModel> data) {
    final allNameKeys = <String>{};
    final parentKeys = <String>{};
    final childCompositeKeys = <String>{};

    for (final loc in data) {
      final name = loc.locationName;
      if (name.trim().isNotEmpty) {
        allNameKeys.add(_nameKey(name));
      }

      if (_isCompositeParent(loc)) {
        parentKeys.add(_nameKey(loc.locationName));
        continue;
      }

      if (_isCompositeChild(loc)) {
        final p = (loc.parent ?? '').trim();
        if (p.isNotEmpty) {
          childCompositeKeys.add(_childCompositeKey(p, loc.locationName));
        }
      }
    }

    return (
      allNameKeys: allNameKeys,
      parentKeys: parentKeys,
      childCompositeKeys: childCompositeKeys,
    );
  }

  Future<List<LocationModel>> _fetchAreaSnapshot(String area) {
    final trimmedArea = area.trim();
    if (trimmedArea.isEmpty) {
      return Future.value(const <LocationModel>[]);
    }

    final existing = _areaSnapshotInFlightByArea[trimmedArea];
    if (existing != null) return existing;

    final future = _repository
        .getLocationsOnce(trimmedArea)
        .then((data) => List<LocationModel>.of(data));

    _areaSnapshotInFlightByArea[trimmedArea] = future;

    return future.whenComplete(() {
      if (identical(_areaSnapshotInFlightByArea[trimmedArea], future)) {
        _areaSnapshotInFlightByArea.remove(trimmedArea);
      }
    });
  }

  int _totalCapacityForCache(List<LocationModel> data) {
    return data.fold<int>(0, (sum, loc) {
      if (_isCompositeParent(loc)) return sum;
      return sum + loc.capacity;
    });
  }

  Future<void> _writeCache({
    required String area,
    required List<LocationModel> data,
    required SharedPreferences prefs,
  }) async {
    final trimmedArea = area.trim();
    final jsonData = json.encode(data.map((e) => e.toCacheMap()).toList());
    final totalCapacity = _totalCapacityForCache(data);
    final locationSaved = await prefs.setString(
      _cacheKeyForArea(trimmedArea),
      jsonData,
    );
    final capacitySaved = await prefs.setInt(
      _capacityKeyForArea(trimmedArea),
      totalCapacity,
    );
    if (!locationSaved || !capacitySaved) {
      throw StateError('주차 구역 로컬 저장 실패');
    }
    await prefs.reload();
    if (prefs.getString(_cacheKeyForArea(trimmedArea)) != jsonData ||
        prefs.getInt(_capacityKeyForArea(trimmedArea)) != totalCapacity) {
      throw StateError('주차 구역 로컬 저장 검증 실패');
    }
  }

  Future<void> _syncFromRepository({
    required String area,
    required bool setLoading,
    required String reason,
    bool rethrowErrors = false,
  }) {
    final trimmedArea = area.trim();
    if (trimmedArea.isEmpty) {
      _resetLocationsStateForEmptyArea();
      return Future.value();
    }

    final existing = _repoSyncInFlightByArea[trimmedArea];
    if (existing != null) {
      if (setLoading && !_isLoading) {
        _isLoading = true;
        _safeNotify();
      }
      return existing;
    }

    final future = _syncFromRepositoryInternal(
      area: trimmedArea,
      setLoading: setLoading,
      reason: reason,
      rethrowErrors: rethrowErrors,
    );

    _repoSyncInFlightByArea[trimmedArea] = future;

    return future.whenComplete(() {
      if (identical(_repoSyncInFlightByArea[trimmedArea], future)) {
        _repoSyncInFlightByArea.remove(trimmedArea);
      }
    });
  }

  Future<void> _syncFromRepositoryInternal({
    required String area,
    required bool setLoading,
    required String reason,
    required bool rethrowErrors,
  }) async {
    final trimmedArea = area.trim();
    final int seq = ++_repoSyncSeq;

    if (setLoading) {
      _isLoading = true;
      _safeNotify();
    }

    try {
      final data = await _repository.getLocationsOnce(trimmedArea);

      if (_shouldDropRepoResult(seq: seq, requestedArea: trimmedArea)) return;

      _locations = data;
      _selectedLocationId = null;
      _previousArea = trimmedArea;

      final prefs = await SharedPreferences.getInstance();
      await _writeCache(area: trimmedArea, data: data, prefs: prefs);
    } catch (e) {
      debugPrint(
          '🔥 LocationState repo sync 실패(reason=$reason, area=$trimmedArea): $e');
      if (rethrowErrors) rethrow;
    } finally {
      if (_shouldDropRepoResult(seq: seq, requestedArea: trimmedArea)) return;
      _isLoading = false;
      _safeNotify();
    }
  }

  Future<void> _syncFromFirestoreAfterWrite(String area) async {
    await _syncFromRepository(
      area: area,
      setLoading: false,
      reason: 'afterWrite',
    );
  }

  Future<void> loadFromLocationCache() {
    final requestedArea = _areaState.currentArea.trim();

    if (requestedArea.isEmpty) {
      _resetLocationsStateForEmptyArea();
      return Future.value();
    }

    final existing = _cacheLoadInFlightByArea[requestedArea];
    if (existing != null) return existing;

    final future = _loadFromLocationCacheInternal(requestedArea: requestedArea);
    _cacheLoadInFlightByArea[requestedArea] = future;

    return future.whenComplete(() {
      if (identical(_cacheLoadInFlightByArea[requestedArea], future)) {
        _cacheLoadInFlightByArea.remove(requestedArea);
      }
    });
  }

  Future<void> _loadFromLocationCacheInternal({
    required String requestedArea,
  }) async {
    final int seq = ++_cacheLoadSeq;

    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cacheKeyForArea(requestedArea));

      if (cachedJson != null && cachedJson.trim().isNotEmpty) {
        final maps = await compute(_decodeCachedLocationsToMaps, cachedJson);

        if (_shouldDropCacheResult(seq: seq, requestedArea: requestedArea))
          return;

        _locations = maps.map((m) => LocationModel.fromCacheMap(m)).toList();
      } else {
        if (_shouldDropCacheResult(seq: seq, requestedArea: requestedArea))
          return;
        _locations = [];
      }
    } catch (e) {
      debugPrint('⚠️ 주차 구역 캐시 로드/디코딩 실패(area=$requestedArea): $e');
      if (_shouldDropCacheResult(seq: seq, requestedArea: requestedArea))
        return;
      _locations = [];
    }

    if (_shouldDropCacheResult(seq: seq, requestedArea: requestedArea)) return;

    _selectedLocationId = null;
    _previousArea = requestedArea;
    _isLoading = false;
    _safeNotify();
  }

  Future<void> manualLocationRefresh() async {
    final currentArea = _areaState.currentArea.trim();

    await _syncFromRepository(
      area: currentArea,
      setLoading: true,
      reason: 'manualRefresh',
    );
  }

  Future<void> clearCurrentAreaCache() async {
    final currentArea = _areaState.currentArea.trim();
    if (currentArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }

    ++_cacheLoadSeq;
    ++_repoSyncSeq;
    _cacheLoadInFlightByArea.remove(currentArea);
    _repoSyncInFlightByArea.remove(currentArea);

    final prefs = await SharedPreferences.getInstance();
    final locationKey = _cacheKeyForArea(currentArea);
    final capacityKey = _capacityKeyForArea(currentArea);
    await prefs.remove(locationKey);
    await prefs.remove(capacityKey);
    await prefs.reload();
    if (prefs.containsKey(locationKey) || prefs.containsKey(capacityKey)) {
      throw StateError('기존 주차 구역 로컬 데이터 삭제 검증 실패');
    }

    _locations = [];
    _selectedLocationId = null;
    _previousArea = currentArea;
    _isLoading = false;
    _safeNotify();
  }

  Future<void> manualLocationRefreshStrict() async {
    final currentArea = _areaState.currentArea.trim();
    if (currentArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }

    await _syncFromRepository(
      area: currentArea,
      setLoading: true,
      reason: 'operationalDataSync',
      rethrowErrors: true,
    );

    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey(_cacheKeyForArea(currentArea)) ||
        !prefs.containsKey(_capacityKeyForArea(currentArea))) {
      throw StateError('주차 구역 로컬 데이터 저장 결과가 없습니다.');
    }
  }

  void toggleLocationSelection(String id) {
    _selectedLocationId = (_selectedLocationId == id) ? null : id;
    _safeNotify();
  }

  void updatePlateCounts(Map<String, int> countsByDisplayName) {
    final cleaned = <String, int>{};
    for (final e in countsByDisplayName.entries) {
      final k = e.key.trim();
      if (k.isEmpty) continue;
      cleaned[k] = e.value;
    }
    _plateCountsByDisplayName = cleaned;

    final leafParents = <String, Set<String>>{};
    for (final loc in _locations) {
      if (!_isCompositeChild(loc)) continue;
      final p = (loc.parent ?? '').trim();
      if (p.isEmpty) continue;

      final leafK = _nameKey(loc.locationName);
      leafParents.putIfAbsent(leafK, () => <String>{}).add(_nameKey(p));
    }

    bool leafUnique(String leaf) =>
        (leafParents[_nameKey(leaf)]?.length ?? 0) <= 1;

    final childSumByParent = <String, int>{};
    for (final loc in _locations) {
      if (!_isCompositeChild(loc)) continue;

      final parentName = (loc.parent ?? '').trim();
      if (parentName.isEmpty) continue;

      final leaf = loc.locationName.trim();
      final fullKey = '$parentName - $leaf';

      final c =
          cleaned[fullKey] ?? (leafUnique(leaf) ? (cleaned[leaf] ?? 0) : 0);
      childSumByParent[parentName] = (childSumByParent[parentName] ?? 0) + c;
    }

    var changed = false;
    final next = <LocationModel>[];

    for (final loc in _locations) {
      final leaf = loc.locationName.trim();

      int nextCount;
      if (_isCompositeParent(loc)) {
        nextCount = childSumByParent[leaf] ?? cleaned[leaf] ?? 0;
      } else {
        final display = _displayNameForCounts(loc);
        nextCount =
            cleaned[display] ?? (leafUnique(leaf) ? (cleaned[leaf] ?? 0) : 0);
      }

      if (loc.plateCount != nextCount) {
        changed = true;
        next.add(loc.copyWith(plateCount: nextCount));
      } else {
        next.add(loc);
      }
    }

    if (changed) {
      _locations = next;
      _safeNotify();
    }
  }

  bool _validateParkingGridForParent(
    ParkingGridModel grid, {
    void Function(String)? onError,
  }) {
    if (grid.rows <= 0 || grid.cols <= 0) {
      onError?.call('⚠️ 그리드 크기가 올바르지 않습니다.');
      return false;
    }
    if (grid.cells.length != grid.rows * grid.cols) {
      onError?.call('⚠️ 그리드 데이터 길이가 올바르지 않습니다.');
      return false;
    }

    final areas = grid.parkingAreas;

    final rows = grid.rows;
    final cols = grid.cols;

    bool isAllowedShape(int h, int w) =>
        (h == 1 && w == 2) || (h == 2 && w == 1) || (h == 2 && w == 2);

    int idx(int r, int c) => r * cols + c;

    final used = <int>{};
    final ids = <String>{};

    for (final a in areas) {
      final id = a.id.trim();
      if (id.isEmpty) {
        onError?.call('⚠️ 주차면적 id가 비어있습니다.');
        return false;
      }
      if (!ids.add(id)) {
        onError?.call('⚠️ 주차면적 id가 중복됩니다: $id');
        return false;
      }

      final r0 = a.r0;
      final c0 = a.c0;
      final r1 = a.r1;
      final c1 = a.c1;

      if (r0 < 0 || c0 < 0 || r1 < 0 || c1 < 0) {
        onError?.call('⚠️ 주차면적 범위가 올바르지 않습니다: $id');
        return false;
      }
      if (r0 >= rows || r1 >= rows || c0 >= cols || c1 >= cols) {
        onError?.call('⚠️ 주차면적이 그리드 밖으로 나갔습니다: $id');
        return false;
      }

      final top = math.min(r0, r1);
      final bottom = math.max(r0, r1);
      final left = math.min(c0, c1);
      final right = math.max(c0, c1);

      final h = bottom - top + 1;
      final w = right - left + 1;

      if (!isAllowedShape(h, w)) {
        onError?.call(
          '⚠️ 주차면적 크기 제한: 1x2 / 2x1 / 2x2만 가능합니다. (id=$id, ${h}x$w)',
        );
        return false;
      }

      for (int r = top; r <= bottom; r++) {
        for (int c = left; c <= right; c++) {
          final p = idx(r, c);
          if (used.contains(p)) {
            onError?.call('⚠️ 주차면적이 서로 겹칩니다. (id=$id, cell=$r,$c)');
            return false;
          }
          if (grid.cells[p] != ParkingGridCellType.empty) {
            onError?.call(
              '⚠️ 주차면적은 빈칸(EMPTY) 위에만 설정할 수 있습니다. (id=$id, cell=$r,$c)',
            );
            return false;
          }
          used.add(p);
        }
      }
    }

    final towers = grid.towerRects;
    if (towers.isNotEmpty) {
      final towerUsed = <int>{};

      final gateUsed = <int>{};
      final gateRects = <GridRect>[...grid.entranceRects, ...grid.exitRects];
      for (final rawGate in gateRects) {
        final g = rawGate.normalized();
        for (int rr = g.r0; rr <= g.r1; rr++) {
          for (int cc = g.c0; cc <= g.c1; cc++) {
            final p = idx(rr, cc);
            if (p < 0 || p >= grid.cells.length) continue;
            gateUsed.add(p);
          }
        }
      }

      for (final raw in towers) {
        final r = raw.normalized();
        if (r.r0 < 0 || r.c0 < 0 || r.r1 < 0 || r.c1 < 0) {
          onError?.call('⚠️ 주차 타워 영역 범위가 올바르지 않습니다.');
          return false;
        }
        if (r.r0 >= rows || r.r1 >= rows || r.c0 >= cols || r.c1 >= cols) {
          onError?.call('⚠️ 주차 타워 영역이 그리드 밖으로 나갔습니다.');
          return false;
        }

        for (int rr = r.r0; rr <= r.r1; rr++) {
          for (int cc = r.c0; cc <= r.c1; cc++) {
            final p = idx(rr, cc);
            if (towerUsed.contains(p)) {
              onError?.call('⚠️ 주차 타워 영역이 서로 겹칩니다. (cell=$rr,$cc)');
              return false;
            }
            if (used.contains(p)) {
              onError?.call('⚠️ 주차 타워 영역이 주차면적과 겹칩니다. (cell=$rr,$cc)');
              return false;
            }
            if (gateUsed.contains(p)) {
              onError?.call('⚠️ 주차 타워 영역이 입구/출구 영역과 겹칩니다. (cell=$rr,$cc)');
              return false;
            }
            if (grid.cells[p] != ParkingGridCellType.empty) {
              onError
                  ?.call('⚠️ 주차 타워는 빈칸(EMPTY) 위에만 설정할 수 있습니다. (cell=$rr,$cc)');
              return false;
            }
            towerUsed.add(p);
          }
        }
      }
    }

    return true;
  }

  Future<bool> addCompositeParent(
    String parent,
    String area, {
    required ParkingGridModel parkingGrid,
    void Function(String)? onError,
  }) async {
    final cleanArea = area.trim();
    final cleanParent = _normalizeName(parent);
    final parentKey = _nameKey(cleanParent);

    if (cleanArea.isEmpty) {
      onError?.call('⚠️ 지역(area)이 비어 있어 부모 구역을 추가할 수 없습니다.');
      return false;
    }
    if (cleanParent.isEmpty) {
      onError?.call('⚠️ 부모(상위) 주차 구역명을 입력하세요.');
      return false;
    }
    if (!_validateParkingGridForParent(parkingGrid, onError: onError)) {
      return false;
    }

    try {
      final snapshot = await _fetchAreaSnapshot(cleanArea);
      final keys = _buildExistingKeysFromSnapshot(snapshot);

      if (keys.allNameKeys.contains(parentKey)) {
        onError?.call('⚠️ "$cleanArea" 지역에 이미 "$cleanParent" 이름이 존재합니다.');
        return false;
      }

      final parentModel = LocationModel(
        id: _parentDocId(parent: cleanParent, area: cleanArea),
        locationName: cleanParent,
        area: cleanArea,
        parent: null,
        type: 'composite_parent',
        capacity: 0,
        isSelected: false,
        plateCount: 0,
        parkingGrid: parkingGrid,
      );

      await _repository.addCompositeParent(parentModel);
      await _syncFromFirestoreAfterWrite(cleanArea);
      return true;
    } catch (e) {
      onError?.call('🚨 부모 구역 추가 실패: $e');
      return false;
    }
  }

  Future<bool> saveCompositeParentGrid({
    required String parent,
    required String area,
    required ParkingGridModel parkingGrid,
    void Function(String)? onError,
  }) async {
    final cleanArea = area.trim();
    final cleanParent = _normalizeName(parent);
    final parentKey = _nameKey(cleanParent);

    if (cleanArea.isEmpty) {
      onError?.call('⚠️ 지역(area)이 비어 있어 저장할 수 없습니다.');
      return false;
    }
    if (cleanParent.isEmpty) {
      onError?.call('⚠️ 부모(상위) 주차 구역명이 비어 있습니다.');
      return false;
    }
    if (!_validateParkingGridForParent(parkingGrid, onError: onError)) {
      return false;
    }

    try {
      final snapshot = await _fetchAreaSnapshot(cleanArea);
      final keys = _buildExistingKeysFromSnapshot(snapshot);
      final parentExists = keys.parentKeys.contains(parentKey);

      if (!parentExists && keys.allNameKeys.contains(parentKey)) {
        onError?.call('⚠️ "$cleanArea" 지역에 이미 "$cleanParent" 이름이 존재합니다.');
        return false;
      }

      final parentModel = LocationModel(
        id: _parentDocId(parent: cleanParent, area: cleanArea),
        locationName: cleanParent,
        area: cleanArea,
        parent: null,
        type: 'composite_parent',
        capacity: 0,
        isSelected: false,
        plateCount: 0,
        parkingGrid: parkingGrid,
      );

      final childrenToUpdate = _rebuildChildrenForParentGrid(
        snapshot: snapshot,
        area: cleanArea,
        parent: cleanParent,
        parentGrid: parkingGrid,
        onError: onError,
      );

      if (childrenToUpdate == null) return false;

      await _repository.saveCompositeParentWithChildren(
        parent: parentModel,
        children: childrenToUpdate,
      );
      await _syncFromFirestoreAfterWrite(cleanArea);
      return true;
    } catch (e) {
      onError?.call('🚨 부모 그리드 저장 실패: $e');
      return false;
    }
  }

  bool _parkingAreaFullyContainedInRect(ParkingArea a, GridRect rect) {
    final rr = rect.normalized();

    final top = math.min(a.r0, a.r1);
    final bottom = math.max(a.r0, a.r1);
    final left = math.min(a.c0, a.c1);
    final right = math.max(a.c0, a.c1);

    return top >= rr.r0 && left >= rr.c0 && bottom <= rr.r1 && right <= rr.c1;
  }

  List<String> _areaIdsForLocation(LocationModel loc) {
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

  List<String> _areaIdsContainedInRect({
    required ParkingGridModel parentGrid,
    required GridRect rect,
  }) {
    final rr = rect.normalized();
    final out = <String>[];
    final seen = <String>{};

    for (final area in parentGrid.parkingAreas) {
      final id = area.id.trim();
      if (id.isEmpty) continue;
      if (!_parkingAreaFullyContainedInRect(area, rr)) continue;
      if (seen.add(id)) out.add(id);
    }

    return out;
  }

  Map<String, int> _slotNumbersForLocation(LocationModel loc) {
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

  List<ChildSlot>? _buildChildSlotsForAreaIds({
    required ParkingGridModel parentGrid,
    required Iterable<String> areaIds,
    required Map<String, int> slotNumbersByAreaId,
    void Function(String)? onError,
  }) {
    final idSet = areaIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    if (idSet.isEmpty) return const <ChildSlot>[];

    final cleanNumbers = <String, int>{};
    slotNumbersByAreaId.forEach((rawId, rawNo) {
      final id = rawId.trim();
      if (id.isEmpty) return;
      if (rawNo <= 0) return;
      cleanNumbers[id] = rawNo;
    });

    final usedNos = <int>{};
    for (final id in idSet) {
      final no = cleanNumbers[id];
      if (no == null || no <= 0) {
        onError?.call('⚠️ 선택된 모든 주차면적에 슬롯 번호를 입력해야 합니다.');
        return null;
      }
      if (!usedNos.add(no)) {
        onError?.call('⚠️ 같은 자식 구역 안에서 슬롯 번호는 중복될 수 없습니다.');
        return null;
      }
    }

    final areas = parentGrid.parkingAreas
        .where((a) => idSet.contains(a.id.trim()))
        .toList()
      ..sort((a, b) {
        final ar0 = math.min(a.r0, a.r1);
        final br0 = math.min(b.r0, b.r1);
        final dr = ar0.compareTo(br0);
        if (dr != 0) return dr;

        final ac0 = math.min(a.c0, a.c1);
        final bc0 = math.min(b.c0, b.c1);
        final dc = ac0.compareTo(bc0);
        if (dc != 0) return dc;

        final dk = a.kind.index.compareTo(b.kind.index);
        if (dk != 0) return dk;

        return a.id.compareTo(b.id);
      });

    final out = <ChildSlot>[];
    for (final area in areas) {
      final id = area.id.trim();
      final no = cleanNumbers[id];
      if (no == null || no <= 0) {
        onError?.call('⚠️ 선택된 모든 주차면적에 슬롯 번호를 입력해야 합니다.');
        return null;
      }
      out.add(ChildSlot.fromParkingArea(no: no, area: area));
    }
    return out;
  }

  Set<String> _usedAreaIdsForParent({
    required List<LocationModel> snapshot,
    required String area,
    required String parent,
    String? excludeChildId,
  }) {
    final cleanArea = area.trim();
    final parentKey = _nameKey(parent);
    final used = <String>{};

    for (final loc in snapshot) {
      if (!_isCompositeChild(loc)) continue;
      if (loc.area.trim() != cleanArea) continue;
      if (excludeChildId != null && loc.id == excludeChildId) continue;

      final p = (loc.parent ?? '').trim();
      if (p.isEmpty || _nameKey(p) != parentKey) continue;

      used.addAll(_areaIdsForLocation(loc));
    }

    return used;
  }

  List<String>? _resolveSelectedAreaIds({
    required ParkingGridModel parentGrid,
    required GridRect rect,
    required Iterable<String> requestedAreaIds,
    required List<LocationModel> snapshot,
    required String area,
    required String parent,
    String? excludeChildId,
    void Function(String)? onError,
  }) {
    final requested = requestedAreaIds.map((e) => e.trim()).where((e) => e.isNotEmpty).toSet();
    final ids = requested.isNotEmpty
        ? requested
        : _areaIdsContainedInRect(parentGrid: parentGrid, rect: rect).toSet();

    if (ids.isEmpty) {
      onError?.call('⚠️ 자식 구역에 포함할 주차면적을 1개 이상 선택하세요.');
      return null;
    }

    final parentAreaIds = parentGrid.parkingAreas.map((a) => a.id.trim()).where((e) => e.isNotEmpty).toSet();
    final missing = ids.where((id) => !parentAreaIds.contains(id)).toList();
    if (missing.isNotEmpty) {
      onError?.call('⚠️ 부모 도면에 존재하지 않는 주차면적이 포함되어 있습니다: ${missing.take(3).join(', ')}');
      return null;
    }

    final byId = <String, ParkingArea>{};
    for (final a in parentGrid.parkingAreas) {
      byId[a.id.trim()] = a;
    }

    final outside = <String>[];
    final rr = rect.normalized();
    for (final id in ids) {
      final areaObj = byId[id];
      if (areaObj == null) continue;
      if (!_parkingAreaFullyContainedInRect(areaObj, rr)) outside.add(id);
    }
    if (outside.isNotEmpty) {
      onError?.call('⚠️ 선택한 주차면적 중 자식 사각형 범위를 벗어난 항목이 있습니다: ${outside.take(3).join(', ')}');
      return null;
    }

    final used = _usedAreaIdsForParent(
      snapshot: snapshot,
      area: area,
      parent: parent,
      excludeChildId: excludeChildId,
    );
    final conflicts = ids.where(used.contains).toList();
    if (conflicts.isNotEmpty) {
      onError?.call('⚠️ 이미 다른 자식 구역에 배정된 주차면적이 포함되어 있습니다.');
      return null;
    }

    final out = ids.toList()..sort();
    return out;
  }

  bool _rectInGrid(GridRect rect, ParkingGridModel grid) {
    final r = rect.normalized();
    if (r.r0 < 0 || r.c0 < 0) return false;
    if (r.r1 >= grid.rows || r.c1 >= grid.cols) return false;
    return true;
  }

  bool _isRegisteredTowerRect(GridRect rect, ParkingGridModel grid) {
    final r = rect.normalized();
    return grid.towerRects.map((e) => e.normalized()).any((e) => e == r);
  }

  List<LocationModel>? _rebuildChildrenForParentGrid({
    required List<LocationModel> snapshot,
    required String area,
    required String parent,
    required ParkingGridModel parentGrid,
    void Function(String)? onError,
  }) {
    final cleanArea = area.trim();
    final cleanParent = _normalizeName(parent);
    final parentKey = _nameKey(cleanParent);

    final existingAreaIds = parentGrid.parkingAreas
        .map((a) => a.id.trim())
        .where((e) => e.isNotEmpty)
        .toSet();

    final out = <LocationModel>[];

    for (final loc in snapshot) {
      if (!_isCompositeChild(loc)) continue;
      if (loc.area.trim() != cleanArea) continue;

      final rawParent = (loc.parent ?? '').trim();
      if (rawParent.isEmpty || _nameKey(rawParent) != parentKey) continue;

      final rect = loc.childRect;
      if (rect == null) {
        out.add(
          loc.copyWith(
            parent: cleanParent,
            area: cleanArea,
            type: 'composite_child',
            childSlotAreaIds: const <String>[],
            childSlots: const <ChildSlot>[],
          ),
        );
        continue;
      }

      final norm = rect.normalized();
      if (!_rectInGrid(norm, parentGrid)) {
        onError?.call(
          '⚠️ "$cleanParent - ${loc.locationName}" 자식 구역이 새 부모 그리드 범위를 벗어납니다.',
        );
        return null;
      }

      final isTower = loc.isTowerChild;
      if (isTower && !_isRegisteredTowerRect(norm, parentGrid)) {
        onError?.call(
          '⚠️ "$cleanParent - ${loc.locationName}" 주차 타워 자식 구역이 새 부모 타워 영역과 일치하지 않습니다.',
        );
        return null;
      }

      final previousIds = _areaIdsForLocation(loc);
      final nextIds = isTower
          ? const <String>[]
          : previousIds.isNotEmpty
              ? previousIds.where(existingAreaIds.contains).toList(growable: false)
              : _areaIdsContainedInRect(parentGrid: parentGrid, rect: norm);

      final slotNumbers = _slotNumbersForLocation(loc);
      final slots = isTower
          ? const <ChildSlot>[]
          : _buildChildSlotsForAreaIds(
              parentGrid: parentGrid,
              areaIds: nextIds,
              slotNumbersByAreaId: slotNumbers,
              onError: onError,
            );

      if (slots == null) return null;

      out.add(
        loc.copyWith(
          parent: cleanParent,
          area: cleanArea,
          type: 'composite_child',
          childRect: norm,
          childKind: isTower ? 'tower' : 'normal',
          capacity: isTower ? loc.capacity : slots.length,
          childSlotAreaIds: nextIds,
          childSlots: slots,
        ),
      );
    }

    return out;
  }

  Future<bool> refreshChildSlotsForCurrentArea({
    void Function(String)? onError,
  }) async {
    final cleanArea = _areaState.currentArea.trim();
    if (cleanArea.isEmpty) {
      onError?.call('⚠️ 현재 지역(area)이 비어 있어 슬롯을 재계산할 수 없습니다.');
      return false;
    }

    try {
      final snapshot = await _fetchAreaSnapshot(cleanArea);

      final parents = snapshot
          .where((loc) =>
              _isCompositeParent(loc) &&
              loc.area.trim() == cleanArea &&
              loc.parkingGrid != null)
          .toList();

      for (final parent in parents) {
        final grid = parent.parkingGrid;
        if (grid == null) continue;

        final rebuilt = _rebuildChildrenForParentGrid(
          snapshot: snapshot,
          area: cleanArea,
          parent: parent.locationName,
          parentGrid: grid,
          onError: onError,
        );

        if (rebuilt == null) return false;

        await _repository.saveCompositeParentWithChildren(
          parent: parent.copyWith(
            area: cleanArea,
            type: 'composite_parent',
            parent: null,
            parkingGrid: grid,
          ),
          children: rebuilt,
        );
      }

      await _syncFromFirestoreAfterWrite(cleanArea);
      return true;
    } catch (e) {
      onError?.call('🚨 자식 슬롯 재계산 실패: $e');
      return false;
    }
  }

  Future<bool> addCompositeChild({
    required String parent,
    required String child,
    required int capacity,
    required String area,
    required GridRect rect,
    List<String> childSlotAreaIds = const <String>[],
    Map<String, int> childSlotNumbersByAreaId = const <String, int>{},
    bool isTower = false,
    void Function(String)? onError,
  }) async {
    final cleanArea = area.trim();
    final cleanParent = _normalizeName(parent);
    final cleanChild = _normalizeName(child);

    if (cleanArea.isEmpty) {
      onError?.call('⚠️ 지역(area)이 비어 있어 자식 구역을 추가할 수 없습니다.');
      return false;
    }
    if (cleanParent.isEmpty) {
      onError?.call('⚠️ 부모(상위) 구역명을 선택/입력하세요.');
      return false;
    }
    if (cleanChild.isEmpty) {
      onError?.call('⚠️ 자식(하위) 구역명을 입력하세요.');
      return false;
    }
    if (capacity <= 0) {
      onError?.call('⚠️ 수용 대수(capacity)는 1 이상이어야 합니다.');
      return false;
    }
    if (_nameKey(cleanParent) == _nameKey(cleanChild)) {
      onError?.call('⚠️ 자식 "$cleanChild"는 부모 "$cleanParent"와 같을 수 없습니다.');
      return false;
    }

    try {
      final snapshot = await _fetchAreaSnapshot(cleanArea);

      final parentKey = _nameKey(cleanParent);
      final childKey = _childCompositeKey(cleanParent, cleanChild);

      LocationModel? parentDoc;
      for (final l in snapshot) {
        if (_isCompositeParent(l) &&
            l.area.trim() == cleanArea &&
            _nameKey(l.locationName) == parentKey) {
          parentDoc = l;
          break;
        }
      }

      if (parentDoc == null) {
        onError?.call('⚠️ "$cleanParent" 부모 구역이 존재하지 않습니다. 먼저 부모를 생성하세요.');
        return false;
      }

      final existingChildCompositeKeys = <String>{};
      for (final loc in snapshot) {
        if (!_isCompositeChild(loc)) continue;
        final p = (loc.parent ?? '').trim();
        if (p.isEmpty) continue;
        existingChildCompositeKeys.add(_childCompositeKey(p, loc.locationName));
      }

      if (existingChildCompositeKeys.contains(childKey)) {
        onError?.call('⚠️ "$cleanParent - $cleanChild" 자식 구역이 이미 존재합니다.');
        return false;
      }

      final parentGrid = parentDoc.parkingGrid;
      if (parentGrid == null) {
        onError?.call(
          '⚠️ "$cleanParent" 부모 구역에 parkingGrid가 없습니다. (부모 그리드 저장/마이그레이션 확인 필요)',
        );
        return false;
      }

      final norm = rect.normalized();
      if (!_rectInGrid(norm, parentGrid)) {
        onError?.call(
          '⚠️ 선택 영역이 부모 그리드 범위를 벗어납니다. '
          '(rows=${parentGrid.rows}, cols=${parentGrid.cols}, rect=$norm)',
        );
        return false;
      }

      if (isTower) {
        if (!_isRegisteredTowerRect(norm, parentGrid)) {
          onError?.call(
            '⚠️ 주차 타워 자식 구역은 부모에서 지정된 “주차 타워 영역” 중 하나를 선택해야 합니다. '
            '(선택 rect=$norm)',
          );
          return false;
        }
      }

      final selectedIds = isTower
          ? const <String>[]
          : _resolveSelectedAreaIds(
              parentGrid: parentGrid,
              rect: norm,
              requestedAreaIds: childSlotAreaIds,
              snapshot: snapshot,
              area: cleanArea,
              parent: cleanParent,
              onError: onError,
            );

      if (selectedIds == null) return false;

      final childDocId = _childDocId(
        parent: cleanParent,
        child: cleanChild,
        area: cleanArea,
      );

      final childSlots = isTower
          ? const <ChildSlot>[]
          : _buildChildSlotsForAreaIds(
              parentGrid: parentGrid,
              areaIds: selectedIds,
              slotNumbersByAreaId: childSlotNumbersByAreaId,
              onError: onError,
            );

      if (childSlots == null) return false;

      final effectiveCapacity = isTower ? capacity : childSlots.length;
      if (!isTower && effectiveCapacity <= 0) {
        onError?.call('⚠️ 자식 구역에 포함할 주차면적을 1개 이상 선택하세요.');
        return false;
      }

      final childModel = LocationModel(
        id: childDocId,
        locationName: cleanChild,
        area: cleanArea,
        parent: cleanParent,
        type: 'composite_child',
        capacity: effectiveCapacity,
        isSelected: false,
        plateCount: 0,
        parkingGrid: null,
        childRect: norm,
        childKind: isTower ? 'tower' : 'normal',
        childSlotAreaIds: selectedIds,
        childSlots: childSlots,
      );

      await _repository.addCompositeChild(childModel);
      await _syncFromFirestoreAfterWrite(cleanArea);
      return true;
    } catch (e) {
      onError?.call('🚨 자식 구역 추가 실패: $e');
      return false;
    }
  }

  Future<bool> saveCompositeChild({
    required String id,
    required String parent,
    required String child,
    required int capacity,
    required String area,
    required GridRect rect,
    List<String> childSlotAreaIds = const <String>[],
    Map<String, int> childSlotNumbersByAreaId = const <String, int>{},
    bool isTower = false,
    void Function(String)? onError,
  }) async {
    final cleanArea = area.trim();
    final cleanParent = _normalizeName(parent);
    final cleanChild = _normalizeName(child);

    if (id.trim().isEmpty) {
      onError?.call('⚠️ 자식 구역 id가 비어 있어 수정할 수 없습니다.');
      return false;
    }
    if (cleanArea.isEmpty) {
      onError?.call('⚠️ 지역(area)이 비어 있어 자식 구역을 수정할 수 없습니다.');
      return false;
    }
    if (cleanParent.isEmpty) {
      onError?.call('⚠️ 부모(상위) 구역명이 비어 있습니다.');
      return false;
    }
    if (cleanChild.isEmpty) {
      onError?.call('⚠️ 자식(하위) 구역명을 입력하세요.');
      return false;
    }
    if (capacity <= 0) {
      onError?.call('⚠️ 수용 대수(capacity)는 1 이상이어야 합니다.');
      return false;
    }
    if (_nameKey(cleanParent) == _nameKey(cleanChild)) {
      onError?.call('⚠️ 자식 "$cleanChild"는 부모 "$cleanParent"와 같을 수 없습니다.');
      return false;
    }

    try {
      final snapshot = await _fetchAreaSnapshot(cleanArea);

      LocationModel? targetChild;
      for (final l in snapshot) {
        if (l.id == id) {
          targetChild = l;
          break;
        }
      }
      if (targetChild == null) {
        onError?.call('⚠️ 수정할 자식 구역을 찾을 수 없습니다. (id=$id)');
        return false;
      }
      if (!_isCompositeChild(targetChild)) {
        onError?.call('⚠️ 자식(composite_child) 구역만 수정할 수 있습니다.');
        return false;
      }

      final existingParent = (targetChild.parent ?? '').trim();
      if (existingParent.isEmpty) {
        onError?.call('⚠️ 기존 자식 구역의 parent 정보가 비어 있습니다.');
        return false;
      }
      if (_nameKey(existingParent) != _nameKey(cleanParent)) {
        onError?.call(
            '⚠️ 부모 구역 변경은 현재 지원하지 않습니다. (기존="$existingParent", 요청="$cleanParent")');
        return false;
      }

      final parentKey = _nameKey(cleanParent);

      LocationModel? parentDoc;
      for (final l in snapshot) {
        if (_isCompositeParent(l) &&
            l.area.trim() == cleanArea &&
            _nameKey(l.locationName) == parentKey) {
          parentDoc = l;
          break;
        }
      }
      if (parentDoc == null) {
        onError?.call('⚠️ "$cleanParent" 부모 구역이 존재하지 않습니다. 먼저 부모를 생성하세요.');
        return false;
      }

      final targetCompositeKey = _childCompositeKey(cleanParent, cleanChild);
      for (final loc in snapshot) {
        if (!_isCompositeChild(loc)) continue;
        if (loc.id == id) continue;

        final p = (loc.parent ?? '').trim();
        if (p.isEmpty) continue;
        if (_nameKey(p) != parentKey) continue;

        final ck = _childCompositeKey(p, loc.locationName);
        if (ck == targetCompositeKey) {
          onError?.call('⚠️ "$cleanParent - $cleanChild" 자식 구역이 이미 존재합니다.');
          return false;
        }
      }

      final parentGrid = parentDoc.parkingGrid;
      if (parentGrid == null) {
        onError?.call(
          '⚠️ "$cleanParent" 부모 구역에 parkingGrid가 없습니다. (부모 그리드 저장/마이그레이션 확인 필요)',
        );
        return false;
      }

      final norm = rect.normalized();
      if (!_rectInGrid(norm, parentGrid)) {
        onError?.call(
          '⚠️ 선택 영역이 부모 그리드 범위를 벗어납니다. '
          '(rows=${parentGrid.rows}, cols=${parentGrid.cols}, rect=$norm)',
        );
        return false;
      }

      if (isTower) {
        if (!_isRegisteredTowerRect(norm, parentGrid)) {
          onError?.call(
            '⚠️ 주차 타워 자식 구역은 부모에서 지정된 “주차 타워 영역” 중 하나를 선택해야 합니다. '
            '(선택 rect=$norm)',
          );
          return false;
        }
      }

      final selectedIds = isTower
          ? const <String>[]
          : _resolveSelectedAreaIds(
              parentGrid: parentGrid,
              rect: norm,
              requestedAreaIds: childSlotAreaIds,
              snapshot: snapshot,
              area: cleanArea,
              parent: cleanParent,
              excludeChildId: id,
              onError: onError,
            );

      if (selectedIds == null) return false;

      final childSlots = isTower
          ? const <ChildSlot>[]
          : _buildChildSlotsForAreaIds(
              parentGrid: parentGrid,
              areaIds: selectedIds,
              slotNumbersByAreaId: childSlotNumbersByAreaId,
              onError: onError,
            );

      if (childSlots == null) return false;

      final effectiveCapacity = isTower ? capacity : childSlots.length;
      if (!isTower && effectiveCapacity <= 0) {
        onError?.call('⚠️ 자식 구역에 포함할 주차면적을 1개 이상 선택하세요.');
        return false;
      }

      final updated = targetChild.copyWith(
        locationName: cleanChild,
        capacity: effectiveCapacity,
        childRect: norm,
        childKind: isTower ? 'tower' : 'normal',
        childSlotAreaIds: selectedIds,
        childSlots: childSlots,
        type: 'composite_child',
        parent: cleanParent,
        area: cleanArea,
      );

      await _repository.addCompositeChild(updated);
      await _syncFromFirestoreAfterWrite(cleanArea);
      return true;
    } catch (e) {
      onError?.call('🚨 자식 구역 수정 실패: $e');
      return false;
    }
  }

  Future<bool> addPlainTextLocation({
    required String name,
    required int capacity,
    required String area,
    void Function(String)? onError,
  }) async {
    final cleanArea = area.trim();
    final cleanName = _normalizeName(name);

    if (cleanArea.isEmpty) {
      onError?.call('⚠️ 지역(area)이 비어 있어 텍스트 구역을 저장할 수 없습니다.');
      return false;
    }
    if (cleanName.isEmpty) {
      onError?.call('⚠️ 구역명을 입력하세요.');
      return false;
    }
    if (capacity < 0) {
      onError?.call('⚠️ 수용 대수(capacity)는 0 이상이어야 합니다.');
      return false;
    }

    try {
      final snapshot = await _fetchAreaSnapshot(cleanArea);
      final keys = _buildExistingKeysFromSnapshot(snapshot);

      if (keys.allNameKeys.contains(_nameKey(cleanName))) {
        onError?.call('⚠️ "$cleanName" 구역이 이미 존재합니다.');
        return false;
      }

      final model = LocationModel(
        id: _plainTextDocId(name: cleanName, area: cleanArea),
        area: cleanArea,
        capacity: capacity,
        isSelected: false,
        locationName: cleanName,
        type: 'single',
        plateCount: 0,
      );

      await _repository.addPlainTextLocation(model);
      await _syncFromFirestoreAfterWrite(cleanArea);
      return true;
    } catch (e) {
      onError?.call('🚨 텍스트 구역 추가 실패: $e');
      return false;
    }
  }

  Future<bool> savePlainTextLocation({
    required String id,
    required String name,
    required int capacity,
    required String area,
    void Function(String)? onError,
  }) async {
    final cleanArea = area.trim();
    final cleanName = _normalizeName(name);

    if (id.trim().isEmpty) {
      onError?.call('⚠️ 텍스트 구역 id가 비어 있어 수정할 수 없습니다.');
      return false;
    }
    if (cleanArea.isEmpty) {
      onError?.call('⚠️ 지역(area)이 비어 있어 텍스트 구역을 수정할 수 없습니다.');
      return false;
    }
    if (cleanName.isEmpty) {
      onError?.call('⚠️ 구역명을 입력하세요.');
      return false;
    }
    if (capacity < 0) {
      onError?.call('⚠️ 수용 대수(capacity)는 0 이상이어야 합니다.');
      return false;
    }

    try {
      final snapshot = await _fetchAreaSnapshot(cleanArea);

      LocationModel? target;
      for (final l in snapshot) {
        if (l.id == id) {
          target = l;
          break;
        }
      }
      if (target == null) {
        onError?.call('⚠️ 수정할 텍스트 구역을 찾을 수 없습니다. (id=$id)');
        return false;
      }
      if (_isCompositeParent(target) || _isCompositeChild(target)) {
        onError?.call('⚠️ 텍스트형/단일 구역만 수정할 수 있습니다.');
        return false;
      }

      final targetKey = _nameKey(cleanName);
      for (final loc in snapshot) {
        if (loc.id == id) continue;
        if (_nameKey(loc.locationName) == targetKey) {
          onError?.call('⚠️ "$cleanName" 구역이 이미 존재합니다.');
          return false;
        }
      }

      final updated = target.copyWith(
        locationName: cleanName,
        capacity: capacity,
        area: cleanArea,
        type: 'single',
        parent: null,
        parkingGrid: null,
        childRect: null,
        childKind: null,
        childSlots: const <ChildSlot>[],
      );

      await _repository.addPlainTextLocation(updated);
      await _syncFromFirestoreAfterWrite(cleanArea);
      return true;
    } catch (e) {
      onError?.call('🚨 텍스트 구역 수정 실패: $e');
      return false;
    }
  }

  Future<bool> deleteLocations(
    List<String> ids, {
    void Function(String)? onError,
  }) async {
    if (ids.isEmpty) return true;

    try {
      final currentArea = _areaState.currentArea.trim();
      final latest = currentArea.isNotEmpty
          ? await _fetchAreaSnapshot(currentArea)
          : List<LocationModel>.of(_locations);

      final byId = <String, LocationModel>{
        for (final loc in latest) loc.id: loc,
      };

      final toDelete = <String>{...ids};

      for (final id in ids) {
        final loc = byId[id];
        if (loc == null) continue;

        if (_isCompositeParent(loc)) {
          final parentName = loc.locationName.trim();
          final area = loc.area.trim();

          for (final child in latest.where(
            (l) =>
                _isCompositeChild(l) &&
                l.area.trim() == area &&
                (l.parent ?? '').trim() == parentName,
          )) {
            toDelete.add(child.id);
          }
        }
      }

      final parentsToCheck = <({String area, String parentName})>{};

      for (final id in ids) {
        final loc = byId[id];
        if (loc == null) continue;
        if (_isCompositeChild(loc)) {
          final parentName = (loc.parent ?? '').trim();
          final area = loc.area.trim();
          if (parentName.isNotEmpty && area.isNotEmpty) {
            parentsToCheck.add((area: area, parentName: parentName));
          }
        }
      }

      for (final key in parentsToCheck) {
        final childIds = latest
            .where((l) =>
                _isCompositeChild(l) &&
                l.area.trim() == key.area &&
                (l.parent ?? '').trim() == key.parentName)
            .map((l) => l.id)
            .toList();

        if (childIds.isEmpty) continue;

        final willDeleteAllChildren = childIds.every(toDelete.contains);
        if (willDeleteAllChildren) {
          LocationModel? parentDoc;
          for (final l in latest) {
            if (_isCompositeParent(l) &&
                l.area.trim() == key.area &&
                _nameKey(l.locationName) == _nameKey(key.parentName)) {
              parentDoc = l;
              break;
            }
          }

          if (parentDoc != null) {
            toDelete.add(parentDoc.id);
          } else {
            toDelete.add(_parentDocId(parent: key.parentName, area: key.area));
          }
        }
      }

      if (currentArea.isEmpty) {
        _locations = _locations.where((l) => !toDelete.contains(l.id)).toList();
        _selectedLocationId = null;
        _safeNotify();
        return true;
      }

      await _repository.deleteLocations(
        area: currentArea,
        ids: toDelete.toList(),
        parentGridUpdates: const [],
      );

      await _syncFromFirestoreAfterWrite(currentArea);
      return true;
    } catch (e) {
      onError?.call('🚨 주차 구역 삭제 실패: $e');
      return false;
    }
  }
}
