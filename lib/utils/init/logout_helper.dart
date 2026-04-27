import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/di/routes.dart';
import '../../features/account/applications/user_state.dart';
import '../../widgets/dialog/block_dialog_package/blocking_dialog.dart';
import '../snackbar_helper.dart';
import '../../services/firebase_google_auth_bridge.dart';

class LogoutHelper {
  static Future<void> logoutAndGoToLogin(
    BuildContext context, {
    String? route,
    bool checkWorking = false,
    Duration delay = const Duration(milliseconds: 500),
  }) async {
    final target = route ?? AppRoutes.selector;

    try {
      await runWithBlockingDialog(
        context: context,
        message: '로그아웃 중입니다...',
        task: () async {
          final userState = Provider.of<UserState>(context, listen: false);
          await FlutterForegroundTask.stopService();
          if (checkWorking) {
            try {
              await userState.isHeWorking();
            } catch (_) {}
          }
          await Future.delayed(delay);
          await userState.clearUserToPhone();
          debugPrint(
              '[LOGOUT][${DateTime.now().toIso8601String()}] userState.clearUserToPhone complete');

          await FirebaseGoogleAuthBridge.instance.signOutAll();
          debugPrint(
              '[LOGOUT][${DateTime.now().toIso8601String()}] FirebaseGoogleAuthBridge.signOutAll complete');

          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('mode');
          debugPrint(
              '[LOGOUT][${DateTime.now().toIso8601String()}] prefs.remove(mode) complete');
        },
      );

      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(target, (route) => false);
      showSuccessSnackbar(context, '로그아웃 되었습니다.');
    } catch (e) {
      if (context.mounted) {
        showFailedSnackbar(context, '로그아웃 실패: $e');
      }
    }
  }
}
