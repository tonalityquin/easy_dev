import 'offline_auth_db.dart';
import 'offline_session_model.dart';

class OfflineAuthRepository {
  final OfflineAuthDb _dbProvider;

  OfflineAuthRepository({OfflineAuthDb? dbProvider})
      : _dbProvider = dbProvider ?? OfflineAuthDb.instance;

  /// 단일 세션 정책: 기존 행 전부 제거 후 새 세션 1건 저장
  Future<void> saveSession(OfflineSession session) async {
    final db = await _dbProvider.database;
    await db.delete(OfflineAuthDb.table);
    await db.insert(OfflineAuthDb.table, session.toMap());
  }

  Future<OfflineSession?> getSession() async {
    final db = await _dbProvider.database;
    final rows = await db.query(
      OfflineAuthDb.table,
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return OfflineSession.fromMap(rows.first);
  }

  Future<void> clearSession() async {
    final db = await _dbProvider.database;
    await db.delete(OfflineAuthDb.table);
  }
}
