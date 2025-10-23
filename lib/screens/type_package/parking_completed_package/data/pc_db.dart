import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class ParkingCompletedDb {
  ParkingCompletedDb._();
  static final ParkingCompletedDb instance = ParkingCompletedDb._();

  static const dbName = 'parking_completed.db';

  // ✅ v2로 올립니다. (UNIQUE 제약 + 인덱스 추가를 위한 마이그레이션 포함)
  static const dbVersion = 2;

  // 테이블/컬럼
  static const table = 'parking_completed_records';
  static const colId = 'id';
  static const colPlate = 'plate_number';
  static const colArea = 'area';
  static const colCreatedAt = 'created_at';

  Database? _db;
  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final base = await getDatabasesPath();
    final path = p.join(base, dbName);

    final db = await openDatabase(
      path,
      version: dbVersion,
      onCreate: (db, version) async {
        // ✅ v2 스키마: UNIQUE(plate_number, area, created_at) + 인덱스 2개
        await db.execute('''
          CREATE TABLE $table(
            $colId INTEGER PRIMARY KEY AUTOINCREMENT,
            $colPlate TEXT NOT NULL,
            $colArea TEXT NOT NULL,
            $colCreatedAt INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
            UNIQUE($colPlate, $colArea, $colCreatedAt) ON CONFLICT IGNORE
          )
        ''');

        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_${table}_plate_area
          ON $table($colPlate, $colArea)
        ''');

        // ✅ created_at 정렬/필터 최적화를 위한 인덱스
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_${table}_created_at
          ON $table($colCreatedAt DESC)
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        // ✅ 1→2 마이그레이션: UNIQUE 제약 및 created_at 인덱스 반영
        if (oldV < 2) {
          await _migrateV1toV2(db);
        }
      },
    );

    // 필요한 경우: await db.execute('PRAGMA foreign_keys = ON;');
    return db;
  }

  Future<void> _migrateV1toV2(Database db) async {
    // v1 테이블에는 UNIQUE/created_at 인덱스가 없음.
    // 새 테이블을 만들고 데이터 이동 → 교체합니다.
    await db.execute('PRAGMA foreign_keys=OFF;');
    await db.execute('BEGIN TRANSACTION;');
    try {
      await db.execute('''
        CREATE TABLE ${table}_new(
          $colId INTEGER PRIMARY KEY AUTOINCREMENT,
          $colPlate TEXT NOT NULL,
          $colArea TEXT NOT NULL,
          $colCreatedAt INTEGER NOT NULL,
          UNIQUE($colPlate, $colArea, $colCreatedAt) ON CONFLICT IGNORE
        )
      ''');

      // created_at이 NULL인 기존 레코드는 now()로 보정
      await db.execute('''
        INSERT OR IGNORE INTO ${table}_new ($colId, $colPlate, $colArea, $colCreatedAt)
        SELECT $colId, $colPlate, $colArea,
               COALESCE($colCreatedAt, strftime('%s','now')*1000)
        FROM $table
      ''');

      await db.execute('DROP TABLE $table;');
      await db.execute('ALTER TABLE ${table}_new RENAME TO $table;');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_${table}_plate_area
        ON $table($colPlate, $colArea)
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_${table}_created_at
        ON $table($colCreatedAt DESC)
      ''');

      await db.execute('COMMIT;');
    } catch (e) {
      await db.execute('ROLLBACK;');
      rethrow;
    } finally {
      await db.execute('PRAGMA foreign_keys=ON;');
    }
  }

  Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null && d.isOpen) await d.close();
  }
}
