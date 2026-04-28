import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../screens/common_package/memo_package/chat_bot_tools.dart';
import 'app_exit_flag.dart';

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
      }

      await ChillStore.instance.cancelProtectedSubmissionNotifications();
      await SystemNavigator.pop();
    } catch (e) {
      AppExitFlag.reset();
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('앱 종료 실패: $e')),
      );
    }
  }
}
