import 'dart:async';
import 'package:flutter/material.dart';
import 'page_info.dart';

class PageState with ChangeNotifier {
  int _selectedIndex = 1;

  int get selectedIndex => _selectedIndex;

  final List<PageInfo> pages;

  Timer? _timer;
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  PageState({required this.pages}) {
    _startAutoRefresh();
  }

  void _startAutoRefresh() {
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      print('자동 상태 갱신 트리거됨: ${DateTime.now()}');
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get selectedPageTitle => pages[_selectedIndex].title;

  void onItemTapped(int index) {
    if (index < 0 || index >= pages.length) {
      throw ArgumentError('Invalid index: $index');
    }
    _selectedIndex = index;
    notifyListeners();
  }

  Future<void> refreshData() async {
    print('데이터 갱신 중...');
    await Future.delayed(Duration(seconds: 2));
    print('데이터 갱신 완료!');
    notifyListeners();
  }
}
