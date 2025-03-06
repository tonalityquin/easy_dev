import 'dart:async';
import 'package:flutter/material.dart';
import '../repositories/adjustment_repository.dart';
import 'area_state.dart';

class AdjustmentState extends ChangeNotifier {
  final AdjustmentRepository _repository;
  final AreaState _areaState;
  StreamSubscription<List<Map<String, dynamic>>>? _subscription;

  AdjustmentState(this._repository, this._areaState) {
    _initializeAdjustments();
  }

  List<Map<String, dynamic>> _adjustments = [];
  Map<String, bool> _selectedAdjustments = {}; // ✅ 선택된 데이터 저장

  List<Map<String, dynamic>> get adjustments => _adjustments;

  Map<String, bool> get selectedAdjustments => _selectedAdjustments; // ✅ 추가된 변수

  Stream<List<Map<String, dynamic>>> get adjustmentsStream {
    final currentArea = _areaState.currentArea;
    return _repository.getAdjustmentStream(currentArea);
  }

  /// ✅ 지역 변경 감지 후 데이터 동기화
  void syncWithAreaState() {
    try {
      final currentArea = _areaState.currentArea.trim();
      debugPrint('🔥 AdjustmentState: 지역 변경 감지됨 ($currentArea) → 데이터 새로 가져옴');

      _subscription?.cancel();
      _initializeAdjustments();
    } catch (e) {
      debugPrint("🔥 Error syncing area state: $e");
    }
  }

  /// ✅ Firestore 데이터 초기화 및 실시간 업데이트 구독
  void _initializeAdjustments() {
    final currentArea = _areaState.currentArea.trim();
    _adjustments.clear();
    _selectedAdjustments.clear();

    _subscription = _repository.getAdjustmentStream(currentArea).listen((data) {
      _adjustments = data
          .where((adj) => adj['area'].toString().trim() == currentArea)
          .map((adj) => {
                'id': adj['id'],
                'countType': adj['CountType']?.toString().trim() ?? adj['countType']?.toString().trim() ?? '',
                'area': adj['area'],
                'basicStandard': parseInt(adj['basicStandard']),
                'basicAmount': parseInt(adj['basicAmount']),
                'addStandard': parseInt(adj['addStandard']),
                'addAmount': parseInt(adj['addAmount']),
              })
          .where((adj) => adj['countType'].isNotEmpty)
          .toList();

      debugPrint('🔥 현재 선택된 지역($currentArea)에 맞는 데이터: $_adjustments');
      notifyListeners();
    });
  }

  /// ✅ 숫자 변환 함수 (데이터 안정성 향상)
  int parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  /// ✅ 선택 상태 토글
  void toggleSelection(String id) {
    _selectedAdjustments[id] = !(_selectedAdjustments[id] ?? false);
    notifyListeners();
  }

  /// ✅ Firestore에 조정 데이터 추가
  Future<void> addAdjustments(
    String countType,
    String area,
    String basicStandard,
    String basicAmount,
    String addStandard,
    String addAmount,
  ) async {
    try {
      final adjustmentData = {
        'CountType': countType,
        'area': area,
        'basicStandard': basicStandard,
        'basicAmount': basicAmount,
        'addStandard': addStandard,
        'addAmount': addAmount,
      };

      await _repository.addAdjustment(adjustmentData);
      syncWithAreaState();
    } catch (e) {
      debugPrint('🔥 Error adding adjustment: $e');
      rethrow;
    }
  }

  /// ✅ Firestore에서 조정 데이터 삭제
  Future<void> deleteAdjustments(List<String> ids) async {
    try {
      await _repository.deleteAdjustment(ids);
      syncWithAreaState();
    } catch (e) {
      debugPrint('🔥 Error deleting adjustment: $e');
      rethrow;
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
