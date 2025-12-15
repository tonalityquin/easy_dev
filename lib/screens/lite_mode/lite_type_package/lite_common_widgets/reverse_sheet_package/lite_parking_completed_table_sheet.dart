import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

// ✅ 추가: 현재 로그인 계정의 currentArea / 전역 AreaState 접근
import '../../../../../../states/user/user_state.dart';
import '../../../../../../states/area/area_state.dart';

import '../../../../../../utils/snackbar_helper.dart';
import 'repositories/lite_parking_completed_repository.dart';
import 'ui/lite_reverse_page_top_sheet.dart';

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
Future<void> showLiteParkingCompletedTableTopSheet(BuildContext context) async {
  // 1) 로그인 계정 currentArea 우선
  final userArea = context.read<UserState>().currentArea.trim();

  // 2) 혹시 userArea가 비어 있으면 AreaState를 차선으로 사용
  final stateArea = context.read<AreaState>().currentArea.trim();

  final area = userArea.isNotEmpty ? userArea : stateArea;

  if (area.isEmpty) {
    showFailedSnackbar(context, '현재 지역(currentArea)이 설정되지 않았습니다.');
    return;
  }

  await showLiteReversePageTopSheet(
    context: context,
    maxHeightFactor: 0.95,
    builder: (_) => LiteParkingCompletedTableSheet(area: area),
  );
}

/// 로컬(SQLite) + 실시간(Firestore view) 탭 제공
/// ✅ 변경: area 주입(해당 지역 문서만 조회)
class LiteParkingCompletedTableSheet extends StatefulWidget {
  final String area;

  const LiteParkingCompletedTableSheet({
    super.key,
    required this.area,
  });

  @override
  State<LiteParkingCompletedTableSheet> createState() => _LiteParkingCompletedTableSheetState();
}

