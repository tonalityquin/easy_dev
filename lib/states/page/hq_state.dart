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

  void onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      throw ArgumentError('Invalid index: $index');
    }
    _selectedIndex = index;
    notifyListeners();
  }
}
