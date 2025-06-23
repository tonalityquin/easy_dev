import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum AreaType {
  dev;

  static String get label => 'dev';
}

class AreaState with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Set<String> _availableAreas = {};
  String _currentArea = '';
  String _currentDivision = '';

  String _selectedArea = '';
  String _selectedDivision = '';

  bool _isLocked = false;

  String get currentArea => _currentArea;
  String get currentDivision => _currentDivision;

  String get selectedArea => _selectedArea;
  String get selectedDivision => _selectedDivision;

  List<String> get availableAreas => _availableAreas.toList();
  bool get isLocked => _isLocked;

  AreaState();

  final Map<String, List<String>> _divisionAreaMap = {};
  Map<String, List<String>> get divisionAreaMap => _divisionAreaMap;

  /// 모든 division-area 구조 로딩 (관리자용)
  Future<void> loadAllDivisionsAndAreas() async {
    try {
      final snapshot = await _firestore.collection('areas').get();

      _divisionAreaMap.clear();

      for (final doc in snapshot.docs) {
        final division = doc['division'] as String? ?? 'default';
        final name = doc['name'] as String?;

        if (name != null && name.trim().isNotEmpty) {
          _divisionAreaMap.putIfAbsent(division, () => []);
          _divisionAreaMap[division]!.add(name);
        }
      }

      debugPrint('✅ divisionAreaMap 로딩 완료: $_divisionAreaMap');
      notifyListeners();
    } catch (e) {
      debugPrint('❌ divisionAreaMap 로딩 실패: $e');
    }
  }

  void lockArea() {
    _isLocked = true;
    debugPrint('🔒 지역 보호 활성화됨 → 현재 지역: $_currentArea');
  }

  void unlockArea() {
    _isLocked = false;
    debugPrint('🔓 지역 보호 해제됨');
  }

  /// ✅ currentArea 초기화
  Future<void> initializeArea(String userArea) async {
    try {
      final snapshot = await _firestore
          .collection('areas')
          .where('name', isEqualTo: userArea)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final division = doc['division'] as String?;

        if (_currentArea != userArea) {
          _currentArea = userArea;
          _currentDivision = (division != null && division.trim().isNotEmpty)
              ? division.trim()
              : 'default';

          _availableAreas.clear();
          _availableAreas.add(userArea);

          notifyListeners();
          debugPrint('✅ 사용자 지역 초기화 완료 → $_currentArea / $_currentDivision');
        } else {
          debugPrint('⚠️ 이미 해당 지역이 설정되어 있습니다: $_currentArea');
        }
      } else {
        debugPrint('⚠️ Firestore에 해당 지역이 존재하지 않음: $userArea');
        _currentArea = '';
        _currentDivision = '';
      }
    } catch (e) {
      debugPrint('❌ Firestore 사용자 지역 초기화 실패: $e');
      _currentArea = '';
      _currentDivision = '';
    }
  }

  Future<void> addArea(String name, String division) async {
    final trimmedName = name.trim();
    final trimmedDivision =
    division.trim().isEmpty ? 'default' : division.trim();

    if (trimmedName.isEmpty || _availableAreas.contains(trimmedName)) {
      debugPrint('⚠️ 이미 존재하거나 빈 값입니다: $trimmedName');
      return;
    }

    final customId = '${trimmedDivision}_$trimmedName';

    try {
      await _firestore.collection('areas').doc(customId).set({
        'name': trimmedName,
        'division': trimmedDivision,
        'createdAt': FieldValue.serverTimestamp(),
      });

      _availableAreas.add(trimmedName);
      notifyListeners();
      debugPrint(
          '🆕 지역 추가됨 (Firestore): $trimmedName, division: $trimmedDivision, id: $customId');
    } catch (e) {
      debugPrint('❌ Firestore 지역 추가 실패: $e');
    }
  }

  Future<void> removeArea(String area) async {
    if (area == AreaType.label) {
      debugPrint('⚠️ 기본 지역 dev는 삭제할 수 없습니다.');
      return;
    }

    try {
      final snapshot = await _firestore
          .collection('areas')
          .where('name', isEqualTo: area)
          .get();

      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }

      if (_availableAreas.remove(area)) {
        if (_currentArea == area) {
          _currentArea = '';
          _currentDivision = '';
        }
        if (_selectedArea == area) {
          _selectedArea = '';
          _selectedDivision = '';
        }
        notifyListeners();
        debugPrint('🗑️ 지역 삭제됨 (Firestore): $area');
      }
    } catch (e) {
      debugPrint('❌ Firestore 지역 삭제 실패: $e');
    }
  }

  Future<void> updateArea(String newArea, {bool isSyncing = false}) async {
    if (_isLocked && !isSyncing) {
      debugPrint('⛔ currentArea는 보호 중 → 변경 무시됨 (입력: $newArea)');
      return;
    }

    if (_currentArea == newArea) {
      debugPrint('ℹ️ currentArea 변경 없음: $_currentArea 그대로 유지됨');
      return;
    }

    try {
      final snapshot = await _firestore
          .collection('areas')
          .where('name', isEqualTo: newArea)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final division = doc['division'] as String?;

        _currentArea = newArea;
        _currentDivision = (division != null && division.trim().isNotEmpty)
            ? division.trim()
            : 'default';

        notifyListeners();
        debugPrint(isSyncing
            ? '🔄 지역 동기화: $_currentArea / division: $_currentDivision'
            : '✅ 지역 변경됨: $_currentArea / division: $_currentDivision');
      } else {
        debugPrint('⚠️ 지역 정보 없음 - 변경 무시됨: $newArea');
      }
    } catch (e) {
      debugPrint('❌ 지역 변경 실패: $e');
    }
  }

  void initializeOrSyncArea(String area) {
    if (_currentArea != area) {
      updateArea(area, isSyncing: true);
    }
  }

  /// ✅ selectedArea 초기화 및 갱신
  Future<void> updateSelectedArea(String newArea) async {
    if (_selectedArea == newArea) {
      debugPrint('ℹ️ selectedArea 변경 없음: $_selectedArea 그대로 유지됨');
      return;
    }

    try {
      final snapshot = await _firestore
          .collection('areas')
          .where('name', isEqualTo: newArea)
          .limit(1)
          .get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final division = doc['division'] as String?;

        _selectedArea = newArea;
        _selectedDivision = (division != null && division.trim().isNotEmpty)
            ? division.trim()
            : 'default';

        notifyListeners();
        debugPrint(
            '✅ selectedArea 변경됨: $_selectedArea / division: $_selectedDivision');
      } else {
        debugPrint('⚠️ 지역 정보 없음 - selectedArea 변경 무시됨: $newArea');
      }
    } catch (e) {
      debugPrint('❌ selectedArea 변경 실패: $e');
    }
  }
}
