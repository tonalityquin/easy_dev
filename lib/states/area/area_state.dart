import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AreaType {
  dev;

  static String get label => 'dev';
}

class AreaState with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Set<String> _availableAreas = {AreaType.label};
  String _currentArea = AreaType.label;
  String _currentDivision = 'dev';

  bool _isLocked = false;

  String get currentArea => _currentArea;

  String get currentDivision => _currentDivision;

  List<String> get availableAreas => _availableAreas.toList();

  bool get isLocked => _isLocked;

  AreaState();

  void lockArea() {
    _isLocked = true;
    debugPrint('🔒 지역 보호 활성화됨 → 현재 지역: $_currentArea');
  }

  void unlockArea() {
    _isLocked = false;
    debugPrint('🔓 지역 보호 해제됨');
  }

  /// ✅ 특정 유저의 지역만 Firestore에서 가져와 초기화
  Future<void> initialize(String userArea) async {
    try {
      final snapshot = await _firestore.collection('areas').where('name', isEqualTo: userArea).limit(1).get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final division = doc['division'] as String?;

        _currentArea = userArea;
        _currentDivision = (division != null && division.trim().isNotEmpty) ? division.trim() : 'default';

        _availableAreas.clear();
        _availableAreas.add(userArea);
        _availableAreas.add(AreaType.label); // dev 항상 포함

        notifyListeners();
        debugPrint('✅ 사용자 지역 초기화 완료 → $_currentArea / $_currentDivision');
      } else {
        debugPrint('⚠️ Firestore에 해당 지역이 존재하지 않음: $userArea');
        _currentArea = AreaType.label;
        _currentDivision = 'dev';
      }
    } catch (e) {
      debugPrint('❌ Firestore 사용자 지역 초기화 실패: $e');
      _currentArea = AreaType.label;
      _currentDivision = 'dev';
    }

    lockArea(); // 초기화 완료 후 보호
  }

  Future<void> addArea(String name, String division) async {
    final trimmedName = name.trim();
    final trimmedDivision = division.trim().isEmpty ? 'default' : division.trim();

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
      debugPrint('🆕 지역 추가됨 (Firestore): $trimmedName, division: $trimmedDivision, id: $customId');
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
      final snapshot = await _firestore.collection('areas').where('name', isEqualTo: area).get();

      for (var doc in snapshot.docs) {
        await doc.reference.delete();
      }

      if (_availableAreas.remove(area)) {
        if (_currentArea == area) {
          _currentArea = AreaType.label;
          _currentDivision = 'dev';
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
      final snapshot = await _firestore.collection('areas').where('name', isEqualTo: newArea).limit(1).get();

      if (snapshot.docs.isNotEmpty) {
        final doc = snapshot.docs.first;
        final division = doc['division'] as String?;

        _currentArea = newArea;
        _currentDivision = (division != null && division.trim().isNotEmpty) ? division.trim() : 'default';

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
}
