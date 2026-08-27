import 'package:flutter/material.dart';

import '../../pages/common/common_hq_dash_board_page.dart';

class DoubleHqDashBoardPage extends StatelessWidget {
  const DoubleHqDashBoardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CommonHqDashBoardPage(
      screenName: 'double_hq_dashboard',
      modeKey: 'double',
    );
  }
}
