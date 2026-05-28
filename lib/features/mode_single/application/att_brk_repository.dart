import 'package:intl/intl.dart';
import 'package:sqflite/sqflite.dart';

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
        'simple_work_attendance',
        <String, Object?>{
          'date': date,
          'type': type.code,
          'time': time,
          'created_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    } else if (type.isBreak) {
      await db.insert(
        'simple_break_attendance',
        <String, Object?>{
          'date': date,
          'type': _breakTypeStart,
          'time': time,
          'created_at': createdAt,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  Future<void> clearEventsForDate(DateTime dateTime) async {
    final db = await _database;
    final date = _dateFormatter.format(dateTime);

    await db.delete(
      'simple_work_attendance',
      where: 'date = ?',
      whereArgs: <Object?>[date],
    );

    await db.delete(
      'simple_break_attendance',
      where: 'date = ?',
      whereArgs: <Object?>[date],
    );
  }

  Future<Map<AttBrkModeType, String>> getEventsForDate(
      DateTime dateTime) async {
    final db = await _database;
    final date = _dateFormatter.format(dateTime);

    final result = <AttBrkModeType, String>{};

    final workRows = await db.query(
      'simple_work_attendance',
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
      'simple_break_attendance',
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
