import 'package:flutter/material.dart';
import 'page_info.dart';

class HqState with ChangeNotifier {
  int _selectedIndex;
  List<HqPageInfo> _pages;
  bool _isLoading = false;

  HqState({required List<HqPageInfo> pages})
      : _pages = pages,
        _selectedIndex = pages.isNotEmpty ? 1 : -1;

  int get selectedIndex => _selectedIndex;

  List<HqPageInfo> get pages => _pages;

  bool get isLoading => _isLoading;

  String get selectedPageTitle =>
      (_selectedIndex >= 0 && _selectedIndex < _pages.length)
          ? _pages[_selectedIndex].title
          : '페이지 없음';

  /// 로딩 상태 갱신
  void setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  /// 페이지 인덱스 변경
  void onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      throw ArgumentError('Invalid index: $index');
    }
    _selectedIndex = index;
    notifyListeners();
  }

  /// 데이터 새로고침 시뮬레이션
  Future<void> refreshData() async {
    debugPrint('📡 데이터 갱신 중...');
    await Future.delayed(const Duration(seconds: 2));
    debugPrint('✅ 데이터 갱신 완료!');
    notifyListeners();
  }

  /// 페이지 목록 갱신 및 선택 인덱스 조정
  void updatePages(List<HqPageInfo> newPages) {
    _pages = newPages;
    if (_selectedIndex >= _pages.length) {
      _selectedIndex = _pages.isNotEmpty ? 0 : -1;
    }
    notifyListeners();
  }
}
