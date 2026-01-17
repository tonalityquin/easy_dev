import 'package:flutter/material.dart';

import '../../enums/plate_type.dart';
import '../../screens/triple_mode/hq_package/triple_dash_board.dart';
import '../../screens/triple_mode/type_package/triple_parking_completed_page.dart';

/// 노말 타입 페이지 탭 메타
class TriplePageInfo {
  final String title;
  final PlateType collectionKey;
  final Widget Function(BuildContext context) builder;

  const TriplePageInfo({
    required this.title,
    required this.collectionKey,
    required this.builder,
  });
}

/// ✅ 하단 탭: "홈" 1개만 유지 (입차/출차 탭 제거)
/// ✅ 순환 참조 방지를 위해 TriplePageState를 import 하지 않습니다.
/// 필요한 GlobalKey는 TriplePageState에서 생성 후 여기로 "주입"합니다.
List<TriplePageInfo> buildTripleDefaultPages({
  required GlobalKey parkingCompletedKey,
}) {
  return <TriplePageInfo>[
    TriplePageInfo(
      title: '홈',
      collectionKey: PlateType.parkingCompleted,
      builder: (context) => TripleParkingCompletedPage(key: parkingCompletedKey),
    ),
  ];
}

/// ✅ HQ 페이지 메타
class TripleHqPageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const TripleHqPageInfo(this.title, this.page, this.icon);
}

/// ✅ HQ 페이지 목록 유지
final List<TripleHqPageInfo> tripleHqPage = [
  const TripleHqPageInfo('TripleDashBoard', TripleDashBoard(), Icon(Icons.apartment)),
];
