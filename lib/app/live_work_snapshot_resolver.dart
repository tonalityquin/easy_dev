import 'package:shared_preferences/shared_preferences.dart';

import '../features/mode_single/application/att_brk_repository.dart';
import 'init/local_work_schedule_reader.dart';
import 'init/work_schedule_prefs.dart';
import 'live_work_diagnostics.dart';
import 'live_work_snapshot.dart';

class LiveWorkSnapshotResolver {
  LiveWorkSnapshotResolver._();

  static Future<LiveWorkSnapshot> resolve() async {
    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final isWorking = prefs.getBool('isWorking') ?? false;
    final schedule = LocalWorkScheduleReader.readForSessionDate(
      prefs: prefs,
      sessionDate: now,
    );
    final breakEnabledToday = WorkSchedulePrefs.requiresBreakOnDate(
      prefs,
      now,
    );
    final events = await AttBrkRepository.instance.getEventsForDate(now);
    final snapshot = LiveWorkSnapshot(
      now: now,
      isWorking: isWorking,
      scheduledStart: _at(now, schedule.start),
      scheduledEnd: _at(now, schedule.end),
      breakEnabledToday: breakEnabledToday,
      actualClockIn: LiveWorkSnapshot.eventTime(events, AttBrkModeType.workIn),
      actualBreak: LiveWorkSnapshot.eventTime(events, AttBrkModeType.breakTime),
      actualClockOut: LiveWorkSnapshot.eventTime(events, AttBrkModeType.workOut),
    );
    LiveWorkDiagnostics.record('snapshot_resolved', <String, Object?>{
      'working': snapshot.isWorking,
      'scheduledStart': snapshot.scheduledStart?.toIso8601String(),
      'scheduledEnd': snapshot.scheduledEnd?.toIso8601String(),
      'breakEnabled': snapshot.breakEnabledToday,
      'clockIn': snapshot.actualClockIn,
      'break': snapshot.actualBreak,
      'currentSessionBreak': snapshot.currentSessionBreak,
      'staleBreakSuppressed': snapshot.hasStaleBreakForCurrentSession,
      'clockOut': snapshot.actualClockOut,
      'canPunchBreak': snapshot.canPunchBreak,
      'overdue': snapshot.isOverdue,
      'overdueMinutes': snapshot.overdueMinutes,
    });
    return snapshot;
  }

  static DateTime? _at(DateTime date, LocalClockTime? time) {
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }
}
