import 'package:sqflite/sqflite.dart';

import 'att_brk_mode_db.dart';

class SingleRuleTodoReminderHistory {
  const SingleRuleTodoReminderHistory({
    required this.userId,
    required this.division,
    required this.area,
    required this.todoFingerprint,
    required this.clockInsSinceReminder,
    required this.reminderCount,
    this.lastRemindedAt,
  });

  final String userId;
  final String division;
  final String area;
  final String todoFingerprint;
  final int clockInsSinceReminder;
  final int reminderCount;
  final DateTime? lastRemindedAt;
}

class SingleRuleTodoReminderRepository {
  const SingleRuleTodoReminderRepository();

  Future<Database> get _database async => AttBrkModeDb.instance.database;

  Future<SingleRuleTodoReminderHistory?> read({
    required String userId,
    required String division,
    required String area,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    if (normalizedUserId.isEmpty ||
        normalizedDivision.isEmpty ||
        normalizedArea.isEmpty) {
      return null;
    }

    final db = await _database;
    final rows = await db.query(
      AttBrkModeDb.ruleTodoReminderHistoryTable,
      where: 'user_id = ? AND division = ? AND area = ?',
      whereArgs: <Object?>[
        normalizedUserId,
        normalizedDivision,
        normalizedArea,
      ],
      limit: 1,
    );
    if (rows.isEmpty) return null;

    final row = rows.first;
    return SingleRuleTodoReminderHistory(
      userId: normalizedUserId,
      division: normalizedDivision,
      area: normalizedArea,
      todoFingerprint: (row['todo_fingerprint'] ?? '').toString(),
      clockInsSinceReminder:
          (row['clock_ins_since_reminder'] as num?)?.toInt() ?? 0,
      reminderCount: (row['reminder_count'] as num?)?.toInt() ?? 0,
      lastRemindedAt: _readDateTime(row['last_reminded_at']),
    );
  }

  Future<void> markReminderConfirmed({
    required String userId,
    required String division,
    required String area,
    required String todoFingerprint,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    final normalizedFingerprint = todoFingerprint.trim();
    if (normalizedUserId.isEmpty ||
        normalizedDivision.isEmpty ||
        normalizedArea.isEmpty ||
        normalizedFingerprint.isEmpty) {
      return;
    }

    final existing = await read(
      userId: normalizedUserId,
      division: normalizedDivision,
      area: normalizedArea,
    );
    final now = DateTime.now().toIso8601String();
    final db = await _database;
    await db.insert(
      AttBrkModeDb.ruleTodoReminderHistoryTable,
      <String, Object?>{
        'user_id': normalizedUserId,
        'division': normalizedDivision,
        'area': normalizedArea,
        'todo_fingerprint': normalizedFingerprint,
        'last_reminded_at': now,
        'clock_ins_since_reminder': 0,
        'reminder_count': (existing?.reminderCount ?? 0) + 1,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> markEligibleClockInSucceeded({
    required String userId,
    required String division,
    required String area,
    required String todoFingerprint,
  }) async {
    final normalizedUserId = userId.trim();
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    final normalizedFingerprint = todoFingerprint.trim();
    if (normalizedUserId.isEmpty ||
        normalizedDivision.isEmpty ||
        normalizedArea.isEmpty ||
        normalizedFingerprint.isEmpty) {
      return;
    }

    final existing = await read(
      userId: normalizedUserId,
      division: normalizedDivision,
      area: normalizedArea,
    );
    final now = DateTime.now().toIso8601String();
    final db = await _database;
    await db.insert(
      AttBrkModeDb.ruleTodoReminderHistoryTable,
      <String, Object?>{
        'user_id': normalizedUserId,
        'division': normalizedDivision,
        'area': normalizedArea,
        'todo_fingerprint': normalizedFingerprint,
        'last_reminded_at': existing?.lastRemindedAt?.toIso8601String(),
        'clock_ins_since_reminder':
            (existing?.clockInsSinceReminder ?? 0) + 1,
        'reminder_count': existing?.reminderCount ?? 0,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  DateTime? _readDateTime(Object? value) {
    final raw = value?.toString().trim() ?? '';
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw);
  }
}
