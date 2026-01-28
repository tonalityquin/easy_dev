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
import '../../../../single_mode/utils/att_brk_repository.dart';
import 'minor_home_dash_board_controller.dart';
import 'widgets/minor_home_user_info_card.dart';
import 'widgets/minor_home_break_button_widget.dart';

import '../../../../hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

class MinorHqDashBoardPage extends StatefulWidget {
  const MinorHqDashBoardPage({super.key});

  @override
  State<MinorHqDashBoardPage> createState() => _MinorHqDashBoardPageState();
}

class _MinorHqDashBoardPageState extends State<MinorHqDashBoardPage> {
  bool _layerHidden = true;

  late final MinorHomeDashBoardController _controller = MinorHomeDashBoardController();

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  Future<void> _handleLogout(BuildContext context) async {
    await LogoutHelper.logoutAndGoToLogin(context);
  }

  Future<void> _exitAppAfterClockOut(BuildContext context) async {
    AppExitFlag.beginExit();

    try {
      if (DebugActionRecorder.instance.isRecording) {
        await DebugActionRecorder.instance.stopAndSave(
          titleOverride: 'auto:clockout_exit',
        );
      }
    } catch (_) {}

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

  Future<void> _handleClockOutFlow(BuildContext context, UserState userState) async {
    _trace(
      '퇴근 처리 시작',
      meta: <String, dynamic>{
        'screen': 'minor_hq_dashboard',
        'action': 'clockout_flow_start',
        'isWorkingBefore': userState.isWorking,
      },
    );

    await _controller.handleWorkStatus(userState, context);

    if (!mounted) return;

    _trace(
      '퇴근 상태 반영',
      meta: <String, dynamic>{
        'screen': 'minor_hq_dashboard',
        'action': 'clockout_state_updated',
        'isWorkingAfter': userState.isWorking,
      },
    );

    if (!userState.isWorking) {
      final user = userState.user;
      if (user != null) {
        final now = DateTime.now();

        _trace(
          '퇴근 이벤트 기록',
          meta: <String, dynamic>{
            'screen': 'minor_hq_dashboard',
            'action': 'workout_event_insert_and_upload',
            'area': userState.currentArea,
            'division': userState.division,
            'at': now.toIso8601String(),
          },
        );

        await AttBrkRepository.instance.insertEventAndUpload(
          dateTime: now,
          type: AttBrkModeType.workOut,
          userId: user.id,
          userName: user.name,
          area: userState.currentArea,
          division: userState.division,
        );
      }

      _trace(
        '앱 종료 진행',
        meta: <String, dynamic>{
          'screen': 'minor_hq_dashboard',
          'action': 'exit_after_clockout',
        },
      );

      await _exitAppAfterClockOut(context);
    } else {
      _trace(
        '퇴근 처리 미완료',
        meta: <String, dynamic>{
          'screen': 'minor_hq_dashboard',
          'action': 'clockout_not_completed',
          'reason': 'userState.isWorking_still_true',
        },
      );
    }
  }

  Future<void> _onClockOutPressed(BuildContext context, UserState userState) async {
    _trace(
      '퇴근하기 버튼',
      meta: <String, dynamic>{
        'screen': 'minor_hq_dashboard',
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

      _trace(
        '퇴근 다이얼로그 결과',
        meta: <String, dynamic>{
          'screen': 'minor_hq_dashboard',
          'action': 'clockout_dialog_result',
          'confirmed': confirmed,
          'durationSeconds': 5,
        },
      );

      if (!confirmed) {
        _trace(
          '퇴근 처리 취소',
          meta: <String, dynamic>{
            'screen': 'minor_hq_dashboard',
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
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: cs.surface,
      body: Consumer<UserState>(
        builder: (context, userState, _) {
          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const MinorHomeUserInfoCard(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    icon: Icon(_layerHidden ? Icons.layers : Icons.layers_clear),
                    label: Text(_layerHidden ? '작업 버튼 펼치기' : '작업 버튼 숨기기'),
                    style: _outlinedSurfaceBtnStyle(context, minHeight: 48),
                    onPressed: () => setState(() => _layerHidden = !_layerHidden),
                  ),
                ),
                const SizedBox(height: 16),
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 200),
                  crossFadeState:
                  _layerHidden ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                  firstChild: const SizedBox.shrink(),
                  secondChild: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      MinorHomeBreakButtonWidget(controller: _controller),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.exit_to_app),
                          label: const Text('퇴근하기'),
                          style: _dangerOutlinedBtnStyle(context),
                          onPressed: () => _onClockOutPressed(context, userState),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: const Text('로그아웃'),
                          style: _outlinedSurfaceBtnStyle(context),
                          onPressed: () => _handleLogout(context),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          icon: const Icon(Icons.folder_open),
                          label: const Text('서류함 열기'),
                          style: _outlinedSurfaceBtnStyle(context),
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

ButtonStyle _outlinedSurfaceBtnStyle(BuildContext context, {double minHeight = 55}) {
  final cs = Theme.of(context).colorScheme;

  return ElevatedButton.styleFrom(
    backgroundColor: cs.surface,
    foregroundColor: cs.onSurface,
    minimumSize: Size.fromHeight(minHeight),
    padding: EdgeInsets.zero,
    elevation: 0,
    side: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ).copyWith(
    overlayColor: MaterialStateProperty.resolveWith<Color?>(
          (states) => states.contains(MaterialState.pressed)
          ? cs.outlineVariant.withOpacity(0.12)
          : null,
    ),
  );
}

ButtonStyle _dangerOutlinedBtnStyle(BuildContext context) {
  final cs = Theme.of(context).colorScheme;

  return ElevatedButton.styleFrom(
    backgroundColor: cs.surface,
    foregroundColor: cs.error,
    minimumSize: const Size.fromHeight(55),
    padding: EdgeInsets.zero,
    elevation: 0,
    side: BorderSide(color: cs.error.withOpacity(0.65), width: 1.0),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  ).copyWith(
    overlayColor: MaterialStateProperty.resolveWith<Color?>(
          (states) => states.contains(MaterialState.pressed)
          ? cs.error.withOpacity(0.10)
          : null,
    ),
  );
}
