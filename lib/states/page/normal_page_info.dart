import 'package:flutter/material.dart';

import '../../enums/plate_type.dart';
import '../../screens/normal_mode/normal_hq_package/normal_dash_board.dart';
import '../../screens/normal_mode/normal_type_package/normal_parking_completed_page.dart';

/// 노말 타입 페이지 탭 메타
class NormalPageInfo {
  final String title;
  final PlateType collectionKey;
  final Widget Function(BuildContext context) builder;

  const NormalPageInfo({
    required this.title,
    required this.collectionKey,
    required this.builder,
  });
}

/// ✅ 하단 탭: "홈" 1개만 유지 (입차/출차 탭 제거)
/// ✅ 순환 참조 방지를 위해 NormalPageState를 import 하지 않습니다.
/// 필요한 GlobalKey는 NormalPageState에서 생성 후 여기로 "주입"합니다.
List<NormalPageInfo> buildNormalDefaultPages({
  required GlobalKey parkingCompletedKey,
}) {
  return <NormalPageInfo>[
    NormalPageInfo(
      title: '홈',
      collectionKey: PlateType.parkingCompleted,
      builder: (context) => NormalParkingCompletedPage(key: parkingCompletedKey),
    ),
  ];
}

/// ✅ HQ 페이지 메타
class NormalHqPageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const NormalHqPageInfo(this.title, this.page, this.icon);
}

/// ✅ HQ 페이지 목록 유지
final List<NormalHqPageInfo> normalHqPage = [
  const NormalHqPageInfo('NormalDashBoard', NormalDashBoard(), Icon(Icons.apartment)),
];
