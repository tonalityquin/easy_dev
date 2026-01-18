import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:easydev/routes.dart';
import 'package:easydev/services/endtime_reminder_service.dart';
import 'package:easydev/states/area/area_state.dart';
import 'package:easydev/states/user/user_state.dart';
import 'package:easydev/utils/snackbar_helper.dart';

import 'package:easydev/repositories/commute_repo_services/commute_true_false_repository.dart';
import 'package:easydev/utils/commute_true_false_mode_config.dart';

import 'utils/minor_commute_in_clock_in_save.dart';

const kIsWorkingPrefsKey = 'isWorking';

enum MinorCommuteDestination { none, headquarter, type }

class MinorCommuteInController {
  final CommuteTrueFalseRepository _commuteTrueFalseRepo = CommuteTrueFalseRepository();

  void initialize(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.area.trim();

      final alreadyInitialized =
          areaState.currentArea == areaToInit && areaState.capabilitiesOfCurrentArea.isNotEmpty;

      if (!alreadyInitialized) {
        await areaState.initializeArea(areaToInit);
        debugPrint('[Minor-GoToWork] initializeArea 호출: $areaToInit');
      } else {
        debugPrint('[Minor-GoToWork] 초기화 스킵 (이미 준비됨): $areaToInit');
      }

      debugPrint('[Minor-GoToWork] currentArea: ${areaState.currentArea}');
    });
  }

  Future<MinorCommuteDestination> _minorDecideDestination(
      BuildContext context,
      UserState userState,
      ) async {
    if (!userState.isWorking) return MinorCommuteDestination.none;
    if (!context.mounted) return MinorCommuteDestination.none;

    final division = userState.user?.divisions.first ?? '';
    final area = userState.area;
    final docId = '$division-$area';

    try {
      final doc = await FirebaseFirestore.instance.collection('areas').doc(docId).get();

      if (!context.mounted) return MinorCommuteDestination.none;

      final isHq = doc.exists && (doc.data()?['isHeadquarter'] == true);
      return isHq ? MinorCommuteDestination.headquarter : MinorCommuteDestination.type;
    } catch (e) {
      debugPrint('❌ [Minor] _decideDestination 실패: $e');
      return MinorCommuteDestination.none;
    }
  }

  Future<MinorCommuteDestination> handleWorkStatusAndDecide(
      BuildContext context,
      UserState userState,
      ) async {
    try {
      // 1) 오늘 출근 여부 캐시 보장 (실제 Firestore read는 UserState에서 하루 1번)
      await userState.ensureTodayClockInStatus();

      // 2) 이미 오늘 출근한 상태라면 중복 출근 방지
      if (userState.hasClockInToday) {
        showFailedSnackbar(context, '이미 오늘 출근 기록이 있습니다.');
        return MinorCommuteDestination.none;
      }

      // 3) 출근 로그 저장 + 로컬 isWorking prefs/알림 세팅
      final uploadResult = await _uploadAttendanceSilently(context);

      // 저장 실패/취소 시에는 여기서 종료
      if (uploadResult == null || uploadResult.success != true) {
        return MinorCommuteDestination.none;
      }

      // 4) 출근 성공 시: Firestore user_accounts.isWorking 토글(false → true)
      await userState.isHeWorking();

      // 5) 출근 성공 시: 오늘 출근했다는 사실을 캐시에 반영
      userState.markClockInToday();

      // 6) commute_true_false 에 "출근 시각" 기록 (Timestamp) - 설정 OFF면 스킵
      await _recordClockInAtToCommuteTrueFalse(userState);

      // 상태가 true면 목적지 결정
      return _minorDecideDestination(context, userState);
    } catch (e, st) {
      debugPrint('[Minor] handleWorkStatusAndDecide error: $e\n$st');
      _showWorkError(context);
      return MinorCommuteDestination.none;
    }
  }

  // ✅ 자동 경로: 현재 근무중이면 목적지 판단 후 즉시 라우팅
  void redirectIfWorking(BuildContext context, UserState userState) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dest = await _minorDecideDestination(context, userState);
      if (!context.mounted) return;

      switch (dest) {
        case MinorCommuteDestination.headquarter:
          Navigator.pushReplacementNamed(context, AppRoutes.minorHeadquarterPage);
          break;
        case MinorCommuteDestination.type:
          Navigator.pushReplacementNamed(context, AppRoutes.minorTypePage);
          break;
        case MinorCommuteDestination.none:
          break;
      }
    });
  }

  Future<dynamic> _uploadAttendanceSilently(BuildContext context) async {
    final userState = Provider.of<UserState>(context, listen: false);
    final area = userState.area;
    final name = userState.name;

    if (area.isEmpty || name.isEmpty) {
      showFailedSnackbar(
        context,
        '출근 기록 업로드 실패: 사용자 정보(area/name)가 비어 있습니다.\n'
            '관리자에게 계정/근무지 설정을 확인해 달라고 요청해 주세요.',
      );
      return null;
    }

    final now = DateTime.now();
    final nowTime = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';

    final result = await MinorCommuteInClockInSave.uploadAttendanceJson(
      context: context,
      data: {
        'recordedTime': nowTime,
      },
    );

    if (!context.mounted) return null;

    if (result.success == true) {
      showSuccessSnackbar(context, result.message);

      // ✅ 출근 상태를 로컬에 저장하고, 알림을 즉시 반영
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kIsWorkingPrefsKey, true);

      final end = prefs.getString('endTime');
      if (end != null && end.isNotEmpty) {
        await EndTimeReminderService.instance.scheduleDailyOneHourBefore(end);
      }
    } else {
      showFailedSnackbar(context, result.message);
    }

    return result;
  }

  Future<void> _recordClockInAtToCommuteTrueFalse(UserState userState) async {
    final enabled = await CommuteTrueFalseModeConfig.isEnabled();
    if (!enabled) {
      debugPrint('[MinorCommuteInController] commute_true_false OFF(기기 설정) → 업데이트 스킵');
      return;
    }

    final company = userState.division.trim();
    final area = userState.area.trim();
    final workerName = userState.name.trim();
    final clockInAt = DateTime.now();

    if (company.isEmpty || area.isEmpty || workerName.isEmpty) {
      debugPrint(
        '[MinorCommuteInController] commute_true_false(clockInAt) 업데이트 스킵 '
            '(company="$company", area="$area", workerName="$workerName")',
      );
      return;
    }

    try {
      await _commuteTrueFalseRepo.setClockInAt(
        company: company,
        area: area,
        workerName: workerName,
        clockInAt: clockInAt,
      );
      debugPrint(
        '[MinorCommuteInController] commute_true_false(clockInAt) 반영 완료 '
            '(company="$company", area="$area", workerName="$workerName", clockInAt="$clockInAt")',
      );
    } catch (e, st) {
      debugPrint('[MinorCommuteInController] commute_true_false(clockInAt) 업데이트 실패: $e\n$st');
    }
  }

  void _showWorkError(BuildContext context) {
    if (!context.mounted) return;
    showFailedSnackbar(context, '작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.');
  }
}
