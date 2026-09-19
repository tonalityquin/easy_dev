import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/init/work_schedule_prefs.dart';
import '../../../app/live_work_diagnostics.dart';
import '../../mode_single/application/att_brk_repository.dart';

class BreakPunchResult {
  const BreakPunchResult._({
    required this.success,
    required this.alreadyRecorded,
    required this.message,
    this.recordedAt,
  });

  const BreakPunchResult.success(DateTime recordedAt)
      : this._(
          success: true,
          alreadyRecorded: false,
          message: '휴게 기록이 완료되었습니다.',
          recordedAt: recordedAt,
        );

  const BreakPunchResult.alreadyRecorded(String message)
      : this._(
          success: false,
          alreadyRecorded: true,
          message: message,
        );

  const BreakPunchResult.failure(String message)
      : this._(
          success: false,
          alreadyRecorded: false,
          message: message,
        );

  final bool success;
  final bool alreadyRecorded;
  final String message;
  final DateTime? recordedAt;
}

class BreakPunchUseCase {
  BreakPunchUseCase._();

  static Future<BreakPunchResult> execute({DateTime? recordedAt}) async {
    final now = recordedAt ?? DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final isWorking = prefs.getBool('isWorking') ?? false;
    final requiresBreak = WorkSchedulePrefs.requiresBreakOnDate(
      prefs,
      now,
    );
    final events = await AttBrkRepository.instance.getEventsForDate(now);
    final hasWorkIn = events.containsKey(AttBrkModeType.workIn);
    final hasWorkOut = events.containsKey(AttBrkModeType.workOut);
    final hasBreak = events.containsKey(AttBrkModeType.breakTime);
    LiveWorkDiagnostics.record('break_validation', <String, Object?>{
      'isWorking': isWorking,
      'requiresBreak': requiresBreak,
      'hasWorkIn': hasWorkIn,
      'hasWorkOut': hasWorkOut,
      'hasBreak': hasBreak,
    });
    if (!isWorking) {
      return const BreakPunchResult.failure('현재 근무 중이 아닙니다.');
    }
    if (!requiresBreak) {
      return const BreakPunchResult.failure('선택한 날짜에는 휴게가 활성화되어 있지 않습니다.');
    }
    if (!hasWorkIn) {
      return const BreakPunchResult.failure('출근 기록 후 휴게를 기록할 수 있습니다.');
    }
    if (hasWorkOut) {
      return const BreakPunchResult.failure('퇴근이 완료된 뒤에는 휴게를 기록할 수 없습니다.');
    }
    if (hasBreak) {
      return const BreakPunchResult.alreadyRecorded('오늘 휴게 기록이 이미 있습니다.');
    }
    final inserted = await AttBrkRepository.instance.insertBreakOnce(dateTime: now);
    final persistedEvents = await AttBrkRepository.instance.getEventsForDate(now);
    final persistedBreak = persistedEvents[AttBrkModeType.breakTime];
    if (persistedBreak == null || persistedBreak.trim().isEmpty) {
      LiveWorkDiagnostics.record('break_persist_failed', <String, Object?>{
        'inserted': inserted,
        'at': now.toIso8601String(),
      });
      return const BreakPunchResult.failure('휴게 기록 저장을 확인하지 못했습니다.');
    }
    if (!inserted) {
      LiveWorkDiagnostics.record('break_already_recorded', <String, Object?>{
        'persistedBreak': persistedBreak,
      });
      return const BreakPunchResult.alreadyRecorded('오늘 휴게 기록이 이미 있습니다.');
    }
    await prefs.setString('last_break_date', _dateKey(now));
    LiveWorkDiagnostics.record('break_recorded', <String, Object?>{
      'at': now.toIso8601String(),
      'persistedBreak': persistedBreak,
    });
    return BreakPunchResult.success(now);
  }

  static String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}
