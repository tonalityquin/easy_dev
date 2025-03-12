import 'package:flutter/material.dart';
import '../repositories/adjustment_repository.dart';
import '../models/adjustment_model.dart';
import '../states/area_state.dart';

class AdjustmentState extends ChangeNotifier {
  final AdjustmentRepository _repository;
  final AreaState _areaState;

  AdjustmentState(this._repository, this._areaState) {
    _initializeAdjustments();
  }

  List<AdjustmentModel> _adjustments = [];
  Map<String, bool> _selectedAdjustments = {};
  bool _isLoading = true;

  List<AdjustmentModel> get adjustments => _adjustments;
  Map<String, bool> get selectedAdjustments => _selectedAdjustments;
  bool get isLoading => _isLoading;

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
      syncWithAreaState();
    } catch (e) {
      debugPrint('🔥 Error adding adjustment: $e');
      rethrow;
    }
  }


  void syncWithAreaState() {
    try {
      final currentArea = _areaState.currentArea.trim();
      debugPrint('🔥 AdjustmentState: 지역 변경 감지됨 ($currentArea) → 데이터 새로 가져옴');
      _initializeAdjustments();
    } catch (e) {
      debugPrint("🔥 Error syncing area state: $e");
    }
  }

  void _initializeAdjustments() {
    final currentArea = _areaState.currentArea;
    _repository.getAdjustmentStream(currentArea).listen(
          (data) {
        _adjustments = data;
        _selectedAdjustments = { for (var adj in data) adj.id: false };
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('Error syncing adjustments: $error');
      },
    );
  }

  Future<void> addAdjustment(AdjustmentModel adjustment, {void Function(String)? onError}) async {
    try {
      await _repository.addAdjustment(adjustment);
    } catch (e) {
      onError?.call('🚨 조정 데이터 추가 실패: $e');
    }
  }

  Future<void> deleteAdjustments(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteAdjustment(ids);
    } catch (e) {
      onError?.call('🚨 조정 데이터 삭제 실패: $e');
    }
  }

  void toggleSelection(String id) {
    _selectedAdjustments[id] = !(_selectedAdjustments[id] ?? false);
    notifyListeners();
  }
}
