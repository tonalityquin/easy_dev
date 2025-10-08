import 'package:flutter/material.dart';
import 'offline_page_info.dart';

class OfflineHqState with ChangeNotifier {
  final List<OfflineHqPageInfo> _pages; // ✅ final
  int _selectedIndex;
  final bool _isLoading = false; // ✅ final

  OfflineHqState({required List<OfflineHqPageInfo> pages})
      : _pages = pages,
        _selectedIndex = pages.isNotEmpty ? 1 : -1;

  int get selectedIndex => _selectedIndex;
  List<OfflineHqPageInfo> get pages => _pages;
  bool get isLoading => _isLoading;

  void onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      throw ArgumentError('Invalid index: $index');
    }
    _selectedIndex = index;
    notifyListeners();
  }
}