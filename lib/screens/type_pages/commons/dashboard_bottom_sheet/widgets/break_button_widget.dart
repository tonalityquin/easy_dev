import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../utils/blocking_dialog.dart';
import '../common_dash_board_controller.dart';

class BreakButtonWidget extends StatefulWidget {
  final CommonDashBoardController controller;

  const BreakButtonWidget({super.key, required this.controller});

  @override
  State<BreakButtonWidget> createState() => _BreakButtonWidgetState();
}

class _BreakButtonWidgetState extends State<BreakButtonWidget> {
  bool _submitting = false;

  Future<void> _onTap() async {
    if (_submitting) return; // ✅ 중복 탭 방지
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();

    try {
      await runWithBlockingDialog(
        context: context,
        message: '휴게 사용 기록 중입니다...',
        task: () async {
          // ⚠️ 컨트롤러 내부 네트워크/DB 호출은 반드시 await
          await widget.controller.recordBreakTime(context);
        },
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: _submitting ? null : _onTap,
      icon: _submitting
          ? const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
        ),
      )
          : const Icon(Icons.coffee),
      label: const Text(
        '휴게 사용 확인',
        style: TextStyle(
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
    );
  }
}
