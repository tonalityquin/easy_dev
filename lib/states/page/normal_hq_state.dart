import 'package:flutter/material.dart';
import 'normal_page_info.dart';

class NormalHqState with ChangeNotifier {
  final List<NormalHqPageInfo> _pages;
  int _selectedIndex;
  bool _isLoading = false;

  NormalHqState({required List<NormalHqPageInfo> pages})
      : _pages = pages,
        _selectedIndex = pages.isNotEmpty ? 0 : -1;

  int get selectedIndex => _selectedIndex;
  List<NormalHqPageInfo> get pages => _pages;
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
