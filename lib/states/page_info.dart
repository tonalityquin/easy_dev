import 'package:flutter/material.dart';
import '../screens/type_pages/parking_request_page.dart'; // 입차 요청 페이지
import '../screens/type_pages/parking_completed_page.dart'; // 입차 완료 페이지
import '../screens/type_pages/departure_request_page.dart'; // 출차 요청 페이지
import '../screens/type_pages/departure_completed_page.dart'; // 출차 완료 페이지

/// 페이지 정보를 나타내는 클래스
/// - 각 페이지의 타이틀, 위젯, 아이콘 정보를 포함
class PageInfo {
  final String title; // 페이지 타이틀
  final Widget page; // 페이지 위젯
  final Icon icon; // 페이지를 나타내는 아이콘

  /// PageInfo 생성자
  /// - [title]: 페이지 이름
  /// - [page]: 해당 페이지 위젯
  /// - [icon]: 페이지를 나타내는 아이콘
  PageInfo(this.title, this.page, this.icon);
}

/// 기본 페이지 리스트
/// - 앱 내에서 탐색 가능한 페이지 정보 목록
final List<PageInfo> defaultPages = [
  // 입차 요청 페이지
  PageInfo(
    'Parking Request', // 페이지 이름
    const ParkingRequestPage(), // 위젯
    Icon(Icons.directions_car), // 아이콘
  ),

  // 입차 완료 페이지
  PageInfo(
    'Parking Completed', // 페이지 이름
    const ParkingCompletedPage(), // 위젯
    Icon(Icons.check_circle), // 아이콘
  ),

  // 출차 요청 페이지
  PageInfo(
    'Departure Request', // 페이지 이름
    const DepartureRequestPage(), // 위젯
    Icon(Icons.departure_board), // 아이콘
  ),

  // 출차 완료 페이지
  PageInfo(
    'Departure Completed', // 페이지 이름
    const DepartureCompletedPage(), // 위젯
    Icon(Icons.done_all), // 아이콘
  ),
];
