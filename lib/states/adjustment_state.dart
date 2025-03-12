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
  Map<String, bool> _selectedAdjustments = {};

  List<Map<String, dynamic>> get adjustments => _adjustments;

  Map<String, bool> get selectedAdjustments => _selectedAdjustments;

  Stream<List<Map<String, dynamic>>> get adjustmentsStream {
    final currentArea = _areaState.currentArea;
    return _repository.getAdjustmentStream(currentArea);
  }

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

  int parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  void toggleSelection(String id) {
    _selectedAdjustments[id] = !(_selectedAdjustments[id] ?? false);
    notifyListeners();
  }

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
