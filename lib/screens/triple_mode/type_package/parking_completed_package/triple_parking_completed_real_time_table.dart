import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FontFeature;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../models/location_model.dart';
import '../../../../models/plate_model.dart';
import '../../../../utils/init/date_utils.dart';
import '../../../../widgets/container/plate_container_fee_calculator.dart';
import '../../../../widgets/container/plate_custom_box.dart';
import '../../../../widgets/dialog/billing_bottom_sheet/fee_calculator.dart';

import '../../../../states/area/area_state.dart';
import '../../../../states/location/location_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../utils/block_dialogs/blocking_dialog.dart';
import '../../../../utils/block_dialogs/duration_blocking_dialog.dart';
import 'widgets/triple_parking_completed_status_bottom_sheet.dart';

import '../../../hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

const String _kLocationAll = '전체';

/// ✅ 다이어로그가 너무 쉽게 닫히는 문제 방지:
/// - 배경(바깥) 탭으로 닫히지 않게 통일
const bool _kDialogBarrierDismissible = false;

/// ✅ 보기 모드: 번호판 / 구역
enum _ViewMode { plate, zone }

/// ✅ 구역 VM(트리/단독 출력용)
class _ZoneVM {
  final String fullName; // "부모 - 자식" 또는 "단독"
  final String group; // composite parent, 단독은 ''
  final String displayName; // 단독=fullName, 복합 child=leaf
  final String leaf;
  final int capacity;
  final int current;
  final int? remaining;

  const _ZoneVM({
    required this.fullName,
    required this.group,
    required this.displayName,
    required this.leaf,
    required this.capacity,
    required this.current,
    required this.remaining,
  });
}

class _ZoneGroupVM {
  final String group; // ''=단독 리스트, !=''=복합 부모 헤더
  final List<_ZoneVM> zones;
  final int totalCapacity;
  final int totalCurrent;
  final int? totalRemaining;

  const _ZoneGroupVM({
    required this.group,
    required this.zones,
    required this.totalCapacity,
    required this.totalCurrent,
    required this.totalRemaining,
  });
}

/// ✅ (분리) 출차 요청 "실시간(view) 탭" 진입 게이트(ON/OFF)
class DepartureRequestsRealtimeTabGate {
  static const String _prefsKeyRealtimeTabEnabled =
      'departure_requests_realtime_tab_enabled_v1';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyRealtimeTabEnabled) ?? false;
  }

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyRealtimeTabEnabled, v);
  }
}

/// ✅ (분리) 입차 완료 "실시간(view) 탭" 진입 게이트(ON/OFF)
class ParkingCompletedRealtimeTabGate {
  static const String _prefsKeyRealtimeTabEnabled =
      'parking_completed_realtime_tab_enabled_v1';

  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyRealtimeTabEnabled) ?? false;
  }

  static Future<void> setEnabled(bool v) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyRealtimeTabEnabled, v);
  }
}

/// ✅ 트리플 모드: 입차 완료(view) / 출차 요청(view)
enum _TabMode {
  parkingCompletedRealtime,
  departureRequestsRealtime,
}

/// UI 렌더링 Row VM
class _RowVM {
  final String plateId; // plates docId
  final String plateNumber;
  final String location;
  final DateTime? createdAt;

  const _RowVM({
    required this.plateId,
    required this.plateNumber,
    required this.location,
    required this.createdAt,
  });
}

/// ─────────────────────────────────────────────────────────
/// GlobalKey 대체: 탭 컨트롤러(탭 탭 시 refresh를 부모에서 호출)
/// ─────────────────────────────────────────────────────────
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

/// ─────────────────────────────────────────────────────────
/// Firestore view repository (탭 공용)
/// - 조회/캐시/쿨다운/파싱만 담당
/// ─────────────────────────────────────────────────────────
class _GenericViewRepository {
  final String collection;
  final String primaryTimeField;
  final FirebaseFirestore _firestore;

  _GenericViewRepository({
    required this.collection,
    required this.primaryTimeField,
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  static final Map<String, List<_RowVM>> _cacheByKey = <String, List<_RowVM>>{};
  static final Map<String, DateTime> _refreshBlockedUntilByKey =
  <String, DateTime>{};

  String _k(String area) => '$collection|${area.trim()}';

  List<_RowVM> getCached(String area) {
    final k = _k(area);
    return List<_RowVM>.of(_cacheByKey[k] ?? const <_RowVM>[]);
  }

  bool isRefreshBlocked(String area) {
    final k = _k(area);
    final until = _refreshBlockedUntilByKey[k];
    return until != null && DateTime.now().isBefore(until);
  }

  int refreshRemainingSec(String area) {
    if (!isRefreshBlocked(area)) return 0;
    final k = _k(area);
    final until = _refreshBlockedUntilByKey[k]!;
    final s = until.difference(DateTime.now()).inSeconds;
    return s < 0 ? 0 : s + 1;
  }

  void startRefreshCooldown(String area, Duration d) {
    final a = area.trim();
    if (a.isEmpty) return;
    final k = _k(a);
    _refreshBlockedUntilByKey[k] = DateTime.now().add(d);
  }

  DateTime? _toDate(dynamic v) => (v is Timestamp) ? v.toDate() : null;

  String _normalizeLocation(String? raw) {
    final v = (raw ?? '').trim();
    return v.isEmpty ? '미지정' : v;
  }

  String _fallbackPlateFromDocId(String docId) {
    final idx = docId.lastIndexOf('_');
    if (idx > 0) return docId.substring(0, idx);
    return docId;
  }

  Future<List<_RowVM>> fetchFromServerAndCache(String area) async {
    final a = area.trim();
    if (a.isEmpty) return const <_RowVM>[];

    final docSnap = await _firestore.collection(collection).doc(a).get();
    final out = <_RowVM>[];

    if (!docSnap.exists) {
      _cacheByKey[_k(a)] = const <_RowVM>[];
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
        final createdAt = _toDate(m[primaryTimeField]) ?? _toDate(m['updatedAt']);

        if (plateNumber.isEmpty) continue;

        out.add(
          _RowVM(
            plateId: plateDocId,
            plateNumber: plateNumber,
            location: location,
            createdAt: createdAt,
          ),
        );
      }
    }

    _cacheByKey[_k(a)] = List<_RowVM>.of(out);
    return out;
  }
}

/// ✅ 브랜드(ColorScheme) 기반 공통 색 헬퍼
class _Brand {
  static Color accentForMode(ColorScheme cs, _TabMode mode) {
    return (mode == _TabMode.parkingCompletedRealtime)
        ? cs.primary
        : cs.secondary;
  }

