// lib/screens/type_package/parking_completed_package/ui/parking_completed_table_sheet.dart
import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ✅ 추가: 현재 로그인 계정의 currentArea / 전역 AreaState 접근
import '../../../../../../states/area/area_state.dart';
import '../../../../../../states/user/user_state.dart';

// ✅ 추가: LocationState(구역별 plateCount 반영용)
import '../../../../../../states/location/location_state.dart';

import '../../../../../../utils/snackbar_helper.dart';
import 'repositories/parking_completed_repository.dart';
import 'ui/reverse_page_top_sheet.dart';

// ✅ Trace 기록용 Recorder
import '../../../../../../screens/hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

/// ✅ 실시간 탭 진입 게이트(ON/OFF)
/// - 기본 OFF
/// - 앱 재실행 후에도 유지(SharedPreferences)
class ParkingCompletedRealtimeTabGate {
  static const String _prefsKeyRealtimeTabEnabled = 'parking_completed_realtime_tab_enabled_v1';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyRealtimeTabEnabled) ?? false; // 기본 OFF
  }

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyRealtimeTabEnabled, v);
  }
}

/// 👉 역 Top Sheet로 "Parking Completed 로컬/실시간 테이블" 열기 헬퍼
///
/// - 로컬 탭: 기존 SQLite 테이블 뷰
/// - 실시간 탭: (게이트 ON일 때만) 캐시된 데이터만 표시(탭 진입 시 서버 조회 금지)
///   서버 조회는 "새로고침" 버튼에서만 수행
///
/// ✅ 변경: 로그인 계정(UserState)의 currentArea(우선) / AreaState.currentArea(차선)를 사용해
///         해당 area 문서의 데이터만 조회하도록 area를 주입합니다.
Future<void> showParkingCompletedTableTopSheet(BuildContext context) async {
  // 1) 로그인 계정 currentArea 우선
  final userArea = context.read<UserState>().currentArea.trim();

  // 2) 혹시 userArea가 비어 있으면 AreaState를 차선으로 사용
  final stateArea = context.read<AreaState>().currentArea.trim();

  final area = userArea.isNotEmpty ? userArea : stateArea;

  if (area.isEmpty) {
    showFailedSnackbar(context, '현재 지역(currentArea)이 설정되지 않았습니다.');
    return;
  }

  await showReversePageTopSheet(
    context: context,
    maxHeightFactor: 0.95,
    builder: (_) => ParkingCompletedTableSheet(area: area),
  );
}

/// 로컬(SQLite) + 실시간(Firestore view) 탭 제공
/// ✅ 변경: area 주입(해당 지역 문서만 조회)
class ParkingCompletedTableSheet extends StatefulWidget {
  final String area;

  const ParkingCompletedTableSheet({
    super.key,
    required this.area,
  });

  @override
  State<ParkingCompletedTableSheet> createState() => _ParkingCompletedTableSheetState();
}

