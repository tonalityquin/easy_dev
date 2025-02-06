import 'package:flutter/material.dart';
import 'page_info.dart'; // PageInfo 클래스 사용

/// 페이지 상태 관리 클래스
/// - 선택된 페이지, 로딩 상태, 페이지 전환 로직 관리
class PageState with ChangeNotifier {
  int _selectedIndex = 1; // 현재 선택된 페이지의 인덱스 (기본값: 1 - Parking Completed)

  // 현재 선택된 페이지 인덱스 반환
  int get selectedIndex => _selectedIndex;

  final List<PageInfo> pages; // 페이지 정보 리스트

  bool _isLoading = false; // 로딩 상태

  // 로딩 상태 반환
  bool get isLoading => _isLoading;

  /// 로딩 상태 설정 및 알림
  void setLoading(bool value) {
    if (_isLoading == value) return; // 🚀 값이 변경되지 않으면 리빌드 방지
    _isLoading = value;
    notifyListeners();
  }

  /// 생성자
  /// - [pages]: 관리할 페이지 정보 리스트
  PageState({required this.pages});

  /// 현재 선택된 페이지의 타이틀 반환
  String get selectedPageTitle => pages[_selectedIndex].title;

  /// 페이지 전환 처리
  /// - [index]: 선택된 페이지의 인덱스
  void onItemTapped(int index, {void Function(String)? onError}) {
    if (index < 0 || index >= pages.length) {
      final error = '🚨 Invalid index: $index';
      debugPrint(error);
      if (onError != null) onError(error); // 🚀 UI에서 사용자에게 알림 가능
      return;
    }
    _selectedIndex = index;
    notifyListeners();
  }
}
