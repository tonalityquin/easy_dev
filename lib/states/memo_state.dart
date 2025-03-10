import 'package:flutter/material.dart';
import '../repositories/memo_repository.dart';
import 'area_state.dart';

class MemoState extends ChangeNotifier {
  final MemoRepository _repository;
  final AreaState _areaState;
  final TextEditingController textController = TextEditingController();

  List<Map<String, dynamic>> _toggleMemo = [];
  String? _selectedMemoId;

  MemoState(this._repository, this._areaState) {
    _fetchMemoToggles();
    _areaState.addListener(_fetchMemoToggles);
  }

  /// Firestore에서 상태 데이터 실시간 가져오기
  void _fetchMemoToggles() {
    final String? currentArea = _areaState.currentArea;
    if (currentArea == null || currentArea.isEmpty) return;

    _repository.getMemoStream(currentArea).listen((memoList) {
      if (_toggleMemo != memoList) {
        _toggleMemo = memoList;
        notifyListeners();
      }
    });
  }

  /// Firestore에서 상태 변경 (토글)
  Future<void> toggleMemo(String id) async {
    final index = _toggleMemo.indexWhere((item) => item['id'] == id);
    if (index != -1) {
      final newMemo = !_toggleMemo[index]['isActive'];
      await _repository.updateMemo(id, newMemo);
      _fetchMemoToggles();
    }
  }

  /// Firestore에 상태 추가 (현재 지역 포함)
  Future<void> addMemo(String name) async {
    final String? currentArea = _areaState.currentArea;
    if (currentArea == null || currentArea.isEmpty) return;

    final newMemo = {
      "id": DateTime.now().millisecondsSinceEpoch.toString(),
      "name": name,
      "isActive": false,
      "area": currentArea,
    };
    await _repository.addMemo(newMemo);
  }

  /// Firestore에서 상태 삭제
  Future<void> removeMemo(String id) async {
    await _repository.removeMemo(id);
  }

  /// 선택 항목 관리
  String? get selectedMemoId => _selectedMemoId;

  void selectMemo(String id) {
    _selectedMemoId = (_selectedMemoId == id) ? null : id;
    notifyListeners();
  }

  /// Getter: 전체 리스트
  List<Map<String, dynamic>> get activeToggleItems {
    return _toggleMemo;
  }

  /// Getter: 현재 지역에 해당하는 메모 목록
  List<Map<String, dynamic>> get memo {
    return _toggleMemo.where((memo) => memo['area'] == _areaState.currentArea).toList();
  }
}
