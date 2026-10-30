import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

import '../../../features/attendance/domain/attendance_context.dart';
import '../../../features/attendance/domain/attendance_session.dart';
import '../../../features/commute/domain/repositories/commute_log_repository.dart';
import 'att_brk_mode_db.dart';
enum AttBrkModeType {
  workIn,
  workOut,
  breakTime,
}

extension AttBrkTypeX on AttBrkModeType {
  String get code {
    switch (this) {
      case AttBrkModeType.workIn:
        return 'work_in';
      case AttBrkModeType.workOut:
        return 'work_out';
      case AttBrkModeType.breakTime:
        return 'break';
    }
  }

  String get statusLabel {
    switch (this) {
      case AttBrkModeType.workIn:
        return '출근';
      case AttBrkModeType.workOut:
        return '퇴근';
      case AttBrkModeType.breakTime:
        return '휴게';
    }
  }

  bool get isWork {
    switch (this) {
      case AttBrkModeType.workIn:
      case AttBrkModeType.workOut:
        return true;
      case AttBrkModeType.breakTime:
        return false;
    }
  }

  bool get isBreak => this == AttBrkModeType.breakTime;
}

AttBrkModeType? singleModeAttBrkTypeFromCode(String code) {
  switch (code) {
    case 'work_in':
      return AttBrkModeType.workIn;
    case 'work_out':
      return AttBrkModeType.workOut;
    case 'break':
      return AttBrkModeType.breakTime;
  }
  return null;
}

class ClockInRestorePoint {
  const ClockInRestorePoint({
    required this.date,
    required this.previousWorkRow,
    required this.previousSessionRow,
  });

  final String date;
  final Map<String, Object?>? previousWorkRow;
  final Map<String, Object?>? previousSessionRow;
}

class AttBrkRepository {
  AttBrkRepository._({
    CommuteLogRepository? commuteLogRepository,
  }) : _commuteLogRepository = commuteLogRepository ?? CommuteLogRepository();

  static final AttBrkRepository instance = AttBrkRepository._();

  final CommuteLogRepository _commuteLogRepository;

  final DateFormat _dateFormatter = DateFormat('yyyy-MM-dd');

  final DateFormat _timeFormatter = DateFormat('HH:mm');

  static const String _breakTypeStart = 'start';

  Future<Database> get _database async => AttBrkModeDb.instance.database;

  Future<ClockInRestorePoint> captureClockInRestorePoint(DateTime dateTime) async {
    final db = await _database;
    final date = _dateFormatter.format(dateTime);
    final workRows = await db.query(
      AttBrkModeDb.workAttendanceTable,
      where: 'date = ? AND type = ?',
      whereArgs: <Object?>[date, AttBrkModeType.workIn.code],
      limit: 1,
    );
    final sessionRows = await db.query(
      AttBrkModeDb.attendanceSessionTable,
      where: 'date = ?',
      whereArgs: <Object?>[date],
      limit: 1,
    );
    return ClockInRestorePoint(
      date: date,
      previousWorkRow: workRows.isEmpty
          ? null
          : Map<String, Object?>.from(workRows.first),
      previousSessionRow: sessionRows.isEmpty
          ? null
          : Map<String, Object?>.from(sessionRows.first),
    );
  }

