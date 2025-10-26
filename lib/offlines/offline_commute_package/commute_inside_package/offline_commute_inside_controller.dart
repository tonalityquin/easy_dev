import 'package:flutter/material.dart';
import '../../../routes.dart';

// SQLite / 세션 (경로는 실제 프로젝트 구조에 맞춰 조정)
import '../../sql/offline_auth_db.dart';
import '../../sql/offline_auth_service.dart';

enum CommuteDestination { none, headquarter, type }

class OfflineCommuteInsideController {
  void initialize(BuildContext context) {
    debugPrint('[OfflineCommuteInsideController] initialize');
  }

  Future<bool> _isHeadquarterArea(String areaName) async {
    if (areaName.trim().isEmpty) return false;
    final db = await OfflineAuthDb.instance.database;
    final rows = await db.query(
      OfflineAuthDb.tableArea,
      columns: const ['isHeadquarter'],
      where: 'name = ?',
      whereArgs: [areaName],
      limit: 1,
    );
    if (rows.isEmpty) return false;
    final v = rows.first['isHeadquarter'];
    if (v is int) return v == 1;
    if (v is bool) return v;
    return false;
  }

  Future<CommuteDestination> decideDestinationFromDb() async {
    final session = await OfflineAuthService.instance.currentSession();
    if (session == null) return CommuteDestination.none;

    final isHq = await _isHeadquarterArea(session.area);
    return isHq ? CommuteDestination.headquarter : CommuteDestination.type;
  }

  Future<bool> _isWorkingFromDb() async {
    final session = await OfflineAuthService.instance.currentSession();
    final db = await OfflineAuthDb.instance.database;

    int working = 0;
    if (session != null && session.userId.isNotEmpty) {
      final rows = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['isWorking'],
        where: 'userId = ?',
        whereArgs: [session.userId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        working = rows.first['isWorking'] as int? ?? 0;
      } else {
        final fb = await db.query(
          OfflineAuthDb.tableAccounts,
          columns: const ['isWorking'],
          where: 'isSelected = 1',
          limit: 1,
        );
        working = fb.isNotEmpty ? (fb.first['isWorking'] as int? ?? 0) : 0;
      }
    } else {
      final fb = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['isWorking'],
        where: 'isSelected = 1',
        limit: 1,
      );
      working = fb.isNotEmpty ? (fb.first['isWorking'] as int? ?? 0) : 0;
    }
    return working == 1;
  }

  void redirectIfWorkingDb(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final isWorking = await _isWorkingFromDb();
      if (!context.mounted || !isWorking) return;

      final dest = await decideDestinationFromDb();
      if (!context.mounted) return;

      switch (dest) {
        case CommuteDestination.headquarter:
          Navigator.pushReplacementNamed(context, AppRoutes.offlineTypePage);
          break;
        case CommuteDestination.type:
          Navigator.pushReplacementNamed(context, AppRoutes.offlineTypePage);
          break;
        case CommuteDestination.none:
          break;
      }
    });
  }
}
