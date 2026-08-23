import 'package:flutter/material.dart';

import '../../../../shared/page/application/single/single_page_info.dart';

class SingleHqState with ChangeNotifier {
  SingleHqState({required List<SingleHqPageInfo> pages})
      : _pages = pages,
        _selectedIndex = pages.isNotEmpty ? 0 : -1;

  final List<SingleHqPageInfo> _pages;
  int _selectedIndex;
  bool _isLoading = false;

  int get selectedIndex => _selectedIndex;
  List<SingleHqPageInfo> get pages => _pages;
  bool get isLoading => _isLoading;

  set isLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  void onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      throw ArgumentError('Invalid index: $index');
    }
    _selectedIndex = index;
    notifyListeners();
  }
}
