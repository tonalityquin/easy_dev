import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

// 라우트 / SQLite
import '../../routes.dart';
import '../sql/offline_auth_db.dart';          // ← 경로 조정
import '../sql/offline_auth_service.dart';     // ← 경로 조정
import '../sql/offline_session_model.dart';    // ← 경로 조정

// ── Deep Blue Palette
const base = Color(0xFF0D47A1); // primary
const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
const light = Color(0xFF5472D3); // 톤 변형/보더
const fg = Color(0xFFFFFFFF);    // onPrimary

/// Firestore/상태 전혀 사용하지 않는, SQLite 전용 지역 선택 바텀시트
/// - PlateState / UserState 의존 제거
/// - 선택 후 offline_sessions 및 offline_accounts 를 갱신
Future<void> offlineAreaPickerBottomSheet({
  required BuildContext context,
}) {
  // pop 이후 push 시 안전하게 쓰기 위한 루트 컨텍스트
  final rootContext = context;

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (modalCtx) {
      return FractionallySizedBox(
        heightFactor: 1, // 화면 100%
        child: DraggableScrollableSheet(
          initialChildSize: 1.0,
          minChildSize: 0.3,
          maxChildSize: 1.0,
          builder: (sheetCtx, scrollController) {
            return SafeArea(
              top: false,
              child: _AreaPickerContent(
                rootContext: rootContext,
              ),
            );
          },
        ),
      );
    },
  );
}

class _AreaPickerContent extends StatefulWidget {
  final BuildContext rootContext;

  const _AreaPickerContent({
    required this.rootContext,
  });

  @override
  State<_AreaPickerContent> createState() => _AreaPickerContentState();
}

class _AreaPickerContentState extends State<_AreaPickerContent> {
  late FixedExtentScrollController _scrollCtrl;

