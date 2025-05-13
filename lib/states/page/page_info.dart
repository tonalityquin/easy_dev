import 'package:flutter/material.dart';
import '../../screens/type_pages/parking_request_page.dart';
import '../../screens/type_pages/parking_completed_page.dart';
import '../../screens/type_pages/departure_request_page.dart';
import '../../screens/type_pages/departure_completed_page.dart';
import '../../screens/hq_pages/office_to_office.dart';
import '../../screens/hq_pages/office_to_field.dart';
import '../../screens/hq_pages/headquarter.dart';
import '../../enums/plate_type.dart';

class PageInfo {
  final String title;
  final Widget page;
  final PlateType collectionKey;

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
    collectionKey: PlateType.parkingRequests,
  ),
  PageInfo(
    title: '입차 완료',
    page: ParkingCompletedPage(),
    collectionKey: PlateType.parkingCompleted,
  ),
  PageInfo(
    title: '출차 요청',
    page: DepartureRequestPage(),
    collectionKey: PlateType.departureRequests,
  ),
  PageInfo(
    title: '출차 완료',
    page: DepartureCompletedPage(),
    collectionKey: PlateType.departureCompleted,
  ),
];

class HqPageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const HqPageInfo(this.title, this.page, this.icon);
}

/// 🔹 hq Pages
final List<HqPageInfo> hqPage = [
  HqPageInfo('오피스2필드', OfficeToField(), Icon(Icons.local_post_office)),
  HqPageInfo('헤드 쿼터', Headquarter(), Icon(Icons.view_headline)),
  HqPageInfo('오피스2오피스', OfficeToOffice(), Icon(Icons.work)),
];
