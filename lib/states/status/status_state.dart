import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../repositories/status/status_repository.dart';
import '../../models/status_model.dart';
import '../area/area_state.dart';

class StatusState extends ChangeNotifier {
  final StatusRepository _repository;
  final AreaState _areaState;
  final TextEditingController textController = TextEditingController();

  StatusState(this._repository, this._areaState) {
    loadFromCache();               // ✅ 캐시 우선 로드
    syncWithAreaStatusState();     // ✅ 이후 Firestore에서 동기화
    _areaState.addListener(syncWithAreaStatusState);
  }

  List<StatusModel> _toggleItems = [];
  String? _selectedItemId;
  String _previousArea = '';
  bool _isLoading = true;

  List<StatusModel> get toggleItems => _toggleItems;
  String? get selectedItemId => _selectedItemId;
  bool get isLoading => _isLoading;

  List<StatusModel> get statuses {
    return _toggleItems
        .where((status) => status.area == _areaState.currentArea)
        .toList();
  }

  /// ✅ 캐시에서 로드
  Future<void> loadFromCache() async {
    final prefs = await SharedPreferences.getInstance();
    final currentArea = _areaState.currentArea.trim();
    final cachedJson = prefs.getString('cached_statuses_$currentArea');

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson) as List;
        _toggleItems = decoded
            .map((e) => StatusModel.fromCacheMap(Map<String, dynamic>.from(e)))
            .toList();
        _previousArea = currentArea;
        _isLoading = false;
        notifyListeners();
        debugPrint("✅ 상태 캐시 로딩 완료 (area: $currentArea)");
      } catch (e) {
        debugPrint("⚠️ 상태 캐시 로드 실패: $e");
      }
    }
  }

  /// ✅ Firestore 동기화 + 캐시 저장
  Future<void> syncWithAreaStatusState() async {
    final currentArea = _areaState.currentArea;

    if (currentArea.isEmpty || _previousArea == currentArea) {
      debugPrint('✅ 상태 재조회 생략: 동일 지역 ($currentArea)');
      return;
    }

    debugPrint('🔥 상태 조회 시작: $_previousArea → $currentArea');
    _previousArea = currentArea;

    _isLoading = true;
    notifyListeners();

    try {
      final statusList = await _repository.getStatusesOnce(currentArea);
      _toggleItems = statusList;

      // ✅ 캐시에 저장
      final prefs = await SharedPreferences.getInstance();
      final jsonData = json.encode(statusList.map((e) => e.toCacheMap()).toList());
      await prefs.setString('cached_statuses_$currentArea', jsonData);

      debugPrint("✅ 상태 Firestore 동기화 완료: ${statusList.length}건");
    } catch (e) {
      debugPrint('🔥 상태 목록 조회 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
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
    await syncWithAreaStatusState();
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
    await syncWithAreaStatusState();
  }

  /// ✅ 선택 항목 토글
  void selectItem(String? id) {
    _selectedItemId = (_selectedItemId == id) ? null : id;
    notifyListeners();
  }

  @override
  void dispose() {
    _areaState.removeListener(syncWithAreaStatusState);
    textController.dispose();
    super.dispose();
  }
}
