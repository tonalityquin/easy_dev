// ==============================
// File: offline_location_repository.dart
// ==============================
import 'package:sqflite/sqflite.dart';

import 'offline_auth_db.dart';
import 'offline_location_model.dart';

class OfflineLocationRepository {
  final OfflineAuthDb _dbProvider;
  OfflineLocationRepository({OfflineAuthDb? dbProvider})
      : _dbProvider = dbProvider ?? OfflineAuthDb.instance;

  Future<int> upsert(OfflineLocation loc) async {
    final db = await _dbProvider.database;
    return db.insert(
      OfflineAuthDb.tableLocations,
      loc.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<OfflineLocation?> getByKey(String locationKey) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      OfflineAuthDb.tableLocations,
      where: 'location_key = ?',
      whereArgs: [locationKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OfflineLocation.fromMap(rows.first);
  }

  Future<List<OfflineLocation>> listByArea(String area, {int limit = 200}) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      OfflineAuthDb.tableLocations,
      where: 'area = ?',
      whereArgs: [area],
      orderBy: 'CASE WHEN updated_at IS NULL THEN 1 ELSE 0 END, updated_at DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(OfflineLocation.fromMap).toList();
  }

  Future<int> deleteByKey(String locationKey) async {
    final db = await _dbProvider.database;
    return db.delete(
      OfflineAuthDb.tableLocations,
      where: 'location_key = ?',
      whereArgs: [locationKey],
    );
  }

  Future<int> clearAll() async {
    final db = await _dbProvider.database;
    return db.delete(OfflineAuthDb.tableLocations);
  }
}
