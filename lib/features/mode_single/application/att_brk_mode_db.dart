import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../app/terminal/application/parkinworkin_terminal_diagnostics.dart';

class AttBrkModeDb {
  AttBrkModeDb._();

  static final AttBrkModeDb instance = AttBrkModeDb._();

  static const String dbName = 'single_mode_attendance.db';
  static const String workAttendanceTable = 'single_work_attendance';
  static const String breakAttendanceTable = 'single_break_attendance';

  static const String _legacyDbName = 'simple_mode_attendance.db';
  static const String _legacyAttendanceTable = 'simple_mode_attendance';
  static const String _legacyWorkAttendanceTable = 'simple_work_attendance';
  static const String _legacyBreakAttendanceTable = 'simple_break_attendance';
  static const int _dbVersion = 5;

  Database? _db;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) {
      return _db!;
    }

    final dbPath = await getDatabasesPath();
    final fullPath = await _prepareDatabasePath(dbPath);

    _db = await openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: _onCreate,
      onOpen: _onOpen,
      onUpgrade: _onUpgrade,
    );

    _record('single_mode_db_open', <String, Object?>{'path': fullPath});
    return _db!;
  }

  Future<String> _prepareDatabasePath(String dbPath) async {
    final targetPath = p.join(dbPath, dbName);
    final legacyPath = p.join(dbPath, _legacyDbName);
    final targetFile = File(targetPath);
    final legacyFile = File(legacyPath);

    if (await targetFile.exists() || !await legacyFile.exists()) {
      return targetPath;
    }

    try {
      await _renameIfExists(legacyPath, targetPath);
      await _renameIfExists('$legacyPath-wal', '$targetPath-wal');
      await _renameIfExists('$legacyPath-shm', '$targetPath-shm');
      await _renameIfExists('$legacyPath-journal', '$targetPath-journal');
      _record('single_mode_db_file_migrated', <String, Object?>{
        'from': _legacyDbName,
        'to': dbName,
      });
      return targetPath;
    } catch (error) {
      _record('single_mode_db_file_migration_failed', <String, Object?>{
        'from': _legacyDbName,
        'to': dbName,
        'error': error.toString(),
      });
      rethrow;
    }
  }

  Future<void> _renameIfExists(String sourcePath, String targetPath) async {
    final source = File(sourcePath);
    if (!await source.exists()) return;
    final target = File(targetPath);
    if (await target.exists()) {
      await target.delete();
    }
    await source.rename(targetPath);
  }

  Future<void> _onCreate(Database db, int version) async {
    await _createSingleTables(db);
    _record('single_mode_db_create', <String, Object?>{'version': version});
  }

  Future<void> _onOpen(Database db) async {
    await _migrateLegacyTablesIfPresent(db);
    await _createSingleTables(db);
    _record('single_mode_db_ready', const <String, Object?>{});
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    _record('single_mode_db_upgrade_start', <String, Object?>{
      'from': oldVersion,
      'to': newVersion,
    });

    if (oldVersion < 2) {
      await _migrateV2RemoveIdAndUseCompositePk(db);
    }
    if (oldVersion < 3) {
      await _migrateV3SplitAttendanceTable(db);
    }
    if (oldVersion < 4) {
      await _migrateV4AddTypeToBreakAttendance(db);
    }
    if (oldVersion < 5) {
      await _migrateV5SingleNaming(db);
    }

    _record('single_mode_db_upgrade_complete', <String, Object?>{
      'from': oldVersion,
      'to': newVersion,
    });
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
  }

  Future<void> _migrateV2RemoveIdAndUseCompositePk(Database db) async {
    if (!await _tableExists(db, _legacyAttendanceTable)) {
      await _createLegacyAttendanceTable(db);
      return;
    }

    const oldTable = '${_legacyAttendanceTable}_old';
    await db.execute(
      'ALTER TABLE $_legacyAttendanceTable RENAME TO $oldTable;',
    );
    await _createLegacyAttendanceTable(db);
    await db.execute('''
      INSERT OR REPLACE INTO $_legacyAttendanceTable (date, type, time, created_at)
      SELECT date, type, time, created_at FROM $oldTable;
    ''');
    await db.execute('DROP TABLE IF EXISTS $oldTable;');
  }

  Future<void> _migrateV3SplitAttendanceTable(Database db) async {
    await _createLegacyWorkAttendanceTable(db);
    await _createLegacyBreakAttendanceTable(db);

    if (!await _tableExists(db, _legacyAttendanceTable)) return;

    await db.execute('''
      INSERT OR REPLACE INTO $_legacyWorkAttendanceTable (date, type, time, created_at)
      SELECT date, type, time, created_at
      FROM $_legacyAttendanceTable
      WHERE type IN ('work_in', 'work_out');
    ''');
    await db.execute('''
      INSERT OR REPLACE INTO $_legacyBreakAttendanceTable (date, type, time, created_at)
      SELECT date, 'start' as type, time, created_at
      FROM $_legacyAttendanceTable
      WHERE type = 'break';
    ''');
    await db.execute('DROP TABLE IF EXISTS $_legacyAttendanceTable;');
  }

  Future<void> _migrateV4AddTypeToBreakAttendance(Database db) async {
    if (!await _tableExists(db, _legacyBreakAttendanceTable)) {
      await _createLegacyBreakAttendanceTable(db);
      return;
    }

    const oldTable = '${_legacyBreakAttendanceTable}_old';
    await db.execute(
      'ALTER TABLE $_legacyBreakAttendanceTable RENAME TO $oldTable;',
    );
    await _createLegacyBreakAttendanceTable(db);
    await db.execute('''
      INSERT OR REPLACE INTO $_legacyBreakAttendanceTable (date, type, time, created_at)
      SELECT date, 'start' as type, time, created_at
      FROM $oldTable;
    ''');
    await db.execute('DROP TABLE IF EXISTS $oldTable;');
  }

  Future<void> _migrateV5SingleNaming(Database db) async {
    await _createSingleTables(db);
    await _copyLegacyRows(db);
    await _dropLegacyTables(db);
    _record('single_mode_db_schema_migrated', const <String, Object?>{
      'version': 5,
    });
  }

  Future<void> _migrateLegacyTablesIfPresent(Database db) async {
    final hasLegacy = await _tableExists(db, _legacyAttendanceTable) ||
        await _tableExists(db, _legacyWorkAttendanceTable) ||
        await _tableExists(db, _legacyBreakAttendanceTable);
    if (!hasLegacy) return;

    await db.transaction((txn) async {
      await _createSingleTables(txn);
      await _copyLegacyRows(txn);
      await _dropLegacyTables(txn);
    });
    _record('single_mode_db_legacy_tables_recovered', const <String, Object?>{});
  }

  Future<void> _copyLegacyRows(DatabaseExecutor db) async {
    if (await _tableExists(db, _legacyAttendanceTable)) {
      await db.execute('''
        INSERT OR REPLACE INTO $workAttendanceTable (date, type, time, created_at)
        SELECT date, type, time, created_at
        FROM $_legacyAttendanceTable
        WHERE type IN ('work_in', 'work_out');
      ''');
      await db.execute('''
        INSERT OR REPLACE INTO $breakAttendanceTable (date, type, time, created_at)
        SELECT date, 'start' as type, time, created_at
        FROM $_legacyAttendanceTable
        WHERE type = 'break';
      ''');
    }

    if (await _tableExists(db, _legacyWorkAttendanceTable)) {
      await db.execute('''
        INSERT OR REPLACE INTO $workAttendanceTable (date, type, time, created_at)
        SELECT date, type, time, created_at
        FROM $_legacyWorkAttendanceTable;
      ''');
    }

    if (await _tableExists(db, _legacyBreakAttendanceTable)) {
      await db.execute('''
        INSERT OR REPLACE INTO $breakAttendanceTable (date, type, time, created_at)
        SELECT date, type, time, created_at
        FROM $_legacyBreakAttendanceTable;
      ''');
    }
  }

  Future<void> _dropLegacyTables(DatabaseExecutor db) async {
    await db.execute('DROP TABLE IF EXISTS $_legacyAttendanceTable;');
    await db.execute('DROP TABLE IF EXISTS $_legacyWorkAttendanceTable;');
    await db.execute('DROP TABLE IF EXISTS $_legacyBreakAttendanceTable;');
  }

  Future<bool> _tableExists(DatabaseExecutor db, String table) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      <Object?>[table],
    );
    return rows.isNotEmpty;
  }

  Future<void> _createSingleTables(DatabaseExecutor db) async {
    await _createWorkAttendanceTable(db);
    await _createBreakAttendanceTable(db);
  }

  Future<void> _createWorkAttendanceTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $workAttendanceTable (
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        time TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (date, type)
      );
    ''');
  }

  Future<void> _createBreakAttendanceTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $breakAttendanceTable (
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        time TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (date, type)
      );
    ''');
  }

  Future<void> _createLegacyWorkAttendanceTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_legacyWorkAttendanceTable (
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        time TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (date, type)
      );
    ''');
  }

  Future<void> _createLegacyBreakAttendanceTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_legacyBreakAttendanceTable (
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        time TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (date, type)
      );
    ''');
  }

  Future<void> _createLegacyAttendanceTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS $_legacyAttendanceTable (
        date TEXT NOT NULL,
        type TEXT NOT NULL,
        time TEXT NOT NULL,
        created_at TEXT NOT NULL,
        PRIMARY KEY (date, type)
      );
    ''');
  }

  void _record(String event, Map<String, Object?> meta) {
    ParkinWorkinTerminalDiagnostics.record(
      event,
      context: 'single_mode_db',
      meta: meta,
    );
  }
}
