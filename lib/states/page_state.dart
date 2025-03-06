import 'package:flutter/material.dart';
import 'page_info.dart'; // PageInfo 클래스 사용

/// **페이지 상태 관리 클래스**
/// - 선택된 페이지, 로딩 상태, 페이지 전환 로직 관리
class PageState with ChangeNotifier {
  int _selectedIndex; // ✅ 기본값 설정 (late final 제거)
  final List<PageInfo> pages;
  bool _isLoading = false;

  /// **현재 선택된 페이지 인덱스 반환**
  int get selectedIndex => _selectedIndex;

  /// **로딩 상태 반환**
  bool get isLoading => _isLoading;

  /// **로딩 상태 변경**
  set isLoading(bool value) {
    if (_isLoading == value) return; // 🚀 값이 변경되지 않으면 리빌드 방지
    _isLoading = value;
    notifyListeners();
  }

  /// **생성자**
  /// - 기본적으로 첫 번째 페이지(1) 선택
  /// - 페이지 리스트가 비어 있으면 예외 발생
  PageState({required this.pages}) : _selectedIndex = pages.isNotEmpty ? 1 : throw Exception("🚨 페이지 리스트가 비어 있습니다.");

  /// **현재 선택된 페이지의 타이틀 반환**
  String get selectedPageTitle => pages[_selectedIndex].title;

  /// **페이지 전환 처리**
  /// - [index]: 선택된 페이지의 인덱스
  /// - 유효하지 않은 인덱스는 예외 발생
  void onItemTapped(int index, {void Function(String)? onError}) {
    if (index < 0 || index >= pages.length) {
      final error = '🚨 Invalid index: $index';
      debugPrint(error);
      if (onError != null) onError(error); // 🚀 UI에서 사용자에게 알림 가능
      return;
    }
    _selectedIndex = index; // ✅ 이제 문제 없이 변경 가능
    notifyListeners();
  }
}
