import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ 추가

enum AreaType {
  dev;

  static String get label => 'dev';
}

class AreaState with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Set<String> _availableAreas = {AreaType.label}; // 항상 dev 포함
  String _currentArea = AreaType.label;
  String _currentDivision = 'dev'; // dev 지역의 division도 명시적으로 지정

  bool _isLocked = false; // ✅ 외부 감지 방지 플래그 추가

  String get currentArea => _currentArea;
  String get currentDivision => _currentDivision;
  List<String> get availableAreas => _availableAreas.toList();
  bool get isLocked => _isLocked; // ✅ 외부에서 상태 확인용

  AreaState();

  /// ✅ 외부에서 수동 설정 시 보호 활성화
  void lockArea() {
    _isLocked = true;
    debugPrint('🔒 지역 보호 활성화됨 → 현재 지역: $_currentArea');
  }

  void unlockArea() {
    _isLocked = false;
    debugPrint('🔓 지역 보호 해제됨');
  }

  Future<void> initializeFromStorageIfAvailable() async {
    final prefs = await SharedPreferences.getInstance();
    final savedArea = prefs.getString('area');

    if (savedArea != null && savedArea.trim().isNotEmpty) {
      debugPrint('📦 저장된 user.area 감지됨 → $savedArea');
      await initialize(savedArea);
    } else {
      debugPrint('📦 SharedPreferences에 저장된 지역 정보 없음');
    }
  }

  Future<void> initialize(String userArea) async {
    await _loadAreasFromFirestore();
    initializeOrSyncArea(userArea);
    lockArea(); // ✅ 초기화 후 보호 활성화
  }

  Future<void> _loadAreasFromFirestore() async {
    try {
      final snapshot = await _firestore.collection('areas').get();

      _availableAreas.clear();
      _availableAreas.add(AreaType.label); // dev는 기본 포함

      for (var doc in snapshot.docs) {
        final name = doc['name'] as String?;
        if (name != null && name.trim().isNotEmpty && name != AreaType.label) {
          _availableAreas.add(name.trim());
        }

        if (name == _currentArea) {
          final division = doc['division'] as String?;
          _currentDivision = division?.trim().isNotEmpty == true ? division!.trim() : 'default';
        }
      }

      notifyListeners();
    } catch (e) {
      debugPrint('❌ Firestore 지역 불러오기 실패: $e');
    }
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
    // ✅ 보호된 상태에서는 감지된 지역 반영 금지
    if (_isLocked && !isSyncing) {
      debugPrint('⛔ currentArea는 보호 중 → 변경 무시됨 (입력: $newArea)');
      return;
    }

    if (!_availableAreas.contains(newArea)) {
      debugPrint('⚠️ 잘못된 지역 입력: $newArea / 가능한 지역: $_availableAreas');
      return;
    }

    if (_currentArea == newArea) {
      debugPrint('ℹ️ currentArea 변경 없음: $_currentArea 그대로 유지됨');
      return;
    }

    _currentArea = newArea;

    if (newArea == AreaType.label) {
      _currentDivision = 'dev';
    } else {
      try {
        final snapshot = await _firestore.collection('areas').where('name', isEqualTo: newArea).limit(1).get();

        if (snapshot.docs.isNotEmpty) {
          final division = snapshot.docs.first['division'] as String?;
          _currentDivision = division?.trim().isNotEmpty == true ? division!.trim() : 'default';
        } else {
          _currentDivision = 'default';
        }
      } catch (e) {
        debugPrint('❌ 지역 division 불러오기 실패: $e');
        _currentDivision = 'default';
      }
    }

    notifyListeners();

    debugPrint(
      isSyncing
          ? '🔄 지역 동기화: $_currentArea / division: $_currentDivision'
          : '✅ 지역 변경됨: $_currentArea / division: $_currentDivision',
    );
  }

  void initializeOrSyncArea(String area) {
    if (_currentArea != area) {
      updateArea(area, isSyncing: true);
    }
  }
}

