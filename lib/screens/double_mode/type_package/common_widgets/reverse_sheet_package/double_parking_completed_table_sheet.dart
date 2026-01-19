import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';

// ✅ 현재 로그인 계정의 currentArea / 전역 AreaState 접근
import '../../../../../../states/user/user_state.dart';
import '../../../../../../states/area/area_state.dart';

// ✅ LocationState(구역별 plateCount 반영용)
import '../../../../../../states/location/location_state.dart';

import '../../../../../../utils/snackbar_helper.dart';
import 'repositories/double_parking_completed_repository.dart';
import 'ui/double_reverse_page_top_sheet.dart';

// ✅ Trace 기록용 Recorder
import '../../../../../../screens/hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

const String _kLocationAll = '전체';

/// ✅ 실시간 탭 진입 게이트(ON/OFF)
/// - 기본 OFF
/// - 앱 재실행 후에도 유지(SharedPreferences)
class ParkingCompletedRealtimeTabGate {
  static const String _prefsKeyRealtimeTabEnabled =
      'parking_completed_realtime_tab_enabled_v1';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyRealtimeTabEnabled) ?? false; // 기본 OFF
  }

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyRealtimeTabEnabled, v);
  }
}

/// Deep Blue 팔레트
class _Palette {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

/// ✅ GlobalKey 대체: 탭 컨트롤러(탭 탭 시 refresh를 부모에서 호출)
class _RealtimeTabController {
  Future<void> Function()? _refreshUser;

  void _bindRefresh(Future<void> Function() refreshUser) {
    _refreshUser = refreshUser;
  }

  void _unbind() {
    _refreshUser = null;
  }

  bool get isBound => _refreshUser != null;

  Future<void> refreshUser() async {
    final f = _refreshUser;
    if (f == null) return;
    await f();
  }
}

/// 👉 역 Top Sheet로 "Parking Completed 로컬/실시간 테이블" 열기 헬퍼
Future<void> showDoubleParkingCompletedTableTopSheet(BuildContext context) async {
  final userArea = context.read<UserState>().currentArea.trim();
  final stateArea = context.read<AreaState>().currentArea.trim();
  final area = userArea.isNotEmpty ? userArea : stateArea;

  if (area.isEmpty) {
    showFailedSnackbar(context, '현재 지역(currentArea)이 설정되지 않았습니다.');
    return;
  }

  await showDoubleReversePageTopSheet(
    context: context,
    maxHeightFactor: 0.95,
    builder: (_) => DoubleParkingCompletedTableSheet(area: area),
  );
}

/// 로컬(SQLite) + 실시간(Firestore view) 탭 제공
class DoubleParkingCompletedTableSheet extends StatefulWidget {
  final String area;

  const DoubleParkingCompletedTableSheet({
    super.key,
    required this.area,
  });

  @override
  State<DoubleParkingCompletedTableSheet> createState() =>
      _DoubleParkingCompletedTableSheetState();
}

enum _TableMode { local, realtime }

class _DoubleParkingCompletedTableSheetState
    extends State<DoubleParkingCompletedTableSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  bool _realtimeTabEnabled = false; // 기본 OFF
  bool _gateLoaded = false;

  // ✅ 탭별 refresh 바인딩(갱신 버튼 삭제 -> 탭 탭 시 갱신)
  final _RealtimeTabController _localCtrl = _RealtimeTabController();
  final _RealtimeTabController _realtimeCtrl = _RealtimeTabController();

  // ✅ 하단 삽입(Write) 토글(실시간 탭에서만 의미)
  final _ParkingCompletedViewRepository _writeRepo = _ParkingCompletedViewRepository();
  bool _writeLoaded = false;
  bool _writeLoading = false;
  bool _writeOn = false;

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
    _tabCtrl.addListener(() {
      if (!mounted) return;
      setState(() {}); // 헤더 타이틀 + footer 토글 활성화 상태 동기화
    });

    _loadGate();
    _loadWriteToggle();
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

