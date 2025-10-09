import 'package:flutter/material.dart';

import '../../../../routes.dart';
import 'offline_auth_db.dart';
import 'offline_auth_service.dart';

/// UserState 없이 SQLite만으로:
/// - 현재 세션의 offline_accounts.isWorking == 1 이면 자동으로 라우팅
/// - HQ 여부는 area 테이블의 isHeadquarter 필드로 판별
/// - isWorking != 1 이거나 세션/데이터 없으면 [child]를 그대로 보여줌
class OfflineWorkAutoRouter extends StatefulWidget {
  const OfflineWorkAutoRouter({
    super.key,
    required this.child,
    this.showSpinnerWhileChecking = true,
  });

  /// 자동 라우팅 조건을 만족하지 않을 때 보여줄 화면
  final Widget child;

  /// 체크 중 인디케이터를 잠깐 보여줄지 여부 (기본 true)
  final bool showSpinnerWhileChecking;

  @override
  State<OfflineWorkAutoRouter> createState() => _OfflineWorkAutoRouterState();
}

class _OfflineWorkAutoRouterState extends State<OfflineWorkAutoRouter> {
  bool _checking = true;
  bool _shouldShowChild = true;

  @override
  void initState() {
    super.initState();
    _checkAndMaybeRoute();
  }

  Future<void> _checkAndMaybeRoute() async {
    try {
      final session = await OfflineAuthService.instance.currentSession();
      if (!mounted) return;

      // 세션/유저 미존재 → 자동 라우팅 없이 child 노출
      if (session == null || session.userId.isEmpty) {
        setState(() {
          _checking = false;
          _shouldShowChild = true;
        });
        return;
      }

      // 1) DB에서 isWorking 읽기 (userId → 없으면 isSelected=1 폴백)
      final db = await OfflineAuthDb.instance.database;
      int workingInt = 0;

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

      if (workingInt != 1) {
        // 출근 상태가 아니면 그대로 child
        setState(() {
          _checking = false;
          _shouldShowChild = true;
        });
        return;
      }

      // 2) 세션 area가 HQ인지 판별
      final isHq = await _isHeadquarterArea(session.area);

      // 3) 다음 프레임에 라우팅 (build 완료 후 전환)
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final routeName = isHq
            ? AppRoutes.offlineTypePage
            : AppRoutes.offlineTypePage; // 프로젝트에서 사용하는 타입 페이지 라우트명

        Navigator.pushReplacementNamed(context, routeName);
      });

      // 라우팅 예정이므로 child를 보여줄 필요 없음
      if (!mounted) return;
      setState(() {
        _checking = false;
        _shouldShowChild = false;
      });
    } catch (e, st) {
      // 실패 시 child로 폴백
      debugPrint('❌ AutoRoute check failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _checking = false;
        _shouldShowChild = true;
      });
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
    // 체크 중이면 가볍게 스피너 표시(옵션)
    if (_checking && widget.showSpinnerWhileChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // 자동 라우팅 조건을 만족하지 않으면 자식 화면을 그대로 노출
    if (_shouldShowChild) {
      return widget.child;
    }

    // 라우팅 직전 짧은 공백 화면
    return const SizedBox.shrink();
  }
}
