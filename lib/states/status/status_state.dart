import 'package:flutter/material.dart';
import '../../repositories/status/status_repository.dart';
import '../../models/status_model.dart';
import '../area/area_state.dart';

class StatusState extends ChangeNotifier {
  final StatusRepository _repository;
  final AreaState _areaState;
  final TextEditingController textController = TextEditingController();

  StatusState(this._repository, this._areaState) {
    syncWithAreaStatusState(); // 🔁 초기화 시 비동기 데이터 로딩
    _areaState.addListener(syncWithAreaStatusState); // 지역 변경 감지
  }

  List<StatusModel> _toggleItems = [];
  String? _selectedItemId;
  String _previousArea = '';

  List<StatusModel> get toggleItems => _toggleItems;

  String? get selectedItemId => _selectedItemId;

  List<StatusModel> get statuses {
    return _toggleItems
        .where((status) => status.area == _areaState.currentArea)
        .toList();
  }

  /// ✅ 지역 변화 시 상태를 일회성 조회로 가져옴
  Future<void> syncWithAreaStatusState() async {
    final String currentArea = _areaState.currentArea;

    if (currentArea.isEmpty || _previousArea == currentArea) {
      debugPrint('✅ 상태 재조회 생략: 동일 지역 ($currentArea)');
      return;
    }

    debugPrint('🔥 상태 조회 시작: $_previousArea → $currentArea');
    _previousArea = currentArea;

    try {
      final statusList = await _repository.getStatusesOnce(currentArea);
      _toggleItems = statusList;
      notifyListeners();
    } catch (e) {
      debugPrint('🔥 상태 목록 조회 실패: $e');
    }
  }

  /// ✅ 항목 추가
  Future<void> addToggleItem(String name) async {
    final String currentArea = _areaState.currentArea;
    if (currentArea.isEmpty) return;

    final newItem = StatusModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      isActive: false,
      area: currentArea,
    );

    await _repository.addToggleItem(newItem);
    await syncWithAreaStatusState(); // 추가 후 상태 갱신
  }

  /// ✅ 항목 상태 토글
  Future<void> toggleItem(String id) async {
    final index = _toggleItems.indexWhere((item) => item.id == id);
    if (index != -1) {
      final newState = !_toggleItems[index].isActive;

      _toggleItems[index] = StatusModel(
        id: _toggleItems[index].id,
        name: _toggleItems[index].name,
        isActive: newState,
        area: _toggleItems[index].area,
      );

      notifyListeners();
      await _repository.updateToggleStatus(id, newState);
    }
  }

  /// ✅ 항목 삭제
  Future<void> removeToggleItem(String id) async {
    await _repository.deleteToggleItem(id);
    await syncWithAreaStatusState(); // 삭제 후 상태 갱신
  }

  /// ✅ 선택 항목 ID 설정
  void selectItem(String? id) {
    _selectedItemId = (_selectedItemId == id) ? null : id;
    notifyListeners();
  }

  @override
  void dispose() {
    _areaState.removeListener(syncWithAreaStatusState); // 리스너 해제
    textController.dispose();
    super.dispose();
  }
}
