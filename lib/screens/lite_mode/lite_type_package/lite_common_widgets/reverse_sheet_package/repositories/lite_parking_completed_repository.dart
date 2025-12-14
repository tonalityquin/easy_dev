import 'package:sqflite/sqflite.dart';

import '../data/lite_pc_db.dart';
import '../models/lite_parking_completed_record.dart';

class ParkingCompletedRepository {
  final ParkingCompletedDb _dbProvider;
  ParkingCompletedRepository({ParkingCompletedDb? dbProvider})
      : _dbProvider = dbProvider ?? ParkingCompletedDb.instance;

  Future<int> insert(ParkingCompletedRecord record) async {
    final db = await _dbProvider.database;

    // UNIQUE(plate_number, location, created_at) 인덱스가 있을 때만 의미 있음.
    // 중복이면 0 반환(삽입 안 됨)
    return db.insert(
      ParkingCompletedDb.table,
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
  }

  Future<List<ParkingCompletedRecord>> listAll({
    int limit = 500,
    String? search, // 번호판 / location 간단 검색
  }) async {
    final db = await _dbProvider.database;

    String? where;
    List<Object?>? args;

    if (search != null && search.trim().isNotEmpty) {
      // 대소문자 무시 검색
      where =
      '${ParkingCompletedDb.colPlate} LIKE ? COLLATE NOCASE '
          'OR ${ParkingCompletedDb.colLocation} LIKE ? COLLATE NOCASE';
      final q = '%${search.trim()}%';
      args = [q, q];
    }

    // 기본 정렬: 오래된 순 (ASC)
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

  /// 테이블 전체 비우기
  Future<int> clearAll() async {
    final db = await _dbProvider.database;
    return db.delete(ParkingCompletedDb.table);
  }

  /// 테이블 전체 비우기 + AUTOINCREMENT 시퀀스 초기화
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

  /// ✅ 가장 최근(가장 늦은 created_at)의 미출차 레코드를 '출차 완료'로 표시
  Future<void> markLatestDepartureCompleted({
    required String plateNumber,
    required String location,
  }) async {
    final db = await _dbProvider.database;

    await db.transaction((txn) async {
      // 1) 미출차 레코드 중 가장 최근 것 1개 찾기
      final rows = await txn.query(
        ParkingCompletedDb.table,
        columns: [ParkingCompletedDb.colId],
        where:
        '${ParkingCompletedDb.colPlate} = ? '
            'AND ${ParkingCompletedDb.colLocation} = ? '
            'AND ${ParkingCompletedDb.colIsDepartureCompleted} = 0',
        whereArgs: [plateNumber, location],
        orderBy:
        '${ParkingCompletedDb.colCreatedAt} DESC, ${ParkingCompletedDb.colId} DESC',
        limit: 1,
      );

      if (rows.isEmpty) {
        // 이미 모두 출차 완료 상태이거나 기록 없음
        return;
      }

      final id = rows.first[ParkingCompletedDb.colId] as int;

      // 2) 해당 id 하나만 출차 완료로 업데이트
      await txn.update(
        ParkingCompletedDb.table,
        {ParkingCompletedDb.colIsDepartureCompleted: 1},
        where: '${ParkingCompletedDb.colId} = ?',
        whereArgs: [id],
      );
    });
  }
}
