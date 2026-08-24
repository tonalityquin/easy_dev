import 'package:flutter/foundation.dart';

import '../../../shared/operational_cache/domain/repositories/operational_local_repository.dart';
import '../../dev/application/area_state.dart';
import '../domain/models/sector_model.dart';
import '../domain/repositories/sector_repository.dart';

class SectorState extends ChangeNotifier {
  SectorState(this._repository, this._localRepository, this._areaState) {
    _previousArea = _areaState.currentArea.trim();
    _areaState.addListener(_handleAreaChanged);
    loadFromSectorCache();
  }

  final SectorRepository _repository;
  final OperationalLocalRepository _localRepository;
  final AreaState _areaState;

  List<SectorModel> _sectors = <SectorModel>[];
  String? _selectedSectorId;
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isRefreshing = false;
  String _previousArea = '';
  int _dataToken = 0;
  Future<void>? _pendingCacheLoad;

  List<SectorModel> get sectors => List<SectorModel>.unmodifiable(_sectors);

  static String cacheKeyForArea(String area) {
    return 'sqlite:operational_sectors:${area.trim()}';
  }

  String? get selectedSectorId => _selectedSectorId;
  bool get isLoading => _isLoading;
  bool get isSaving => _isSaving;
  bool get isRefreshing => _isRefreshing;
  bool get isBusy => _isLoading || _isSaving || _isRefreshing;

  SectorModel? get selectedSector {
    final id = _selectedSectorId;
    if (id == null) return null;
    for (final sector in _sectors) {
      if (sector.id == id) return sector;
    }
    return null;
  }

  void _handleAreaChanged() {
    final currentArea = _areaState.currentArea.trim();
    if (currentArea == _previousArea) return;
    _previousArea = currentArea;
    loadFromSectorCache();
  }

  Future<void> waitUntilReady() async {
    final wait = Stopwatch()..start();
    var generation = 0;
    while (true) {
      final pending = _pendingCacheLoad;
      if (pending == null) {
        wait.stop();
        debugPrint(
          '[SectorState] waitUntilReady complete elapsedMs=${wait.elapsedMilliseconds} generation=$generation loading=$_isLoading saving=$_isSaving refreshing=$_isRefreshing area=${_areaState.currentArea.trim()} count=${_sectors.length}',
        );
        return;
      }
      generation += 1;
      debugPrint(
        '[SectorState] waitUntilReady await generation=$generation area=${_areaState.currentArea.trim()} loading=$_isLoading saving=$_isSaving refreshing=$_isRefreshing',
      );
      await pending;
      if (identical(_pendingCacheLoad, pending)) {
        wait.stop();
        debugPrint(
          '[SectorState] waitUntilReady complete elapsedMs=${wait.elapsedMilliseconds} generation=$generation loading=$_isLoading saving=$_isSaving refreshing=$_isRefreshing area=${_areaState.currentArea.trim()} count=${_sectors.length}',
        );
        return;
      }
      debugPrint(
        '[SectorState] waitUntilReady local future changed generation=$generation area=${_areaState.currentArea.trim()}',
      );
    }
  }

  Future<void> loadFromSectorCache() {
    final future = _loadFromSectorCache();
    _pendingCacheLoad = future;
    return future.whenComplete(() {
      if (identical(_pendingCacheLoad, future)) {
        _pendingCacheLoad = null;
      }
    });
  }

