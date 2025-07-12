import 'package:flutter/material.dart';
import 'secondary_info.dart';

class SecondaryState with ChangeNotifier {
  int _selectedIndex = 0;
  List<SecondaryInfo> _pages;
  bool _isLoading = false;

  SecondaryState({required List<SecondaryInfo> pages}) : _pages = pages;

  /// ✅ 현재 선택된 인덱스
  int get selectedIndex => _selectedIndex;

  /// ✅ 현재 페이지 리스트
  List<SecondaryInfo> get pages => _pages;

  /// ✅ 현재 로딩 여부
  bool get isLoading => _isLoading;

  /// ✅ 현재 선택된 페이지의 제목
  String get selectedPageTitle =>
      (_selectedIndex >= 0 && _selectedIndex < _pages.length)
          ? _pages[_selectedIndex].title
          : '';

  /// ✅ 로딩 상태 설정
  void setLoading(bool value) {
    if (_isLoading == value) return;
    _isLoading = value;
    notifyListeners();
  }

  /// ✅ 인덱스 기반 페이지 선택
  void onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      debugPrint('⚠️ 잘못된 인덱스 접근: $index');
      return;
    }

    if (_selectedIndex != index) {
      _selectedIndex = index;
      notifyListeners();
    }
  }

  /// ✅ 페이지 리스트 업데이트
  void updatePages(List<SecondaryInfo> newPages, {bool keepIndex = false}) {
    _pages = newPages;

    if (!keepIndex || _selectedIndex >= newPages.length) {
      _selectedIndex = 0;
    }

    notifyListeners();
  }

  /// ✅ 새로고침 로직 (예시)
  Future<void> refreshData() async {
    setLoading(true);

    try {
      debugPrint('🔄 데이터 갱신 중...');
      await Future.delayed(const Duration(seconds: 2));
      debugPrint('✅ 데이터 갱신 완료!');
    } catch (e) {
      debugPrint('🚨 데이터 갱신 실패: $e');
    } finally {
      setLoading(false);
    }
  }
}
