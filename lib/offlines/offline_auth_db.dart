import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class OfflineAuthDb {
  OfflineAuthDb._();
  static final OfflineAuthDb instance = OfflineAuthDb._();

  static const _dbName = 'offlines.db';
  static const _dbVersion = 1;
  static const table = 'offline_sessions';

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, _dbName);
    _db = await openDatabase(
      path,
      version: _dbVersion,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE $table(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            name TEXT NOT NULL,
            position TEXT NOT NULL,
            phone TEXT NOT NULL,
            area TEXT NOT NULL,
            created_at INTEGER NOT NULL
          )
        ''');
      },
    );
    return _db!;
  }
}
