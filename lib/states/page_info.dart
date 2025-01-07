import 'package:flutter/material.dart';
import '../screens/type_pages/parking_request_page.dart';
import '../screens/type_pages/parking_completed_page.dart';
import '../screens/type_pages/departure_request_page.dart';
import '../screens/type_pages/departure_completed_page.dart';

/// 페이지 정보 클래스
class PageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  PageInfo(this.title, this.page, this.icon);
}

/// 페이지 리스트 상수
final List<PageInfo> defaultPages = [
  PageInfo('Parking Request', const ParkingRequestPage(), Icon(Icons.directions_car)),
  PageInfo('Parking Completed', const ParkingCompletedPage(), Icon(Icons.check_circle)),
  PageInfo('Departure Request', const DepartureRequestPage(), Icon(Icons.departure_board)),
  PageInfo('Departure Completed', const DepartureCompletedPage(), Icon(Icons.done_all)),
];
