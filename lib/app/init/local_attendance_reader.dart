import 'package:sqflite/sqflite.dart';

import '../../features/mode_single/application/att_brk_mode_db.dart';

class LocalAttendanceDayState {
  final String? workInTime;
  final String? workOutTime;

  const LocalAttendanceDayState({
    required this.workInTime,
    required this.workOutTime,
  });

  bool get hasWorkIn => workInTime != null && workInTime!.isNotEmpty;
  bool get hasWorkOut => workOutTime != null && workOutTime!.isNotEmpty;
}

class LocalAttendanceReader {
  LocalAttendanceReader._();

  static final LocalAttendanceReader instance = LocalAttendanceReader._();

  Future<Database> get _database async => AttBrkModeDb.instance.database;

  Future<LocalAttendanceDayState> readDay(DateTime dateTime) async {
    final db = await _database;
    final date = _formatDate(dateTime);
    final rows = await db.query(
      'simple_work_attendance',
      columns: <String>['type', 'time'],
      where: 'date = ?',
      whereArgs: <Object?>[date],
    );

    String? workInTime;
    String? workOutTime;

    for (final row in rows) {
      final type = row['type'] as String?;
      final time = row['time'] as String?;
      if (type == 'work_in') {
        workInTime = time;
      } else if (type == 'work_out') {
        workOutTime = time;
      }
    }

    return LocalAttendanceDayState(
      workInTime: workInTime,
      workOutTime: workOutTime,
    );
  }

  Future<DateTime?> findOpenWorkSessionDate() async {
    final db = await _database;
    final latestWorkIn = await _readLatestEvent(
      db: db,
      type: 'work_in',
    );
    if (latestWorkIn == null) return null;

    final latestWorkOut = await _readLatestEvent(
      db: db,
      type: 'work_out',
    );

    if (latestWorkOut != null && !latestWorkIn.isAfter(latestWorkOut)) {
      return null;
    }

    return DateTime(
      latestWorkIn.year,
      latestWorkIn.month,
      latestWorkIn.day,
    );
  }

  Future<DateTime?> _readLatestEvent({
    required Database db,
    required String type,
  }) async {
    final rows = await db.query(
      'simple_work_attendance',
      columns: <String>['date', 'time', 'created_at'],
      where: 'type = ?',
      whereArgs: <Object?>[type],
      orderBy: 'date DESC, time DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    final createdAt = row['created_at'] as String?;
    final parsedCreatedAt =
        createdAt == null ? null : DateTime.tryParse(createdAt);
    if (parsedCreatedAt != null) return parsedCreatedAt;

    final date = row['date'] as String?;
    final time = row['time'] as String?;
    if (date == null || time == null) return null;

    return DateTime.tryParse('${date}T$time:00');
  }

  String _formatDate(DateTime dateTime) {
    final year = dateTime.year.toString().padLeft(4, '0');
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }
}
