// lib/screens/type_pages/parking_request_page.dart
//
// 변경 요약 👇
// - Firestore/Provider 제거, SQLite(offline_auth_db/offline_auth_service)만 사용
// - PlateType enum 의존 제거 → 상태 문자열을 파일 내부 상수로 정의해 사용
// - '입차 완료' 처리 시 offline_locations.capacity 기준으로 초과 여부 판정
// - 위치 바텀시트(OfflineParkingLocationBottomSheet)에서 선택 후 상태 전환
// - 선택/뒤로가기/정렬 등은 전부 offline_plates 직접 질의로 구현
// - 검색: 기존 CommonPlateSearchBottomSheet 대신 모달 바텀시트로 안내 텍스트만 표시
// - ✅ 목록 아이템을 박스(UI)로 리팩터링하고, 번호 + 위치 + 정산 유형(요약) 함께 출력
//
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ▼ SQLite / 세션
import '../sql/offline_auth_db.dart';
import '../sql/offline_auth_service.dart';

import '../../utils/snackbar_helper.dart';

// 위치 선택 바텀시트 (기존 프로젝트의 것을 사용)
import 'offline_parking_request_package/offline_parking_location_bottom_sheet.dart';

// 상단 네비게이션 (기존 프로젝트의 것을 사용)
import '../offline_navigation/offline_top_navigation.dart';

// 하단 컨트롤 버튼(기존 프로젝트 위젯 시그니처에 맞춰 콜백 제공)
import 'offline_parking_request_package/offline_parking_request_control_buttons.dart';

// ⛳ PlateType 제거: 상태 문자열을 직접 사용
//   스키마: offline_plates.status_type TEXT
const String _kStatusParkingCompleted = 'parkingCompleted';
const String _kStatusParkingRequests = 'parkingRequests';

class OfflineParkingRequestPage extends StatefulWidget {
  const OfflineParkingRequestPage({super.key});

  @override
  State<OfflineParkingRequestPage> createState() => _OfflineParkingRequestPageState();
}

class _OfflineParkingRequestPageState extends State<OfflineParkingRequestPage> {
  bool _isSorted = true; // 최신순(true) / 오래된순(false)
  bool _isLocked = false; // 화면 잠금

  // 검색 바텀시트 중복 오픈 방지
  bool _openingSearch = false;

  // 위치 리미트 캐시 (area::location → capacity)
  final Map<String, int> _locationLimitCache = {};

