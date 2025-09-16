import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';

import '../../../../utils/external_openers.dart';
import 'home_dash_board_controller.dart';
import 'widgets/home_user_info_card.dart';
import 'widgets/home_break_button_widget.dart';
import 'widgets/home_work_button_widget.dart';

class HqDashBoardPage extends StatelessWidget {
  const HqDashBoardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = HomeDashBoardController();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                HomeUserInfoCard(),
                const SizedBox(height: 16),

                // (로그아웃 버튼 제거됨)

                const SizedBox(height: 32),
                HomeBreakButtonWidget(controller: controller),
                const SizedBox(height: 16),
                HomeWorkButtonWidget(
                  controller: controller,
                  userState: userState,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.email),
                    label: const Text('Gmail 열기'),
                    style: _gmailBtnStyle(),
                    onPressed: () => openGmailInbox(context), // ← 헬퍼 호출
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

ButtonStyle _gmailBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
