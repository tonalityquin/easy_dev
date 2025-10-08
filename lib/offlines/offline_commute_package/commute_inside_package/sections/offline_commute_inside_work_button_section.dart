import 'package:flutter/material.dart';

import '../../../../utils/blocking_dialog.dart';
import '../offline_commute_inside_controller.dart'; // CommuteDestination enum 사용
import '../../../../routes.dart';

// SQLite / 세션
import '../../../sql/offline_auth_db.dart';
import '../../../sql/offline_auth_service.dart';

/// UserState 없이, SQLite만으로 동작
/// - 마운트 시 DB 하이드레이트하여 isWorking==1이면 즉시 자동 라우팅(HQ/TYPE)
/// - 버튼 클릭 시 isWorking=1 저장 + 라우팅
/// - 중복 네비게이션 방지
class OfflineCommuteInsideWorkButtonSection extends StatefulWidget {
  final OfflineCommuteInsideController controller; // 시그니처 유지(내부 미사용)
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
  bool _navigating = false; // 중복 네비게이션 방지

  @override
  void initState() {
    super.initState();
    _hydrateFromDb();
  }

  String _digits(String s) => s.replaceAll(RegExp(r'[^0-9]'), '');

  /// DB에서 현재 계정의 isWorking을 읽어 초기 상태 구성
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

      // userId → 폴백 isSelected=1
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

      // ✅ 이미 출근 중이면 즉시 자동 라우팅
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

  /// (핵심) 세션 userId 또는 phone(숫자만 비교)으로 계정 행을 찾아 선택/출근 상태 저장
  /// - 1) 전체 계정 조회 후 매칭(userId == session.userId || digits(phone) == digits(session.userId) || digits(phone) == digits(session.phone))
  /// - 2) 못 찾으면 isSelected=1 행 사용
  /// - 3) 선택한 행에 isSelected=1, isWorking=1 저장
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

      // 1) 매칭할 후보 찾기
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

      // 2) 후보 없으면 isSelected=1 행 사용
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

      // 3) 선택 계정 마킹: 모두 0 → target 1
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

  /// area 테이블로 HQ 여부 확인
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

  /// 세션의 area로 이동 목적지 결정 (HQ ↔ TYPE)
  Future<CommuteDestination> _decideDestinationFromDb() async {
    final session = await OfflineAuthService.instance.currentSession();
    if (session == null) return CommuteDestination.none;

    final isHq = await _isHeadquarterArea(session.area);
    return isHq ? CommuteDestination.headquarter : CommuteDestination.type;
  }

  /// 이미 출근 중이면 자동 라우팅
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
          // 목적지 판별 실패 시 버튼은 '출근 중' 상태로 남지만, 필요하면 안내
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('목적지 판별에 실패했습니다. 다시 시도해 주세요.')),
          );
          // 실패 시 다시 네비게이션 허용
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
                    final ok = await _clockInPersist(); // 1) 매칭/선택 + isWorking=1 저장
                    if (!ok) return CommuteDestination.none; // 저장 실패면 라우팅 중단
                    return _decideDestinationFromDb(); // 2) 목적지 결정
                  },
                );

                if (!mounted) return;

                if (dest == CommuteDestination.none) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('출근 처리에 실패했습니다.')),
                  );
                  return;
                }

                // 모달 닫힌 뒤: 라우팅 & 로컬 버튼 상태 갱신
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
                    // 위에서 처리됨
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
