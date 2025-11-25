// lib/time_record/time_record_db.dart
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 근무 기록 전용 SQLite DB 래퍼
class TimeRecordDb {
  TimeRecordDb._internal();

  static final TimeRecordDb instance = TimeRecordDb._internal();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, 'work_time_record.db');

    debugPrint('[TimeRecordDb] open at $path');

    return openDatabase(
      path,
      // ⬅️ 현재 스키마 버전
      version: 2,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
      // ⬅️ 매번 열릴 때마다 스키마 점검(테이블이 날아간 경우 재생성)
      onOpen: _onOpen,
    );
  }

  // ─────────────────────────────────────────────────────────
  // onCreate / onUpgrade / onOpen
  // ─────────────────────────────────────────────────────────

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('[TimeRecordDb] onCreate v$version');
    // v2 스키마 기준으로 테이블/인덱스 생성
    await _createWorkDailySummaryTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('[TimeRecordDb] onUpgrade $oldVersion -> $newVersion');

    // v1 → v2 마이그레이션:
    // 기존 work_daily_summary 에 fg_h/m/s, bg_h/m/s 컬럼 추가 후
    // fg_secs/bg_secs 기준으로 값을 채운다.
    if (oldVersion < 2) {
      debugPrint('[TimeRecordDb] migrate v1 -> v2 (add h/m/s columns)');

      // 혹시라도 테이블 자체가 없을 수도 있으므로 먼저 보장
      await _ensureWorkDailySummaryTable(db);

      // 컬럼 존재 여부 체크 없이 단순 ADD 는 에러가 날 수 있어서,
      // 이미 존재하면 무시하는 방식을 쓰려면 pragma 를 검사해야 함.
      // 여기서는 "정상적인 v1 → v2" 만 상정하고, 컬럼이 없다고 가정.
      await db.execute(
          'ALTER TABLE work_daily_summary ADD COLUMN fg_h INTEGER NOT NULL DEFAULT 0;');
      await db.execute(
          'ALTER TABLE work_daily_summary ADD COLUMN fg_m INTEGER NOT NULL DEFAULT 0;');
      await db.execute(
          'ALTER TABLE work_daily_summary ADD COLUMN fg_s INTEGER NOT NULL DEFAULT 0;');
      await db.execute(
          'ALTER TABLE work_daily_summary ADD COLUMN bg_h INTEGER NOT NULL DEFAULT 0;');
      await db.execute(
          'ALTER TABLE work_daily_summary ADD COLUMN bg_m INTEGER NOT NULL DEFAULT 0;');
      await db.execute(
          'ALTER TABLE work_daily_summary ADD COLUMN bg_s INTEGER NOT NULL DEFAULT 0;');

      // 기존 row 들에 대해 fg_secs/bg_secs 기준으로 h/m/s 채우기
      final rows = await db.query('work_daily_summary');
      for (final row in rows) {
        final int id = row['id'] as int;
        final int fgSecs = (row['fg_secs'] as int?) ?? 0;
        final int bgSecs = (row['bg_secs'] as int?) ?? 0;

        final fg = _splitSecondsToHms(fgSecs);
        final bg = _splitSecondsToHms(bgSecs);

        await db.update(
          'work_daily_summary',
          {
            'fg_h': fg[0],
            'fg_m': fg[1],
            'fg_s': fg[2],
            'bg_h': bg[0],
            'bg_m': bg[1],
            'bg_s': bg[2],
          },
          where: 'id = ?',
          whereArgs: [id],
        );
      }
    }
  }

  /// DB 가 열릴 때마다 호출됨.
  /// - 테이블을 누가 DROP 했더라도 다시 생성되도록 보강.
  Future<void> _onOpen(Database db) async {
    debugPrint('[TimeRecordDb] onOpen → ensure table');
    await _ensureWorkDailySummaryTable(db);
  }

  // ─────────────────────────────────────────────────────────
  // 테이블/인덱스 생성 & 존재 보장
  // ─────────────────────────────────────────────────────────

  /// 스키마 v2 기준 테이블/인덱스 생성
  Future<void> _createWorkDailySummaryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS work_daily_summary (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL UNIQUE,

        -- 누적 초(계산용 기준)
        fg_secs INTEGER NOT NULL DEFAULT 0,
        bg_secs INTEGER NOT NULL DEFAULT 0,

        -- 시/분/초 분해 저장(사람이 보기 좋은 용도)
        fg_h INTEGER NOT NULL DEFAULT 0,
        fg_m INTEGER NOT NULL DEFAULT 0,
        fg_s INTEGER NOT NULL DEFAULT 0,
        bg_h INTEGER NOT NULL DEFAULT 0,
        bg_m INTEGER NOT NULL DEFAULT 0,
        bg_s INTEGER NOT NULL DEFAULT 0,

        created_at TEXT NOT NULL,
        updated_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_work_daily_summary_date 
      ON work_daily_summary(date);
    ''');
  }

  /// work_daily_summary 테이블이 없으면 다시 만들어주는 안전 장치
  Future<void> _ensureWorkDailySummaryTable(Database db) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='work_daily_summary'",
    );
    if (rows.isEmpty) {
      debugPrint(
        '[TimeRecordDb] work_daily_summary not found → creating again',
      );
      await _createWorkDailySummaryTable(db);
    }
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
    }
  }
}

/// 초 → [시, 분, 초] 로 나누기
List<int> _splitSecondsToHms(int totalSeconds) {
  if (totalSeconds <= 0) return [0, 0, 0];
  final h = totalSeconds ~/ 3600;
  final m = (totalSeconds % 3600) ~/ 60;
  final s = totalSeconds % 60;
  return [h, m, s];
}
