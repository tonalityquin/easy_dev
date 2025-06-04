import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../models/adjustment_model.dart';
import '../../repositories/adjustment/adjustment_repository.dart';
import '../../states/area/area_state.dart';

class AdjustmentState extends ChangeNotifier {
  final AdjustmentRepository _repository;
  final AreaState _areaState;

  AdjustmentState(this._repository, this._areaState) {
    loadFromCache(); // ✅ 캐시 먼저 로딩
    syncWithAreaAdjustmentState(); // ✅ 이후 Firestore 최신화
  }

  List<AdjustmentModel> _adjustments = [];
  Map<String, bool> _selectedAdjustments = {};
  bool _isLoading = true;

  String _previousArea = '';

  List<AdjustmentModel> get adjustments => _adjustments;
  Map<String, bool> get selectedAdjustments => _selectedAdjustments;
  bool get isLoading => _isLoading;

  /// ✅ 빈 AdjustmentModel 기본 제공
  AdjustmentModel get emptyModel => AdjustmentModel(
    id: '',
    countType: '',
    area: '',
    basicStandard: 0,
    basicAmount: 0,
    addStandard: 0,
    addAmount: 0,
  );

  Future<void> loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final currentArea = _areaState.currentArea.trim();
    final cachedJson = prefs.getString('cached_adjustments_$currentArea');

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson) as List;
        _adjustments = decoded
            .map((e) => AdjustmentModel.fromCacheMap(Map<String, dynamic>.from(e)))
            .toList();
        _selectedAdjustments = {for (var adj in _adjustments) adj.id: false};
        _previousArea = currentArea;
        _isLoading = false;
        notifyListeners();
        debugPrint('✅ Adjustment 캐시 로드 성공 (area: $currentArea)');
      } catch (e) {
        debugPrint('⚠️ Adjustment 캐시 파싱 실패: $e');
      }
    }
  }

  /// 🔄 지역 상태 변경 감지 및 Firestore 동기화
  Future<void> syncWithAreaAdjustmentState() async {
    final currentArea = _areaState.currentArea.trim();

    if (currentArea.isEmpty || _previousArea == currentArea) {
      debugPrint('✅ Adjustment 재조회 생략: 동일 지역 ($currentArea)');
      return;
    }

    debugPrint('🔥 Adjustment 지역 변경 감지: $_previousArea → $currentArea');
    _previousArea = currentArea;

    _isLoading = true;
    notifyListeners();

    try {
      final data = await _repository.getAdjustmentsOnce(currentArea);

      _adjustments = data;
      _selectedAdjustments = {for (var adj in _adjustments) adj.id: false};

      // ✅ 캐시 저장
      final prefs = await SharedPreferences.getInstance();
      final jsonData = json.encode(data.map((e) => e.toCacheMap()).toList());
      await prefs.setString('cached_adjustments_$currentArea', jsonData);

      debugPrint("✅ Firestore에서 Adjustment 데이터 새로 불러옴");
    } catch (e) {
      debugPrint("🔥 Adjustment Firestore 동기화 실패: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ✅ 조정 데이터 추가 (문자열 기반)
  Future<void> addAdjustments(
      String countType,
      String area,
      String basicStandard,
      String basicAmount,
      String addStandard,
      String addAmount,
      ) async {
    try {
      final adjustment = AdjustmentModel(
        id: '${countType}_$area',
        countType: countType,
        area: area,
        basicStandard: int.tryParse(basicStandard) ?? 0,
        basicAmount: int.tryParse(basicAmount) ?? 0,
        addStandard: int.tryParse(addStandard) ?? 0,
        addAmount: int.tryParse(addAmount) ?? 0,
      );

      await _repository.addAdjustment(adjustment);
      await syncWithAreaAdjustmentState();
    } catch (e) {
      debugPrint('🔥 Adjustment 추가 실패: $e');
      rethrow;
    }
  }

  /// ✅ 삭제
  Future<void> deleteAdjustments(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteAdjustment(ids);
      await syncWithAreaAdjustmentState();
    } catch (e) {
      onError?.call('🚨 조정 데이터 삭제 실패: $e');
    }
  }

  void toggleSelection(String id) {
    _selectedAdjustments[id] = !(_selectedAdjustments[id] ?? false);
    notifyListeners();
  }
}
