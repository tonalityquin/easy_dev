import 'package:flutter/material.dart';
import 'double_page_info.dart';

class DoubleHqState with ChangeNotifier {
  final List<DoubleHqPageInfo> _pages;
  int _selectedIndex;
  bool _isLoading = false;

  DoubleHqState({required List<DoubleHqPageInfo> pages})
      : _pages = pages,
        _selectedIndex = pages.isNotEmpty ? 0 : -1;

  int get selectedIndex => _selectedIndex;
  List<DoubleHqPageInfo> get pages => _pages;
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
