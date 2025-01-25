import 'package:flutter/material.dart';
import '../repositories/adjustment_repository.dart';
import 'area_state.dart';

/// AdjustmentState
/// - Firestore와 동기화하여 정산 데이터를 관리
/// - 선택 상태 및 네비게이션 아이콘 상태를 포함
class AdjustmentState extends ChangeNotifier {
  final AdjustmentRepository _repository;
  final AreaState _areaState; // AreaState 의존성 추가

  AdjustmentState(this._repository, this._areaState) {
    _initializeAdjustments(); // Firestore 데이터와 동기화
  }

  List<Map<String, String>> _adjustments = []; // 정산 데이터
  Map<String, bool> _selectedAdjustments = {}; // 선택된 정산 상태
  bool _isLoading = true; // 로딩 상태
  List<IconData> _navigationIcons = UIHelper.defaultIcons; // 하단 네비게이션 아이콘 상태

  // 정산 데이터 반환
  List<Map<String, String>> get adjustments => _adjustments;

  // 선택된 정산 상태 반환
  Map<String, bool> get selectedAdjustments => _selectedAdjustments;

  // 로딩 상태 반환
  bool get isLoading => _isLoading;

  // 하단 네비게이션 아이콘 반환
  List<IconData> get navigationIcons => _navigationIcons;

  /// Firestore 데이터 실시간 동기화
  /// - Firestore에서 정산 데이터를 구독하고 상태 업데이트
  void _initializeAdjustments() {
    final currentArea = _areaState.currentArea; // AreaState에서 현재 지역 가져오기
    _repository.getAdjustmentStream(currentArea).listen((data) {
      debugPrint('Firestore에서 수신한 데이터: $data'); // 로그 추가

      _adjustments = UIHelper.mapAdjustmentsData(data);
      _selectedAdjustments = {
        for (var adjustment in data) adjustment['id'] as String: adjustment['isSelected'] as bool,
      };

      _navigationIcons = UIHelper.updateIcons(_selectedAdjustments);
      _isLoading = false;
      notifyListeners();
    });
  }

  /// Stream 반환: Firestore 데이터 스트림
  Stream<List<Map<String, dynamic>>> get adjustmentsStream {
    final currentArea = _areaState.currentArea; // AreaState에서 현재 지역 가져오기
    return _repository.getAdjustmentStream(currentArea); // Firestore 쿼리에 지역 전달
  }

  /// Firestore에 정산 타입 추가
  Future<void> addAdjustments(
      String countType,
      String area,
      String basicStandard,
      String basicAmount,
      String addStandard,
      String addAmount,
      ) async {
    try {
      // Firestore에 저장할 데이터를 Map 형태로 생성
      final adjustmentData = {
        'CountType': countType,
        'area': area,
        'basicStandard': basicStandard,
        'basicAmount': basicAmount,
        'addStandard': addStandard,
        'addAmount': addAmount,
        'isSelected': false,
      };

      // Map 데이터를 Firestore에 전달
      await _repository.addAdjustment(adjustmentData);
    } catch (e) {
      debugPrint('Error adding adjustment: $e');
      rethrow; // 에러를 호출부로 전달
    }
  }

  /// Firestore에서 정산 데이터 삭제
  Future<void> deleteAdjustments(List<String> ids) async {
    try {
      await _repository.deleteAdjustment(ids);
    } catch (e) {
      debugPrint('Error deleting adjustment: $e');
      rethrow; // 에러를 호출부로 전달
    }
  }

  /// 정산 선택 상태 토글
  /// - UI 피드백은 호출부에서 처리
  Future<void> toggleSelection(String id) async {
    final currentState = _selectedAdjustments[id] ?? false;
    try {
      // Firestore에서 선택 상태를 토글
      await _repository.toggleAdjustmentSelection(id, !currentState);

      // 선택 상태 업데이트
      _selectedAdjustments[id] = !currentState;
      notifyListeners();
    } catch (e) {
      debugPrint('Error toggling selection: $e');
      rethrow; // 에러를 호출부로 전달
    }
  }
}

/// UI 관련 헬퍼 클래스
/// - 중복 코드를 제거하고 UI 상태 관리를 지원
class UIHelper {
  static const List<IconData> defaultIcons = [Icons.add, Icons.circle, Icons.settings];

  /// Firestore 데이터 매핑
  static List<Map<String, String>> mapAdjustmentsData(List<Map<String, dynamic>> data) {
    return data.map((adjustment) => {
      'id': adjustment['id'] as String,
      'countType': adjustment['CountType'] as String,
      'area': adjustment['area'] as String,
      'basicStandard': adjustment['basicStandard'] as String,
      'basicAmount': adjustment['basicAmount'] as String,
      'addStandard': adjustment['addStandard'] as String,
      'addAmount': adjustment['addAmount'] as String,
    }).toList();
  }

  /// 네비게이션 아이콘 상태 업데이트
  static List<IconData> updateIcons(Map<String, bool> selectedAdjustments) {
    if (selectedAdjustments.values.contains(true)) {
      return [Icons.lock, Icons.delete, Icons.edit]; // 선택된 상태의 아이콘
    }
    return defaultIcons; // 기본 아이콘
  }
}
