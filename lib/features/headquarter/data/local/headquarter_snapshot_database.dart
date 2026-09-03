import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../../../app/models/capability.dart';
import '../../domain/models/headquarter_download_snapshot.dart';

class HeadquarterSnapshotDatabase {
  HeadquarterSnapshotDatabase._();

  static final HeadquarterSnapshotDatabase instance =
      HeadquarterSnapshotDatabase._();

  static const String databaseName = 'headquarter_snapshot.db';
  static const int databaseVersion = 2;

  Database? _database;

  Future<Database> get database async {
    final current = _database;
    if (current != null && current.isOpen) return current;
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, databaseName);
    _database = await openDatabase(
      path,
      version: databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, _) => _ensureSchema(db),
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await _migrateToVersion2(db);
        }
        await _ensureSchema(db);
      },
      onOpen: _ensureSchema,
    );
    return _database!;
  }

  Future<void> _migrateToVersion2(Database db) async {
    await db.execute('DROP TABLE IF EXISTS account_capacity');
    final metaExists = await _tableExists(db, 'snapshot_meta');
    if (!metaExists) return;
    await db.execute('''
CREATE TABLE IF NOT EXISTS snapshot_meta_v2 (
  division TEXT PRIMARY KEY,
  downloaded_at_iso TEXT NOT NULL,
  area_count INTEGER NOT NULL,
  schema_version INTEGER NOT NULL
)
''');
    await db.execute('''
INSERT OR REPLACE INTO snapshot_meta_v2 (
  division,
  downloaded_at_iso,
  area_count,
  schema_version
)
SELECT
  division,
  downloaded_at_iso,
  area_count,
  2
FROM snapshot_meta
''');
    await db.execute('DROP TABLE snapshot_meta');
    await db.execute('ALTER TABLE snapshot_meta_v2 RENAME TO snapshot_meta');
  }

  Future<bool> _tableExists(DatabaseExecutor db, String tableName) async {
    final rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' AND name = ? LIMIT 1",
      <Object?>[tableName],
    );
    return rows.isNotEmpty;
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS snapshot_meta (
  division TEXT PRIMARY KEY,
  downloaded_at_iso TEXT NOT NULL,
  area_count INTEGER NOT NULL,
  schema_version INTEGER NOT NULL
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS areas (
  division TEXT NOT NULL,
  area_name TEXT NOT NULL,
  email TEXT NOT NULL DEFAULT '',
  invite TEXT NOT NULL DEFAULT '',
  communication TEXT NOT NULL DEFAULT '',
  is_headquarter INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (division, area_name)
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS area_modes (
  division TEXT NOT NULL,
  area_name TEXT NOT NULL,
  mode TEXT NOT NULL,
  PRIMARY KEY (division, area_name, mode),
  FOREIGN KEY (division, area_name)
    REFERENCES areas(division, area_name)
    ON DELETE CASCADE
)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS area_capabilities (
  division TEXT NOT NULL,
  area_name TEXT NOT NULL,
  capability TEXT NOT NULL,
  PRIMARY KEY (division, area_name, capability),
  FOREIGN KEY (division, area_name)
    REFERENCES areas(division, area_name)
    ON DELETE CASCADE
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_area_modes_division_mode ON area_modes(division, mode)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_area_capabilities_division_capability ON area_capabilities(division, capability)',
    );
  }

  Future<void> replaceSnapshot(HeadquarterDownloadSnapshot snapshot) async {
    final division = snapshot.division.trim();
    if (division.isEmpty) {
      throw ArgumentError('division is empty');
    }
    if (snapshot.downloadedAtIso.trim().isEmpty) {
      throw ArgumentError('downloadedAtIso is empty');
    }

    final areaNames = <String>{};
    var expectedModeCount = 0;
    var expectedCapabilityCount = 0;
    for (final area in snapshot.areas) {
      final areaName = area.name.trim();
      if (areaName.isEmpty) {
        throw StateError('SQLite Snapshot contains empty area name');
      }
      if (!areaNames.add(areaName)) {
        throw StateError('SQLite Snapshot contains duplicated area: $areaName');
      }
      expectedModeCount += area.modes
          .map((value) => value.trim().toLowerCase())
          .where((value) => value.isNotEmpty)
          .toSet()
          .length;
      expectedCapabilityCount += area.capabilities.length;
    }

    final expectedAreaCount = snapshot.areas.length;
    final downloadedAtIso = snapshot.downloadedAtIso.trim();
    final db = await database;

    await db.transaction((txn) async {
      await txn.delete(
        'area_modes',
        where: 'division = ?',
        whereArgs: <Object?>[division],
      );
      await txn.delete(
        'area_capabilities',
        where: 'division = ?',
        whereArgs: <Object?>[division],
      );
      await txn.delete(
        'areas',
        where: 'division = ?',
        whereArgs: <Object?>[division],
      );
      await txn.delete(
        'snapshot_meta',
        where: 'division = ?',
        whereArgs: <Object?>[division],
      );

      final remainingAreaCount = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM areas WHERE division = ?',
              <Object?>[division],
            ),
          ) ??
          0;
      final remainingModeCount = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM area_modes WHERE division = ?',
              <Object?>[division],
            ),
          ) ??
          0;
      final remainingCapabilityCount = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM area_capabilities WHERE division = ?',
              <Object?>[division],
            ),
          ) ??
          0;
      final remainingMetaCount = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM snapshot_meta WHERE division = ?',
              <Object?>[division],
            ),
          ) ??
          0;

      if (remainingAreaCount != 0 ||
          remainingModeCount != 0 ||
          remainingCapabilityCount != 0 ||
          remainingMetaCount != 0) {
        throw StateError(
          'SQLite Snapshot delete verification failed: areas=$remainingAreaCount modes=$remainingModeCount capabilities=$remainingCapabilityCount meta=$remainingMetaCount',
        );
      }

      for (final area in snapshot.areas) {
        final areaName = area.name.trim();
        await txn.insert(
          'areas',
          <String, Object?>{
            'division': division,
            'area_name': areaName,
            'email': area.email.trim(),
            'invite': area.invite.trim(),
            'communication': area.communication.trim(),
            'is_headquarter': area.isHeadquarter ? 1 : 0,
          },
          conflictAlgorithm: ConflictAlgorithm.abort,
        );

        final modes = area.modes
            .map((value) => value.trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
        for (final mode in modes) {
          await txn.insert(
            'area_modes',
            <String, Object?>{
              'division': division,
              'area_name': areaName,
              'mode': mode,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }

        final capabilities = area.capabilities.toList(growable: false)
          ..sort((a, b) => a.key.compareTo(b.key));
        for (final capability in capabilities) {
          await txn.insert(
            'area_capabilities',
            <String, Object?>{
              'division': division,
              'area_name': areaName,
              'capability': capability.key,
            },
            conflictAlgorithm: ConflictAlgorithm.abort,
          );
        }
      }

      await txn.insert(
        'snapshot_meta',
        <String, Object?>{
          'division': division,
          'downloaded_at_iso': downloadedAtIso,
          'area_count': expectedAreaCount,
          'schema_version': databaseVersion,
        },
        conflictAlgorithm: ConflictAlgorithm.abort,
      );

      final storedAreaCount = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM areas WHERE division = ?',
              <Object?>[division],
            ),
          ) ??
          0;
      final storedModeCount = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM area_modes WHERE division = ?',
              <Object?>[division],
            ),
          ) ??
          0;
      final storedCapabilityCount = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM area_capabilities WHERE division = ?',
              <Object?>[division],
            ),
          ) ??
          0;
      final metaRows = await txn.query(
        'snapshot_meta',
        where: 'division = ?',
        whereArgs: <Object?>[division],
        limit: 1,
      );

      if (storedAreaCount != expectedAreaCount) {
        throw StateError(
          'SQLite Snapshot area verification failed: expected=$expectedAreaCount actual=$storedAreaCount',
        );
      }
      if (storedModeCount != expectedModeCount) {
        throw StateError(
          'SQLite Snapshot mode verification failed: expected=$expectedModeCount actual=$storedModeCount',
        );
      }
      if (storedCapabilityCount != expectedCapabilityCount) {
        throw StateError(
          'SQLite Snapshot capability verification failed: expected=$expectedCapabilityCount actual=$storedCapabilityCount',
        );
      }
      if (metaRows.length != 1) {
        throw StateError('SQLite Snapshot meta verification failed');
      }

      final meta = metaRows.single;
      final storedDownloadedAt =
          (meta['downloaded_at_iso'] ?? '').toString().trim();
      final storedMetaAreaCount = _intValue(meta['area_count']);
      final storedSchemaVersion = _intValue(meta['schema_version']);
      if (storedDownloadedAt != downloadedAtIso ||
          storedMetaAreaCount != expectedAreaCount ||
          storedSchemaVersion != databaseVersion) {
        throw StateError(
          'SQLite Snapshot meta value verification failed: downloadedAt=$storedDownloadedAt areaCount=$storedMetaAreaCount schemaVersion=$storedSchemaVersion',
        );
      }
    });
  }

  Future<HeadquarterDownloadSnapshot?> readSnapshot(String division) async {
    final normalized = division.trim();
    if (normalized.isEmpty) return null;
    final db = await database;

    final metaRows = await db.query(
      'snapshot_meta',
      where: 'division = ?',
      whereArgs: <Object?>[normalized],
      limit: 1,
    );
    if (metaRows.isEmpty) return null;

    final areaRows = await db.query(
      'areas',
      where: 'division = ?',
      whereArgs: <Object?>[normalized],
      orderBy: 'area_name COLLATE NOCASE ASC',
    );
    final modeRows = await db.query(
      'area_modes',
      where: 'division = ?',
      whereArgs: <Object?>[normalized],
    );
    final capabilityRows = await db.query(
      'area_capabilities',
      where: 'division = ?',
      whereArgs: <Object?>[normalized],
    );

    final modesByArea = <String, Set<String>>{};
    for (final row in modeRows) {
      final areaName = (row['area_name'] ?? '').toString().trim();
      final mode = (row['mode'] ?? '').toString().trim().toLowerCase();
      if (areaName.isEmpty || mode.isEmpty) continue;
      modesByArea.putIfAbsent(areaName, () => <String>{}).add(mode);
    }

    final capabilitiesByArea = <String, CapSet>{};
    for (final row in capabilityRows) {
      final areaName = (row['area_name'] ?? '').toString().trim();
      final capabilityKey = (row['capability'] ?? '').toString().trim();
      if (areaName.isEmpty || capabilityKey.isEmpty) continue;
      final parsed = Cap.fromDynamic(<String>[capabilityKey]);
      if (parsed.isEmpty) continue;
      capabilitiesByArea
          .putIfAbsent(areaName, () => <Capability>{})
          .addAll(parsed);
    }

    final areas = areaRows.map((row) {
      final areaName = (row['area_name'] ?? '').toString().trim();
      return HeadquarterSnapshotArea(
        division: normalized,
        name: areaName,
        email: (row['email'] ?? '').toString().trim(),
        invite: (row['invite'] ?? '').toString().trim(),
        communication: (row['communication'] ?? '').toString().trim(),
        modes: Set<String>.unmodifiable(
          modesByArea[areaName] ?? const <String>{},
        ),
        capabilities: Set<Capability>.unmodifiable(
          capabilitiesByArea[areaName] ?? const <Capability>{},
        ),
        isHeadquarter: _intValue(row['is_headquarter']) == 1,
      );
    }).toList(growable: false);

    return HeadquarterDownloadSnapshot(
      division: normalized,
      downloadedAtIso:
          (metaRows.first['downloaded_at_iso'] ?? '').toString().trim(),
      areas: List<HeadquarterSnapshotArea>.unmodifiable(areas),
    );
  }

  Future<HeadquarterSnapshotArea?> readArea({
    required String division,
    required String area,
  }) async {
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    if (normalizedDivision.isEmpty || normalizedArea.isEmpty) return null;
    final snapshot = await readSnapshot(normalizedDivision);
    if (snapshot == null) return null;
    for (final item in snapshot.areas) {
      if (item.name.trim() == normalizedArea) return item;
    }
    return null;
  }

  Future<HeadquarterSnapshotArea> updateAreaEmail({
    required String division,
    required String area,
    required String email,
  }) async {
    final normalizedDivision = division.trim();
    final normalizedArea = area.trim();
    final normalizedEmail = email.trim();
    if (normalizedDivision.isEmpty) {
      throw ArgumentError('division is empty');
    }
    if (normalizedArea.isEmpty) {
      throw ArgumentError('area is empty');
    }
    if (normalizedEmail.isEmpty) {
      throw ArgumentError('email is empty');
    }

    final db = await database;
    await db.transaction((txn) async {
      final existingRows = await txn.query(
        'areas',
        columns: const <String>['email'],
        where: 'division = ? AND area_name = ?',
        whereArgs: <Object?>[normalizedDivision, normalizedArea],
        limit: 2,
      );
      if (existingRows.length != 1) {
        throw StateError(
          'SQLite area email target verification failed: division=$normalizedDivision area=$normalizedArea count=${existingRows.length}',
        );
      }

      final affected = await txn.update(
        'areas',
        <String, Object?>{'email': normalizedEmail},
        where: 'division = ? AND area_name = ?',
        whereArgs: <Object?>[normalizedDivision, normalizedArea],
        conflictAlgorithm: ConflictAlgorithm.abort,
      );
      if (affected != 1) {
        throw StateError(
          'SQLite area email update failed: division=$normalizedDivision area=$normalizedArea affected=$affected',
        );
      }

      final verifyRows = await txn.query(
        'areas',
        columns: const <String>['email'],
        where: 'division = ? AND area_name = ?',
        whereArgs: <Object?>[normalizedDivision, normalizedArea],
        limit: 2,
      );
      if (verifyRows.length != 1) {
        throw StateError(
          'SQLite area email read-back failed: division=$normalizedDivision area=$normalizedArea count=${verifyRows.length}',
        );
      }
      final storedEmail = (verifyRows.single['email'] ?? '').toString().trim();
      if (storedEmail != normalizedEmail) {
        throw StateError(
          'SQLite area email value verification failed: expected=$normalizedEmail actual=$storedEmail',
        );
      }
    });

    final updated = await readArea(
      division: normalizedDivision,
      area: normalizedArea,
    );
    if (updated == null || updated.email.trim() != normalizedEmail) {
      throw StateError(
        'SQLite area email post-transaction verification failed: division=$normalizedDivision area=$normalizedArea',
      );
    }
    return updated;
  }

  Future<HeadquarterSnapshotDiagnostics?> readDiagnostics(String division) async {
    final snapshot = await readSnapshot(division);
    if (snapshot == null) return null;
    return HeadquarterSnapshotDiagnostics(
      databaseVersion: databaseVersion,
      division: snapshot.division,
      downloadedAtIso: snapshot.downloadedAtIso,
      areaCount: snapshot.areas.length,
      singleCount: snapshot.supportCount('single'),
      doubleCount: snapshot.supportCount('double'),
      tripleCount: snapshot.supportCount('triple'),
      minorCount: snapshot.supportCount('minor'),
      tabletCount: snapshot.capabilityCount(Capability.tablet),
    );
  }

  int _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
