import 'package:flutter/material.dart';
import '../repositories/status_repository.dart';
import 'area_state.dart';

class StatusState extends ChangeNotifier {
  final StatusRepository _repository;
  final AreaState _areaState; // 🔄 AreaState 추가

  StatusState(this._repository, this._areaState) {
    _fetchStatusToggles(); // Firestore 데이터와 동기화
    _areaState.addListener(_fetchStatusToggles); // 🔄 지역 변경 감지
  }

  List<Map<String, dynamic>> _toggleItems = [];
  String? _selectedItemId;
  final TextEditingController textController = TextEditingController();

  List<Map<String, dynamic>> get toggleItems => _toggleItems;

  String? get selectedItemId => _selectedItemId;

  List<Map<String, dynamic>> get statuses {
    return _toggleItems.where((status) => status['area'] == _areaState.currentArea).toList();
  }

  /// Firestore에서 상태 데이터 실시간 가져오기 (지역 필터 적용)
  /// Firestore에서 상태 데이터 실시간 가져오기 (지역 필터 적용)
  /// Firestore에서 상태 데이터 실시간 가져오기 (지역 필터 적용)
  void _fetchStatusToggles() {
    final String? currentArea = _areaState.currentArea;

    if (currentArea == null || currentArea.isEmpty) {
      return;
    }

    _repository.getStatusStream(currentArea).listen((statusList) {
      if (_toggleItems != statusList) {
        // ✅ 데이터가 변경된 경우에만 notifyListeners 호출
        _toggleItems = statusList;
        notifyListeners();
      }
    });
  }

  /// Firestore에 상태 추가 (현재 지역 포함)
  Future<void> addToggleItem(String name) async {
    final String? currentArea = _areaState.currentArea;
    if (currentArea == null || currentArea.isEmpty) return; // 🔄 지역이 없으면 추가 불가

    final newItem = {
      "id": DateTime.now().millisecondsSinceEpoch.toString(),
      "name": name,
      "isActive": false,
      "area": currentArea, // 🔄 현재 지역 포함
    };
    await _repository.addToggleItem(newItem);
  }

  /// Firestore에서 상태 변경
  Future<void> toggleItem(String id) async {
    final index = _toggleItems.indexWhere((item) => item['id'] == id);
    if (index != -1) {
      final newState = !_toggleItems[index]['isActive'];
      await _repository.updateToggleStatus(id, newState);
    }
  }

  /// Firestore에서 상태 삭제
  Future<void> removeToggleItem(String id) async {
    await _repository.deleteToggleItem(id);
  }

  /// 선택 항목 관리
  void selectItem(String id) {
    _selectedItemId = (_selectedItemId == id) ? null : id;
    notifyListeners();
  }
}
