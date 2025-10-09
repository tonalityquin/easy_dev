import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../offline_type_package/offline_departure_request_page.dart';
import '../../offline_type_package/offline_parking_completed_page.dart';
import '../../offline_type_package/offline_parking_request_page.dart';
import 'offline_page_state.dart';

/// 앱 하단 탭(타입 페이지) 한 개의 메타 정보를 담는 모델
class OfflinePageInfo {
  /// 탭에 표시될 이름
  final String title;

  /// 데이터 소스 구분용 키 (ex: 입차요청/완료/출차요청)
  final PlateType collectionKey;

  /// 실제 화면을 생성하는 빌더
  final Widget Function(BuildContext context) builder;

  const OfflinePageInfo({
    required this.title,
    required this.collectionKey,
    required this.builder,
  });
}

/// 하단 탭 기본 구성 (HQ 관련 페이지는 제외)
final List<OfflinePageInfo> defaultPages = [
  OfflinePageInfo(
    title: '입차 요청',
    collectionKey: PlateType.parkingRequests,
    builder: (_) => const OfflineParkingRequestPage(),
  ),
  OfflinePageInfo(
    title: '홈',
    collectionKey: PlateType.parkingCompleted,
    builder: (context) {
      final offlinePageState = context.read<OfflinePageState>();
      return OfflineParkingCompletedPage(key: offlinePageState.parkingCompletedKey);
    },
  ),
  OfflinePageInfo(
    title: '출차 요청',
    collectionKey: PlateType.departureRequests,
    builder: (_) => const OfflineDepartureRequestPage(),
  ),
];

class OfflineHqPageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const OfflineHqPageInfo(this.title, this.page, this.icon);
}
