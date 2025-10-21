import 'package:sqflite/sqflite.dart';

import '../data/pc_db.dart';
import '../models/parking_completed_record.dart';

class ParkingCompletedRepository {
  final ParkingCompletedDb _dbProvider;
  ParkingCompletedRepository({ParkingCompletedDb? dbProvider})
      : _dbProvider = dbProvider ?? ParkingCompletedDb.instance;

  Future<int> insert(ParkingCompletedRecord record) async {
    final db = await _dbProvider.database;
    return db.insert(
      ParkingCompletedDb.table,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<ParkingCompletedRecord>> listAll({
    int limit = 500,
    String? search, // plate/area 간단 검색 지원(옵션)
  }) async {
    final db = await _dbProvider.database;
    String? where;
    List<Object?>? args;
    if (search != null && search.trim().isNotEmpty) {
      where = '${ParkingCompletedDb.colPlate} LIKE ? OR ${ParkingCompletedDb.colArea} LIKE ?';
      final q = '%${search.trim()}%';
      args = [q, q];
    }
    final rows = await db.query(
      ParkingCompletedDb.table,
      where: where,
      whereArgs: args,
      orderBy: '${ParkingCompletedDb.colCreatedAt} DESC, ${ParkingCompletedDb.colId} DESC',
      limit: limit,
    );
    return rows.map((m) => ParkingCompletedRecord.fromMap(m)).toList();
  }

  Future<int> deleteById(int id) async {
    final db = await _dbProvider.database;
    return db.delete(
      ParkingCompletedDb.table,
      where: '${ParkingCompletedDb.colId} = ?',
      whereArgs: [id],
    );
  }

  Future<int> clearAll() async {
    final db = await _dbProvider.database;
    return db.delete(ParkingCompletedDb.table);
  }
}
