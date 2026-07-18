import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import '../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../features/community/application/game/game_quick_actions.dart';
import '../../features/dashboard/widgets/utils/productivity_tools.dart';
import 'app_exit_flag.dart';

class AppExitService {
  AppExitService._();

  static Future<void> exitApp(
    BuildContext context, {
    bool usePromptUi = false,
  }) async {
    AppExitFlag.beginExit();

    try {
      try {
        await GameQuickActions.terminateSession();
      } catch (_) {}

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
              _showFailure(
                context,
                '포그라운드 중지 실패(플러그인 반환값 false)',
                usePromptUi: usePromptUi,
              );
            }
          } catch (e) {
            _showFailure(
              context,
              '포그라운드 중지 실패: $e',
              usePromptUi: usePromptUi,
            );
          }
          await Future.delayed(const Duration(milliseconds: 150));
        }
      }

      await ChillStore.instance.cancelProtectedSubmissionNotifications();
      await SystemNavigator.pop();
    } catch (e) {
      AppExitFlag.reset();
      _showFailure(
        context,
        '앱 종료 실패: $e',
        usePromptUi: usePromptUi,
      );
    }
  }

  static void _showFailure(
    BuildContext context,
    String message, {
    required bool usePromptUi,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    if (!usePromptUi) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    messenger.showSnackBar(
      SnackBar(
        backgroundColor: tokens.dangerContainer,
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
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
