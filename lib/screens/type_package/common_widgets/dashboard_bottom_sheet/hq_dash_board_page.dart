import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';

import '../../../../utils/init/logout_helper.dart';
import '../../../../utils/app_exit_flag.dart';

import 'dialog/dashboard_duration_blocking_dialog.dart';
import 'home_dash_board_controller.dart';
import 'widgets/home_user_info_card.dart';
import 'widgets/home_break_button_widget.dart';

import 'documents/document_box_sheet.dart';

class HqDashBoardPage extends StatefulWidget {
  const HqDashBoardPage({super.key});

  @override
  State<HqDashBoardPage> createState() => _HqDashBoardPageState();
}

class _HqDashBoardPageState extends State<HqDashBoardPage> {
  bool _layerHidden = true;

  /// ✅ 퇴근 처리 이후 “앱까지 종료”를 담당하는 헬퍼
  Future<void> _exitAppAfterClockOut(BuildContext context) async {
    // 명시적 종료 플로우 시작 플래그
    AppExitFlag.beginExit();

    try {
      if (Platform.isAndroid) {
        bool running = false;

        // 포그라운드 서비스가 돌아가고 있으면 먼저 중지
        try {
          running = await FlutterForegroundTask.isRunningService;
        } catch (_) {
          // isRunningService가 예외를 던져도 치명적이진 않으므로 무시
        }

        if (running) {
          try {
            final stopped = await FlutterForegroundTask.stopService();
            if (stopped != true && context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('포그라운드 서비스 중지 실패(플러그인 반환값 false)'),
                ),
              );
            }
          } catch (e) {
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('포그라운드 서비스 중지 실패: $e')),
              );
            }
          }

          // 서비스 중지 브로드캐스트 약간의 딜레이
          await Future.delayed(const Duration(milliseconds: 150));
        }
      }

      // 실제 앱 종료
      await SystemNavigator.pop();
    } catch (e) {
      // 종료에 실패하면 플래그 롤백
      AppExitFlag.reset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('앱 종료 실패: $e')),
        );
      }
    }
  }

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
                const HomeUserInfoCard(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(_layerHidden ? Icons.layers : Icons.layers_clear),
                    label: Text(_layerHidden ? '작업 버튼 펼치기' : '작업 버튼 숨기기'),
                    style: _layerToggleBtnStyle(),
                    onPressed: () =>
                        setState(() => _layerHidden = !_layerHidden),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _layerHidden
                      ? CrossFadeState.showFirst
                      : CrossFadeState.showSecond,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HomeBreakButtonWidget(controller: controller),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('퇴근하기'),
                          style: _clockOutBtnStyle(),
                          onPressed: () async {
                            // 근무 중일 때만 퇴근 확인 다이얼로그 노출
                            if (userState.isWorking) {
                              final bool confirmed =
                              await showDashboardDurationBlockingDialog(
                                context,
                                message:
                                '지금 퇴근 처리하시겠습니까?\n5초 안에 취소하지 않으면 자동으로 진행됩니다.',
                                duration: const Duration(seconds: 5),
                              );
                              if (!confirmed) {
                                // 사용자가 취소한 경우 → 아무 것도 하지 않음
                                return;
                              }
                            }

                            // ✅ 실제 퇴근 처리
                            await controller.handleWorkStatus(
                                userState, context);

                            if (!mounted) return;

                            // ✅ 퇴근 처리가 정상적으로 끝나서 isWorking이 false라면 → 앱까지 종료
                            if (!userState.isWorking) {
                              await _exitAppAfterClockOut(context);
                            }
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('로그아웃'),
                          style: _logoutBtnStyle(),
                          onPressed: () =>
                              LogoutHelper.logoutAndGoToLogin(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: const Text('서류함 열기'),
                          style: _docBoxBtnStyle(),
                          onPressed: () => openDocumentBox(context),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_layerHidden) const SizedBox(height: 16),
                const SizedBox(height: 32),
              ],
            ),
          );
        },
      ),
    );
  }
}

ButtonStyle _layerToggleBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(48),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

ButtonStyle _clockOutBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.redAccent, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
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

ButtonStyle _docBoxBtnStyle() {
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
