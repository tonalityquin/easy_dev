import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/config/commute_true_false_mode_config.dart';
import '../../../app/init/work_schedule_prefs.dart';
import '../../../app/utils/developer_operation_status_dialog.dart';
import '../../account/applications/user_state.dart';
import '../../commute/domain/repositories/commute_true_false_repository.dart';
import '../../dashboard/applications/common/endtime_reminder_service.dart';
import '../../dev/application/area_state.dart';
import '../../mode_single/application/att_brk_repository.dart';
import '../domain/attendance_action_result.dart';
import '../domain/attendance_context.dart';
import 'attendance_diagnostics.dart';

class CommonAttendanceService {
  CommonAttendanceService._();

  static final CommuteTrueFalseRepository _commuteTrueFalseRepository =
      CommuteTrueFalseRepository();

  static AttendanceContext? resolveContext(
    BuildContext context, {
    required String source,
    String modeKey = '',
    bool? isHeadquarter,
  }) {
    final userState = context.read<UserState>();
    final session = userState.session;
    if (session == null) return null;
    final areaState = context.read<AreaState>();
    final currentArea = userState.currentArea.trim();
    final areaStateDivision = areaState.currentDivision.trim();
    final division =
        areaStateDivision.isNotEmpty ? areaStateDivision : userState.division.trim();
    final record = areaState.currentRecord;
    final resolvedIsHeadquarter = isHeadquarter ??
        (record != null &&
            record.name.trim() == currentArea &&
            record.isHeadquarter);
    return AttendanceContext(
      userId: session.id.trim(),
      userName: session.displayName.trim(),
      area: currentArea,
      division: division,
      isHeadquarter: resolvedIsHeadquarter,
      modeKey: resolvedIsHeadquarter ? '' : modeKey.trim(),
      source: source.trim().isEmpty ? 'unknown' : source.trim(),
    );
  }

  static Future<AttendanceActionResult> clockIn(
    BuildContext context, {
    required String source,
    String modeKey = '',
    bool? isHeadquarter,
    DeveloperOperationTrace? trace,
    DateTime? recordedAt,
  }) async {
    final attendance = resolveContext(
      context,
      source: source,
      modeKey: modeKey,
      isHeadquarter: isHeadquarter,
    );
    if (attendance == null || !attendance.isValid) {
      const message = '출근 처리에 필요한 사용자 또는 업무 지역 정보가 없습니다.';
      _record(
        'clock_in_invalid_context',
        attendance,
        trace: trace,
        extra: const <String, Object?>{'message': message},
      );
      return const AttendanceActionResult.failure(message: message);
    }

    final userState = context.read<UserState>();
    try {
      _record('clock_in_start', attendance, trace: trace);
      await userState.ensureTodayClockInStatus();
      if (userState.hasClockInToday) {
        const message = '오늘 출근 기록이 이미 존재합니다.';
        _record(
          'clock_in_already_recorded',
          attendance,
          trace: trace,
          extra: const <String, Object?>{'message': message},
        );
        return const AttendanceActionResult.alreadyRecorded(message: message);
      }

      final now = recordedAt ?? DateTime.now();
      await AttBrkRepository.instance.insertEvent(
        dateTime: now,
        type: AttBrkModeType.workIn,
      );
      _record(
        'clock_in_local_saved',
        attendance,
        trace: trace,
        extra: <String, Object?>{'at': now.toIso8601String()},
      );

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isWorking', true);
      await WorkSchedulePrefs.refreshReminderFromPrefs(prefs);
      await userState.setWorkingStatus(true);
      userState.markClockInToday();
      _record(
        'clock_in_working_state_updated',
        attendance,
        trace: trace,
        extra: <String, Object?>{
          'isWorking': userState.isWorking,
          'firebaseWrite': 1,
        },
      );

      await _recordClockInAtToCommuteTrueFalse(
        attendance,
        now,
        trace: trace,
      );

      return AttendanceActionResult.success(
        recordedAt: now,
        message: '출근 기록이 완료되었습니다.',
      );
    } catch (error, stackTrace) {
      _record(
        'clock_in_failure',
        attendance,
        trace: trace,
        extra: <String, Object?>{
          'error': error,
          'stack': stackTrace,
        },
      );
      return AttendanceActionResult.failure(
        message: '출근 처리 중 오류가 발생했습니다: $error',
      );
    }
  }

