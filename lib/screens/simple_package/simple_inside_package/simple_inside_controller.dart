// lib/screens/simple_package/simple_inside_package/simple_inside_controller.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../routes.dart';
import '../../../states/user/user_state.dart';
import '../../../states/area/area_state.dart';
import '../../../utils/snackbar_helper.dart';
import 'utils/simple_inside_clock_in_log_uploader.dart';
// import '../../../utils/usage_reporter.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:easydev/services/endtime_reminder_service.dart';

const kIsWorkingPrefsKey = 'isWorking';

// ✅ 라우팅을 밖에서 수행하기 위한 목적지 enum
enum SimpleDestination { none, headquarter, type }

class SimpleInsideController {
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

  Future<SimpleDestination> _decideDestination(
    BuildContext context,
    UserState userState,
  ) async {
    if (!userState.isWorking) return SimpleDestination.none;
    if (!context.mounted) return SimpleDestination.none;

    final division = userState.user?.divisions.first ?? '';
    final area = userState.area;
    final docId = '$division-$area';

    try {
      final doc = await FirebaseFirestore.instance.collection('areas').doc(docId).get();

      /*await UsageReporter.instance.report(
       area: area.isNotEmpty ? area : 'unknown',
       action: 'read',
       n: 1,
       source: 'SimpleInsideController._decideDestination/areas.doc.get',
     );*/

      if (!context.mounted) return SimpleDestination.none;

      final isHq = doc.exists && (doc.data()?['isHeadquarter'] == true);
      return isHq ? SimpleDestination.headquarter : SimpleDestination.type;
    } catch (e) {
      debugPrint('❌ _decideDestination 실패: $e');
      return SimpleDestination.none;
    }
  }

  // ✅ 버튼 경로: 모달 안에서 호출 — 상태 갱신 + 목적지 판단만 수행
  Future<SimpleDestination> handleWorkStatusAndDecide(
    BuildContext context,
    UserState userState,
  ) async {
    try {
      // 1) 오늘 출근 여부 캐시 보장 (실제 Firestore read는 UserState에서 하루 1번)
      await userState.ensureTodayClockInStatus();

      // 2) 이미 오늘 출근한 상태라면 중복 출근 방지
      if (userState.hasClockInToday) {
        showFailedSnackbar(context, '이미 오늘 출근 기록이 있습니다.');
        return SimpleDestination.none;
      }

      // 3) 출근 로그 업로드 + 로컬 isWorking prefs/알림 세팅
      final uploadResult = await _uploadAttendanceSilently(context);

      // 업로드 실패/취소 시에는 여기서 종료
      if (uploadResult == null || uploadResult.success != true) {
        return SimpleDestination.none;
      }

      // 4) 출근 성공 시: Firestore user_accounts.isWorking 토글(false → true)
      await userState.isHeWorking();

      // 5) 출근 성공 시: 오늘 출근했다는 사실을 캐시에 반영
      userState.markClockInToday();

      // 상태가 true면 목적지 결정
      return _decideDestination(context, userState);
    } catch (e, st) {
      debugPrint('handleWorkStatusAndDecide error: $e\n$st');
      _showWorkError(context);
      return SimpleDestination.none;
    }
  }

  // ✅ 자동 경로: (모달 아님) 현재 근무중이면 목적지 판단 후 즉시 라우팅
  void redirectIfWorking(BuildContext context, UserState userState) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dest = await _decideDestination(context, userState);
      if (!context.mounted) return;

      switch (dest) {
        case SimpleDestination.headquarter:
          Navigator.pushReplacementNamed(context, AppRoutes.headquarterPage);
          break;
        case SimpleDestination.type:
          Navigator.pushReplacementNamed(context, AppRoutes.typePage);
          break;
        case SimpleDestination.none:
          break;
      }
    });
  }

  /// 출근 기록을 Firestore에 업로드하고,
  /// 성공 시 로컬 isWorking prefs 및 퇴근 알림까지 세팅하는 헬퍼.
  ///
  /// - 성공/실패 여부는 반환값의 `success` 필드로 판단(dynamic 사용)
  /// - 스낵바는 이 함수 안에서 처리
  Future<dynamic> _uploadAttendanceSilently(BuildContext context) async {
    final userState = Provider.of<UserState>(context, listen: false);
    final area = userState.area;
    final name = userState.name;

    if (area.isEmpty || name.isEmpty) {
      // 사용자 정보 자체가 잘못된 케이스도 스낵바로 알려주고 싶다면 이렇게:
      showFailedSnackbar(
        context,
        '출근 기록 업로드 실패: 사용자 정보(area/name)가 비어 있습니다.\n'
        '관리자에게 계정/근무지 설정을 확인해 달라고 요청해 주세요.',
      );
      return null;
    }

    final now = DateTime.now();
    final nowTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    // ⬇️ bool 이 아니라 SheetUploadResult 가 반환됨 (dynamic 으로 취급)
    final result = await SimpleInsideClockInLogUploader.uploadAttendanceJson(
      context: context,
      data: {
        'recordedTime': nowTime,
      },
    );

    if (!context.mounted) return null;

    if (result.success == true) {
      // 🔔 업로더가 만들어준 구체 메시지를 그대로 사용
      showSuccessSnackbar(context, result.message);

      // ✅ 출근 상태를 로컬에 저장하고, 알림을 즉시 반영
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kIsWorkingPrefsKey, true);
      final end = prefs.getString('endTime');
      if (end != null && end.isNotEmpty) {
        await EndtimeReminderService.instance.scheduleDailyOneHourBefore(end);
      }
    } else {
      // 실패 사유를 담은 메시지를 그대로 노출
      showFailedSnackbar(context, result.message);
    }

    return result;
  }

  void _showWorkError(BuildContext context) {
    if (!context.mounted) return;
    showFailedSnackbar(
      context,
      '작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.',
    );
  }
}
