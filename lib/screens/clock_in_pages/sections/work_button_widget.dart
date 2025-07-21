import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../states/user/user_state.dart';
import '../clock_in_controller.dart';
import '../debugs/clock_in_debug_firestore_logger.dart';

class WorkButtonWidget extends StatelessWidget {
  final ClockInController controller;
  final ValueChanged<bool> onLoadingChanged;

  const WorkButtonWidget({
    super.key,
    required this.controller,
    required this.onLoadingChanged,
  });

  @override
  Widget build(BuildContext context) {
    final logger = ClockInDebugFirestoreLogger();
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

      // 버튼 클릭 핸들링
      onPressed: isWorking
          ? () {
        logger.log('🚫 출근 버튼 클릭 무시: 이미 출근 상태', level: 'warn');
      }
          : () {
        logger.log('🧲 [UI] 출근 버튼 클릭됨', level: 'called');
        onLoadingChanged(true); // 상위에서 로딩 시작 처리
        controller.handleWorkStatus(
          context,
          userState,
              () => onLoadingChanged(false), // 로딩 종료 시 호출
        );
      },
    );
  }
}
