// lib/screens/type_package/parking_completed_package/data/pc_db.dart

import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class ParkingCompletedDb {
  ParkingCompletedDb._();
  static final ParkingCompletedDb instance = ParkingCompletedDb._();

  static const dbName = 'parking_completed.db';

  // ✅ v4: is_departure_completed 컬럼 추가
  static const dbVersion = 4;

  // 테이블/컬럼
  static const table = 'parking_completed_records';
  static const colId = 'id';
  static const colPlate = 'plate_number';
  static const colLocation = 'location';
  static const colCreatedAt = 'created_at';
  static const colIsDepartureCompleted = 'is_departure_completed';

  Database? _db;
  Future<Database> get database async => _db ??= await _open();

  Future<Database> _open() async {
    final base = await getDatabasesPath();
    final path = p.join(base, dbName);

    final db = await openDatabase(
      path,
      version: dbVersion,
      onCreate: (db, version) async {
        await _createSchemaV4(db);
      },
      onUpgrade: (db, oldV, newV) async {
        // 🔹 v1/v2/v3 → v4 업그레이드 시, 기존 테이블/데이터는 모두 삭제 후 재생성
        if (oldV < 4) {
          await _recreateSchemaV4(db);
        }
      },
    );

    return db;
  }

  /// v4 스키마 생성
  /// - location 컬럼 사용
  /// - is_departure_completed 플래그 추가
  /// - UNIQUE(plate_number, location, created_at) + 인덱스 2개
  Future<void> _createSchemaV4(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE $table(
        $colId INTEGER PRIMARY KEY AUTOINCREMENT,
        $colPlate TEXT NOT NULL,
        $colLocation TEXT NOT NULL,
        $colCreatedAt INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
        $colIsDepartureCompleted INTEGER NOT NULL DEFAULT 0,
        UNIQUE($colPlate, $colLocation, $colCreatedAt) ON CONFLICT IGNORE
      )
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_${table}_plate_location
      ON $table($colPlate, $colLocation)
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_${table}_created_at
      ON $table($colCreatedAt DESC)
    ''');
  }

  /// v4 스키마로 완전히 재생성 (기존 데이터는 모두 제거됨)
  Future<void> _recreateSchemaV4(Database db) async {
    await db.transaction((txn) async {
      await txn.execute('DROP TABLE IF EXISTS $table;');
      await _createSchemaV4(txn);
    });
  }

  Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null && d.isOpen) await d.close();
  }
}
