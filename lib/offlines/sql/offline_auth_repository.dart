import 'package:sqflite/sqflite.dart';

import 'offline_auth_db.dart';
import 'offline_session_model.dart';

class OfflineAuthRepository {
  final OfflineAuthDb _dbProvider;

  OfflineAuthRepository({OfflineAuthDb? dbProvider})
      : _dbProvider = dbProvider ?? OfflineAuthDb.instance;

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

  Future<void> clearSession() async {
    final db = await _dbProvider.database;
    await db.delete(OfflineAuthDb.tableSessions); // 세션만 삭제
  }
}
