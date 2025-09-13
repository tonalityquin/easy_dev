import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/blocking_dialog.dart';
import '../commute_inside_controller.dart';

class CommuteInsideWorkButtonSection extends StatelessWidget {
  final CommuteInsideController controller;
  final ValueChanged<bool> onLoadingChanged;

  const CommuteInsideWorkButtonSection({
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: isWorking
          ? null // 이미 출근 상태일 경우 버튼 비활성화
          : () async {
              onLoadingChanged(true);
              try {
                await runWithBlockingDialog(
                  context: context,
                  message: '출근 처리 중입니다...',
                  task: () async {
                    await controller.handleWorkStatus(
                      context,
                      context.read<UserState>(),
                      () => onLoadingChanged(false),
                    );
                  },
                );
              } finally {
                onLoadingChanged(false);
              }
            },
    );
  }
}
