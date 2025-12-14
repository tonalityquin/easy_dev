import 'package:flutter/material.dart';
import 'lite_page_info.dart';

class LiteHqState with ChangeNotifier {
  final List<LiteHqPageInfo> _pages;
  int _selectedIndex;
  bool _isLoading = false;

  LiteHqState({required List<LiteHqPageInfo> pages})
      : _pages = pages,
        _selectedIndex = pages.isNotEmpty ? 0 : -1;

  int get selectedIndex => _selectedIndex;
  List<LiteHqPageInfo> get pages => _pages;
  bool get isLoading => _isLoading;

  set isLoading(bool value) {
    if (_isLoading != value) {
      _isLoading = value;
      notifyListeners();
    }
  }

  void onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      throw ArgumentError('Invalid index: $index');
    }
    _selectedIndex = index;
    notifyListeners();
  }
}
