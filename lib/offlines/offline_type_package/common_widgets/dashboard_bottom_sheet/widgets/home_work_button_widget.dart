import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../../../states/user/user_state.dart';
import '../../../../../utils/blocking_dialog.dart';
import '../home_dash_board_controller.dart';

class HomeWorkButtonWidget extends StatefulWidget {
  final HomeDashBoardController controller;
  final UserState userState;

  const HomeWorkButtonWidget({
    super.key,
    required this.controller,
    required this.userState,
  });

  @override
  State<HomeWorkButtonWidget> createState() => _HomeWorkButtonWidgetState();
}

class _HomeWorkButtonWidgetState extends State<HomeWorkButtonWidget> {
  bool _submitting = false;

  Future<void> _onTap() async {
    if (_submitting) return;
    setState(() => _submitting = true);
    HapticFeedback.lightImpact();

    try {
      await runWithBlockingDialog(
        context: context,
        message: widget.userState.isWorking ? '퇴근 처리 중입니다...' : '출근 처리 중입니다...',
        task: () async {
          await widget.controller.handleWorkStatus(widget.userState, context);
        },
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isWorking = widget.userState.isWorking;
    final label = isWorking ? '퇴근하기' : '출근하기';
    final icon = isWorking ? Icons.logout : Icons.login;

    return ElevatedButton.icon(
      icon: _submitting
          ? const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
        ),
      )
          : Icon(icon),
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
      onPressed: _submitting ? null : _onTap,
    );
  }
}
