import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/di/routes.dart';
import '../../features/account/applications/user_state.dart';
import '../../features/dashboard/applications/common/firebase_google_auth_bridge.dart';
import '../../features/dev/application/area_state.dart';
import '../../features/headquarter/application/fab/hub_quick_actions.dart';
import '../../features/launcher/application/launcher_debug_account_override_store.dart';
import '../../shared/tts/application/plate_tts_session_diagnostics.dart';
import '../../shared/tts/application/tts_ownership.dart';
import '../../shared/tts/services/plate/plate_tts_listener_service.dart';
import '../utils/block_dialog/blocking_dialog.dart';
import '../utils/developer_operation_status_dialog.dart';
import '../utils/snackbar_helper.dart';

class LogoutHelper {
  static Future<void> logoutAndGoToLogin(
    BuildContext context, {
    String? route,
    bool checkWorking = false,
    Duration delay = const Duration(milliseconds: 500),
    bool useCommonUi = false,
  }) async {
    final target = route ?? AppRoutes.modeLauncher;
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '로그아웃 상태',
      initialMessage: '로그아웃과 Area 세션 캐시 초기화를 시작합니다.',
      useCommonUi: useCommonUi,
      developerModeMessage:
          '개발자 모드 ON: 로그아웃 단계와 Area 캐시 초기화를 Status Dialog에 표시합니다.',
      standardModeMessage:
          '개발자 모드 OFF: 로그아웃 단계와 Area 캐시 초기화를 debugPrint로 기록합니다.',
    );

    Future<void> performLogout() async {
      final userState = Provider.of<UserState>(context, listen: false);
      final areaState = Provider.of<AreaState>(context, listen: false);

      trace.log('Foreground service 종료를 시작합니다.', progress: 0.1);
      await TtsOwnership.setOwner(TtsOwner.app);
      PlateTtsListenerService.setLocalRole(TtsOwner.app);
      await PlateTtsListenerService.stop();
      await FlutterForegroundTask.stopService();
      PlateTtsSessionDiagnostics.record(
        'logout_tts_reset',
        meta: <String, Object?>{
          'owner': TtsOwner.app.name,
          'foregroundServiceStopped': true,
        },
      );

      if (checkWorking) {
        trace.log('근무 상태 종료 반영을 확인합니다.', progress: 0.2);
        try {
          await userState.setWorkingStatus(false);
        } catch (e, st) {
          trace.log('근무 상태 종료 반영 중 오류가 발생했습니다: $e', progress: 0.24);
          trace.log('근무 상태 종료 스택 추적: $st', progress: 0.24);
        }
      }

      await Future.delayed(delay);
      final ephemeralDebugSession =
          await LauncherDebugAccountOverrideStore.isActive();
      trace.log(
        '사용자 세션과 Area 세션 캐시를 초기화합니다. debugEphemeral=$ephemeralDebugSession',
        progress: 0.38,
      );
      await userState.clearUserToPhone(
        onDiagnostic: (message) {
          trace.log(message, progress: 0.52);
        },
        skipRemoteStatusUpdate: ephemeralDebugSession,
        keepArea: !ephemeralDebugSession,
      );
      trace.log(
        'UserState 로그아웃 완료: currentArea="${areaState.currentArea}", currentDivision="${areaState.currentDivision}", currentRecord=${areaState.currentRecord == null ? 'null' : 'present'}, capabilities=${areaState.capabilitiesOfCurrentArea.length}',
        progress: 0.62,
      );

      await FirebaseGoogleAuthBridge.instance.signOutAll();
      trace.log('Firebase 및 Google 인증 로그아웃 완료.', progress: 0.78);

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('mode');
      trace.log('로그인 mode 로컬값 제거 완료.', progress: 0.88);
      if (ephemeralDebugSession) {
        await LauncherDebugAccountOverrideStore.discardForLogout(
          source: 'logout_helper',
        );
        trace.log(
          'Debug ephemeral 스냅샷을 로그아웃 기준으로 폐기했습니다.',
          progress: 0.91,
        );
      }

      await HeadHubActions.resetForLogout();
      trace.log('본사 퀵버튼 상태를 false로 초기화했습니다.', progress: 0.94);
    }

    try {
      if (trace.developerMode) {
        await performLogout();
      } else {
        await runWithBlockingDialog(
          context: context,
          message: '로그아웃 중입니다...',
          useCommonUi: useCommonUi,
          task: performLogout,
        );
      }

      await trace.succeed('로그아웃과 Area 세션 캐시 초기화가 완료되었습니다.');

      if (!context.mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(target, (route) => false);
      showSuccessSnackbar(
        context,
        '로그아웃 되었습니다.',
        useCommonUi: useCommonUi,
      );
    } catch (e, st) {
      await trace.fail(
        '로그아웃 처리에 실패했습니다.',
        error: e,
        stackTrace: st,
      );
      if (context.mounted) {
        showFailedSnackbar(
          context,
          '로그아웃 실패: $e',
          useCommonUi: useCommonUi,
        );
      }
    }
  }
}
