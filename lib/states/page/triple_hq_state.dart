import 'package:flutter/material.dart';
import 'triple_page_info.dart';

class TripleHqState with ChangeNotifier {
  final List<TripleHqPageInfo> _pages;
  int _selectedIndex;
  bool _isLoading = false;

  TripleHqState({required List<TripleHqPageInfo> pages})
      : _pages = pages,
        _selectedIndex = pages.isNotEmpty ? 0 : -1;

  int get selectedIndex => _selectedIndex;
  List<TripleHqPageInfo> get pages => _pages;
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
