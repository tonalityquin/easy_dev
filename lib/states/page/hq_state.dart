import 'package:flutter/material.dart';
import 'page_info.dart';

class HqState with ChangeNotifier {
  int _selectedIndex = 2;
  List<HqPageInfo> _pages;
  bool _isLoading = false;

  int get selectedIndex => _selectedIndex;

  List<HqPageInfo> get pages => _pages;

  bool get isLoading => _isLoading;

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  HqState({required List<HqPageInfo> pages}) : _pages = pages;

  String get selectedPageTitle => _pages[_selectedIndex].title;

  void onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      throw ArgumentError('Invalid index: $index');
    }
    _selectedIndex = index;
    notifyListeners();
  }

  Future<void> refreshData() async {
    debugPrint('데이터 갱신 중...');
    await Future.delayed(const Duration(seconds: 2));
    debugPrint('데이터 갱신 완료!');
    notifyListeners();
  }

  void updatePages(List<HqPageInfo> newPages) {
    _pages = newPages;
    _selectedIndex = 0;
    notifyListeners();
  }
}