  Future<void> restoreClockInAttempt({
    required ClockInRestorePoint restorePoint,
    required DateTime attemptedAt,
  }) async {
    final db = await _database;
    await db.transaction((txn) async {
      final current = await txn.query(
        AttBrkModeDb.workAttendanceTable,
        where: 'date = ? AND type = ?',
        whereArgs: <Object?>[restorePoint.date, AttBrkModeType.workIn.code],
        limit: 1,
      );
      if (current.isEmpty ||
          current.first['created_at'] != attemptedAt.toIso8601String()) {
        throw StateError('CLOCK_IN_RESTORE_CONCURRENT_UPDATE');
      }
      await txn.delete(
        AttBrkModeDb.workAttendanceTable,
        where: 'date = ? AND type = ?',
        whereArgs: <Object?>[restorePoint.date, AttBrkModeType.workIn.code],
      );
      if (restorePoint.previousWorkRow != null) {
        await txn.insert(
          AttBrkModeDb.workAttendanceTable,
          restorePoint.previousWorkRow!,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await txn.delete(
        AttBrkModeDb.attendanceSessionTable,
        where: 'date = ?',
        whereArgs: <Object?>[restorePoint.date],
      );
      if (restorePoint.previousSessionRow != null) {
        await txn.insert(
          AttBrkModeDb.attendanceSessionTable,
          restorePoint.previousSessionRow!,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    debugPrint('[ATTENDANCE_SESSION] clock_in_restore_complete date=${restorePoint.date}');
  }

  Future<AttendanceSession> insertClockInWithSession({
    required DateTime dateTime,
    required AttendanceContext attendance,
  }) async {
    final db = await _database;
    final date = _dateFormatter.format(dateTime);
    final time = _timeFormatter.format(dateTime);
    final createdAt = dateTime.toIso8601String();
    final now = DateTime.now();
    final session = AttendanceSession(
      date: date,
      userId: attendance.userId.trim(),
      userName: attendance.userName.trim(),
      area: attendance.area.trim(),
      division: attendance.division.trim(),
      contextKey: attendance.contextKey.trim(),
      modeKey: attendance.isHeadquarter ? '' : attendance.modeKey.trim(),
      isHeadquarter: attendance.isHeadquarter,
      clockInAt: dateTime,
      createdAt: now,
      updatedAt: now,
    );
    if (!session.isValid) {
      throw StateError('유효하지 않은 근무 세션입니다.');
    }

    await db.transaction((txn) async {
      await txn.insert(
        AttBrkModeDb.workAttendanceTable,
        <String, Object?>{
          'date': date,
          'type': AttBrkModeType.workIn.code,
          'time': time,
          'created_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert(
        AttBrkModeDb.attendanceSessionTable,
        session.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });

    debugPrint(
      '[ATTENDANCE_SESSION] saved date=$date context=${session.contextKey} mode=${session.modeKey} headquarter=${session.isHeadquarter} area=${session.area} division=${session.division}',
    );
    return session;
  }

  Future<AttendanceSession?> getAttendanceSessionForDate(
    DateTime dateTime,
  ) async {
    final db = await _database;
    final date = _dateFormatter.format(dateTime);
    final rows = await db.query(
      AttBrkModeDb.attendanceSessionTable,
      where: 'date = ?',
      whereArgs: <Object?>[date],
      limit: 1,
    );
    if (rows.isEmpty) {
      debugPrint('[ATTENDANCE_SESSION] missing date=$date');
      return null;
    }
    final session = AttendanceSession.fromMap(
      Map<String, Object?>.from(rows.first),
    );
    if (session == null) {
      debugPrint('[ATTENDANCE_SESSION] invalid date=$date');
      return null;
    }
    debugPrint(
      '[ATTENDANCE_SESSION] loaded date=$date context=${session.contextKey} mode=${session.modeKey} headquarter=${session.isHeadquarter}',
    );
    return session;
  }

  Future<void> insertEvent({
    required DateTime dateTime,
    required AttBrkModeType type,
  }) async {
    final db = await _database;

    final date = _dateFormatter.format(dateTime);
    final time = _timeFormatter.format(dateTime);
    final createdAt = dateTime.toIso8601String();

    if (type.isWork) {
      await db.insert(
        AttBrkModeDb.workAttendanceTable,
        <String, Object?>{
          'date': date,
          'type': type.code,
          'time': time,
          'created_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else if (type.isBreak) {
      await insertBreakOnce(dateTime: dateTime);
    }
  }

  Future<bool> insertBreakOnce({required DateTime dateTime}) async {
    final db = await _database;
    final date = _dateFormatter.format(dateTime);
    final time = _timeFormatter.format(dateTime);
    final createdAt = dateTime.toIso8601String();
    final rowId = await db.rawInsert(
      'INSERT OR IGNORE INTO ${AttBrkModeDb.breakAttendanceTable} (date, type, time, created_at) VALUES (?, ?, ?, ?)',
      <Object?>[date, _breakTypeStart, time, createdAt],
    );
    return rowId > 0;
  }


  Future<void> upsertReviewEvent({
    required DateTime date,
    required AttBrkModeType type,
    required String time,
  }) async {
    final normalizedTime = time.trim();
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(normalizedTime);
    if (match == null) {
      throw FormatException('유효하지 않은 시간 형식입니다.');
    }
    final hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    if (hour > 23 || minute > 59) {
      throw FormatException('유효하지 않은 시간입니다.');
    }
    final db = await _database;
    final day = _dateFormatter.format(date);
    final eventAt = DateTime(date.year, date.month, date.day, hour, minute);
    final values = <String, Object?>{
      'date': day,
      'type': type.isBreak ? _breakTypeStart : type.code,
      'time': normalizedTime,
      'created_at': eventAt.toIso8601String(),
    };
    await db.insert(
      type.isBreak
          ? AttBrkModeDb.breakAttendanceTable
          : AttBrkModeDb.workAttendanceTable,
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint(
      '[ATTENDANCE_REVIEW] local_upsert date=$day type=${type.code} time=$normalizedTime',
    );
  }

  Future<int> deleteReviewEvent({
    required DateTime date,
    required AttBrkModeType type,
  }) async {
    final db = await _database;
    final day = _dateFormatter.format(date);
    final table = type.isBreak
        ? AttBrkModeDb.breakAttendanceTable
        : AttBrkModeDb.workAttendanceTable;
    final localType = type.isBreak ? _breakTypeStart : type.code;
    final deleted = await db.delete(
      table,
      where: 'date = ? AND type = ?',
      whereArgs: <Object?>[day, localType],
    );
    debugPrint(
      '[ATTENDANCE_REVIEW] local_delete date=$day type=${type.code} deleted=$deleted',
    );
    return deleted;
  }

  Future<int> deleteReviewCommuteDate(DateTime date) async {
    final db = await _database;
    final day = _dateFormatter.format(date);
    final deleted = await db.delete(
      AttBrkModeDb.workAttendanceTable,
      where: 'date = ? AND type IN (?, ?)',
      whereArgs: <Object?>[
        day,
        AttBrkModeType.workIn.code,
        AttBrkModeType.workOut.code,
      ],
    );
    debugPrint(
      '[ATTENDANCE_REVIEW] local_delete_commute_date date=$day deleted=$deleted',
    );
    return deleted;
  }

  Future<void> clearEventsForDate(DateTime dateTime) async {
    final db = await _database;
    final date = _dateFormatter.format(dateTime);

    await db.delete(
      AttBrkModeDb.workAttendanceTable,
      where: 'date = ?',
      whereArgs: <Object?>[date],
    );

    await db.delete(
      AttBrkModeDb.breakAttendanceTable,
      where: 'date = ?',
      whereArgs: <Object?>[date],
    );

    await db.delete(
      AttBrkModeDb.attendanceSessionTable,
      where: 'date = ?',
      whereArgs: <Object?>[date],
    );
    debugPrint('[ATTENDANCE_SESSION] cleared date=$date');
  }

  Future<Map<AttBrkModeType, String>> getEventsForDate(
      DateTime dateTime) async {
    final db = await _database;
    final date = _dateFormatter.format(dateTime);

    final result = <AttBrkModeType, String>{};

    final workRows = await db.query(
      AttBrkModeDb.workAttendanceTable,
      columns: ['type', 'time'],
      where: 'date = ?',
      whereArgs: <Object?>[date],
    );

    for (final row in workRows) {
      final typeCode = row['type'] as String;
      final time = row['time'] as String;

      final maybeType = singleModeAttBrkTypeFromCode(typeCode);
      if (maybeType == null) continue;

      if (maybeType == AttBrkModeType.workIn ||
          maybeType == AttBrkModeType.workOut) {
        result[maybeType] = time;
      }
    }

    final breakRows = await db.query(
      AttBrkModeDb.breakAttendanceTable,
      columns: ['time'],
      where: 'date = ? AND type = ?',
      whereArgs: <Object?>[date, _breakTypeStart],
    );

    if (breakRows.isNotEmpty) {
      final time = breakRows.first['time'] as String;
      result[AttBrkModeType.breakTime] = time;
    }

    return result;
  }

  Future<void> insertEventAndUpload({
    required DateTime dateTime,
    required AttBrkModeType type,
    required String userId,
    required String userName,
    required String area,
    required String division,
  }) async {
    await insertEvent(dateTime: dateTime, type: type);

    final dateStr = _dateFormatter.format(dateTime);
    final recordedTime = _timeFormatter.format(dateTime);
    final statusLabel = type.statusLabel;

    final alreadyExists = await _commuteLogRepository.hasLogForDate(
      status: statusLabel,
      userId: userId,
      dateStr: dateStr,
    );

    if (alreadyExists) return;

    await _commuteLogRepository.addLog(
      status: statusLabel,
      userId: userId,
      userName: userName,
      area: area,
      division: division,
      dateStr: dateStr,
      recordedTime: recordedTime,
      dateTime: dateTime,
    );
  }

  Future<void> syncDateToRemote({
    required DateTime date,
    required String userId,
    required String userName,
    required String area,
    required String division,
  }) async {
    final localEvents = await getEventsForDate(date);
    if (localEvents.isEmpty) return;

    final dateStr = _dateFormatter.format(date);

    for (final entry in localEvents.entries) {
      final type = entry.key;
      final timeStr = entry.value;
      final statusLabel = type.statusLabel;

      final alreadyExists = await _commuteLogRepository.hasLogForDate(
        status: statusLabel,
        userId: userId,
        dateStr: dateStr,
      );
      if (alreadyExists) continue;

      final parts = timeStr.split(':');
      final hour = int.tryParse(parts.elementAt(0)) ?? 0;
      final minute = int.tryParse(parts.elementAt(1)) ?? 0;

      final dateTime = DateTime(
        date.year,
        date.month,
        date.day,
        hour,
        minute,
      );

      await _commuteLogRepository.addLog(
        status: statusLabel,
        userId: userId,
        userName: userName,
        area: area,
        division: division,
        dateStr: dateStr,
        recordedTime: timeStr,
        dateTime: dateTime,
      );
    }
  }
}
