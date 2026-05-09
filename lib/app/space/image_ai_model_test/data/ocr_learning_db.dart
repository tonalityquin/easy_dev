import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class OcrLearningDb {
  OcrLearningDb._internal();

  static final OcrLearningDb instance = OcrLearningDb._internal();

  static const String dbFileName = 'space_ocr_learning.db';
  static const int dbVersion = 2;

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, dbFileName);
    debugPrint('[OcrLearningDb] open at $path');

    return openDatabase(
      path,
      version: dbVersion,
      onCreate: _onCreate,
      onOpen: _onOpen,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS ocr_session (
        session_id TEXT PRIMARY KEY,
        created_at_ms INTEGER NOT NULL,

        last_text TEXT,
        candidates_json TEXT,
        selected_candidate TEXT,
        attempt_count INTEGER,
        torch_on INTEGER NOT NULL DEFAULT 0,
        force_insert_on INTEGER NOT NULL DEFAULT 0,
        used_learning_mid INTEGER NOT NULL DEFAULT 0,
        used_learning_rank INTEGER NOT NULL DEFAULT 0,

        edit_front_cnt INTEGER NOT NULL DEFAULT 0,
        edit_mid_cnt INTEGER NOT NULL DEFAULT 0,
        edit_back_cnt INTEGER NOT NULL DEFAULT 0,
        edit_total_cnt INTEGER NOT NULL DEFAULT 0,

        final_plate TEXT,
        final_front TEXT,
        final_mid TEXT,
        final_back TEXT,
        committed_at_ms INTEGER
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_ocr_session_committed
      ON ocr_session(committed_at_ms);
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS mid_correction_stat (
        raw_mid TEXT NOT NULL,
        final_mid TEXT NOT NULL,
        cnt INTEGER NOT NULL DEFAULT 0,
        last_seen_ms INTEGER NOT NULL,
        PRIMARY KEY(raw_mid, final_mid)
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_mid_correction_raw_mid
      ON mid_correction_stat(raw_mid);
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS front_len_stat (
        len INTEGER PRIMARY KEY,
        cnt INTEGER NOT NULL DEFAULT 0,
        last_seen_ms INTEGER NOT NULL
      );
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS candidate_correction_stat (
        raw_candidate TEXT NOT NULL,
        final_plate TEXT NOT NULL,
        cnt INTEGER NOT NULL DEFAULT 0,
        last_seen_ms INTEGER NOT NULL,
        PRIMARY KEY(raw_candidate, final_plate)
      );
    ''');

    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_candidate_correction_raw_candidate
      ON candidate_correction_stat(raw_candidate);
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS candidate_correction_stat (
          raw_candidate TEXT NOT NULL,
          final_plate TEXT NOT NULL,
          cnt INTEGER NOT NULL DEFAULT 0,
          last_seen_ms INTEGER NOT NULL,
          PRIMARY KEY(raw_candidate, final_plate)
        );
      ''');

      await db.execute('''
        CREATE INDEX IF NOT EXISTS idx_candidate_correction_raw_candidate
        ON candidate_correction_stat(raw_candidate);
      ''');
    }
  }

  Future<void> _onOpen(Database db) async {
    await db.execute('PRAGMA foreign_keys = ON;');
  }

  Future<void> close() async {
    if (_db == null) return;
    await _db!.close();
    _db = null;
  }
}
