// ==============================
// File: offline_plate_repository.dart
// ==============================
import 'package:sqflite/sqflite.dart';

import 'offline_auth_db.dart';
import 'offline_plate_model.dart';

class OfflinePlateRepository {
  final OfflineAuthDb _dbProvider;
  OfflinePlateRepository({OfflineAuthDb? dbProvider})
      : _dbProvider = dbProvider ?? OfflineAuthDb.instance;

  Future<int> upsert(OfflinePlate plate) async {
    final db = await _dbProvider.database;
    final values = plate.toMap();
    return db.insert(
      OfflineAuthDb.tablePlates,
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<OfflinePlate?> getByPlate({required String plateNumber, required String area}) async {
    final db = await _dbProvider.database;
    final key = OfflinePlate.makePlateKey(plateNumber: plateNumber, area: area);
    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      where: 'plate_key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OfflinePlate.fromMap(rows.first);
  }

  Future<List<OfflinePlate>> listRecent({int limit = 100}) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      orderBy: 'CASE WHEN updated_at IS NULL THEN 1 ELSE 0 END, updated_at DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(OfflinePlate.fromMap).toList();
  }

  Future<int> deleteByPlate({required String plateNumber, required String area}) async {
    final db = await _dbProvider.database;
    final key = OfflinePlate.makePlateKey(plateNumber: plateNumber, area: area);
    return db.delete(
      OfflineAuthDb.tablePlates,
      where: 'plate_key = ?',
      whereArgs: [key],
    );
  }

  Future<int> clearAll() async {
    final db = await _dbProvider.database;
    return db.delete(OfflineAuthDb.tablePlates);
  }
}
