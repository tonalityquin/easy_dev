import 'package:flutter/material.dart';
import '../../../routes.dart';

// SQLite / 세션 (경로는 실제 프로젝트 구조에 맞춰 조정)
import '../../sql/offline_auth_db.dart';
import '../../sql/offline_auth_service.dart';

// ✅ 라우팅을 밖에서 수행하기 위한 목적지 enum (유지)
enum CommuteDestination { none, headquarter, type }

class OfflineCommuteInsideController {
  void initialize(BuildContext context) {
    // 현재는 DB 기반이라 별도 초기화 불필요
    debugPrint('[OfflineCommuteInsideController] initialize');
  }

  // HQ 여부 판별 (area 테이블)
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

  // DB에서 현재 세션 기준 목적지 결정
  Future<CommuteDestination> decideDestinationFromDb() async {
    final session = await OfflineAuthService.instance.currentSession();
    if (session == null) return CommuteDestination.none;

    final isHq = await _isHeadquarterArea(session.area);
    return isHq ? CommuteDestination.headquarter : CommuteDestination.type;
  }

  // DB에서 isWorking=1인지 확인 (userId → isSelected=1 폴백)
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

  /// ✅ 자동 경로: 현재 근무중이면 목적지 판단 후 즉시 라우팅 (UserState 불필요)
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

  // 기존 온라인 업로드 자리를 남겨둠(현재는 오프라인이므로 NO-OP)
  Future<void> uploadAttendanceSilentlyIfPossible() async {
    // 예: 세션에서 area/name 읽어 Sheets에 append 하던 로직
    final session = await OfflineAuthService.instance.currentSession();
    if (session == null) return;
    // 오프라인 모드에서는 네트워크 업로드 생략 또는 큐에 적재
  }
}
