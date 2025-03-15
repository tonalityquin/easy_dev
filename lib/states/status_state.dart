import 'package:flutter/material.dart';
import '../repositories/status/status_repository.dart';
import '../models/status_model.dart';
import 'area_state.dart';

class StatusState extends ChangeNotifier {
  final StatusRepository _repository;
  final AreaState _areaState;
  final TextEditingController textController = TextEditingController();

  StatusState(this._repository, this._areaState) {
    _fetchStatusToggles();
    _areaState.addListener(_fetchStatusToggles);
  }

  List<StatusModel> _toggleItems = [];
  String? _selectedItemId;

  List<StatusModel> get toggleItems => _toggleItems;
  String? get selectedItemId => _selectedItemId;

  List<StatusModel> get statuses {
    return _toggleItems.where((status) => status.area == _areaState.currentArea).toList();
  }

  void _fetchStatusToggles() {
    final String currentArea = _areaState.currentArea;
    if (currentArea.isEmpty) {
      return;
    }
    _repository.getStatusStream(currentArea).listen((statusList) {
      _toggleItems = statusList;
      notifyListeners();
    });
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
}