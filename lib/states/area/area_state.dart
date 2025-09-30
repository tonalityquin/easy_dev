// lib/states/area/area_state.dart
//
// Firestore 읽기 동작만 UsageReporter로 계측합니다 (action='read').

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../models/capability.dart';
// import '../../utils/usage_reporter.dart';

enum AreaType {
  dev;

  static String get label => 'dev';
}

class AreaState with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Set<String> _availableAreas = {};
  final Map<String, List<String>> _divisionAreaMap = {};

  String _currentArea = '';
  String _currentDivision = '';

  // ⬇️ 여기 세 줄만 final 로 유지
  final String _selectedArea = '';
  final String _selectedDivision = '';
  final bool _isLocked = false;

  // 지역명 → Capability Set 매핑
  final Map<String, CapSet> _areaCaps = {};

  String get currentArea => _currentArea;

  String get currentDivision => _currentDivision;

  String get selectedArea => _selectedArea;

  String get selectedDivision => _selectedDivision;

  List<String> get availableAreas => _availableAreas.toList();

  bool get isLocked => _isLocked;

  Map<String, List<String>> get divisionAreaMap => _divisionAreaMap;

  /// 현재 지역의 Capability 집합
  CapSet get capabilitiesOfCurrentArea => _areaCaps[_currentArea] ?? <Capability>{};

  AreaState();

  /*void _reportRead(String source, {String? area, int n = 1}) {
    try {
      final a = (area?.trim().isNotEmpty ?? false)
          ? area!.trim()
          : (_currentArea.isNotEmpty ? _currentArea : '(unspecified)');
      UsageReporter.instance.report(
        area: a,
        action: 'read',
        n: n,
        source: source,
      );
    } catch (e) {
      debugPrint('UsageReporter(read) error: $e');
    }
  }*/

  /// ✅ 공통: 현재 설정된 _currentArea를 FG(Service)에 통지
  void _notifyForegroundWithArea() {
    if (_currentArea.isNotEmpty) {
      FlutterForegroundTask.sendDataToTask({'area': _currentArea});
      debugPrint('📤 FG로 area 전송: $_currentArea');
    } else {
      debugPrint('⚠️ currentArea 가 비어 있어 FG 전송 스킵');
    }
  }

  /// Firestore 문서 데이터(Map)에서 division/capabilities 파싱 후 상태 반영
  void _applyDocDataToState(
    Map<String, dynamic>? data, {
    required String areaName,
  }) {
    final divisionRaw = data?['division'] as String?;
    final capsRaw = data?['capabilities'];

    _currentArea = areaName;
    _currentDivision = (divisionRaw != null && divisionRaw.trim().isNotEmpty) ? divisionRaw.trim() : 'default';

    // Capability 파싱(없으면 빈 집합)
    final caps = Cap.fromDynamic(capsRaw);
    _areaCaps[areaName] = caps;

    // 비어 있던 리스트 초기화/유지
    _availableAreas
      ..clear()
      ..add(areaName);
  }

  /// 현재 메모리 상태에 동일 area에 대한 "쓸만한" 캐시가 있는지 판단
  bool _hasValidCacheFor(String area) {
    final trimmed = area.trim();
    if (trimmed.isEmpty) return false;

    final sameArea = (_currentArea == trimmed);
    final caps = _areaCaps[trimmed];
    final hasCaps = caps != null && caps.isNotEmpty;
    final hasDivision = _currentDivision.trim().isNotEmpty;

    // 동일 지역이 이미 셋업되어 있고, 기능셋 또는 division이 유효하면 캐시 히트로 간주
    if (sameArea && (hasCaps || hasDivision)) return true;

    // 혹시 선행 로드로 _areaCaps만 채워진 케이스
    if (_availableAreas.contains(trimmed) && hasCaps) return true;

    return false;
  }

  Future<void> loadAreasForDivision(String userDivision) async {
    try {
      final q = _firestore.collection('areas').where('division', isEqualTo: userDivision);

      final snapshot = await q.get();

      /*_reportRead('AreaState.loadAreasForDivision.areas.get', area: 'division:$userDivision');*/

      _divisionAreaMap.clear();

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>?;
        final division = (data?['division'] as String?)?.trim();
        final name = (data?['name'] as String?)?.trim();

        if (name != null && name.isNotEmpty) {
          _divisionAreaMap.putIfAbsent(division ?? 'default', () => []);
          _divisionAreaMap[division ?? 'default']!.add(name);

          // capabilities 캐시 (선행 로드)
          final capsRaw = data?['capabilities'];
          _areaCaps[name] = Cap.fromDynamic(capsRaw);
        }
      }

      debugPrint('✅ divisionAreaMap 로딩 완료: $_divisionAreaMap');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ divisionAreaMap 로딩 실패: $e');
    }
  }

  /// ✅ A(멱등화): 같은 area가 이미 메모리에 유효하게 로드돼 있으면 네트워크 READ를 **스킵**
  ///    필요 시 강제 새로고침하려면 [forceRefresh]를 true로 전달
  Future<void> initializeArea(String userArea, {bool forceRefresh = false}) async {
    final area = userArea.trim();
    if (area.isEmpty) {
      debugPrint('⚠️ initializeArea: 빈 area 입력 → 스킵');
      return;
    }

    // 캐시 히트 시 네트워크 쿼리 생략
    if (!forceRefresh && _hasValidCacheFor(area)) {
      debugPrint('ℹ️ initializeArea: cache hit → query skip for "$area"');
      // 상태/리스너 정합성 보장
      _currentArea = area;
      if (_currentDivision.trim().isEmpty) {
        _currentDivision = 'default';
      }
      notifyListeners();
      _notifyForegroundWithArea();
      return;
    }

    try {
      final q = _firestore.collection('areas').where('name', isEqualTo: area).limit(1);

      final snapshot = await q.get();

      /*_reportRead('AreaState.initializeArea.areas.get', area: area);*/

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data() as Map<String, dynamic>?;
        _applyDocDataToState(data, areaName: area);

        notifyListeners();
        debugPrint(
          '✅ 사용자 지역 초기화 완료 → $_currentArea / $_currentDivision'
          ' / caps: ${Cap.human(capabilitiesOfCurrentArea)}',
        );

        // ✅ FG에도 반드시 통지
        _notifyForegroundWithArea();
      } else {
        debugPrint('⚠️ Firestore에 해당 지역이 존재하지 않음: $area');
        _currentArea = '';
        _currentDivision = '';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('❌ Firestore 사용자 지역 초기화 실패: $e');
      _currentArea = '';
      _currentDivision = '';
      notifyListeners();
    }
  }

  Future<void> updateAreaPicker(String newArea, {bool isSyncing = false}) async {
    await _updateAreaCommon(newArea, isSyncing: isSyncing);
  }

  Future<void> updateArea(String newArea, {bool isSyncing = false}) async {
    await _updateAreaCommon(newArea, isSyncing: isSyncing);
  }

  Future<void> _updateAreaCommon(String newArea, {required bool isSyncing}) async {
    if (_isLocked && !isSyncing) {
      debugPrint('⛔ currentArea는 보호 중 → 변경 무시됨 (입력: $newArea)');
      return;
    }

    if (_currentArea == newArea) {
      debugPrint('ℹ️ currentArea 변경 없음: $_currentArea 그대로 유지됨');
      return;
    }

    try {
      final q = _firestore.collection('areas').where('name', isEqualTo: newArea).limit(1);

      final snapshot = await q.get();

      /*_reportRead('AreaState.updateArea.areas.get', area: newArea);*/

      if (snapshot.docs.isNotEmpty) {
        final data = snapshot.docs.first.data() as Map<String, dynamic>?;
        _applyDocDataToState(data, areaName: newArea);

        notifyListeners();
        final msg = isSyncing
            ? '🔄 지역 동기화: $_currentArea / division: $_currentDivision'
            : '✅ 지역 변경됨: $_currentArea / division: $_currentDivision';
        debugPrint('$msg / caps: ${Cap.human(capabilitiesOfCurrentArea)}');

        // ✅ FG에도 반드시 통지
        _notifyForegroundWithArea();
      } else {
        debugPrint('⚠️ 지역 정보 없음 - 변경 무시됨: $newArea');
      }
    } catch (e) {
      debugPrint('❌ 지역 변경 실패: $e');
    }
  }
}