class _LiteParkingCompletedTableSheetState extends State<LiteParkingCompletedTableSheet> with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  bool _realtimeTabEnabled = false; // ✅ 기본 OFF
  bool _gateLoaded = false;

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
    if (index == 1 && !_realtimeTabEnabled) {
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
                    child: Icon(
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
                  // ✅ 진입 차단
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
                physics: _realtimeTabEnabled ? const PageScrollPhysics() : const NeverScrollableScrollPhysics(),
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

  /// ✅ 추가: 현재 지역(=로그인 계정 currentArea)
  final String area;

  const _ParkingCompletedTableTab({
    required this.mode,
    required this.description,
    required this.area,
  });

  @override
  State<_ParkingCompletedTableTab> createState() => _ParkingCompletedTableTabState();
}

class _ParkingCompletedTableTabState extends State<_ParkingCompletedTableTab> with AutomaticKeepAliveClientMixin {
  // 로컬(SQLite) repo
  final _localRepo = LiteParkingCompletedRepository();

  // 실시간(Firestore view) repo
  final _realtimeRepo = _ParkingCompletedViewRepository();

  bool _loading = true;

  /// ✅ 전체 로우(필터 전)
  /// - 실시간 탭: 캐시/서버조회 결과를 유지(필터 변경 시 재조회 금지)
  List<_RowVM> _allRows = [];

  /// ✅ 화면에 표시되는 로우(필터/정렬 후)
  List<_RowVM> _rows = [];

  final TextEditingController _searchCtrl = TextEditingController();

  // 디바운스 타이머
  Timer? _debounce;
  static const int _debounceMs = 300;

  // 세로 스크롤 컨트롤러(Top Sheet에서 직접 사용)
  final ScrollController _scrollCtrl = ScrollController();

  // 테이블 최소 너비(좁은 폰에선 가로 스크롤)
  static const double _tableMinWidth = 720;
  static const double _headerHeight = 44;

  // 정렬 상태: true = 오래된 순(ASC), false = 최신 순(DESC)
  bool _sortOldFirst = true;

  // 출차 완료 숨김 필터: true면 isDepartureCompleted == true 행을 숨김
  // - 로컬 모드에서만 의미 있음
  bool _hideDepartureCompleted = false;

  bool get _isLocal => widget.mode == _TableMode.local;
  bool get _isRealtime => widget.mode == _TableMode.realtime;

  // ✅ 실시간 탭: “주차 구역”은 area가 아니라 location
  static const String _locationAll = '전체';
  String _selectedLocation = _locationAll;
  List<String> _availableLocations = [];

  // ✅ 옵션 A: 실시간 탭은 자동 서버조회 금지
  // - 서버 조회는 오직 "새로고침" 버튼에서만 수행
  // - 캐시가 있으면 캐시 표시
  bool _hasFetchedFromServer = false;

  // ✅ 쿨다운 표시 갱신용(리오픈 시에도 repository 값을 기반으로 재시작)
  Timer? _refreshCooldownTicker;

  bool get _isRefreshBlocked => _realtimeRepo.isRefreshBlocked(widget.area);
  int get _refreshRemainingSec => _realtimeRepo.refreshRemainingSec(widget.area);

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
      setState(() {}); // 남은시간/아이콘 상태 갱신
    });
  }

  // ✅ 실시간 write 토글 로딩 상태(SharedPreferences 읽기)
  bool _writeToggleLoading = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _searchCtrl.addListener(_onSearchChangedDebounced);

    if (_isLocal) {
      // 로컬은 기존처럼 init에서 로드
      _loadLocal();
    } else {
      // ✅ 실시간: init에서 서버 조회 금지, area별 캐시만 즉시 반영
      final cached = _realtimeRepo.getCached(widget.area);
      _allRows = List.of(cached);
      _availableLocations = _extractLocations(_allRows);
      _rows = List.of(_allRows);
      _applyFilterAndSort();
      _loading = false;

      // ✅ 리오픈 시에도 쿨다운이 남아있다면 표시 갱신을 재시작
      _ensureCooldownTicker();

      // ✅ 실시간 "데이터 삽입(Write) ON/OFF" 토글 로드(기기 로컬, 기본 OFF)
      _loadRealtimeWriteToggle();
    }
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
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _refreshCooldownTicker?.cancel();
    super.dispose();
  }

  void _onSearchChangedDebounced() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _debounceMs), () {
      if (!mounted) return;

      // ✅ 로컬: 기존 유지(검색어 변경 시 repo 재조회)
      // ✅ 실시간: 재조회 금지(이미 가진 _allRows 기반으로 숨김/필터만 적용)
      if (_isRealtime) {
        setState(() => _applyFilterAndSort());
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
  /// ✅ 추가: 새로고침 1회 수행 후 30초 쿨다운(시트를 닫아도 area별로 유지)
  Future<void> _refreshRealtimeFromServer() async {
    if (!_isRealtime) return;

    if (_loading) {
      showSelectedSnackbar(context, '이미 갱신 중입니다.');
      return;
    }

    // ✅ repository에 저장된 쿨다운 기준으로 차단(시트 재오픈해도 area별로 유지)
    if (_isRefreshBlocked) {
      _ensureCooldownTicker();
      showSelectedSnackbar(context, '새로고침 대기 중: ${_refreshRemainingSec}초');
      return;
    }

    // ✅ "클릭 시점"부터 30초 시작(성공/실패 무관) — area별
    _realtimeRepo.startRefreshCooldown(widget.area, const Duration(seconds: 30));
    _ensureCooldownTicker();

    setState(() => _loading = true);

    try {
      // ✅ 핵심: 현재 area 문서만 조회
      final rows = await _realtimeRepo.fetchFromServerAndCache(widget.area);

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
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFailedSnackbar(context, '실시간 갱신 실패: $e');
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
      // ✅ 로컬 탭: 출차 완료 숨김(기존 유지)
      if (_isLocal && _hideDepartureCompleted && r.isDepartureCompleted) {
        return false;
      }

      // ✅ 실시간 탭: 주차 구역(location) 필터 (재조회 없이 숨김)
      if (_isRealtime && _selectedLocation != _locationAll) {
        if (r.location != _selectedLocation) return false;
      }

      // ✅ 실시간 탭: 검색도 재조회 없이 로컬 필터(숨김)
      if (_isRealtime && search.isNotEmpty) {
        final hit = r.plateNumber.toLowerCase().contains(search) || r.location.toLowerCase().contains(search);
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
        v ? '이 기기에서 실시간 데이터 삽입(Write)을 ON 했습니다.' : '이 기기에서 실시간 데이터 삽입(Write)을 OFF 했습니다.',
      );
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '설정 저장 실패: $e');
    } finally {
      if (!mounted) return;
      setState(() => _writeToggleLoading = false);
    }
  }

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
          Icon(Icons.list_alt_outlined, size: 16, color: _Palette.base),
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
      // ✅ 실시간 탭에서 아직 서버 갱신을 누르지 않았고 캐시도 없을 때
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

                          // 로컬만 의미 있음. 실시간(view)은 항상 false.
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: _Palette.light.withOpacity(.18),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.place_outlined, size: 16, color: _Palette.base),
          const SizedBox(width: 6),
          Text(
            '주차구역:',
            style: text.labelMedium?.copyWith(
              color: _Palette.base,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(width: 6),
          DropdownButtonHideUnderline(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: DropdownButton<String>(
                value: _selectedLocation,
                isDense: true,
                icon: Icon(Icons.expand_more, color: cs.outline),
                items: <String>[_locationAll, ..._availableLocations].map((v) {
                  return DropdownMenuItem<String>(
                    value: v,
                    child: Text(
                      v,
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
                    _applyFilterAndSort(); // ✅ 재조회 없이 숨김 처리
                  });
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ✅ 실시간 "데이터 삽입(Write)" On/Off UI (기기 로컬 저장, 기본 OFF)
  /// - 이 스위치는 "실제 Firestore write 수행 지점"에서 반드시 체크해서 동작을 막아야 의미가 있습니다.
  /// - ✅ 요구사항: 버튼 폭이 "번호판 검색 필드"와 동일한 길이가 되도록(부모 Expanded 폭을 그대로 사용)
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
        mainAxisSize: MainAxisSize.max, // ✅ Expanded 폭을 실제로 사용
        children: [
          Icon(Icons.edit_note_outlined, size: 16, color: _Palette.base),
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
          const Spacer(), // ✅ 스위치를 오른쪽 끝으로 밀어 정렬 안정화
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: on,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: disabled ? null : (v) => _toggleRealtimeWriteEnabled(v),
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
              setState(() => _applyFilterAndSort()); // ✅ 실시간: 재조회 없이 숨김
            } else {
              _loadLocal(); // ✅ 로컬: 기존 유지
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
                    onPressed: _loading ? null : _refreshRealtimeFromServer,
                    icon: Icon(
                      Icons.refresh,
                      color: (_loading || _isRefreshBlocked) ? cs.outline.withOpacity(.5) : cs.outline,
                    ),
                  ),
              ],
            ),
          ),

          // ✅ Row:2 (Rows 칩 + 삽입 토글)
          // ✅ 요구사항: "삽입 여부 버튼" 폭이 "번호판 검색 필드"와 동일한 길이(= 5:5 반반)
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
                  // 로컬: 기존 Rows + 눈/삭제 유지
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

          // ✅ 주차구역 칩을 검색 필드와 같은 행으로 내림
          // ✅ 좌(주차구역) : 우(검색) = 5 : 5
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: _isRealtime
                ? Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildRealtimeLocationFilter(cs, text),
                  ),
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
/// - ✅ area별 문서만 조회(doc(area)) 하도록 변경
/// - ✅ area별 캐시/쿨다운 분리 (지역 섞임 방지)
/// - ✅ 실시간 "데이터 삽입(write) ON/OFF"는 SharedPreferences로 기기 로컬 영속 저장(기존 유지)
/// ─────────────────────────
class _ParkingCompletedViewRepository {
  static const String _collection = 'parking_completed_view';
  final FirebaseFirestore _firestore;

  _ParkingCompletedViewRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  // ✅ area별 메모리 캐시(앱 살아있는 동안 유지)
  static final Map<String, List<_RowVM>> _cacheByArea = <String, List<_RowVM>>{};
  static final Map<String, DateTime> _cachedAtByArea = <String, DateTime>{};

  // ✅ area별 새로고침 쿨다운(앱 살아있는 동안 유지)
  static final Map<String, DateTime> _refreshBlockedUntilByArea = <String, DateTime>{};

  // ✅ 실시간 "데이터 삽입(write)" 토글(기기 로컬, 앱 재실행 후에도 유지)
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
    return s < 0 ? 0 : s + 1; // UX상 0초 바로 보이지 않도록 +1
  }

  void startRefreshCooldown(String area, Duration d) {
    final a = area.trim();
    if (a.isEmpty) return;
    _refreshBlockedUntilByArea[a] = DateTime.now().add(d);
  }

  Future<void> ensureWriteToggleLoaded() async {
    if (_prefsLoaded) return;
    _prefs = await SharedPreferences.getInstance();
    _realtimeWriteEnabled = _prefs!.getBool(_prefsKeyRealtimeWriteEnabled) ?? false; // 기본 OFF
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

  /// ✅ area 문서 1개만 조회해서 items를 파싱
  Future<List<_RowVM>> fetchFromServerAndCache(String area) async {
    final a = area.trim();
    if (a.isEmpty) {
      return const <_RowVM>[];
    }

    // ✅ 핵심 변경: 컬렉션 전체 get() 금지 → doc(a).get()로 지역 한정
    final docSnap = await _firestore.collection(_collection).doc(a).get();

    final out = <_RowVM>[];

    if (!docSnap.exists) {
      // 해당 지역 문서가 없으면 빈 캐시로 갱신
      _cacheByArea[a] = const <_RowVM>[];
      _cachedAtByArea[a] = DateTime.now();
      return const <_RowVM>[];
    }

    final data = docSnap.data() ?? <String, dynamic>{};

    // ✅ 신규 스키마: 문서 1개에 items 맵이 존재
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
    } else {
      // 하위 호환(예전 스키마) — area 문서 구조가 다르면 빈 처리(필요 시 확장)
      // (원한다면 여기에서 data['plateNumber'] 단일 문서 형태를 처리하도록 추가 가능)
    }

    // ✅ area별 캐시 갱신
    _cacheByArea[a] = List<_RowVM>.of(out);
    _cachedAtByArea[a] = DateTime.now();

    return out;
  }

  String _fallbackPlateFromDocId(String docId) {
    // docId가 {plateNumber}_{area}인 경우 plateNumber만 추출
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
  Widget build(
      BuildContext context,
      double shrinkOffset,
      bool overlapsContent,
      ) {
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
