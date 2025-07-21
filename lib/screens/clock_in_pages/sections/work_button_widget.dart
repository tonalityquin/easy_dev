import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../states/user/user_state.dart';
import '../clock_in_controller.dart';
import '../debugs/clock_in_debug_firestore_logger.dart';

class WorkButtonWidget extends StatefulWidget {
  final ClockInController controller;

  const WorkButtonWidget({
    super.key,
    required this.controller,
  });

  @override
  State<WorkButtonWidget> createState() => _WorkButtonWidgetState();
}

class _WorkButtonWidgetState extends State<WorkButtonWidget> {
  bool _isLoading = false;
  final logger = ClockInDebugFirestoreLogger();

  void _toggleLoading() {
    setState(() {
      _isLoading = !_isLoading;
      logger.log(
        _isLoading ? '🔄 출근 버튼: 로딩 시작됨' : '✅ 출근 버튼: 로딩 종료됨',
        level: 'info',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final userState = context.watch<UserState>();
    final isWorking = userState.isWorking;

    final label = _isLoading
        ? '로딩 중...'
        : isWorking
        ? '출근 중'
        : '출근하기';

    return ElevatedButton.icon(
      icon: const Icon(Icons.assignment),
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
      onPressed: (_isLoading || isWorking)
          ? () {
        if (_isLoading) {
          logger.log('⚠️ 출근 버튼 클릭 무시: 로딩 중', level: 'warn');
        } else {
          logger.log('🚫 출근 버튼 클릭 무시: 이미 출근 상태', level: 'warn');
        }
      }
          : () {
        logger.log('🧲 [UI] 출근 버튼 클릭됨', level: 'called');
        widget.controller.handleWorkStatus(
          context,
          userState,
          _toggleLoading,
        );
      },
    );
  }
}
