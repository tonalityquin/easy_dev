import 'package:sqflite/sqflite.dart';

import 'att_brk_mode_db.dart';

class SingleRuleTodoPromptHistory {
  const SingleRuleTodoPromptHistory({
    required this.userId,
    required this.division,
    required this.area,
    required this.todoFingerprint,
    required this.clockInsSincePrompt,
    required this.promptCount,
    this.lastPromptedAt,
  });

  final String userId;
  final String division;
  final String area;
  final String todoFingerprint;
  final int clockInsSincePrompt;
  final int promptCount;
  final DateTime? lastPromptedAt;
}

class SingleRuleTodoPromptRepository {
  const SingleRuleTodoPromptRepository();

  Future<Database> get _database async => AttBrkModeDb.instance.database;

  Future<SingleRuleTodoPromptHistory?> read({
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
      AttBrkModeDb.ruleTodoPromptHistoryTable,
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
    return SingleRuleTodoPromptHistory(
      userId: normalizedUserId,
      division: normalizedDivision,
      area: normalizedArea,
      todoFingerprint: (row['todo_fingerprint'] ?? '').toString(),
      clockInsSincePrompt:
          (row['clock_ins_since_prompt'] as num?)?.toInt() ?? 0,
      promptCount: (row['prompt_count'] as num?)?.toInt() ?? 0,
      lastPromptedAt: _readDateTime(row['last_prompted_at']),
    );
  }

  Future<void> markPrompted({
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
      AttBrkModeDb.ruleTodoPromptHistoryTable,
      <String, Object?>{
        'user_id': normalizedUserId,
        'division': normalizedDivision,
        'area': normalizedArea,
        'todo_fingerprint': normalizedFingerprint,
        'last_prompted_at': now,
        'clock_ins_since_prompt': 0,
        'prompt_count': (existing?.promptCount ?? 0) + 1,
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
      AttBrkModeDb.ruleTodoPromptHistoryTable,
      <String, Object?>{
        'user_id': normalizedUserId,
        'division': normalizedDivision,
        'area': normalizedArea,
        'todo_fingerprint': normalizedFingerprint,
        'last_prompted_at': existing?.lastPromptedAt?.toIso8601String(),
        'clock_ins_since_prompt':
            (existing?.clockInsSincePrompt ?? 0) + 1,
        'prompt_count': existing?.promptCount ?? 0,
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
