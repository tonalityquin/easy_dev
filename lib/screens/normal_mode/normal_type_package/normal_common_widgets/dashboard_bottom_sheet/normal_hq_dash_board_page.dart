import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';

import '../../../../../../states/user/user_state.dart';
import '../../../../../utils/block_dialogs/work_end_duration_blocking_dialog.dart';
import '../../../../../utils/init/logout_helper.dart';
import '../../../../../utils/app_exit_flag.dart';

import '../../../../common_package/sheet_tool/leader_document_box_sheet.dart';
import '../../../../simple_mode/utils/simple_mode/simple_mode_attendance_repository.dart';
import 'normal_home_dash_board_controller.dart';
import 'widgets/normal_home_user_info_card.dart';
import 'widgets/normal_home_break_button_widget.dart';

// ✅ Trace 기록용 Recorder
import '../../../../hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

class NormalHqDashBoardPage extends StatefulWidget {
  const NormalHqDashBoardPage({super.key});

  @override
  State<NormalHqDashBoardPage> createState() => _NormalHqDashBoardPageState();
}

class _NormalHqDashBoardPageState extends State<NormalHqDashBoardPage> {
  bool _layerHidden = true;

  late final NormalHomeDashBoardController _controller = NormalHomeDashBoardController();

  // ✅ 공통 Trace 기록 헬퍼
  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    // 기존 동작 유지
    await LogoutHelper.logoutAndGoToLogin(context);
  }

  Future<void> _exitAppAfterClockOut(BuildContext context) async {
    AppExitFlag.beginExit();

    // ✅ 앱 종료 직전, Trace 기록이 실제로 파일에 남도록 자동 저장(기록 중일 때만)
    // - stopAndSave는 기록 중이 아니면 null 반환 → 안전
    // - 앱이 종료되면 Trace 탭에서 수동 저장할 기회가 없으므로 유실 방지 목적
    try {
      if (DebugActionRecorder.instance.isRecording) {
        await DebugActionRecorder.instance.stopAndSave(
          titleOverride: 'auto:clockout_exit',
        );
      }
    } catch (_) {
      // auto-save 실패는 앱 종료를 막지 않음
    }

    try {
      if (Platform.isAndroid) {
        bool running = false;

        try {
          running = await FlutterForegroundTask.isRunningService;
        } catch (_) {}

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

          await Future.delayed(const Duration(milliseconds: 150));
        }
      }

      await SystemNavigator.pop();
    } catch (e) {
      AppExitFlag.reset();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('앱 종료 실패: $e')),
        );
      }
    }
  }

  /// ✅ 퇴근 확정 후 실제로 실행할 "퇴근 처리" 로직
  ///
  /// 순서:
  ///  1) 기존 컨트롤러 로직으로 userState.isWorking → false 처리
  ///  2) isWorking=false 확인 후 SQLite(simple_mode_attendance)에 workOut 이벤트 기록(+필요시 업로드)
  ///  3) 앱 종료 플로우 실행
  ///
  /// ⚠️ 정책 변경:
  ///   - commute_true_false 는 출근 시각 기록용이며,
  ///     퇴근(workOut) 시에는 이 컬렉션을 절대 수정하지 않습니다.
  Future<void> _handleClockOutFlow(
    BuildContext context,
    UserState userState,
  ) async {
    // ✅ 퇴근 플로우 시작 Trace
    _trace(
      '퇴근 처리 시작',
      meta: <String, dynamic>{
        'screen': 'normal_hq_dashboard',
        'action': 'clockout_flow_start',
        'isWorkingBefore': userState.isWorking,
      },
    );

    // 1) 기존 퇴근 처리 (user_accounts.isWorking 등)
    await _controller.handleWorkStatus(userState, context);

    if (!mounted) return;

    // ✅ 퇴근 처리 후 상태 Trace(선택)
    _trace(
      '퇴근 상태 반영',
      meta: <String, dynamic>{
        'screen': 'normal_hq_dashboard',
        'action': 'clockout_state_updated',
        'isWorkingAfter': userState.isWorking,
      },
    );

    // 2) 퇴근 처리 성공 여부 확인
    if (!userState.isWorking) {
      final user = userState.user;
      if (user != null) {
        final now = DateTime.now();

        final String userId = user.id;
        final String userName = user.name;
        final String area = userState.currentArea; // 기존 로직 유지
        final String division = userState.division;

        // ✅ workOut 기록 직전 Trace(선택)
        _trace(
          '퇴근 이벤트 기록',
          meta: <String, dynamic>{
            'screen': 'normal_hq_dashboard',
            'action': 'workout_event_insert_and_upload',
            'area': area,
            'division': division,
            'at': now.toIso8601String(),
          },
        );

        // 2-1) SQLite + (필요 시) Firestore commute_user_logs 업로드
        await SimpleModeAttendanceRepository.instance.insertEventAndUpload(
          dateTime: now,
          type: SimpleModeAttendanceType.workOut,
          userId: userId,
          userName: userName,
          area: area,
          division: division,
        );
      }

      // ✅ 앱 종료 직전 Trace(선택)
      _trace(
        '앱 종료 진행',
        meta: <String, dynamic>{
          'screen': 'normal_hq_dashboard',
          'action': 'exit_after_clockout',
        },
      );

      // 3) 퇴근 처리 완료 → 앱 종료
      await _exitAppAfterClockOut(context);
    } else {
      // ✅ 퇴근 실패/미반영 Trace(선택)
      _trace(
        '퇴근 처리 미완료',
        meta: <String, dynamic>{
          'screen': 'normal_hq_dashboard',
          'action': 'clockout_not_completed',
          'reason': 'userState.isWorking_still_true',
        },
      );
    }
  }

  Future<void> _onClockOutPressed(BuildContext context, UserState userState) async {
    // ✅ 퇴근하기 버튼 Trace 기록(진입 즉시)
    _trace(
      '퇴근하기 버튼',
      meta: <String, dynamic>{
        'screen': 'normal_hq_dashboard',
        'action': 'clockout_tap',
        'isWorking': userState.isWorking,
      },
    );

    if (userState.isWorking) {
      final bool confirmed = await showWorkEndDurationBlockingDialog(
        context,
        message: '지금 퇴근 처리하시겠습니까?\n5초 안에 취소하지 않으면 자동으로 진행됩니다.',
        duration: const Duration(seconds: 5),
      );

      // ✅ 다이얼로그 결과 Trace 기록
      _trace(
        '퇴근 다이얼로그 결과',
        meta: <String, dynamic>{
          'screen': 'normal_hq_dashboard',
          'action': 'clockout_dialog_result',
          'confirmed': confirmed,
          'durationSeconds': 5,
        },
      );

      if (!confirmed) {
        // ✅ 취소 Trace(선택)
        _trace(
          '퇴근 처리 취소',
          meta: <String, dynamic>{
            'screen': 'normal_hq_dashboard',
            'action': 'clockout_aborted',
            'reason': 'user_cancelled_dialog',
          },
        );
        return;
      }
    }

    await _handleClockOutFlow(context, userState);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const NormalHomeUserInfoCard(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(_layerHidden ? Icons.layers : Icons.layers_clear),
                    label: Text(_layerHidden ? '작업 버튼 펼치기' : '작업 버튼 숨기기'),
                    style: _layerToggleBtnStyle(),
                    onPressed: () => setState(() => _layerHidden = !_layerHidden),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState: _layerHidden ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      HomeBreakButtonWidget(controller: _controller),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('퇴근하기'),
                          style: _clockOutBtnStyle(),
                          onPressed: () => _onClockOutPressed(context, userState),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('로그아웃'),
                          style: _logoutBtnStyle(),
                          onPressed: () => _handleLogout(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: const Text('서류함 열기'),
                          style: _docBoxBtnStyle(),
                          onPressed: () => openLeaderDocumentBox(context),
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