  Future<void> _loadWriteToggle() async {
    setState(() => _writeLoading = true);
    try {
      await _writeRepo.ensureWriteToggleLoaded();
      if (!mounted) return;
      setState(() {
        _writeOn = _writeRepo.isRealtimeWriteEnabled;
        _writeLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _writeLoaded = true);
    } finally {
      if (!mounted) return;
      setState(() => _writeLoading = false);
    }
  }

  bool get _isRealtimeSelected => _tabCtrl.index == 1;

  // ✅ 탭 탭 시 해당 탭 갱신
  void _requestRefreshForIndex(int index) {
    final ctrl = (index == 0) ? _localCtrl : _realtimeCtrl;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // 실시간 탭은 게이트가 켜져 있어야 함
      if (index == 1 && !_realtimeTabEnabled) return;

      if (ctrl.isBound) {
        await ctrl.refreshUser();
        return;
      }

      // TabBarView lazy-build 대비 1회 재시도
      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      await ctrl.refreshUser();
    });
  }

  void _onTapTab(int index) {
    _trace(
      '입차 완료 테이블 탭 클릭(탭=갱신)',
      meta: <String, dynamic>{
        'screen': 'double_parking_completed_table_sheet',
        'action': 'tab_tap_refresh',
        'tabIndex': index,
        'tab': index == 0 ? 'local' : 'realtime',
        'realtimeEnabled': _realtimeTabEnabled,
        'area': widget.area,
      },
    );

    if (!_gateLoaded) {
      showSelectedSnackbar(context, '설정 확인 중입니다.');
      return;
    }

    if (index == 1 && !_realtimeTabEnabled) {
      _trace(
        '실시간 탭 차단',
        meta: <String, dynamic>{
          'screen': 'double_parking_completed_table_sheet',
          'action': 'tab_blocked',
          'tabIndex': 1,
          'area': widget.area,
          'reason': 'realtime_tab_gate_off',
        },
      );

      HapticFeedback.selectionClick();
      _tabCtrl.animateTo(0);

      // “탭 탭 = 갱신” 정책 일관성: 차단되어 로컬로 복귀하면 로컬도 갱신
      _requestRefreshForIndex(0);
      return;
    }

    _tabCtrl.animateTo(index);
    _requestRefreshForIndex(index);
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
        Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Future<void> _toggleWriteForCurrentTab(bool v) async {
    if (_writeLoading) return;
    if (!_writeLoaded) return;
    if (!_gateLoaded) return;

    // 로컬 탭에서는 의미 없음
    if (!_isRealtimeSelected) {
      HapticFeedback.selectionClick();
      return;
    }

    // 실시간 탭이 비활성화면 차단
    if (!_realtimeTabEnabled) {
      HapticFeedback.selectionClick();
      showSelectedSnackbar(context, '실시간 탭이 비활성화되어 있습니다.');
      return;
    }

    setState(() => _writeLoading = true);

    try {
      await _writeRepo.setRealtimeWriteEnabled(v);
      _writeOn = _writeRepo.isRealtimeWriteEnabled;

      if (!mounted) return;
      showSelectedSnackbar(
        context,
        v
            ? '이 기기에서 입차 완료 실시간 삽입(Write)을 ON 했습니다.'
            : '이 기기에서 입차 완료 실시간 삽입(Write)을 OFF 했습니다.',
      );

      _trace(
        '실시간 삽입 토글 저장',
        meta: <String, dynamic>{
          'screen': 'double_parking_completed_table_sheet',
          'action': 'realtime_write_toggle_saved',
          'area': widget.area,
          'value': v,
        },
      );
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '설정 저장 실패: $e');
    } finally {
      if (!mounted) return;
      setState(() => _writeLoading = false);
    }
  }

  Widget _buildTopHeader(TextTheme textTheme, ColorScheme cs) {
    final title = _isRealtimeSelected ? '입차 완료 테이블(실시간)' : '입차 완료 테이블(로컬)';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
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
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _Palette.dark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '지역: ${widget.area}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: cs.outline),
                ),
              ],
            ),
          ),
          if (!_gateLoaded || !_writeLoaded) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2.2,
                valueColor:
                AlwaysStoppedAnimation<Color>(_Palette.base.withOpacity(.9)),
              ),
            ),
          ],
          const SizedBox(width: 6),
          IconButton(
            tooltip: '닫기',
            onPressed: () => Navigator.of(context).maybePop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterWriteToggle(ColorScheme cs, TextTheme text) {
    final isLocal = !_isRealtimeSelected;

    final enabled = _gateLoaded &&
        _writeLoaded &&
        _realtimeTabEnabled &&
        !isLocal &&
        !_writeLoading;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Palette.light.withOpacity(.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.edit_note_outlined, size: 16, color: _Palette.base),
          const SizedBox(width: 6),
          Text(
            '삽입:',
            style: text.labelMedium?.copyWith(
              color: _Palette.base,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            isLocal ? '-' : (_writeOn ? 'ON' : 'OFF'),
            style: text.labelMedium?.copyWith(
              color: isLocal ? cs.outline : (_writeOn ? Colors.teal : cs.outline),
              fontWeight: FontWeight.w900,
              letterSpacing: .2,
            ),
          ),
          const SizedBox(width: 6),
          Transform.scale(
            scale: 0.85,
            child: Switch(
              value: _writeOn,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              onChanged: enabled ? (v) => _toggleWriteForCurrentTab(v) : null,
            ),
          ),
        ],
      ),
    );
  }

  // ✅ 하단 바: 삽입 토글 + 탭 (갱신 버튼 없음)
  Widget _buildBottomBar(ColorScheme cs, TextTheme text) {
    return SafeArea(
      top: false,
      left: false,
      right: false,
      bottom: true,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: cs.outline.withOpacity(.15))),
        ),
        child: Row(
          children: [
            _buildFooterWriteToggle(cs, text),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                height: 48,
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
                  labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                  tabs: [
                    Tab(child: _tabLabel(text: '로컬', enabled: true)),
                    Tab(child: _tabLabel(text: '실시간', enabled: _realtimeTabEnabled)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
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
            _buildTopHeader(textTheme, cs),
            const Divider(height: 1),

            // ✅ 스와이프 전환 비활성(탭 탭=갱신 정책 일관)
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _ParkingCompletedTableTab(
                    controller: _localCtrl,
                    mode: _TableMode.local,
                    description: '하단 “로컬” 탭을 탭하면 로컬 데이터가 재로드됩니다. 하루 업무가 끝나면 꼭 휴지통을 눌러 데이터를 비워주세요.',
                    area: widget.area,
                  ),
                  _realtimeTabEnabled
                      ? _ParkingCompletedTableTab(
                    controller: _realtimeCtrl,
                    mode: _TableMode.realtime,
                    description: '하단 “실시간” 탭을 탭하면 실시간 데이터가 갱신됩니다. 잦은 갱신은 앱에 무리를 줍니다.',
                    area: widget.area,
                  )
                      : const _RealtimeTabLockedPanel(),
                ],
              ),
            ),

            // ✅ 하단 고정 바(삽입 + 탭)
            _buildBottomBar(cs, textTheme),
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

/// UI 렌더링 Row VM
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
/// - ✅ Refresh 버튼 제거
/// - ✅ controller 바인딩: 탭 탭 시 (로컬=재로드, 실시간=서버 갱신)
/// - ✅ Write 토글 제거(footer로 이동)
/// ─────────────────────────────────────────────────────────
class _ParkingCompletedTableTab extends StatefulWidget {
  final _RealtimeTabController controller;
  final _TableMode mode;
  final String description;
  final String area;

  const _ParkingCompletedTableTab({
    required this.controller,
    required this.mode,
    required this.description,
    required this.area,
  });

  @override
  State<_ParkingCompletedTableTab> createState() =>
      _ParkingCompletedTableTabState();
}

class _ParkingCompletedTableTabState extends State<_ParkingCompletedTableTab>
    with AutomaticKeepAliveClientMixin {
  final _localRepo = DoubleParkingCompletedRepository();
  final _realtimeRepo = _ParkingCompletedViewRepository();

  bool _loading = true;

  List<_RowVM> _allRows = [];
  List<_RowVM> _rows = [];

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  static const int _debounceMs = 300;

  final ScrollController _scrollCtrl = ScrollController();

  static const double _tableMinWidth = 720;
  static const double _headerHeight = 44;

  bool _sortOldFirst = true;
  bool _hideDepartureCompleted = false;

  bool get _isLocal => widget.mode == _TableMode.local;
  bool get _isRealtime => widget.mode == _TableMode.realtime;

  static const String _locationAll = _kLocationAll;
  String _selectedLocation = _locationAll;
  List<String> _availableLocations = [];

  bool _hasFetchedFromServer = false;
  Timer? _refreshCooldownTicker;

  bool get _isRefreshBlocked => _realtimeRepo.isRefreshBlocked(widget.area);
  int get _refreshRemainingSec => _realtimeRepo.refreshRemainingSec(widget.area);

  @override
  bool get wantKeepAlive => true;

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  // LocationState update (post-frame)
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

      try {
        final locationState = context.read<LocationState>();
        locationState.updatePlateCounts(toApply);
      } catch (_) {}
    });
  }

  String _leafFromRowLocation(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final idx = v.lastIndexOf(' - ');
    if (idx >= 0) return v.substring(idx + 3).trim();
    return v;
  }

  void _syncLocationPickerCountsFromRows(List<_RowVM> rows, {int attempt = 0}) {
    if (!mounted) return;

    LocationState locationState;
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

    final countsByDisplayName = <String, int>{};

    for (final loc in locations) {
      final leaf = loc.locationName.trim();
      final parent = (loc.parent ?? '').trim();
      final displayName =
      loc.type == 'composite' ? (parent.isEmpty ? leaf : '$parent - $leaf') : leaf;

      countsByDisplayName[displayName] = rawCounts[displayName] ?? leafCounts[leaf] ?? 0;
    }

    _scheduleApplyPlateCountsAfterFrame(countsByDisplayName);
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
      if (!_isRefreshBlocked) t.cancel();
      setState(() {});
    });
  }

  @override
  void initState() {
    super.initState();

    _searchCtrl.addListener(_onSearchChangedDebounced);

    // ✅ controller 바인딩: 탭 탭 시 실행될 “갱신” 정의
    widget.controller._bindRefresh(() async {
      if (_isLocal) {
        await _loadLocal();
      } else {
        await _refreshRealtimeFromServer();
      }
    });

    if (_isLocal) {
      _loadLocal();
    } else {
      // 실시간: init에서 서버 조회 금지, 캐시만 즉시 반영
      final cached = _realtimeRepo.getCached(widget.area);
      _allRows = List.of(cached);
      _availableLocations = _extractLocations(_allRows);
      _rows = List.of(_allRows);
      _applyFilterAndSort();
      _loading = false;

      _syncLocationPickerCountsFromRows(_allRows);
      _ensureCooldownTicker();
    }
  }

  @override
  void dispose() {
    widget.controller._unbind();
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

      _syncLocationPickerCountsFromRows(_allRows);

      _trace(
        '로컬 탭 갱신(재로드)',
        meta: <String, dynamic>{
          'screen': 'double_parking_completed_table_sheet',
          'action': 'local_reload',
          'area': widget.area,
          'rowCount': _allRows.length,
        },
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showFailedSnackbar(context, '데이터 로드 실패: $e');
    }
  }

  /// ✅ 실시간 서버 조회(탭 탭으로만 호출)
  Future<void> _refreshRealtimeFromServer() async {
    if (!_isRealtime) return;

    _trace(
      '실시간 탭 갱신(탭 탭)',
      meta: <String, dynamic>{
        'screen': 'double_parking_completed_table_sheet',
        'action': 'realtime_refresh_by_tab_tap',
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
      return;
    }

    _realtimeRepo.startRefreshCooldown(widget.area, const Duration(seconds: 30));
    _ensureCooldownTicker();

    setState(() => _loading = true);

    try {
      final rows = await _realtimeRepo.fetchFromServerAndCache(widget.area);

      _syncLocationPickerCountsFromRows(rows);

      if (!mounted) return;
      setState(() {
        _allRows = List.of(rows);
        _availableLocations = _extractLocations(_allRows);

        if (_selectedLocation != _locationAll &&
            !_availableLocations.contains(_selectedLocation)) {
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
      if (_isLocal && _hideDepartureCompleted && r.isDepartureCompleted) {
        return false;
      }

      if (_isRealtime && _selectedLocation != _locationAll) {
        if (r.location != _selectedLocation) return false;
      }

      if (_isRealtime && search.isNotEmpty) {
        final hit = r.plateNumber.toLowerCase().contains(search) ||
            r.location.toLowerCase().contains(search);
        if (!hit) return false;
      }

      return true;
    }).toList();

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

  Widget _buildCooldownChip(ColorScheme cs, TextTheme text) {
    final blocked = _isRefreshBlocked;
    final label = blocked ? '대기 ${_refreshRemainingSec}s' : 'Ready';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: blocked ? Colors.orange.withOpacity(.12) : Colors.teal.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            blocked ? Icons.timer_outlined : Icons.check_circle_outline,
            size: 16,
            color: blocked ? Colors.orange.shade800 : Colors.teal.shade700,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: text.labelMedium?.copyWith(
              color: blocked ? Colors.orange.shade800 : Colors.teal.shade700,
              fontWeight: FontWeight.w800,
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

    Widget content = Align(alignment: _alignTo(align), child: labelRow);

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
        border: Border(bottom: BorderSide(color: _Palette.light.withOpacity(.5))),
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
          bottom: BorderSide(color: _Palette.light.withOpacity(.25), width: .7),
          right: showRightBorder
              ? BorderSide(color: _Palette.light.withOpacity(.25), width: .7)
              : BorderSide.none,
        ),
      ),
      child: child,
    );

    if (flex > 0) return Expanded(flex: flex, child: cell);
    return SizedBox(width: width, child: cell);
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
          message: '캐시된 데이터가 없습니다.\n하단 “실시간” 탭을 탭하면 갱신됩니다.',
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
              setState(() => _applyFilterAndSort());
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
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // ✅ Refresh 버튼 제거(탭 탭 = 갱신)
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                if (!_loading)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _buildRowsChip(text),
                  ),
                const Spacer(),
                if (_isRealtime) ...[
                  _buildCooldownChip(cs, text),
                ] else ...[
                  IconButton(
                    tooltip: _hideDepartureCompleted ? '출차 완료 포함하여 보기' : '출차 완료 숨기기',
                    onPressed: (_allRows.isEmpty && !_hideDepartureCompleted)
                        ? null
                        : _toggleHideDepartureCompleted,
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
                      backgroundColor:
                      cs.errorContainer.withOpacity((_rows.isEmpty) ? 0.12 : 0.2),
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
                Expanded(flex: 5, child: _buildRealtimeLocationFilter(cs, text)),
                const SizedBox(width: 8),
                Expanded(flex: 5, child: _buildSearchField(cs)),
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
/// Firestore view repository (입차 완료)
/// ─────────────────────────
class _ParkingCompletedViewRepository {
  static const String _collection = 'parking_completed_view';
  final FirebaseFirestore _firestore;

  _ParkingCompletedViewRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  static final Map<String, List<_RowVM>> _cacheByArea = <String, List<_RowVM>>{};
  static final Map<String, DateTime> _cachedAtByArea = <String, DateTime>{};

  static final Map<String, DateTime> _refreshBlockedUntilByArea = <String, DateTime>{};

  static const String _prefsKeyRealtimeWriteEnabled =
      'parking_completed_realtime_write_enabled_v1';
  static SharedPreferences? _prefs;
  static bool _prefsLoaded = false;
  static bool _realtimeWriteEnabled = false;

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
    _realtimeWriteEnabled =
        _prefs!.getBool(_prefsKeyRealtimeWriteEnabled) ?? false;
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
    final out = <_RowVM>[];

    if (!docSnap.exists) {
      _cacheByArea[a] = const <_RowVM>[];
      _cachedAtByArea[a] = DateTime.now();
      return const <_RowVM>[];
    }

    final data = docSnap.data() ?? <String, dynamic>{};
    final items = data['items'];

    if (items is Map) {
      for (final entry in items.entries) {
        final plateDocId = entry.key?.toString() ?? '';
        final v = entry.value;

        if (v is! Map) continue;
        final m = Map<String, dynamic>.from(v);

        final plateNumber =
            (m['plateNumber'] as String?) ?? _fallbackPlateFromDocId(plateDocId);
        final location = _normalizeLocation(m['location'] as String?);
        final createdAt =
            _toDate(m['parkingCompletedAt']) ?? _toDate(m['updatedAt']);

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
