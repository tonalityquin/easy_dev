import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../account/applications/user_state.dart';
import '../../attendance/application/common_attendance_service.dart';
import '../../dev/application/area_state.dart';
import '../utils/commute_mode_spec.dart';

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

  void initialize(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) return;
      final userState = context.read<UserState>();
      final areaState = context.read<AreaState>();
      final areaToInit = userState.currentArea.trim();
      final divisionToInit = areaState.currentDivision.trim().isNotEmpty
          ? areaState.currentDivision.trim()
          : userState.division.trim();

      final alreadyInitialized = areaState.hasCurrentRecordFor(
        division: divisionToInit,
        area: areaToInit,
      );

      if (!alreadyInitialized && areaToInit.isNotEmpty && divisionToInit.isNotEmpty) {
        await areaState.initializeArea(
          areaToInit,
          division: divisionToInit,
        );
        debugPrint(
          '[${spec.diagnosticKey}] AreaRecord 초기화 fallback 호출: $divisionToInit/$areaToInit',
        );
      } else {
        debugPrint(
          '[${spec.diagnosticKey}] AreaRecord 초기화 스킵: 현재 업무지역 세션 사용 $divisionToInit/$areaToInit',
        );
      }

      debugPrint(
        '[${spec.diagnosticKey}] currentArea=${areaState.currentArea}, currentDivision=${areaState.currentDivision}, hasRecord=${areaState.currentRecord != null}',
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

    final areaState = context.read<AreaState>();
    final division = areaState.currentDivision.trim().isNotEmpty
        ? areaState.currentDivision.trim()
        : userState.division.trim();
    final area = userState.currentArea.trim();

    try {
      trace?.log(
        '목적지 판정을 시작합니다: context=${spec.diagnosticKey}, division=$division, area=$area, cacheAvailable=${areaState.hasCurrentRecordFor(division: division, area: area)}',
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
    } catch (error, stackTrace) {
      final message =
          '[${spec.diagnosticKey}] _decideDestination 실패: $error';
      if (trace != null) {
        trace.log(message, progress: 0.96);
        trace.log('목적지 판정 스택 추적: $stackTrace', progress: 0.96);
      } else {
        debugPrint('$message\n$stackTrace');
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
      initialMessage: '공통 출근 처리와 현재 업무지역 검증을 시작합니다.',
      useCommonUi: true,
      developerModeMessage:
          '개발자 모드 ON: 공통 Attendance, Firebase 근무상태, 현재 업무지역을 Status Dialog에 표시합니다.',
      standardModeMessage:
          '개발자 모드 OFF: 공통 출근 처리 상태를 debugPrint로 기록합니다.',
    );

    try {
      final attendanceResult = await CommonAttendanceService.clockIn(
        context,
        source: 'commute_gate:${spec.diagnosticKey}',
        modeKey: spec.modeKey,
        isHeadquarter: spec.isHeadquarterContext ? true : null,
        trace: trace,
      );

      if (attendanceResult.alreadyRecorded) {
        await trace.succeed(attendanceResult.message);
        return const CommuteResult(
          type: CommuteResultType.alreadyWorked,
          destination: CommuteDestination.none,
        );
      }

      if (!attendanceResult.success) {
        await trace.fail(attendanceResult.message);
        return const CommuteResult(
          type: CommuteResultType.failure,
          destination: CommuteDestination.none,
        );
      }

      final destination = await _decideDestination(
        context,
        userState,
        trace: trace,
      );
      await trace.succeed(
        '공통 출근 처리가 완료되었습니다: context=${spec.diagnosticKey}, destination=$destination',
      );
      return CommuteResult(
        type: CommuteResultType.success,
        destination: destination,
      );
    } catch (error, stackTrace) {
      await trace.fail(
        '공통 출근 처리 중 오류가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
      return const CommuteResult(
        type: CommuteResultType.failure,
        destination: CommuteDestination.none,
      );
    }
  }

  void redirectIfWorking(BuildContext context, UserState userState) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final destination = await _decideDestination(context, userState);
      if (!context.mounted) return;

      switch (destination) {
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
}