  static Color border(ColorScheme cs) => cs.outlineVariant.withOpacity(0.85);
}

/// ─────────────────────────────────────────────────────────
/// 메인: 트리플 실시간 테이블(입차완료/출차요청)
/// ─────────────────────────────────────────────────────────
class TripleParkingCompletedRealTimeTable extends StatefulWidget {
  final VoidCallback? onClose; // (호환성 유지) UI에서는 더 이상 사용하지 않음

  const TripleParkingCompletedRealTimeTable({
    super.key,
    this.onClose,
  });

  @override
  State<TripleParkingCompletedRealTimeTable> createState() =>
      _TripleParkingCompletedRealTimeTableState();
}

class _TripleParkingCompletedRealTimeTableState
    extends State<TripleParkingCompletedRealTimeTable>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  bool _pcGate = false;
  bool _depGate = false;
  bool _gatesLoaded = false;

  final _RealtimeTabController _pcCtrl = _RealtimeTabController();
  final _RealtimeTabController _depCtrl = _RealtimeTabController();

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  String get _area {
    final userArea = context.read<UserState>().currentArea.trim();
    final stateArea = context.read<AreaState>().currentArea.trim();
    return userArea.isNotEmpty ? userArea : stateArea;
  }

  @override
  void initState() {
    super.initState();

    _tabCtrl = TabController(length: 2, vsync: this);
    _tabCtrl.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    _loadGates();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  int _firstEnabledTabOr(int fallback) {
    if (_pcGate) return 0;
    if (_depGate) return 1;
    return fallback;
  }

  Future<void> _loadGates() async {
    try {
      final pc = await ParkingCompletedRealtimeTabGate.isEnabled();
      final dep = await DepartureRequestsRealtimeTabGate.isEnabled();

      if (!mounted) return;

      setState(() {
        _pcGate = pc;
        _depGate = dep;
        _gatesLoaded = true;
        _tabCtrl.index = _firstEnabledTabOr(0);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pcGate = false;
        _depGate = false;
        _gatesLoaded = true;
        _tabCtrl.index = 0;
      });
    }
  }

  bool _isTabEnabled(int idx) => (idx == 0) ? _pcGate : _depGate;

  _RealtimeTabController _controllerForIndex(int idx) {
    if (idx == 0) return _pcCtrl;
    return _depCtrl;
  }

  void _requestRefreshForIndex(int index) {
    final ctrl = _controllerForIndex(index);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!_gatesLoaded) return;
      if (!_isTabEnabled(index)) return;

      if (ctrl.isBound) {
        await ctrl.refreshUser();
        return;
      }

      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      if (!_gatesLoaded) return;
      if (!_isTabEnabled(index)) return;

      await ctrl.refreshUser();
    });
  }

  void _onTapTab(int index) {
    final tabName = (index == 0) ? 'parking_completed' : 'departure_requests';

    _trace(
      '리버스 테이블 하단 탭 클릭(탭=갱신)',
      meta: <String, dynamic>{
        'screen': 'triple_reverse_table_embedded',
        'action': 'tab_tap_refresh',
        'tabIndex': index,
        'tab': tabName,
        'parkingCompletedEnabled': _pcGate,
        'departureRequestsEnabled': _depGate,
        'area': _area,
      },
    );

    if (!_gatesLoaded) {
      showSelectedSnackbar(context, '설정 확인 중입니다.');
      return;
    }

    if (!_isTabEnabled(index)) {
      HapticFeedback.selectionClick();
      showSelectedSnackbar(
        context,
        '해당 탭이 비활성화되어 있습니다. 설정에서 ON 후 사용해 주세요.',
      );
      _tabCtrl.animateTo(_firstEnabledTabOr(_tabCtrl.index));
      return;
    }

    _requestRefreshForIndex(index);
  }

  String _descriptionForMode(_TabMode mode) {
    if (mode == _TabMode.departureRequestsRealtime) {
      return '하단 탭을 누르면 데이터가 갱신됩니다. 잦은 갱신은 앱에 무리를 줍니다. (최소 3초 간격)';
    }
    return '하단 탭을 누르면 데이터가 갱신됩니다. 잦은 갱신은 앱에 무리를 줍니다. (최소 30초 간격)';
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

  Widget _buildBottomTabBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: cs.surface,
        border: Border(top: BorderSide(color: _Brand.border(cs))),
      ),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Brand.border(cs)),
        ),
        child: TabBar(
          controller: _tabCtrl,
          onTap: _onTapTab,
          labelColor: cs.onSurface,
          unselectedLabelColor: cs.onSurfaceVariant,
          indicatorColor: cs.primary,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          tabs: [
            Tab(child: _tabLabel(text: '입차 완료', enabled: _pcGate)),
            Tab(child: _tabLabel(text: '출차 요청', enabled: _depGate)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: cs.surface,
      child: Column(
        children: [
          // ✅ 수정안 1) 상단 헤더 삭제 → 데이터 영역 확장
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              physics: const PageScrollPhysics(),
              children: [
                _pcGate
                    ? _UnifiedTableTab(
                  controller: _pcCtrl,
                  mode: _TabMode.parkingCompletedRealtime,
                  description: _descriptionForMode(
                      _TabMode.parkingCompletedRealtime),
                )
                    : const _RealtimeTabLockedPanel(
                  title: '입차 완료 실시간 탭이 비활성화되어 있습니다',
                  message:
                  '설정에서 “입차 완료 실시간 모드(탭) 사용”을 ON으로 변경한 뒤 다시 시도해 주세요.',
                ),
                _depGate
                    ? _UnifiedTableTab(
                  controller: _depCtrl,
                  mode: _TabMode.departureRequestsRealtime,
                  description:
                  _descriptionForMode(_TabMode.departureRequestsRealtime),
                )
                    : const _RealtimeTabLockedPanel(
                  title: '출차 요청 실시간 탭이 비활성화되어 있습니다',
                  message:
                  '설정에서 “출차 요청 실시간 모드(탭) 사용”을 ON으로 변경한 뒤 다시 시도해 주세요.',
                ),
              ],
            ),
          ),
          _buildBottomTabBar(cs),
        ],
      ),
    );
  }
}

class _RealtimeTabLockedPanel extends StatelessWidget {
  final String title;
  final String message;

  const _RealtimeTabLockedPanel({
    required this.title,
    required this.message,
  });

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
              title,
              textAlign: TextAlign.center,
              style: text.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// ─────────────────────────────────────────────────────────
/// 통합 탭(뷰 전용 2종) + 하이브리드 상세 팝업 + 구역보기
/// ─────────────────────────────────────────────────────────
class _UnifiedTableTab extends StatefulWidget {
  final _RealtimeTabController controller;
  final _TabMode mode;
  final String description;

