// lib/screens/.../home_dash_board_bottom_sheet.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart'; // ⬅️ 추가

import '../../../../../../states/user/user_state.dart';
import '../../../../../../states/location/location_state.dart';
import '../../../../../../states/bill/bill_state.dart';
import '../../../../../../states/area/area_state.dart'; // ⬅️ 추가: 현재 지역 읽기용

import '../../../../utils/external_openers.dart';
import '../../../../widgets/tts_filter_sheet.dart';
import 'home_dash_board_controller.dart';
import 'widgets/home_user_info_card.dart';
import 'widgets/home_break_button_widget.dart';
import 'widgets/home_work_button_widget.dart';
import 'widgets/home_show_report_dialog.dart';

// ⬇️ 추가: TTS 필터 로드 & 시트
import '../../../../utils/tts/tts_user_filters.dart';

class HomeDashBoardBottomSheet extends StatelessWidget {
  const HomeDashBoardBottomSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = HomeDashBoardController();

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
                    const SizedBox(height: 16),
                    HomeUserInfoCard(),
                    const SizedBox(height: 16),

                    // 로그아웃
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
                    HomeBreakButtonWidget(controller: controller),
                    const SizedBox(height: 16),

                    // 보고/업무 시작
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.assignment),
                            label: const Text('보고 작성'),
                            style: _reportBtnStyle(),
                            onPressed: () => showHomeReportDialog(context),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: HomeWorkButtonWidget(
                            controller: controller,
                            userState: userState,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // 🔊 TTS 설정 버튼 (추가)
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.volume_up_outlined),
                        label: const Text('TTS 설정'),
                        style: _ttsBtnStyle(),
                        onPressed: () async {
                          await _openTtsFilterSheet(context);
                          // 시트 내에서 저장된 최신 필터를 즉시 FG에 전달
                          final area = context.read<AreaState>().currentArea;
                          if (area.isNotEmpty) {
                            final filters = await TtsUserFilters.load();
                            FlutterForegroundTask.sendDataToTask({
                              'area': area,
                              'ttsFilters': filters.toMap(),
                            });
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('TTS 설정이 적용되었습니다.')),
                              );
                            }
                          }
                        },
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Gmail 열기
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.email),
                        label: const Text('Gmail 열기'),
                        style: _gmailBtnStyle(),
                        onPressed: () => openGmailInbox(context),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // 수동 새로고침
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

  Future<void> _openTtsFilterSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const TtsFilterSheet(),
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

ButtonStyle _ttsBtnStyle() {
  // TTS 버튼도 동일한 톤으로
  return ElevatedButton.styleFrom(
    backgroundColor: Colors.white,
    foregroundColor: Colors.black,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    side: const BorderSide(color: Colors.grey, width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}
