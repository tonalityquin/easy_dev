import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';

import '../../../../features/location/domain/models/location_model.dart';
import '../../../../features/payment/domain/models/bill_model.dart';
import '../../../../features/payment/domain/models/regular_bill_model.dart';
import '../../../../features/sector/domain/models/sector_model.dart';
import '../../domain/models/bill_local_snapshot.dart';
import '../../domain/models/operational_area_meta.dart';
import '../../domain/repositories/operational_local_repository.dart';
import '../local/operational_cache_database.dart';

class SqliteOperationalLocalRepository implements OperationalLocalRepository {
  SqliteOperationalLocalRepository(this._database);

  final OperationalCacheDatabase _database;

  String _requireArea(String area) {
    final normalized = area.trim();
    if (normalized.isEmpty) {
      throw StateError('현재 지역 정보가 없습니다.');
    }
    return normalized;
  }

  Future<void> _ensureMetaRow(DatabaseExecutor db, String area) async {
    await db.insert(
      'operational_area_meta',
      <String, Object?>{'area': area},
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<int> _count(
    DatabaseExecutor db,
    String table,
    String area,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $table WHERE area = ?',
      <Object?>[area],
    );
    return Sqflite.firstIntValue(rows) ?? 0;
  }

  Map<String, dynamic> _decodePayload(Object? raw, String label) {
    if (raw is! String || raw.trim().isEmpty) {
      throw FormatException('$label SQLite payload가 비어 있습니다.');
    }
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw FormatException('$label SQLite payload 형식이 올바르지 않습니다.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<List<LocationModel>> readLocations(String area) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    final rows = await db.query(
      'operational_locations',
      columns: <String>['payload_json'],
      where: 'area = ?',
      whereArgs: <Object?>[normalizedArea],
      orderBy: 'id ASC',
    );
    final result = rows
        .map((row) => LocationModel.fromCacheMap(
              _decodePayload(row['payload_json'], '주차 구역'),
            ))
        .toList(growable: false);
    debugPrint(
      '[OperationalSQLite] readLocations area=$normalizedArea count=${result.length}',
    );
    return result;
  }

  @override
  Future<void> replaceLocations({
    required String area,
    required List<LocationModel> locations,
    required int totalCapacity,
  }) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete(
        'operational_locations',
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      for (final location in locations) {
        if (location.area.trim().isNotEmpty &&
            location.area.trim() != normalizedArea) {
          throw StateError('주차 구역의 지역 값이 현재 지역과 다릅니다: ${location.id}');
        }
        await txn.insert(
          'operational_locations',
          <String, Object?>{
            'area': normalizedArea,
            'id': location.id,
            'payload_json': jsonEncode(location.toCacheMap()),
          },
        );
      }
      await _ensureMetaRow(txn, normalizedArea);
      await txn.update(
        'operational_area_meta',
        <String, Object?>{
          'locations_ready': 1,
          'location_count': locations.length,
          'total_capacity': totalCapacity,
        },
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      final stored = await _count(txn, 'operational_locations', normalizedArea);
      if (stored != locations.length) {
        throw StateError(
          '주차 구역 SQLite 저장 개수가 일치하지 않습니다: expected=${locations.length}, actual=$stored',
        );
      }
    });
    debugPrint(
      '[OperationalSQLite] replaceLocations area=$normalizedArea count=${locations.length} totalCapacity=$totalCapacity',
    );
  }