  const _UnifiedTableTab({
    required this.controller,
    required this.mode,
    required this.description,
  });

  @override
  State<_UnifiedTableTab> createState() => _UnifiedTableTabState();
}

class _UnifiedTableTabState extends State<_UnifiedTableTab>
    with AutomaticKeepAliveClientMixin {
  late final _GenericViewRepository _repo;

  bool _loading = false;
  bool _hasFetchedFromServer = false;

  List<_RowVM> _allRows = <_RowVM>[];
  List<_RowVM> _rows = <_RowVM>[];

  // ✅ 일자별 No(날짜가 바뀌면 1부터)
  List<int> _displayNos = <int>[];

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  static const int _debounceMs = 250;

  static const String _locationAll = _kLocationAll;
  String _selectedLocation = _locationAll;
  List<String> _availableLocations = <String>[];

  bool _sortOldFirst = true;

  final ScrollController _scrollCtrl = ScrollController();
  Timer? _cooldownTicker;

  final Map<String, PlateModel> _plateDetailCache = <String, PlateModel>{};
  final Map<String, Future<PlateModel?>> _plateDetailInflight =
  <String, Future<PlateModel?>>{};

  bool _openingDetail = false;

  _ViewMode _viewMode = _ViewMode.plate;

  List<LocationModel> _cachedLocations = <LocationModel>[];
  int _totalCapacityFromPrefs = 0;
  String _locationsLoadedArea = '';
  bool _loadingLocationMeta = false;

  final Map<String, bool> _groupExpanded = <String, bool>{};

  String get _primaryTimeField =>
      widget.mode == _TabMode.departureRequestsRealtime
          ? 'departureRequestedAt'
          : 'parkingCompletedAt';

  String get _collection =>
      widget.mode == _TabMode.departureRequestsRealtime
          ? 'departure_requests_view'
          : 'parking_completed_view';

  Duration get _refreshCooldownDuration =>
      widget.mode == _TabMode.departureRequestsRealtime
          ? const Duration(seconds: 3)
          : const Duration(seconds: 30);

  String get _currentArea {
    final a1 = context.read<UserState>().currentArea.trim();
    final a2 = context.read<AreaState>().currentArea.trim();
    return a1.isNotEmpty ? a1 : a2;
  }

  bool get _isRefreshBlocked => _repo.isRefreshBlocked(_currentArea);
  int get _refreshRemainingSec => _repo.refreshRemainingSec(_currentArea);

  Color _accent(ColorScheme cs) => _Brand.accentForMode(cs, widget.mode);

  String _dayKey(DateTime? dt) {
    if (dt == null) return 'unknown';
    final d = dt.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();

    _repo = _GenericViewRepository(
      collection: _collection,
      primaryTimeField: _primaryTimeField,
    );

    widget.controller._bindRefresh(_refreshFromTabTap);

    _searchCtrl.addListener(_onSearchChangedDebounced);

    _allRows = List<_RowVM>.of(_repo.getCached(_currentArea));
    _availableLocations = _extractLocations(_allRows);

    _applyFilterAndSort();
    _syncLocationPickerCountsFromRows(_allRows);

    _ensureCooldownTicker();
    _ensureLocationMetaLoaded();
  }

  @override
  void dispose() {
    widget.controller._unbind();
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _cooldownTicker?.cancel();
    super.dispose();
  }

  // ─────────────────────────────────────────
  // ✅ Location meta
  // ─────────────────────────────────────────
  Future<void> _ensureLocationMetaLoaded({bool force = false}) async {
    final area = _currentArea.trim();
    if (area.isEmpty) return;

    if (!force &&
        _locationsLoadedArea == area &&
        (_cachedLocations.isNotEmpty || _totalCapacityFromPrefs > 0)) {
      return;
    }

    if (_loadingLocationMeta) return;
    _loadingLocationMeta = true;
    if (mounted) setState(() {});

    try {
      try {
        final ls = context.read<LocationState>().locations;
        if (ls.isNotEmpty) _cachedLocations = List<LocationModel>.of(ls);
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      if (_cachedLocations.isEmpty) {
        final cachedJson = prefs.getString('cached_locations_$area');
        if (cachedJson != null && cachedJson.trim().isNotEmpty) {
          final decoded = json.decode(cachedJson) as List;
          _cachedLocations = decoded
              .map(
                (e) => LocationModel.fromCacheMap(
              Map<String, dynamic>.from(e as Map),
            ),
          )
              .toList();
        }
      }

      _totalCapacityFromPrefs = prefs.getInt('total_capacity_$area') ??
          _cachedLocations.fold<int>(0, (sum, loc) => sum + loc.capacity);

      _locationsLoadedArea = area;

      for (final loc in _cachedLocations) {
        final g = _groupKeyForLocation(loc);
        if (g.isNotEmpty) {
          _groupExpanded.putIfAbsent(g, () => true);
        }
      }
    } finally {
      _loadingLocationMeta = false;
      if (mounted) setState(() {});
    }
  }

  String _groupKeyForLocation(LocationModel loc) {
    final parent = (loc.parent ?? '').trim();
    final type = (loc.type ?? '').trim();
    if (type == 'composite' && parent.isNotEmpty) return parent;
    return '';
  }

  String _displayNameForLocation(LocationModel loc) {
    final leaf = loc.locationName.trim();
    final parent = (loc.parent ?? '').trim();
    final type = (loc.type ?? '').trim();
    if (type == 'composite') return parent.isEmpty ? leaf : '$parent - $leaf';
    return leaf;
  }

  String _leafFromLocationLabel(String raw) {
    final v = raw.trim();
    if (v.isEmpty) return '';
    final idx = v.lastIndexOf(' - ');
    if (idx >= 0) return v.substring(idx + 3).trim();
    return v;
  }

  List<String> _locationOptionsForDropdown() {
    if (_viewMode == _ViewMode.zone && _cachedLocations.isNotEmpty) {
      final set = <String>{};
      for (final loc in _cachedLocations) {
        final name = _displayNameForLocation(loc).trim();
        if (name.isNotEmpty) set.add(name);
      }
      final list = set.toList()..sort();
      return list;
    }
    return _availableLocations;
  }

  Future<void> _toggleViewMode() async {
    final next =
    (_viewMode == _ViewMode.plate) ? _ViewMode.zone : _ViewMode.plate;

    setState(() {
      _viewMode = next;

      if (next == _ViewMode.plate) {
        if (_selectedLocation != _locationAll &&
            !_availableLocations.contains(_selectedLocation)) {
          _selectedLocation = _locationAll;
        }
      }
      _applyFilterAndSort();
    });

    if (next == _ViewMode.zone) {
      await _ensureLocationMetaLoaded();
      final opts = _locationOptionsForDropdown();
      if (!mounted) return;
      setState(() {
        if (_selectedLocation != _locationAll && !opts.contains(_selectedLocation)) {
          _selectedLocation = _locationAll;
        }
      });
    }
  }

  // ─────────────────────────────────────────
  // Refresh / Search / Filter
  // ─────────────────────────────────────────
  void _onSearchChangedDebounced() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: _debounceMs), () {
      if (!mounted) return;
      setState(() => _applyFilterAndSort());
    });
  }

  void _ensureCooldownTicker() {
    _cooldownTicker?.cancel();
    if (!_isRefreshBlocked) return;

    _cooldownTicker = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (!_isRefreshBlocked) t.cancel();
      setState(() {});
    });
  }

  Future<void> _refreshFromTabTap() async {
    _trace(
      '탭 탭 갱신',
      meta: <String, dynamic>{
        'screen': 'triple_reverse_table_embedded',
        'action': 'tab_tap_refresh',
        'mode': widget.mode.toString(),
        'collection': _collection,
        'area': _currentArea,
        'loading': _loading,
        'blocked': _isRefreshBlocked,
        'remainingSec': _refreshRemainingSec,
        'cooldownSec': _refreshCooldownDuration.inSeconds,
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

    _repo.startRefreshCooldown(_currentArea, _refreshCooldownDuration);
    _ensureCooldownTicker();

    setState(() => _loading = true);

    try {
      final rows = await _repo.fetchFromServerAndCache(_currentArea);
      _syncLocationPickerCountsFromRows(rows);

      if (!mounted) return;
      setState(() {
        _allRows = List<_RowVM>.of(rows);
        _availableLocations = _extractLocations(_allRows);

        if (_viewMode == _ViewMode.plate &&
            _selectedLocation != _locationAll &&
            !_availableLocations.contains(_selectedLocation)) {
          _selectedLocation = _locationAll;
        }

        _applyFilterAndSort();
        _loading = false;
        _hasFetchedFromServer = true;
      });

      if (_viewMode == _ViewMode.zone) {
        await _ensureLocationMetaLoaded();
      }

      showSuccessSnackbar(context, '실시간 데이터를 갱신했습니다. ($_currentArea)');
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
    if (_viewMode != _ViewMode.plate) {
      _rows = List<_RowVM>.of(_allRows);
      _displayNos = <int>[];
      return;
    }

    final search = _searchCtrl.text.trim().toLowerCase();

    _rows = _allRows.where((r) {
      if (_selectedLocation != _locationAll) {
        if (r.location != _selectedLocation) return false;
      }
      if (search.isNotEmpty) {
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

    _displayNos = List<int>.filled(_rows.length, 0);
    String prevKey = '';
    int seq = 0;
    for (int i = 0; i < _rows.length; i++) {
      final k = _dayKey(_rows[i].createdAt);
      if (k != prevKey) {
        prevKey = k;
        seq = 1;
      } else {
        seq += 1;
      }
      _displayNos[i] = seq;
    }
  }

  void _toggleSortByNo() {
    setState(() {
      _sortOldFirst = !_sortOldFirst;
      _applyFilterAndSort();
    });
    showSelectedSnackbar(context, _sortOldFirst ? '정렬: 오래된 순' : '정렬: 최신 순');
  }

  // ─────────────────────────────────────────
  // Zone build & dialog
  // ─────────────────────────────────────────
  _ZoneVM _zoneVmFromLocation(LocationModel loc) {
    final fullName = _displayNameForLocation(loc).trim();
    final group = _groupKeyForLocation(loc);
    final leaf = loc.locationName.trim();
    final displayName = group.isEmpty ? fullName : leaf;

    return _ZoneVM(
      fullName: fullName,
      group: group,
      displayName: displayName,
      leaf: leaf,
      capacity: loc.capacity,
      current: 0,
      remaining: null,
    );
  }

  bool _isCompositeLeafUnique(String leaf) {
    final l = leaf.trim();
    if (l.isEmpty) return true;

    final parents = <String>{};
    for (final loc in _cachedLocations) {
      final type = (loc.type ?? '').trim();
      final parent = (loc.parent ?? '').trim();
      final locLeaf = loc.locationName.trim();
      if (type == 'composite' && parent.isNotEmpty && locLeaf == l) {
        parents.add(parent);
      }
    }
    return parents.length <= 1;
  }

  bool _matchRowToZone(_RowVM r, _ZoneVM z) {
    final raw = r.location.trim();
    if (raw.isEmpty) return false;

    final full = z.fullName.trim();
    final group = z.group.trim();
    final leaf = z.leaf.trim();

    if (full.isNotEmpty && raw == full) return true;

    if (group.isEmpty) {
      if (leaf.isNotEmpty && raw == leaf) return true;
      return false;
    }

    if (leaf.isEmpty) return false;

    if (raw.contains(' - ')) {
      if (!raw.startsWith('$group - ')) return false;
      return _leafFromLocationLabel(raw) == leaf;
    }

    if (raw == leaf && _isCompositeLeafUnique(leaf)) return true;
    return false;
  }

  List<_RowVM> _rowsForZone(_ZoneVM z) {
    final zn = z.fullName.trim();
    if (zn == '기타/미지정') {
      final metaVms = _cachedLocations
          .map(_zoneVmFromLocation)
          .where((e) => e.fullName.trim().isNotEmpty)
          .toList();

      final out = <_RowVM>[];
      for (final r in _allRows) {
        var matched = false;
        for (final vm in metaVms) {
          if (_matchRowToZone(r, vm)) {
            matched = true;
            break;
          }
        }
        if (!matched) out.add(r);
      }
      return out;
    }

    final out = <_RowVM>[];
    for (final r in _allRows) {
      if (_matchRowToZone(r, z)) out.add(r);
    }
    return out;
  }

  Future<void> _openZonePlatesDialog(_ZoneVM z) async {
    if (!mounted) return;

    _trace(
      '구역 탭(번호판 목록 다이얼로그)',
      meta: <String, dynamic>{
        'screen': 'triple_reverse_table_embedded',
        'action': 'zone_tap_open_dialog',
        'area': _currentArea,
        'mode': widget.mode.toString(),
        'zoneFullName': z.fullName,
        'zoneGroup': z.group,
        'zoneLeaf': z.leaf,
        'zoneCurrent': z.current,
        'zoneCapacity': z.capacity,
      },
    );

    final rows = _rowsForZone(z);

    rows.sort((a, b) {
      final ca = a.createdAt;
      final cb = b.createdAt;
      if (ca == null && cb == null) return 0;
      if (ca == null) return _sortOldFirst ? 1 : -1;
      if (cb == null) return _sortOldFirst ? -1 : 1;
      final cmp = ca.compareTo(cb);
      return _sortOldFirst ? cmp : -cmp;
    });

    final cs = Theme.of(context).colorScheme;

    await showDialog<void>(
      context: context,
      barrierDismissible: _kDialogBarrierDismissible,
      builder: (_) {
        final text = Theme.of(context).textTheme;

        final remainText = (z.remaining == null)
            ? '-'
            : (z.remaining! >= 0 ? '${z.remaining}대' : '0대');
        final capText = z.capacity > 0 ? '${z.capacity}대' : '-';

        final title = '구역: ${z.fullName}';
        final subtitle = z.fullName == '기타/미지정'
            ? '메타에 매칭되지 않는 항목 · ${rows.length}대'
            : '현재 ${rows.length}대 / 총 $capText / 잔여 $remainText';

        TextStyle monoSmall(Color color) => text.labelMedium!.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
          fontFamilyFallback: const ['monospace'],
          fontWeight: FontWeight.w900,
          color: color,
        );

        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: Colors.transparent,
              child: AlertDialog(
                backgroundColor: cs.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 8,
                insetPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                content: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              title,
                              style: text.titleMedium?.copyWith(
                                fontWeight: FontWeight.w900,
                                color: cs.onSurface,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // ✅ (다이얼로그 닫기 아이콘은 유지: 메인 닫기(X)와 별개)
                          IconButton(
                            tooltip: '닫기',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: Icon(Icons.close, color: cs.onSurface),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          subtitle,
                          style: text.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(height: 10),
                      if (rows.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 26),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_outlined,
                                  size: 40, color: cs.onSurfaceVariant),
                              const SizedBox(height: 10),
                              Text(
                                '표시할 번호판이 없습니다.',
                                style: text.bodyMedium
                                    ?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        )
                      else
                        Flexible(
                          child: Container(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                  color: _Brand.border(cs).withOpacity(0.85)),
                            ),
                            child: Scrollbar(
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: rows.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: _Brand.border(cs).withOpacity(0.5),
                                ),
                                itemBuilder: (ctx, i) {
                                  final r = rows[i];
                                  final timeText = _fmtDate(r.createdAt);

                                  return Material(
                                    color: Colors.transparent,
                                    child: InkWell(
                                      onTap: () {
                                        Navigator.of(context).pop();
                                        WidgetsBinding.instance
                                            .addPostFrameCallback((_) {
                                          if (!mounted) return;
                                          _openHybridDetailPopup(r);
                                        });
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            10, 10, 10, 10),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 30,
                                              child: Text(
                                                (i + 1)
                                                    .toString()
                                                    .padLeft(2, '0'),
                                                style: monoSmall(cs.onSurface),
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Column(
                                                crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                                children: [
                                                  Text(
                                                    r.plateNumber,
                                                    style: text.bodyMedium
                                                        ?.copyWith(
                                                      fontWeight:
                                                      FontWeight.w900,
                                                      color: cs.onSurface,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                    TextOverflow.ellipsis,
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    r.location,
                                                    style: text.bodySmall
                                                        ?.copyWith(
                                                      color: cs
                                                          .onSurfaceVariant,
                                                    ),
                                                    maxLines: 1,
                                                    overflow:
                                                    TextOverflow.ellipsis,
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 10),
                                            Text(
                                              timeText.isEmpty ? '-' : timeText,
                                              style: text.bodySmall?.copyWith(
                                                  color: cs.onSurfaceVariant),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          '항목을 탭하면 번호판 상세로 이동합니다.',
                          style: text.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<_ZoneGroupVM> _buildZoneGroupsFromCurrentData() {
    final rows = List<_RowVM>.of(_allRows);

    final rawCounts = <String, int>{};
    final leafCounts = <String, int>{};

    for (final r in rows) {
      final raw = r.location.trim();
      if (raw.isEmpty) continue;

      rawCounts[raw] = (rawCounts[raw] ?? 0) + 1;

      final leaf = _leafFromLocationLabel(raw);
      if (leaf.isNotEmpty) {
        leafCounts[leaf] = (leafCounts[leaf] ?? 0) + 1;
      }
    }

    final standalones = <_ZoneVM>[];
    final compositeByParent = <String, List<_ZoneVM>>{};

    int sumKnownCurrent = 0;

    for (final loc in _cachedLocations) {
      final fullName = _displayNameForLocation(loc).trim();
      if (fullName.isEmpty) continue;

      if (_selectedLocation != _locationAll && fullName != _selectedLocation) {
        continue;
      }

      final leaf = loc.locationName.trim();
      final cap = loc.capacity;

      final current = rawCounts[fullName] ?? leafCounts[leaf] ?? 0;
      sumKnownCurrent += current;

      final remaining = cap > 0 ? (cap - current) : null;

      final parent = _groupKeyForLocation(loc);
      final isCompositeChild = parent.isNotEmpty;

      final displayLabel = isCompositeChild ? leaf : fullName;

      final vm = _ZoneVM(
        fullName: fullName,
        group: parent,
        displayName: displayLabel,
        leaf: leaf,
        capacity: cap,
        current: current,
        remaining: remaining,
      );

      if (isCompositeChild) {
        compositeByParent.putIfAbsent(parent, () => <_ZoneVM>[]).add(vm);
      } else {
        standalones.add(vm);
      }
    }

    final unknown = rows.length - sumKnownCurrent;
    if (unknown > 0 && _selectedLocation == _locationAll) {
      standalones.add(
        _ZoneVM(
          fullName: '기타/미지정',
          group: '',
          displayName: '기타/미지정',
          leaf: '',
          capacity: 0,
          current: unknown,
          remaining: null,
        ),
      );
    }

    standalones.sort((a, b) {
      final aEtc = a.fullName == '기타/미지정';
      final bEtc = b.fullName == '기타/미지정';
      if (aEtc != bEtc) return aEtc ? 1 : -1;

      final ar = a.remaining ?? (1 << 30);
      final br = b.remaining ?? (1 << 30);
      final c = ar.compareTo(br);
      if (c != 0) return c;
      return a.displayName.compareTo(b.displayName);
    });

    final out = <_ZoneGroupVM>[];

    if (standalones.isNotEmpty) {
      final totalCap = standalones.fold<int>(0, (s, z) => s + z.capacity);
      final totalCur = standalones.fold<int>(0, (s, z) => s + z.current);
      final totalRem = totalCap > 0 ? (totalCap - totalCur) : null;

      out.add(
        _ZoneGroupVM(
          group: '',
          zones: standalones,
          totalCapacity: totalCap,
          totalCurrent: totalCur,
          totalRemaining: totalRem,
        ),
      );
    }

    final parents = compositeByParent.keys.toList()..sort();
    for (final p in parents) {
      final list = compositeByParent[p] ?? <_ZoneVM>[];

      list.sort((a, b) {
        final ar = a.remaining ?? (1 << 30);
        final br = b.remaining ?? (1 << 30);
        final c = ar.compareTo(br);
        if (c != 0) return c;
        return a.displayName.compareTo(b.displayName);
      });

      final totalCap = list.fold<int>(0, (s, z) => s + z.capacity);
      final totalCur = list.fold<int>(0, (s, z) => s + z.current);
      final totalRem = totalCap > 0 ? (totalCap - totalCur) : null;

      out.add(
        _ZoneGroupVM(
          group: p,
          zones: list,
          totalCapacity: totalCap,
          totalCurrent: totalCur,
          totalRemaining: totalRem,
        ),
      );
    }

    return out;
  }

  Widget _buildZoneTree(ColorScheme cs, TextTheme text) {
    if (_loadingLocationMeta && _cachedLocations.isEmpty) {
      return const _ExpandedLoading();
    }

    if (_cachedLocations.isEmpty) {
      return const _ExpandedEmpty(
        message: '주차구역 캐시가 없습니다.\n설정에서 주차구역 새로고침 후 다시 시도하세요.',
      );
    }

    final groups = _buildZoneGroupsFromCurrentData();

    final totalCurAll = _allRows.length;
    final totalCapAll = _totalCapacityFromPrefs;
    final totalRemAll = totalCapAll > 0 ? (totalCapAll - totalCurAll) : null;

    Widget buildZoneRow(_ZoneVM z, {required bool indented}) {
      final remainText = (z.remaining == null)
          ? '-'
          : (z.remaining! >= 0 ? '${z.remaining}대' : '0대');
      final capText = z.capacity > 0 ? '${z.capacity}대' : '-';
      final leftPad = indented ? 28.0 : 12.0;

      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _loading ? null : () => _openZonePlatesDialog(z),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(leftPad, 10, 12, 10),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                bottom: BorderSide(color: _Brand.border(cs).withOpacity(0.55)),
              ),
            ),
            child: Row(
              children: [
                if (indented) ...[
                  Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    z.displayName,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text('현재 ${z.current}대',
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 10),
                Text('총 $capText',
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 10),
                Text(
                  '잔여 $remainText',
                  style: text.bodySmall?.copyWith(
                    color: (z.remaining != null && z.remaining! <= 0)
                        ? cs.error
                        : Colors.teal.shade700,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final children = <Widget>[];

    for (final g in groups) {
      if (g.group.isEmpty) {
        for (final z in g.zones) {
          children.add(buildZoneRow(z, indented: false));
        }
        continue;
      }

      final expanded = _groupExpanded[g.group] ?? true;

      final groupRemainText = g.totalRemaining == null
          ? '-'
          : (g.totalRemaining! >= 0 ? '${g.totalRemaining}대' : '0대');

      children.add(
        Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => setState(() => _groupExpanded[g.group] = !expanded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: _Brand.border(cs).withOpacity(0.6)),
                ),
              ),
              child: Row(
                children: [
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      color: cs.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      g.group,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: cs.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('현재 ${g.totalCurrent}대',
                      style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(width: 10),
                  Text(
                    '총 ${g.totalCapacity > 0 ? "${g.totalCapacity}대" : "-"}',
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '잔여 $groupRemainText',
                    style: text.bodySmall?.copyWith(
                      color: (g.totalRemaining != null && g.totalRemaining! <= 0)
                          ? cs.error
                          : Colors.teal.shade700,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      if (expanded) {
        for (final z in g.zones) {
          children.add(buildZoneRow(z, indented: true));
        }
      }
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(color: _Brand.border(cs)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '구역별 잔여 공간',
                  style: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                totalCapAll > 0
                    ? '총 ${totalCapAll}대 / 현재 ${totalCurAll}대 / 잔여 ${totalRemAll ?? 0}대'
                    : '현재 ${totalCurAll}대',
                style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scrollCtrl,
            child: ListView(
              controller: _scrollCtrl,
              children: children,
            ),
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────
  // Detail popup / fee
  // ─────────────────────────────────────────
  Future<PlateModel?> _fetchPlateDetail(String plateId) async {
    final id = plateId.trim();
    if (id.isEmpty) return null;

    final cached = _plateDetailCache[id];
    if (cached != null) return cached;

    final inflight = _plateDetailInflight[id];
    if (inflight != null) return inflight;

    final fut = () async {
      try {
        final doc =
        await FirebaseFirestore.instance.collection('plates').doc(id).get();
        if (!doc.exists) return null;

        final plate = PlateModel.fromDocument(doc);
        _plateDetailCache[id] = plate;
        return plate;
      } catch (_) {
        return null;
      } finally {
        _plateDetailInflight.remove(id);
      }
    }();

    _plateDetailInflight[id] = fut;
    return fut;
  }

  FeeMode _parseFeeMode(String? modeString) {
    switch (modeString) {
      case 'plus':
        return FeeMode.plus;
      case 'minus':
        return FeeMode.minus;
      default:
        return FeeMode.normal;
    }
  }

  String _formatElapsed(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) return '$hours시간 $minutes분';
    if (minutes > 0) return '$minutes분 $seconds초';
    return '$seconds초';
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

  Future<void> _showPlateNotFoundDialog({
    required String plateId,
    required _RowVM viewRow,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: _kDialogBarrierDismissible,
      builder: (_) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: Colors.transparent,
              child: AlertDialog(
                backgroundColor: Theme.of(context).colorScheme.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 8,
                insetPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                content: _PlateDetailNotFoundDialog(
                  plateId: plateId,
                  viewPlateNumber: viewRow.plateNumber,
                  viewLocation: viewRow.location,
                  viewTimeText: _fmtDate(viewRow.createdAt),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showPlateDetailDialog({
    required _RowVM viewRow,
    required PlateModel plate,
    required String feeText,
    required String elapsedText,
    required Color? backgroundColor,
    required String displayUser,
  }) async {
    final String viewLabel =
    widget.mode == _TabMode.departureRequestsRealtime ? '출차 요청' : '입차 완료';

    return showDialog<bool>(
      context: context,
      barrierDismissible: _kDialogBarrierDismissible,
      builder: (_) {
        final cs = Theme.of(context).colorScheme;
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: Colors.transparent,
              child: AlertDialog(
                backgroundColor: cs.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 8,
                insetPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                content: _PlateDetailBodyDialog(
                  title: '번호판 상세',
                  subtitle:
                  '$viewLabel VIEW: ${viewRow.location} / ${_fmtDate(viewRow.createdAt)}   ·   '
                      'PLATES: ${plate.location} / ${CustomDateUtils.formatTimestamp(plate.requestTime)}',
                  child: PlateCustomBox(
                    topLeftText: '소속',
                    topCenterText: '${plate.region ?? '전국'} ${plate.plateNumber}',
                    topRightUpText: plate.billingType ?? '없음',
                    topRightDownText: feeText,
                    midLeftText: plate.location,
                    midCenterText: displayUser.isEmpty ? '-' : displayUser,
                    midRightText:
                    CustomDateUtils.formatTimeForUI(plate.requestTime),
                    bottomLeftLeftText: plate.statusList.isNotEmpty
                        ? plate.statusList.join(", ")
                        : "",
                    bottomLeftCenterText: plate.customStatus ?? '',
                    bottomRightText: elapsedText,
                    isSelected: plate.isSelected,
                    backgroundColor: backgroundColor,
                    onTap: () {},
                  ),
                  showWorkButton: true,
                  workButtonText: '작업 수행',
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _openHybridDetailPopup(_RowVM r) async {
    if (_openingDetail) return;
    _openingDetail = true;

    try {
      final plateId = r.plateId.trim();
      if (plateId.isEmpty) {
        showFailedSnackbar(context, '상세 조회 식별자(plateId)가 비어 있습니다.');
        return;
      }

      final proceed = await showDurationBlockingDialog(
        context,
        message: '원본 데이터를 불러옵니다.\n(취소하면 조회 비용이 발생하지 않습니다)',
        duration: const Duration(seconds: 5),
      );

      if (!mounted) return;

      if (!proceed) {
        showSelectedSnackbar(context, '취소했습니다. 원본 조회를 실행하지 않습니다.');
        return;
      }

      final plate = await runWithBlockingDialog<PlateModel?>(
        context: context,
        message: '원본 데이터를 불러오는 중입니다...',
        task: () => _fetchPlateDetail(plateId),
      );

      if (!mounted) return;

      if (plate == null) {
        await _showPlateNotFoundDialog(plateId: plateId, viewRow: r);
        return;
      }

      final billType = billTypeFromString(plate.billingType);
      final bool isRegular = billType == BillType.fixed;

      final int basicStandard = plate.basicStandard ?? 0;
      final int basicAmount = plate.basicAmount ?? 0;
      final int addStandard = plate.addStandard ?? 0;
      final int addAmount = plate.addAmount ?? 0;

      int currentFee = 0;
      if (!isRegular) {
        if (plate.isLockedFee && plate.lockedFeeAmount != null) {
          currentFee = plate.lockedFeeAmount!;
        } else {
          currentFee = calculateParkingFee(
            entryTimeInSeconds: plate.requestTime.millisecondsSinceEpoch ~/ 1000,
            currentTimeInSeconds:
            DateTime.now().millisecondsSinceEpoch ~/ 1000,
            basicStandard: basicStandard,
            basicAmount: basicAmount,
            addStandard: addStandard,
            addAmount: addAmount,
            isLockedFee: plate.isLockedFee,
            lockedAtTimeInSeconds: plate.lockedAtTimeInSeconds,
            userAdjustment: plate.userAdjustment ?? 0,
            mode: _parseFeeMode(plate.feeMode),
          ).toInt();
        }
      }

      final feeText = isRegular
          ? '${plate.isLockedFee ? (plate.lockedFeeAmount ?? 0) : (plate.regularAmount ?? 0)}원'
          : '$currentFee원';

      final elapsedText =
      _formatElapsed(DateTime.now().difference(plate.requestTime));

      final Color? backgroundColor =
      ((plate.billingType?.trim().isNotEmpty ?? false) && plate.isLockedFee)
          ? Colors.orange[50]
          : Theme.of(context).colorScheme.surface;

      final bool isSelected = plate.isSelected;
      final String displayUser =
      isSelected ? (plate.selectedBy ?? '') : plate.userName;

      final bool? doWork = await _showPlateDetailDialog(
        viewRow: r,
        plate: plate,
        feeText: feeText,
        elapsedText: elapsedText,
        backgroundColor: backgroundColor,
        displayUser: displayUser,
      );

      if (!mounted) return;

      if (doWork == true) {
        final rootCtx = Navigator.of(context, rootNavigator: true).context;
        await showTripleParkingCompletedStatusBottomSheetFromDialog(
          context: rootCtx,
          plate: plate,
        );
      }
    } finally {
      _openingDetail = false;
    }
  }

  // ─────────────────────────────────────────
  // LocationState plateCounts 동기화(기존 유지)
  // ─────────────────────────────────────────
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
      final displayName = loc.type == 'composite'
          ? (parent.isEmpty ? leaf : '$parent - $leaf')
          : leaf;

      countsByDisplayName[displayName] =
          rawCounts[displayName] ?? leafCounts[leaf] ?? 0;
    }

    _scheduleApplyPlateCountsAfterFrame(countsByDisplayName);
  }

  // ─────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────
  Widget _buildRowsChip(ColorScheme cs, TextTheme text) {
    final count =
    (_viewMode == _ViewMode.plate) ? _rows.length : _allRows.length;
    final accent = _accent(cs);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Brand.border(cs).withOpacity(0.65)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.list_alt_outlined, size: 16, color: accent),
          const SizedBox(width: 6),
          Text(
            'Rows: $count',
            style: text.labelMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCooldownChip(ColorScheme cs, TextTheme text) {
    final blocked = _isRefreshBlocked;
    final label = blocked ? '대기 ${_refreshRemainingSec}s' : 'Ready';

    final Color bg = blocked
        ? cs.errorContainer.withOpacity(0.40)
        : cs.tertiaryContainer.withOpacity(0.45);
    final Color fg = blocked ? cs.onErrorContainer : cs.onTertiaryContainer;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Brand.border(cs)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            blocked ? Icons.timer_outlined : Icons.check_circle_outline,
            size: 16,
            color: fg,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: text.labelMedium?.copyWith(
              color: fg,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewModeTogglePill(ColorScheme cs, TextTheme text) {
    final disabled = _loading;
    final toggleLabel =
    (_viewMode == _ViewMode.plate) ? '구역으로 보기' : '번호판으로 보기';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Brand.border(cs)),
      ),
      child: Row(
        children: [
          Icon(Icons.view_list_outlined, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            '보기:',
            style: text.labelMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: disabled ? null : _toggleViewMode,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        toggleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          color:
                          disabled ? cs.onSurfaceVariant : cs.onSurface,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(Icons.swap_horiz_rounded,
                        size: 18, color: cs.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRealtimeLocationFilter(ColorScheme cs, TextTheme text) {
    final options = _locationOptionsForDropdown();
    final disabled = _loading || options.isEmpty;

    if (_selectedLocation != _locationAll &&
        !options.contains(_selectedLocation)) {
      _selectedLocation = _locationAll;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Brand.border(cs)),
      ),
      child: Row(
        children: [
          Icon(Icons.place_outlined, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            '주차구역:',
            style: text.labelMedium?.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedLocation,
                isDense: true,
                isExpanded: true,
                icon: Icon(Icons.expand_more, color: cs.onSurfaceVariant),
                items: <String>[_locationAll, ...options].map((v) {
                  return DropdownMenuItem<String>(
                    value: v,
                    child: Text(
                      v,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium?.copyWith(
                        color:
                        disabled ? cs.onSurfaceVariant : cs.onSurface,
                        fontWeight: FontWeight.w700,
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
        hintText: _viewMode == _ViewMode.zone
            ? '주차 구역명 또는 상위 구역명 검색'
            : '번호판 또는 주차 구역으로 검색',
        prefixIcon: Icon(Icons.search, color: cs.onSurfaceVariant),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
          icon: Icon(Icons.clear, color: cs.onSurfaceVariant),
          onPressed: () {
            _searchCtrl.clear();
            setState(() => _applyFilterAndSort());
          },
        ),
        filled: true,
        fillColor: cs.surfaceContainerLow,
        contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  TextStyle _headStyle(ColorScheme cs) =>
      Theme.of(context).textTheme.labelMedium!.copyWith(
        fontWeight: FontWeight.w900,
        letterSpacing: .2,
        color: cs.onSurface,
      );

  TextStyle _cellStyle(ColorScheme cs) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        height: 1.2,
        color: cs.onSurface,
      );

  TextStyle _monoStyle(ColorScheme cs) => _cellStyle(cs).copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
    fontFamilyFallback: const ['monospace'],
  );

  Widget _buildTable(ColorScheme cs) {
    if (_loading) return const _ExpandedLoading();

    if (_rows.isEmpty) {
      if (!_hasFetchedFromServer && _allRows.isEmpty) {
        return const _ExpandedEmpty(
          message: '캐시된 데이터가 없습니다.\n하단 탭을 탭하면 해당 데이터가 갱신됩니다.',
        );
      }
      return const _ExpandedEmpty(message: '표시할 데이터가 없습니다.');
    }

    final headStyle = _headStyle(cs);
    final cellStyle = _cellStyle(cs);
    final monoStyle = _monoStyle(cs);

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(bottom: BorderSide(color: _Brand.border(cs))),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: _toggleSortByNo,
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('No',
                            style: headStyle,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _sortOldFirst
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        size: 14,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 7,
                child: Text('Plate',
                    style: headStyle, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Text('Location',
                    style: headStyle, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scrollCtrl,
            child: ListView.builder(
              controller: _scrollCtrl,
              itemCount: _rows.length,
              itemBuilder: (context, i) {
                final r = _rows[i];
                final rowBg =
                i.isEven ? cs.surface : cs.surfaceContainerLowest;

                final rawNo =
                (i < _displayNos.length) ? _displayNos[i] : (i + 1);
                final noText = rawNo.toString().padLeft(2, '0');

                return Material(
                  color: rowBg,
                  child: InkWell(
                    onTap: () async => _openHybridDetailPopup(r),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _Brand.border(cs).withOpacity(0.55),
                            width: .7,
                          ),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: Text(
                              noText,
                              style: monoStyle.copyWith(
                                  fontWeight: FontWeight.w900),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 7,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                r.plateNumber,
                                style: cellStyle.copyWith(
                                    fontWeight: FontWeight.w900),
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 5,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerLeft,
                              child: Text(
                                r.location,
                                style: cellStyle,
                                maxLines: 1,
                                softWrap: false,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      color: cs.surface,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.description,
                    style: text.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                Expanded(flex: 5, child: _buildRowsChip(cs, text)),
                const SizedBox(width: 8),
                Expanded(flex: 5, child: _buildCooldownChip(cs, text)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: Row(
              children: [
                Expanded(flex: 5, child: _buildViewModeTogglePill(cs, text)),
                const SizedBox(width: 8),
                Expanded(
                    flex: 5, child: _buildRealtimeLocationFilter(cs, text)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _buildSearchField(cs),
          ),
          Divider(height: 1, color: _Brand.border(cs)),
          Expanded(
            child: (_viewMode == _ViewMode.plate)
                ? _buildTable(cs)
                : _buildZoneTree(cs, text),
          ),
        ],
      ),
    );
  }
}

class _ExpandedLoading extends StatelessWidget {
  const _ExpandedLoading();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            '데이터를 불러오는 중입니다…',
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _ExpandedEmpty extends StatelessWidget {
  final String message;

  const _ExpandedEmpty({required this.message});

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
            Icon(Icons.inbox_outlined, size: 40, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              '기록이 없습니다',
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              message,
              textAlign: TextAlign.center,
              style: text.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlateDetailNotFoundDialog extends StatelessWidget {
  final String plateId;
  final String viewPlateNumber;
  final String viewLocation;
  final String viewTimeText;

  const _PlateDetailNotFoundDialog({
    required this.plateId,
    required this.viewPlateNumber,
    required this.viewLocation,
    required this.viewTimeText,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SizedBox(
      width: 520,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '번호판 상세',
                  style: text.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
              IconButton(
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Icon(Icons.close, color: cs.onSurface),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: cs.errorContainer.withOpacity(.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cs.error.withOpacity(.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '원본 plates 문서를 찾을 수 없습니다.',
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                    color: cs.onErrorContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text('plateId: $plateId',
                    style: text.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(height: 6),
                Text('VIEW Plate: $viewPlateNumber',
                    style: text.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                Text('VIEW Location: $viewLocation',
                    style: text.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
                Text('VIEW Time: $viewTimeText',
                    style: text.bodySmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _PlateDetailBodyDialog extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;

  final bool showWorkButton;
  final String workButtonText;

  const _PlateDetailBodyDialog({
    required this.title,
    required this.subtitle,
    required this.child,
    this.showWorkButton = false,
    this.workButtonText = '작업 수행',
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return SizedBox(
      width: 520,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: text.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: cs.onSurface,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: Icon(Icons.close, color: cs.onSurface),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                subtitle,
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 12),
            child,
            const SizedBox(height: 8),
            if (showWorkButton) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.playlist_add_check),
                  label: Text(
                    workButtonText,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 2),
            ],
          ],
        ),
      ),
    );
  }
}
