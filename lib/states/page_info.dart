import 'package:flutter/material.dart';
import '../screens/type_pages/parking_request_page.dart'; // 입차 요청 페이지
import '../screens/type_pages/parking_completed_page.dart'; // 입차 완료 페이지
import '../screens/type_pages/departure_request_page.dart'; // 출차 요청 페이지
import '../screens/type_pages/departure_completed_page.dart'; // 출차 완료 페이지

/// 페이지 정보를 나타내는 클래스
/// - 각 페이지의 타이틀, 위젯, 아이콘 데이터를 포함
class PageInfo {
  final String title; // 페이지 타이틀
  final Widget page; // 페이지 위젯
  final IconData iconData; // 아이콘 데이터

  PageInfo(this.title, this.page, this.iconData);
}

/// 기본 페이지 데이터 목록
/// - 앱 내에서 탐색 가능한 페이지 정보를 관리
final List<Map<String, dynamic>> _pageData = [
  {
    'title': 'Parking Request',
    'page': const ParkingRequestPage(),
    'icon': Icons.directions_car,
  },
  {
    'title': 'Parking Completed',
    'page': const ParkingCompletedPage(),
    'icon': Icons.check_circle,
  },
  {
    'title': 'Departure Request',
    'page': const DepartureRequestPage(),
    'icon': Icons.departure_board,
  },
  {
    'title': 'Departure Completed',
    'page': const DepartureCompletedPage(),
    'icon': Icons.done_all,
  },
];

/// 기본 페이지 리스트
/// - `_pageData`를 기반으로 `PageInfo` 리스트 자동 생성
final List<PageInfo> defaultPages =
    _pageData.map((data) => PageInfo(data['title'], data['page'], data['icon'] as IconData)).toList();