  void _log(String msg) {
    if (kDebugMode) debugPrint('[ParkingRequest] $msg');
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
  // 위치 리미트(capacity) 및 카운트
  // ─────────────────────────────────────────────────────────────
  Future<int?> _getLocationLimit(String area, String loc) async {
    final key = '$area::$loc';
    if (_locationLimitCache.containsKey(key)) return _locationLimitCache[key];

    final db = await OfflineAuthDb.instance.database;
    final rows = await db.query(
      OfflineAuthDb.tableLocations,
      columns: const ['capacity'],
      where: 'area = ? AND location_name = ?',
      whereArgs: [area, loc],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    final cap = (rows.first['capacity'] as int?) ?? 0;
    if (cap <= 0) return null;

    _locationLimitCache[key] = cap;
    return cap;
  }

  Future<int> _countCompletedAt(String area, String loc) async {
    final db = await OfflineAuthDb.instance.database;
    final res = await db.rawQuery(
      '''
      SELECT COUNT(*) AS c
        FROM ${OfflineAuthDb.tablePlates}
       WHERE COALESCE(status_type,'') = ?
         AND area = ?
         AND location = ?
      ''',
      [_kStatusParkingCompleted, area, loc],
    );
    final c = (res.isNotEmpty ? res.first['c'] : 0) as int? ?? 0;
    return c;
  }

  // ─────────────────────────────────────────────────────────────
  // 검색 다이얼로그 → 모달 바텀시트로 안내 문구 표시
  // ─────────────────────────────────────────────────────────────
  Future<void> _showSearchDialog() async {
    if (_openingSearch) return;
    _openingSearch = true;
    try {
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,        // ✅ 풀스크린 높이 사용
        useSafeArea: true,               // ✅ 노치/상단 안전영역까지 차오르되 컨텐츠는 안전영역 내 배치
        backgroundColor: Colors.white,
        builder: (sheetContext) {
          return FractionallySizedBox(
            heightFactor: 1,             // ✅ 화면 전체 높이
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.max,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '번호판 위치 검색',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(sheetContext).pop(),
                          tooltip: '닫기',
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '입차 요청 및 출차 요청에 있는 번호판 위치를 검색할 수 있습니다.',
                      style: TextStyle(fontSize: 15),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          );
        },
      );
    } finally {
      _openingSearch = false;
    }
  }

  // ─────────────────────────────────────────────────────────────
  // '입차 완료' 플로우
  // ─────────────────────────────────────────────────────────────
  Future<void> _handleParkingCompleted() async {
    if (_isLocked) {
      showSelectedSnackbar(context, '화면이 잠금 상태입니다.');
      return;
    }

    final db = await OfflineAuthDb.instance.database;
    final (uid, uname) = await _loadSessionIdentity();

    // 현재 선택된 요청 1건
    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const ['id', 'plate_number', 'area'],
      where: '''
        is_selected = 1
        AND COALESCE(status_type,'') = ?
        AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)
      ''',
      whereArgs: [_kStatusParkingRequests, uid, uname],
      orderBy: 'COALESCE(updated_at, created_at) DESC',
      limit: 1,
    );

    if (rows.isEmpty) {
      showFailedSnackbar(context, '선택된 입차 요청이 없습니다.');
      return;
    }

    final int id = rows.first['id'] as int;
    final String plateNumber = (rows.first['plate_number'] as String?) ?? '';
    final String area = (rows.first['area'] as String?) ?? '';

    final TextEditingController locationController = TextEditingController();

    while (mounted) {
      final String? selectedLocation = await showDialog<String>(
        context: context,
        builder: (dialogContext) {
          return OfflineParkingLocationBottomSheet(locationController: locationController);
        },
      );

      if (selectedLocation == null) break; // 닫힘
      if (selectedLocation == 'refresh') continue;

      final loc = selectedLocation.trim();
      if (loc.isEmpty) {
        showFailedSnackbar(context, '주차 구역을 입력해주세요.');
        continue;
      }

      // 리미트 체크
      final limit = await _getLocationLimit(area, loc);
      if (limit == null || limit <= 0) {
        showFailedSnackbar(context, '"$loc" 리미트가 설정되지 않았습니다. 관리자에 문의하세요.');
        continue;
      }
      final curCnt = await _countCompletedAt(area, loc);
      if (curCnt >= limit) {
        showFailedSnackbar(context, '입차 제한: "$loc"은(는) 현재 $curCnt대 / $limit대입니다.');
        continue;
      }

      // 전환 처리
      try {
        await db.update(
          OfflineAuthDb.tablePlates,
          {
            'status_type': _kStatusParkingCompleted,
            'location': loc,
            'is_selected': 0, // 완료 시 선택 해제
            'updated_at': _nowMs(),
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        if (!mounted) return;
        showSuccessSnackbar(context, '입차 완료: $plateNumber ($loc)');
        setState(() {}); // 목록 재빌드
        break;
      } catch (e) {
        if (kDebugMode) debugPrint('입차 완료 처리 실패: $e');
        if (!mounted) return;
        showFailedSnackbar(context, "입차 완료 처리 중 오류 발생: 다시 시도해 주세요.");
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // 선택 토글
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

      // 나의 기존 선택 해제(같은 status 범위)
      await txn.update(
        OfflineAuthDb.tablePlates,
        {'is_selected': 0},
        where:
        "COALESCE(status_type,'') = ? AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)",
        whereArgs: [_kStatusParkingRequests, uid, uname],
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
      whereArgs: [_kStatusParkingRequests, uid, uname],
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

  void _toggleSortIcon() {
    setState(() => _isSorted = !_isSorted);
    _log(_isSorted ? 'sort → 최신순' : 'sort → 오래된순');
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // 선택 해제 먼저 시도
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
        bottomNavigationBar: OfflineParkingRequestControlButtons(
          isSorted: _isSorted,
          isLocked: _isLocked,
          onToggleLock: () {
            setState(() => _isLocked = !_isLocked);
            _log(_isLocked ? 'lock ON' : 'lock OFF');
          },
          onSearchPressed: _showSearchDialog,
          onSortToggle: _toggleSortIcon,
          onParkingCompleted: _handleParkingCompleted,
        ),
      ),
    );
  }

  String _buildBillingSummary({
    required int basicAmount,
    required int basicStd,
    required int addAmount,
    required int addStd,
  }) {
    final parts = <String>[];
    if (basicAmount > 0) {
      parts.add('기본 ${basicAmount}원${basicStd > 0 ? ' / ${basicStd}분' : ''}');
    }
    if (addAmount > 0) {
      parts.add('추가 ${addAmount}원${addStd > 0 ? ' / ${addStd}분' : ''}');
    }
    return parts.isEmpty ? '' : parts.join(', ');
  }

  Future<Widget> _buildListBody() async {
    final db = await OfflineAuthDb.instance.database;
    final area = await _loadCurrentArea();
    if (area.isEmpty) {
      return const Center(child: Text('현재 지역 정보를 확인할 수 없습니다.'));
    }

    // ✅ 위치, 정산 유형(오프라인 플레이트의 billing_type 및 요약) 함께 조회
    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const [
        'id',
        'plate_number',
        'plate_four_digit',
        'location',
        'billing_type',
        'basic_amount',
        'basic_standard',
        'add_amount',
        'add_standard',
        'request_time',
        'is_selected',
      ],
      where: "COALESCE(status_type,'') = ? AND area = ?",
      whereArgs: [_kStatusParkingRequests, area],
      orderBy: _isSorted
          ? 'COALESCE(request_time, COALESCE(updated_at, created_at)) DESC'
          : 'COALESCE(request_time, COALESCE(updated_at, created_at)) ASC',
      limit: 300,
    );

    if (rows.isEmpty) {
      return const Center(child: Text('오프라인 입차 요청 내역이 없습니다.'));
    }

    final tiles = rows.map((r) {
      final id = r['id'] as int;
      final pn = (r['plate_number'] as String?)?.trim();
      final four = (r['plate_four_digit'] as String?)?.trim() ?? '';
      final loc = (r['location'] as String?)?.trim() ?? '';
      final billing = (r['billing_type'] as String?)?.trim() ?? '';
      final basicAmount = (r['basic_amount'] as int?) ?? 0;
      final basicStd = (r['basic_standard'] as int?) ?? 0;
      final addAmount = (r['add_amount'] as int?) ?? 0;
      final addStd = (r['add_standard'] as int?) ?? 0;
      final selected = ((r['is_selected'] as int?) ?? 0) != 0;

      final title = (pn != null && pn.isNotEmpty) ? pn : (four.isNotEmpty ? '****-$four' : '미상');
      final locationText = loc.isNotEmpty ? loc : '위치 미지정';

      final billingSummary = _buildBillingSummary(
        basicAmount: basicAmount,
        basicStd: basicStd,
        addAmount: addAmount,
        addStd: addStd,
      );
      final billingText = billing.isEmpty
          ? '정산 미지정'
          : (billingSummary.isEmpty ? '정산 $billing' : '정산 $billing ($billingSummary)');

      return InkWell(
        onTap: () async {
          if (_isLocked) {
            showSelectedSnackbar(context, '화면이 잠금 상태입니다.');
            return;
          }
          await _togglePlateSelection(id);
          if (!mounted) return;
          setState(() {}); // 재빌드
        },
        child: Container(
          width: double.infinity, // ✅ 가로 꽉차게
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: selected ? Colors.black.withOpacity(0.04) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? Colors.black : Colors.grey.shade300,
              width: selected ? 1.6 : 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.check_circle : Icons.directions_car,
                size: 22,
                color: selected ? Colors.black : Colors.grey[700],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 차량 번호(크게)
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // 위치
                    Text(
                      locationText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey.shade700,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    // 정산 유형 + 요약
                    Text(
                      billingText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: Colors.grey.shade600,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      );
    }).toList();

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: tiles.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10), // ✅ 박스 간격
      itemBuilder: (_, i) => tiles[i],
    );
  }
}
