import 'package:flutter/material.dart';
import '../screens/type_pages/parking_request_page.dart'; // 입차 요청 페이지
import '../screens/type_pages/parking_completed_page.dart'; // 입차 완료 페이지
import '../screens/type_pages/departure_request_page.dart'; // 출차 요청 페이지
import '../screens/type_pages/departure_completed_page.dart'; // 출차 완료 페이지

/// **PageInfo 클래스**
/// - 화면 정보를 저장하는 데이터 클래스
/// - 각 화면의 타이틀, 페이지 위젯, 아이콘을 포함
class PageInfo {
  final String title; // 페이지 타이틀
  final Widget page; // 해당 페이지 위젯
  final Icon icon; // 페이지를 나타내는 아이콘

  /// **PageInfo 생성자**
  /// - [title]: 페이지의 제목
  /// - [page]: 페이지를 렌더링할 위젯
  /// - [icon]: 페이지 아이콘
  PageInfo(this.title, this.page, this.icon);
}

/// **기본 페이지 목록 정의**
/// - 앱에서 사용되는 각 페이지의 정보를 포함
final List<PageInfo> defaultPages = [
  // 입차 요청 페이지
  PageInfo(
    'Parking Request', // 타이틀
    const ParkingRequestPage(), // 위젯
    Icon(Icons.directions_car), // 아이콘
  ),

  // 입차 완료 페이지
  PageInfo(
    'Parking Completed', // 타이틀
    const ParkingCompletedPage(), // 위젯
    Icon(Icons.check_circle), // 아이콘
  ),

  // 출차 요청 페이지
  PageInfo(
    'Departure Request', // 타이틀
    const DepartureRequestPage(), // 위젯
    Icon(Icons.departure_board), // 아이콘
  ),

  // 출차 완료 페이지
  PageInfo(
    'Departure Completed', // 타이틀
    const DepartureCompletedPage(), // 위젯
    Icon(Icons.done_all), // 아이콘
  ),
];
