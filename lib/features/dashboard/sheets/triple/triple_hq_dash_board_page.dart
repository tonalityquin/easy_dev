import 'package:flutter/material.dart';

import '../../../../../features/dashboard/pages/common/common_hq_dash_board_page.dart';
import 'triple_home_dash_board_controller.dart';
import 'widgets/triple_home_break_button_widget.dart';
import 'widgets/triple_home_user_info_card.dart';

class TripleHqDashBoardPage extends StatefulWidget {
  const TripleHqDashBoardPage({super.key});

  @override
  State<TripleHqDashBoardPage> createState() => _TripleHqDashBoardPageState();
}

class _TripleHqDashBoardPageState extends State<TripleHqDashBoardPage> {
  late final TripleHomeDashBoardController _controller =
  TripleHomeDashBoardController();

  @override
  Widget build(BuildContext context) {
    return CommonHqDashBoardPage(
      screenName: 'triple_hq_dashboard',
      stylePreset: HqDashBoardStylePreset.outlined,
      userInfoCard: const TripleHomeUserInfoCard(),
      breakButton: TripleHomeBreakButtonWidget(
        controller: _controller,
      ),
      onHandleWorkStatus: (userState, context) =>
          _controller.handleWorkStatus(userState, context),
    );
  }
}