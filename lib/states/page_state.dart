import 'package:flutter/material.dart';
import '../screens/type_pages/parking_request_page.dart';
import '../screens/type_pages/parking_completed_page.dart';
import '../screens/type_pages/departure_request_page.dart';
import '../screens/type_pages/departure_completed_page.dart';

/// 상태 관리 클래스 : 페이지 전환 로직
class PageState with ChangeNotifier {
  int _selectedIndex = 1; // 초기 선택된 탭 인덱스
  int get selectedIndex => _selectedIndex;

  final List<Widget> pages = [
    const ParkingRequestPage(),
    const ParkingCompletedPage(),
    const DepartureRequestPage(),
    const DepartureCompletedPage(),
  ];

  /// 탭 변경 시 호출
  void onItemTapped(int index) {
    _selectedIndex = index;
    notifyListeners(); // 상태 변경 알림
  }
}
