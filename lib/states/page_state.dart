import 'dart:async'; // Timer 사용
import 'package:flutter/material.dart';
import 'page_info.dart';

/// 상태 관리 클래스 : 페이지 전환 로직
class PageState with ChangeNotifier {
  int _selectedIndex = 1; // 초기 선택된 탭 인덱스
  int get selectedIndex => _selectedIndex;

  final List<PageInfo> pages;

  Timer? _timer; // Timer 변수 추가
  bool _isLoading = false; // 로딩 상태 추가

  /// 로딩 상태 Getter
  bool get isLoading => _isLoading;

  /// 로딩 상태 Setter
  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners(); // 상태 변경 알림
  }

  /// 생성자에서 페이지 리스트 및 Timer 시작
  PageState({required this.pages}) {
    _startAutoRefresh();
  }

  /// 1분마다 상태 갱신
  void _startAutoRefresh() {
    _timer = Timer.periodic(const Duration(minutes: 1), (timer) {
      print('자동 상태 갱신 트리거됨: ${DateTime.now()}'); // 디버깅 로그
      notifyListeners(); // 상태 갱신 알림
    });
  }

  /// Timer 해제
  @override
  void dispose() {
    _timer?.cancel(); // Timer 해제
    super.dispose();
  }

  /// 현재 선택된 페이지 이름
  String get selectedPageTitle => pages[_selectedIndex].title;

  /// 탭 변경 시 호출
  void onItemTapped(int index) {
    if (index < 0 || index >= pages.length) {
      throw ArgumentError('Invalid index: $index');
    }
    _selectedIndex = index;
    notifyListeners(); // 상태 변경 알림
  }

  /// 데이터 갱신 메서드
  Future<void> refreshData() async {
    print('데이터 갱신 중...');
    await Future.delayed(Duration(seconds: 2)); // 테스트용 지연 시간
    print('데이터 갱신 완료!');
    notifyListeners(); // 상태 변경 알림
  }
}
