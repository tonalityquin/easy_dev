import 'package:flutter/material.dart';
import '../../repositories/adjustment/adjustment_repository.dart';
import '../../models/adjustment_model.dart';
import '../../states/area/area_state.dart';

class AdjustmentState extends ChangeNotifier {
  final AdjustmentRepository _repository;
  final AreaState _areaState;

  AdjustmentState(this._repository, this._areaState) {
    syncWithAreaAdjustmentState(); // 🔄 초기화 시 비동기 동기화 실행
  }

  List<AdjustmentModel> _adjustments = [];
  Map<String, bool> _selectedAdjustments = {};
  bool _isLoading = true;

  String _previousArea = '';

  List<AdjustmentModel> get adjustments => _adjustments;

  Map<String, bool> get selectedAdjustments => _selectedAdjustments;

  bool get isLoading => _isLoading;

  /// 🔄 지역 상태 변경 감지 및 데이터 로딩
  Future<void> syncWithAreaAdjustmentState() async {
    try {
      final currentArea = _areaState.currentArea.trim();

      if (_previousArea == currentArea) {
        debugPrint('✅ 동일 지역 감지됨 ($currentArea) → 재조회 생략');
        return;
      }

      debugPrint('🔥 지역 변경 감지됨 ($_previousArea → $currentArea) → 데이터 새로 가져옴');
      _previousArea = currentArea;

      await _initializeAdjustments(); // 🔁 비동기화 적용
    } catch (e) {
      debugPrint("🔥 Error syncing area state: $e");
    }
  }

  /// ✅ Firestore에서 일회성 조회로 데이터 로딩
  Future<void> _initializeAdjustments() async {
    _isLoading = true;
    notifyListeners();

    try {
      final currentArea = _areaState.currentArea;

      final data = await _repository.getAdjustmentsOnce(currentArea);

      _adjustments.clear();
      _adjustments = data;

      for (var adj in data) {
        debugPrint("📌 Firestore에서 불러온 데이터: $adj");
      }

      if (data.isEmpty) {
        debugPrint("⚠️ Firestore에서 가져온 데이터가 없음. 기존 값 유지");
      }

      _selectedAdjustments = {for (var adj in _adjustments) adj.id: false};
    } catch (e) {
      debugPrint("🔥 Firestore 조정 데이터 조회 실패: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
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
      final adjustment = AdjustmentModel(
        id: '${countType}_$area',
        countType: countType,
        area: area,
        basicStandard: int.tryParse(basicStandard) ?? 0,
        basicAmount: int.tryParse(basicAmount) ?? 0,
        addStandard: int.tryParse(addStandard) ?? 0,
        addAmount: int.tryParse(addAmount) ?? 0,
      );

      debugPrint("📌 저장할 데이터: $adjustment");

      await _repository.addAdjustment(adjustment);
      debugPrint("✅ 데이터 저장 성공");

      await syncWithAreaAdjustmentState(); // 🔄 저장 후 다시 불러오기
    } catch (e) {
      debugPrint('🔥 데이터 추가 중 오류 발생: $e');
      rethrow;
    }
  }

  Future<void> addAdjustment(AdjustmentModel adjustment, {void Function(String)? onError}) async {
    debugPrint("📌 저장하는 데이터: $adjustment");
    try {
      await _repository.addAdjustment(adjustment);
      await syncWithAreaAdjustmentState(); // ✅ 저장 후 갱신
    } catch (e) {
      onError?.call('🚨 조정 데이터 추가 실패: $e');
    }
  }

  Future<void> deleteAdjustments(List<String> ids, {void Function(String)? onError}) async {
    try {
      await _repository.deleteAdjustment(ids);
      await syncWithAreaAdjustmentState(); // ✅ 삭제 후 갱신
    } catch (e) {
      onError?.call('🚨 조정 데이터 삭제 실패: $e');
    }
  }

  void toggleSelection(String id) {
    _selectedAdjustments[id] = !(_selectedAdjustments[id] ?? false);
    notifyListeners();
  }
}
