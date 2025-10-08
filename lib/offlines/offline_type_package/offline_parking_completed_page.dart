// lib/screens/type_pages/parking_completed_page.dart
//
// 변경 요약 👇
// - Firestore/Provider 제거, SQLite(offline_auth_db/offline_auth_service)만 사용
// - PlateType enum 의존 제거 → 상태 문자열을 파일 내부 상수로 정의해 사용
// - location 리미트는 offline_locations.capacity 사용
// - 위치 선택 시 plateList로 전환하지 않고, 조건 만족 시 번호판 BottomSheet 표시
// - 조건 판별/목록 조회 모두 offline_plates 직접 질의
// - plateList 화면은 단순 ListTile로 보존(선택 토글 SQLite 구현)
// - 뒤로가기 시 선택 해제/모드 롤백 로직 SQLite로 구현
//
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ▼ SQLite / 세션
import '../sql/offline_auth_db.dart';
import '../sql/offline_auth_service.dart';

import '../../utils/snackbar_helper.dart';

import 'offline_parking_completed_package/widgets/offline_signature_plate_search_bottom_sheet/offline_parking_completed_search_bottom_sheet.dart';
import '../offline_navigation/offline_top_navigation.dart';

import 'offline_parking_completed_package/offline_parking_completed_control_buttons.dart';
import 'offline_parking_completed_package/offline_parking_completed_location_picker.dart';
import 'offline_parking_completed_package/widgets/offline_parking_status_page.dart';

// ⛳ PlateType 제거: 상태 문자열을 직접 사용
//   스키마: offline_plates.status_type TEXT
//   프로젝트에서 사용하는 키에 맞춰 수정하세요.
const String _kStatusParkingCompleted = 'parkingCompleted';
const String _kStatusParkingRequests = 'parkingRequests';

enum ParkingViewMode { status, locationPicker, plateList }

class OfflineParkingCompletedPage extends StatefulWidget {
  const OfflineParkingCompletedPage({super.key});

  /// 홈 탭 재진입/재탭 시 내부 상태 초기화를 위한 entry point
  static void reset(GlobalKey key) {
    (key.currentState as _OfflineParkingCompletedPageState?)?._resetInternalState();
  }

  @override
  State<OfflineParkingCompletedPage> createState() => _OfflineParkingCompletedPageState();
}

class _OfflineParkingCompletedPageState extends State<OfflineParkingCompletedPage> {
  ParkingViewMode _mode = ParkingViewMode.status; // 기본은 현황 화면
  String? _selectedParkingArea; // 선택된 주차 구역(location)
  bool _isSorted = true; // true=최신순
  bool _isLocked = true; // 화면 잠금

  // ✅ Status 페이지 강제 재생성용 키 시드 (홈 버튼 리셋 시 증가)
  int _statusKeySeed = 0;

  // BottomSheet 중복 오픈 가드
  bool _openingSheet = false;

  // 리미트 캐싱 (location 한정) — key = '$area::$loc'
  final Map<String, int> _locationLimitCache = {};

  // ─────────────────────────────────────────────────────────────
  // 유틸
  // ─────────────────────────────────────────────────────────────
  void _log(String msg) {
    if (kDebugMode) debugPrint('[ParkingCompleted] $msg');
  }

  int _nowMs() => DateTime.now().millisecondsSinceEpoch;

  /// 현재 세션의 area 불러오기 (없으면 isSelected=1 계정)
  Future<String> _loadCurrentArea() async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();

    Map<String, Object?>? row;
    if (uid.isNotEmpty) {
      final r1 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'userId = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (r1.isNotEmpty) row = r1.first;
    }
    row ??= (await db.query(
      OfflineAuthDb.tableAccounts,
      columns: const ['currentArea', 'selectedArea'],
      where: 'isSelected = 1',
      limit: 1,
    ))
        .firstOrNull;