  static Future<AttendanceActionResult> recordBreak(
    BuildContext context, {
    required String source,
    String modeKey = '',
    bool? isHeadquarter,
    DateTime? recordedAt,
    DeveloperOperationTrace? trace,
  }) async {
    final attendance = resolveContext(
      context,
      source: source,
      modeKey: modeKey,
      isHeadquarter: isHeadquarter,
    );
    if (attendance == null || !attendance.isValid) {
      const message = '휴게 처리에 필요한 사용자 또는 업무 지역 정보가 없습니다.';
      _record(
        'break_invalid_context',
        attendance,
        trace: trace,
        extra: const <String, Object?>{'message': message},
      );
      return const AttendanceActionResult.failure(message: message);
    }

    final now = recordedAt ?? DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final requiresBreak = WorkSchedulePrefs.requiresBreakOnDateFromPrefs(
        prefs,
        now,
        defaultWhenUnset: true,
      );
      final events = await AttBrkRepository.instance.getEventsForDate(now);
      final hasWorkIn = events.containsKey(AttBrkModeType.workIn);
      final hasWorkOut = events.containsKey(AttBrkModeType.workOut);
      final hasBreak = events.containsKey(AttBrkModeType.breakTime);
      _record(
        'break_policy_check',
        attendance,
        trace: trace,
        extra: <String, Object?>{
          'requiresBreak': requiresBreak,
          'hasWorkIn': hasWorkIn,
          'hasWorkOut': hasWorkOut,
          'hasBreak': hasBreak,
          'scheduledTimeRequired': false,
        },
      );
      if (!requiresBreak) {
        const message = '선택한 날짜에는 휴게가 활성화되어 있지 않습니다.';
        _record(
          'break_blocked_not_required',
          attendance,
          trace: trace,
          extra: const <String, Object?>{'message': message},
        );
        return const AttendanceActionResult.failure(message: message);
      }
      if (!hasWorkIn) {
        const message = '출근 기록 후 휴게를 기록할 수 있습니다.';
        _record(
          'break_blocked_without_clock_in',
          attendance,
          trace: trace,
          extra: const <String, Object?>{'message': message},
        );
        return const AttendanceActionResult.failure(message: message);
      }
      if (hasWorkOut) {
        const message = '퇴근이 완료된 뒤에는 휴게를 기록할 수 없습니다.';
        _record(
          'break_blocked_after_clock_out',
          attendance,
          trace: trace,
          extra: const <String, Object?>{'message': message},
        );
        return const AttendanceActionResult.failure(message: message);
      }
      _record(
        'break_start',
        attendance,
        trace: trace,
        extra: <String, Object?>{
          'at': now.toIso8601String(),
          'repunch': hasBreak,
        },
      );
      await AttBrkRepository.instance.insertEvent(
        dateTime: now,
        type: AttBrkModeType.breakTime,
      );
      await prefs.setString('last_break_date', _dateKey(now));
      _record(
        'break_complete',
        attendance,
        trace: trace,
        extra: <String, Object?>{'at': now.toIso8601String()},
      );
      return AttendanceActionResult.success(
        recordedAt: now,
        message: '휴게 기록이 완료되었습니다.',
      );
    } catch (error, stackTrace) {
      _record(
        'break_failure',
        attendance,
        trace: trace,
        extra: <String, Object?>{
          'error': error,
          'stack': stackTrace,
        },
      );
      return AttendanceActionResult.failure(
        message: '휴게 처리 중 오류가 발생했습니다: $error',
      );
    }
  }

  static Future<AttendanceActionResult> clockOut(
    BuildContext context, {
    required String source,
    String modeKey = '',
    bool? isHeadquarter,
    DateTime? recordedAt,
    DeveloperOperationTrace? trace,
  }) async {
    final attendance = resolveContext(
      context,
      source: source,
      modeKey: modeKey,
      isHeadquarter: isHeadquarter,
    );
    if (attendance == null || !attendance.isValid) {
      const message = '퇴근 처리에 필요한 사용자 또는 업무 지역 정보가 없습니다.';
      _record(
        'clock_out_invalid_context',
        attendance,
        trace: trace,
        extra: const <String, Object?>{'message': message},
      );
      return const AttendanceActionResult.failure(message: message);
    }

    final now = recordedAt ?? DateTime.now();
    final affectsWorkingState = _isToday(now);
    final userState = context.read<UserState>();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final requiresBreak = WorkSchedulePrefs.requiresBreakOnDateFromPrefs(
        prefs,
        now,
        defaultWhenUnset: true,
      );
      final events = await AttBrkRepository.instance.getEventsForDate(now);
      final hasWorkIn = events.containsKey(AttBrkModeType.workIn);
      final hasBreak = events.containsKey(AttBrkModeType.breakTime);
      final hasWorkOut = events.containsKey(AttBrkModeType.workOut);
      _record(
        'clock_out_policy_check',
        attendance,
        trace: trace,
        extra: <String, Object?>{
          'requiresBreak': requiresBreak,
          'hasWorkIn': hasWorkIn,
          'hasBreak': hasBreak,
          'hasWorkOut': hasWorkOut,
          'scheduledTimeRequired': false,
        },
      );
      if (!hasWorkIn) {
        const message = '출근 기록 후 퇴근할 수 있습니다.';
        _record(
          'clock_out_blocked_without_clock_in',
          attendance,
          trace: trace,
          extra: const <String, Object?>{'message': message},
        );
        return const AttendanceActionResult.failure(message: message);
      }
      if (hasWorkOut) {
        const message = '선택한 날짜의 퇴근 기록이 이미 존재합니다.';
        _record(
          'clock_out_already_recorded',
          attendance,
          trace: trace,
          extra: const <String, Object?>{'message': message},
        );
        return const AttendanceActionResult.alreadyRecorded(message: message);
      }
      if (requiresBreak && !hasBreak) {
        const message = '휴게를 기록한 뒤 퇴근할 수 있습니다.';
        _record(
          'clock_out_blocked_break_required',
          attendance,
          trace: trace,
          extra: const <String, Object?>{'message': message},
        );
        return const AttendanceActionResult.failure(message: message);
      }
      _record(
        'clock_out_start',
        attendance,
        trace: trace,
        extra: <String, Object?>{
          'at': now.toIso8601String(),
          'affectsWorkingState': affectsWorkingState,
          'isWorkingBefore': userState.isWorking,
        },
      );
      await AttBrkRepository.instance.insertEvent(
        dateTime: now,
        type: AttBrkModeType.workOut,
      );
      _record(
        'clock_out_local_saved',
        attendance,
        trace: trace,
        extra: <String, Object?>{'at': now.toIso8601String()},
      );

      if (affectsWorkingState) {
        await prefs.setBool('isWorking', false);
        await EndTimeReminderService.instance.cancel();
        await userState.setWorkingStatus(false);
        _record(
          'clock_out_working_state_updated',
          attendance,
          trace: trace,
          extra: <String, Object?>{
            'isWorking': userState.isWorking,
            'firebaseWrite': 1,
          },
        );
      }

      _record(
        'clock_out_remote_sync_skipped',
        attendance,
        trace: trace,
        extra: const <String, Object?>{
          'policy': 'local_first',
          'firebaseRead': 0,
          'firebaseWrite': 0,
        },
      );


      return AttendanceActionResult.success(
        recordedAt: now,
        message: '퇴근 기록이 완료되었습니다.',
      );
    } catch (error, stackTrace) {
      _record(
        'clock_out_failure',
        attendance,
        trace: trace,
        extra: <String, Object?>{
          'error': error,
          'stack': stackTrace,
        },
      );
      return AttendanceActionResult.failure(
        message: '퇴근 처리 중 오류가 발생했습니다: $error',
      );
    }
  }

  static Future<AttendanceActionResult> replaceClockOut(
    BuildContext context, {
    required String source,
    String modeKey = '',
    bool? isHeadquarter,
    DateTime? recordedAt,
    DeveloperOperationTrace? trace,
  }) async {
    final attendance = resolveContext(
      context,
      source: source,
      modeKey: modeKey,
      isHeadquarter: isHeadquarter,
    );
    if (attendance == null || !attendance.isValid) {
      const message = '퇴근 재펀칭에 필요한 사용자 또는 업무 지역 정보가 없습니다.';
      _record(
        'clock_out_replace_invalid_context',
        attendance,
        trace: trace,
        extra: const <String, Object?>{'message': message},
      );
      return const AttendanceActionResult.failure(message: message);
    }

    final now = recordedAt ?? DateTime.now();
    try {
      _record(
        'clock_out_replace_start',
        attendance,
        trace: trace,
        extra: <String, Object?>{'at': now.toIso8601String()},
      );
      await AttBrkRepository.instance.insertEvent(
        dateTime: now,
        type: AttBrkModeType.workOut,
      );
      _record(
        'clock_out_replace_complete',
        attendance,
        trace: trace,
        extra: <String, Object?>{'at': now.toIso8601String()},
      );
      return AttendanceActionResult.success(
        recordedAt: now,
        message: '퇴근 시간이 변경되었습니다.',
      );
    } catch (error, stackTrace) {
      _record(
        'clock_out_replace_failure',
        attendance,
        trace: trace,
        extra: <String, Object?>{
          'error': error,
          'stack': stackTrace,
        },
      );
      return AttendanceActionResult.failure(
        message: '퇴근 시간 변경 중 오류가 발생했습니다: $error',
      );
    }
  }

  static Future<void> resetStaleWorkingState(
    BuildContext context, {
    required String source,
    String modeKey = '',
    bool? isHeadquarter,
    DeveloperOperationTrace? trace,
  }) async {
    final attendance = resolveContext(
      context,
      source: source,
      modeKey: modeKey,
      isHeadquarter: isHeadquarter,
    );
    final userState = context.read<UserState>();
    _record(
      'stale_working_reset_start',
      attendance,
      trace: trace,
      extra: <String, Object?>{'isWorkingBefore': userState.isWorking},
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isWorking', false);
    await EndTimeReminderService.instance.cancel();
    await userState.setWorkingStatus(false);
    _record(
      'stale_working_reset_complete',
      attendance,
      trace: trace,
      extra: <String, Object?>{'isWorkingAfter': userState.isWorking},
    );
  }

  static Future<void> _recordClockInAtToCommuteTrueFalse(
    AttendanceContext attendance,
    DateTime clockInAt, {
    DeveloperOperationTrace? trace,
  }) async {
    final enabled = await CommuteTrueFalseModeConfig.isEnabled();
    if (!enabled) {
      _record(
        'clock_in_commute_true_false_skipped',
        attendance,
        trace: trace,
        extra: const <String, Object?>{'reason': 'disabled'},
      );
      return;
    }
    try {
      await _commuteTrueFalseRepository.setClockInAt(
        company: attendance.division,
        area: attendance.area,
        workerName: attendance.userName,
        clockInAt: clockInAt,
      );
      _record(
        'clock_in_commute_true_false_complete',
        attendance,
        trace: trace,
        extra: <String, Object?>{
          'at': clockInAt.toIso8601String(),
          'firebaseWrite': 1,
        },
      );
    } catch (error, stackTrace) {
      _record(
        'clock_in_commute_true_false_failure',
        attendance,
        trace: trace,
        extra: <String, Object?>{
          'error': error,
          'stack': stackTrace,
        },
      );
    }
  }

  static void _record(
    String event,
    AttendanceContext? attendance, {
    DeveloperOperationTrace? trace,
    Map<String, Object?> extra = const <String, Object?>{},
  }) {
    final meta = <String, Object?>{
      'source': attendance?.source ?? '',
      'context': attendance?.contextKey ?? '',
      'mode': attendance?.modeKey ?? '',
      'isHeadquarter': attendance?.isHeadquarter ?? false,
      'area': attendance?.area ?? '',
      'division': attendance?.division ?? '',
      'userId': attendance?.userId ?? '',
      ...extra,
    };
    AttendanceDiagnostics.record(event, meta: meta);
    trace?.log(
      'attendance $event ${meta.entries.map((entry) => '${entry.key}=${entry.value}').join(' ')}',
    );
  }

  static String _dateKey(DateTime value) {
    final year = value.year.toString().padLeft(4, '0');
    final month = value.month.toString().padLeft(2, '0');
    final day = value.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  static bool _isToday(DateTime value) {
    final now = DateTime.now();
    return value.year == now.year &&
        value.month == now.month &&
        value.day == now.day;
  }
}
