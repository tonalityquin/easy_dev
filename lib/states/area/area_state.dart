import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  // ⬇️ 여기 세 줄만 final 로 변경
  final String _selectedArea = '';
  final String _selectedDivision = '';
  final bool _isLocked = false;

  String get currentArea => _currentArea;

  String get currentDivision => _currentDivision;

  String get selectedArea => _selectedArea;

  String get selectedDivision => _selectedDivision;

  List<String> get availableAreas => _availableAreas.toList();

  bool get isLocked => _isLocked;

  Map<String, List<String>> get divisionAreaMap => _divisionAreaMap;

  AreaState();

  Future<void> loadAreasForDivision(String userDivision) async {
    try {
      final snapshot = await _firestore.collection('areas').where('division', isEqualTo: userDivision).get();

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

  Future<void> initializeArea(String userArea) async {
    try {
      final snapshot = await _firestore.collection('areas').where('name', isEqualTo: userArea).limit(1).get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final division = doc['division'] as String?;

        if (_currentArea != userArea) {
          _currentArea = userArea;
          _currentDivision = (division != null && division.trim().isNotEmpty) ? division.trim() : 'default';

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

  Future<void> updateAreaPicker(String newArea, {bool isSyncing = false}) async {
    if (_isLocked && !isSyncing) {
      debugPrint('⛔ currentArea는 보호 중 → 변경 무시됨 (입력: $newArea)');
      return;
    }

    if (_currentArea == newArea) {
      debugPrint('ℹ️ currentArea 변경 없음: $_currentArea 그대로 유지됨');
      return;
    }

    try {
      final snapshot = await _firestore.collection('areas').where('name', isEqualTo: newArea).limit(1).get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final division = doc['division'] as String?;

        _currentArea = newArea;
        _currentDivision = (division != null && division.trim().isNotEmpty) ? division.trim() : 'default';

        notifyListeners();
        final msg = isSyncing
            ? '🔄 지역 동기화: $_currentArea / division: $_currentDivision'
            : '✅ 지역 변경됨: $_currentArea / division: $_currentDivision';
        debugPrint(msg);
      } else {
        debugPrint('⚠️ 지역 정보 없음 - 변경 무시됨: $newArea');
      }
    } catch (e) {
      debugPrint('❌ 지역 변경 실패: $e');
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
      final snapshot = await _firestore.collection('areas').where('name', isEqualTo: newArea).limit(1).get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final division = doc['division'] as String?;

        _currentArea = newArea;
        _currentDivision = (division != null && division.trim().isNotEmpty) ? division.trim() : 'default';

        notifyListeners();
        final msg = isSyncing
            ? '🔄 지역 동기화: $_currentArea / division: $_currentDivision'
            : '✅ 지역 변경됨: $_currentArea / division: $_currentDivision';
        debugPrint(msg);
      } else {
        debugPrint('⚠️ 지역 정보 없음 - 변경 무시됨: $newArea');
      }
    } catch (e) {
      debugPrint('❌ 지역 변경 실패: $e');
    }
  }
}
