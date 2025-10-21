import 'dart:async';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class ParkingCompletedDb {
  ParkingCompletedDb._();
  static final ParkingCompletedDb instance = ParkingCompletedDb._();

  static const dbName = 'parking_completed.db';
  static const dbVersion = 1;

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
        // 전용 테이블 생성 (id, 전체 번호판, 주차 구역)
        await db.execute('''
          CREATE TABLE $table(
            $colId INTEGER PRIMARY KEY AUTOINCREMENT,
            $colPlate TEXT NOT NULL,
            $colArea TEXT NOT NULL,
            $colCreatedAt INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)
          )
        ''');
        await db.execute('''
          CREATE INDEX IF NOT EXISTS idx_${table}_plate_area
          ON $table($colPlate, $colArea)
        ''');
      },
      onUpgrade: (db, oldV, newV) async {
        // 이후 스키마 변경 시 단계별 migrate 추가
      },
    );
    // 외래키 필요 시: await db.execute('PRAGMA foreign_keys = ON;');
    return db;
  }

  Future<void> close() async {
    final d = _db;
    _db = null;
    if (d != null && d.isOpen) await d.close();
  }
}
