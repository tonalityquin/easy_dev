// lib/screens/type_pages/offline_departure_request_page.dart
//
// 변경 요약 👇
// - Firestore/Provider 제거, SQLite(offline_auth_db/offline_auth_service)만 사용
// - PlateType/PlateModel 의존 제거 → status_type 문자열 상수로 대체
// - 출차 요청 목록/선택/출차 완료/뒤로가기(선택 해제) 전부 offline_plates 직접 질의
// - UI는 간단한 ListTile 기반(PlateContainer 제거)
// - 검색 바텀시트/상단 네비/하단 컨트롤 버튼은 기존 위젯 재사용(단, 상태 시트는 로컬 간단 시트로 대체)
//
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ▼ SQLite / 세션
import '../sql/offline_auth_db.dart';
import '../sql/offline_auth_service.dart';

import '../../utils/snackbar_helper.dart';

import '../offline_navigation/offline_top_navigation.dart';
import '../../widgets/dialog/common_plate_search_bottom_sheet/common_plate_search_bottom_sheet.dart';
// 기존 departure_request_status_bottom_sheet.dart는 PlateModel 의존 → 사용 제거
import 'offline_departure_request_package/departure_request_control_buttons.dart';

// ⛳ PlateType 제거: status_type을 문자열 상수로 사용
const String _kStatusDepartureRequests = 'departureRequests';
const String _kStatusDepartured       = 'departured'; // 프로젝트 정책에 맞게 수정 가능

class OfflineDepartureRequestPage extends StatefulWidget {
  const OfflineDepartureRequestPage({super.key});

  @override
  State<OfflineDepartureRequestPage> createState() => _OfflineDepartureRequestPageState();
}

class _OfflineDepartureRequestPageState extends State<OfflineDepartureRequestPage> {
  bool _isSorted = true;  // true: 최신순
  bool _isLocked = false; // 화면 잠금

  // 검색 바텀시트 중복 오픈 방지
  bool _openingSearch = false;

  void _log(String msg) {
    if (kDebugMode) debugPrint('[DepartureRequest] $msg');
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  // ─────────────────────────────────────────────────────────────
  // 세션/영역 로딩
  // ─────────────────────────────────────────────────────────────
  Future<(String uid, String uname)> _loadSessionIdentity() async {
    final s = await OfflineAuthService.instance.currentSession();
    final uid = (s?.userId ?? '').trim();
    final uname = (s?.name ?? '').trim();
    return (uid, uname);
  }

  Future<String> _loadCurrentArea() async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();

    String area = '';

    if (uid.isNotEmpty) {
      final r1 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'userId = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (r1.isNotEmpty) {
        area = ((r1.first['currentArea'] as String?) ?? (r1.first['selectedArea'] as String?) ?? '').trim();
      }
    }