class _ParkingCompletedTableSheetState extends State<ParkingCompletedTableSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  bool _realtimeTabEnabled = false; // ✅ 기본 OFF
  bool _gateLoaded = false;

  // ✅ Trace 기록 헬퍼
  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _loadGate();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGate() async {
    try {
      final enabled = await ParkingCompletedRealtimeTabGate.isEnabled();
      if (!mounted) return;

      setState(() {
        _realtimeTabEnabled = enabled;
        _gateLoaded = true;

        if (!_realtimeTabEnabled && _tabCtrl.index == 1) {
          _tabCtrl.index = 0;
        }
      });
    } catch (_) {
      if (!mounted) return;

      setState(() {
        _realtimeTabEnabled = false;
        _gateLoaded = true;
        _tabCtrl.index = 0;
      });
    }
  }

  void _onTapTab(int index) {
    // ✅ 탭 클릭 Trace 기록
    _trace(
      '입차 완료 테이블 탭 클릭',
      meta: <String, dynamic>{
        'screen': 'parking_completed_table_sheet',
        'action': 'tab_tap',
        'tabIndex': index,
        'tab': index == 0 ? 'local' : 'realtime',
        'realtimeEnabled': _realtimeTabEnabled,
        'area': widget.area,
      },
    );

    if (index == 1 && !_realtimeTabEnabled) {
      // ✅ 실시간 탭 차단 Trace 기록
      _trace(
        '실시간 탭 차단',
        meta: <String, dynamic>{
          'screen': 'parking_completed_table_sheet',
          'action': 'tab_blocked',
          'tabIndex': 1,
          'tab': 'realtime',
          'area': widget.area,
          'reason': 'realtime_tab_gate_off',
        },
      );

      HapticFeedback.selectionClick();
      _tabCtrl.animateTo(0);
      return;
    }

    _tabCtrl.animateTo(index);
  }

  Widget _tabLabel({
    required String text,
    required bool enabled,
  }) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (!enabled) ...[
          Icon(Icons.lock_outline, size: 16, color: cs.outline.withOpacity(.9)),
          const SizedBox(width: 6),
        ],
        Text(text),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      top: true,
      left: false,
      right: false,
      bottom: false,
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            const SizedBox(height: 4),

            // ─────────────── 상단 헤더(공통) ───────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: _Palette.base.withOpacity(.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.table_chart_outlined,
                      color: _Palette.base,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '입차 완료 테이블',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: _Palette.dark,
                          ),
                        ),
                        const SizedBox(height: 2),

                        // 확장 슬롯(현재는 사용하지 않음)
                        if (_gateLoaded && !_realtimeTabEnabled) ...[],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Container(
                decoration: BoxDecoration(
                  color: _Palette.base.withOpacity(.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _Palette.light.withOpacity(.25)),
                ),
                child: TabBar(
                  controller: _tabCtrl,
                  onTap: _onTapTab,
                  labelColor: _Palette.base,
                  unselectedLabelColor: cs.outline,
                  indicatorColor: _Palette.base,
                  indicatorSize: TabBarIndicatorSize.tab,
                  dividerColor: Colors.transparent,
                  tabs: [
                    Tab(child: _tabLabel(text: '로컬', enabled: true)),
                    Tab(child: _tabLabel(text: '실시간', enabled: _realtimeTabEnabled)),
                  ],
                ),
              ),
            ),

            const Divider(height: 1),

            // ─────────────── 탭 바디 ───────────────
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                physics: _realtimeTabEnabled
                    ? const PageScrollPhysics()
                    : const NeverScrollableScrollPhysics(),
                children: [
                  _ParkingCompletedTableTab(
                    mode: _TableMode.local,
                    description: '하루 업무가 끝나면 꼭 휴지통을 눌러 데이터를 비워주세요.',
                    area: widget.area,
                  ),
                  _realtimeTabEnabled
                      ? _ParkingCompletedTableTab(
                    mode: _TableMode.realtime,
                    description: '잦은 새로고침은 앱에 무리를 줍니다.',
                    area: widget.area,
                  )
                      : const _RealtimeTabLockedPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RealtimeTabLockedPanel extends StatelessWidget {
  const _RealtimeTabLockedPanel();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outline, size: 44, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              '실시간 탭이 비활성화되어 있습니다',
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: _Palette.dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '설정에서 “실시간 모드(탭) 사용”을 ON으로 변경한 뒤 다시 시도해 주세요.',
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: cs.outline,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _TableMode { local, realtime }

/// Deep Blue 팔레트(서비스 전반에서 사용하는 컬러와 동일 계열)
class _Palette {
  static const base = Color(0xFF0D47A1); // primary
  static const dark = Color(0xFF09367D); // 강조 텍스트/아이콘
  static const light = Color(0xFF5472D3); // 톤 변형/보더
}

/// UI 렌더링을 위한 내부 Row VM
/// - 로컬(SQLite): isDepartureCompleted 의미 있음
/// - 실시간(Firestore): isDepartureCompleted는 false 고정
class _RowVM {
  final String plateNumber;
  final String location;
  final DateTime? createdAt;
  final bool isDepartureCompleted;

  const _RowVM({
    required this.plateNumber,
    required this.location,
    required this.createdAt,
    required this.isDepartureCompleted,
  });
}

/// ─────────────────────────────────────────────────────────
/// 탭 단위 테이블(로컬/실시간 공통 UI, 데이터 소스만 교체)
/// ─────────────────────────────────────────────────────────
class _ParkingCompletedTableTab extends StatefulWidget {
  final _TableMode mode;
  final String description;

  /// ✅ 현재 지역(=로그인 계정 currentArea)
  final String area;

  const _ParkingCompletedTableTab({
    required this.mode,
    required this.description,
    required this.area,
  });

  @override
  State<_ParkingCompletedTableTab> createState() => _ParkingCompletedTableTabState();
}

class _ParkingCompletedTableTabState extends State<_ParkingCompletedTableTab>
    with AutomaticKeepAliveClientMixin {
  // 로컬(SQLite) repo
  final _localRepo = ParkingCompletedRepository();

  // 실시간(Firestore view) repo
  final _realtimeRepo = _ParkingCompletedViewRepository();

  static const int _debounceMs = 300;
  static const double _tableMinWidth = 720;
  static const double _headerHeight = 44;

  bool _loading = true;

  /// 전체 로우(필터 전)
  /// - 실시간 탭: 캐시/서버조회 결과를 유지(필터 변경 시 재조회 금지)
  List<_RowVM> _allRows = [];

  /// 화면에 표시되는 로우(필터/정렬 후)
  List<_RowVM> _rows = [];

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  final ScrollController _scrollCtrl = ScrollController();

  // 정렬 상태: true = 오래된 순(ASC), false = 최신 순(DESC)
  bool _sortOldFirst = true;

  // 출차 완료 숨김(로컬만)
  bool _hideDepartureCompleted = false;

  bool get _isLocal => widget.mode == _TableMode.local;
  bool get _isRealtime => widget.mode == _TableMode.realtime;

  // ✅ 실시간 탭: “주차 구역”은 area가 아니라 location
  static const String _locationAll = '전체';
  String _selectedLocation = _locationAll;
  List<String> _availableLocations = [];

  // ✅ 옵션 A: 실시간 탭은 자동 서버조회 금지
  bool _hasFetchedFromServer = false;

  // ✅ 쿨다운 표시 갱신용(리오픈 시에도 repository 값을 기반으로 재시작)
  Timer? _refreshCooldownTicker;
  bool get _isRefreshBlocked => _realtimeRepo.isRefreshBlocked(widget.area);
  int get _refreshRemainingSec => _realtimeRepo.refreshRemainingSec(widget.area);

  // ✅ 실시간 write 토글 로딩 상태(SharedPreferences 읽기)
  bool _writeToggleLoading = false;

  // ✅ Trace 기록 헬퍼
  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  // ─────────────────────────────────────────────────────────
  // ✅ [수정안 핵심] LocationState.updatePlateCounts()를 post-frame으로 이연 + coalesce
  // ─────────────────────────────────────────────────────────
  Map<String, int>? _pendingPlateCountsByDisplayName;
  bool _plateCountsApplyScheduled = false;
  Map<String, int>? _lastAppliedPlateCountsByDisplayName;

  bool _mapsEqual(Map<String, int> a, Map<String, int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  void _scheduleApplyPlateCountsAfterFrame(Map<String, int> countsByDisplayName) {
    _pendingPlateCountsByDisplayName = countsByDisplayName;

    if (_plateCountsApplyScheduled) return;
    _plateCountsApplyScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _plateCountsApplyScheduled = false;
      if (!mounted) return;

      final toApply = _pendingPlateCountsByDisplayName;
      _pendingPlateCountsByDisplayName = null;
      if (toApply == null) return;

      if (_lastAppliedPlateCountsByDisplayName != null &&
          _mapsEqual(_lastAppliedPlateCountsByDisplayName!, toApply)) {
        return;
      }

      _lastAppliedPlateCountsByDisplayName = Map<String, int>.of(toApply);

      // Provider가 없는 트리에서 시트가 열리면 예외가 날 수 있으므로 방어
      try {
        final locationState = context.read<LocationState>();
        locationState.updatePlateCounts(toApply);
      } catch (_) {
        // no-op
      }
    });
  }

  /// ✅ [수정안 적용] 테이블 rows(location 기반) → LocationState.locations의 plateCount 동기화
  void _syncLocationPickerCountsFromRows(
      List<_RowVM> rows, {
        int attempt = 0,
      }) {
    if (!mounted) return;

    LocationState? locationState;
    try {
      locationState = context.read<LocationState>();
    } catch (_) {
      return;
    }

    final locations = locationState.locations;

    if (locations.isEmpty) {
      if (attempt < 10) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (!mounted) return;
          _syncLocationPickerCountsFromRows(rows, attempt: attempt + 1);
        });
      }
      return;
    }

    // 1) rows에서 location 집계
    final rawCounts = <String, int>{};
    final leafCounts = <String, int>{};

    for (final r in rows) {
      final raw = r.location.trim();
      if (raw.isEmpty) continue;

      rawCounts[raw] = (rawCounts[raw] ?? 0) + 1;

      final leaf = _leafFromRowLocation(raw);
      if (leaf.isNotEmpty) {
        leafCounts[leaf] = (leafCounts[leaf] ?? 0) + 1;
      }
    }

    // 2) LocationState.updatePlateCounts()가 기대하는 displayName 키로 맵 구성
    final countsByDisplayName = <String, int>{};

    for (final loc in locations) {
      final leaf = loc.locationName.trim();
      final parent = (loc.parent ?? '').trim();

      final displayName =
      loc.type == 'composite' ? (parent.isEmpty ? leaf : '$parent - $leaf') : leaf;

      countsByDisplayName[displayName] = rawCounts[displayName] ?? leafCounts[leaf] ?? 0;
    }

    // ✅ 3) build-phase notifyListeners 방지: post-frame으로 이연
    _scheduleApplyPlateCountsAfterFrame(countsByDisplayName);
  }

  String _leafFromRowLocation(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final idx = v.lastIndexOf(' - ');
    if (idx >= 0) return v.substring(idx + 3).trim();
    return v;
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _searchCtrl.addListener(_onSearchChangedDebounced);

    if (_isLocal) {
      _loadLocal();
    } else {
      _initRealtimeFromCache();
      _ensureCooldownTicker();
      _loadRealtimeWriteToggle();
    }
  }

  void _initRealtimeFromCache() {
    // ✅ 실시간: init에서 서버 조회 금지, area별 캐시만 즉시 반영
    final cached = _realtimeRepo.getCached(widget.area);

    _allRows = List.of(cached);
    _availableLocations = _extractLocations(_allRows);
    _rows = List.of(_allRows);

    _applyFilterAndSort();
    _loading = false;

    // ✅ [수정안] 캐시 rows → LocationPicker 카운트 동기화(post-frame)
    _syncLocationPickerCountsFromRows(_allRows);
  }

  Future<void> _loadRealtimeWriteToggle() async {
    if (!_isRealtime) return;

    setState(() => _writeToggleLoading = true);
    try {
      await _realtimeRepo.ensureWriteToggleLoaded();
    } catch (_) {
      // prefs 로드 실패는 치명적이지 않으므로 UI만 OFF로 유지
    } finally {
      if (!mounted) return;
      setState(() => _writeToggleLoading = false);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _refreshCooldownTicker?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _ensureCooldownTicker() {
    _refreshCooldownTicker?.cancel();

    if (!_isRealtime) return;
    if (!_isRefreshBlocked) return;

    _refreshCooldownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (!_isRefreshBlocked) {
        t.cancel();
      }
      setState(() {});
    });
  }

  void _onSearchChangedDebounced() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _debounceMs), () {
      if (!mounted) return;

      if (_isRealtime) {
        setState(_applyFilterAndSort);
      } else {
        _loadLocal();
      }
    });
  }

  Future<void> _loadLocal() async {
    setState(() => _loading = true);

    try {
      final rows = await _localRepo.listAll(search: _searchCtrl.text);
      if (!mounted) return;

      setState(() {
        _allRows = rows
            .map(
              (r) => _RowVM(
            plateNumber: r.plateNumber,
            location: r.location,
            createdAt: r.createdAt,
            isDepartureCompleted: r.isDepartureCompleted,
          ),
        )
            .toList();

        _applyFilterAndSort();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFailedSnackbar(context, '데이터 로드 실패: $e');
    }
  }

  /// ✅ 실시간 서버 조회는 "새로고침" 버튼에서만 수행
  /// ✅ 새로고침 1회 수행 후 30초 쿨다운(시트를 닫아도 area별로 유지)
  Future<void> _refreshRealtimeFromServer() async {
    if (!_isRealtime) return;

    // ✅ 새로고침 요청 Trace
    _trace(
      '실시간 새로고침 요청',
      meta: <String, dynamic>{
        'screen': 'parking_completed_table_sheet',
        'action': 'refresh_request',
        'area': widget.area,
        'loading': _loading,
        'blocked': _isRefreshBlocked,
        'remainingSec': _refreshRemainingSec,
        'hasFetchedFromServer': _hasFetchedFromServer,
      },
    );

    if (_loading) {
      showSelectedSnackbar(context, '이미 갱신 중입니다.');
      return;
    }

    if (_isRefreshBlocked) {
      _ensureCooldownTicker();
      showSelectedSnackbar(context, '새로고침 대기 중: ${_refreshRemainingSec}초');

      // ✅ 차단 Trace(선택)
      _trace(
        '실시간 새로고침 차단',
        meta: <String, dynamic>{
          'screen': 'parking_completed_table_sheet',
          'action': 'refresh_blocked',
          'area': widget.area,
          'remainingSec': _refreshRemainingSec,
        },
      );

      return;
    }

    _realtimeRepo.startRefreshCooldown(widget.area, const Duration(seconds: 30));
    _ensureCooldownTicker();

    setState(() => _loading = true);

    // ✅ 서버 fetch 시작 Trace(선택)
    _trace(
      '실시간 새로고침 시작',
      meta: <String, dynamic>{
        'screen': 'parking_completed_table_sheet',
        'action': 'refresh_start',
        'area': widget.area,
      },
    );

    try {
      // ✅ 핵심: 현재 area 문서만 조회
      final rows = await _realtimeRepo.fetchFromServerAndCache(widget.area);

      // ✅ [수정안] 서버 rows → LocationPicker 카운트 동기화(post-frame)
      _syncLocationPickerCountsFromRows(rows);

      if (!mounted) return;

      setState(() {
        _allRows = List.of(rows);
        _availableLocations = _extractLocations(_allRows);

        if (_selectedLocation != _locationAll && !_availableLocations.contains(_selectedLocation)) {
          _selectedLocation = _locationAll;
        }

        _applyFilterAndSort();
        _loading = false;
        _hasFetchedFromServer = true;
      });

      showSuccessSnackbar(context, '실시간 데이터를 갱신했습니다. (${widget.area})');

      // ✅ 성공 Trace(선택)
      _trace(
        '실시간 새로고침 성공',
        meta: <String, dynamic>{
          'screen': 'parking_completed_table_sheet',
          'action': 'refresh_success',
          'area': widget.area,
          'rowCount': rows.length,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFailedSnackbar(context, '실시간 갱신 실패: $e');

      // ✅ 실패 Trace(선택)
      _trace(
        '실시간 새로고침 실패',
        meta: <String, dynamic>{
          'screen': 'parking_completed_table_sheet',
          'action': 'refresh_failure',
          'area': widget.area,
          'error': e.toString(),
        },
      );
    }
  }

  List<String> _extractLocations(List<_RowVM> rows) {
    final set = <String>{};
    for (final r in rows) {
      final k = r.location.trim();
      if (k.isNotEmpty) set.add(k);
    }
    final list = set.toList()..sort();
    return list;
  }

  void _applyFilterAndSort() {
    final search = _searchCtrl.text.trim().toLowerCase();

    _rows = _allRows.where((r) {
      if (_isLocal && _hideDepartureCompleted && r.isDepartureCompleted) {
        return false;
      }

      if (_isRealtime && _selectedLocation != _locationAll) {
        if (r.location != _selectedLocation) return false;
      }

      if (_isRealtime && search.isNotEmpty) {
        final hit =
            r.plateNumber.toLowerCase().contains(search) || r.location.toLowerCase().contains(search);
        if (!hit) return false;
      }

      return true;
    }).toList();

    _sortRows();
  }

  void _sortRows() {
    _rows.sort((a, b) {
      final ca = a.createdAt;
      final cb = b.createdAt;
      if (ca == null && cb == null) return 0;
      if (ca == null) return _sortOldFirst ? 1 : -1;
      if (cb == null) return _sortOldFirst ? -1 : 1;
      final cmp = ca.compareTo(cb);
      return _sortOldFirst ? cmp : -cmp;
    });
  }

  void _toggleSortByCreatedAt() {
    setState(() {
      _sortOldFirst = !_sortOldFirst;
      _applyFilterAndSort();
    });
    showSelectedSnackbar(
      context,
      _sortOldFirst ? '입차 시각: 오래된 순으로 정렬' : '입차 시각: 최신 순으로 정렬',
    );
  }

  void _toggleHideDepartureCompleted() {
    if (!_isLocal) return;

    setState(() {
      _hideDepartureCompleted = !_hideDepartureCompleted;
      _applyFilterAndSort();
    });

    showSelectedSnackbar(
      context,
      _hideDepartureCompleted ? '출차 완료 건을 숨깁니다.' : '출차 완료 건을 다시 표시합니다.',
    );
  }

  Future<void> _clearAll() async {
    if (!_isLocal) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('테이블 비우기'),
        content: const Text('모든 기록을 삭제할까요?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    await _localRepo.clearAll();
    if (!mounted) return;

    showSuccessSnackbar(context, '전체 삭제되었습니다.');
    _loadLocal();
  }

  Future<void> _toggleRealtimeWriteEnabled(bool v) async {
    if (!_isRealtime) return;
    if (_writeToggleLoading) return;

    setState(() => _writeToggleLoading = true);
    try {
      await _realtimeRepo.setRealtimeWriteEnabled(v);
      if (!mounted) return;

      showSelectedSnackbar(
        context,
        v
            ? '이 기기에서 실시간 데이터 삽입(Write)을 ON 했습니다.'
            : '이 기기에서 실시간 데이터 삽입(Write)을 OFF 했습니다.',
      );

      // ✅ 저장 성공 Trace(선택)
      _trace(
        '실시간 삽입 토글 저장 성공',
        meta: <String, dynamic>{
          'screen': 'parking_completed_table_sheet',
          'action': 'realtime_write_toggle_saved',
          'area': widget.area,
          'value': v,
        },
      );
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '설정 저장 실패: $e');

      // ✅ 저장 실패 Trace(선택)
      _trace(
        '실시간 삽입 토글 저장 실패',
        meta: <String, dynamic>{
          'screen': 'parking_completed_table_sheet',
          'action': 'realtime_write_toggle_save_failed',
          'area': widget.area,
          'value': v,
          'error': e.toString(),
        },
      );
    } finally {
      if (!mounted) return;
      setState(() => _writeToggleLoading = false);
    }
  }

  TextStyle get _headStyle => Theme.of(context).textTheme.labelMedium!.copyWith(
    fontWeight: FontWeight.w700,
    letterSpacing: .2,
    color: _Palette.dark,
  );

  TextStyle get _cellStyle => Theme.of(context).textTheme.bodyMedium!.copyWith(
    height: 1.25,
    color: _Palette.dark.withOpacity(.9),
  );

  TextStyle get _monoStyle => _cellStyle.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
    fontFamilyFallback: const ['monospace'],
  );

  Widget _buildRowsChip(TextTheme text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.list_alt_outlined, size: 16, color: _Palette.base),
          const SizedBox(width: 6),
          Text(
            'Rows: ${_rows.length}',
            style: text.labelMedium?.copyWith(
              color: _Palette.base,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _th(
      String label, {
        double? width,
        int flex = 0,
        TextAlign align = TextAlign.left,
        bool sortable = false,
        bool sortAsc = true,
        VoidCallback? onTap,
      }) {
    final sortIcon = sortable
        ? Icon(
      sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
      size: 14,
      color: _Palette.dark.withOpacity(.8),
    )
        : null;

    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            label,
            style: _headStyle,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (sortIcon != null) ...[
          const SizedBox(width: 4),
          sortIcon,
        ],
      ],
    );

    Widget content = Align(
      alignment: _alignTo(align),
      child: labelRow,
    );

    if (onTap != null) {
      content = InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: content,
        ),
      );
    }

    final cell = Container(
      height: _headerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        border: Border(
          bottom: BorderSide(color: _Palette.light.withOpacity(.5)),
        ),
      ),
      child: content,
    );

    if (flex > 0) return Expanded(flex: flex, child: cell);
    return SizedBox(width: width, child: cell);
  }

  Widget _td(
      Widget child, {
        double? width,
        int flex = 0,
        TextAlign align = TextAlign.left,
        Color? bg,
        bool showRightBorder = false,
      }) {
    final cell = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      alignment: _alignTo(align),
      decoration: BoxDecoration(
        color: bg ?? Colors.white,
        border: Border(
          bottom: BorderSide(
            color: _Palette.light.withOpacity(.25),
            width: .7,
          ),
          right: showRightBorder
              ? BorderSide(
            color: _Palette.light.withOpacity(.25),
            width: .7,
          )
              : BorderSide.none,
        ),
      ),
      child: child,
    );

    if (flex > 0) return Expanded(flex: flex, child: cell);
    return SizedBox(width: width, child: cell);
  }

  Alignment _alignTo(TextAlign align) {
    switch (align) {
      case TextAlign.center:
        return Alignment.center;
      case TextAlign.right:
        return Alignment.centerRight;
      case TextAlign.left:
      default:
        return Alignment.centerLeft;
    }
  }

  String _fmtDate(DateTime? v) {
    if (v == null) return '';
    final y = v.year.toString().padLeft(4, '0');
    final mo = v.month.toString().padLeft(2, '0');
    final d = v.day.toString().padLeft(2, '0');
    final h = v.hour.toString().padLeft(2, '0');
    final mi = v.minute.toString().padLeft(2, '0');
    return '$y-$mo-$d $h:$mi';
  }

  Widget _buildTable(ScrollController scrollCtrl) {
    if (_loading) return const ExpandedLoading();

    if (_rows.isEmpty) {
      if (_isRealtime && !_hasFetchedFromServer && _allRows.isEmpty) {
        return const ExpandedEmpty(
          message: '캐시된 데이터가 없습니다.\n오른쪽 위 새로고침을 눌러 실시간 데이터를 불러오세요.',
        );
      }
      return ExpandedEmpty(
        message: _isLocal ? '기록이 없습니다.' : '표시할 입차 완료 데이터가 없습니다.',
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = math.max(_tableMinWidth, constraints.maxWidth);

        return Scrollbar(
          controller: scrollCtrl,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: tableWidth,
                maxWidth: tableWidth,
              ),
              child: DecoratedBox(
                decoration: const BoxDecoration(color: Colors.white),
                child: CustomScrollView(
                  controller: scrollCtrl,
                  slivers: [
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _HeaderDelegate(
                        height: _headerHeight,
                        child: Row(
                          children: [
                            _th('Plate Number', flex: 2),
                            _th('Location', flex: 2),
                            _th(
                              'Entry Time',
                              flex: 3,
                              sortable: true,
                              sortAsc: _sortOldFirst,
                              onTap: _toggleSortByCreatedAt,
                            ),
                            _th('Departure', width: 110, align: TextAlign.center),
                          ],
                        ),
                      ),
                    ),
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (context, i) {
                          final r = _rows[i];
                          final plate = r.plateNumber;
                          final location = r.location;
                          final created = _fmtDate(r.createdAt);

                          final departed = _isLocal ? r.isDepartureCompleted : false;
                          final isEven = i.isEven;

                          Color rowBg;
                          if (departed) {
                            rowBg = Colors.green.withOpacity(.06);
                          } else {
                            rowBg = isEven ? Colors.white : _Palette.base.withOpacity(.02);
                          }

                          return Row(
                            children: [
                              _td(
                                Text(
                                  plate,
                                  style: _cellStyle.copyWith(fontWeight: FontWeight.w600),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                flex: 2,
                                bg: rowBg,
                              ),
                              _td(
                                Text(location, style: _cellStyle, overflow: TextOverflow.ellipsis),
                                flex: 2,
                                bg: rowBg,
                              ),
                              _td(
                                Text(created, style: _monoStyle, overflow: TextOverflow.ellipsis),
                                flex: 3,
                                bg: rowBg,
                              ),
                              _td(
                                Icon(
                                  departed ? Icons.check_circle : Icons.radio_button_unchecked,
                                  size: 18,
                                  color: departed ? Colors.teal : Colors.grey.shade400,
                                ),
                                width: 110,
                                align: TextAlign.center,
                                bg: rowBg,
                              ),
                            ],
                          );
                        },
                        childCount: _rows.length,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRealtimeLocationFilter(ColorScheme cs, TextTheme text) {
    final disabled = _loading || _availableLocations.isEmpty;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Palette.light.withOpacity(.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          const Icon(Icons.place_outlined, size: 16, color: _Palette.base),
          const SizedBox(width: 6),
          Text(
            '주차구역:',
            style: text.labelMedium?.copyWith(
              color: _Palette.base,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedLocation,
                isDense: true,
                isExpanded: true,
                icon: Icon(Icons.expand_more, color: cs.outline),
                items: <String>[_locationAll, ..._availableLocations].map((v) {
                  return DropdownMenuItem<String>(
                    value: v,
                    child: Text(
                      v,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium?.copyWith(
                        color: disabled ? cs.outline : _Palette.dark,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
                onChanged: disabled
                    ? null
                    : (v) {
                  if (v == null) return;
                  setState(() {
                    _selectedLocation = v;
                    _applyFilterAndSort();
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealtimeWriteToggle(ColorScheme cs, TextTheme text) {
    final disabled = _writeToggleLoading;
    final on = _realtimeRepo.isRealtimeWriteEnabled;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Palette.light.withOpacity(.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.max,
        children: [
          const Icon(Icons.edit_note_outlined, size: 16, color: _Palette.base),
          const SizedBox(width: 6),
          Text(
            '삽입:',
            style: text.labelMedium?.copyWith(
              color: _Palette.base,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            on ? 'ON' : 'OFF',
            style: text.labelMedium?.copyWith(
              color: on ? Colors.teal : cs.outline,
              fontWeight: FontWeight.w800,
              letterSpacing: .2,
            ),
          ),
          const Spacer(),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: on,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: disabled
                  ? null
                  : (v) {
                // ✅ 토글 클릭 Trace 기록(의도된 값 포함)
                _trace(
                  '실시간 삽입 토글 클릭',
                  meta: <String, dynamic>{
                    'screen': 'parking_completed_table_sheet',
                    'action': 'realtime_write_toggle_tap',
                    'area': widget.area,
                    'value': v,
                    'prevValue': on,
                  },
                );
                _toggleRealtimeWriteEnabled(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(ColorScheme cs) {
    return TextField(
      controller: _searchCtrl,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: '번호판 또는 주차 구역으로 검색',
        prefixIcon: Icon(Icons.search, color: _Palette.dark.withOpacity(.7)),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
          icon: Icon(Icons.clear, color: _Palette.dark.withOpacity(.7)),
          onPressed: () {
            _searchCtrl.clear();
            if (_isRealtime) {
              setState(_applyFilterAndSort);
            } else {
              _loadLocal();
            }
          },
        ),
        filled: true,
        fillColor: _Palette.base.withOpacity(.03),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final refreshTooltip =
    _loading ? '갱신 중…' : (_isRefreshBlocked ? '대기 중: ${_refreshRemainingSec}초' : '새로고침(서버 조회)');

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.description,
                    style: text.bodySmall?.copyWith(color: cs.outline),
                  ),
                ),
                if (_isRealtime)
                  IconButton(
                    tooltip: refreshTooltip,
                    onPressed: _loading
                        ? null
                        : () {
                      // ✅ 새로고침 아이콘 클릭 Trace 기록(즉시)
                      _trace(
                        '실시간 새로고침 아이콘 클릭',
                        meta: <String, dynamic>{
                          'screen': 'parking_completed_table_sheet',
                          'action': 'refresh_icon_tap',
                          'area': widget.area,
                          'blocked': _isRefreshBlocked,
                          'remainingSec': _refreshRemainingSec,
                        },
                      );
                      _refreshRealtimeFromServer();
                    },
                    icon: Icon(
                      Icons.refresh,
                      color: (_loading || _isRefreshBlocked) ? cs.outline.withOpacity(.5) : cs.outline,
                    ),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                if (_isRealtime) ...[
                  Expanded(
                    flex: 5,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: _loading ? const SizedBox.shrink() : _buildRowsChip(text),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 5,
                    child: _buildRealtimeWriteToggle(cs, text),
                  ),
                ] else ...[
                  if (!_loading)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _buildRowsChip(text),
                    ),
                  const Spacer(),
                  IconButton(
                    tooltip: _hideDepartureCompleted ? '출차 완료 포함하여 보기' : '출차 완료 숨기기',
                    onPressed: (_allRows.isEmpty && !_hideDepartureCompleted) ? null : _toggleHideDepartureCompleted,
                    icon: Icon(
                      _hideDepartureCompleted ? Icons.visibility_off : Icons.visibility,
                      color: _hideDepartureCompleted ? Colors.teal : cs.outline,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton.filledTonal(
                    tooltip: '전체 비우기',
                    style: IconButton.styleFrom(
                      backgroundColor: cs.errorContainer.withOpacity(
                        (_rows.isEmpty) ? 0.12 : 0.2,
                      ),
                    ),
                    onPressed: _rows.isEmpty ? null : _clearAll,
                    icon: Icon(
                      Icons.delete_sweep,
                      color: _rows.isEmpty ? cs.outline : cs.error,
                      size: 20,
                    ),
                  ),
                ],
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _isRealtime
                ? Row(
              children: [
                Expanded(
                  flex: 5,
                  child: _buildRealtimeLocationFilter(cs, text),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 5,
                  child: _buildSearchField(cs),
                ),
              ],
            )
                : _buildSearchField(cs),
          ),

          const Divider(height: 1),
          Expanded(child: _buildTable(_scrollCtrl)),
        ],
      ),
    );
  }
}

/// ─────────────────────────
/// Firestore view repository
/// - ✅ "옵션 A": 캐시만 노출 + 서버 조회는 명시적 호출(새로고침)에서만
/// - ✅ area별 문서만 조회(doc(area))
/// - ✅ area별 캐시/쿨다운 분리 (지역 섞임 방지)
/// - ✅ 실시간 "데이터 삽입(write) ON/OFF"는 SharedPreferences로 기기 로컬 영속 저장
/// ─────────────────────────
class _ParkingCompletedViewRepository {
  static const String _collection = 'parking_completed_view';
  final FirebaseFirestore _firestore;

  _ParkingCompletedViewRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static final Map<String, List<_RowVM>> _cacheByArea = <String, List<_RowVM>>{};
  static final Map<String, DateTime> _cachedAtByArea = <String, DateTime>{};

  static final Map<String, DateTime> _refreshBlockedUntilByArea = <String, DateTime>{};

  static const String _prefsKeyRealtimeWriteEnabled = 'parking_completed_realtime_write_enabled_v1';
  static SharedPreferences? _prefs;
  static bool _prefsLoaded = false;
  static bool _realtimeWriteEnabled = false; // 기본 OFF

  List<_RowVM> getCached(String area) {
    final a = area.trim();
    return List<_RowVM>.of(_cacheByArea[a] ?? const <_RowVM>[]);
  }

  DateTime? cachedAtOf(String area) {
    final a = area.trim();
    return _cachedAtByArea[a];
  }

  bool isRefreshBlocked(String area) {
    final a = area.trim();
    final until = _refreshBlockedUntilByArea[a];
    return until != null && DateTime.now().isBefore(until);
  }

  int refreshRemainingSec(String area) {
    if (!isRefreshBlocked(area)) return 0;
    final a = area.trim();
    final until = _refreshBlockedUntilByArea[a]!;
    final s = until.difference(DateTime.now()).inSeconds;
    return s < 0 ? 0 : s + 1;
  }

  void startRefreshCooldown(String area, Duration d) {
    final a = area.trim();
    if (a.isEmpty) return;
    _refreshBlockedUntilByArea[a] = DateTime.now().add(d);
  }

  Future<void> ensureWriteToggleLoaded() async {
    if (_prefsLoaded) return;
    _prefs = await SharedPreferences.getInstance();
    _realtimeWriteEnabled = _prefs!.getBool(_prefsKeyRealtimeWriteEnabled) ?? false;
    _prefsLoaded = true;
  }

  bool get isRealtimeWriteEnabled => _realtimeWriteEnabled;

  Future<void> setRealtimeWriteEnabled(bool v) async {
    await ensureWriteToggleLoaded();
    _realtimeWriteEnabled = v;
    await _prefs!.setBool(_prefsKeyRealtimeWriteEnabled, v);
  }

  DateTime? _toDate(dynamic v) {
    if (v is Timestamp) return v.toDate();
    return null;
  }

  String _normalizeLocation(String? raw) {
    final v = (raw ?? '').trim();
    return v.isEmpty ? '미지정' : v;
  }

  Future<List<_RowVM>> fetchFromServerAndCache(String area) async {
    final a = area.trim();
    if (a.isEmpty) {
      return const <_RowVM>[];
    }

    final docSnap = await _firestore.collection(_collection).doc(a).get();

    if (!docSnap.exists) {
      _cacheByArea[a] = const <_RowVM>[];
      _cachedAtByArea[a] = DateTime.now();
      return const <_RowVM>[];
    }

    final data = docSnap.data() ?? <String, dynamic>{};

    final out = <_RowVM>[];

    final items = data['items'];
    if (items is Map) {
      for (final entry in items.entries) {
        final plateDocId = entry.key?.toString() ?? '';
        final v = entry.value;

        if (v is! Map) continue;
        final m = Map<String, dynamic>.from(v);

        final plateNumber = (m['plateNumber'] as String?) ?? _fallbackPlateFromDocId(plateDocId);
        final location = _normalizeLocation(m['location'] as String?);
        final createdAt = _toDate(m['parkingCompletedAt']) ?? _toDate(m['updatedAt']);

        if (plateNumber.isEmpty) continue;

        out.add(
          _RowVM(
            plateNumber: plateNumber,
            location: location,
            createdAt: createdAt,
            isDepartureCompleted: false,
          ),
        );
      }
    }

    _cacheByArea[a] = List<_RowVM>.of(out);
    _cachedAtByArea[a] = DateTime.now();

    return out;
  }

  String _fallbackPlateFromDocId(String docId) {
    final idx = docId.lastIndexOf('_');
    if (idx > 0) return docId.substring(0, idx);
    return docId;
  }
}

// ───────────────────────── SliverPinned Header Delegate ─────────────────────────
class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final Widget child;

  _HeaderDelegate({
    required this.height,
    required this.child,
  });

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final showShadow = overlapsContent || shrinkOffset > 0;
    return Material(
      elevation: showShadow ? 1.5 : 0,
      shadowColor: Colors.black26,
      child: child,
    );
  }

  @override
  bool shouldRebuild(covariant _HeaderDelegate oldDelegate) {
    return oldDelegate.height != height || oldDelegate.child != child;
  }
}

// ───────────────────────── helper widgets ─────────────────────────

class ExpandedLoading extends StatelessWidget {
  const ExpandedLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(_Palette.base),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '데이터를 불러오는 중입니다…',
            style: text.bodySmall?.copyWith(color: cs.outline),
          ),
        ],
      ),
    );
  }
}

class ExpandedEmpty extends StatelessWidget {
  final String message;

  const ExpandedEmpty({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.inbox_outlined,
              size: 40,
              color: cs.outline,
            ),
            const SizedBox(height: 10),
            Text(
              '기록이 없습니다',
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: _Palette.dark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                color: cs.outline,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
