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
import '../../../../states/area/area_state.dart';
import '../../../../states/location/location_state.dart';
import '../../../../states/user/user_state.dart';
import '../../../../utils/block_dialogs/blocking_dialog.dart'; // runWithBlockingDialog
import '../../../../utils/block_dialogs/duration_blocking_dialog.dart'; // showDurationBlockingDialog
import '../../../../utils/init/date_utils.dart';
import '../../../../utils/snackbar_helper.dart';
import '../../../../widgets/container/plate_container_fee_calculator.dart';
import '../../../../widgets/container/plate_custom_box.dart';
import '../../../../widgets/dialog/billing_bottom_sheet/fee_calculator.dart';

import '../../../hubs_mode/dev_package/debug_package/debug_action_recorder.dart';
import 'widgets/double_parking_completed_status_bottom_sheet.dart';

const String _kLocationAll = '전체';

/// ✅ 다이얼로그가 "너무 쉽게 닫히는" 문제 방지:
/// - 배경(바깥) 탭으로 닫히지 않게 통일
const bool _kDialogBarrierDismissible = false;

/// ✅ Top-level (Dart 규칙 준수)
enum _ViewMode { plate, zone }

/// ✅ Top-level (Dart 규칙 준수)
/// ✅ 변경: fullName(원본 매칭 키) 추가
class _ZoneVM {
  /// 드롭다운/집계(rawCounts) 키로 쓰는 "전체 표시명"
  /// 예: "부모 - 자식" 또는 단독이면 "자식"
  final String fullName;

  /// composite parent(부모명). 단독은 ''.
  final String group;

  /// 화면 표시용(단독=fullName, 복합 child=leaf)
  final String displayName;

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
  /// group == '' 인 경우: 단독 리스트(헤더 없이 출력)
  /// group != '' 인 경우: 복합 부모 헤더
  final String group;
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

/// ✅ (분리) 입차 완료 "실시간(view) 모드" 진입 게이트(ON/OFF)
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

/// Deep Blue 팔레트(기존 컨셉 유지)
class _Palette {
  static const base = Color(0xFF0D47A1);
  static const dark = Color(0xFF09367D);
  static const light = Color(0xFF5472D3);
}

/// UI 렌더링 Row VM
class _RowVM {
  final String plateId; // plates 문서 docId
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

/// refresh 컨트롤러
class _RealtimeController {
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

/// Firestore view repository (입차 완료(view) 전용)
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
        final createdAt =
            _toDate(m[primaryTimeField]) ?? _toDate(m['updatedAt']);

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

class DoubleParkingCompletedRealTimeTable extends StatefulWidget {
  final VoidCallback? onClose;

  const DoubleParkingCompletedRealTimeTable({
    super.key,
    this.onClose,
  });

  @override
  State<DoubleParkingCompletedRealTimeTable> createState() =>
      _DoubleParkingCompletedRealTimeTableState();
}

class _DoubleParkingCompletedRealTimeTableState
    extends State<DoubleParkingCompletedRealTimeTable>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  bool _pcGate = false;
  bool _gatesLoaded = false;

  final _RealtimeController _ctrl = _RealtimeController();

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

    _tabCtrl = TabController(length: 1, vsync: this);
    _tabCtrl.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    _loadGate();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGate() async {
    try {
      final pc = await ParkingCompletedRealtimeTabGate.isEnabled();
      if (!mounted) return;
      setState(() {
        _pcGate = pc;
        _gatesLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _pcGate = false;
        _gatesLoaded = true;
      });
    }
  }

