import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../screens/type_package/parking_request_page.dart';
import '../../screens/type_package/parking_completed_page.dart';
import '../../screens/type_package/departure_request_page.dart';

import '../../screens/hq_package/management.dart';
import '../../screens/hq_package/human_resource.dart';
import '../../screens/hq_package/dash_board.dart';

import '../../enums/plate_type.dart';
import 'page_state.dart';

/// 앱 하단 탭(타입 페이지) 한 개의 메타 정보를 담는 모델
class PageInfo {
  /// 탭에 표시될 이름
  final String title;

  /// 데이터 소스 구분용 키 (ex: 입차요청/완료/출차요청)
  final PlateType collectionKey;

  /// 실제 화면을 생성하는 빌더
  final Widget Function(BuildContext context) builder;

  const PageInfo({
    required this.title,
    required this.collectionKey,
    required this.builder,
  });
}

/// 하단 탭 기본 구성 (HQ 관련 페이지는 제외)
final List<PageInfo> defaultPages = [
  PageInfo(
    title: '입차 요청',
    collectionKey: PlateType.parkingRequests,
    builder: (_) => const ParkingRequestPage(),
  ),
  PageInfo(
    title: '홈',
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
];

class HqPageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const HqPageInfo(this.title, this.page, this.icon);
}

final List<HqPageInfo> hqPage = [
  const HqPageInfo('HR', HumanResource(), Icon(Icons.people)),
  const HqPageInfo('DashBoard', DashBoard(), Icon(Icons.apartment)),
  const HqPageInfo('MGMT', Management(), Icon(Icons.manage_accounts)),
];
