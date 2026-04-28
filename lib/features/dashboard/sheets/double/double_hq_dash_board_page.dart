import 'package:flutter/material.dart';

import '../../../../../features/dashboard/pages/common/common_hq_dash_board_page.dart';
import 'double_home_dash_board_controller.dart';
import 'widgets/double_home_break_button_widget.dart';
import 'widgets/double_home_user_info_card.dart';

class DoubleHqDashBoardPage extends StatefulWidget {
  const DoubleHqDashBoardPage({super.key});

  @override
  State<DoubleHqDashBoardPage> createState() => _DoubleHqDashBoardPageState();
}

class _DoubleHqDashBoardPageState extends State<DoubleHqDashBoardPage> {
  late final DoubleHomeDashBoardController _controller =
  DoubleHomeDashBoardController();

  @override
  Widget build(BuildContext context) {
    return CommonHqDashBoardPage(
      screenName: 'double_hq_dashboard',
      stylePreset: HqDashBoardStylePreset.doubleLegacy,
      userInfoCard: const DoubleHomeUserInfoCard(),
      breakButton: DoubleHomeBreakButtonWidget(
        controller: _controller,
      ),
      onHandleWorkStatus: (userState, context) =>
          _controller.handleWorkStatus(userState, context),
    );
  }
}