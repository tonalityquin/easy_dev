import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../routes.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../utils/snackbar_helper.dart';
import 'clock_in_log_uploader.dart';

class ClockInController {
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

  void redirectIfWorking(BuildContext context, UserState userState) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final division = userState.user?.divisions.first ?? '';
      final area = userState.area;
      final doc = await FirebaseFirestore.instance.collection('areas').doc('$division-$area').get();

      if (!context.mounted) return;

      if (doc.exists && doc['isHeadquarter'] == true) {
        Navigator.pushReplacementNamed(context, AppRoutes.headquarterPage);
      } else {
        Navigator.pushReplacementNamed(context, AppRoutes.typePage);
      }
    });
  }

  Future<void> handleWorkStatus(BuildContext context, UserState userState, VoidCallback onLoadingChanged) async {
    onLoadingChanged.call();

    try {
      // ✅ 출근 여부 확인 전 GCS에 출근 JSON 업로드
      await _uploadAttendanceSilently(context);

      await userState.isHeWorking();

      if (userState.isWorking) {
        await _navigateToProperPageIfWorking(context, userState);
      }
    } catch (e) {
      _showWorkError(context);
    } finally {
      onLoadingChanged.call();
    }
  }

  Future<void> _navigateToProperPageIfWorking(BuildContext context, UserState userState) async {
    if (!userState.isWorking || !context.mounted) return;

    final division = userState.user?.divisions.first ?? '';
    final area = userState.area;
    final doc = await FirebaseFirestore.instance.collection('areas').doc('$division-$area').get();

    if (!context.mounted) return;

    final isHq = doc.exists && doc['isHeadquarter'] == true;
    Navigator.pushReplacementNamed(context, isHq ? AppRoutes.headquarterPage : AppRoutes.typePage);
  }

  void _showWorkError(BuildContext context) {
    if (!context.mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.'),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.redAccent,
      ),
    );
  }

  /// ✅ 수정된 출근 로그 업로드 함수
  Future<void> _uploadAttendanceSilently(BuildContext context) async {
    final userState = Provider.of<UserState>(context, listen: false);
    final area = userState.area;
    final name = userState.name;

    if (area.isEmpty || name.isEmpty) return;

    final now = DateTime.now();
    final nowTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final success = await ClockInLogUploader.uploadAttendanceJson(
      context: context,
      recordedTime: nowTime, // ✅ 시간만 전달
    );

    if (!context.mounted) return;

    if (success) {
      showSuccessSnackbar(context, '출근 기록 업로드 완료');
    } else {
      showFailedSnackbar(context, '출근 기록 업로드 실패');
    }
  }
}
