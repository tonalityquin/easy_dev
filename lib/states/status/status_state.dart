import 'dart:async';
import 'package:flutter/material.dart';
import '../../repositories/status/status_repository.dart';
import '../../models/status_model.dart';
import '../area/area_state.dart';

class StatusState extends ChangeNotifier {
  final StatusRepository _repository;
  final AreaState _areaState;
  final TextEditingController textController = TextEditingController();

  StatusState(this._repository, this._areaState) {
    _fetchStatusToggles();
    _areaState.addListener(_fetchStatusToggles); // 지역 변경 감지
  }

  List<StatusModel> _toggleItems = [];
  String? _selectedItemId;
  String _previousArea = '';
  StreamSubscription<List<StatusModel>>? _subscription;

  List<StatusModel> get toggleItems => _toggleItems;

  String? get selectedItemId => _selectedItemId;

  List<StatusModel> get statuses {
    return _toggleItems.where((status) => status.area == _areaState.currentArea).toList();
  }

  void _fetchStatusToggles() {
    final String currentArea = _areaState.currentArea;

    if (currentArea.isEmpty || _previousArea == currentArea) return;

    _previousArea = currentArea;

    _subscription?.cancel(); // ✅ 기존 스트림 해제

    _subscription = _repository.getStatusStream(currentArea).listen(
      (statusList) {
        _toggleItems = statusList;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('🔥 Status stream error: $error');
      },
    );
  }

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
  }

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

  Future<void> removeToggleItem(String id) async {
    await _repository.deleteToggleItem(id);
  }

  void selectItem(String? id) {
    _selectedItemId = (_selectedItemId == id) ? null : id;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel(); // ✅ 상태 해제 시 스트림도 해제
    _areaState.removeListener(_fetchStatusToggles); // 리스너 해제
    textController.dispose();
    super.dispose();
  }
}
