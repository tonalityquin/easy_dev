import 'package:flutter/material.dart';

import '../../enums/plate_type.dart';
import '../../screens/lite_mode/lite_hq_package/lite_dash_board.dart';
import '../../screens/lite_mode/lite_type_package/lite_parking_completed_page.dart';

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
/// ✅ 순환 참조 방지를 위해 LitePageState를 import 하지 않습니다.
/// 필요한 GlobalKey는 LitePageState에서 생성 후 여기로 "주입"합니다.
List<LitePageInfo> buildLiteDefaultPages({
  required GlobalKey parkingCompletedKey,
}) {
  return <LitePageInfo>[
    LitePageInfo(
      title: '홈',
      collectionKey: PlateType.parkingCompleted,
      builder: (context) => LiteParkingCompletedPage(key: parkingCompletedKey),
    ),
  ];
}

/// ✅ HQ 페이지 메타
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
