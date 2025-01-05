import 'package:flutter/material.dart';
import '../screens/type_pages/parking_request_page.dart';
import '../screens/type_pages/parking_completed_page.dart';
import '../screens/type_pages/departure_request_page.dart';
import '../screens/type_pages/departure_completed_page.dart';

/// 페이지 정보 클래스
class PageInfo {
  final String title;
  final Widget page;
  final Icon icon; // 아이콘 추가

  PageInfo(this.title, this.page, this.icon);
}

/// 상태 관리 클래스 : 페이지 전환 로직
class PageState with ChangeNotifier {
  int _selectedIndex = 1; // 초기 선택된 탭 인덱스
  int get selectedIndex => _selectedIndex;

  final List<PageInfo> pages = [
    PageInfo('Parking Request', const ParkingRequestPage(), Icon(Icons.directions_car)),
    PageInfo('Parking Completed', const ParkingCompletedPage(), Icon(Icons.check_circle)),
    PageInfo('Departure Request', const DepartureRequestPage(), Icon(Icons.departure_board)),
    PageInfo('Departure Completed', const DepartureCompletedPage(), Icon(Icons.done_all)),
  ];

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
}
