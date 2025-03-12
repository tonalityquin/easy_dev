import 'package:flutter/material.dart';
import 'page_info.dart';

class PageState with ChangeNotifier {
  int _selectedIndex;
  final List<PageInfo> pages;
  bool _isLoading = false;

  int get selectedIndex => _selectedIndex;

  bool get isLoading => _isLoading;

  set isLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  PageState({required this.pages}) : _selectedIndex = pages.isNotEmpty ? 1 : throw Exception("🚨 페이지 리스트가 비어 있습니다.");

  String get selectedPageTitle => pages[_selectedIndex].title;

  void onItemTapped(int index, {void Function(String)? onError}) {
    if (index < 0 || index >= pages.length) {
      final error = '🚨 Invalid index: $index';
      debugPrint(error);
      if (onError != null) onError(error);
      return;
    }
    _selectedIndex = index;
    notifyListeners();
  }
}
