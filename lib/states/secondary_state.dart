import 'package:flutter/material.dart';
import 'secondary_info.dart'; // SecondaryInfo 클래스 사용

class SecondaryState with ChangeNotifier {
  int _selectedIndex = 0; // 현재 선택된 페이지의 인덱스
  List<SecondaryInfo> _pages; // 페이지 정보 리스트
  bool _isLoading = false; // 로딩 상태

  /// 현재 선택된 페이지의 인덱스
  int get selectedIndex => _selectedIndex;

  /// 현재 페이지 리스트
  List<SecondaryInfo> get pages => _pages;

  /// 현재 로딩 상태
  bool get isLoading => _isLoading;

  /// 로딩 상태 업데이트
  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  /// SecondaryState 생성자
  SecondaryState({required List<SecondaryInfo> pages}) : _pages = pages;

  /// 현재 선택된 페이지의 타이틀 반환
  String get selectedPageTitle => _pages[_selectedIndex].title;

  /// 페이지 탭 처리
  void onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      throw ArgumentError('Invalid index: $index');
    }
    _selectedIndex = index;
    notifyListeners();
  }

  /// 데이터 갱신 메서드
  Future<void> refreshData() async {
    print('데이터 갱신 중...');
    await Future.delayed(const Duration(seconds: 2));
    print('데이터 갱신 완료!');
    notifyListeners();
  }

  /// 페이지 리스트 업데이트
  void updatePages(List<SecondaryInfo> newPages) {
    _pages = newPages;
    _selectedIndex = 0;
    notifyListeners();
  }
}
