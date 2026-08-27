import 'package:flutter/material.dart';

import '../../pages/common/common_hq_dash_board_page.dart';

class TripleHqDashBoardPage extends StatelessWidget {
  const TripleHqDashBoardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CommonHqDashBoardPage(
      screenName: 'triple_hq_dashboard',
      modeKey: 'triple',
    );
  }
}