  List<String> _areas = const [];
  String _tempSelected = '';
  int _initialIndex = 0;
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _scrollCtrl = FixedExtentScrollController(initialItem: _initialIndex);
    _initLoad();
  }

  @override
  void dispose() {
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _initLoad() async {
    try {
      final areas = await _loadAreasForCurrentUser();
      if (areas.isEmpty) {
        setState(() {
          _areas = const [];
          _tempSelected = '';
          _initialIndex = 0;
          _loading = false;
        });
        return;
      }

      // 세션의 현재 지역을 읽어 초기 선택 위치를 맞춤
      final session = await OfflineAuthService.instance.currentSession();
      final cur = (session?.area ?? '').trim();
      final idx = (cur.isNotEmpty && areas.contains(cur)) ? areas.indexOf(cur) : 0;

      setState(() {
        _areas = areas;
        _tempSelected = (idx >= 0 && idx < areas.length) ? areas[idx] : areas.first;
        _initialIndex = idx;
        _loading = false;
      });

      // 컨트롤러 위치 동기화
      if (mounted) {
        _scrollCtrl.jumpToItem(_initialIndex);
      }
    } catch (e) {
      setState(() {
        _error = '지역 목록을 불러오지 못했습니다: $e';
        _loading = false;
      });
    }
  }

  /// 현재 세션 사용자 기준으로 지역 목록을 가져온다.
  /// - 우선: offline_account_areas(userId)의 orderIndex 순
  /// - 없으면: area 테이블 전체를 이름순
  Future<List<String>> _loadAreasForCurrentUser() async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();
    final userId = session?.userId;

    if (userId != null && userId.isNotEmpty) {
      final rows = await db.rawQuery('''
        SELECT a.name
        FROM ${OfflineAuthDb.tableArea} a
        JOIN ${OfflineAuthDb.tableAccAreas} aa
          ON aa.name = a.name
        WHERE aa.userId = ?
        ORDER BY aa.orderIndex ASC
      ''', [userId]);

      final names = rows
          .map((e) => (e['name'] as String?)?.trim() ?? '')
          .where((s) => s.isNotEmpty)
          .toList();

      if (names.isNotEmpty) return names;
    }

    final rows2 = await db.query(
      OfflineAuthDb.tableArea,
      columns: ['name'],
      orderBy: 'name ASC',
    );

    return rows2
        .map((e) => (e['name'] as String?)?.trim() ?? '')
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// 선택된 지역의 HQ 여부를 area 테이블에서 확인
  Future<bool> _isHeadquarter(String areaName) async {
    final db = await OfflineAuthDb.instance.database;
    final rows = await db.query(
      OfflineAuthDb.tableArea,
      columns: ['isHeadquarter'],
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

  /// 세션(offline_sessions)과 계정(offline_accounts)의 지역을 함께 갱신
  /// - 우선 세션 userId 행을 타깃으로, 없으면 isSelected=1 행 사용
  /// - 세션 테이블은 단일 세션 정책: 전부 삭제 후 1건 삽입
  Future<bool> _persistSelectedAreaEverywhere(String selected) async {
    final db = await OfflineAuthDb.instance.database;
    final cur = await OfflineAuthService.instance.currentSession();

    return await db.transaction<bool>((txn) async {
      String? targetUserId = cur?.userId;

      if (targetUserId == null || targetUserId.isEmpty) {
        final sel = await txn.query(
          OfflineAuthDb.tableAccounts,
          columns: const ['userId'],
          where: 'isSelected = 1',
          limit: 1,
        );
        if (sel.isNotEmpty) {
          targetUserId = (sel.first['userId'] as String?)?.trim();
        }
      } else {
        // 세션 userId가 실제로 존재하는지 체크 (없으면 isSelected=1로 폴백)
        final me = await txn.query(
          OfflineAuthDb.tableAccounts,
          columns: const ['userId'],
          where: 'userId = ?',
          whereArgs: [targetUserId],
          limit: 1,
        );
        if (me.isEmpty) {
          final sel = await txn.query(
            OfflineAuthDb.tableAccounts,
            columns: const ['userId'],
            where: 'isSelected = 1',
            limit: 1,
          );
          if (sel.isNotEmpty) {
            targetUserId = (sel.first['userId'] as String?)?.trim();
          } else {
            targetUserId = null;
          }
        }
      }

      if (targetUserId == null || targetUserId.isEmpty) {
        debugPrint('❌ 대상 계정이 없어 지역 저장 불가');
        return false;
      }

      // 1) offline_accounts: 대표/현재 지역 갱신
      final accUpd = await txn.update(
        OfflineAuthDb.tableAccounts,
        {
          'currentArea': selected,
          'selectedArea': selected,
          'area': selected, // v5의 대표지역 컬럼까지 동기화(선택)
        },
        where: 'userId = ?',
        whereArgs: [targetUserId],
      );

      // 2) offline_sessions: 단일 세션 재기록
      //    - cur가 있으면 기존 정보 유지 + area만 교체
      final updatedSession = OfflineSession(
        userId: cur?.userId ?? targetUserId,
        name: cur?.name ?? '',
        position: cur?.position ?? '',
        phone: cur?.phone ?? '',
        area: selected,
        createdAt: DateTime.now(),
      );
      await txn.delete(OfflineAuthDb.tableSessions);
      await txn.insert(OfflineAuthDb.tableSessions, updatedSession.toMap());

      return accUpd > 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return _shell(
        child: const Expanded(
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_error.isNotEmpty) {
      return _shell(
        child: Expanded(
          child: Center(
            child: Text(
              _error,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ),
      );
    }

    if (_areas.isEmpty) {
      return _shell(
        child: const Expanded(
          child: Center(child: Text('선택 가능한 지역이 없습니다.')),
        ),
      );
    }

    return _shell(
      child: Expanded(
        child: CupertinoPicker(
          scrollController: _scrollCtrl,
          itemExtent: 48,
          magnification: 1.05,
          useMagnifier: true,
          squeeze: 1.1,
          onSelectedItemChanged: (index) {
            setState(() {
              _tempSelected = _areas[index];
            });
          },
          children: _areas
              .map((area) => Center(
            child: Text(
              area,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.black87,
              ),
            ),
          ))
              .toList(),
        ),
      ),
    );
  }

  /// 상단 타이틀/그립바/확인버튼을 공통으로 감싸는 쉘
  Widget _shell({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: light.withOpacity(.35)),
        boxShadow: [
          BoxShadow(
            color: base.withOpacity(.06),
            blurRadius: 20,
            offset: const Offset(0, -6),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Column(
        children: [
          // 그립바
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: light.withOpacity(.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Text(
            '지역 선택',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ).copyWith(color: dark),
          ),
          const SizedBox(height: 16),

          // 내용
          child,

          const SizedBox(height: 12),
          Divider(height: 1, color: light.withOpacity(.35)),
          const SizedBox(height: 16),

          // 확인 버튼
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: base,
                foregroundColor: fg,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              icon: const Icon(Icons.check_rounded),
              label: const Text('확인'),
              onPressed: () async {
                // 선택값 확정 (스크롤 안 했어도 기본 선택 반영)
                final selected = _tempSelected.trim().isNotEmpty
                    ? _tempSelected.trim()
                    : (_areas.isNotEmpty ? _areas[_initialIndex] : '');

                if (selected.isEmpty) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('지역을 선택하세요.')),
                  );
                  return;
                }

                // 닫기
                if (mounted) Navigator.of(context).pop();

                // 세션/계정 DB 갱신
                bool ok = false;
                try {
                  ok = await _persistSelectedAreaEverywhere(selected);
                } on DatabaseException catch (e, st) {
                  debugPrint('❌ 지역 저장 실패: $e\n$st');
                }

                // HQ 여부를 SQLite에서 조회
                bool isHeadquarter = false;
                try {
                  isHeadquarter = await _isHeadquarter(selected);
                } on DatabaseException catch (e, st) {
                  debugPrint('❌ area 조회 실패: $e\n$st');
                }

                if (!widget.rootContext.mounted) return;

                if (!ok) {
                  ScaffoldMessenger.of(widget.rootContext).showSnackBar(
                    const SnackBar(content: Text('지역 저장에 실패했습니다. 다시 시도해 주세요.')),
                  );
                  return;
                }

                // ✅ PlateState 없이 라우팅만 수행
                if (isHeadquarter) {
                  Navigator.pushReplacementNamed(
                    widget.rootContext,
                    AppRoutes.offlineTypePage,
                  );
                } else {
                  Navigator.pushReplacementNamed(
                    widget.rootContext,
                    AppRoutes.offlineTypePage,
                  );
                }
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
