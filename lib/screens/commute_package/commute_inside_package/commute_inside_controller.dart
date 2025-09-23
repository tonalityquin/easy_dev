// lib/screens/commute/inside/commute_inside_controller.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../routes.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../utils/snackbar_helper.dart';
import 'utils/commute_inside_clock_in_log_uploader.dart';
import '../../../utils/usage_reporter.dart'; // ✅ 비용 보고

class CommuteInsideController {
  void initialize(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.area.trim();

      final alreadyInitialized = areaState.currentArea == areaToInit && areaState.capabilitiesOfCurrentArea.isNotEmpty;

      if (!alreadyInitialized) {
        await areaState.initializeArea(areaToInit);
        debugPrint('[GoToWork] initializeArea 호출: $areaToInit');
      } else {
        debugPrint('[GoToWork] 초기화 스킵 (이미 준비됨): $areaToInit');
      }

      debugPrint('[GoToWork] currentArea: ${areaState.currentArea}');
    });
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

      await UsageReporter.instance.report(
        area: area.isNotEmpty ? area : 'unknown',
        action: 'read',
        n: 1,
        source: 'CommuteInsideController._navigateToProperPageIfWorking/areas.doc.get',
      );

      if (!context.mounted) return;

      final isHq = doc.exists && (doc.data()?['isHeadquarter'] == true);
      Navigator.pushReplacementNamed(
        context,
        isHq ? AppRoutes.headquarterPage : AppRoutes.typePage,
      );
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

    final success = await CommuteInsideClockInLogUploader.uploadAttendanceJson(
      context: context,
      data: {
        'recordedTime': nowTime,
      },
    );

    if (!context.mounted) return;

    if (success) {
      await UsageReporter.instance.report(
        area: area,
        action: 'Commute - Google Sheets Append',
        n: 1,
        source: 'CommuteInsideController._uploadAttendanceSilently',
      );
      showSuccessSnackbar(context, '출근 기록 업로드 완료');
    } else {
      showFailedSnackbar(context, '출근 기록 업로드 실패');
    }
  }

  void redirectIfWorking(BuildContext context, UserState userState) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final division = userState.user?.divisions.first ?? '';
      final area = userState.area;
      final docId = '$division-$area';

      try {
        final doc = await FirebaseFirestore.instance.collection('areas').doc(docId).get();

        await UsageReporter.instance.report(
          area: area.isNotEmpty ? area : 'unknown',
          action: 'read',
          n: 1,
          source: 'CommuteInsideController.redirectIfWorking/areas.doc.get',
        );

        if (!context.mounted) return;

        if (doc.exists && (doc.data()?['isHeadquarter'] == true)) {
          Navigator.pushReplacementNamed(context, AppRoutes.headquarterPage);
        } else {
          Navigator.pushReplacementNamed(context, AppRoutes.typePage);
        }
      } catch (e) {
        debugPrint('redirectIfWorking 오류: $e');
      }
    });
  }

  Future<void> handleWorkStatus(
    BuildContext context,
    UserState userState,
    VoidCallback onLoadingChanged,
  ) async {
    onLoadingChanged.call();

    try {
      await _uploadAttendanceSilently(context);
      await userState.isHeWorking(); // (내부 read는 해당 서비스 쪽에서 계측 권장)

      if (userState.isWorking) {
        await _navigateToProperPageIfWorking(context, userState);
      }
    } catch (e) {
      _showWorkError(context);
    } finally {
      onLoadingChanged.call();
    }
  }

  void _showWorkError(BuildContext context) {
    if (!context.mounted) return;
    showFailedSnackbar(context, '작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.');
  }
}
