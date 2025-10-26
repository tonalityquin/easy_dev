import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../offline_type_package/offline_departure_request_page.dart';
import '../../offline_type_package/offline_parking_completed_page.dart';
import '../../offline_type_package/offline_parking_request_page.dart';
import 'offline_page_state.dart';

class OfflinePageInfo {
  final String title;

  final PlateType collectionKey;

  final Widget Function(BuildContext context) builder;

  const OfflinePageInfo({
    required this.title,
    required this.collectionKey,
    required this.builder,
  });
}

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