  Future<void> _loadFromSectorCache() async {
    final requestedArea = _areaState.currentArea.trim();
    final token = ++_dataToken;
    _isLoading = true;
    _selectedSectorId = null;
    notifyListeners();

    if (requestedArea.isEmpty) {
      _sectors = <SectorModel>[];
      _isLoading = false;
      notifyListeners();
      debugPrint('[SectorState] 현재 지역이 없어 SQLite 데이터를 비웠습니다.');
      return;
    }

    try {
      final stored = await _localRepository.readSectors(requestedArea);
      _validateSectorModels(stored, requestedArea);
      if (token != _dataToken || _areaState.currentArea.trim() != requestedArea) {
        return;
      }
      _sectors = List<SectorModel>.from(stored);
      _sortSectors();
      _previousArea = requestedArea;
      debugPrint(
        '[SectorState] SQLite 로드 완료: area=$requestedArea count=${_sectors.length}',
      );
    } catch (error, stackTrace) {
      _sectors = <SectorModel>[];
      debugPrint('[SectorState] SQLite 로드 실패: area=$requestedArea error=$error');
      debugPrint('[SectorState] stackTrace=$stackTrace');
    } finally {
      if (token == _dataToken && _areaState.currentArea.trim() == requestedArea) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> manualSectorRefresh() async {
    await _refreshSectors(rethrowErrors: false);
  }

  Future<int> manualSectorRefreshStrict() {
    return manualSectorRefreshStrictForArea(_areaState.currentArea.trim());
  }

  Future<int> manualSectorRefreshStrictForArea(String area) async {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    if (_isRefreshing) {
      throw StateError('이미 섹터 새로고침이 진행 중입니다.');
    }
    if (_areaState.currentArea.trim() != normalizedArea) {
      throw StateError('섹터 동기화 시작 전에 현재 지역이 변경되었습니다.');
    }

    final token = ++_dataToken;
    _isRefreshing = true;
    _isLoading = true;
    notifyListeners();
    try {
      final result = await _repository.getSectors(normalizedArea);
      if (token != _dataToken ||
          _areaState.currentArea.trim() != normalizedArea) {
        throw StateError('섹터 동기화 중 현재 지역이 변경되었습니다.');
      }

      final sectors = List<SectorModel>.from(result)
        ..sort((a, b) {
          final normalizedCompare =
              a.normalizedName.compareTo(b.normalizedName);
          if (normalizedCompare != 0) return normalizedCompare;
          return a.name.compareTo(b.name);
        });
      _validateSectorModels(sectors, normalizedArea);
      await _localRepository.replaceSectors(
        area: normalizedArea,
        sectors: sectors,
      );
      if (_areaState.currentArea.trim() != normalizedArea) {
        throw StateError('섹터 저장 중 현재 지역이 변경되었습니다.');
      }

      if (!await _localRepository.hasSectorsSnapshot(normalizedArea)) {
        throw StateError('섹터 SQLite 저장 결과가 없습니다.');
      }
      final stored = await _localRepository.readSectors(normalizedArea);
      _validateSectorModels(stored, normalizedArea);
      _ensureStoredMatchesModels(stored, sectors, normalizedArea);
      final count = await _localRepository.countSectors(normalizedArea);
      if (count != stored.length) {
        throw StateError(
          '섹터 SQLite 저장 개수가 일치하지 않습니다: query=$count models=${stored.length}',
        );
      }

      _sectors = sectors;
      _selectedSectorId = null;
      _previousArea = normalizedArea;
      debugPrint(
        '[SectorState] 고정 지역 SQLite 다운로드 무결성 검증 완료: area=$normalizedArea count=$count checks=fields,area,duplicateId,duplicateName,date,state',
      );
      return count;
    } catch (error, stackTrace) {
      debugPrint(
        '[SectorState] 고정 지역 Firestore 새로고침 실패: area=$normalizedArea error=$error',
      );
      debugPrint('[SectorState] stackTrace=$stackTrace');
      Error.throwWithStackTrace(error, stackTrace);
    } finally {
      _isRefreshing = false;
      if (token == _dataToken &&
          _areaState.currentArea.trim() == normalizedArea) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _refreshSectors({required bool rethrowErrors}) async {
    if (_isRefreshing) {
      debugPrint('[SectorState] 이미 새로고침이 진행 중입니다.');
      if (rethrowErrors) {
        throw StateError('이미 섹터 새로고침이 진행 중입니다.');
      }
      return;
    }

    final requestedArea = _areaState.currentArea.trim();
    if (requestedArea.isEmpty) {
      if (rethrowErrors) {
        throw StateError('현재 지역 정보가 없습니다.');
      }
      return;
    }

    final token = ++_dataToken;
    _isRefreshing = true;
    _isLoading = true;
    notifyListeners();
    debugPrint('[SectorState] Firestore 새로고침 시작: area=$requestedArea');

    try {
      final result = await _repository.getSectors(requestedArea);
      if (token != _dataToken || _areaState.currentArea.trim() != requestedArea) {
        throw StateError('섹터 동기화 중 현재 지역이 변경되었습니다.');
      }
      _sectors = List<SectorModel>.from(result);
      _validateSectorModels(_sectors, requestedArea);
      _selectedSectorId = null;
      _sortSectors();
      await _saveCacheForArea(requestedArea);
      debugPrint(
        '[SectorState] Firestore 새로고침 완료: area=$requestedArea count=${_sectors.length}',
      );
    } catch (error, stackTrace) {
      debugPrint('[SectorState] Firestore 새로고침 실패: area=$requestedArea error=$error');
      debugPrint('[SectorState] stackTrace=$stackTrace');
      if (rethrowErrors) {
        Error.throwWithStackTrace(error, stackTrace);
      }
    } finally {
      _isRefreshing = false;
      if (token == _dataToken && _areaState.currentArea.trim() == requestedArea) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<SectorModel> createSector(String name) async {
    if (_isSaving || _isRefreshing || _isLoading) {
      throw StateError('다른 섹터 작업이 진행 중입니다.');
    }
    final area = _requireCurrentArea();
    final sectorName = _requireName(name);
    _ensureLocalUnique(sectorName);
    ++_dataToken;
    _isSaving = true;
    notifyListeners();
    try {
      final created = await _repository.addSector(area: area, name: sectorName);
      _ensureAreaUnchanged(area);
      _sectors = <SectorModel>[..._sectors, created];
      _selectedSectorId = created.id;
      _sortSectors();
      try {
        await _saveCacheForArea(area);
      } catch (error, stackTrace) {
        debugPrint('[SectorState] 등록 후 SQLite 저장 실패: $error');
        debugPrint('[SectorState] stackTrace=$stackTrace');
      }
      notifyListeners();
      debugPrint('[SectorState] 등록 완료: id=${created.id} area=$area name=${created.name}');
      return created;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<SectorModel> updateSector({
    required String id,
    required String name,
  }) async {
    if (_isSaving || _isRefreshing || _isLoading) {
      throw StateError('다른 섹터 작업이 진행 중입니다.');
    }
    final area = _requireCurrentArea();
    final normalizedId = id.trim();
    final sectorName = _requireName(name);
    if (normalizedId.isEmpty) {
      throw const SectorNotFoundException();
    }
    _ensureLocalUnique(sectorName, excludedId: normalizedId);
    ++_dataToken;
    _isSaving = true;
    notifyListeners();
    try {
      final updated = await _repository.updateSector(
        id: normalizedId,
        area: area,
        name: sectorName,
      );
      _ensureAreaUnchanged(area);
      final index = _sectors.indexWhere((sector) => sector.id == normalizedId);
      if (index < 0) {
        _sectors = <SectorModel>[..._sectors, updated];
      } else {
        _sectors = List<SectorModel>.from(_sectors)..[index] = updated;
      }
      _selectedSectorId = updated.id;
      _sortSectors();
      try {
        await _saveCacheForArea(area);
      } catch (error, stackTrace) {
        debugPrint('[SectorState] 수정 후 SQLite 저장 실패: $error');
        debugPrint('[SectorState] stackTrace=$stackTrace');
      }
      notifyListeners();
      debugPrint('[SectorState] 수정 완료: id=${updated.id} area=$area name=${updated.name}');
      return updated;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> deleteSector(String id) async {
    if (_isSaving || _isRefreshing || _isLoading) {
      throw StateError('다른 섹터 작업이 진행 중입니다.');
    }
    final area = _requireCurrentArea();
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) {
      throw const SectorNotFoundException();
    }
    ++_dataToken;
    _isSaving = true;
    notifyListeners();
    try {
      await _repository.deleteSector(id: normalizedId, area: area);
      _ensureAreaUnchanged(area);
      _sectors = _sectors.where((sector) => sector.id != normalizedId).toList(growable: true);
      if (_selectedSectorId == normalizedId) {
        _selectedSectorId = null;
      }
      try {
        await _saveCacheForArea(area);
      } catch (error, stackTrace) {
        debugPrint('[SectorState] 삭제 후 SQLite 저장 실패: $error');
        debugPrint('[SectorState] stackTrace=$stackTrace');
      }
      notifyListeners();
      debugPrint('[SectorState] 삭제 완료: id=$normalizedId area=$area');
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> clearCurrentAreaCache() {
    return clearAreaCache(_areaState.currentArea.trim());
  }

  Future<void> clearAreaCache(String area) async {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    final affectsCurrentArea =
        _areaState.currentArea.trim() == normalizedArea;
    if (affectsCurrentArea) {
      ++_dataToken;
    }
    await _localRepository.clearSectors(normalizedArea);
    if (await _localRepository.countSectors(normalizedArea) != 0 ||
        await _localRepository.hasSectorsSnapshot(normalizedArea)) {
      throw StateError('기존 섹터 SQLite 데이터 삭제 검증 실패');
    }
    if (affectsCurrentArea &&
        _areaState.currentArea.trim() == normalizedArea) {
      _sectors = <SectorModel>[];
      _selectedSectorId = null;
      _previousArea = normalizedArea;
      _isLoading = false;
      notifyListeners();
    }
    debugPrint('[SectorState] 지역 SQLite 삭제 완료: area=$normalizedArea');
  }

  void toggleSectorSelection(String id) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return;
    _selectedSectorId = _selectedSectorId == normalizedId ? null : normalizedId;
    notifyListeners();
  }

  void clearSelection() {
    if (_selectedSectorId == null) return;
    _selectedSectorId = null;
    notifyListeners();
  }

  Future<void> _saveCacheForArea(String area) async {
    final normalizedArea = area.trim();
    final source = List<SectorModel>.from(_sectors);
    _validateSectorModels(source, normalizedArea);
    await _localRepository.replaceSectors(area: normalizedArea, sectors: source);
    if (!await _localRepository.hasSectorsSnapshot(normalizedArea)) {
      throw StateError('섹터 SQLite 저장 결과가 없습니다.');
    }
    final stored = await _localRepository.readSectors(normalizedArea);
    _validateSectorModels(stored, normalizedArea);
    _ensureStoredMatchesModels(stored, source, normalizedArea);
    debugPrint(
      '[SectorState] SQLite 저장 무결성 검증 완료: area=$normalizedArea count=${stored.length}',
    );
  }

  static void _validateSectorModels(List<SectorModel> sectors, String area) {
    if (area.isEmpty) {
      throw StateError('섹터 SQLite 저장 지역이 비어 있습니다.');
    }
    final ids = <String>{};
    final normalizedNames = <String>{};
    for (var index = 0; index < sectors.length; index += 1) {
      final sector = sectors[index];
      final id = sector.id.trim();
      final sectorArea = sector.area.trim();
      final name = sector.name.trim();
      final normalizedName = sector.normalizedName.trim();
      final expectedNormalizedName = normalizeSectorName(name);
      if (id.isEmpty || id != sector.id || id.contains('/')) {
        throw StateError('SectorState $index번 항목의 문서 ID가 올바르지 않습니다.');
      }
      if (sectorArea != area || sectorArea != sector.area) {
        throw StateError(
          'SectorState $index번 항목의 지역이 현재 지역과 다릅니다: expected=$area actual=$sectorArea',
        );
      }
      if (name.isEmpty || name != sector.name || name.contains('/')) {
        throw StateError('SectorState $index번 항목의 섹터명이 올바르지 않습니다.');
      }
      if (normalizedName.isEmpty ||
          normalizedName != sector.normalizedName ||
          normalizedName != expectedNormalizedName) {
        throw StateError('SectorState $index번 항목의 정규화명이 올바르지 않습니다.');
      }
      if (!ids.add(id)) {
        throw StateError('SectorState에 중복 문서 ID가 있습니다: $id');
      }
      if (!normalizedNames.add(normalizedName)) {
        throw StateError('SectorState에 중복 섹터명이 있습니다: $name');
      }
    }
  }

  static void _ensureStoredMatchesModels(
    List<SectorModel> stored,
    List<SectorModel> expected,
    String area,
  ) {
    _validateSectorModels(expected, area);
    if (stored.length != expected.length) {
      throw StateError(
        '섹터 SQLite 저장 개수가 일치하지 않습니다: state=${expected.length} sqlite=${stored.length}',
      );
    }
    final storedById = <String, SectorModel>{
      for (final sector in stored) sector.id: sector,
    };
    for (final sector in expected) {
      final local = storedById[sector.id];
      if (local == null) {
        throw StateError('섹터 SQLite에 문서가 없습니다: ${sector.id}');
      }
      if (local.area != sector.area ||
          local.name != sector.name ||
          local.normalizedName != sector.normalizedName ||
          local.createdAt?.toIso8601String() != sector.createdAt?.toIso8601String() ||
          local.updatedAt?.toIso8601String() != sector.updatedAt?.toIso8601String()) {
        throw StateError('섹터 SQLite와 SectorState 값이 다릅니다: ${sector.id}');
      }
    }
  }

  void _ensureLocalUnique(String name, {String? excludedId}) {
    final normalized = normalizeSectorName(name);
    for (final sector in _sectors) {
      if (sector.id == excludedId) continue;
      final comparable = normalizeSectorName(
        sector.normalizedName.isEmpty ? sector.name : sector.normalizedName,
      );
      if (comparable == normalized) {
        throw SectorDuplicateNameException(sector.name);
      }
    }
  }

  String _requireCurrentArea() {
    final area = _areaState.currentArea.trim();
    if (area.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    return area;
  }

  String _requireName(String value) {
    final name = value.trim();
    if (name.isEmpty) {
      throw ArgumentError('섹터명을 입력해야 합니다.');
    }
    return name;
  }

  void _ensureAreaUnchanged(String area) {
    if (_areaState.currentArea.trim() != area) {
      throw StateError('섹터 작업 중 현재 지역이 변경되었습니다.');
    }
  }

  void _sortSectors() {
    _sectors.sort((a, b) {
      final normalizedCompare = a.normalizedName.compareTo(b.normalizedName);
      if (normalizedCompare != 0) return normalizedCompare;
      return a.name.compareTo(b.name);
    });
  }

  @override
  void dispose() {
    _areaState.removeListener(_handleAreaChanged);
    super.dispose();
  }
}