  @override
  Future<void> clearLocations(String area) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete(
        'operational_locations',
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      await _ensureMetaRow(txn, normalizedArea);
      await txn.update(
        'operational_area_meta',
        <String, Object?>{
          'locations_ready': 0,
          'location_count': 0,
          'total_capacity': 0,
        },
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      if (await _count(txn, 'operational_locations', normalizedArea) != 0) {
        throw StateError('기존 주차 구역 SQLite 데이터 삭제 검증 실패');
      }
    });
    debugPrint('[OperationalSQLite] clearLocations area=$normalizedArea');
  }

  @override
  Future<bool> hasLocationsSnapshot(String area) async {
    final meta = await readAreaMeta(area);
    return meta?.locationsReady ?? false;
  }

  @override
  Future<int> countLocations(String area) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    return _count(db, 'operational_locations', normalizedArea);
  }

  @override
  Future<BillLocalSnapshot> readBills(String area) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    final generalRows = await db.query(
      'operational_general_bills',
      columns: <String>['payload_json'],
      where: 'area = ?',
      whereArgs: <Object?>[normalizedArea],
      orderBy: 'id ASC',
    );
    final regularRows = await db.query(
      'operational_regular_bills',
      columns: <String>['payload_json'],
      where: 'area = ?',
      whereArgs: <Object?>[normalizedArea],
      orderBy: 'id ASC',
    );
    final snapshot = BillLocalSnapshot(
      generalBills: generalRows
          .map((row) => BillModel.fromCacheMap(
                _decodePayload(row['payload_json'], '일반 정산'),
              ))
          .toList(growable: false),
      regularBills: regularRows
          .map((row) => RegularBillModel.fromCacheMap(
                _decodePayload(row['payload_json'], '정기 정산'),
              ))
          .toList(growable: false),
    );
    debugPrint(
      '[OperationalSQLite] readBills area=$normalizedArea general=${snapshot.generalBills.length} regular=${snapshot.regularBills.length}',
    );
    return snapshot;
  }

  @override
  Future<void> replaceBills({
    required String area,
    required List<BillModel> generalBills,
    required List<RegularBillModel> regularBills,
  }) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete(
        'operational_general_bills',
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      await txn.delete(
        'operational_regular_bills',
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      for (final bill in generalBills) {
        if (bill.area.trim().isNotEmpty && bill.area.trim() != normalizedArea) {
          throw StateError('일반 정산의 지역 값이 현재 지역과 다릅니다: ${bill.id}');
        }
        await txn.insert(
          'operational_general_bills',
          <String, Object?>{
            'area': normalizedArea,
            'id': bill.id,
            'payload_json': jsonEncode(bill.toCacheMap()),
          },
        );
      }
      for (final bill in regularBills) {
        if (bill.area.trim().isNotEmpty && bill.area.trim() != normalizedArea) {
          throw StateError('정기 정산의 지역 값이 현재 지역과 다릅니다: ${bill.id}');
        }
        await txn.insert(
          'operational_regular_bills',
          <String, Object?>{
            'area': normalizedArea,
            'id': bill.id,
            'payload_json': jsonEncode(bill.toCacheMap()),
          },
        );
      }
      await _ensureMetaRow(txn, normalizedArea);
      await txn.update(
        'operational_area_meta',
        <String, Object?>{
          'general_bills_ready': 1,
          'regular_bills_ready': 1,
          'general_bill_count': generalBills.length,
          'regular_bill_count': regularBills.length,
        },
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      final storedGeneral =
          await _count(txn, 'operational_general_bills', normalizedArea);
      final storedRegular =
          await _count(txn, 'operational_regular_bills', normalizedArea);
      if (storedGeneral != generalBills.length ||
          storedRegular != regularBills.length) {
        throw StateError(
          '정산 SQLite 저장 개수가 일치하지 않습니다: general=$storedGeneral/${generalBills.length}, regular=$storedRegular/${regularBills.length}',
        );
      }
    });
    debugPrint(
      '[OperationalSQLite] replaceBills area=$normalizedArea general=${generalBills.length} regular=${regularBills.length}',
    );
  }

  @override
  Future<void> clearBills(String area) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete(
        'operational_general_bills',
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      await txn.delete(
        'operational_regular_bills',
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      await _ensureMetaRow(txn, normalizedArea);
      await txn.update(
        'operational_area_meta',
        <String, Object?>{
          'general_bills_ready': 0,
          'regular_bills_ready': 0,
          'general_bill_count': 0,
          'regular_bill_count': 0,
        },
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      final general =
          await _count(txn, 'operational_general_bills', normalizedArea);
      final regular =
          await _count(txn, 'operational_regular_bills', normalizedArea);
      if (general != 0 || regular != 0) {
        throw StateError('기존 정산 SQLite 데이터 삭제 검증 실패');
      }
    });
    debugPrint('[OperationalSQLite] clearBills area=$normalizedArea');
  }

  @override
  Future<bool> hasBillsSnapshot(String area) async {
    final meta = await readAreaMeta(area);
    return meta?.billsReady ?? false;
  }

  @override
  Future<int> countGeneralBills(String area) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    return _count(db, 'operational_general_bills', normalizedArea);
  }

  @override
  Future<int> countRegularBills(String area) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    return _count(db, 'operational_regular_bills', normalizedArea);
  }

  @override
  Future<List<SectorModel>> readSectors(String area) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    final rows = await db.query(
      'operational_sectors',
      columns: <String>['payload_json'],
      where: 'area = ?',
      whereArgs: <Object?>[normalizedArea],
      orderBy: 'normalized_name ASC, id ASC',
    );
    final result = rows
        .map((row) => SectorModel.fromCacheMap(
              _decodePayload(row['payload_json'], '섹터'),
            ))
        .toList(growable: false);
    debugPrint(
      '[OperationalSQLite] readSectors area=$normalizedArea count=${result.length}',
    );
    return result;
  }

  @override
  Future<void> replaceSectors({
    required String area,
    required List<SectorModel> sectors,
  }) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete(
        'operational_sectors',
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      for (final sector in sectors) {
        if (sector.area.trim() != normalizedArea) {
          throw StateError('섹터의 지역 값이 현재 지역과 다릅니다: ${sector.id}');
        }
        await txn.insert(
          'operational_sectors',
          <String, Object?>{
            'area': normalizedArea,
            'id': sector.id,
            'normalized_name': sector.normalizedName,
            'payload_json': jsonEncode(sector.toCacheMap()),
          },
        );
      }
      await _ensureMetaRow(txn, normalizedArea);
      await txn.update(
        'operational_area_meta',
        <String, Object?>{
          'sectors_ready': 1,
          'sector_count': sectors.length,
        },
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      final stored = await _count(txn, 'operational_sectors', normalizedArea);
      if (stored != sectors.length) {
        throw StateError(
          '섹터 SQLite 저장 개수가 일치하지 않습니다: expected=${sectors.length}, actual=$stored',
        );
      }
    });
    debugPrint(
      '[OperationalSQLite] replaceSectors area=$normalizedArea count=${sectors.length}',
    );
  }

  @override
  Future<void> clearSectors(String area) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    await db.transaction((txn) async {
      await txn.delete(
        'operational_sectors',
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      await _ensureMetaRow(txn, normalizedArea);
      await txn.update(
        'operational_area_meta',
        <String, Object?>{
          'sectors_ready': 0,
          'sector_count': 0,
        },
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
      if (await _count(txn, 'operational_sectors', normalizedArea) != 0) {
        throw StateError('기존 섹터 SQLite 데이터 삭제 검증 실패');
      }
    });
    debugPrint('[OperationalSQLite] clearSectors area=$normalizedArea');
  }

  @override
  Future<bool> hasSectorsSnapshot(String area) async {
    final meta = await readAreaMeta(area);
    return meta?.sectorsReady ?? false;
  }

  @override
  Future<int> countSectors(String area) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    return _count(db, 'operational_sectors', normalizedArea);
  }

  @override
  Future<OperationalAreaMeta?> readAreaMeta(String area) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    final rows = await db.query(
      'operational_area_meta',
      where: 'area = ?',
      whereArgs: <Object?>[normalizedArea],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final monthlyRaw = row['has_monthly_parking'];
    final syncedRaw = row['synced_at_iso']?.toString() ?? '';
    return OperationalAreaMeta(
      area: normalizedArea,
      locationsReady: (row['locations_ready'] as num?)?.toInt() == 1,
      generalBillsReady: (row['general_bills_ready'] as num?)?.toInt() == 1,
      regularBillsReady: (row['regular_bills_ready'] as num?)?.toInt() == 1,
      sectorsReady: (row['sectors_ready'] as num?)?.toInt() == 1,
      locationCount: (row['location_count'] as num?)?.toInt() ?? 0,
      generalBillCount: (row['general_bill_count'] as num?)?.toInt() ?? 0,
      regularBillCount: (row['regular_bill_count'] as num?)?.toInt() ?? 0,
      sectorCount: (row['sector_count'] as num?)?.toInt() ?? 0,
      totalCapacity: (row['total_capacity'] as num?)?.toInt() ?? 0,
      hasMonthlyParking: monthlyRaw == null
          ? null
          : (monthlyRaw as num).toInt() == 1,
      syncedAt: syncedRaw.trim().isEmpty ? null : DateTime.tryParse(syncedRaw),
    );
  }

  @override
  Future<void> clearOperationalMetadata(String area) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    await db.transaction((txn) async {
      await _ensureMetaRow(txn, normalizedArea);
      await txn.update(
        'operational_area_meta',
        <String, Object?>{
          'has_monthly_parking': null,
          'synced_at_iso': null,
        },
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
    });
    debugPrint('[OperationalSQLite] clearMetadata area=$normalizedArea');
  }

  @override
  Future<void> saveOperationalMetadata({
    required String area,
    required bool hasMonthlyParking,
    required String syncedAtIso,
  }) async {
    final normalizedArea = _requireArea(area);
    final normalizedSyncedAt = syncedAtIso.trim();
    if (DateTime.tryParse(normalizedSyncedAt) == null) {
      throw FormatException('운영 데이터 동기화 시각 형식이 올바르지 않습니다.');
    }
    final db = await _database.database;
    await db.transaction((txn) async {
      await _ensureMetaRow(txn, normalizedArea);
      await txn.update(
        'operational_area_meta',
        <String, Object?>{
          'has_monthly_parking': hasMonthlyParking ? 1 : 0,
          'synced_at_iso': normalizedSyncedAt,
        },
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
    });
    final stored = await readAreaMeta(normalizedArea);
    if (stored?.hasMonthlyParking != hasMonthlyParking ||
        stored?.syncedAt?.toIso8601String() != normalizedSyncedAt) {
      throw StateError('운영 데이터 SQLite 메타 정보 저장 검증 실패');
    }
    debugPrint(
      '[OperationalSQLite] saveMetadata area=$normalizedArea monthly=$hasMonthlyParking syncedAt=$normalizedSyncedAt',
    );
  }

  @override
  Future<void> updateMonthlyParking({
    required String area,
    required bool hasMonthlyParking,
  }) async {
    final normalizedArea = _requireArea(area);
    final db = await _database.database;
    await db.transaction((txn) async {
      await _ensureMetaRow(txn, normalizedArea);
      await txn.update(
        'operational_area_meta',
        <String, Object?>{
          'has_monthly_parking': hasMonthlyParking ? 1 : 0,
        },
        where: 'area = ?',
        whereArgs: <Object?>[normalizedArea],
      );
    });
    debugPrint(
      '[OperationalSQLite] updateMonthlyParking area=$normalizedArea monthly=$hasMonthlyParking',
    );
  }
}
