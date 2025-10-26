import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class OfflineAuthDb {
  OfflineAuthDb._();
  static final OfflineAuthDb instance = OfflineAuthDb._();

  static const _dbName = 'offlines.db';
  static const _dbVersion = 7;

  static const tableSessions  = 'offline_sessions';
  @Deprecated('Use tableSessions instead')
  static const table          = tableSessions;

  static const tableDivision  = 'division';
  static const tableArea      = 'area';
  static const tableAccounts  = 'offline_accounts';
  static const tableAccAreas  = 'offline_account_areas';
  static const tableAccDivs   = 'offline_account_divisions';

  static const tablePlates    = 'offline_plates';
  static const tableBills     = 'offline_bills';
  static const tableLocations = 'offline_locations';

  Database? _db;
  Future<Database>? _openingFuture;

  static const int _divCreatedAtMs  = 1746712957000;
  static const int _seedCreatedAtMs = 1746853071000;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    return _open();
  }

  Future<void> reopenIfNeeded() async {
    if (_db == null || !_db!.isOpen) {
      await _open();
    }
  }

  Future<Database> _open() async {
    final opening = _openingFuture;
    if (opening != null) return opening;

    final completer = Completer<Database>();
    _openingFuture = completer.future;
    try {
      final dbPath = await getDatabasesPath();
      final path = p.join(dbPath, _dbName);

      final db = await openDatabase(
        path,
        version: _dbVersion,
        onCreate: (Database db, int version) async {
          await db.execute('''
            CREATE TABLE $tableSessions(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              user_id TEXT NOT NULL,
              name TEXT NOT NULL,
              position TEXT NOT NULL,
              phone TEXT NOT NULL,
              area TEXT NOT NULL,
              created_at INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE $tableDivision(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL UNIQUE,
              createdAt INTEGER NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE $tableArea(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              englishName TEXT NOT NULL,
              division TEXT NOT NULL,
              isHeadquarter INTEGER NOT NULL,
              createdAt INTEGER NOT NULL,
              UNIQUE(name)
            )
          ''');

          await db.execute('''
            CREATE TABLE $tableAccounts(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              userId TEXT NOT NULL UNIQUE,
              name TEXT NOT NULL,
              phone TEXT NOT NULL,
              pin TEXT NOT NULL,
              isSaved INTEGER NOT NULL DEFAULT 1,   -- 0/1
              createdAt INTEGER NOT NULL,

              -- v4 확장 메타
              email TEXT,
              role TEXT,
              position TEXT,
              isSelected INTEGER NOT NULL DEFAULT 0, -- 0/1
              isWorking INTEGER NOT NULL DEFAULT 0,  -- 0/1
              currentArea TEXT,
              selectedArea TEXT,
              englishSelectedAreaName TEXT,
              startHour INTEGER,
              startMinute INTEGER,
              endHour INTEGER,
              endMinute INTEGER,

              -- v5 추가 메타
              division TEXT,
              area TEXT
            )
          ''');

          await db.execute('''
            CREATE TABLE $tableAccAreas(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              userId TEXT NOT NULL,
              name TEXT NOT NULL,
              orderIndex INTEGER NOT NULL,
              UNIQUE(userId, orderIndex),
              UNIQUE(userId, name)
            )
          ''');

          await db.execute('''
            CREATE TABLE $tableAccDivs(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              userId TEXT NOT NULL,
              name TEXT NOT NULL,
              orderIndex INTEGER NOT NULL,
              UNIQUE(userId, orderIndex),
              UNIQUE(userId, name)
            )
          ''');

          await db.execute('''
            CREATE TABLE $tablePlates(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              plate_key TEXT NOT NULL UNIQUE,
              plate_number TEXT NOT NULL,
              plate_four_digit TEXT,
              region TEXT,
              area TEXT,
              location TEXT,
              billing_type TEXT,
              custom_status TEXT,
              basic_amount INTEGER NOT NULL DEFAULT 0,
              basic_standard INTEGER NOT NULL DEFAULT 0,
              add_amount INTEGER NOT NULL DEFAULT 0,
              add_standard INTEGER NOT NULL DEFAULT 0,
              is_locked_fee INTEGER NOT NULL DEFAULT 0,
              locked_fee_amount INTEGER NOT NULL DEFAULT 0,
              locked_at_seconds INTEGER,
              is_selected INTEGER NOT NULL DEFAULT 0,
              status_type TEXT,
              updated_at INTEGER,
              request_time TEXT,
              user_name TEXT,
              selected_by TEXT,
              user_adjustment INTEGER NOT NULL DEFAULT 0,
              regular_amount INTEGER NOT NULL DEFAULT 0,
              regular_duration_hours INTEGER NOT NULL DEFAULT 0,
              image_urls TEXT,
              logs TEXT,
              created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_${tablePlates}_plate_area
            ON $tablePlates(plate_number, area)
          ''');

          await db.execute('''
            CREATE TABLE $tableBills(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              bill_key TEXT NOT NULL UNIQUE,          -- 예: "무료_HQ 지역"
              area TEXT NOT NULL,                     -- 예: "HQ 지역"
              count_type TEXT NOT NULL,               -- 예: "무료"
              type TEXT NOT NULL,                     -- 예: "변동"
              basic_amount INTEGER NOT NULL DEFAULT 0,
              basic_standard INTEGER NOT NULL DEFAULT 1,
              add_amount INTEGER NOT NULL DEFAULT 0,
              add_standard INTEGER NOT NULL DEFAULT 1,
              updated_at INTEGER,                     -- ms epoch
              created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
              UNIQUE(area, count_type, type)
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_${tableBills}_area_type
            ON $tableBills(area, type)
          ''');

          await db.execute('''
            CREATE TABLE $tableLocations(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              location_key TEXT NOT NULL UNIQUE,      -- 예: "승강기_HQ 지역", "A-1_HQ 지역"
              area TEXT NOT NULL,
              location_name TEXT NOT NULL,            -- 예: "승강기", "A-1"
              parent TEXT NOT NULL DEFAULT '',        -- 예: "승강기", "airport" (빈문자 기본)
              type TEXT NOT NULL,                     -- 예: "single", "composite"
              capacity INTEGER NOT NULL DEFAULT 0,
              is_selected INTEGER NOT NULL DEFAULT 0, -- 0/1
              timestamp_raw TEXT,                     -- 원문 문자열 보관
              updated_at INTEGER,                     -- ms epoch (선택)
              created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
              UNIQUE(area, location_name, parent)
            )
          ''');
          await db.execute('''
            CREATE INDEX IF NOT EXISTS idx_${tableLocations}_area_name
            ON $tableLocations(area, location_name)
          ''');

          await _seedDefaults(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          if (oldVersion < 2) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $tableDivision(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL UNIQUE,
                createdAt INTEGER NOT NULL
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $tableArea(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                name TEXT NOT NULL,
                englishName TEXT NOT NULL,
                division TEXT NOT NULL,
                isHeadquarter INTEGER NOT NULL,
                createdAt INTEGER NOT NULL,
                UNIQUE(name)
              )
            ''');
          }
          if (oldVersion < 3) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $tableAccounts(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                userId TEXT NOT NULL UNIQUE,
                name TEXT NOT NULL,
                phone TEXT NOT NULL,
                pin TEXT NOT NULL,
                isSaved INTEGER NOT NULL DEFAULT 1,
                createdAt INTEGER NOT NULL
              )
            ''');
          }
          if (oldVersion < 4) {
            final addCols = <String>[
              'ALTER TABLE $tableAccounts ADD COLUMN email TEXT',
              'ALTER TABLE $tableAccounts ADD COLUMN role TEXT',
              'ALTER TABLE $tableAccounts ADD COLUMN position TEXT',
              'ALTER TABLE $tableAccounts ADD COLUMN isSelected INTEGER NOT NULL DEFAULT 0',
              'ALTER TABLE $tableAccounts ADD COLUMN isWorking INTEGER NOT NULL DEFAULT 0',
              'ALTER TABLE $tableAccounts ADD COLUMN currentArea TEXT',
              'ALTER TABLE $tableAccounts ADD COLUMN selectedArea TEXT',
              'ALTER TABLE $tableAccounts ADD COLUMN englishSelectedAreaName TEXT',
              'ALTER TABLE $tableAccounts ADD COLUMN startHour INTEGER',
              'ALTER TABLE $tableAccounts ADD COLUMN startMinute INTEGER',
              'ALTER TABLE $tableAccounts ADD COLUMN endHour INTEGER',
              'ALTER TABLE $tableAccounts ADD COLUMN endMinute INTEGER',
            ];
            for (final sql in addCols) {
              await db.execute(sql);
            }
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $tableAccAreas(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                userId TEXT NOT NULL,
                name TEXT NOT NULL,
                orderIndex INTEGER NOT NULL,
                UNIQUE(userId, orderIndex),
                UNIQUE(userId, name)
              )
            ''');
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $tableAccDivs(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                userId TEXT NOT NULL,
                name TEXT NOT NULL,
                orderIndex INTEGER NOT NULL,
                UNIQUE(userId, orderIndex),
                UNIQUE(userId, name)
              )
            ''');
          }
          if (oldVersion < 5) {
            try { await db.execute('ALTER TABLE $tableAccounts ADD COLUMN division TEXT'); } catch (_) {}
            try { await db.execute('ALTER TABLE $tableAccounts ADD COLUMN area TEXT'); } catch (_) {}
            await db.execute('''
              UPDATE $tableAccounts
                 SET division = COALESCE(division, 'dev'),
                     area     = COALESCE(area, 'HQ 지역')
               WHERE userId = 'tester'
            ''');
          }
          if (oldVersion < 6) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $tablePlates(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                plate_key TEXT NOT NULL UNIQUE,
                plate_number TEXT NOT NULL,
                plate_four_digit TEXT,
                region TEXT,
                area TEXT,
                location TEXT,
                billing_type TEXT,
                custom_status TEXT,
                basic_amount INTEGER NOT NULL DEFAULT 0,
                basic_standard INTEGER NOT NULL DEFAULT 0,
                add_amount INTEGER NOT NULL DEFAULT 0,
                add_standard INTEGER NOT NULL DEFAULT 0,
                is_locked_fee INTEGER NOT NULL DEFAULT 0,
                locked_fee_amount INTEGER NOT NULL DEFAULT 0,
                locked_at_seconds INTEGER,
                is_selected INTEGER NOT NULL DEFAULT 0,
                status_type TEXT,
                updated_at INTEGER,
                request_time TEXT,
                user_name TEXT,
                selected_by TEXT,
                user_adjustment INTEGER NOT NULL DEFAULT 0,
                regular_amount INTEGER NOT NULL DEFAULT 0,
                regular_duration_hours INTEGER NOT NULL DEFAULT 0,
                image_urls TEXT,
                logs TEXT,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000)
              )
            ''');
            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_${tablePlates}_plate_area
              ON $tablePlates(plate_number, area)
            ''');
          }
          if (oldVersion < 7) {
            await db.execute('''
              CREATE TABLE IF NOT EXISTS $tableBills(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                bill_key TEXT NOT NULL UNIQUE,
                area TEXT NOT NULL,
                count_type TEXT NOT NULL,
                type TEXT NOT NULL,
                basic_amount INTEGER NOT NULL DEFAULT 0,
                basic_standard INTEGER NOT NULL DEFAULT 1,
                add_amount INTEGER NOT NULL DEFAULT 0,
                add_standard INTEGER NOT NULL DEFAULT 1,
                updated_at INTEGER,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
                UNIQUE(area, count_type, type)
              )
            ''');
            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_${tableBills}_area_type
              ON $tableBills(area, type)
            ''');

            await db.execute('''
              CREATE TABLE IF NOT EXISTS $tableLocations(
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                location_key TEXT NOT NULL UNIQUE,
                area TEXT NOT NULL,
                location_name TEXT NOT NULL,
                parent TEXT NOT NULL DEFAULT '',
                type TEXT NOT NULL,
                capacity INTEGER NOT NULL DEFAULT 0,
                is_selected INTEGER NOT NULL DEFAULT 0,
                timestamp_raw TEXT,
                updated_at INTEGER,
                created_at INTEGER NOT NULL DEFAULT (strftime('%s','now')*1000),
                UNIQUE(area, location_name, parent)
              )
            ''');
            await db.execute('''
              CREATE INDEX IF NOT EXISTS idx_${tableLocations}_area_name
              ON $tableLocations(area, location_name)
            ''');
          }

          await _seedDefaults(db);
        },
        onOpen: (db) async {
          await _seedDefaults(db);
        },
      );

      _db = db;
      if (!completer.isCompleted) completer.complete(db);
      return db;
    } catch (e, st) {
      if (!completer.isCompleted) completer.completeError(e, st);
      rethrow;
    } finally {
      _openingFuture = null;
    }
  }

  static Future<void> _seedDefaults(Database db) async {
    await db.transaction((txn) async {
      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableDivision(name, createdAt) VALUES(?, ?)',
        ['dev', _divCreatedAtMs],
      );

      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableArea(name, englishName, division, isHeadquarter, createdAt) VALUES(?, ?, ?, ?, ?)',
        ['HQ 지역', 'HQ', 'dev', 1, _seedCreatedAtMs],
      );
      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableArea(name, englishName, division, isHeadquarter, createdAt) VALUES(?, ?, ?, ?, ?)',
        ['WorkingArea 지역', 'WorkingArea', 'dev', 0, _seedCreatedAtMs],
      );

      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableAccounts(userId, name, phone, pin, isSaved, createdAt) VALUES(?, ?, ?, ?, ?, ?)',
        ['tester', 'tester', '01012345678', '12345', 1, _seedCreatedAtMs],
      );

      await txn.rawUpdate(
        '''
        UPDATE $tableAccounts
           SET email = COALESCE(email, ''),
               role = COALESCE(role, 'dev'),
               position = COALESCE(position, 'tester'),
               isSelected = COALESCE(isSelected, 0),
               isWorking  = COALESCE(isWorking, 0),
               currentArea = COALESCE(currentArea, 'HQ 지역'),
               selectedArea = COALESCE(selectedArea, 'HQ 지역'),
               englishSelectedAreaName = COALESCE(englishSelectedAreaName, 'HQ'),
               startHour = COALESCE(startHour, 9),
               startMinute = COALESCE(startMinute, 0),
               endHour = COALESCE(endHour, 18),
               endMinute = COALESCE(endMinute, 0),
               division = COALESCE(division, 'dev'),
               area = COALESCE(area, 'HQ 지역')
         WHERE userId = 'tester'
        ''',
      );

      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableAccAreas(userId, name, orderIndex) VALUES(?, ?, ?)',
        ['tester', 'HQ 지역', 0],
      );
      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableAccAreas(userId, name, orderIndex) VALUES(?, ?, ?)',
        ['tester', 'WorkingArea 지역', 1],
      );
      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableAccDivs(userId, name, orderIndex) VALUES(?, ?, ?)',
        ['tester', 'dev', 0],
      );

      await txn.rawInsert(
        '''
        INSERT OR IGNORE INTO $tableLocations
          (location_key, area, location_name, parent, type, capacity, is_selected, timestamp_raw)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          '승강기_HQ 지역',
          'HQ 지역',
          '승강기',
          '승강기',
          'single',
          14,
          0,
          '2025년 10월 7일 오후 3시 21분 47초 UTC+9',
        ],
      );

      await txn.rawInsert(
        '''
        INSERT OR IGNORE INTO $tableLocations
          (location_key, area, location_name, parent, type, capacity, is_selected, timestamp_raw)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          'A-1_HQ 지역',
          'HQ 지역',
          'A-1',
          'airport',
          'composite',
          3,
          0,
          '2025년 9월 18일 오후 6시 12분 51초 UTC+9',
        ],
      );

      await txn.rawInsert(
        '''
        INSERT OR IGNORE INTO $tableLocations
          (location_key, area, location_name, parent, type, capacity, is_selected, timestamp_raw)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          'A-2_HQ 지역',
          'HQ 지역',
          'A-2',
          'airport',
          'composite',
          2,
          0,
          '2025년 9월 18일 오후 6시 12분 51초 UTC+9',
        ],
      );

      await txn.rawInsert(
        '''
        INSERT OR IGNORE INTO $tableBills
          (bill_key, area, count_type, type, basic_amount, basic_standard, add_amount, add_standard)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          '무료_HQ 지역',
          'HQ 지역',
          '무료',
          '변동',
          0, 1, 0, 1,
        ],
      );

      await txn.rawInsert(
        '''
        INSERT OR IGNORE INTO $tableBills
          (bill_key, area, count_type, type, basic_amount, basic_standard, add_amount, add_standard)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        ''',
        [
          '일반주차_HQ 지역',
          'HQ 지역',
          '일반주차',
          '변동',
          2000, 5, 1000, 1,
        ],
      );
    });
  }
}
