import 'package:flutter/material.dart';
import '../../../../features/dashboard/pages/double/widgets/double_dash_board.dart';
import '../../../../screens/double_mode/type_package/double_parking_completed_page.dart';
import '../../../plate/domain/enums/plate_type.dart';

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

List<DoublePageInfo> buildDoubleDefaultPages({
  required GlobalKey parkingCompletedKey,
}) {
  return <DoublePageInfo>[
    DoublePageInfo(
      title: '홈',
      collectionKey: PlateType.parkingCompleted,
      builder: (context) =>
          DoubleParkingCompletedPage(key: parkingCompletedKey),
    ),
  ];
}

class DoubleHqPageInfo {
  final String title;
  final Widget page;
  final Icon icon;

  const DoubleHqPageInfo(this.title, this.page, this.icon);
}

final List<DoubleHqPageInfo> doubleHqPage = [
  const DoubleHqPageInfo(
      'DoubleDashBoard', DoubleDashBoard(), Icon(Icons.apartment)),
];
