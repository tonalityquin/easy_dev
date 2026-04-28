import 'package:flutter/material.dart';
import '../../../../features/dashboard/pages/minor/widgets/minor_dash_board.dart';
import '../../../../screens/minor_mode/type_package/minor_parking_completed_page.dart';
import '../../../plate/domain/enums/plate_type.dart';

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

class MinorHqPageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const MinorHqPageInfo(this.title, this.page, this.icon);
}

final List<MinorHqPageInfo> minorHqPage = [
  const MinorHqPageInfo(
      'MinorDashBoard', MinorDashBoard(), Icon(Icons.apartment)),
];
