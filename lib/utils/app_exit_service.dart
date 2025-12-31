// lib/utils/app_exit_service.dart

import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'app_exit_flag.dart';

/// 앱 종료 로직을 단일 진입점으로 제공합니다.
///
/// - Android
///   1) FlutterOverlayWindow 기반 오버레이가 떠 있으면 닫기
///   2) flutter_foreground_task 서비스가 돌고 있으면 stopService 시도
///   3) SystemNavigator.pop()로 앱 종료
/// - iOS 등 기타 플랫폼: SystemNavigator.pop() 호출
///
/// 기존 Header의 `_exitApp` 로직을 그대로 옮겨 재사용합니다.
class AppExitService {
  AppExitService._();

  static Future<void> exitApp(BuildContext context) async {
    AppExitFlag.beginExit();

    try {
      if (Platform.isAndroid) {
        try {
          if (await FlutterOverlayWindow.isActive()) {
            await FlutterOverlayWindow.closeOverlay();
          }
        } catch (_) {}

        bool running = false;
        try {
          running = await FlutterForegroundTask.isRunningService;
        } catch (_) {}

        if (running) {
          try {
            final stopped = await FlutterForegroundTask.stopService();
            if (stopped != true) {
              ScaffoldMessenger.maybeOf(context)?.showSnackBar(
                const SnackBar(
                  content: Text('포그라운드 중지 실패(플러그인 반환값 false)'),
                ),
              );
            }
          } catch (e) {
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(
              SnackBar(content: Text('포그라운드 중지 실패: $e')),
            );
          }
          await Future.delayed(const Duration(milliseconds: 150));
        }

        await SystemNavigator.pop();
      } else {
        await SystemNavigator.pop();
      }
    } catch (e) {
      AppExitFlag.reset();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('앱 종료 실패: $e')),
      );
    }
  }
}
