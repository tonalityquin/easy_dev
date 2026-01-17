import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../states/user/user_state.dart';
import '../../../../../utils/block_dialogs/work_start_duration_blocking_dialog.dart';
import '../double_commute_in_controller.dart';
import '../../../../../routes.dart';

// ✅ Trace 기록용 Recorder
import '../../../../../screens/hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

class DoubleCommuteInWorkButtonWidget extends StatelessWidget {
  final DoubleCommuteInController controller;
  final ValueChanged<bool> onLoadingChanged;

  const DoubleCommuteInWorkButtonWidget({
    super.key,
    required this.controller,
    required this.onLoadingChanged,
  });

  // ✅ 공통 Trace 기록 헬퍼
  void _trace(BuildContext context, String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final isWorking = userState.isWorking;
    final label = isWorking ? '출근 중' : '출근하기';

    return ElevatedButton.icon(
      icon: const Icon(Icons.access_time),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: const BorderSide(color: Colors.grey, width: 1.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      onPressed: isWorking
          ? null // 이미 출근 상태일 경우 버튼 비활성화
          : () async {
        // ✅ 버튼 탭 Trace 기록 (핸들러 진입 즉시)
        _trace(
          context,
          '출근하기 버튼',
          meta: <String, dynamic>{
            'screen': 'double_commute_inside',
            'action': 'work_start_attempt',
            'isWorkingBefore': isWorking,
          },
        );

        bool loadingTurnedOn = false;

        try {
          // 1) 출근 시작 전에 5초 카운트다운 + 취소 가능한 다이얼로그
          final proceed = await showWorkStartDurationBlockingDialog(
            context,
            message: '출근을 펀칭하면 근무가 시작됩니다.\n약 5초 정도 소요됩니다.',
            duration: const Duration(seconds: 5),
          );

          // ✅ 다이얼로그 결과 기록 (취소/진행)
          _trace(
            context,
            '출근 다이얼로그 결과',
            meta: <String, dynamic>{
              'screen': 'double_commute_inside',
              'action': 'work_start_dialog_result',
              'proceed': proceed,
              'durationSeconds': 5,
            },
          );

          // 취소 또는 false 반환 시, 실제 출근 로직은 수행하지 않음
          if (!proceed) {
            // ✅ 취소 종료 기록(선택적)
            _trace(
              context,
              '출근 처리 종료',
              meta: <String, dynamic>{
                'screen': 'double_commute_inside',
                'action': 'work_start_aborted',
                'reason': 'user_cancelled_dialog',
              },
            );
            return;
          }

          if (!context.mounted) return;

          // 2) 실제 출근 처리 로직 실행 구간에서만 상위 로딩 오버레이 표시
          onLoadingChanged(true);
          loadingTurnedOn = true;

          final dest = await controller.handleWorkStatusAndDecide(
            context,
            context.read<UserState>(),
          );

          if (!context.mounted) return;

          // ✅ 출근 처리 결과 기록 (라우팅 목적지 포함)
          _trace(
            context,
            '출근 처리 결과',
            meta: <String, dynamic>{
              'screen': 'double_commute_inside',
              'action': 'work_start_result',
              'dest': dest.toString(),
            },
          );

          // 3) 출근 처리 결과에 따른 라우팅
          switch (dest) {
            case DoubleCommuteDestination.headquarter:
              _trace(
                context,
                '출근 라우팅',
                meta: <String, dynamic>{
                  'screen': 'double_commute_inside',
                  'action': 'navigate',
                  'to': AppRoutes.doubleHeadquarterPage,
                  'dest': 'headquarter',
                },
              );
              Navigator.pushReplacementNamed(
                context,
                AppRoutes.doubleHeadquarterPage,
              );
              break;

            case DoubleCommuteDestination.type:
              _trace(
                context,
                '출근 라우팅',
                meta: <String, dynamic>{
                  'screen': 'double_commute_inside',
                  'action': 'navigate',
                  'to': AppRoutes.doubleTypePage,
                  'dest': 'type',
                },
              );
              Navigator.pushReplacementNamed(
                context,
                AppRoutes.doubleTypePage,
              );
              break;

            case DoubleCommuteDestination.none:
            // ✅ 라우팅 없음 기록(선택적)
              _trace(
                context,
                '출근 라우팅',
                meta: <String, dynamic>{
                  'screen': 'double_commute_inside',
                  'action': 'no_navigation',
                  'dest': 'none',
                },
              );
              // 아무 라우팅도 하지 않음
              break;
          }
        } catch (e) {
          // ✅ 예외 발생 기록(선택적)
          _trace(
            context,
            '출근 처리 오류',
            meta: <String, dynamic>{
              'screen': 'double_commute_inside',
              'action': 'exception',
              'error': e.toString(),
            },
          );
          rethrow;
        } finally {
          // 안전하게 로딩 상태 해제
          if (context.mounted && loadingTurnedOn) {
            onLoadingChanged(false);
          } else if (context.mounted && !loadingTurnedOn) {
            // 기존 코드의 "항상 false" 정책을 유지하려면 아래 줄을 살릴 수 있으나,
            // 실제로 로딩을 켠 경우에만 끄는 것이 더 정확합니다.
            onLoadingChanged(false);
          }
        }
      },
    );
  }
}
