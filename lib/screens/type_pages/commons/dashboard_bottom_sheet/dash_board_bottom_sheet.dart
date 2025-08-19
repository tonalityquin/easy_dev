import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:android_intent_plus/android_intent.dart';

import '../../../../../../states/user/user_state.dart';
import '../../../../../../states/location/location_state.dart';
import '../../../../../../states/bill/bill_state.dart';

import 'common_dash_board_controller.dart';
import 'widgets/user_info_card.dart';
import 'widgets/break_button_widget.dart';
import 'widgets/work_button_widget.dart';
import 'widgets/show_report_dialog.dart';
import './clock_out_fetch_plate_count_widget.dart';

class DashBoardBottomSheet extends StatelessWidget {
  const DashBoardBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = CommonDashBoardController();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.95,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Consumer<UserState>(
            builder: (context, userState, _) {
              return SingleChildScrollView(
                controller: scrollController,
                padding: const EdgeInsets.all(24),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Container(
                      width: 60,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.grey[300],
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const ClockOutFetchPlateCountWidget(),
                    const SizedBox(height: 16),
                    UserInfoCard(),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.logout),
                        label: const Text('로그아웃'),
                        style: _logoutBtnStyle(),
                        onPressed: () => controller.logout(context),
                      ),
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
                            style: _reportBtnStyle(),
                            onPressed: () => showReportDialog(context),
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
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.email),
                        label: const Text('Gmail 열기'),
                        style: _gmailBtnStyle(),
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
                    ),
                    const SizedBox(height: 16),
                    Consumer<LocationState>(
                      builder: (context, locationState, _) {
                        bool isRefreshing = false;

                        return StatefulBuilder(
                          builder: (context, setState) => SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              style: _refreshBtnStyle(),
                              icon: isRefreshing
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.refresh),
                              label: const Text(
                                "주차 구역 수동 새로고침",
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                              ),
                              onPressed: isRefreshing
                                  ? null
                                  : () async {
                                      setState(() => isRefreshing = true);
                                      await locationState.manualLocationRefresh();
                                      await context.read<BillState>().manualBillRefresh();
                                      setState(() => isRefreshing = false);
                                    },
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }
}

ButtonStyle _logoutBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

ButtonStyle _reportBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
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

ButtonStyle _refreshBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