    final area = ((row?['currentArea'] as String?) ?? (row?['selectedArea'] as String?) ?? '').trim();
    return area;
  }

  /// 현재 세션 정보(선택자 아이덴티티)
  Future<(String uid, String uname)> _loadSessionIdentity() async {
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();
    final uname = (session?.name ?? '').trim();
    return (uid, uname);
  }

  /// 홈 재탭/진입 시 초기 상태로 되돌림
  void _resetInternalState() {
    setState(() {
      _mode = ParkingViewMode.status;
      _selectedParkingArea = null;
      _isSorted = true;
      _isLocked = true; // 요구: 리셋 시 잠금 ON
      _statusKeySeed++; // Status 재생성 트리거 → 집계 재실행
    });
    _log('reset page state');
  }

  void _toggleSortIcon() {
    setState(() => _isSorted = !_isSorted);
    _log(_isSorted ? 'sort → 최신순' : 'sort → 오래된순');
  }

  Future<void> _showSearchDialog(BuildContext context) async {
    final currentArea = await _loadCurrentArea();
    _log('open search dialog');
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) {
        return OfflineParkingCompletedSearchBottomSheet(
          onSearch: (_) {},
          area: currentArea,
        );
      },
    );
  }

  void _resetParkingAreaFilter() {
    setState(() {
      _selectedParkingArea = null;
      _mode = ParkingViewMode.status;
    });
    _log('reset location filter');
  }

  // ─────────────────────────────────────────────────────────────
  // SQLite: location 리미트(capacity) 조회 (캐싱)
  // ─────────────────────────────────────────────────────────────
  Future<int?> _getLocationLimit(String area, String loc) async {
    final key = '$area::$loc';
    if (_locationLimitCache.containsKey(key)) return _locationLimitCache[key];

    final db = await OfflineAuthDb.instance.database;

    // location_name 정확 일치 우선
    List<Map<String, Object?>> rows = await db.query(
      OfflineAuthDb.tableLocations,
      columns: const ['capacity'],
      where: 'area = ? AND location_name = ?',
      whereArgs: [area, loc],
      limit: 1,
    );

    // 못 찾으면 parent-자식 모델 가능성: '부모 - 자식'에서 자식명만 일치 시도는 호출부에서 처리
    if (rows.isEmpty) {
      // 보수적으로 동일 쿼리 유지(규칙상 정확 일치만)
      rows = await db.query(
        OfflineAuthDb.tableLocations,
        columns: const ['capacity'],
        where: 'area = ? AND location_name = ?',
        whereArgs: [area, loc],
        limit: 1,
      );
    }

    if (rows.isEmpty) return null;
    final cap = (rows.first['capacity'] as int?) ?? 0;
    if (cap <= 0) return null;

    _locationLimitCache[key] = cap;
    return cap;
  }

  // ─────────────────────────────────────────────────────────────
  // SQLite: count/select 유틸
  // ─────────────────────────────────────────────────────────────
  Future<int> _countAt(String area, String loc) async {
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

  Future<List<String>> _fetchPlateNumbers(String area, String loc, int limit) async {
    final db = await OfflineAuthDb.instance.database;
    final rows = await db.rawQuery(
      '''
      SELECT plate_number, plate_four_digit
        FROM ${OfflineAuthDb.tablePlates}
       WHERE COALESCE(status_type,'') = ?
         AND area = ?
         AND location = ?
       ORDER BY COALESCE(updated_at, created_at) DESC
       LIMIT ?
      ''',
      [_kStatusParkingCompleted, area, loc, limit],
    );

    final out = <String>[];
    for (final r in rows) {
      final pn = (r['plate_number'] as String?)?.trim();
      if (pn != null && pn.isNotEmpty) {
        out.add(pn);
      } else {
        final four = (r['plate_four_digit'] as String?)?.trim() ?? '';
        if (four.isNotEmpty) out.add('****-$four');
      }
    }
    return out;
  }

  // ─────────────────────────────────────────────────────────────
  // 출차 요청(오프라인): 현재 선택된 parkingCompleted 1건을 parkingRequests로 전환
  // ─────────────────────────────────────────────────────────────
  Future<void> _handleDepartureRequested(BuildContext context) async {
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
        whereArgs: [_kStatusParkingCompleted, uid, uname],
        orderBy: 'COALESCE(updated_at, created_at) DESC',
        limit: 1,
      );

      if (rows.isEmpty) {
        showFailedSnackbar(context, '선택된 차량이 없습니다.');
        return;
      }

      final id = rows.first['id'] as int;
      await db.update(
        OfflineAuthDb.tablePlates,
        {
          'status_type': _kStatusParkingRequests,
          'is_selected': 0,
          'updated_at': _nowMs(),
        },
        where: 'id = ?',
        whereArgs: [id],
      );

      showSuccessSnackbar(context, '출차 요청이 완료되었습니다.');
    } catch (e) {
      showFailedSnackbar(context, '출차 요청 중 오류: $e');
    }
  }

  // ✅ (빌드 에러 방지) 컨트롤 버튼에서 요구하는 입차 요청 콜백 스텁
  void handleEntryParkingRequest(BuildContext context, String plateNumber, String area) async {
    _log('stub: entry parking request $plateNumber ($area)');
    showSuccessSnackbar(context, "입차 요청 처리: $plateNumber ($area)");
  }

  // ─────────────────────────────────────────────────────────────
  // ⛳ 새 로직: "구역 선택" 시 plateList 모드로 가지 않고, 조건 만족 시 번호판 BottomSheet 표시
  //   - 조건: 해당 구역(location)의 parkingCompleted 개수 ≤ capacity  (offline_locations.capacity)
  //   - 만족 시: 번호판 목록을 소량 조회하여 BottomSheet로 표시
  //   - 불만족/미설정 시: Snackbar 안내
  // ─────────────────────────────────────────────────────────────
  Future<void> _tryShowPlateNumbersBottomSheet(String locationName) async {
    // 🔒 잠금 상태면 즉시 차단
    if (_isLocked) {
      showFailedSnackbar(context, '잠금 상태입니다. 잠금을 해제한 뒤 이용해 주세요.');
      return;
    }

    // 중복 오픈 가드
    if (_openingSheet) return;
    _openingSheet = true;

    // '부모 - 자식' 케이스 대비 자식 파트
    String raw = locationName.trim();
    String? child;
    final hyphenIdx = raw.lastIndexOf(' - ');
    if (hyphenIdx != -1) {
      child = raw.substring(hyphenIdx + 3).trim();
    }

    try {
      final area = await _loadCurrentArea();
      if (area.isEmpty) {
        showFailedSnackbar(context, '현재 지역 정보를 확인할 수 없습니다.');
        return;
      }

      // 1) location 단위 개수 선판별: raw → (없으면) child 순으로 count()
      String selectedLoc = raw;
      int locCnt = await _countAt(area, raw);
      if (locCnt == 0 && child != null && child.isNotEmpty) {
        selectedLoc = child;
        locCnt = await _countAt(area, child);
      }

      if (locCnt == 0) {
        showSelectedSnackbar(context, '해당 구역에 입차 완료 차량이 없습니다.');
        return;
      }

      // 2) 리미트 결정: offline_locations.capacity
      final limit = await _getLocationLimit(area, selectedLoc);
      if (limit == null || limit <= 0) {
        showFailedSnackbar(context, '"$selectedLoc" 리미트가 설정되지 않았습니다. 관리자에 문의하세요.');
        return;
      }

      // 3) 기준 초과면 차단
      if (locCnt > limit) {
        showFailedSnackbar(context, '목록 잠금: "$selectedLoc"에 입차 완료 $locCnt대(>$limit) 입니다.');
        return;
      }

      // 4) 조건 만족 시: 선택된 location에서 실제 목록을 소량 조회 (번호판만 사용)
      final plateNumbers = await _fetchPlateNumbers(area, selectedLoc, limit);

      if (plateNumbers.isEmpty) {
        showSelectedSnackbar(context, '해당 구역에 입차 완료 차량이 없습니다.');
        return;
      }

      if (!mounted) return;
      await _showPlateNumberListSheet(locationName: locationName, plates: plateNumbers);
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '번호판 목록 표시 실패: $e');
    } finally {
      _openingSheet = false;
    }
  }

  /// 번호판 목록을 간단히 보여주는 바텀시트 UI (plateNumber 텍스트만)
  Future<void> _showPlateNumberListSheet({
    required String locationName,
    required List<String> plates,
  }) async {
    // 아이템 수에 따라 초기/최소 높이를 동적으로 설정
    final double initialFactor = plates.length <= 3 ? 0.45 : (plates.length <= 7 ? 0.60 : 0.80);

    final theme = Theme.of(context);
    final surfaceColor = theme.colorScheme.surface;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: initialFactor,
          minChildSize: initialFactor,
          maxChildSize: 0.95,
          expand: false,
          builder: (context, scrollController) {
            return SafeArea(
              top: false,
              child: Container(
                decoration: BoxDecoration(
                  color: surfaceColor, // 다크모드 대응
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 상단 핸들
                    Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 12),
                      decoration: BoxDecoration(
                        color: theme.dividerColor.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // 헤더
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.local_parking),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '"$locationName" 번호판',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${plates.length}대',
                            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),

                    // 목록
                    Expanded(
                      child: ListView.separated(
                        controller: scrollController, // 드래그 시트와 스크롤 연동
                        itemCount: plates.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final pn = plates[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.directions_car),
                            title: Text(
                              pn,
                              style: const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            // 요구사항: "번호판 명만" → 탭 액션 없음
                          );
                        },
                      ),
                    ),

                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // 뒤로가기(pop): 선택 해제/모드 롤백
  // ─────────────────────────────────────────────────────────────
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
      whereArgs: [_kStatusParkingCompleted, uid, uname],
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

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // 시스템/뒤로가기 처리: 선택/모드 단계적으로 해제
      onWillPop: () async {
        // 선택된 번호판이 있으면 선택 해제 먼저
        if (await _clearSelectedIfAny()) {
          _log('clear selection');
          return false;
        }

        // plateList → locationPicker → status 순으로 한 단계씩 되돌기
        if (_mode == ParkingViewMode.plateList) {
          setState(() => _mode = ParkingViewMode.locationPicker);
          _log('back → locationPicker');
          return false;
        } else if (_mode == ParkingViewMode.locationPicker) {
          setState(() => _mode = ParkingViewMode.status);
          _log('back → status');
          return false;
        }

        // 최상위(status)면 pop 허용
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
        body: _buildBody(context),
        bottomNavigationBar: OfflineParkingCompletedControlButtons(
          isParkingAreaMode: _mode == ParkingViewMode.plateList,
          isStatusMode: _mode == ParkingViewMode.status,
          isLocationPickerMode: _mode == ParkingViewMode.locationPicker,
          isSorted: _isSorted,
          isLocked: _isLocked,
          onToggleLock: () {
            setState(() => _isLocked = !_isLocked);
            _log(_isLocked ? 'lock ON' : 'lock OFF');
          },
          showSearchDialog: () => _showSearchDialog(context),
          resetParkingAreaFilter: _resetParkingAreaFilter,
          toggleSortIcon: _toggleSortIcon,
          handleEntryParkingRequest: handleEntryParkingRequest,
          handleDepartureRequested: _handleDepartureRequested,
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    switch (_mode) {
      case ParkingViewMode.status:
        // 🔹 현황 화면을 탭하면 위치 선택 화면으로 전환
        return GestureDetector(
          onTap: () {
            setState(() => _mode = ParkingViewMode.locationPicker);
            _log('open location picker');
          },
          // ✅ 리셋마다 키가 바뀌어 ParkingStatusPage의 State가 새로 만들어짐 → 집계 재실행
          child: OfflineParkingStatusPage(
            key: ValueKey('status-$_statusKeySeed'),
            isLocked: _isLocked,
          ),
        );

      case ParkingViewMode.locationPicker:
        // 🔹 위치 선택 시: plateList 모드로 가지 않고, 번호판 BottomSheet 시도
        return OfflineParkingCompletedLocationPicker(
          onLocationSelected: (locationName) {
            _selectedParkingArea = locationName; // 선택된 구역 저장(필요 시)
            _tryShowPlateNumbersBottomSheet(locationName);
          },
          isLocked: _isLocked,
        );

      case ParkingViewMode.plateList:
        // 🔹 기존 plateList 화면 보존: 간단한 SQLite 목록 구현
        return FutureBuilder<Widget>(
          future: _buildPlateListBody(),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator(strokeWidth: 3));
            }
            if (snap.hasError) {
              return Center(child: Text('목록 로드 실패: ${snap.error}'));
            }
            return snap.data ?? const SizedBox.shrink();
          },
        );
    }
  }

  Future<Widget> _buildPlateListBody() async {
    final db = await OfflineAuthDb.instance.database;
    final area = await _loadCurrentArea();
    if (area.isEmpty) {
      return const Center(child: Text('현재 지역 정보를 확인할 수 없습니다.'));
    }

    final whereParts = <String>[
      "COALESCE(status_type,'') = ?",
      'area = ?',
    ];
    final args = <Object?>[_kStatusParkingCompleted, area];

    if (_selectedParkingArea != null && _selectedParkingArea!.trim().isNotEmpty) {
      whereParts.add('location = ?');
      args.add(_selectedParkingArea!.trim());
    }

    final rows = await db.query(
      OfflineAuthDb.tablePlates,
      columns: const ['id', 'plate_number', 'plate_four_digit', 'location', 'is_selected'],
      where: whereParts.join(' AND '),
      whereArgs: args,
      orderBy: _isSorted ? 'COALESCE(updated_at, created_at) DESC' : 'COALESCE(updated_at, created_at) ASC',
      limit: 200, // 표시에 충분한 제한
    );

    final listTiles = rows.map((r) {
      final int id = r['id'] as int;
      final pn = (r['plate_number'] as String?)?.trim();
      final four = (r['plate_four_digit'] as String?)?.trim() ?? '';
      final loc = (r['location'] as String?)?.trim() ?? '';
      final selected = ((r['is_selected'] as int?) ?? 0) != 0;

      final title = (pn != null && pn.isNotEmpty) ? pn : (four.isNotEmpty ? '****-$four' : '미상');

      return ListTile(
        dense: true,
        leading: Icon(selected ? Icons.check_circle : Icons.circle_outlined),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(loc),
        onTap: () async {
          await _togglePlateSelection(id);
          if (!mounted) return;
          setState(() {}); // 재빌드
        },
      );
    }).toList();

    return ListView.separated(
      padding: const EdgeInsets.all(8.0),
      itemCount: listTiles.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) => listTiles[i],
    );
  }

  Future<void> _togglePlateSelection(int id) async {
    final db = await OfflineAuthDb.instance.database;
    final (uid, uname) = await _loadSessionIdentity();

    await db.transaction((txn) async {
      // 현재 선택 상태 조회
      final r = await txn.query(
        OfflineAuthDb.tablePlates,
        columns: const ['is_selected'],
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      final curSel = r.isNotEmpty ? ((r.first['is_selected'] as int?) ?? 0) : 0;

      // 나의 기존 선택 해제(같은 status 범위에서 중복 선택 방지)
      await txn.update(
        OfflineAuthDb.tablePlates,
        {'is_selected': 0},
        where: "COALESCE(status_type,'') = ? AND (COALESCE(selected_by,'') = ? OR COALESCE(user_name,'') = ?)",
        whereArgs: [_kStatusParkingCompleted, uid, uname],
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
}
