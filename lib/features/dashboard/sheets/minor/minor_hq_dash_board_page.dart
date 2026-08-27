import 'package:flutter/material.dart';

import '../../pages/common/common_hq_dash_board_page.dart';

class MinorHqDashBoardPage extends StatelessWidget {
  const MinorHqDashBoardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CommonHqDashBoardPage(
      screenName: 'minor_hq_dashboard',
      modeKey: 'minor',
    );
  }
}
