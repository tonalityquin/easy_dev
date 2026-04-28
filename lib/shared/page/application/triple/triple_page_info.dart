import 'package:flutter/material.dart';
import '../../../../features/dashboard/pages/triple/widgets/triple_dash_board.dart';
import '../../../../screens/triple_mode/type_package/triple_parking_completed_page.dart';
import '../../../plate/domain/enums/plate_type.dart';

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

List<TriplePageInfo> buildTripleDefaultPages({
  required GlobalKey parkingCompletedKey,
}) {
  return <TriplePageInfo>[
    TriplePageInfo(
      title: '홈',
      collectionKey: PlateType.parkingCompleted,
      builder: (context) =>
          TripleParkingCompletedPage(key: parkingCompletedKey),
    ),
  ];
}

class TripleHqPageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const TripleHqPageInfo(this.title, this.page, this.icon);
}

final List<TripleHqPageInfo> tripleHqPage = [
  const TripleHqPageInfo(
      'TripleDashBoard', TripleDashBoard(), Icon(Icons.apartment)),
];
