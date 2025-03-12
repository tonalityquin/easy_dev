import 'package:flutter/material.dart';
import '../screens/type_pages/parking_request_page.dart';
import '../screens/type_pages/parking_completed_page.dart';
import '../screens/type_pages/departure_request_page.dart';
import '../screens/type_pages/departure_completed_page.dart';

class PageInfo {
  final String title;
  final Widget page;
  final IconData iconData;

  const PageInfo({
    required this.title,
    required this.page,
    required this.iconData,
  });
}

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
