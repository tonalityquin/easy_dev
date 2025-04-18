import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

enum AreaType {
  dev;

  static String get label => 'dev';
}

class AreaState with ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  final Set<String> _availableAreas = {AreaType.label}; // 항상 dev 포함
  String _currentArea = AreaType.label;
  String _currentDivision = 'dev'; // dev 지역의 division도 명시적으로 지정

  String get currentArea => _currentArea;
  String get currentDivision => _currentDivision;
  List<String> get availableAreas => _availableAreas.toList();

  // ❌ 초기 로드 제거 — 외부에서 initialize로 호출하도록 변경
  AreaState();

  /// ✅ 외부에서 Firestore 로드 완료 후 사용자 지역 반영
  Future<void> initialize(String userArea) async {
    await _loadAreasFromFirestore();
    initializeOrSyncArea(userArea);
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
      final snapshot = await _firestore
          .collection('areas')
          .where('name', isEqualTo: area)
          .get();

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
    if (_availableAreas.contains(newArea) && _currentArea != newArea) {
      _currentArea = newArea;

      if (newArea == AreaType.label) {
        _currentDivision = 'dev';
      } else {
        try {
          final snapshot = await _firestore
              .collection('areas')
              .where('name', isEqualTo: newArea)
              .limit(1)
              .get();

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
    } else if (!_availableAreas.contains(newArea)) {
      debugPrint('⚠️ 잘못된 지역 입력: $newArea / 가능한 지역: $_availableAreas');
    }
  }

  void initializeOrSyncArea(String area) {
    if (_currentArea != area) {
      updateArea(area, isSyncing: true);
    }
  }
}
