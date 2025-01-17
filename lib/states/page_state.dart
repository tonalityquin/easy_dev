import 'package:flutter/material.dart';
import 'page_info.dart'; // PageInfo 클래스 사용

/// **PageState 클래스**
/// - 앱의 페이지 상태를 관리하는 클래스
/// - 현재 선택된 페이지와 로딩 상태를 처리
class PageState with ChangeNotifier {
  int _selectedIndex = 1; // 현재 선택된 페이지의 인덱스, 기본값은 1 (Parking Completed)

  /// **현재 선택된 페이지의 인덱스**
  int get selectedIndex => _selectedIndex;

  final List<PageInfo> pages; // 페이지 정보 리스트

  bool _isLoading = false; // 로딩 상태

  /// **현재 로딩 상태**
  bool get isLoading => _isLoading;

  /// **로딩 상태 업데이트**
  /// - [value]: 새로운 로딩 상태 값 (true 또는 false)
  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners(); // 상태 변경 알림
  }

  /// **PageState 생성자**
  /// - [pages]: 앱의 페이지 리스트를 받아 초기화
  PageState({required this.pages});

  /// **리소스 정리**
  /// - 부모 클래스의 dispose 호출
  @override
  void dispose() {
    super.dispose();
  }

  /// **현재 선택된 페이지의 타이틀 반환**
  String get selectedPageTitle => pages[_selectedIndex].title;

  /// **페이지 탭 처리**
  /// - [index]: 선택된 페이지의 인덱스
  /// - 잘못된 인덱스가 입력되면 예외 발생
  void onItemTapped(int index) {
    if (index < 0 || index >= pages.length) {
      throw ArgumentError('Invalid index: $index'); // 유효하지 않은 인덱스 처리
    }
    _selectedIndex = index; // 선택된 페이지 업데이트
    notifyListeners(); // 상태 변경 알림
  }
}
