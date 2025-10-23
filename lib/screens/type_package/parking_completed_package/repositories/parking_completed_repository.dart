import 'package:sqflite/sqflite.dart';

import '../data/pc_db.dart';
import '../models/parking_completed_record.dart';

class ParkingCompletedRepository {
  final ParkingCompletedDb _dbProvider;
  ParkingCompletedRepository({ParkingCompletedDb? dbProvider})
      : _dbProvider = dbProvider ?? ParkingCompletedDb.instance;

  Future<int> insert(ParkingCompletedRecord record) async {
    final db = await _dbProvider.database;

    // UNIQUE(plate_number, area, created_at) 인덱스가 있을 때만 의미 있음.
    // 중복이면 0 반환(삽입 안 됨)
    return db.insert(
      ParkingCompletedDb.table,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<ParkingCompletedRecord>> listAll({
    int limit = 500,
    String? search, // 번호판/구역 간단 검색
  }) async {
    final db = await _dbProvider.database;

    String? where;
    List<Object?>? args;

    if (search != null && search.trim().isNotEmpty) {
      // 대소문자 무시 검색
      where =
      '${ParkingCompletedDb.colPlate} LIKE ? COLLATE NOCASE '
          'OR ${ParkingCompletedDb.colArea} LIKE ? COLLATE NOCASE';
      final q = '%${search.trim()}%';
      args = [q, q];
    }

    // ✅ 오래된 순: created_at ASC (안정적 정렬을 위해 id ASC를 보조 tie-breaker로 사용하지만 UI/로직에서는 id를 참조하지 않음)
    final rows = await db.query(
      ParkingCompletedDb.table,
      where: where,
      whereArgs: args,
      orderBy:
      '${ParkingCompletedDb.colCreatedAt} ASC, ${ParkingCompletedDb.colId} ASC',
      limit: limit,
    );

    return rows.map((m) => ParkingCompletedRecord.fromMap(m)).toList();
  }

  /// 테이블 전체 비우기 (id는 더 이상 사용하지 않으므로 시퀀스 초기화 불필요)
  Future<int> clearAll() async {
    final db = await _dbProvider.database;
    return db.delete(ParkingCompletedDb.table);
  }

  // (선택) 여전히 필요하면 시퀀스 초기화까지 포함
  Future<void> clearAllAndResetIds() async {
    final db = await _dbProvider.database;
    await db.transaction((txn) async {
      await txn.delete(ParkingCompletedDb.table);
      await txn.execute(
        'DELETE FROM sqlite_sequence WHERE name = ?',
        [ParkingCompletedDb.table],
      );
    });
  }
}
