import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../dev/application/area_state.dart';
import '../domain/models/sector_model.dart';
import '../domain/repositories/sector_repository.dart';

class SectorCacheIntegrityReport {
  const SectorCacheIntegrityReport({
    required this.area,
    required this.key,
    required this.sectors,
  });

  final String area;
  final String key;
  final List<SectorModel> sectors;

  int get count => sectors.length;
}

class SectorState extends ChangeNotifier {
  SectorState(this._repository, this._areaState) {
    _previousArea = _areaState.currentArea.trim();
    _areaState.addListener(_handleAreaChanged);
    loadFromSectorCache();
  }

  final SectorRepository _repository;
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

  static String cacheKeyForArea(String area) {
    final normalizedArea = area.trim();
    return 'cached_sectors_$normalizedArea';
  }

  static SectorCacheIntegrityReport? cachedIntegrityOf(
    SharedPreferences preferences,
    String area, {
    bool rethrowErrors = false,
  }) {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) return null;
    final key = cacheKeyForArea(normalizedArea);
    final encoded = preferences.getString(key);
    if (encoded == null || encoded.trim().isEmpty) return null;

    try {
      return _decodeAndValidateCache(
        encoded: encoded,
        area: normalizedArea,
        key: key,
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SectorState] 로컬 캐시 무결성 확인 실패: '
        'area=$normalizedArea, key=$key, error=$error',
      );
      debugPrint('[SectorState] stackTrace=$stackTrace');
      if (rethrowErrors) rethrow;
      return null;
    }
  }

  static int? cachedCountOf(
    SharedPreferences preferences,
    String area, {
    bool rethrowErrors = false,
  }) {
    return cachedIntegrityOf(
      preferences,
      area,
      rethrowErrors: rethrowErrors,
    )?.count;
  }

  String _cacheKey(String area) => cacheKeyForArea(area);

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
          '[SectorState] waitUntilReady complete '
          'elapsedMs=${wait.elapsedMilliseconds} generation=$generation '
          'loading=$_isLoading saving=$_isSaving refreshing=$_isRefreshing '
          'area=${_areaState.currentArea.trim()} count=${_sectors.length}',
        );
        return;
      }
      generation += 1;
      debugPrint(
        '[SectorState] waitUntilReady await '
        'generation=$generation area=${_areaState.currentArea.trim()} '
        'loading=$_isLoading saving=$_isSaving refreshing=$_isRefreshing',
      );
      await pending;
      if (identical(_pendingCacheLoad, pending)) {
        wait.stop();
        debugPrint(
          '[SectorState] waitUntilReady complete '
          'elapsedMs=${wait.elapsedMilliseconds} generation=$generation '
          'loading=$_isLoading saving=$_isSaving refreshing=$_isRefreshing '
          'area=${_areaState.currentArea.trim()} count=${_sectors.length}',
        );
        return;
      }
      debugPrint(
        '[SectorState] waitUntilReady cache future changed '
        'generation=$generation area=${_areaState.currentArea.trim()}',
      );
    }
  }

  Future<void> loadFromSectorCache() {
    final future = _loadFromSectorCache();
    _pendingCacheLoad = future;
    return future;
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
      debugPrint('[SectorState] 현재 지역이 없어 캐시를 비웠습니다.');
      return;
    }

    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.reload();
      final report = cachedIntegrityOf(
        preferences,
        requestedArea,
        rethrowErrors: true,
      );
      if (token != _dataToken ||
          _areaState.currentArea.trim() != requestedArea) {
        return;
      }

      _sectors = report == null
          ? <SectorModel>[]
          : List<SectorModel>.from(report.sectors);
      _sortSectors();
      _previousArea = requestedArea;
      debugPrint(
        '[SectorState] 캐시 로드 완료: area=$requestedArea, count=${_sectors.length}',
      );
    } catch (error, stackTrace) {
      _sectors = <SectorModel>[];
      debugPrint(
        '[SectorState] 캐시 로드 실패: area=$requestedArea, error=$error',
      );
      debugPrint('[SectorState] stackTrace=$stackTrace');
    } finally {
      if (token == _dataToken &&
          _areaState.currentArea.trim() == requestedArea) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> manualSectorRefresh() async {
    await _refreshSectors(rethrowErrors: false);
  }

  Future<int> manualSectorRefreshStrict() async {
    await _refreshSectors(rethrowErrors: true);
    final area = _requireCurrentArea();
    final preferences = await SharedPreferences.getInstance();
    await preferences.reload();
    final report = cachedIntegrityOf(
      preferences,
      area,
      rethrowErrors: true,
    );
    if (report == null) {
      throw StateError('섹터 로컬 데이터 저장 결과가 없습니다.');
    }
    _ensureCacheMatchesState(report);
    debugPrint(
      '[SectorState] 로컬 다운로드 무결성 검증 완료: '
      'area=$area, count=${report.count}, key=${report.key}, '
      'checks=type,fields,area,duplicateId,duplicateName,date,state',
    );
    return report.count;
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
      if (token != _dataToken ||
          _areaState.currentArea.trim() != requestedArea) {
        throw StateError('섹터 동기화 중 현재 지역이 변경되었습니다.');
      }
      _sectors = List<SectorModel>.from(result);
      _validateSectorModels(_sectors, requestedArea);
      _selectedSectorId = null;
      _sortSectors();
      await _saveCacheForArea(requestedArea);
      debugPrint(
        '[SectorState] Firestore 새로고침 완료: area=$requestedArea, count=${_sectors.length}',
      );
    } catch (error, stackTrace) {
      debugPrint(
        '[SectorState] Firestore 새로고침 실패: area=$requestedArea, error=$error',
      );
      debugPrint('[SectorState] stackTrace=$stackTrace');
      if (rethrowErrors) rethrow;
    } finally {
      _isRefreshing = false;
      if (token == _dataToken &&
          _areaState.currentArea.trim() == requestedArea) {
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
      final created = await _repository.addSector(
        area: area,
        name: sectorName,
      );
      _ensureAreaUnchanged(area);
      _sectors = <SectorModel>[..._sectors, created];
      _selectedSectorId = created.id;
      _sortSectors();
      try {
        await _saveCacheForArea(area);
      } catch (cacheError, cacheStackTrace) {
        debugPrint('[SectorState] 등록 후 캐시 저장 실패: $cacheError');
        debugPrint('[SectorState] stackTrace=$cacheStackTrace');
      }
      notifyListeners();
      debugPrint(
        '[SectorState] 등록 완료: id=${created.id}, area=$area, name=${created.name}',
      );
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
      } catch (cacheError, cacheStackTrace) {
        debugPrint('[SectorState] 수정 후 캐시 저장 실패: $cacheError');
        debugPrint('[SectorState] stackTrace=$cacheStackTrace');
      }
      notifyListeners();
      debugPrint(
        '[SectorState] 수정 완료: id=${updated.id}, area=$area, name=${updated.name}',
      );
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
      _sectors = _sectors
          .where((sector) => sector.id != normalizedId)
          .toList(growable: true);
      if (_selectedSectorId == normalizedId) {
        _selectedSectorId = null;
      }
      try {
        await _saveCacheForArea(area);
      } catch (cacheError, cacheStackTrace) {
        debugPrint('[SectorState] 삭제 후 캐시 저장 실패: $cacheError');
        debugPrint('[SectorState] stackTrace=$cacheStackTrace');
      }
      notifyListeners();
      debugPrint('[SectorState] 삭제 완료: id=$normalizedId, area=$area');
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> clearCurrentAreaCache() async {
    final area = _requireCurrentArea();
    ++_dataToken;
    final preferences = await SharedPreferences.getInstance();
    final key = _cacheKey(area);
    await preferences.remove(key);
    await preferences.reload();
    if (preferences.containsKey(key)) {
      throw StateError('기존 섹터 로컬 데이터 삭제 검증 실패');
    }

    _sectors = <SectorModel>[];
    _selectedSectorId = null;
    _previousArea = area;
    _isLoading = false;
    notifyListeners();
    debugPrint('[SectorState] 현재 지역 캐시 삭제 완료: area=$area');
  }

  void toggleSectorSelection(String id) {
    final normalizedId = id.trim();
    if (normalizedId.isEmpty) return;
    _selectedSectorId =
        _selectedSectorId == normalizedId ? null : normalizedId;
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
    final encoded = json.encode(
      source.map((sector) => sector.toCacheMap()).toList(growable: false),
    );
    final preferences = await SharedPreferences.getInstance();
    final key = _cacheKey(normalizedArea);
    final saved = await preferences.setString(key, encoded);
    if (!saved) {
      throw StateError('섹터 데이터 로컬 저장 실패');
    }
    await preferences.reload();
    if (preferences.getString(key) != encoded) {
      throw StateError('섹터 데이터 로컬 저장 원문 검증 실패');
    }
    final report = cachedIntegrityOf(
      preferences,
      normalizedArea,
      rethrowErrors: true,
    );
    if (report == null) {
      throw StateError('섹터 데이터 로컬 저장 결과가 없습니다.');
    }
    _ensureCacheMatchesModels(report, source);
    debugPrint(
      '[SectorState] 캐시 저장 무결성 검증 완료: '
      'area=$normalizedArea, count=${report.count}, key=$key',
    );
  }

  static SectorCacheIntegrityReport _decodeAndValidateCache({
    required String encoded,
    required String area,
    required String key,
  }) {
    final decoded = json.decode(encoded);
    if (decoded is! List) {
      throw const FormatException('섹터 캐시 최상위 형식은 목록이어야 합니다.');
    }

    final sectors = <SectorModel>[];
    final ids = <String>{};
    final normalizedNames = <String>{};
    const requiredKeys = <String>{
      'id',
      'area',
      'name',
      'normalizedName',
      'createdAt',
      'updatedAt',
    };

    for (var index = 0; index < decoded.length; index += 1) {
      final item = decoded[index];
      if (item is! Map) {
        throw FormatException('섹터 캐시 $index번 항목은 객체여야 합니다.');
      }

      Map<String, dynamic> map;
      try {
        map = Map<String, dynamic>.from(item);
      } catch (_) {
        throw FormatException('섹터 캐시 $index번 항목의 키 형식이 올바르지 않습니다.');
      }

      final missingKeys = requiredKeys.difference(map.keys.toSet());
      if (missingKeys.isNotEmpty) {
        throw FormatException(
          '섹터 캐시 $index번 항목에 필수 필드가 없습니다: '
          '${missingKeys.join(',')}',
        );
      }

      final rawId = (map['id'] ?? '').toString();
      final rawArea = (map['area'] ?? '').toString();
      final rawName = (map['name'] ?? '').toString();
      final rawNormalizedName = (map['normalizedName'] ?? '').toString();
      final id = rawId.trim();
      final cachedArea = rawArea.trim();
      final name = rawName.trim();
      final normalizedName = rawNormalizedName.trim();

      if (id.isEmpty) {
        throw FormatException('섹터 캐시 $index번 항목의 문서 ID가 비어 있습니다.');
      }
      if (id != rawId || id.contains('/')) {
        throw FormatException('섹터 캐시 $index번 항목의 문서 ID가 올바르지 않습니다.');
      }
      if (cachedArea.isEmpty || cachedArea != rawArea) {
        throw FormatException('섹터 캐시 $index번 항목의 지역 값이 올바르지 않습니다.');
      }
      if (cachedArea != area) {
        throw FormatException(
          '섹터 캐시 $index번 항목의 지역이 현재 지역과 다릅니다: '
          'expected=$area, actual=$cachedArea',
        );
      }
      if (name.isEmpty || name != rawName || name.contains('/')) {
        throw FormatException('섹터 캐시 $index번 항목의 섹터명이 올바르지 않습니다.');
      }

      final expectedNormalizedName = normalizeSectorName(name);
      if (normalizedName.isEmpty ||
          normalizedName != rawNormalizedName ||
          normalizedName != expectedNormalizedName) {
        throw FormatException(
          '섹터 캐시 $index번 항목의 정규화명이 일치하지 않습니다: '
          'expected=$expectedNormalizedName, actual=$normalizedName',
        );
      }
      if (!ids.add(id)) {
        throw FormatException('섹터 캐시에 중복 문서 ID가 있습니다: $id');
      }
      if (!normalizedNames.add(normalizedName)) {
        throw FormatException('섹터 캐시에 중복 섹터명이 있습니다: $name');
      }

      _validateCachedDate(map['createdAt'], index, 'createdAt');
      _validateCachedDate(map['updatedAt'], index, 'updatedAt');

      final sector = SectorModel.fromCacheMap(map);
      if (sector.id != id ||
          sector.area != cachedArea ||
          sector.name != name ||
          sector.normalizedName != normalizedName) {
        throw FormatException('섹터 캐시 $index번 항목의 모델 변환 결과가 일치하지 않습니다.');
      }
      sectors.add(sector);
    }

    return SectorCacheIntegrityReport(
      area: area,
      key: key,
      sectors: List<SectorModel>.unmodifiable(sectors),
    );
  }

  static void _validateCachedDate(dynamic value, int index, String field) {
    if (value == null) return;
    if (value is! String ||
        value.trim().isEmpty ||
        value != value.trim() ||
        DateTime.tryParse(value) == null) {
      throw FormatException(
        '섹터 캐시 $index번 항목의 $field 형식이 올바르지 않습니다.',
      );
    }
  }

  static void _validateSectorModels(List<SectorModel> sectors, String area) {
    if (area.isEmpty) {
      throw StateError('섹터 캐시 저장 지역이 비어 있습니다.');
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
          'SectorState $index번 항목의 지역이 현재 지역과 다릅니다: '
          'expected=$area, actual=$sectorArea',
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

  void _ensureCacheMatchesState(SectorCacheIntegrityReport report) {
    _ensureCacheMatchesModels(report, List<SectorModel>.from(_sectors));
  }

  static void _ensureCacheMatchesModels(
    SectorCacheIntegrityReport report,
    List<SectorModel> expected,
  ) {
    _validateSectorModels(expected, report.area);
    if (report.count != expected.length) {
      throw StateError(
        '섹터 로컬 데이터 저장 개수가 일치하지 않습니다. '
        'state=${expected.length}, cache=${report.count}',
      );
    }

    final cachedById = <String, SectorModel>{
      for (final sector in report.sectors) sector.id: sector,
    };
    for (final sector in expected) {
      final cached = cachedById[sector.id];
      if (cached == null) {
        throw StateError('섹터 로컬 캐시에 문서가 없습니다: ${sector.id}');
      }
      if (cached.area != sector.area ||
          cached.name != sector.name ||
          cached.normalizedName != sector.normalizedName ||
          cached.createdAt?.toIso8601String() !=
              sector.createdAt?.toIso8601String() ||
          cached.updatedAt?.toIso8601String() !=
              sector.updatedAt?.toIso8601String()) {
        throw StateError('섹터 로컬 캐시와 SectorState 값이 다릅니다: ${sector.id}');
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
