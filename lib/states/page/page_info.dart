import 'package:flutter/material.dart';
import '../../screens/type_pages/parking_request_page.dart';
import '../../screens/type_pages/parking_completed_page.dart';
import '../../screens/type_pages/departure_request_page.dart';
import '../../screens/type_pages/departure_completed_page.dart';
import '../../enums/plate_collection.dart';

class PageInfo {
  final String title;
  final Widget page;
  final PlateCollection collectionKey;

  const PageInfo({
    required this.title,
    required this.page,
    required this.collectionKey,
  });
}

const List<PageInfo> defaultPages = [
  PageInfo(
    title: '입차 요청',
    page: ParkingRequestPage(),
    collectionKey: PlateCollection.parkingRequests,
  ),
  PageInfo(
    title: '입차 완료',
    page: ParkingCompletedPage(),
    collectionKey: PlateCollection.parkingCompleted,
  ),
  PageInfo(
    title: '출차 요청',
    page: DepartureRequestPage(),
    collectionKey: PlateCollection.departureRequests,
  ),
  PageInfo(
    title: '출차 완료',
    page: DepartureCompletedPage(),
    collectionKey: PlateCollection.departureCompleted,
  ),
];
