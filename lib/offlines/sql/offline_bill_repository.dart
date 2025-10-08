// ==============================
// File: offline_bill_repository.dart
// ==============================
import 'package:sqflite/sqflite.dart';

import 'offline_auth_db.dart';
import 'offline_bill_model.dart';

class OfflineBillRepository {
  final OfflineAuthDb _dbProvider;
  OfflineBillRepository({OfflineAuthDb? dbProvider})
      : _dbProvider = dbProvider ?? OfflineAuthDb.instance;

  Future<int> upsert(OfflineBill bill) async {
    final db = await _dbProvider.database;
    return db.insert(
      OfflineAuthDb.tableBills,
      bill.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<OfflineBill?> getByKey(String billKey) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      OfflineAuthDb.tableBills,
      where: 'bill_key = ?',
      whereArgs: [billKey],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OfflineBill.fromMap(rows.first);
  }

  Future<OfflineBill?> getByAreaType({
    required String area,
    required String countType,
    required String type,
  }) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      OfflineAuthDb.tableBills,
      where: 'area = ? AND count_type = ? AND type = ?',
      whereArgs: [area, countType, type],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OfflineBill.fromMap(rows.first);
  }

  Future<List<OfflineBill>> listByArea(String area, {int limit = 100}) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      OfflineAuthDb.tableBills,
      where: 'area = ?',
      whereArgs: [area],
      orderBy: 'CASE WHEN updated_at IS NULL THEN 1 ELSE 0 END, updated_at DESC, created_at DESC',
      limit: limit,
    );
    return rows.map(OfflineBill.fromMap).toList();
  }

  Future<int> deleteByKey(String billKey) async {
    final db = await _dbProvider.database;
    return db.delete(
      OfflineAuthDb.tableBills,
      where: 'bill_key = ?',
      whereArgs: [billKey],
    );
  }

  Future<int> clearAll() async {
    final db = await _dbProvider.database;
    return db.delete(OfflineAuthDb.tableBills);
  }
}
