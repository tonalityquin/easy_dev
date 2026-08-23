import 'package:flutter/material.dart';

import '../../../../features/dashboard/pages/single/widgets/single_dash_board.dart';

class SingleHqPageInfo {
  const SingleHqPageInfo(this.title, this.page, this.icon);

  final String title;
  final Widget page;
  final Icon icon;
}

final List<SingleHqPageInfo> singleHqPage = <SingleHqPageInfo>[
  const SingleHqPageInfo(
    'SingleDashBoard',
    SingleDashBoard(),
    Icon(Icons.looks_one_rounded),
  ),
];
