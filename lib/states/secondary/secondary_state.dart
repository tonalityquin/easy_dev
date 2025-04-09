import 'package:flutter/material.dart';
import 'secondary_info.dart';

class SecondaryState with ChangeNotifier {
  int _selectedIndex = 0;
  List<SecondaryInfo> _pages;
  bool _isLoading = false;

  int get selectedIndex => _selectedIndex;

  List<SecondaryInfo> get pages => _pages;

  bool get isLoading => _isLoading;

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  SecondaryState({required List<SecondaryInfo> pages}) : _pages = pages;

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

  void updatePages(List<SecondaryInfo> newPages) {
    _pages = newPages;
    _selectedIndex = 0;
    notifyListeners();
  }
}
