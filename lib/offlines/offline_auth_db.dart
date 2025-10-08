import 'dart:async';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class OfflineAuthDb {
  OfflineAuthDb._();
  static final OfflineAuthDb instance = OfflineAuthDb._();

  // ───────────────── DB 메타 ─────────────────
  static const _dbName = 'offlines.db';
  static const _dbVersion = 5; // ⬅️ v5: offline_accounts에 division, area 컬럼 추가

  // ───────────────── 테이블명 ─────────────────
  static const tableSessions = 'offline_sessions';
  @Deprecated('Use tableSessions instead')
  static const table = tableSessions; // 구 코드 호환용

  static const tableDivision = 'division';                    // 마스터
  static const tableArea = 'area';                            // 마스터
  static const tableAccounts = 'offline_accounts';            // 계정 메타
  static const tableAccAreas = 'offline_account_areas';       // 계정-지역 배열(정렬)
  static const tableAccDivs  = 'offline_account_divisions';   // 계정-디비전 배열(정렬)

  Database? _db;
  Future<Database>? _openingFuture;

  // ───────────────── 시드 타임스탬프(ms) ─────────────────
  // 2025-05-08 23:02:37 (UTC+9)
  static const int _divCreatedAtMs = 1746712957000;
  // 2025-05-10 13:57:51 (UTC+9)
  static const int _seedCreatedAtMs = 1746853071000;

  /// 항상 이 게터로 핸들을 받으세요.
  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    return _open();
  }

  /// 닫혀 있으면 재오픈.
  Future<void> reopenIfNeeded() async {
    if (_db == null || !_db!.isOpen) {
      await _open();
    }
  }

  Future<Database> _open() async {
    // 동시 오픈 방지: 열리고 있으면 그 Future 재사용
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
          // ── 세션(그대로) ──
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

          // ── 마스터: division / area ──
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

          // ── 계정 메타 ──
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
              division TEXT,  -- ⬅️ 선택/대표 디비전
              area TEXT       -- ⬅️ 선택/대표 지역
            )
          ''');

          // ── per-account 배열: areas/divisions (정렬 보존) ──
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

          await _seedDefaults(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // v2: 마스터 테이블
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

          // v3: 계정 테이블(기본형)
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

          // v4: 계정 메타 확장 + per-account 배열 테이블
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

          // v5: offline_accounts에 division/area 추가
          if (oldVersion < 5) {
            try { await db.execute('ALTER TABLE $tableAccounts ADD COLUMN division TEXT'); } catch (_) {}
            try { await db.execute('ALTER TABLE $tableAccounts ADD COLUMN area TEXT'); } catch (_) {}

            // 기존 tester 행 보정: division/area 기본값 주입 (없을 때만)
            await db.execute('''
              UPDATE $tableAccounts
                 SET division = COALESCE(division, 'dev'),
                     area     = COALESCE(area, 'HQ 지역')
               WHERE userId = 'tester'
            ''');
          }

          // 누락 보정 및 시드 보정
          await _seedDefaults(db);
        },
        onOpen: (db) async {
          // 혹시 누락된 시드 보정
          await _seedDefaults(db);
        },
      );

      _db = db;
      completer.complete(db);
      return db;
    } catch (e, st) {
      completer.completeError(e, st);
      rethrow;
    } finally {
      _openingFuture = null;
    }
  }

  /// (선택) 테스트/리셋용
  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
    }
    _db = null;
  }

  // ───────────────── 시드 주입(idempotent) ─────────────────
  static Future<void> _seedDefaults(Database db) async {
    await db.transaction((txn) async {
      // 1) division(dev)
      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableDivision(name, createdAt) VALUES(?, ?)',
        ['dev', _divCreatedAtMs],
      );

      // 2) area(HQ 지역 / WorkingArea 지역) - division="dev"
      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableArea(name, englishName, division, isHeadquarter, createdAt) VALUES(?, ?, ?, ?, ?)',
        ['HQ 지역', 'HQ', 'dev', 1, _seedCreatedAtMs],
      );
      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableArea(name, englishName, division, isHeadquarter, createdAt) VALUES(?, ?, ?, ?, ?)',
        ['WorkingArea 지역', 'WorkingArea', 'dev', 0, _seedCreatedAtMs],
      );

      // 3) offline_accounts: tester 기본 계정(누락 시만 삽입)
      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableAccounts(userId, name, phone, pin, isSaved, createdAt) VALUES(?, ?, ?, ?, ?, ?)',
        ['tester', 'tester', '01012345678', '12345', 1, _seedCreatedAtMs],
      );

      // v4/5 메타 기본값 보정 + v5 division/area 채우기
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

      // 4) per-account 배열: tester의 areas/divisions 정렬 시드
      // 요청: tester 계정은 HQ 지역이 array 0번, WorkingArea 지역이 array 1번
      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableAccAreas(userId, name, orderIndex) VALUES(?, ?, ?)',
        ['tester', 'HQ 지역', 0],
      );
      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableAccAreas(userId, name, orderIndex) VALUES(?, ?, ?)',
        ['tester', 'WorkingArea 지역', 1],
      );

      // divisions: tester는 dev 0번
      await txn.rawInsert(
        'INSERT OR IGNORE INTO $tableAccDivs(userId, name, orderIndex) VALUES(?, ?, ?)',
        ['tester', 'dev', 0],
      );
    });
  }
}
