// lib/screens/simple_package/simple_inside_package/sections/simple_inside_clock_out_button_section.dart
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:easydev/time_record/simple_mode/simple_mode_attendance_repository.dart';
import 'package:easydev/utils/app_exit_flag.dart';

class SimpleInsideClockOutButtonSection extends StatelessWidget {
  final bool isDisabled;

  const SimpleInsideClockOutButtonSection({
    super.key,
    this.isDisabled = false,
  });

  /// ✅ 헤더의 _exitApp 과 동일한 종료 플로우 + 퇴근 시간 로그 기록
  Future<void> _exitApp(BuildContext context) async {
    // ✅ 먼저 퇴근 시간 로그를 SQLite에 기록
    final now = DateTime.now();
    await SimpleModeAttendanceRepository.instance.insertEvent(
      dateTime: now,
      type: SimpleModeAttendanceType.workOut,
    );

    // 명시적 종료 플로우 시작 플래그 ON
    AppExitFlag.beginExit();

    try {
      // 안드로이드일 때만 플로팅 오버레이 및 포그라운드 서비스 정리
      if (Platform.isAndroid) {
        // 1) 떠 있는 플로팅 버블(overlayMain → QuickOverlayApp)이 있다면 먼저 닫기
        try {
          if (await FlutterOverlayWindow.isActive()) {
            await FlutterOverlayWindow.closeOverlay();
          }
        } catch (_) {
          // 오버레이가 없거나 플러그인에서 오류가 나도 치명적이지 않으니 무시
        }

        // 2) 포그라운드 서비스 중지
        bool running = false;
        try {
          running = await FlutterForegroundTask.isRunningService;
        } catch (_) {}

        if (running) {
          try {
            final stopped = await FlutterForegroundTask.stopService();
            if (stopped != true) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('포그라운드 중지 실패(플러그인 반환값 false)'),
                ),
              );
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('포그라운드 중지 실패: $e')),
            );
          }

          // 서비스 중지 브로드캐스트 반영을 위한 약간의 딜레이
          await Future.delayed(const Duration(milliseconds: 150));
        }

        // 3) 실제 앱 종료 (SystemNavigator.pop)
        await SystemNavigator.pop();
      } else {
        // iOS / 기타 플랫폼
        await SystemNavigator.pop();
      }
    } catch (e) {
      // 종료 시도 중 예외가 발생하면 플래그를 원복해서
      // 이후 라이프사이클에서 다시 정상 동작하도록 함
      AppExitFlag.reset();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('앱 종료 실패: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      icon: const Icon(Icons.exit_to_app),
      label: const Text(
        '퇴근하기',
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      // 🔥 여기서 헤더와 동일한 앱 종료 플로우 실행 + 퇴근 로그
      onPressed: isDisabled ? null : () => _exitApp(context),
    );
  }
}
