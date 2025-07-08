import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:android_intent_plus/android_intent.dart'; // ✅ 추가

import '../../../../states/user/user_state.dart';
import 'dash_board_controller.dart';
import 'widgets/user_info_card.dart';
import 'widgets/break_button_widget.dart';
import 'widgets/work_button_widget.dart';
import 'widgets/show_report_dialog.dart';

class DashBoardScreen extends StatelessWidget {
  const DashBoardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = DashBoardController();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: Colors.black87,
        title: const Text(
          '대시보드',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        automaticallyImplyLeading: false,
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                controller.logout(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, color: Colors.redAccent),
                    SizedBox(width: 8),
                    Text('로그아웃'),
                  ],
                ),
              ),
            ],
            icon: const Icon(Icons.more_vert),
          )
        ],
      ),
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          return SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 32),
                    Text(
                      '사용자 정보',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    UserInfoCard(),
                    const SizedBox(height: 32),
                    BreakButtonWidget(controller: controller),
                    const SizedBox(height: 16),
                    // ✅ 보고 작성, 퇴근하기 버튼
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
                    // ✅ Gmail 앱 열기 버튼 (안정적인 방식)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
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
                            // Gmail 앱 실패 시 웹 메일 fallback
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
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
