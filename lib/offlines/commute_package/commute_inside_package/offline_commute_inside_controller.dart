import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../routes.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../utils/snackbar_helper.dart';
import 'utils/offline_commute_inside_clock_in_log_uploader.dart';

// ✅ Firestore, SharedPreferences 제거
// import 'package:cloud_firestore/cloud_firestore.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import 'package:easydev/services/endtime_reminder_service.dart';

// (선택) 오프라인 세션을 활용하고 싶다면 주석 해제하여 사용하세요.
// import 'package:easydev/offlines/offline_auth_service.dart';
// import 'package:easydev/offlines/offline_session_model.dart';

// ✅ 라우팅을 밖에서 수행하기 위한 목적지 enum
enum CommuteDestination { none, headquarter, type }

class OfflineCommuteInsideController {
  void initialize(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.area.trim();

      final alreadyInitialized =
          areaState.currentArea == areaToInit && areaState.capabilitiesOfCurrentArea.isNotEmpty;

      if (!alreadyInitialized) {
        await areaState.initializeArea(areaToInit);
        debugPrint('[GoToWork] initializeArea 호출: $areaToInit');
      } else {
        debugPrint('[GoToWork] 초기화 스킵 (이미 준비됨): $areaToInit');
      }

      debugPrint('[GoToWork] currentArea: ${areaState.currentArea}');
    });
  }

  // ✅ Firestore 의존 제거: 간단한 폴백 규칙으로 대체
  Future<CommuteDestination> _decideDestination(
      BuildContext context,
      UserState userState,
      ) async {
    if (!userState.isWorking) return CommuteDestination.none;
    if (!context.mounted) return CommuteDestination.none;

    // 기존(Firestore): 본사 여부 판단 → headquarter/type
    // 변경: 정보가 없으므로 기본 목적지를 'type'으로 보냄(업무유형 선택 페이지)
    return CommuteDestination.type;
  }

  // ✅ 버튼 경로: 모달 안에서 호출 — 상태 갱신 + 목적지 판단만 수행
  Future<CommuteDestination> handleWorkStatusAndDecide(
      BuildContext context,
      UserState userState,
      ) async {
    try {
      await _uploadAttendanceSilently(context); // (Sheets append)
      await userState.isHeWorking(); // 근무 상태 갱신

      return _decideDestination(context, userState);
    } catch (e) {
      _showWorkError(context);
      return CommuteDestination.none;
    }
  }

  // ✅ 자동 경로: (모달 아님) 현재 근무중이면 목적지 판단 후 즉시 라우팅
  void redirectIfWorking(BuildContext context, UserState userState) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dest = await _decideDestination(context, userState);
      if (!context.mounted) return;

      switch (dest) {
        case CommuteDestination.headquarter:
          Navigator.pushReplacementNamed(context, AppRoutes.headquarterPage);
          break;
        case CommuteDestination.type:
          Navigator.pushReplacementNamed(context, AppRoutes.typePage);
          break;
        case CommuteDestination.none:
          break;
      }
    });
  }

  Future<void> _uploadAttendanceSilently(BuildContext context) async {
    final userState = Provider.of<UserState>(context, listen: false);
    var area = userState.area;
    var name = userState.name;

    // (선택) 오프라인 세션을 활용하고 싶다면 아래 주석을 해제해서 폴백 사용
    // try {
    //   final session = await OfflineAuthService.instance.currentSession();
    //   area = (area.isEmpty) ? (session?.area ?? area) : area;
    //   name = (name.isEmpty) ? (session?.name ?? name) : name;
    // } catch (_) {}

    if (area.isEmpty || name.isEmpty) {
      // 업로드 필수 정보 부족 시 업로드 스킵
      return;
    }

    final now = DateTime.now();
    final nowTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final success = await OfflineCommuteInsideClockInLogUploader.uploadAttendanceJson(
      context: context,
      data: {
        'recordedTime': nowTime,
      },
    );

    if (!context.mounted) return;

    if (success) {
      showSuccessSnackbar(context, '출근 기록 업로드 완료');
      // ✅ SharedPreferences / EndtimeReminderService 제거
    } else {
      showFailedSnackbar(context, '출근 기록 업로드 실패');
    }
  }

  void _showWorkError(BuildContext context) {
    if (!context.mounted) return;
    showFailedSnackbar(context, '작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.');
  }
}
