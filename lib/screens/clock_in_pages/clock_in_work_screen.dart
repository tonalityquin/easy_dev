import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../states/user/user_state.dart';
import '../../utils/snackbar_helper.dart';
import 'widgets/report_dialog.dart';
import 'clock_in_controller.dart';
import 'widgets/plate_count_widget.dart';
import 'widgets/work_button_widget.dart';
import 'widgets/user_info_card.dart';

class ClockInWorkScreen extends StatefulWidget {
  const ClockInWorkScreen({super.key});

  @override
  State<ClockInWorkScreen> createState() => _ClockInWorkScreenState();
}

class _ClockInWorkScreenState extends State<ClockInWorkScreen> {
  final controller = ClockInController();

  @override
  void initState() {
    super.initState();
    controller.initialize(context);
  }

  Future<void> _handleLogout(BuildContext context) async {
    try {
      final userState = Provider.of<UserState>(context, listen: false);

      // ✅ TTS 포그라운드 서비스 종료
      await FlutterForegroundTask.stopService();

      // ✅ 유저 상태 초기화
      await userState.clearUserToPhone();

      // ✅ 잠시 대기 후 앱 종료
      await Future.delayed(const Duration(milliseconds: 500));
      SystemChannels.platform.invokeMethod('SystemNavigator.pop');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('로그아웃 실패: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          if (userState.isWorking) {
            controller.redirectIfWorking(context, userState);
          }

          return SafeArea(
            child: Stack(
              children: [
                SingleChildScrollView(
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const SizedBox(height: 96),
                          SizedBox(
                            height: 120,
                            child: Image.asset('assets/images/belivus_logo.PNG'),
                          ),
                          const SizedBox(height: 48),
                          Center(
                            child: Text(
                              '출근 전 사용자 정보 확인',
                              style: Theme.of(context).textTheme.titleLarge,
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 16),
                          const UserInfoCard(),
                          const PlateCountWidget(),
                          const SizedBox(height: 32),

                          // ✅ 같은 줄에 보고 작성, 출근하기 버튼
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  icon: const Icon(Icons.assignment),
                                  label: const Text('보고 작성'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.white,
                                    foregroundColor: Colors.black,
                                    padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                    side: const BorderSide(color: Colors.grey),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  onPressed: () {
                                    // 보고 작성 다이얼로그 표시
                                    showDialog(
                                      context: context,
                                      barrierDismissible: false,
                                      builder: (context) {
                                        return Dialog(
                                          backgroundColor: Colors.white,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          insetPadding: const EdgeInsets.symmetric(
                                              horizontal: 16, vertical: 24),
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              bottom: MediaQuery.of(context)
                                                  .viewInsets
                                                  .bottom,
                                            ),
                                            child: SingleChildScrollView(
                                              child: Padding(
                                                padding: const EdgeInsets.all(20),
                                                child: ParkingReportContent(
                                                  onReport: (type, content) async {
                                                    if (type == 'cancel') {
                                                      Navigator.pop(context);
                                                      return;
                                                    }

                                                    showSuccessSnackbar(
                                                        context, "보고 처리됨: $content");
                                                    Navigator.pop(context);
                                                  },
                                                ),
                                              ),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: WorkButtonWidget(controller: controller),
                              ),
                            ],
                          ),

                          const SizedBox(height: 32),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 16,
                  right: 16,
                  child: PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'logout') {
                        _handleLogout(context);
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
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
