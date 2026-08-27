import 'package:flutter/material.dart';

import '../../pages/common/common_hq_dash_board_page.dart';

class SingleHqDashBoardPage extends StatelessWidget {
  const SingleHqDashBoardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CommonHqDashBoardPage(
      screenName: 'single_hq_dashboard',
      modeKey: 'single',
    );
  }
}
