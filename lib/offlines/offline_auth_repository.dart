import 'package:sqflite/sqflite.dart';

import 'offline_auth_db.dart';
import 'offline_session_model.dart';

class OfflineAuthRepository {
  final OfflineAuthDb _dbProvider;

  OfflineAuthRepository({OfflineAuthDb? dbProvider})
      : _dbProvider = dbProvider ?? OfflineAuthDb.instance;

  /// 단일 세션 정책: 기존 행 전부 제거 후 새 세션 1건 저장
  Future<void> saveSession(OfflineSession session) async {
    final db = await _dbProvider.database;
    await db.delete(OfflineAuthDb.tableSessions); // 세션만 정리
    await db.insert(OfflineAuthDb.tableSessions, session.toMap());
  }

  Future<OfflineSession?> getSession() async {
    try {
      final db = await _dbProvider.database;
      final rows = await db.query(
        OfflineAuthDb.tableSessions,
        orderBy: 'created_at DESC',
        limit: 1,
      );
      if (rows.isEmpty) return null;
      return OfflineSession.fromMap(rows.first);
    } on DatabaseException catch (e) {
      // 🔁 dev 중 자주 만나는 닫힌 핸들 보호
      if (e.toString().contains('database_closed')) {
        await _dbProvider.reopenIfNeeded();
        final db = await _dbProvider.database;
        final rows = await db.query(
          OfflineAuthDb.tableSessions,
          orderBy: 'created_at DESC',
          limit: 1,
        );
        if (rows.isEmpty) return null;
        return OfflineSession.fromMap(rows.first);
      }
      rethrow;
    }
  }

  /// 로그아웃 시 기본 마스터/테스터 데이터는 건드리지 않음
  Future<void> clearSession() async {
    final db = await _dbProvider.database;
    await db.delete(OfflineAuthDb.tableSessions); // 세션만 삭제
  }
}