    if (area.isEmpty) {
      final r2 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'isSelected = 1',
        limit: 1,
      );
      if (r2.isNotEmpty) {
        area = ((r2.first['currentArea'] as String?) ?? (r2.first['selectedArea'] as String?) ?? '').trim();
      }
    }

    return area;
  }

  // ─────────────────────────────────────────────────────────────
  // 검색 바텀시트
  // ─────────────────────────────────────────────────────────────
  Future<void> _showSearchDialog() async {
    if (_openingSearch) return;
    _openingSearch = true;
    try {
      final currentArea = await _loadCurrentArea();
      if (!mounted) return;
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => CommonPlateSearchBottomSheet(
          onSearch: (query) {
            // TODO: 필요시 SQLite LIKE 검색으로 확장
          },
          area: currentArea,
        ),
      );
    } finally {
      _openingSearch = false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 출차 완료 처리
  // ─────────────────────────────────────────────────────────────
  Future<void> _handleDepartureCompleted() async {
    if (_isLocked) {
      showSelectedSnackbar(context, '화면이 잠금 상태입니다.');
      return;
    }

    try {
      final db = await OfflineAuthDb.instance.database;
      final (uid, uname) = await _loadSessionIdentity();

      final rows = await db.query(
        OfflineAuthDb.tablePlates,
        columns: const ['id', 'plate_number'],
        where: '''
          is_selected = 1
          AND COALESCE(status_type,'') = ?
          AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
        ''',
        whereArgs: [_kStatusDepartureRequests, uid, uname],
        orderBy: 'COALESCE(updated_at, created_at) DESC',
        limit: 1,
      );

      if (rows.isEmpty) {
        showFailedSnackbar(context, '선택된 출차 요청이 없습니다.');
        return;
      }

      final id = rows.first['id'] as int;
      final pn = (rows.first['plate_number'] as String?) ?? '';

      await db.update(
        OfflineAuthDb.tablePlates,
        {
          'status_type': _kStatusDepartured,
          'is_selected': 0,
          'updated_at': _nowMs(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      if (!mounted) return;
      showSuccessSnackbar(context, '출차 완료: $pn');
      setState(() {}); // 목록 갱신
    } catch (e) {
      if (kDebugMode) debugPrint("출차 완료 처리 실패: $e");
      if (mounted) showFailedSnackbar(context, "출차 완료 중 오류 발생: $e");
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 선택 토글 (departureRequests 범위에서 내 선택을 1건으로 유지)
  // ─────────────────────────────────────────────────────────────
  Future<void> _togglePlateSelection(int id) async {
    final db = await OfflineAuthDb.instance.database;
    final (uid, uname) = await _loadSessionIdentity();

    await db.transaction((txn) async {
      // 현재 선택 상태
      final r = await txn.query(
        OfflineAuthDb.tablePlates,
        columns: const ['is_selected'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final curSel = r.isNotEmpty ? ((r.first['is_selected'] as int?) ?? 0) : 0;

      // 같은 status 범위에서 나의 기존 선택 해제
      await txn.update(
        OfflineAuthDb.tablePlates,
        {'is_selected': 0},
        where: "COALESCE(status_type,'') = ? AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)",
        whereArgs: [_kStatusDepartureRequests, uid, uname],
      );

      // 대상 토글
      await txn.update(
        OfflineAuthDb.tablePlates,
        {
          'is_selected': curSel == 0 ? 1 : 0,
          'selected_by': uid,
          'user_name': uname,
          'updated_at': _nowMs(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  // 뒤로가기: 선택 해제
  Future<bool> _clearSelectedIfAny() async {
    final db = await OfflineAuthDb.instance.database;
    final (uid, uname) = await _loadSessionIdentity();

    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const ['id'],
      where: '''
        is_selected = 1
        AND COALESCE(status_type,'') = ?
        AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
      ''',
      whereArgs: [_kStatusDepartureRequests, uid, uname],
      limit: 1,
    );
    if (rows.isEmpty) return false;

    final id = rows.first['id'] as int;
    await db.update(
      OfflineAuthDb.tablePlates,
      {'is_selected': 0, 'updated_at': _nowMs()},
      where: 'id = ?',
      whereArgs: [id],
    );
    return true;
  }

  // ─────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────
  void _toggleSortIcon() => setState(() => _isSorted = !_isSorted);
  void _toggleLock()     => setState(() => _isLocked = !_isLocked);

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 먼저 선택 해제 시도
        if (await _clearSelectedIfAny()) {
          _log('clear selection');
          return false;
        }
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const OfflineTopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: FutureBuilder<Widget>(
          future: _buildListBody(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 3));
            }
            if (snap.hasError) {
              return Center(child: Text('목록 로드 실패: ${snap.error}'));
            }
            return snap.data ?? const SizedBox.shrink();
          },
        ),
        // FAB 없음: SQLite 즉시반영
        bottomNavigationBar: DepartureRequestControlButtons(
          isSorted: _isSorted,
          isLocked: _isLocked,
          showSearchDialog: _showSearchDialog,
          toggleSortIcon: _toggleSortIcon,
          toggleLock: _toggleLock,
          handleDepartureCompleted: _handleDepartureCompleted,
          // ✅ 시그니처 맞춤(4개 인자)
          handleEntryParkingRequest: (ctx, plateNumber, area) {
            showSelectedSnackbar(context, '이 화면에서는 입차 요청 처리를 제공하지 않습니다.');
          },
          handleEntryParkingCompleted: (ctx, plateNumber, area, location) {
            showSelectedSnackbar(context, '이 화면에서는 입차 완료 처리를 제공하지 않습니다.');
          },
        ),
      ),
    );
  }

  Future<Widget> _buildListBody() async {
    final db = await OfflineAuthDb.instance.database;
    final area = await _loadCurrentArea();
    if (area.isEmpty) {
      return const Center(child: Text('현재 지역 정보를 확인할 수 없습니다.'));
    }

    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const [
        'id',
        'plate_number',
        'plate_four_digit',
        'location',
        'request_time',
        'is_selected',
      ],
      where: "COALESCE(status_type,'') = ? AND area = ?",
      whereArgs: [_kStatusDepartureRequests, area],
      orderBy: _isSorted
          ? 'COALESCE(request_time, COALESCE(updated_at, created_at)) DESC'
          : 'COALESCE(request_time, COALESCE(updated_at, created_at)) ASC',
      limit: 300,
    );

    if (rows.isEmpty) {
      return const Center(
        child: Text(
          '출차 요청이 없습니다.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }

    final tiles = rows.map((r) {
      final id = r['id'] as int;
      final pn = (r['plate_number'] as String?)?.trim();
      final four = (r['plate_four_digit'] as String?)?.trim() ?? '';
      final loc = (r['location'] as String?)?.trim() ?? '';
      final selected = ((r['is_selected'] as int?) ?? 0) != 0;

      final title = (pn != null && pn.isNotEmpty)
          ? pn
          : (four.isNotEmpty ? '****-$four' : '미상');

      return ListTile(
        dense: true,
        leading: Icon(selected ? Icons.check_circle : Icons.circle_outlined),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: loc.isNotEmpty ? Text(loc) : null,
        onTap: () async {
          if (_isLocked) return;
          await _togglePlateSelection(id);
          if (!mounted) return;
          setState(() {}); // 재빌드
        },
      );
    }).toList();

    return ListView.separated(
      padding: const EdgeInsets.all(8.0),
      itemCount: tiles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => tiles[i],
    );
  }
}