  void _requestRefreshByTabTap() {
    _trace(
      '입차 완료 탭 탭(갱신)',
      meta: <String, dynamic>{
        'screen': 'double_parking_completed_view_embedded',
        'action': 'tab_tap_refresh',
        'area': _area,
        'gatesLoaded': _gatesLoaded,
        'gateEnabled': _pcGate,
        'ctrlBound': _ctrl.isBound,
      },
    );

    if (!_gatesLoaded) {
      showSelectedSnackbar(context, '설정 확인 중입니다.');
      return;
    }

    if (!_pcGate) {
      HapticFeedback.selectionClick();
      showSelectedSnackbar(
        context,
        '입차 완료 실시간 모드가 비활성화되어 있습니다. 설정에서 ON 후 사용해 주세요.',
      );
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      if (_ctrl.isBound) {
        await _ctrl.refreshUser();
        return;
      }

      await Future.delayed(const Duration(milliseconds: 120));
      if (!mounted) return;
      await _ctrl.refreshUser();
    });
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

  Widget _buildTopHeader(TextTheme textTheme, ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _Palette.base.withOpacity(.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.table_chart_outlined, color: _Palette.base, size: 18),
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
                    fontWeight: FontWeight.w800,
                    color: _Palette.dark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '지역: $_area',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.bodySmall?.copyWith(color: cs.outline),
                ),
              ],
            ),
          ),
          if (!_gatesLoaded) ...[
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
            onPressed: () {
              final cb = widget.onClose;
              if (cb != null) {
                cb();
                return;
              }
              Navigator.of(context).maybePop();
            },
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomTabBar(ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: cs.outline.withOpacity(.15))),
      ),
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          color: _Palette.base.withOpacity(.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _Palette.light.withOpacity(.25)),
        ),
        child: TabBar(
          controller: _tabCtrl,
          onTap: (_) => _requestRefreshByTabTap(),
          labelColor: _Palette.base,
          unselectedLabelColor: cs.outline,
          indicatorColor: _Palette.base,
          indicatorSize: TabBarIndicatorSize.tab,
          dividerColor: Colors.transparent,
          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
          tabs: [Tab(child: _tabLabel(text: '입차 완료', enabled: _pcGate))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          _buildTopHeader(textTheme, cs),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabCtrl,
              physics: const PageScrollPhysics(),
              children: [
                _pcGate
                    ? _UnifiedTableBody(
                  controller: _ctrl,
                  description:
                  '하단 “입차 완료” 탭을 누르면 데이터가 갱신됩니다. 잦은 갱신은 앱에 무리를 줍니다.',
                )
                    : const _LockedPanel(
                  title: '입차 완료 실시간 모드가 비활성화되어 있습니다',
                  message:
                  '설정에서 “입차 완료 실시간 모드(탭) 사용”을 ON으로 변경한 뒤 다시 시도해 주세요.',
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

class _LockedPanel extends StatelessWidget {
  final String title;
  final String message;

  const _LockedPanel({
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
                fontWeight: FontWeight.w800,
                color: _Palette.dark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
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

class _UnifiedTableBody extends StatefulWidget {
  final _RealtimeController controller;
  final String description;

  const _UnifiedTableBody({
    required this.controller,
    required this.description,
  });

  @override
  State<_UnifiedTableBody> createState() => _UnifiedTableBodyState();
}

class _UnifiedTableBodyState extends State<_UnifiedTableBody>
    with AutomaticKeepAliveClientMixin {
  late final _GenericViewRepository _repo;

  bool _loading = false;
  bool _hasFetchedFromServer = false;

  List<_RowVM> _allRows = <_RowVM>[];
  List<_RowVM> _rows = <_RowVM>[];

  // ✅ 추가: 일자별 No(날짜가 바뀌면 1부터)
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

  String get _primaryTimeField => 'parkingCompletedAt';
  String get _collection => 'parking_completed_view';

  String get _currentArea {
    final a1 = context.read<UserState>().currentArea.trim();
    final a2 = context.read<AreaState>().currentArea.trim();
    return a1.isNotEmpty ? a1 : a2;
  }

  bool get _isRefreshBlocked => _repo.isRefreshBlocked(_currentArea);
  int get _refreshRemainingSec => _repo.refreshRemainingSec(_currentArea);

  _ViewMode _viewMode = _ViewMode.plate;

  List<LocationModel> _cachedLocations = <LocationModel>[];
  int _totalCapacityFromPrefs = 0;
  String _locationsLoadedArea = '';
  bool _loadingLocationMeta = false;

  final Map<String, bool> _groupExpanded = <String, bool>{};

  // ✅ createdAt의 로컬 일자 키
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

    widget.controller._bindRefresh(_refreshFromUser);

    _searchCtrl.addListener(_onSearchChangedDebounced);

    _allRows = List<_RowVM>.of(_repo.getCached(_currentArea));
    _availableLocations = _extractLocations(_allRows);

    _applyFilterAndSort();
    _ensureCooldownTicker();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
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

      // ✅ 단독 구역은 그룹 확장 상태가 필요 없으므로 composite parent만 등록
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

  /// ✅ 단독은 그룹으로 묶지 않음 → '' 반환
  /// 복합(composite + parent 존재)만 parent 그룹 반환
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
    final next = (_viewMode == _ViewMode.plate) ? _ViewMode.zone : _ViewMode.plate;

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

  Future<void> _refreshFromUser() async {
    if (_loading) {
      showSelectedSnackbar(context, '이미 갱신 중입니다.');
      return;
    }

    if (_isRefreshBlocked) {
      _ensureCooldownTicker();
      showSelectedSnackbar(context, '새로고침 대기 중: ${_refreshRemainingSec}초');
      return;
    }

    _repo.startRefreshCooldown(_currentArea, const Duration(seconds: 30));
    _ensureCooldownTicker();

    setState(() => _loading = true);

    try {
      final rows = await _repo.fetchFromServerAndCache(_currentArea);

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
    // zone 모드에서는 No 계산 불필요
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

    // ✅ 정렬 기준 유지: createdAt
    _rows.sort((a, b) {
      final ca = a.createdAt;
      final cb = b.createdAt;
      if (ca == null && cb == null) return 0;
      if (ca == null) return _sortOldFirst ? 1 : -1;
      if (cb == null) return _sortOldFirst ? -1 : 1;
      final cmp = ca.compareTo(cb);
      return _sortOldFirst ? cmp : -cmp;
    });

    // ✅ 일자별 No 계산(날짜가 바뀌면 1부터)
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

  /// ✅ No 헤더 탭으로 정렬 토글(기준: createdAt)
  void _toggleSortByNo() {
    setState(() {
      _sortOldFirst = !_sortOldFirst;
      _applyFilterAndSort();
    });
    showSelectedSnackbar(
      context,
      _sortOldFirst ? '정렬: 오래된 순' : '정렬: 최신 순',
    );
  }

  // ─────────────────────────────────────────────────────────
  // ✅ [추가] Zone 행 탭 → 해당 구역 번호판 목록 다이얼로그
  // ─────────────────────────────────────────────────────────

  _ZoneVM _zoneVmFromLocation(LocationModel loc) {
    final fullName = _displayNameForLocation(loc).trim();
    final parent = _groupKeyForLocation(loc);
    final leaf = loc.locationName.trim();
    final isCompositeChild = parent.isNotEmpty;
    final displayLabel = isCompositeChild ? leaf : fullName;

    return _ZoneVM(
      fullName: fullName,
      group: parent,
      displayName: displayLabel,
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
    // leaf가 여러 parent에 중복되면, row.location이 leaf만 있을 때 어느 parent인지 단정 불가
    return parents.length <= 1;
  }

  bool _matchRowToZone(_RowVM r, _ZoneVM z) {
    final raw = r.location.trim();
    if (raw.isEmpty) return false;

    final full = z.fullName.trim();
    final group = z.group.trim();
    final leaf = z.leaf.trim();

    // 1) 가장 우선: fullName 정합 매칭
    if (full.isNotEmpty && raw == full) return true;

    // 2) 단독 구역: leaf 단독 저장 케이스(레거시)까지 보조 허용
    if (group.isEmpty) {
      if (leaf.isNotEmpty && raw == leaf) return true;
      return false;
    }

    // 3) composite child
    if (leaf.isEmpty) return false;

    if (raw.contains(' - ')) {
      // "부모 - 자식" 형태면, parent 및 leaf 모두 확인
      if (!raw.startsWith('$group - ')) return false;
      return _leafFromLocationLabel(raw) == leaf;
    }

    // 4) row.location이 leaf만 있는 편차 케이스: leaf가 유일할 때만 포함
    if (raw == leaf && _isCompositeLeafUnique(leaf)) return true;

    return false;
  }

  List<_RowVM> _rowsForZone(_ZoneVM z) {
    final zn = z.fullName.trim();
    if (zn == '기타/미지정') {
      // "기타/미지정": 메타에 매칭되지 않는 rows를 모아 보여줌
      final metaVms = _cachedLocations.map(_zoneVmFromLocation).where((e) {
        final fn = e.fullName.trim();
        return fn.isNotEmpty;
      }).toList();

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
        'screen': 'double_parking_completed_view_embedded',
        'action': 'zone_tap_open_dialog',
        'area': _currentArea,
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

    await showDialog<void>(
      context: context,
      barrierDismissible: _kDialogBarrierDismissible,
      builder: (_) {
        final cs = Theme.of(context).colorScheme;
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
                backgroundColor: Colors.white,
                elevation: 8,
                insetPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
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
                                color: _Palette.dark,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          IconButton(
                            tooltip: '닫기',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          subtitle,
                          style: text.bodySmall?.copyWith(color: cs.outline),
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
                                  size: 40, color: cs.outline),
                              const SizedBox(height: 10),
                              Text(
                                '표시할 번호판이 없습니다.',
                                style:
                                text.bodyMedium?.copyWith(color: cs.outline),
                              ),
                            ],
                          ),
                        )
                      else
                        Flexible(
                          child: Container(
                            decoration: BoxDecoration(
                              color: _Palette.base.withOpacity(.02),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: cs.outline.withOpacity(.15),
                              ),
                            ),
                            child: Scrollbar(
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: rows.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: cs.outline.withOpacity(.12),
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
                                                (i + 1).toString().padLeft(2, '0'),
                                                style: monoSmall(_Palette.dark),
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
                                                      fontWeight: FontWeight.w900,
                                                      color: _Palette.dark,
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
                                                      color: cs.outline,
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
                                              style: text.bodySmall
                                                  ?.copyWith(color: cs.outline),
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
                          style: text.bodySmall?.copyWith(color: cs.outline),
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

  // ─────────────────────────────────────────────────────────
  // 기존: plate 상세 / fee 계산 / table 렌더링
  // ─────────────────────────────────────────────────────────

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

  Widget _buildRowsChip(TextTheme text) {
    final count = _viewMode == _ViewMode.plate ? _rows.length : _allRows.length;

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
            'Rows: $count',
            style: text.labelMedium?.copyWith(
              color: _Palette.base,
              fontWeight: FontWeight.w700,
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
        color: blocked
            ? Colors.orange.withOpacity(.12)
            : Colors.teal.withOpacity(.10),
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

  Widget _buildViewModeTogglePill(ColorScheme cs, TextTheme text) {
    final disabled = _loading;
    final toggleLabel =
    (_viewMode == _ViewMode.plate) ? '구역으로 보기' : '번호판으로 보기';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Palette.light.withOpacity(.18)),
      ),
      child: Row(
        children: [
          Icon(Icons.view_list_outlined, size: 16, color: _Palette.base),
          const SizedBox(width: 6),
          Text(
            '보기:',
            style: text.labelMedium?.copyWith(
              color: _Palette.base,
              fontWeight: FontWeight.w700,
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
                          color: disabled ? cs.outline : _Palette.dark,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: 18,
                      color: disabled ? cs.outline : cs.outline,
                    ),
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

    if (_selectedLocation != _locationAll && !options.contains(_selectedLocation)) {
      _selectedLocation = _locationAll;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _Palette.base.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _Palette.light.withOpacity(.18)),
      ),
      child: Row(
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
                items: <String>[_locationAll, ...options].map((v) {
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
        hintText: _viewMode == _ViewMode.zone
            ? '주차 구역명 또는 상위 구역명 검색'
            : '번호판 또는 주차 구역으로 검색',
        prefixIcon: Icon(Icons.search, color: _Palette.dark.withOpacity(.7)),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
          icon: Icon(Icons.clear, color: _Palette.dark.withOpacity(.7)),
          onPressed: () {
            _searchCtrl.clear();
            setState(() => _applyFilterAndSort());
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

  TextStyle get _headStyle =>
      Theme.of(context).textTheme.labelMedium!.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: .2,
        color: _Palette.dark,
      );

  TextStyle get _cellStyle =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        height: 1.2,
        color: _Palette.dark.withOpacity(.9),
      );

  TextStyle get _monoStyle => _cellStyle.copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
    fontFamilyFallback: const ['monospace'],
  );

  /// ✅ 변경:
  /// - No 컬럼 추가(맨 왼쪽), Time 컬럼 제거
  /// - No는 일자별 1부터, 표기는 01 형식
  /// - Plate/Location scaleDown 적용 + Plate 폭 확대
  Widget _buildTable() {
    if (_loading) return const _ExpandedLoading();

    if (_rows.isEmpty) {
      if (!_hasFetchedFromServer && _allRows.isEmpty) {
        return const _ExpandedEmpty(
          message: '캐시된 데이터가 없습니다.\n하단 “입차 완료” 탭을 누르면 데이터가 갱신됩니다.',
        );
      }
      return const _ExpandedEmpty(message: '표시할 데이터가 없습니다.');
    }

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: _Palette.base.withOpacity(.06),
            border: Border(
              bottom: BorderSide(color: _Palette.light.withOpacity(.35)),
            ),
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
                            style: _headStyle,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        _sortOldFirst ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 14,
                        color: _Palette.dark.withOpacity(.8),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 7,
                child: Text('Plate',
                    style: _headStyle, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Text('Location',
                    style: _headStyle, overflow: TextOverflow.ellipsis),
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
                i.isEven ? Colors.white : _Palette.base.withOpacity(.02);

                final rawNo = (i < _displayNos.length) ? _displayNos[i] : (i + 1);
                final noText = rawNo.toString().padLeft(2, '0'); // ✅ 01 형식

                return Material(
                  color: rowBg,
                  child: InkWell(
                    onTap: () async => _openHybridDetailPopup(r),
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(
                            color: _Palette.light.withOpacity(.20),
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
                              style:
                              _monoStyle.copyWith(fontWeight: FontWeight.w800),
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
                                style: _cellStyle.copyWith(
                                    fontWeight: FontWeight.w800),
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
                                style: _cellStyle,
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

  Widget _buildZoneAccordion(ColorScheme cs, TextTheme text) {
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

      // ✅ 변경: 단독/하위 구역 탭 가능(구역 번호판 목록 다이얼로그)
      return Material(
        color: Colors.white,
        child: InkWell(
          onTap: _loading ? null : () => _openZonePlatesDialog(z),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(leftPad, 10, 12, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                bottom: BorderSide(color: cs.outline.withOpacity(.10)),
              ),
            ),
            child: Row(
              children: [
                if (indented) ...[
                  Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 18, color: cs.outline.withOpacity(.85)),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Text(
                    z.displayName,
                    style: text.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: _Palette.dark,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text('현재 ${z.current}대',
                    style: text.bodySmall?.copyWith(color: cs.outline)),
                const SizedBox(width: 10),
                Text('총 $capText',
                    style: text.bodySmall?.copyWith(color: cs.outline)),
                const SizedBox(width: 10),
                Text(
                  '잔여 $remainText',
                  style: text.bodySmall?.copyWith(
                    color: (z.remaining != null && z.remaining! <= 0)
                        ? Colors.redAccent
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

      // 상위 그룹 헤더: 기존대로 expand/collapse만 유지
      children.add(
        Material(
          color: Colors.white,
          child: InkWell(
            onTap: () => setState(() => _groupExpanded[g.group] = !expanded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: _Palette.base.withOpacity(.03),
                border: Border(
                  bottom: BorderSide(color: cs.outline.withOpacity(.12)),
                ),
              ),
              child: Row(
                children: [
                  Icon(expanded ? Icons.expand_less : Icons.expand_more,
                      color: cs.outline),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      g.group,
                      style: text.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: _Palette.dark,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('현재 ${g.totalCurrent}대',
                      style: text.bodySmall?.copyWith(color: cs.outline)),
                  const SizedBox(width: 10),
                  Text(
                      '총 ${g.totalCapacity > 0 ? "${g.totalCapacity}대" : "-"}',
                      style: text.bodySmall?.copyWith(color: cs.outline)),
                  const SizedBox(width: 10),
                  Text(
                    '잔여 $groupRemainText',
                    style: text.bodySmall?.copyWith(
                      color: (g.totalRemaining != null && g.totalRemaining! <= 0)
                          ? Colors.redAccent
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
            color: _Palette.base.withOpacity(.06),
            border: Border(
              bottom: BorderSide(color: _Palette.light.withOpacity(.35)),
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  '구역별 잔여 공간',
                  style: text.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: _Palette.dark,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                totalCapAll > 0
                    ? '총 ${totalCapAll}대 / 현재 ${totalCurAll}대 / 잔여 ${totalRemAll ?? 0}대'
                    : '현재 ${totalCurAll}대',
                style: text.labelMedium?.copyWith(color: cs.outline),
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
                backgroundColor: Colors.white,
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
    return showDialog<bool>(
      context: context,
      barrierDismissible: _kDialogBarrierDismissible,
      builder: (_) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Material(
              color: Colors.transparent,
              child: AlertDialog(
                backgroundColor: Colors.white,
                elevation: 8,
                insetPadding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
                contentPadding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                content: _PlateDetailBodyDialog(
                  title: '번호판 상세',
                  subtitle:
                  'VIEW: ${viewRow.location} / ${_fmtDate(viewRow.createdAt)}   ·   '
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

      final backgroundColor =
      ((plate.billingType?.trim().isNotEmpty ?? false) && plate.isLockedFee)
          ? Colors.orange[50]
          : Colors.white;

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
        await showDoubleParkingCompletedStatusBottomSheetFromDialog(
          context: rootCtx,
          plate: plate,
        );
      }
    } finally {
      _openingDetail = false;
    }
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
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
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
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Row(
              children: [
                Expanded(flex: 5, child: _buildRowsChip(text)),
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
                Expanded(flex: 5, child: _buildRealtimeLocationFilter(cs, text)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: _buildSearchField(cs),
          ),
          const Divider(height: 1),
          Expanded(
            child: _viewMode == _ViewMode.plate
                ? _buildTable()
                : _buildZoneAccordion(cs, text),
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
            Icon(Icons.inbox_outlined, size: 40, color: cs.outline),
            const SizedBox(height: 10),
            Text(
              '기록이 없습니다',
              style: text.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
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
                    fontWeight: FontWeight.w800,
                    color: _Palette.dark,
                  ),
                ),
              ),
              IconButton(
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.red.withOpacity(.25)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '원본 plates 문서를 찾을 수 없습니다.',
                  style: text.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: Colors.red.shade700,
                  ),
                ),
                const SizedBox(height: 8),
                Text('plateId: $plateId',
                    style: text.bodySmall?.copyWith(color: cs.outline)),
                const SizedBox(height: 6),
                Text('VIEW Plate: $viewPlateNumber',
                    style: text.bodySmall?.copyWith(color: cs.outline)),
                Text('VIEW Location: $viewLocation',
                    style: text.bodySmall?.copyWith(color: cs.outline)),
                Text('VIEW Time: $viewTimeText',
                    style: text.bodySmall?.copyWith(color: cs.outline)),
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
                      fontWeight: FontWeight.w800,
                      color: _Palette.dark,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '닫기',
                  onPressed: () => Navigator.of(context).pop(false),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                subtitle,
                style: text.bodySmall?.copyWith(color: cs.outline),
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
                    backgroundColor: _Palette.base,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
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
