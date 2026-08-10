import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/config/commute_true_false_mode_config.dart';
import '../../../app/init/work_schedule_prefs.dart';
import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../../features/account/applications/user_state.dart';
import '../../dev/application/area_state.dart';
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
      if (!context.mounted) return;
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.area.trim();
      final divisionToInit = userState.division.trim();

      final alreadyInitialized = areaState.hasCurrentRecordFor(
        division: divisionToInit,
        area: areaToInit,
      );

      if (!alreadyInitialized) {
        await areaState.initializeArea(
          areaToInit,
          division: divisionToInit,
        );
        debugPrint(
          '[${spec.modeKey}] AreaRecord 초기화 fallback 호출: $divisionToInit/$areaToInit',
        );
      } else {
        debugPrint(
          '[${spec.modeKey}] AreaRecord 초기화 스킵: 로그인 세션 캐시 사용 $divisionToInit/$areaToInit',
        );
      }

      debugPrint(
        '[${spec.modeKey}] currentArea=${areaState.currentArea}, currentDivision=${areaState.currentDivision}, hasRecord=${areaState.currentRecord != null}',
      );
    });
  }

  Future<CommuteDestination> _decideDestination(
    BuildContext context,
    UserState userState, {
    DeveloperOperationTrace? trace,
  }) async {
    if (!userState.isWorking) {
      trace?.log('근무 상태가 아니므로 목적지 결정을 중단합니다.', progress: 0.8);
      return CommuteDestination.none;
    }
    if (!context.mounted) return CommuteDestination.none;

    final division = userState.division.trim();
    final area = userState.area.trim();

    try {
      final areaState = context.read<AreaState>();
      trace?.log(
        '목적지 판정을 시작합니다: division=$division, area=$area, cacheAvailable=${areaState.hasCurrentRecordFor(division: division, area: area)}',
        progress: 0.82,
      );
      final isHeadquarter = await areaState.resolveIsHeadquarter(
        division: division,
        area: area,
        onLog: trace?.log,
      );

      if (!context.mounted) return CommuteDestination.none;

      final destination = isHeadquarter
          ? CommuteDestination.headquarter
          : CommuteDestination.type;
      trace?.log(
        '목적지 판정 완료: isHeadquarter=$isHeadquarter, destination=$destination',
        progress: 0.96,
      );
      return destination;
    } catch (e, st) {
      final message = '[${spec.modeKey}] _decideDestination 실패: $e';
      if (trace != null) {
        trace.log(message, progress: 0.96);
        trace.log('목적지 판정 스택 추적: $st', progress: 0.96);
      } else {
        debugPrint('$message\n$st');
      }
      return CommuteDestination.none;
    }
  }

  Future<CommuteResult> handleWorkStatusAndDecide(
    BuildContext context,
    UserState userState,
  ) async {
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '출근 처리 상태',
      initialMessage: '출근 처리와 Area 세션 캐시 검증을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 출근 처리, Firebase 반영, Area cache hit/fallback을 Status Dialog에 표시합니다.',
      standardModeMessage:
          '개발자 모드 OFF: 출근 처리 상태를 debugPrint로 기록합니다.',
    );

    try {
      trace.log('오늘 출근 여부를 확인합니다.', progress: 0.08);
      await userState.ensureTodayClockInStatus();

      if (userState.hasClockInToday) {
        await trace.succeed('오늘 출근 기록이 이미 존재하여 추가 출근 처리를 중단합니다.');
        return const CommuteResult(
          type: CommuteResultType.alreadyWorked,
          destination: CommuteDestination.none,
        );
      }

      trace.log('로컬 출근 시각 저장을 시작합니다.', progress: 0.18);
      final uploadResult = await _uploadAttendanceSilently(
        context,
        trace: trace,
      );

      if (uploadResult == null || uploadResult.success != true) {
        await trace.fail('로컬 출근 시각 저장에 실패했습니다.');
        return const CommuteResult(
          type: CommuteResultType.failure,
          destination: CommuteDestination.none,
        );
      }

      trace.log('사용자 근무 상태를 Firebase에 반영합니다.', progress: 0.44);
      await userState.isHeWorking();
      trace.log(
        '사용자 근무 상태 반영 완료: isWorking=${userState.isWorking}',
        progress: 0.58,
      );

      userState.markClockInToday();
      trace.log('오늘 출근 캐시를 완료 상태로 갱신했습니다.', progress: 0.64);

      await _recordClockInAtToCommuteTrueFalse(
        userState,
        trace: trace,
      );

      final destination = await _decideDestination(
        context,
        userState,
        trace: trace,
      );
      await trace.succeed(
        '출근 처리가 완료되었습니다: destination=$destination',
      );
      return CommuteResult(
        type: CommuteResultType.success,
        destination: destination,
      );
    } catch (e, st) {
      await trace.fail(
        '출근 처리 중 오류가 발생했습니다.',
        error: e,
        stackTrace: st,
      );
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

  Future<dynamic> _uploadAttendanceSilently(
    BuildContext context, {
    DeveloperOperationTrace? trace,
  }) async {
    final userState = Provider.of<UserState>(context, listen: false);
    final area = userState.area;
    final name = userState.name;

    if (area.isEmpty || name.isEmpty) {
      trace?.log(
        '출근 저장에 필요한 사용자 정보가 없습니다: area="$area", name="$name"',
        progress: 0.22,
      );
      return null;
    }

    final result = await CommuteClockInSave.saveWorkIn(
      context: context,
      logPrefix: spec.saveLogPrefix,
    );

    if (!context.mounted) return null;

    if (result.success == true) {
      trace?.log('SQLite 출근 시각 저장 완료.', progress: 0.3);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(kIsWorkingPrefsKey, true);
      await WorkSchedulePrefs.refreshReminderFromPrefs(prefs);
      trace?.log(
        '로컬 isWorking 및 퇴근 알림 상태 갱신 완료.',
        progress: 0.38,
      );
    }

    return result;
  }

  Future<void> _recordClockInAtToCommuteTrueFalse(
    UserState userState, {
    DeveloperOperationTrace? trace,
  }) async {
    final enabled = await CommuteTrueFalseModeConfig.isEnabled();
    if (!enabled) {
      final message =
          '[${spec.modeKey}] commute_true_false OFF 기기 설정으로 업데이트를 건너뜁니다.';
      if (trace != null) {
        trace.log(message, progress: 0.72);
      } else {
        debugPrint(message);
      }
      return;
    }

    final company = userState.division.trim();
    final area = userState.area.trim();
    final workerName = userState.name.trim();
    final clockInAt = DateTime.now();

    if (company.isEmpty || area.isEmpty || workerName.isEmpty) {
      final message =
          '[${spec.modeKey}] commute_true_false 업데이트 스킵: company="$company", area="$area", workerName="$workerName"';
      if (trace != null) {
        trace.log(message, progress: 0.72);
      } else {
        debugPrint(message);
      }
      return;
    }

    try {
      await _commuteTrueFalseRepo.setClockInAt(
        company: company,
        area: area,
        workerName: workerName,
        clockInAt: clockInAt,
      );
      final message =
          '[${spec.modeKey}] commute_true_false 반영 완료: company="$company", area="$area", workerName="$workerName", clockInAt="$clockInAt"';
      if (trace != null) {
        trace.log(message, progress: 0.76);
      } else {
        debugPrint(message);
      }
    } catch (e, st) {
      final message =
          '[${spec.modeKey}] commute_true_false 업데이트 실패: $e';
      if (trace != null) {
        trace.log(message, progress: 0.76);
        trace.log('commute_true_false 스택 추적: $st', progress: 0.76);
      } else {
        debugPrint('$message\n$st');
      }
    }
  }
}
