import 'package:flutter/material.dart';
import '../../repositories/adjustment/adjustment_repository.dart';
import '../../models/adjustment_model.dart';
import '../../states/area/area_state.dart';

class AdjustmentState extends ChangeNotifier {
  final AdjustmentRepository _repository;
  final AreaState _areaState;

  AdjustmentState(this._repository, this._areaState) {
    _initializeAdjustments();
  }

  List<AdjustmentModel> _adjustments = [];
  Map<String, bool> _selectedAdjustments = {};
  bool _isLoading = true;

  String _previousArea = ''; // ✅ 이전 지역 캐시 변수 추가

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

      debugPrint("📌 저장할 데이터: $adjustment");

      await _repository.addAdjustment(adjustment);
      debugPrint("✅ 데이터 저장 성공");

      // 🔥 Firestore에서 데이터를 다시 불러오기 전에, UI에 즉시 반영
      _adjustments.add(adjustment);
      notifyListeners();

      syncWithAreaState();
    } catch (e) {
      debugPrint('🔥 데이터 추가 중 오류 발생: $e');
      rethrow;
    }
  }

  void syncWithAreaState() {
    try {
      final currentArea = _areaState.currentArea.trim();

      // ✅ 이전 지역과 비교하여 동일하면 재조회 생략
      if (_previousArea == currentArea) {
        debugPrint('✅ 동일 지역 감지됨 ($currentArea) → 재조회 생략');
        return;
      }

      debugPrint('🔥 지역 변경 감지됨 ($_previousArea → $currentArea) → 데이터 새로 가져옴');
      _previousArea = currentArea;
      _initializeAdjustments();
    } catch (e) {
      debugPrint("🔥 Error syncing area state: $e");
    }
  }

  void _initializeAdjustments() {
    final currentArea = _areaState.currentArea;

    // 기존 스트림을 제거하고 새로운 스트림을 추가
    _repository.getAdjustmentStream(currentArea).listen(
          (data) {
        _adjustments.clear(); // 기존 데이터 초기화

        for (var adj in data) {
          debugPrint("📌 Firestore에서 불러온 데이터: $adj");
        }

        if (data.isNotEmpty) {
          _adjustments = data;
        } else {
          debugPrint("⚠️ Firestore에서 가져온 데이터가 없음. 기존 값 유지");
        }

        _selectedAdjustments = {for (var adj in _adjustments) adj.id: false};
        _isLoading = false;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('🔥 Firestore 데이터 불러오기 오류: $error');
      },
    );
  }

  Future<void> addAdjustment(AdjustmentModel adjustment, {void Function(String)? onError}) async {
    debugPrint("📌 저장하는 데이터: $adjustment");
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
