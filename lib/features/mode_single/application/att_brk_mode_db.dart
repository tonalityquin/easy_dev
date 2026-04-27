import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class AttBrkModeDb {
  AttBrkModeDb._();

  static final AttBrkModeDb instance = AttBrkModeDb._();

  static const _dbName = 'simple_mode_attendance.db';

  
  static const _dbVersion = 4;

  Database? _db;

  Future<Database> get database async {
    
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
      onUpgrade: _onUpgrade, 
    );

    debugPrint('[SimpleModeDb] open at $fullPath');
    return _db!;
  }

  Future<void> _onCreate(Database db, int version) async {
    debugPrint('[SimpleModeDb] onCreate v$version');
    
    await _createWorkAttendanceTable(db);
    await _createBrkTable(db);
  }

  Future<void> _onOpen(Database db) async {
    debugPrint('[SimpleModeDb] onOpen → ensure tables');
    
    await _createWorkAttendanceTable(db);
    await _createBrkTable(db);
  }

  
  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    debugPrint('[SimpleModeDb] onUpgrade $oldVersion → $newVersion');

    
    if (oldVersion < 2) {
      await _migrateV2_removeIdAndUseCompositePk(db);
    }

    
    if (oldVersion < 3) {
      await _migrateV3_splitAttendanceTable(db);
    }

    
    if (oldVersion < 4) {
      await _migrateV4_addTypeToBreakAttendance(db);
    }
  }

  
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
  }

  
  
  
  
  Future<void> _migrateV2_removeIdAndUseCompositePk(Database db) async {
    
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='simple_mode_attendance'",
    );
    if (tables.isEmpty) {
      
      await _createAttTable(db);
      return;
    }

    
    await db.execute(
      'ALTER TABLE simple_mode_attendance RENAME TO simple_mode_attendance_old;',
    );

    
    await _createAttTable(db);

    
    await db.execute('''
      INSERT OR REPLACE INTO simple_mode_attendance (date, type, time, created_at)
      SELECT date, type, time, created_at FROM simple_mode_attendance_old;
    ''');

    
    await db.execute('DROP TABLE IF EXISTS simple_mode_attendance_old;');
  }

  
  
  
  
  Future<void> _migrateV3_splitAttendanceTable(Database db) async {
    
    await _createWorkAttendanceTable(db);
    await _createBrkTable(db);

    
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='simple_mode_attendance'",
    );
    if (tables.isEmpty) {
      
      return;
    }

    
    await db.execute('''
      INSERT OR REPLACE INTO simple_work_attendance (date, type, time, created_at)
      SELECT date, type, time, created_at
      FROM simple_mode_attendance
      WHERE type IN ('work_in', 'work_out');
    ''');

    
    await db.execute('''
      INSERT OR REPLACE INTO simple_break_attendance (date, type, time, created_at)
      SELECT date, 'start' as type, time, created_at
      FROM simple_mode_attendance
      WHERE type = 'break';
    ''');

    
    await db.execute('DROP TABLE IF EXISTS simple_mode_attendance;');
  }

  
  
  
  
  Future<void> _migrateV4_addTypeToBreakAttendance(Database db) async {
    
    final tables = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name='simple_break_attendance'",
    );
    if (tables.isEmpty) {
      
      await _createBrkTable(db);
      return;
    }

    
    await db.execute(
      'ALTER TABLE simple_break_attendance RENAME TO simple_break_attendance_old;',
    );

    
    await _createBrkTable(db);

    
    await db.execute('''
      INSERT OR REPLACE INTO simple_break_attendance (date, type, time, created_at)
      SELECT date, 'start' as type, time, created_at
      FROM simple_break_attendance_old;
    ''');

    
    await db.execute('DROP TABLE IF EXISTS simple_break_attendance_old;');
  }

  
  
  
  
  
  
  
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

  
  
  
  
  
  
  
  Future<void> _createBrkTable(Database db) async {
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

  
  
  
  
  Future<void> _createAttTable(Database db) async {
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
