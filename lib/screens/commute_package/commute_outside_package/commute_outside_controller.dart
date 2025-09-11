// lib/screens/commute_package/commute_outside_package/commute_outside_controller.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../routes.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../type_package/common_widgets/dashboard_bottom_sheet/utils/break_log_uploader.dart';
import '../../type_package/common_widgets/dashboard_bottom_sheet/utils/clock_out_log_uploader.dart';
import 'floating_controls/commute_outside_floating.dart';
import 'utils/commute_outside_clock_in_log_uploader.dart';
import '../../../utils/app_navigator.dart';

class CommuteOutsideController {
  void initialize(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.area;

      await areaState.initializeArea(areaToInit);

      debugPrint('[GoToWork] 초기화 area: $areaToInit');
      debugPrint('[GoToWork] currentArea: ${areaState.currentArea}');
    });
  }

  Future<void> handleWorkStatus(
    BuildContext context,
    UserState userState,
    VoidCallback onLoadingChanged, {
    bool navigateOnWorking = true,
  }) async {
    onLoadingChanged.call();

    try {
      await _uploadAttendanceSilently(context);
      await userState.isHeWorking();

      if (!context.mounted) return;

      if (userState.isWorking && navigateOnWorking) {
        await _navigateToProperPageIfWorking(context, userState);
      }
    } catch (e) {
      if (context.mounted) {}
    } finally {
      onLoadingChanged.call();
    }
  }

  Future<void> _navigateToProperPageIfWorking(
    BuildContext context,
    UserState userState,
  ) async {
    if (!userState.isWorking || !context.mounted) return;

    final division = userState.user?.divisions.first ?? '';
    final area = userState.area;
    final docId = '$division-$area';

    try {
      final doc = await FirebaseFirestore.instance.collection('areas').doc(docId).get();

      if (!context.mounted) return;

      final isHq = doc.exists && doc['isHeadquarter'] == true;
      Navigator.pushReplacementNamed(context, isHq ? AppRoutes.headquarterPage : AppRoutes.typePage);
    } catch (e) {
      debugPrint('❌ _navigateToProperPageIfWorking 실패: $e');
    }
  }

  Future<void> _uploadAttendanceSilently(BuildContext context) async {
    final userState = Provider.of<UserState>(context, listen: false);
    final area = userState.area;
    final name = userState.name;

    if (area.isEmpty || name.isEmpty) {
      return;
    }

    final now = DateTime.now();
    final nowTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final success = await CommuteOutsideClockInLogUploader.uploadAttendanceJson(
      context: context,
      data: {
        'recordedTime': nowTime,
      },
    );

    if (!context.mounted) return;

    if (success) {
      // ✅ 출근 성공 → 플로팅(휴식/퇴근) 활성화
      await _enableFloatingShortcutsAfterClockIn(context, userState);
    } else {}
  }

  /// 출근 성공 직후 플로팅 오버레이(휴식/퇴근) 활성화
  Future<void> _enableFloatingShortcutsAfterClockIn(
    BuildContext context,
    UserState cachedUserState,
  ) async {
    // ✅ Snackbar/Sheet에 안전한 Context: Navigator(=ScaffoldMessenger) 우선
    BuildContext _safeCtx() =>
        AppNavigator.key.currentState?.context ??
        AppNavigator.key.currentState?.overlay?.context ?? // ← 보조
        context;

    CommuteOutsideFloating.configure(
      onBreak: () async {
        final ctx = _safeCtx();
        await handleBreakPressed(ctx, cachedUserState, () {});
      },
      onClockOut: () async {
        final ctx = _safeCtx();
        await handleLeavePressed(ctx, cachedUserState, () {}, exitAppAfter: true);
        await CommuteOutsideFloating.setEnabled(false);
      },
    );

    await CommuteOutsideFloating.init();
    await CommuteOutsideFloating.setEnabled(true);
    CommuteOutsideFloating.mountIfNeeded();
  }

  /// '휴식해요' 버튼 로직
  Future<void> handleBreakPressed(
    BuildContext context,
    UserState userState,
    VoidCallback onLoadingChanged,
  ) async {
    onLoadingChanged.call();

    try {
      final area = userState.area;
      final name = userState.name;

      if (area.isEmpty || name.isEmpty) {
        if (context.mounted) {
          return;
        }
      }

      final now = DateTime.now();
      final hhmm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final ok = await BreakLogUploader.uploadBreakJson(
        context: context,
        data: {
          'userId': userState.user?.id ?? '',
          'userName': name,
          'area': area,
          'division': userState.user?.divisions.first ?? '',
          'recordedTime': hhmm,
          'status': '휴게',
        },
      );

      if (!context.mounted) return;
      if (ok) {
      } else {}
    } catch (e) {
      if (context.mounted) ;
    } finally {
      onLoadingChanged.call();
    }
  }

  /// '퇴근해요' 버튼 로직
  Future<void> handleLeavePressed(
    BuildContext context,
    UserState userState,
    VoidCallback onLoadingChanged, {
    bool exitAppAfter = true,
  }) async {
    onLoadingChanged.call();

    try {
      final name = userState.name;
      if (name.isEmpty) {
        if (context.mounted) ;
        return;
      }

      final now = DateTime.now();
      final hhmm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

      final ok = await ClockOutLogUploader.uploadLeaveJson(
        context: context,
        data: {
          'userId': userState.user?.id ?? '',
          'userName': name,
          'division': userState.user?.divisions.first ?? '',
          'recordedTime': hhmm,
        },
      );

      if (context.mounted) {
        if (ok) {
        } else {}
      }

      // ✅ 퇴근 처리 후 포그라운드 서비스 종료 + 상태 리프레시
      await FlutterForegroundTask.stopService();
      await userState.isHeWorking();
      await Future.delayed(const Duration(milliseconds: 600));

      // ✅ 퇴근 후 플로팅 비활성화(안전 차원) + 저장
      await CommuteOutsideFloating.setEnabled(false);

      if (exitAppAfter) {
        SystemNavigator.pop();
      } else {
        // if (context.mounted) {
        //   Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
        // }
      }
    } catch (e) {
      if (context.mounted) ;
    } finally {
      onLoadingChanged.call();
    }
  }
}
