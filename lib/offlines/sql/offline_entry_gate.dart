import 'package:flutter/material.dart';

import 'offline_auth_service.dart';
import 'offline_auth_db.dart';
import '../../../../routes.dart';

/// 오프라인 모드 진입 게이트:
/// - 세션이 없으면 로그인으로 이동
/// - 세션이 있으면 DB에서 isWorking 확인 후:
///   - isWorking == 1 → 세션 area의 HQ 여부로 목적지 결정(HQ/TYPE)하여 즉시 이동
///   - isWorking != 1 → 기존 offlineHome(라우트 or 빌더)로 이동
class OfflineEntryGate extends StatefulWidget {
  const OfflineEntryGate({
    super.key,
    this.offlineHomeRoute,
    this.offlineHomeBuilder,
    this.loginRoute,
    this.loginBuilder,
  }) : assert(offlineHomeRoute != null || offlineHomeBuilder != null,
  'offlineHomeRoute 또는 offlineHomeBuilder 중 하나는 필요합니다.'),
        assert(loginRoute != null || loginBuilder != null,
        'loginRoute 또는 loginBuilder 중 하나는 필요합니다.');

  final String? offlineHomeRoute;
  final WidgetBuilder? offlineHomeBuilder;

  final String? loginRoute;
  final WidgetBuilder? loginBuilder;

  @override
  State<OfflineEntryGate> createState() => _OfflineEntryGateState();
}

class _OfflineEntryGateState extends State<OfflineEntryGate> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final has = await OfflineAuthService.instance.hasSession();
    if (!mounted) return;

    if (!has) {
      // 로그인으로
      if (widget.loginRoute != null) {
        Navigator.pushReplacementNamed(context, widget.loginRoute!);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: widget.loginBuilder!),
        );
      }
      return;
    }

    // 세션이 존재 → isWorking 확인
    final session = await OfflineAuthService.instance.currentSession();
    if (!mounted) return;

    int workingInt = 0;
    if (session != null && session.userId.isNotEmpty) {
      final db = await OfflineAuthDb.instance.database;

      final rows = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['isWorking'],
        where: 'userId = ?',
        whereArgs: [session.userId],
        limit: 1,
      );

      if (rows.isEmpty) {
        final fallback = await db.query(
          OfflineAuthDb.tableAccounts,
          columns: const ['isWorking'],
          where: 'isSelected = 1',
          limit: 1,
        );
        workingInt = fallback.isNotEmpty ? (fallback.first['isWorking'] as int? ?? 0) : 0;
      } else {
        workingInt = rows.first['isWorking'] as int? ?? 0;
      }
    }

    if (workingInt == 1) {
      // 출근 중 → HQ/TYPE으로 곧장
      final isHq = await _isHeadquarterArea(session?.area ?? '');
      if (!mounted) return;

      final routeName = isHq
          ? AppRoutes.offlineTypePage
          : AppRoutes.offlineTypePage;

      Navigator.pushReplacementNamed(context, routeName);
      return;
    }

    // 출근 상태 아님 → 오프라인 홈으로
    if (widget.offlineHomeRoute != null) {
      Navigator.pushReplacementNamed(context, widget.offlineHomeRoute!);
    } else {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: widget.offlineHomeBuilder!),
      );
    }
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

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
