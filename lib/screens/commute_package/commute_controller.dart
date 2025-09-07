import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../routes.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../utils/snackbar_helper.dart';
import '../type_package/debugs/firestore_logger.dart';
import 'utils/clock_in_log_uploader.dart';
import 'debugs/clock_in_debug_firestore_logger.dart';

class CommuteController {
  final _localLogger = ClockInDebugFirestoreLogger();

  void initialize(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.area;

      _localLogger.log('initialize() called: area=$areaToInit', level: 'called');

      await areaState.initializeArea(areaToInit);

      _localLogger.log('initialize() complete: currentArea=${areaState.currentArea}', level: 'info');

      debugPrint('[GoToWork] 초기화 area: $areaToInit');
      debugPrint('[GoToWork] currentArea: ${areaState.currentArea}');
    });
  }

  void redirectIfWorking(BuildContext context, UserState userState) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final division = userState.user?.divisions.first ?? '';
      final area = userState.area;
      final docId = '$division-$area';

      _localLogger.log('redirectIfWorking() called: $docId', level: 'called');
      await FirestoreLogger().log('redirectIfWorking() called: doc=$docId', level: 'called');

      try {
        final doc = await FirebaseFirestore.instance.collection('areas').doc(docId).get();

        _localLogger.log('redirectIfWorking() success: doc.exists=${doc.exists}', level: 'success');
        await FirestoreLogger().log('redirectIfWorking() success: doc.exists=${doc.exists}', level: 'success');

        if (!context.mounted) return;

        if (doc.exists && doc['isHeadquarter'] == true) {
          Navigator.pushReplacementNamed(context, AppRoutes.headquarterPage);
        } else {
          Navigator.pushReplacementNamed(context, AppRoutes.typePage);
        }
      } catch (e) {
        _localLogger.log('redirectIfWorking() error: $e', level: 'error');
        await FirestoreLogger().log('redirectIfWorking() error: $e', level: 'error');
      }
    });
  }

  Future<void> handleWorkStatus(
      BuildContext context,
      UserState userState,
      VoidCallback onLoadingChanged,
      ) async {
    _localLogger.log('handleWorkStatus() 시작', level: 'called');
    onLoadingChanged.call();

    try {
      await _uploadAttendanceSilently(context);
      await userState.isHeWorking();

      _localLogger.log('handleWorkStatus() userState.isWorking=${userState.isWorking}', level: 'info');

      if (userState.isWorking) {
        await _navigateToProperPageIfWorking(context, userState);
      }
    } catch (e) {
      _localLogger.log('handleWorkStatus() error: $e', level: 'error');
      _showWorkError(context);
    } finally {
      onLoadingChanged.call();
      _localLogger.log('handleWorkStatus() 완료', level: 'info');
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

    _localLogger.log('_navigateToProperPageIfWorking() called: $docId', level: 'called');
    await FirestoreLogger().log('_navigateToProperPageIfWorking() called: doc=$docId', level: 'called');

    try {
      final doc = await FirebaseFirestore.instance.collection('areas').doc(docId).get();

      _localLogger.log('_navigateToProperPageIfWorking() success: doc.exists=${doc.exists}', level: 'success');
      await FirestoreLogger()
          .log('_navigateToProperPageIfWorking() success: doc.exists=${doc.exists}', level: 'success');

      if (!context.mounted) return;

      final isHq = doc.exists && doc['isHeadquarter'] == true;
      Navigator.pushReplacementNamed(context, isHq ? AppRoutes.headquarterPage : AppRoutes.typePage);
    } catch (e) {
      _localLogger.log('_navigateToProperPageIfWorking() error: $e', level: 'error');
      await FirestoreLogger().log('_navigateToProperPageIfWorking() error: $e', level: 'error');
    }
  }

  void _showWorkError(BuildContext context) {
    if (!context.mounted) return;

    _localLogger.log('_showWorkError() called', level: 'warn');

    // ✅ snackbar_helper 사용
    showFailedSnackbar(context, '작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.');
  }

  Future<void> _uploadAttendanceSilently(BuildContext context) async {
    final userState = Provider.of<UserState>(context, listen: false);
    final area = userState.area;
    final name = userState.name;

    if (area.isEmpty || name.isEmpty) {
      _localLogger.log('_uploadAttendanceSilently(): area 또는 name 없음. 건너뜀.', level: 'warn');
      return;
    }

    final now = DateTime.now();
    final nowTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    _localLogger.log('_uploadAttendanceSilently() called - $area, $name @ $nowTime', level: 'called');

    final success = await ClockInLogUploader.uploadAttendanceJson(
      context: context,
      data: {
        'recordedTime': nowTime,
      },
    );

    if (!context.mounted) return;

    if (success) {
      _localLogger.log('✅ 출근 기록 업로드 성공', level: 'success');
      showSuccessSnackbar(context, '출근 기록 업로드 완료');
    } else {
      _localLogger.log('🔥 출근 기록 업로드 실패', level: 'error');
      showFailedSnackbar(context, '출근 기록 업로드 실패');
    }
  }
}
