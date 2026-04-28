import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/config/commute_true_false_mode_config.dart';
import '../../../app/init/work_schedule_prefs.dart';
import '../../../features/account/applications/user_state.dart';
import '../../dev/application/area_state.dart';
import '../../dev/domain/repositories/area_repo_package/area_repository.dart';
import '../domain/repositories/commute_true_false_repository.dart';
import '../utils/commute_clock_in_save.dart';
import '../utils/commute_mode_spec.dart';
const kIsWorkingPrefsKey = 'isWorking';

enum CommuteDestination { none, headquarter, type }

enum CommuteResultType { success, alreadyWorked, failure }

class CommuteResult {
  const CommuteResult({
    required this.type,
    required this.destination,
  });

  final CommuteResultType type;
  final CommuteDestination destination;
}

class CommonCommuteInController {
  CommonCommuteInController({required this.spec});

  final CommuteModeSpec spec;
  final CommuteTrueFalseRepository _commuteTrueFalseRepo =
      CommuteTrueFalseRepository();

  void initialize(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.area.trim();

      final alreadyInitialized = areaState.currentArea == areaToInit &&
          areaState.capabilitiesOfCurrentArea.isNotEmpty;

      if (!alreadyInitialized) {
        await areaState.initializeArea(areaToInit);
        debugPrint('[${spec.modeKey}] initializeArea 호출: $areaToInit');
      } else {
        debugPrint('[${spec.modeKey}] 초기화 스킵 (이미 준비됨): $areaToInit');
      }

      debugPrint('[${spec.modeKey}] currentArea: ${areaState.currentArea}');
    });
  }

  Future<CommuteDestination> _decideDestination(
    BuildContext context,
    UserState userState,
  ) async {
    if (!userState.isWorking) return CommuteDestination.none;
    if (!context.mounted) return CommuteDestination.none;

    final divisions = userState.session?.divisions ?? const <String>[];
    final division = divisions.isNotEmpty ? divisions.first : '';
    final area = userState.area;

    try {
      final areaRepository = context.read<AreaRepository>();
      final isHeadquarter = await areaRepository.isHeadquarter(
        division: division,
        area: area,
      );

      if (!context.mounted) return CommuteDestination.none;

      return isHeadquarter
          ? CommuteDestination.headquarter
          : CommuteDestination.type;
    } catch (e) {
      debugPrint('❌ [${spec.modeKey}] _decideDestination 실패: $e');
      return CommuteDestination.none;
    }
  }

  Future<CommuteResult> handleWorkStatusAndDecide(
    BuildContext context,
    UserState userState,
  ) async {
    try {
      await userState.ensureTodayClockInStatus();

      if (userState.hasClockInToday) {
        return const CommuteResult(
          type: CommuteResultType.alreadyWorked,
          destination: CommuteDestination.none,
        );
      }

      final uploadResult = await _uploadAttendanceSilently(context);

      if (uploadResult == null || uploadResult.success != true) {
        return const CommuteResult(
          type: CommuteResultType.failure,
          destination: CommuteDestination.none,
        );
      }

      await userState.isHeWorking();
      userState.markClockInToday();
      await _recordClockInAtToCommuteTrueFalse(userState);

      final destination = await _decideDestination(context, userState);
      return CommuteResult(
        type: CommuteResultType.success,
        destination: destination,
      );
    } catch (e, st) {
      debugPrint('[${spec.modeKey}] handleWorkStatusAndDecide error: $e\n$st');
      return const CommuteResult(
        type: CommuteResultType.failure,
        destination: CommuteDestination.none,
      );
    }
  }

  void redirectIfWorking(BuildContext context, UserState userState) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final dest = await _decideDestination(context, userState);
      if (!context.mounted) return;

      switch (dest) {
        case CommuteDestination.headquarter:
          Navigator.pushReplacementNamed(context, spec.headquarterRoute);
          break;
        case CommuteDestination.type:
          Navigator.pushReplacementNamed(context, spec.typeRoute);
          break;
        case CommuteDestination.none:
          break;
      }
    });
  }

  Future<dynamic> _uploadAttendanceSilently(BuildContext context) async {
    final userState = Provider.of<UserState>(context, listen: false);
    final area = userState.area;
    final name = userState.name;

    if (area.isEmpty || name.isEmpty) {
      return null;
    }

    final result = await CommuteClockInSave.saveWorkIn(
      context: context,
      logPrefix: spec.saveLogPrefix,
    );

    if (!context.mounted) return null;

    if (result.success == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kIsWorkingPrefsKey, true);
      await WorkSchedulePrefs.refreshReminderFromPrefs(prefs);
    }

    return result;
  }

  Future<void> _recordClockInAtToCommuteTrueFalse(UserState userState) async {
    final enabled = await CommuteTrueFalseModeConfig.isEnabled();
    if (!enabled) {
      debugPrint(
        '[${spec.modeKey}] commute_true_false OFF(기기 설정) → 업데이트 스킵',
      );
      return;
    }

    final company = userState.division.trim();
    final area = userState.area.trim();
    final workerName = userState.name.trim();
    final clockInAt = DateTime.now();

    if (company.isEmpty || area.isEmpty || workerName.isEmpty) {
      debugPrint(
        '[${spec.modeKey}] commute_true_false(clockInAt) 업데이트 스킵 '
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
        '[${spec.modeKey}] commute_true_false(clockInAt) 반영 완료 '
        '(company="$company", area="$area", workerName="$workerName", clockInAt="$clockInAt")',
      );
    } catch (e, st) {
      debugPrint(
        '[${spec.modeKey}] commute_true_false(clockInAt) 업데이트 실패: $e\n$st',
      );
    }
  }
}
