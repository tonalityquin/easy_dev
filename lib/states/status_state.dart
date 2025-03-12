import 'package:flutter/material.dart';
import '../repositories/status_repository.dart';
import 'area_state.dart';

class StatusState extends ChangeNotifier {
  final StatusRepository _repository;
  final AreaState _areaState;

  StatusState(this._repository, this._areaState) {
    _fetchStatusToggles();
    _areaState.addListener(_fetchStatusToggles);
  }

  List<Map<String, dynamic>> _toggleItems = [];
  String? _selectedItemId;
  final TextEditingController textController = TextEditingController();

  List<Map<String, dynamic>> get toggleItems => _toggleItems;

  String? get selectedItemId => _selectedItemId;

  List<Map<String, dynamic>> get statuses {
    return _toggleItems.where((status) => status['area'] == _areaState.currentArea).toList();
  }

  void _fetchStatusToggles() {
    final String? currentArea = _areaState.currentArea;
    if (currentArea == null || currentArea.isEmpty) {
      return;
    }
    _repository.getStatusStream(currentArea).listen((statusList) {
      if (_toggleItems != statusList) {
        _toggleItems = statusList;
        notifyListeners();
      }
    });
  }

  Future<void> addToggleItem(String name) async {
    final String? currentArea = _areaState.currentArea;
    if (currentArea == null || currentArea.isEmpty) return;
    final newItem = {
      "id": DateTime.now().millisecondsSinceEpoch.toString(),
      "name": name,
      "isActive": false,
      "area": currentArea,
    };
    await _repository.addToggleItem(newItem);
  }

  Future<void> toggleItem(String id) async {
    final index = _toggleItems.indexWhere((item) => item['id'] == id);
    if (index != -1) {
      final newState = !_toggleItems[index]['isActive'];
      await _repository.updateToggleStatus(id, newState);
    }
  }

  Future<void> removeToggleItem(String id) async {
    await _repository.deleteToggleItem(id);
  }

  void selectItem(String id) {
    _selectedItemId = (_selectedItemId == id) ? null : id;
    notifyListeners();
  }
}
