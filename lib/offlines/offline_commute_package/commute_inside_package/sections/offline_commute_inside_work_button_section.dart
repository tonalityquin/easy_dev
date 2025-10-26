import 'package:flutter/material.dart';

import '../../../../utils/blocking_dialog.dart';
import '../offline_commute_inside_controller.dart'; // CommuteDestination enum 사용
import '../../../../routes.dart';

// SQLite / 세션
import '../../../sql/offline_auth_db.dart';
import '../../../sql/offline_auth_service.dart';

class OfflineCommuteInsideWorkButtonSection extends StatefulWidget {
  final OfflineCommuteInsideController controller;
  final ValueChanged<bool> onLoadingChanged;

  const OfflineCommuteInsideWorkButtonSection({
    super.key,
    required this.controller,
    required this.onLoadingChanged,
  });

  @override
  State<OfflineCommuteInsideWorkButtonSection> createState() => _OfflineCommuteInsideWorkButtonSectionState();
}

class _OfflineCommuteInsideWorkButtonSectionState extends State<OfflineCommuteInsideWorkButtonSection> {
  bool _loading = true;
  bool _isWorking = false;
  bool _navigating = false;

  @override
  void initState() {
    super.initState();
    _hydrateFromDb();
  }

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  Future<void> _hydrateFromDb() async {
    try {
      final session = await OfflineAuthService.instance.currentSession();
      if (!mounted) return;

      if (session == null) {
        setState(() {
          _isWorking = false;
          _loading = false;
        });
        return;
      }

      final db = await OfflineAuthDb.instance.database;

      int workingInt = 0;
      List<Map<String, Object?>> rows = [];
      if ((session.userId).toString().isNotEmpty) {
        rows = await db.query(
          OfflineAuthDb.tableAccounts,
          columns: const ['isWorking'],
          where: 'userId = ?',
          whereArgs: [session.userId],
          limit: 1,
        );
      }

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

      if (!mounted) return;
      setState(() {
        _isWorking = workingInt == 1;
        _loading = false;
      });

      if (_isWorking && !_navigating) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _autoRouteIfWorking();
        });
      }
    } catch (e, st) {
      debugPrint('❌ hydrate 실패: $e\n$st');
      if (!mounted) return;
      setState(() {
        _isWorking = false;
        _loading = false;
      });
    }
  }

  Future<bool> _clockInPersist() async {
    final session = await OfflineAuthService.instance.currentSession();
    if (session == null) {
      debugPrint('❌ 세션 없음: isWorking 갱신 불가');
      return false;
    }

    final db = await OfflineAuthDb.instance.database;

    return await db.transaction<bool>((txn) async {
      final all = await txn.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['userId', 'phone', 'isSelected', 'isWorking'],
      );
      debugPrint(
          '👀 accounts(before)=${all.map((e) => "${e['userId']}:${e['phone']}:${e['isSelected']}/${e['isWorking']}").toList()}');

      String? targetUserId;
      final sessUid = session.userId.trim();
      final sessPhoneDigits = _digits(session.phone);

      final sessUidDigits = _digits(sessUid);

      for (final r in all) {
        final uid = (r['userId'] as String?)?.trim() ?? '';
        final phone = (r['phone'] as String?) ?? '';
        final phDigits = _digits(phone);

        if (uid == sessUid && uid.isNotEmpty) {
          targetUserId = uid;
          break;
        }
        if (phDigits.isNotEmpty && phDigits == sessUidDigits && sessUidDigits.isNotEmpty) {
          targetUserId = uid;
          break;
        }
        if (phDigits.isNotEmpty && phDigits == sessPhoneDigits && sessPhoneDigits.isNotEmpty) {
          targetUserId = uid;
          break;
        }
      }

      if (targetUserId == null) {
        final sel = await txn.query(
          OfflineAuthDb.tableAccounts,
          columns: const ['userId'],
          where: 'isSelected = 1',
          limit: 1,
        );
        if (sel.isNotEmpty) {
          targetUserId = (sel.first['userId'] as String?)?.trim();
        }
      }

      if (targetUserId == null || targetUserId.isEmpty) {
        debugPrint('❌ 매칭되는 계정 행을 찾지 못했습니다.');
        return false;
      }

      await txn.update(
        OfflineAuthDb.tableAccounts,
        {'isSelected': 0},
        where: 'isSelected = 1',
      );
      final selUpd = await txn.update(
        OfflineAuthDb.tableAccounts,
        {'isSelected': 1},
        where: 'userId = ?',
        whereArgs: [targetUserId],
      );

      // 4) isWorking = 1
      final workUpd = await txn.update(
        OfflineAuthDb.tableAccounts,
        {'isWorking': 1},
        where: 'userId = ?',
        whereArgs: [targetUserId],
      );

      final allAfter = await txn.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['userId', 'phone', 'isSelected', 'isWorking'],
      );
      debugPrint(
          '👀 accounts(after)=${allAfter.map((e) => "${e['userId']}:${e['phone']}:${e['isSelected']}/${e['isWorking']}").toList()}');
      debugPrint('✅ selectUpd=$selUpd, workUpd=$workUpd, target=$targetUserId');

      return workUpd > 0;
    });
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

    final val = rows.first['isHeadquarter'];
    if (val is int) return val == 1;
    if (val is bool) return val;
    return false;
  }

  Future<CommuteDestination> _decideDestinationFromDb() async {
    final session = await OfflineAuthService.instance.currentSession();
    if (session == null) return CommuteDestination.none;

    final isHq = await _isHeadquarterArea(session.area);
    return isHq ? CommuteDestination.headquarter : CommuteDestination.type;
  }

  Future<void> _autoRouteIfWorking() async {
    if (_navigating || !_isWorking) return;
    _navigating = true;
    try {
      final dest = await _decideDestinationFromDb();
      if (!mounted) return;

      switch (dest) {
        case CommuteDestination.headquarter:
          Navigator.pushReplacementNamed(context, AppRoutes.offlineTypePage);
          break;
        case CommuteDestination.type:
          Navigator.pushReplacementNamed(context, AppRoutes.offlineTypePage);
          break;
        case CommuteDestination.none:
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('목적지 판별에 실패했습니다. 다시 시도해 주세요.')),
          );
          _navigating = false;
          break;
      }
    } catch (e, st) {
      debugPrint('❌ autoRoute 실패: $e\n$st');
      if (!mounted) return;
      _navigating = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = _isWorking ? '출근 중' : '오프라인 출근하기';

    return ElevatedButton.icon(
      icon: const Icon(Icons.access_time),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        minimumSize: const Size.fromHeight(55),
        padding: EdgeInsets.zero,
        side: const BorderSide(color: Colors.grey, width: 1.0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      onPressed: (_loading || _isWorking || _navigating)
          ? null // 로딩/이미 출근/네비 중이면 비활성
          : () async {
              widget.onLoadingChanged(true);
              try {
                // 모달 안에서: DB 업데이트 & 목적지 결정만 수행
                final dest = await runWithBlockingDialog<CommuteDestination>(
                  context: context,
                  message: '출근 처리 중입니다...',
                  task: () async {
                    final ok = await _clockInPersist();
                    if (!ok) return CommuteDestination.none;
                    return _decideDestinationFromDb();
                  },
                );

                if (!mounted) return;

                if (dest == CommuteDestination.none) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('출근 처리에 실패했습니다.')),
                  );
                  return;
                }

                setState(() {
                  _isWorking = true;
                  _navigating = true;
                });

                switch (dest) {
                  case CommuteDestination.headquarter:
                    Navigator.pushReplacementNamed(
                      context,
                      AppRoutes.offlineTypePage,
                    );
                    break;
                  case CommuteDestination.type:
                    Navigator.pushReplacementNamed(
                      context,
                      AppRoutes.offlineTypePage,
                    );
                    break;
                  case CommuteDestination.none:
                    break;
                }
              } finally {
                if (mounted) {
                  widget.onLoadingChanged(false);
                }
              }
            },
    );
  }
}
