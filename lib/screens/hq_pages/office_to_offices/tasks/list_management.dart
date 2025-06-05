import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

mixin ListManagement<T extends StatefulWidget, E> on State<T> {
  final Map<String, List<E>> _todoLists = {};
  String _currentList = '기본 목록';
  final TextEditingController _listNameController = TextEditingController();

  Map<String, List<E>> get todoLists => _todoLists;
  String get currentList => _currentList;
  set currentList(String value) => _currentList = value;
  TextEditingController get listNameController => _listNameController;

  /// 현재 목록의 항목 리스트 반환 (존재하지 않으면 생성)
  List<E> getCurrentListItems() {
    if (!_todoLists.containsKey(_currentList)) {
      _todoLists[_currentList] = <E>[];
    }
    return _todoLists[_currentList]!;
  }

  /// 모든 목록 불러오기
  void loadAllLists(String prefix, E Function(String) fromJson) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith(prefix));
    setState(() {
      _todoLists.clear();
      for (var key in keys) {
        final name = key.replaceFirst(prefix, '');
        final rawList = prefs.getStringList(key) ?? [];
        _todoLists[name] = rawList.map(fromJson).toList();
      }
      if (_todoLists.isEmpty) {
        _todoLists['기본 목록'] = [];
      }
      if (!_todoLists.containsKey(_currentList)) {
        _currentList = _todoLists.keys.first;
      }
    });
  }

  /// 현재 목록 저장
  void saveCurrentList(String prefix, String Function(E) toJson) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = getCurrentListItems().map(toJson).toList();
    await prefs.setStringList('$prefix$_currentList', jsonList);
  }

  /// 목록 이름 수정
  void editListName(VoidCallback onSave) {
    _listNameController.text = _currentList;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('목록 이름 수정'),
        content: TextField(
          controller: _listNameController,
          decoration: const InputDecoration(hintText: '새 목록 이름'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              final newName = _listNameController.text.trim();
              if (newName.isNotEmpty &&
                  newName != _currentList &&
                  !_todoLists.containsKey(newName)) {
                setState(() {
                  _todoLists[newName] = _todoLists[_currentList]!;
                  _todoLists.remove(_currentList);
                  _currentList = newName;
                });
                onSave();
              }
              Navigator.pop(context);
            },
            child: const Text('저장'),
          ),
        ],
      ),
    );
  }

  /// 현재 목록 삭제
  void deleteCurrentList(String prefix, VoidCallback onSave) async {
    if (_todoLists.length <= 1) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('목록 삭제'),
        content: const Text('이 목록을 정말 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$prefix$_currentList');

      setState(() {
        _todoLists.remove(_currentList);
        _currentList = _todoLists.keys.first;
      });
      onSave();
    }
  }

  /// 새 목록 생성
  void showCreateListDialog(VoidCallback onCreate) {
    _listNameController.clear();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('새 목록 만들기'),
        content: TextField(
          controller: _listNameController,
          decoration: const InputDecoration(hintText: '목록 이름'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              final name = _listNameController.text.trim();
              if (name.isNotEmpty && !_todoLists.containsKey(name)) {
                setState(() {
                  _todoLists[name] = [];
                  _currentList = name;
                });
                onCreate();
              }
              Navigator.pop(context);
            },
            child: const Text('추가'),
          ),
        ],
      ),
    );
  }
}
