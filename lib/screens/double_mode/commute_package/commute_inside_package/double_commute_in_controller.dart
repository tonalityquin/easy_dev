import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../routes.dart';
import '../../../../states/user/user_state.dart';
import '../../../../states/area/area_state.dart';
import '../../../../utils/snackbar_helper.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:easydev/services/endtime_reminder_service.dart';

import '../../../../repositories/commute_repo_services/commute_true_false_repository.dart';

import '../../../../utils/commute_true_false_mode_config.dart';
import 'utils/double_commute_in_clock_in_save.dart';

const kIsWorkingPrefsKey = 'isWorking';

enum DoubleCommuteDestination { none, headquarter, type }

class DoubleCommuteInController {
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
        debugPrint('[GoToWork] initializeArea 호출: $areaToInit');
      } else {
        debugPrint('[GoToWork] 초기화 스킵 (이미 준비됨): $areaToInit');
      }

      debugPrint('[GoToWork] currentArea: ${areaState.currentArea}');
    });
  }

  Future<DoubleCommuteDestination> _doubleDecideDestination(
      BuildContext context,
      UserState userState,
      ) async {
    if (!userState.isWorking) return DoubleCommuteDestination.none;
    if (!context.mounted) return DoubleCommuteDestination.none;

    final division = userState.user?.divisions.first ?? '';
    final area = userState.area;
    final docId = '$division-$area';

    try {
      final doc = await FirebaseFirestore.instance.collection('areas').doc(docId).get();

      if (!context.mounted) return DoubleCommuteDestination.none;

      final isHq = doc.exists && (doc.data()?['isHeadquarter'] == true);
      return isHq ? DoubleCommuteDestination.headquarter : DoubleCommuteDestination.type;
    } catch (e) {
      debugPrint('❌ _decideDestination 실패: $e');
      return DoubleCommuteDestination.none;
    }
  }

  Future<DoubleCommuteDestination> handleWorkStatusAndDecide(
      BuildContext context,
      UserState userState,
      ) async {
    try {
      await userState.ensureTodayClockInStatus();

      if (userState.hasClockInToday) {
        showFailedSnackbar(context, '이미 오늘 출근 기록이 있습니다.');
        return DoubleCommuteDestination.none;
      }

      final uploadResult = await _uploadAttendanceSilently(context);

      if (uploadResult == null || uploadResult.success != true) {
        return DoubleCommuteDestination.none;
      }

      await userState.isHeWorking();

      userState.markClockInToday();

      await _recordClockInAtToCommuteTrueFalse(userState);

      return _doubleDecideDestination(context, userState);
    } catch (e, st) {
      debugPrint('handleWorkStatusAndDecide error: $e\n$st');
      _showWorkError(context);
      return DoubleCommuteDestination.none;
    }
  }

  void redirectIfWorking(BuildContext context, UserState userState) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dest = await _doubleDecideDestination(context, userState);
      if (!context.mounted) return;

      switch (dest) {
        case DoubleCommuteDestination.headquarter:
          Navigator.pushReplacementNamed(context, AppRoutes.doubleHeadquarterPage);
          break;
        case DoubleCommuteDestination.type:
          Navigator.pushReplacementNamed(context, AppRoutes.doubleTypePage);
          break;
        case DoubleCommuteDestination.none:
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

    final result = await DoubleCommuteInClockInSave.uploadAttendanceJson(
      context: context,
      data: {
        'recordedTime': nowTime,
      },
    );

    if (!context.mounted) return null;

    if (result.success == true) {
      showSuccessSnackbar(context, result.message);

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
      debugPrint('[CommuteInsideController] commute_true_false OFF(기기 설정) → 업데이트 스킵');
      return;
    }

    final company = userState.division.trim();
    final area = userState.area.trim();
    final workerName = userState.name.trim();
    final clockInAt = DateTime.now();

    if (company.isEmpty || area.isEmpty || workerName.isEmpty) {
      debugPrint(
        '[CommuteInsideController] commute_true_false(clockInAt) 업데이트 스킵 '
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
        '[CommuteInsideController] commute_true_false(clockInAt) 반영 완료 '
            '(company="$company", area="$area", workerName="$workerName", clockInAt="$clockInAt")',
      );
    } catch (e, st) {
      debugPrint('[CommuteInsideController] commute_true_false(clockInAt) 업데이트 실패: $e\n$st');
    }
  }

  void _showWorkError(BuildContext context) {
    if (!context.mounted) return;
    showFailedSnackbar(
      context,
      '작업 처리 중 오류가 발생했습니다. 다시 시도해주세요.',
    );
  }
}
