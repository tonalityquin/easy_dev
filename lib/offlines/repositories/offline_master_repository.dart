import '../offline_auth_db.dart';

class OfflineMasterRepository {
  final OfflineAuthDb _dbProvider;
  OfflineMasterRepository({OfflineAuthDb? dbProvider})
      : _dbProvider = dbProvider ?? OfflineAuthDb.instance;

  // ───────────── 마스터 조회 ─────────────
  Future<List<Map<String, Object?>>> getDivisions() async {
    final db = await _dbProvider.database;
    return db.query(OfflineAuthDb.tableDivision, orderBy: 'name ASC');
  }

  Future<List<Map<String, Object?>>> getAreas() async {
    final db = await _dbProvider.database;
    return db.query(
      OfflineAuthDb.tableArea,
      orderBy: 'isHeadquarter DESC, name ASC',
    );
  }

  // ───────────── 계정별 배열 조회(정렬 보존) ─────────────
  Future<List<String>> getAccountAreas(String userId) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      OfflineAuthDb.tableAccAreas,
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'orderIndex ASC',
    );
    return rows.map((r) => (r['name'] ?? '') as String).where((e) => e.isNotEmpty).toList();
  }

  Future<List<String>> getAccountDivisions(String userId) async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      OfflineAuthDb.tableAccDivs,
      where: 'userId = ?',
      whereArgs: [userId],
      orderBy: 'orderIndex ASC',
    );
    return rows.map((r) => (r['name'] ?? '') as String).where((e) => e.isNotEmpty).toList();
  }

  // ───────────── tester 관리 ─────────────
  Future<Map<String, Object?>?> getTester() async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      OfflineAuthDb.tableAccounts,
      where: 'userId = ?',
      whereArgs: ['tester'],
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> setTesterSaved(bool saved) async {
    final db = await _dbProvider.database;
    await db.update(
      OfflineAuthDb.tableAccounts,
      {'isSaved': saved ? 1 : 0},
      where: 'userId = ?',
      whereArgs: ['tester'],
    );
  }

  Future<bool> isTesterSaved() async {
    final row = await getTester();
    if (row == null) return false;
    final v = row['isSaved'];
    if (v is int) return v == 1;
    if (v is num) return v.toInt() == 1;
    if (v is bool) return v;
    return false;
  }
}
