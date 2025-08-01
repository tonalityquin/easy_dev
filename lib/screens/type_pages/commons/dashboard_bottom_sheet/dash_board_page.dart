import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:android_intent_plus/android_intent.dart';

import '../../../../../../states/user/user_state.dart';

import 'common_dash_board_controller.dart';
import 'widgets/user_info_card.dart';
import 'widgets/break_button_widget.dart';
import 'widgets/work_button_widget.dart';
import 'widgets/show_report_dialog.dart';

class DashBoardPage extends StatelessWidget {
  const DashBoardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = CommonDashBoardController();

    return Scaffold(

      backgroundColor: Colors.white,
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                UserInfoCard(),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('로그아웃'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => controller.logout(context),
                ),
                const SizedBox(height: 32),
                BreakButtonWidget(controller: controller),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.assignment),
                        label: const Text('보고 작성'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: Colors.black,
                          side: const BorderSide(color: Colors.grey),
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        onPressed: () {
                          showReportDialog(context);
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: WorkButtonWidget(
                        controller: controller,
                        userState: userState,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  icon: const Icon(Icons.email),
                  label: const Text('Gmail 열기'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.black,
                    side: const BorderSide(color: Colors.grey),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () async {
                    try {
                      final intent = AndroidIntent(
                        action: 'android.intent.action.MAIN',
                        package: 'com.google.android.gm',
                        componentName: 'com.google.android.gm.ConversationListActivityGmail',
                      );
                      await intent.launch();
                    } catch (e) {
                      try {
                        final fallbackIntent = AndroidIntent(
                          action: 'android.intent.action.VIEW',
                          data: 'https://mail.google.com',
                        );
                        await fallbackIntent.launch();
                      } catch (e2) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('Gmail 실행 실패: $e2')),
                          );
                        }
                      }
                    }
                  },
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
