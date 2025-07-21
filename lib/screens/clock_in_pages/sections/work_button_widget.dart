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

  /// 로딩 상태 토글 및 로그 기록
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

    // 버튼에 표시될 텍스트 라벨 설정
    final label = _isLoading
        ? '로딩 중...'
        : isWorking
        ? '출근 중'
        : '출근하기';

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

      /// 버튼 클릭 이벤트 핸들링
      onPressed: (_isLoading || isWorking)
      // 로딩 중이거나 이미 출근 중이면 클릭 무시
          ? () {
        if (_isLoading) {
          logger.log('⚠️ 출근 버튼 클릭 무시: 로딩 중', level: 'warn');
        } else {
          logger.log('🚫 출근 버튼 클릭 무시: 이미 출근 상태', level: 'warn');
        }
      }
      // 출근 상태 확인 및 처리 시작
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
