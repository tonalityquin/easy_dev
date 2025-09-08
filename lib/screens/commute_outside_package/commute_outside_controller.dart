import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import '../../../routes.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../type_package/common_widgets/dashboard_bottom_sheet/utils/break_log_uploader.dart';
import '../type_package/common_widgets/dashboard_bottom_sheet/utils/clock_out_log_uploader.dart';
import 'utils/clock_in_log_uploader.dart';

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

      if (!context.mounted) return; // ✅ context 안전성 체크

      if (userState.isWorking && navigateOnWorking) {
        await _navigateToProperPageIfWorking(context, userState);
      }
    } catch (e) {
      if (context.mounted) {
        _showWorkError(context);
      }
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

  void _showWorkError(BuildContext context) {
    if (!context.mounted) return;

    showFailedSnackbar(context, '작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.');
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

    final success = await ClockInLogUploader.uploadAttendanceJson(
      context: context,
      data: {
        'recordedTime': nowTime,
      },
    );

    if (!context.mounted) return;

    if (success) {
      showSuccessSnackbar(context, '출근 기록 업로드 완료');
    } else {
      showFailedSnackbar(context, '출근 기록 업로드 실패');
    }
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
        if (context.mounted) showFailedSnackbar(context, '사용자/지역 정보가 없습니다.');
        return;
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
        showSuccessSnackbar(context, '휴게 기록 업로드 완료');
      } else {
        showFailedSnackbar(context, '휴게 기록 업로드 실패 또는 중복');
      }
    } catch (e) {
      if (context.mounted) showFailedSnackbar(context, '휴게 기록 중 오류: $e');
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
        if (context.mounted) showFailedSnackbar(context, '사용자 정보가 없습니다.');
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
          showSuccessSnackbar(context, '퇴근 기록 업로드 완료');
        } else {
          showFailedSnackbar(context, '퇴근 기록 업로드 실패 또는 중복');
        }
      }

      await FlutterForegroundTask.stopService();
      await userState.isHeWorking();
      await Future.delayed(const Duration(milliseconds: 600));

      if (exitAppAfter) {
        SystemNavigator.pop();
      } else {
        // if (context.mounted) {
        //   Navigator.pushNamedAndRemoveUntil(context, AppRoutes.login, (_) => false);
        // }
      }
    } catch (e) {
      if (context.mounted) showFailedSnackbar(context, '퇴근 처리 중 오류: $e');
    } finally {
      onLoadingChanged.call();
    }
  }
}
