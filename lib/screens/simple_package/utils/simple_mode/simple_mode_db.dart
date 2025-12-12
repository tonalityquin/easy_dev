// lib/time_record/simple_mode/simple_mode_db.dart
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class SimpleModeDb {
  SimpleModeDb._();

  static final SimpleModeDb instance = SimpleModeDb._();

  static const _dbName = 'simple_mode_attendance.db';

  // ✅ v4: simple_break_attendance 에 type 컬럼 추가 (항상 "start" 저장)
  static const _dbVersion = 4;

  Database? _db;

  Future<Database> get database async {
    // 이미 열려 있고 유효하면 그대로 사용
    if (_db != null && _db!.isOpen) {
      return _db!;
    }

    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, _dbName);

    _db = await openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onOpen: _onOpen,
      onUpgrade: _onUpgrade, // ✅ 마이그레이션 훅
    );

    debugPrint('[SimpleModeDb] open at $fullPath');
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('[SimpleModeDb] onCreate v$version');
    // 신규 생성 시에는 분리된 두 테이블만 생성 (v4 스키마 기준)
    await _createWorkAttendanceTable(db);
    await _createBreakAttendanceTable(db);
  }

  Future<void> _onOpen(Database db) async {
    debugPrint('[SimpleModeDb] onOpen → ensure tables');
    // 앱 실행 시마다 분리된 두 테이블이 존재하는지 보장 (v4 스키마 기준)
    await _createWorkAttendanceTable(db);
    await _createBreakAttendanceTable(db);
  }

  /// 버전 업그레이드 마이그레이션
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('[SimpleModeDb] onUpgrade $oldVersion → $newVersion');

    // v1 → v2: 기존 simple_mode_attendance(id 포함) → (date, type) PK 스키마로 변경
    if (oldVersion < 2) {
      await _migrateV2_removeIdAndUseCompositePk(db);
    }

    // v2 → v3: 단일 테이블(simple_mode_attendance) → 출근/퇴근 / 휴게 테이블 분리
    if (oldVersion < 3) {
      await _migrateV3_splitAttendanceTable(db);
    }

    // v3 → v4: simple_break_attendance 에 type 컬럼 추가 + (date, type) PK로 변경
    if (oldVersion < 4) {
      await _migrateV4_addTypeToBreakAttendance(db);
    }
  }

  /// 필요 시 외부에서 DB를 명시적으로 닫고 싶을 때 사용할 수 있는 헬퍼
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
  }

  /// v2 마이그레이션:
  /// - 기존 simple_mode_attendance(id 포함) → simple_mode_attendance_old로 rename
  /// - id 없는 새 simple_mode_attendance 생성 (PRIMARY KEY(date, type))
  /// - 데이터 복사 후 old 테이블 drop
  Future<void> _migrateV2_removeIdAndUseCompositePk(Database db) async {
    // 기존 테이블이 없을 수도 있으니 방어적으로 처리
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='simple_mode_attendance'",
    );
    if (tables.isEmpty) {
      // 테이블 없으면 새 스키마만 생성
      await _createSimpleModeAttendanceTable(db);
      return;
    }

    // 1) rename
    await db.execute(
      'ALTER TABLE simple_mode_attendance RENAME TO simple_mode_attendance_old;',
    );

    // 2) 새로운 스키마로 테이블 생성
    await _createSimpleModeAttendanceTable(db);

    // 3) 데이터 복사
    await db.execute('''
      INSERT OR REPLACE INTO simple_mode_attendance (date, type, time, created_at)
      SELECT date, type, time, created_at FROM simple_mode_attendance_old;
    ''');

    // 4) 옛 테이블 드랍
    await db.execute('DROP TABLE IF EXISTS simple_mode_attendance_old;');
  }

  /// v3 마이그레이션:
  /// - 기존 단일 테이블(simple_mode_attendance) 데이터를
  ///   simple_work_attendance / simple_break_attendance 로 분리 이관
  /// - 이후 simple_mode_attendance 테이블은 제거
  Future<void> _migrateV3_splitAttendanceTable(Database db) async {
    // 1) 대상 테이블(분리된 두 테이블) 생성 보장
    await _createWorkAttendanceTable(db);
    await _createBreakAttendanceTable(db);

    // 2) 기존 단일 테이블 존재 여부 확인
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='simple_mode_attendance'",
    );
    if (tables.isEmpty) {
      // 이미 v3 스키마만 사용하는 신규 DB일 수 있음
      return;
    }

    // 3) 출근/퇴근 데이터 → simple_work_attendance
    await db.execute('''
      INSERT OR REPLACE INTO simple_work_attendance (date, type, time, created_at)
      SELECT date, type, time, created_at
      FROM simple_mode_attendance
      WHERE type IN ('work_in', 'work_out');
    ''');

    // 4) 휴게 데이터 → simple_break_attendance
    await db.execute('''
      INSERT OR REPLACE INTO simple_break_attendance (date, type, time, created_at)
      SELECT date, 'start' as type, time, created_at
      FROM simple_mode_attendance
      WHERE type = 'break';
    ''');

    // 5) 기존 단일 테이블 제거
    await db.execute('DROP TABLE IF EXISTS simple_mode_attendance;');
  }

  /// v4 마이그레이션:
  /// - simple_break_attendance 스키마를 (date, type, time, created_at, PRIMARY KEY(date, type)) 로 변경
  /// - 기존에는 (date, time, created_at, PRIMARY KEY(date)) 구조일 수 있음
  /// - 기존 모든 행에 대해 type = 'start'를 부여해 이관
  Future<void> _migrateV4_addTypeToBreakAttendance(Database db) async {
    // 1) 기존 break 테이블 존재 여부 확인
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='simple_break_attendance'",
    );
    if (tables.isEmpty) {
      // 기존 break 테이블이 없다면, 새 스키마로만 생성
      await _createBreakAttendanceTable(db);
      return;
    }

    // 2) 기존 테이블 rename
    await db.execute(
      'ALTER TABLE simple_break_attendance RENAME TO simple_break_attendance_old;',
    );

    // 3) 새 스키마로 break 테이블 생성
    await _createBreakAttendanceTable(db);

    // 4) 데이터 이관: 기존 모든 row 에 대해 type = 'start' 부여
    await db.execute('''
      INSERT OR REPLACE INTO simple_break_attendance (date, type, time, created_at)
      SELECT date, 'start' as type, time, created_at
      FROM simple_break_attendance_old;
    ''');

    // 5) old 테이블 제거
    await db.execute('DROP TABLE IF EXISTS simple_break_attendance_old;');
  }

  /// 출근/퇴근 로그 테이블 생성
  ///
  /// - date: yyyy-MM-dd
  /// - type: 'work_in' 또는 'work_out'
  /// - time: HH:mm
  /// - created_at: ISO8601 문자열
  /// - PK: (date, type)
  Future<void> _createWorkAttendanceTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS simple_work_attendance (
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        time TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (date, type)
      );
    ''');
  }

  /// 휴게 로그 테이블 생성
  ///
  /// - date: yyyy-MM-dd
  /// - type: 'start' (현재는 시작만 사용)
  /// - time: HH:mm
  /// - created_at: ISO8601 문자열
  /// - PK: (date, type)
  Future<void> _createBreakAttendanceTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS simple_break_attendance (
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        time TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (date, type)
      );
    ''');
  }

  /// v2 스키마의 단일 테이블 생성
  ///
  /// - (리팩터링 이후에는 신규 생성 시 사용하지 않고,
  ///   v1 → v2 마이그레이션용으로만 사용됨)
  Future<void> _createSimpleModeAttendanceTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS simple_mode_attendance (
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        time TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (date, type)
      );
    ''');
  }
}
