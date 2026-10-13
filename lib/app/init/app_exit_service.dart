import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../design_system/common_ui/common_ui_theme.dart';
import '../../features/community/application/game/game_quick_actions.dart';
import '../../features/dashboard/widgets/utils/productivity_tools.dart';
import 'app_exit_flag.dart';
import 'work_status_notification.dart';

class AppExitService {
  AppExitService._();

  static const MethodChannel _androidExitChannel = MethodChannel(
    'com.quintus.dev/app_exit',
  );

  static Future<void> exitApp(
    BuildContext context, {
    bool useCommonUi = false,
  }) async {
    AppExitFlag.beginExit();

    try {
      await WorkStatusNotificationController.shutdownForAppExit(
        source: 'app_exit_service_primary',
      );

      try {
        await GameQuickActions.terminateSession();
      } catch (_) {}

      if (Platform.isAndroid) {
        await _stopAndroidServices();
      }

      final workNotificationVerified =
          await WorkStatusNotificationController.shutdownForAppExit(
        source: 'app_exit_service_verify',
      );
      if (!workNotificationVerified) {
        throw StateError('근무 세션 알림 종료를 확인하지 못했습니다.');
      }

      await ChillStore.instance.cancelProtectedSubmissionNotifications();
      await _closeApplication();
    } catch (e) {
      AppExitFlag.reset();
      await WorkStatusNotificationController.resumeAfterFailedAppExit(
        source: 'app_exit_service_failure',
      );
      _showFailure(
        context,
        '앱 종료 실패: $e',
        useCommonUi: useCommonUi,
      );
    }
  }

  static Future<void> _stopAndroidServices() async {
    var running = false;
    try {
      running = await FlutterForegroundTask.isRunningService;
    } catch (_) {}

    if (!running) return;

    try {
      await FlutterForegroundTask.stopService();
    } catch (_) {}

    for (var attempt = 1; attempt <= 4; attempt++) {
      try {
        running = await FlutterForegroundTask.isRunningService;
      } catch (_) {
        running = true;
      }
      if (!running) return;
      if (attempt < 4) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }
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
