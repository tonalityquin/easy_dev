import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/type_pages/parking_request_page.dart';
import '../../screens/type_pages/parking_completed_page.dart';
import '../../screens/type_pages/departure_request_page.dart';
import '../../screens/type_pages/departure_completed_page.dart';

import '../../screens/hq_pages/management.dart';
import '../../screens/hq_pages/human_resource.dart';
import '../../screens/hq_pages/head_quarter.dart';

import '../../enums/plate_type.dart';
import 'page_state.dart';

/// ✅ PageInfo를 builder 패턴으로 변경
class PageInfo {
  final String title;
  final PlateType collectionKey;
  final Widget Function(BuildContext context) builder;

  const PageInfo({
    required this.title,
    required this.collectionKey,
    required this.builder,
  });
}

/// ✅ defaultPages에서 builder로 구성
final List<PageInfo> defaultPages = [
  PageInfo(
    title: '입차 요청',
    collectionKey: PlateType.parkingRequests,
    builder: (_) => const ParkingRequestPage(),
  ),
  PageInfo(
    title: '입차 완료',
    collectionKey: PlateType.parkingCompleted,
    builder: (context) {
      final pageState = context.read<PageState>();
      return ParkingCompletedPage(key: pageState.parkingCompletedKey);
    },
  ),
  PageInfo(
    title: '출차 요청',
    collectionKey: PlateType.departureRequests,
    builder: (_) => const DepartureRequestPage(),
  ),
  PageInfo(
    title: '출차 완료',
    collectionKey: PlateType.departureCompleted,
    builder: (_) => const DepartureCompletedPage(),
  ),
];

/// ✅ 본사(HQ) 전용 페이지 정보
class HqPageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const HqPageInfo(this.title, this.page, this.icon);
}

final List<HqPageInfo> hqPage = [
  const HqPageInfo('HR', HumanResource(), Icon(Icons.people)),
  const HqPageInfo('HQ', HeadQuarter(), Icon(Icons.apartment)),
  const HqPageInfo('MGMT', Management(), Icon(Icons.manage_accounts)),
];
