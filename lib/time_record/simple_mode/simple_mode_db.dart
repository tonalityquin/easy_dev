// lib/time_record/simple_mode/simple_mode_db.dart
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class SimpleModeDb {
  SimpleModeDb._();
  static final SimpleModeDb instance = SimpleModeDb._();

  static const _dbName = 'simple_mode_attendance.db';
  static const _dbVersion = 2; // ✅ v2: id 제거 + (date, type) PK

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
      onUpgrade: _onUpgrade, // ✅ 마이그레이션 훅 추가
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

  /// 버전 업그레이드 마이그레이션
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('[SimpleModeDb] onUpgrade $oldVersion → $newVersion');
    if (oldVersion < 2) {
      await _migrateV2_removeIdAndUseCompositePk(db);
    }
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
    //
    //  기존 Repository가 (date, type) 조합당 항상 1건만 유지하도록
    //  DELETE 후 INSERT 패턴을 썼기 때문에, 중복은 없다고 가정 가능.
    await db.execute('''
      INSERT OR REPLACE INTO simple_mode_attendance (date, type, time, created_at)
      SELECT date, type, time, created_at FROM simple_mode_attendance_old;
    ''');

    // 4) 옛 테이블 드랍
    await db.execute('DROP TABLE IF EXISTS simple_mode_attendance_old;');
  }

  /// 약식 모드 출근/퇴근/휴게 시간 로그 테이블 생성
  ///
  /// ✅ v2 스키마:
  ///   - id 제거
  ///   - (date, type) 복합 PRIMARY KEY
  ///   - created_at 는 마지막 변경 시각
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

    // (date, type) PK에 이미 인덱스가 포함되므로 별도의 인덱스 불필요.
    // 필요하면 아래처럼 추가 인덱스를 둘 수도 있음.
    //
    // await db.execute('''
    //   CREATE INDEX IF NOT EXISTS idx_simple_mode_attendance_date
    //   ON simple_mode_attendance(date);
    // ''');
  }
}
