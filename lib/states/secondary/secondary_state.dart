// lib/states/secondary/secondary_state.dart
//
// 하단 탭(Secondary) 상태: 선택 인덱스와 페이지 목록 관리
//
import 'package:flutter/material.dart';
import 'secondary_info.dart';

class SecondaryState with ChangeNotifier {
  int _selectedIndex = 0;
  List<SecondaryInfo> _pages;
  final bool _isLoading = false; // ✅ final로 유지

  SecondaryState({required List<SecondaryInfo> pages}) : _pages = pages;

  int get selectedIndex => _selectedIndex;

  List<SecondaryInfo> get pages => _pages;

  bool get isLoading => _isLoading;

  void onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      debugPrint('⚠️ 잘못된 인덱스 접근: $index');
      return;
    }
    if (_selectedIndex != index) {
      _selectedIndex = index;
      notifyListeners();
    }
  }

  void updatePages(List<SecondaryInfo> newPages, {bool keepIndex = false}) {
    _pages = newPages;
    if (!keepIndex || _selectedIndex >= newPages.length) {
      _selectedIndex = 0;
    }
    notifyListeners();
  }
}
