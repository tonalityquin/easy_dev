import 'package:flutter/material.dart';
import 'secondary_info.dart'; // SecondaryInfo 클래스 사용

/// SecondaryState
/// - 페이지 전환 및 로딩 상태를 관리
/// - 선택된 페이지 및 데이터 갱신 기능 제공
class SecondaryState with ChangeNotifier {
  int _selectedIndex = 0; // 현재 선택된 페이지의 인덱스
  List<SecondaryInfo> _pages; // 페이지 정보 리스트
  bool _isLoading = false; // 로딩 상태

  /// 현재 선택된 페이지의 인덱스 반환
  int get selectedIndex => _selectedIndex;

  /// 현재 페이지 리스트 반환
  List<SecondaryInfo> get pages => _pages;

  /// 현재 로딩 상태 반환
  bool get isLoading => _isLoading;

  /// 로딩 상태 업데이트
  /// - [value]: 새로운 로딩 상태
  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners(); // 상태 변경 알림
  }

  /// SecondaryState 생성자
  /// - [pages]: 초기 페이지 리스트
  SecondaryState({required List<SecondaryInfo> pages}) : _pages = pages;

  /// 현재 선택된 페이지의 타이틀 반환
  String get selectedPageTitle => _pages[_selectedIndex].title;

  /// 페이지 전환 처리
  /// - [index]: 새로 선택된 페이지 인덱스
  /// - 유효하지 않은 인덱스 입력 시 에러 발생
  void onItemTapped(int index) {
    if (index < 0 || index >= _pages.length) {
      throw ArgumentError('Invalid index: $index');
    }
    _selectedIndex = index;
    notifyListeners(); // 상태 변경 알림
  }

  /// 데이터 갱신
  /// - 비동기적으로 데이터를 갱신하고 알림
  Future<void> refreshData() async {
    print('데이터 갱신 중...');
    await Future.delayed(const Duration(seconds: 2)); // 데이터 갱신 시뮬레이션
    print('데이터 갱신 완료!');
    notifyListeners(); // 상태 변경 알림
  }

  /// 페이지 리스트 업데이트
  /// - [newPages]: 새로운 페이지 리스트
  /// - 새 리스트로 업데이트하고 선택된 페이지를 초기화
  void updatePages(List<SecondaryInfo> newPages) {
    _pages = newPages;
    _selectedIndex = 0; // 페이지 선택 초기화
    notifyListeners(); // 상태 변경 알림
  }
}
