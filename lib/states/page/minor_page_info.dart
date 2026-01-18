import 'package:flutter/material.dart';

import '../../enums/plate_type.dart';
import '../../screens/minor_mode/hq_package/minor_dash_board.dart';
import '../../screens/minor_mode/type_package/minor_parking_completed_page.dart';

/// 노말 타입 페이지 탭 메타
class MinorPageInfo {
  final String title;
  final PlateType collectionKey;
  final Widget Function(BuildContext context) builder;

  const MinorPageInfo({
    required this.title,
    required this.collectionKey,
    required this.builder,
  });
}

/// ✅ 하단 탭: "홈" 1개만 유지 (입차/출차 탭 제거)
/// ✅ 순환 참조 방지를 위해 MinorPageState를 import 하지 않습니다.
/// 필요한 GlobalKey는 MinorPageState에서 생성 후 여기로 "주입"합니다.
List<MinorPageInfo> buildMinorDefaultPages({
  required GlobalKey parkingCompletedKey,
}) {
  return <MinorPageInfo>[
    MinorPageInfo(
      title: '홈',
      collectionKey: PlateType.parkingCompleted,
      builder: (context) => MinorParkingCompletedPage(key: parkingCompletedKey),
    ),
  ];
}

/// ✅ HQ 페이지 메타
class MinorHqPageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const MinorHqPageInfo(this.title, this.page, this.icon);
}

/// ✅ HQ 페이지 목록 유지
final List<MinorHqPageInfo> minorHqPage = [
  const MinorHqPageInfo('MinorDashBoard', MinorDashBoard(), Icon(Icons.apartment)),
];
