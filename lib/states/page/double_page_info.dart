import 'package:flutter/material.dart';

import '../../enums/plate_type.dart';
import '../../screens/double_mode/hq_package/double_dash_board.dart';
import '../../screens/double_mode/type_package/double_parking_completed_page.dart';

class DoublePageInfo {
  final String title;
  final PlateType collectionKey;
  final Widget Function(BuildContext context) builder;

  const DoublePageInfo({
    required this.title,
    required this.collectionKey,
    required this.builder,
  });
}

/// ✅ 하단 탭: "홈" 1개만 유지 (입차/출차 탭 제거)
/// ✅ 순환 참조 방지를 위해 DoublePageState를 import 하지 않습니다.
/// 필요한 GlobalKey는 DoublePageState에서 생성 후 여기로 "주입"합니다.
List<DoublePageInfo> buildDoubleDefaultPages({
  required GlobalKey parkingCompletedKey,
}) {
  return <DoublePageInfo>[
    DoublePageInfo(
      title: '홈',
      collectionKey: PlateType.parkingCompleted,
      builder: (context) => DoubleParkingCompletedPage(key: parkingCompletedKey),
    ),
  ];
}

/// ✅ HQ 페이지 메타
class DoubleHqPageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const DoubleHqPageInfo(this.title, this.page, this.icon);
}

/// ✅ HQ 페이지 목록 유지
final List<DoubleHqPageInfo> doubleHqPage = [
  const DoubleHqPageInfo('DoubleDashBoard', DoubleDashBoard(), Icon(Icons.apartment)),
];
