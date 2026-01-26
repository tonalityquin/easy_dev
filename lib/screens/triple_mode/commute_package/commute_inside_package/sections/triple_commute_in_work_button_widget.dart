import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../../states/user/user_state.dart';
import '../../../../../utils/block_dialogs/work_start_duration_blocking_dialog.dart';
import '../triple_commute_in_controller.dart';
import '../../../../../routes.dart';

class TripleCommuteInWorkButtonWidget extends StatelessWidget {
  final TripleCommuteInController controller;
  final ValueChanged<bool> onLoadingChanged;

  const TripleCommuteInWorkButtonWidget({
    super.key,
    required this.controller,
    required this.onLoadingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final userState = context.watch<UserState>();
    final isWorking = userState.isWorking;
    final label = isWorking ? '출근 중' : '출근하기';

    // ✅ 컨셉 테마(프리셋/다크모드) 기반 버튼 토큰
    final bg = isWorking ? cs.surfaceContainerLow : cs.primary;
    final fg = isWorking ? cs.onSurfaceVariant : cs.onPrimary;
    final border = isWorking ? cs.outlineVariant : cs.primary;

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
        backgroundColor: bg,
        foregroundColor: fg,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: BorderSide(color: border, width: 1.0),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        elevation: 0,
      ),
      onPressed: isWorking
          ? null
          : () async {
        bool loadingTurnedOn = false;

        try {
          // 1) 출근 시작 전에 5초 카운트다운 + 취소 가능한 다이얼로그
          final proceed = await showWorkStartDurationBlockingDialog(
            context,
            message: '출근을 펀칭하면 근무가 시작됩니다.\n약 5초 정도 소요됩니다.',
            duration: const Duration(seconds: 5),
          );

          if (!proceed) return;
          if (!context.mounted) return;

          // 2) 실제 출근 처리 구간에서만 로딩 오버레이 표시
          onLoadingChanged(true);
          loadingTurnedOn = true;

          final dest = await controller.handleWorkStatusAndDecide(
            context,
            context.read<UserState>(),
          );

          if (!context.mounted) return;

          // 3) 결과에 따른 라우팅
          switch (dest) {
            case CommuteDestination.headquarter:
              Navigator.pushReplacementNamed(
                context,
                AppRoutes.tripleHeadquarterPage,
              );
              break;
            case CommuteDestination.type:
              Navigator.pushReplacementNamed(
                context,
                AppRoutes.tripleTypePage,
              );
              break;
            case CommuteDestination.none:
              break;
          }
        } finally {
          // 로딩을 켠 경우에만 끄는 것이 정확하지만,
          // 기존 동작(항상 false)과의 호환을 위해 mounted면 안전하게 false 처리
          if (context.mounted) {
            if (loadingTurnedOn) {
              onLoadingChanged(false);
            } else {
              onLoadingChanged(false);
            }
          }
        }
      },
    );
  }
}
