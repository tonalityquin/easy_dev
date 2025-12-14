import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';
import '../../screens/lite_mode/lite_hq_package/lite_dash_board.dart';
import 'lite_page_state.dart';

// ✅ 서비스 모드 기존 페이지 재사용
import '../../screens/service_mode/type_package/parking_completed_page.dart';

/// 라이트 타입 페이지 탭 메타
class LitePageInfo {
  final String title;
  final PlateType collectionKey;
  final Widget Function(BuildContext context) builder;

  const LitePageInfo({
    required this.title,
    required this.collectionKey,
    required this.builder,
  });
}

/// ✅ 하단 탭: "홈" 1개만 유지 (입차/출차 탭 제거)
final List<LitePageInfo> defaultPages = [
  LitePageInfo(
    title: '홈',
    collectionKey: PlateType.parkingCompleted,
    builder: (context) {
      final liteState = context.read<LitePageState>();
      return ParkingCompletedPage(key: liteState.parkingCompletedKey);
    },
  ),
];

/// ✅ LiteHqPageInfo 로직 유지
class LiteHqPageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const LiteHqPageInfo(this.title, this.page, this.icon);
}

/// ✅ HQ 페이지 목록 유지
final List<LiteHqPageInfo> liteHqPage = [
  const LiteHqPageInfo('LiteDashBoard', LiteDashBoard(), Icon(Icons.apartment)),
];
