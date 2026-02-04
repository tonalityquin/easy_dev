import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../repositories/location_repo_services/location_repository.dart';
import '../../models/location_model.dart';
import '../area/area_state.dart';

class LocationState extends ChangeNotifier {
  final LocationRepository _repository;
  final AreaState _areaState;
  final List<IconData> _navigationIcons = [Icons.add, Icons.delete];

  List<LocationModel> _locations = [];
  String? _selectedLocationId;
  String _previousArea = '';
  bool _isLoading = true;

  List<LocationModel> get locations => _locations;
  List<IconData> get navigationIcons => _navigationIcons;
  String? get selectedLocationId => _selectedLocationId;
  bool get isLoading => _isLoading;

  LocationState(this._repository, this._areaState) {
    loadFromLocationCache();

    _areaState.addListener(() async {
      final currentArea = _areaState.currentArea.trim();
      if (currentArea != _previousArea) {
        _previousArea = currentArea;
        await loadFromLocationCache();
      }
    });
  }

  // ---------------------------------------------------------------------------
  // A안: 같은 지역(area) 내 "주차 구역명" 전역 유니크 강제
  // - 단일(single) 이름과 복합(composite) 자식 이름이 서로 충돌하면 안 됨
  // - 근거: locations 문서 ID가 '<name>_<area>' 규칙이라 덮어쓰기/충돌 발생
  // ---------------------------------------------------------------------------
  static String _normalizeName(String raw) {
    // 앞뒤 공백 제거 + 내부 다중 공백 축약
    return raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _nameKey(String raw) => _normalizeName(raw).toLowerCase();

  Future<Set<String>> _fetchExistingNameKeysForArea(String area) async {
    final trimmedArea = area.trim();
    final data = await _repository.getLocationsOnce(trimmedArea);
    return data.map((loc) => _nameKey(loc.locationName)).toSet();
  }

  /// ✅ write(add/delete) 직후 Firestore를 1회 읽어서:
  /// - _locations 갱신
  /// - SharedPreferences 캐시 갱신
  /// - 화면 즉시 최신화
  Future<void> _syncFromFirestoreAfterWrite(String area) async {
    final trimmedArea = area.trim();
    if (trimmedArea.isEmpty) return;

    try {
      final data = await _repository.getLocationsOnce(trimmedArea);

      _locations = data;
      _selectedLocationId = null;
      _previousArea = trimmedArea;

      final prefs = await SharedPreferences.getInstance();
      final jsonData = json.encode(data.map((e) => e.toCacheMap()).toList());
      await prefs.setString('cached_locations_$trimmedArea', jsonData);

      final totalCapacity = data.fold<int>(0, (sum, loc) => sum + loc.capacity);
      await prefs.setInt('total_capacity_$trimmedArea', totalCapacity);

      debugPrint('✅ write 후 Firestore 동기화 완료 (area: $trimmedArea, ${data.length}건)');
    } catch (e) {
      debugPrint('⚠️ write 후 Firestore 동기화 실패(area=$trimmedArea): $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadFromLocationCache() async {
    final prefs = await SharedPreferences.getInstance();
    final currentArea = _areaState.currentArea.trim();
    final cachedJson = prefs.getString('cached_locations_$currentArea');

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson) as List;
        _locations = decoded
            .map((e) => LocationModel.fromCacheMap(Map<String, dynamic>.from(e)))
            .toList();

        _selectedLocationId = null;
        _previousArea = currentArea;
        _isLoading = false;
        notifyListeners();

        debugPrint('✅ 캐시에서 주차 구역 ${_locations.length}건 로드 (area: $currentArea)');
        final totalCapacity = prefs.getInt('total_capacity_$currentArea') ?? 0;
        debugPrint('📦 총 capacity 캐시값: $totalCapacity');
      } catch (e) {
        debugPrint('⚠️ 주차 구역 캐시 디코딩 실패: $e');
        _locations = [];
        _selectedLocationId = null;
        _isLoading = false;
        notifyListeners();
      }
    } else {
      debugPrint('⚠️ 캐시에 없음 → Firestore 호출 없음 (수동 새로고침에서만 호출)');
      _locations = [];
      _selectedLocationId = null;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> manualLocationRefresh() async {
    final currentArea = _areaState.currentArea.trim();
    debugPrint('🔥 수동 새로고침 Firestore 호출 → $currentArea');

    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.getLocationsOnce(currentArea);

      final currentIds = _locations.map((e) => e.id).toSet();
      final newIds = data.map((e) => e.id).toSet();
      final isIdentical =
          currentIds.length == newIds.length && currentIds.containsAll(newIds);

      if (isIdentical) {
        debugPrint('✅ Firestore 데이터가 캐시와 동일 → 갱신 없음');
      } else {
        _locations = data;
        _selectedLocationId = null;

        final prefs = await SharedPreferences.getInstance();
        final jsonData = json.encode(data.map((e) => e.toCacheMap()).toList());
        await prefs.setString('cached_locations_$currentArea', jsonData);

        final totalCapacity = data.fold<int>(0, (sum, loc) => sum + loc.capacity);
        await prefs.setInt('total_capacity_$currentArea', totalCapacity);

        debugPrint('✅ Firestore 데이터 캐시에 갱신됨 (area: $currentArea)');
        debugPrint('📦 총 capacity 저장됨: $totalCapacity');
      }
    } catch (e) {
      debugPrint('🔥 Firestore 주차 구역 조회 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void updatePlateCounts(Map<String, int> counts) {
    int changed = 0;

    _locations = _locations.map((loc) {
      final fullName =
      loc.type == 'composite' ? '${loc.parent} - ${loc.locationName}' : loc.locationName;

      final next = counts[fullName];
      if (next == null) return loc;

      if (loc.plateCount != next) changed++;
      return loc.copyWith(plateCount: next);
    }).toList();

    notifyListeners();
    debugPrint('📊 plateCount 업데이트 완료: 변경 $changed건 / 입력 ${counts.length}건');
  }

  Future<void> updatePlateCountsForNames(
      LocationRepository repo,
      List<String> displayNames,
      ) async {
    if (displayNames.isEmpty) return;

    final uniq = displayNames.toSet().toList();
    debugPrint('🎯 부분 갱신 요청: ${uniq.length}개 → 예: ${uniq.take(5).toList()}');

    final counts = await repo.getPlateCountsForLocations(
      locationNames: uniq,
      area: _areaState.currentArea,
    );

    updatePlateCounts(counts);
  }

  /// ✅ 단일 주차 구역 추가 (A안: 지역 내 전역 유니크)
  /// 반환: true 성공 / false 실패(중복 포함)
  Future<bool> addSingleLocation(
      String locationName,
      String area, {
        int capacity = 0,
        void Function(String)? onError,
      }) async {
    final cleanArea = area.trim();
    final cleanName = _normalizeName(locationName);

    if (cleanArea.isEmpty) {
      onError?.call('⚠️ 지역(area)이 비어 있어 주차 구역을 추가할 수 없습니다.');
      return false;
    }
    if (cleanName.isEmpty) {
      onError?.call('⚠️ 주차 구역 이름을 입력하세요.');
      return false;
    }
    if (capacity < 0) {
      onError?.call('⚠️ 수용 대수(capacity)는 0 이상이어야 합니다.');
      return false;
    }

    try {
      // ✅ Firestore 기준으로 중복 확인(캐시가 오래되어도 안전)
      final existing = await _fetchExistingNameKeysForArea(cleanArea);
      final key = _nameKey(cleanName);

      if (existing.contains(key)) {
        onError?.call(
          '⚠️ "$cleanArea" 지역에 이미 "$cleanName" 주차 구역이 존재합니다.\n'
              '단일/복합(자식) 주차 구역명은 지역 내에서 중복될 수 없습니다.',
        );
        return false;
      }

      final location = LocationModel(
        id: '${cleanName}_$cleanArea',
        locationName: cleanName,
        area: cleanArea,
        // ✅ 기존 코드(parent: area)는 의미상/표시상 부자연스러움 → single은 자기 자신을 parent로 두는 편이 안전
        parent: cleanName,
        type: 'single',
        capacity: capacity,
        isSelected: false,
      );

      await _repository.addSingleLocation(location);
      await _syncFromFirestoreAfterWrite(cleanArea);
      return true;
    } catch (e) {
      onError?.call('🚨 주차 구역 추가 실패: $e');
      return false;
    }
  }

  /// ✅ 복합 주차 구역 추가 (A안: 지역 내 전역 유니크)
  /// - 같은 area 내에서는 "자식(leaf) 이름"이 부모가 달라도 중복 불가
  /// - 단일(single) 이름과도 중복 불가
  /// 반환: true 성공 / false 실패(중복 포함)
  Future<bool> addCompositeLocation(
      String parent,
      List<Map<String, dynamic>> subs,
      String area, {
        void Function(String)? onError,
      }) async {
    final cleanArea = area.trim();
    final cleanParent = _normalizeName(parent);

    if (cleanArea.isEmpty) {
      onError?.call('⚠️ 지역(area)이 비어 있어 복합 주차 구역을 추가할 수 없습니다.');
      return false;
    }
    if (cleanParent.isEmpty) {
      onError?.call('⚠️ 상위(부모) 주차 구역명을 입력하세요.');
      return false;
    }
    if (subs.isEmpty) {
      onError?.call('⚠️ 하위(자식) 주차 구역이 1개 이상 필요합니다.');
      return false;
    }

    // 1) 입력 정규화 + "요청 내" 중복 체크
    final normalizedSubs = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final sub in subs) {
      final name = _normalizeName(sub['name']?.toString() ?? '');
      final cap = (sub['capacity'] as num?)?.toInt() ?? 0;

      if (name.isEmpty) {
        onError?.call('⚠️ 하위(자식) 주차 구역명은 비어 있을 수 없습니다.');
        return false;
      }
      if (cap < 0) {
        onError?.call('⚠️ 하위(자식) 수용 대수(capacity)는 0 이상이어야 합니다.');
        return false;
      }

      final key = _nameKey(name);
      if (seen.contains(key)) {
        onError?.call('⚠️ 입력한 하위(자식) 목록에 "$name"이(가) 중복되어 있습니다.');
        return false;
      }
      seen.add(key);

      normalizedSubs.add({'name': name, 'capacity': cap});
    }

    try {
      // 2) Firestore 기준 "지역 내 전역 유니크" 중복 체크
      final existing = await _fetchExistingNameKeysForArea(cleanArea);
      final conflicts = <String>[];

      for (final sub in normalizedSubs) {
        final n = sub['name']?.toString() ?? '';
        if (existing.contains(_nameKey(n))) conflicts.add(n);
      }

      if (conflicts.isNotEmpty) {
        onError?.call(
          '⚠️ "$cleanArea" 지역에 이미 사용 중인 주차 구역명이 있습니다: ${conflicts.join(', ')}\n'
              '복합 자식명은 부모가 달라도 지역 내에서 중복될 수 없습니다.',
        );
        return false;
      }

      // 3) 저장 포맷으로 변환(기존 저장 규칙 유지)
      final safeParent = '${cleanParent}_$cleanArea';
      final safeSubs = normalizedSubs
          .map((sub) => {
        'name': '${sub['name']}_$cleanArea',
        'capacity': sub['capacity'] ?? 0,
      })
          .toList();

      await _repository.addCompositeLocation(safeParent, safeSubs, cleanArea);
      await _syncFromFirestoreAfterWrite(cleanArea);
      return true;
    } catch (e) {
      onError?.call('🚨 복합 주차 구역 추가 실패: $e');
      return false;
    }
  }

  /// ✅ 주차 구역 삭제
  /// 반환: true 성공 / false 실패
  Future<bool> deleteLocations(
      List<String> ids, {
        void Function(String)? onError,
      }) async {
    if (ids.isEmpty) return true;

    try {
      await _repository.deleteLocations(ids);

      final currentArea = _areaState.currentArea.trim();
      await _syncFromFirestoreAfterWrite(currentArea);
      return true;
    } catch (e) {
      onError?.call('🚨 주차 구역 삭제 실패: $e');
      return false;
    }
  }

  Future<void> toggleLocationSelection(String id) async {
    if (_selectedLocationId == id) {
      _selectedLocationId = null;
    } else {
      _selectedLocationId = id;
    }
    notifyListeners();
  }
}
