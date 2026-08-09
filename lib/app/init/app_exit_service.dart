import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../design_system/common_ui/common_ui_theme.dart';
import '../../features/community/application/game/game_quick_actions.dart';
import '../../features/dashboard/widgets/utils/productivity_tools.dart';
import 'app_exit_flag.dart';

class AppExitService {
  AppExitService._();

  static const MethodChannel _androidExitChannel = MethodChannel(
    'com.quintus.dev/app_exit',
  );

  // Channel's Path : android/app/src/main/kotlin/com/quintus/easydev/MainActivity.kt
  // Release 버전에서는 kotlin/com/~ 경로가 다르니 참고할 것

  static Future<void> exitApp(
    BuildContext context, {
    bool useCommonUi = false,
  }) async {
    AppExitFlag.beginExit();

    try {
      try {
        await GameQuickActions.terminateSession();
      } catch (_) {}

      if (Platform.isAndroid) {
        await _stopAndroidServices(
          context,
          useCommonUi: useCommonUi,
        );
      }

      await ChillStore.instance.cancelProtectedSubmissionNotifications();
      await _closeApplication();
    } catch (e) {
      AppExitFlag.reset();
      _showFailure(
        context,
        '앱 종료 실패: $e',
        useCommonUi: useCommonUi,
      );
    }
  }

  static Future<void> _stopAndroidServices(
    BuildContext context, {
    required bool useCommonUi,
  }) async {
    try {
      if (await FlutterOverlayWindow.isActive()) {
        await FlutterOverlayWindow.closeOverlay();
      }
    } catch (_) {}

    bool running = false;
    try {
      running = await FlutterForegroundTask.isRunningService;
    } catch (_) {}

    if (!running) return;

    try {
      final stopped = await FlutterForegroundTask.stopService();
      if (stopped != true) {
        _showFailure(
          context,
          '포그라운드 중지 실패(플러그인 반환값 false)',
          useCommonUi: useCommonUi,
        );
      }
    } catch (e) {
      _showFailure(
        context,
        '포그라운드 중지 실패: $e',
        useCommonUi: useCommonUi,
      );
    }

    await Future.delayed(const Duration(milliseconds: 150));
  }

  static Future<void> _closeApplication() async {
    if (Platform.isAndroid) {
      try {
        await _androidExitChannel.invokeMethod<void>('finishAndRemoveTask');
        return;
      } catch (_) {}
    }

    await SystemNavigator.pop();
  }

  static void _showFailure(
    BuildContext context,
    String message, {
    required bool useCommonUi,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    if (!useCommonUi) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: tokens.dangerContainer,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          side: BorderSide(
            color: tokens.danger.withOpacity(tokens.isDark ? 0.58 : 0.36),
          ),
        ),
        content: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: tokens.danger,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: text.bodyMedium?.copyWith(
                  color: tokens.onDangerContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
