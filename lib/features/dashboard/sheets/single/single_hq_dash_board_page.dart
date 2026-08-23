import 'package:flutter/material.dart';

import '../../pages/common/common_hq_dash_board_page.dart';
import 'single_home_dash_board_controller.dart';
import 'widgets/single_home_break_button_widget.dart';

class SingleHqDashBoardPage extends StatefulWidget {
  const SingleHqDashBoardPage({super.key});

  @override
  State<SingleHqDashBoardPage> createState() => _SingleHqDashBoardPageState();
}

class _SingleHqDashBoardPageState extends State<SingleHqDashBoardPage> {
  late final SingleHomeDashBoardController _controller =
      SingleHomeDashBoardController();

  @override
  Widget build(BuildContext context) {
    return CommonHqDashBoardPage(
      screenName: 'single_hq_dashboard',
      stylePreset: HqDashBoardStylePreset.outlined,
      userInfoCard: const SizedBox.shrink(),
      breakButton: SingleHomeBreakButtonWidget(controller: _controller),
      onHandleWorkStatus: (userState, context) =>
          _controller.handleWorkStatus(userState, context),
    );
  }
}
