import 'package:flutter/material.dart';
import '../screens/type_pages/parking_request_page.dart'; // 입차 요청 페이지
import '../screens/type_pages/parking_completed_page.dart'; // 입차 완료 페이지
import '../screens/type_pages/departure_request_page.dart'; // 출차 요청 페이지
import '../screens/type_pages/departure_completed_page.dart'; // 출차 완료 페이지

/// **페이지 정보를 나타내는 모델 클래스**
/// - 각 페이지의 **타이틀(title)**, **페이지 위젯(page)**, **아이콘(iconData)**을 포함
class PageInfo {
  final String title; // 페이지 타이틀
  final Widget page; // 페이지 위젯
  final IconData iconData; // 아이콘 데이터

  const PageInfo({
    required this.title,
    required this.page,
    required this.iconData,
  });
}

/// **기본 페이지 리스트 (정적 리스트)**
/// - `const` 적용하여 앱 실행 중 변경 불가능 (불변 리스트)
const List<PageInfo> defaultPages = [
  PageInfo(
    title: 'Parking Request',
    page: ParkingRequestPage(),
    iconData: Icons.directions_car,
  ),
  PageInfo(
    title: 'Parking Completed',
    page: ParkingCompletedPage(),
    iconData: Icons.check_circle,
  ),
  PageInfo(
    title: 'Departure Request',
    page: DepartureRequestPage(),
    iconData: Icons.departure_board,
  ),
  PageInfo(
    title: 'Departure Completed',
    page: DepartureCompletedPage(),
    iconData: Icons.done_all,
  ),
];
