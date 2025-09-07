import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/blocking_dialog.dart';
import '../commute_outside_controller.dart';
import '../debugs/clock_in_debug_firestore_logger.dart';

class WorkButtonSection extends StatelessWidget {
  final CommuteOutsideController controller;
  final ValueChanged<bool> onLoadingChanged;

  const WorkButtonSection({
    super.key,
    required this.controller,
    required this.onLoadingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final logger = ClockInDebugFirestoreLogger();
    final userState = context.watch<UserState>();
    final isWorking = userState.isWorking;

    final label = isWorking ? '출근 중' : '일해요';

    return ElevatedButton.icon(
      icon: const Icon(Icons.access_time),
      label: Text(
        label,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.1),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: const BorderSide(color: Colors.grey, width: 1.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: isWorking
          ? () => logger.log('🚫 출근 버튼 클릭 무시: 이미 출근 상태', level: 'warn')
          : () async {
        logger.log('🧲 [UI] 출근 버튼 클릭됨', level: 'called');

        // 컨트롤러의 토글 콜백에 맞춰 부모의 로딩 상태를 true→false로 전달
        bool loading = false;

        await runWithBlockingDialog(
          context: context,
          message: '출근 처리 중입니다...',
          task: () async {
            await controller.handleWorkStatus(
              context,
              context.read<UserState>(),
                  () {
                loading = !loading;        // true -> false
                onLoadingChanged(loading); // 부모로 전달
              },
              navigateOnWorking: false,     // ⬅️ 출근 후에도 화면 전환 금지
            );
          },
        );
      },
    );
  }
}
