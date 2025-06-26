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
    loadFromCache(); // ✅ 캐시 우선 로드
    _areaState.addListener(_handleAreaChange); // 지역 변경 감지
  }

  List<StatusModel> _toggleItems = [];
  String? _selectedItemId;
  String _previousArea = '';
  bool _isLoading = true;

  List<StatusModel> get toggleItems => _toggleItems;
  List<StatusModel> get statuses =>
      _toggleItems.where((s) => s.area == _areaState.currentArea).toList();

  String? get selectedItemId => _selectedItemId;
  bool get isLoading => _isLoading;

  /// ✅ 캐시에서 상태 우선 로드 (유효기간 검사 없음)
  Future<void> loadFromCache() async {
    final currentArea = _areaState.currentArea.trim();
    final prefs = await SharedPreferences.getInstance();

    final cacheKey = 'statuses_$currentArea';
    final cachedJson = prefs.getString(cacheKey);

    if (cachedJson != null) {
      try {
        final decoded = json.decode(cachedJson) as List;
        _toggleItems = decoded
            .map((e) => StatusModel.fromCacheMap(Map<String, dynamic>.from(e)))
            .toList();
        _previousArea = currentArea;
        _isLoading = false;
        debugPrint('✅ 상태 캐시 로딩 완료 (area: $currentArea)');
      } catch (e) {
        debugPrint('⚠️ 상태 캐시 디코딩 실패: $e');
      }
    } else {
      debugPrint('⚠️ 상태 캐시 없음 → Firestore 호출 대기');
      await fetchStatusesFromFirestore(currentArea); // 최초 호출
    }

    notifyListeners();
  }

  /// ✅ Firestore 호출 + 캐시 갱신
  Future<void> fetchStatusesFromFirestore(String area) async {
    debugPrint('🔥 상태 Firestore 호출 → $area');

    _isLoading = true;
    notifyListeners();

    try {
      final statusList = await _repository.getStatusesOnce(area);
      _toggleItems = statusList;
      await _updateCacheWithStatuses(area, statusList); // 캐시 갱신
      debugPrint('✅ 상태 Firestore 동기화 완료: ${statusList.length}건');
    } catch (e) {
      debugPrint('🔥 상태 Firestore 조회 실패: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// ✅ 캐시 갱신
  Future<void> _updateCacheWithStatuses(
      String area, List<StatusModel> statuses) async {
    final cacheKey = 'statuses_$area';
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString(
      cacheKey,
      json.encode(
        statuses.map((status) => status.toCacheMap()).toList(),
      ),
    );

    debugPrint('✅ 상태 캐시 갱신 완료 → $area (${statuses.length}개)');
  }

  /// 🧠 지역 변경 트리거
  Future<void> _handleAreaChange() async {
    final currentArea = _areaState.currentArea.trim();

    if (currentArea.isEmpty || _previousArea == currentArea) {
      debugPrint('✅ 상태 재조회 생략: 동일 지역 ($currentArea)');
      return;
    }

    _previousArea = currentArea;
    await fetchStatusesFromFirestore(currentArea);
  }

  /// 🔄 수동 Firestore 호출 트리거 (예: 새로고침 버튼)
  Future<void> manualRefresh() async {
    final currentArea = _areaState.currentArea.trim();
    await fetchStatusesFromFirestore(currentArea);
  }

  /// Single-status_management.dart
  Future<void> addToggleItem(String name) async {
    final currentArea = _areaState.currentArea;
    if (currentArea.isEmpty) return;

    final newItem = StatusModel(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      name: name,
      isActive: false,
      area: currentArea,
    );

    await _repository.addToggleItem(newItem);
    await fetchStatusesFromFirestore(currentArea); // 캐시 갱신
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
    await fetchStatusesFromFirestore(_areaState.currentArea); // 캐시 갱신
  }

  void selectItem(String? id) {
    _selectedItemId = (_selectedItemId == id) ? null : id;
    notifyListeners();
  }

  @override
  void dispose() {
    _areaState.removeListener(_handleAreaChange);
    textController.dispose();
    super.dispose();
  }
}
