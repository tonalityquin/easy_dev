// lib/utils/logout_helper.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../block_dialogs/blocking_dialog.dart';
import '../snackbar_helper.dart';
import '../../states/user/user_state.dart';
import '../../routes.dart';


class LogoutHelper {
  /// 공통 로그아웃 처리:
  /// - 포그라운드 서비스 중단
  /// - 사용자 상태/로컬 저장소 정리
  /// - 로그인 모드(prefs: 'mode') 초기화
  /// - 허브 선택(Selector) 화면으로 스택 제거 이동
  static Future<void> logoutAndGoToLogin(
      BuildContext context, {
        String? route,
        bool checkWorking = false,
        Duration delay = const Duration(milliseconds: 500),
      }) async {
    // 기본 목적지는 허브 선택 페이지
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

          // 로그인 모드(서비스/태블릿) 고정값 제거 → 허브에서 두 카드 모두 선택 가능
          final prefs = await SharedPreferences.getInstance();
          await prefs.remove('mode');
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
