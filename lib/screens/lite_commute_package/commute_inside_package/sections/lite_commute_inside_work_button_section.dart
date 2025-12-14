import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/user/user_state.dart';
import '../../../../utils/block_dialogs/work_start_duration_blocking_dialog.dart';
import '../lite_commute_inside_controller.dart';
import '../../../../routes.dart';

class LiteCommuteInsideWorkButtonSection extends StatelessWidget {
  final LiteCommuteInsideController controller;
  final ValueChanged<bool> onLoadingChanged;

  const LiteCommuteInsideWorkButtonSection({
    super.key,
    required this.controller,
    required this.onLoadingChanged,
  });

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
        try {
          // 1) simple commute 와 동일하게,
          //    출근 시작 전에 5초 카운트다운 + 취소 가능한 다이얼로그 먼저 실행
          final proceed = await showWorkStartDurationBlockingDialog(
            context,
            message: '출근을 펀칭하면 근무가 시작됩니다.\n약 5초 정도 소요됩니다.',
            duration: const Duration(seconds: 5),
          );

          // 취소 또는 false 반환 시, 실제 출근 로직은 수행하지 않음
          if (!proceed) {
            return;
          }

          if (!context.mounted) return;

          // 2) 실제 출근 처리 로직 실행 구간에서만 상위 로딩 오버레이 표시
          onLoadingChanged(true);

          final dest = await controller.handleWorkStatusAndDecide(
            context,
            context.read<UserState>(),
          );

          if (!context.mounted) return;

          // 3) 출근 처리 결과에 따른 라우팅
          switch (dest) {
            case LiteCommuteDestination.headquarter:
              Navigator.pushReplacementNamed(
                context,
                AppRoutes.liteHeadquarterPage,
              );
              break;
            case LiteCommuteDestination.type:
              Navigator.pushReplacementNamed(
                context,
                AppRoutes.liteTypePage,
              );
              break;
            case LiteCommuteDestination.none:
            // 아무 라우팅도 하지 않음
              break;
          }
        } finally {
          // 카운트다운을 통과해 로딩을 켠 경우/안 켠 경우 모두 포함해
          // 안전하게 로딩 상태 해제
          if (context.mounted) {
            onLoadingChanged(false);
          }
        }
      },
    );
  }
}
