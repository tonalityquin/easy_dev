import 'package:flutter/material.dart';

import '../../../../../features/dashboard/pages/common/common_hq_dash_board_page.dart';
import 'minor_home_dash_board_controller.dart';
import 'widgets/minor_home_break_button_widget.dart';
import 'widgets/minor_home_user_info_card.dart';

class MinorHqDashBoardPage extends StatefulWidget {
  const MinorHqDashBoardPage({super.key});

  @override
  State<MinorHqDashBoardPage> createState() => _MinorHqDashBoardPageState();
}

class _MinorHqDashBoardPageState extends State<MinorHqDashBoardPage> {
  late final MinorHomeDashBoardController _controller =
  MinorHomeDashBoardController();

  @override
  Widget build(BuildContext context) {
    return CommonHqDashBoardPage(
      screenName: 'minor_hq_dashboard',
      stylePreset: HqDashBoardStylePreset.outlined,
      userInfoCard: const MinorHomeUserInfoCard(),
      breakButton: MinorHomeBreakButtonWidget(
        controller: _controller,
      ),
      onHandleWorkStatus: (userState, context) =>
          _controller.handleWorkStatus(userState, context),
    );
  }
}