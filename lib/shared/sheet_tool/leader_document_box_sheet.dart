import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../features/account/applications/user_state.dart';
import '../../features/commute/domain/repositories/commute_log_repository.dart';
import '../../features/dev/application/area_state.dart';
import '../../features/mode_single/application/att_brk_mode_db.dart';

class LocalCommuteRecord {
  final String status;
  final DateTime dateTime;
  final String localTable;
  final String localDate;
  final String localType;

  LocalCommuteRecord({
    required this.status,
    required this.dateTime,
    required this.localTable,
    required this.localDate,
    required this.localType,
  });
}

Future<List<LocalCommuteRecord>> _loadLocalCommuteRecordsFromSqlite({
  required BuildContext context,
  required List<String> statuses,
  required String userId,
}) async {
  final db = await AttBrkModeDb.instance.database;
  final result = <LocalCommuteRecord>[];

  final dateTimeParser = DateFormat('yyyy-MM-dd HH:mm');

  final needWorkIn = statuses.contains('출근');
  final needWorkOut = statuses.contains('퇴근');

  if (needWorkIn || needWorkOut) {
    final workRows = await db.query(
      'simple_work_attendance',
      columns: ['date', 'type', 'time'],
      orderBy: 'date ASC, created_at ASC',
    );

    for (final row in workRows) {
      final typeCode = row['type'] as String;
      final dateStr = row['date'] as String;
      final timeStr = row['time'] as String;

      String? statusLabel;
      if (typeCode == 'work_in' && needWorkIn) {
        statusLabel = '출근';
      } else if (typeCode == 'work_out' && needWorkOut) {
        statusLabel = '퇴근';
      } else {
        continue;
      }

      try {
        final dt = dateTimeParser.parse('$dateStr $timeStr');
        result.add(
          LocalCommuteRecord(
            status: statusLabel,
            dateTime: dt,
            localTable: 'simple_work_attendance',
            localDate: dateStr,
            localType: typeCode,
          ),
        );
      } catch (_) {
        continue;
      }
    }
  }

  final needBreak = statuses.contains('휴게');
  if (needBreak) {
    final breakRows = await db.query(
      'simple_break_attendance',
      columns: ['date', 'type', 'time'],
      orderBy: 'date ASC, created_at ASC',
    );

    for (final row in breakRows) {
      final dateStr = row['date'] as String;
      final typeCode = (row['type'] as String?) ?? 'start';
      final timeStr = row['time'] as String;

      try {
        final dt = dateTimeParser.parse('$dateStr $timeStr');
        result.add(
          LocalCommuteRecord(
            status: '휴게',
            dateTime: dt,
            localTable: 'simple_break_attendance',
            localDate: dateStr,
            localType: typeCode,
          ),
        );
      } catch (_) {
        continue;
      }
    }
  }

  return result;
}

Future<int> _deleteLocalAttendanceRow(LocalCommuteRecord record) async {
  final db = await AttBrkModeDb.instance.database;
  return db.delete(
    record.localTable,
    where: 'date = ? AND type = ?',
    whereArgs: [record.localDate, record.localType],
  );
}

Future<void> submitLeaderCommuteRecordsFromSqlite(BuildContext context) async {
  final userState = context.read<UserState>();
  final areaState = context.read<AreaState>();

  final userId = (userState.session?.id ?? '').trim();
  final userName = userState.name.trim();
  final area = (userState.session?.selectedArea ?? '').trim();
  final division = areaState.currentDivision.trim();

  const debugTag = 'DashboardQuickActions/LeaderCommuteSubmit';
  debugPrint('[$debugTag] start statuses=출근,퇴근');

  if (userId.isEmpty || userName.isEmpty || area.isEmpty || division.isEmpty) {
    debugPrint('[$debugTag] skipped reason=missing_required_context');
    return;
  }

  try {
    final records = await _loadLocalCommuteRecordsFromSqlite(
      context: context,
      statuses: const ['출근', '퇴근'],
      userId: userId,
    );

    if (records.isEmpty) {
      debugPrint('[$debugTag] skipped reason=no_local_records');
      return;
    }

    debugPrint('[$debugTag] localRecordCount=${records.length}');
    final repo = CommuteLogRepository();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('HH:mm');

    for (final record in records) {
      final status = record.status;
      final eventDateTime = record.dateTime;

      final dateStr = dateFormatter.format(eventDateTime);
      final recordedTime = timeFormatter.format(eventDateTime);

      final alreadyExists = await repo.hasLogForDate(
        status: status,
        userId: userId,
        dateStr: dateStr,
      );

      if (alreadyExists) {
        continue;
      }

      await repo.addLog(
        status: status,
        userId: userId,
        userName: userName,
        area: area,
        division: division,
        dateStr: dateStr,
        recordedTime: recordedTime,
        dateTime: eventDateTime,
      );

      final nowExists = await repo.hasLogForDate(
        status: status,
        userId: userId,
        dateStr: dateStr,
      );

      debugPrint('[$debugTag] remoteVerified=$nowExists');
    }
    debugPrint('[$debugTag] complete processed=${records.length}');
  } catch (e, st) {
    debugPrint('❌ [$debugTag] 출퇴근 기록 제출 중 오류: $e');
    debugPrint('stack: $st');
  }
}

Future<void> submitLeaderRestTimeRecordsFromSqlite(BuildContext context) async {
  final userState = context.read<UserState>();
  final areaState = context.read<AreaState>();

  final userId = (userState.session?.id ?? '').trim();
  final userName = userState.name.trim();
  final area = (userState.session?.selectedArea ?? '').trim();
  final division = areaState.currentDivision.trim();

  const debugTag = 'DashboardQuickActions/LeaderBreakSubmit';
  debugPrint('[$debugTag] start statuses=휴게');

  if (userId.isEmpty || userName.isEmpty || area.isEmpty || division.isEmpty) {
    debugPrint('[$debugTag] skipped reason=missing_required_context');
    return;
  }

  try {
    final records = await _loadLocalCommuteRecordsFromSqlite(
      context: context,
      statuses: const ['휴게'],
      userId: userId,
    );

    if (records.isEmpty) {
      debugPrint('[$debugTag] skipped reason=no_local_records');
      return;
    }

    debugPrint('[$debugTag] localRecordCount=${records.length}');
    final repo = CommuteLogRepository();
    final dateFormatter = DateFormat('yyyy-MM-dd');
    final timeFormatter = DateFormat('HH:mm');

    for (final record in records) {
      final eventDateTime = record.dateTime;
      final dateStr = dateFormatter.format(eventDateTime);
      final recordedTime = timeFormatter.format(eventDateTime);

      final alreadyExists = await repo.hasLogForDate(
        status: '휴게',
        userId: userId,
        dateStr: dateStr,
      );

      if (alreadyExists) {
        await _deleteLocalAttendanceRow(record);
        continue;
      }

      await repo.addLog(
        status: '휴게',
        userId: userId,
        userName: userName,
        area: area,
        division: division,
        dateStr: dateStr,
        recordedTime: recordedTime,
        dateTime: eventDateTime,
      );

      final nowExists = await repo.hasLogForDate(
        status: '휴게',
        userId: userId,
        dateStr: dateStr,
      );

      if (nowExists) {
        await _deleteLocalAttendanceRow(record);
      }
    }
    debugPrint('[$debugTag] complete processed=${records.length}');
  } catch (e, st) {
    debugPrint('❌ [$debugTag] 휴게시간 기록 제출 중 오류: $e');
    debugPrint('stack: $st');
  }
}
