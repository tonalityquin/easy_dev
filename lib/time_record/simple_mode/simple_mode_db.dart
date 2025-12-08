// lib/time_record/simple_mode/simple_mode_db.dart
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class SimpleModeDb {
  SimpleModeDb._();
  static final SimpleModeDb instance = SimpleModeDb._();

  static const _dbName = 'simple_mode_attendance.db';
  static const _dbVersion = 1;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;

    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, _dbName);

    _db = await openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onOpen: _onOpen,
    );

    debugPrint('[SimpleModeDb] open at $fullPath');
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('[SimpleModeDb] onCreate v$version');
    await _createSimpleModeAttendanceTable(db);
  }

  Future<void> _onOpen(Database db) async {
    debugPrint('[SimpleModeDb] onOpen → ensure table');
    await _createSimpleModeAttendanceTable(db);
  }

  /// 약식 모드 출근/퇴근/휴게 시간 로그 테이블 생성
  Future<void> _createSimpleModeAttendanceTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS simple_mode_attendance (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        time TEXT NOT NULL,
        created_at TEXT NOT NULL
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_simple_mode_attendance_date
      ON simple_mode_attendance(date);
    ''');
  }
}
