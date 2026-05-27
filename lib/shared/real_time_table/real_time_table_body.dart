import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../features/account/applications/user_state.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../features/dev/debug/debug_action_recorder.dart';
import '../../../features/location/applications/location_state.dart';
import '../../../features/location/domain/models/location_model.dart';
import '../../../shared/plate/application/common/view_doc_rows_store.dart';
import '../../../shared/plate/domain/models/plate_model.dart';
import '../../../shared/plate/domain/repositories/plate_repository.dart';
import 'real_time_tab_controller.dart';
import 'real_time_table_components.dart';
import 'real_time_table_row_vm.dart';
import 'real_time_table_spec.dart';
import 'real_time_table_zone.dart';

const bool kRealTimeDialogBarrierDismissible = false;

enum RealTimeViewMode { plate, zone }

class RealTimeTableBody extends StatefulWidget {
  final RealTimeTabController controller;
  final RealTimeTabSpec spec;
  final String description;
  final String screen;

  const RealTimeTableBody({
    super.key,
    required this.controller,
    required this.spec,
    required this.description,
    required this.screen,
  });

  @override
  State<RealTimeTableBody> createState() => _RealTimeTableBodyState();
}

class _RealTimeTableBodyState extends State<RealTimeTableBody>
    with AutomaticKeepAliveClientMixin {
  bool _loading = false;
  bool _hasFetchedFromServer = false;

  List<RealTimeRowVM> _allRows = <RealTimeRowVM>[];
  List<RealTimeRowVM> _rows = <RealTimeRowVM>[];
  List<int> _displayNos = <int>[];

  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;
  static const int _debounceMs = 250;

  String _selectedLocation = kRealTimeLocationAll;
  List<String> _availableLocations = <String>[];

  late bool _sortOldFirst;

  final ScrollController _scrollCtrl = ScrollController();

  ViewDocRowsStore? _store;
  int _storeRev = 0;
  String _storeArea = '';
  AreaState? _areaState;
  UserState? _userState;

  final Map<String, PlateModel> _plateDetailCache = <String, PlateModel>{};
  final Map<String, Future<PlateModel?>> _plateDetailInflight =
  <String, Future<PlateModel?>>{};

  bool _openingDetail = false;

  RealTimeViewMode _viewMode = RealTimeViewMode.plate;

  List<LocationModel> _cachedLocations = <LocationModel>[];
  int _totalCapacityFromPrefs = 0;
  int _totalCompositeChildCapacityFromMeta = 0;
  String _locationsLoadedArea = '';
  bool _loadingLocationMeta = false;

  final Map<String, bool> _groupExpanded = <String, bool>{};

  Map<String, int>? _pendingPlateCountsByDisplayName;
  bool _plateCountsApplyScheduled = false;
  Map<String, int>? _lastAppliedPlateCountsByDisplayName;

  Route<void>? _globalLoadingRoute;

  static const Duration _maskMinShow = Duration(seconds: 1);

  @override
  bool get wantKeepAlive => true;

  String get _currentArea {
    final a1 = context.read<UserState>().currentArea.trim();
    final a2 = context.read<AreaState>().currentArea.trim();
    return a1.isNotEmpty ? a1 : a2;
  }

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

    _sortOldFirst = widget.spec.defaultSortOldFirst;

    widget.controller.bind(_refreshFromUser);
    _searchCtrl.addListener(_onSearchChangedDebounced);

    if (!widget.spec.zoneSupported) {
      _viewMode = RealTimeViewMode.plate;
    }

    _applyFilterAndSort();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindProviders();
    _pullFromStore(reason: 'didChangeDependencies');
    if (widget.spec.zoneSupported) {
      _ensureLocationMetaLoaded();
    }
  }

  @override
  void dispose() {
    widget.controller.unbind();
    _debounce?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _store?.removeListener(_onStoreChanged);
    _areaState?.removeListener(_onAreaChanged);
    _userState?.removeListener(_onAreaChanged);

    final route = _globalLoadingRoute;
    if (route != null) {
      try {
        Navigator.of(context, rootNavigator: true).removeRoute(route);
      } catch (_) {}
      _globalLoadingRoute = null;
    }

    super.dispose();
  }

  void _bindProviders() {
    final s = context.read<ViewDocRowsStore>();
    if (!identical(_store, s)) {
      _store?.removeListener(_onStoreChanged);
      _store = s;
      _store!.addListener(_onStoreChanged);
    }

    final a = context.read<AreaState>();
    if (!identical(_areaState, a)) {
      _areaState?.removeListener(_onAreaChanged);
      _areaState = a;
      _areaState!.addListener(_onAreaChanged);
    }

    final u = context.read<UserState>();
    if (!identical(_userState, u)) {
      _userState?.removeListener(_onAreaChanged);
      _userState = u;
      _userState!.addListener(_onAreaChanged);
    }
  }

  void _onAreaChanged() {
    _pullFromStore(reason: 'areaChanged');
  }

  void _onStoreChanged() {
    _pullFromStore(reason: 'storeChanged');
  }

  void _pullFromStore({required String reason}) {
    if (!mounted) return;
    final store = _store;
    if (store == null) return;

    final area = _currentArea.trim();
    if (area.isEmpty) return;

    final rev = store.revision(collection: widget.spec.collection, area: area);
    if (area == _storeArea && rev == _storeRev) return;

    _storeArea = area;
    _storeRev = rev;

    final data = store.rows(collection: widget.spec.collection, area: area);

    final rows = data
        .map(
          (e) => RealTimeRowVM(
        plateId: e.plateId,
        plateNumber: e.plateNumber,
        location: e.location,
        primaryAt: e.primaryAt,
        updatedAt: e.updatedAt,
        createdAt: e.createdAt,
      ),
    )
        .toList(growable: false);

    setState(() {
      _allRows = List<RealTimeRowVM>.of(rows);
      _availableLocations = _extractLocations(_allRows);

      if (_viewMode == RealTimeViewMode.plate &&
          _selectedLocation != kRealTimeLocationAll &&
          !_availableLocations.contains(_selectedLocation)) {
        _selectedLocation = kRealTimeLocationAll;
      }

      if (!widget.spec.zoneSupported) {
        _viewMode = RealTimeViewMode.plate;
      }

      if (widget.spec.zoneSupported && _viewMode == RealTimeViewMode.zone) {
        final opts = _locationOptionsForDropdown();
        if (_selectedLocation != kRealTimeLocationAll &&
            !opts.contains(_selectedLocation)) {
          _selectedLocation = kRealTimeLocationAll;
        }
      }

      _applyFilterAndSort();
      _loading = false;
      _hasFetchedFromServer = true;
    });

    if (widget.spec.syncLocationCounts) {
      _syncLocationPickerCountsFromRows(_allRows);
    }
  }

  List<String> _extractLocations(List<RealTimeRowVM> rows) {
    final set = <String>{};
    for (final r in rows) {
      final k = r.location.trim();
      if (k.isNotEmpty) set.add(k);
    }
    final list = set.toList()..sort();
    return list;
  }

  Future<void> _ensureLocationMetaLoaded({bool force = false}) async {
    if (!widget.spec.zoneSupported) return;

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

      _totalCompositeChildCapacityFromMeta =
          compositeChildTotalCapacity(_cachedLocations);

      _locationsLoadedArea = area;

      final parentSet = extractParentsFromMeta(_cachedLocations);
      for (final p in parentSet) {
        _groupExpanded.putIfAbsent(p, () => true);
      }
    } finally {
      _loadingLocationMeta = false;
      if (mounted) setState(() {});
    }
  }

  List<String> _locationOptionsForDropdown() {
    return zoneDropdownOptions(
      meta: _cachedLocations,
      plateLocations: _availableLocations,
      zoneMode: widget.spec.zoneSupported && _viewMode == RealTimeViewMode.zone,
    );
  }

  Future<void> _toggleViewMode() async {
    if (!widget.spec.zoneSupported) {
      return;
    }

    final next = (_viewMode == RealTimeViewMode.plate)
        ? RealTimeViewMode.zone
        : RealTimeViewMode.plate;

    setState(() {
      _viewMode = next;

      if (next == RealTimeViewMode.plate) {
        if (_selectedLocation != kRealTimeLocationAll &&
            !_availableLocations.contains(_selectedLocation)) {
          _selectedLocation = kRealTimeLocationAll;
        }
      }

      _applyFilterAndSort();
    });

    if (next == RealTimeViewMode.zone) {
      await _ensureLocationMetaLoaded();
      final opts = _locationOptionsForDropdown();
      if (!mounted) return;
      setState(() {
        if (_selectedLocation != kRealTimeLocationAll &&
            !opts.contains(_selectedLocation)) {
          _selectedLocation = kRealTimeLocationAll;
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

  void _applyFilterAndSort() {
    if (!widget.spec.zoneSupported) {
      _viewMode = RealTimeViewMode.plate;
    }

    if (_viewMode != RealTimeViewMode.plate) {
      _rows = List<RealTimeRowVM>.of(_allRows);
      _displayNos = const <int>[];
      return;
    }

    final search = _searchCtrl.text.trim().toLowerCase();

    _rows = _allRows.where((r) {
      if (_selectedLocation != kRealTimeLocationAll) {
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

    _displayNos = widget.spec.tableNoStrategy
        .buildNos(_rows, sortOldFirst: _sortOldFirst);
  }

  void _toggleSortByNo() {
    setState(() {
      _sortOldFirst = !_sortOldFirst;
      _applyFilterAndSort();
    });
  }

  Future<void> _refreshFromUser() async {
    _trace(
      '탭 탭 갱신',
      meta: <String, dynamic>{
        'screen': widget.screen,
        'action': 'tab_tap_refresh',
        'tabId': widget.spec.id,
        'collection': widget.spec.collection,
        'area': _currentArea,
        'loading': _loading,
      },
    );

    _pullFromStore(reason: 'userTap');
  }

  Future<PlateModel?> _fetchPlateDetail(String plateId) async {
    final id = plateId.trim();
    if (id.isEmpty) return null;

    final cached = _plateDetailCache[id];
    if (cached != null) return cached;

    final inflight = _plateDetailInflight[id];
    if (inflight != null) return inflight;

    final repo = context.read<PlateRepository>();

    final fut = () async {
      try {
        final plate = await repo.getPlate(id);
        if (plate != null) {
          _plateDetailCache[id] = plate;
        }
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
    required RealTimeRowVM viewRow,
  }) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: kRealTimeDialogBarrierDismissible,
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
                content: RealTimePlateDetailNotFoundDialog(
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

  Route<void> _buildGlobalLoadingRoute({required String message}) {
    return RawDialogRoute<void>(
      barrierDismissible: false,
      barrierLabel: 'loading',
      barrierColor: Colors.black26,
      transitionDuration: const Duration(milliseconds: 120),
      pageBuilder: (dialogContext, animation, secondaryAnimation) {
        final cs = Theme.of(dialogContext).colorScheme;
        final text = Theme.of(dialogContext).textTheme;

        return PopScope(
          canPop: false,
          child: Material(
            color: cs.surface.withOpacity(0.96),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(
                    height: 44,
                    width: 44,
                    child: CircularProgressIndicator(),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: (text.titleMedium ??
                        text.bodyLarge ??
                        const TextStyle())
                        .copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        return FadeTransition(opacity: animation, child: child);
      },
    );
  }

  Future<void> _showGlobalLoadingMask({required String message}) async {
    if (!mounted) return;
    if (_globalLoadingRoute != null) return;

    final route = _buildGlobalLoadingRoute(message: message);
    _globalLoadingRoute = route;

    unawaited(
      Navigator.of(context, rootNavigator: true).push(route).whenComplete(() {
        if (identical(_globalLoadingRoute, route)) {
          _globalLoadingRoute = null;
        }
      }),
    );

    await Future<void>.delayed(Duration.zero);
  }

  void _hideGlobalLoadingMask() {
    final route = _globalLoadingRoute;
    if (route == null || !mounted) return;

    _globalLoadingRoute = null;

    try {
      Navigator.of(context, rootNavigator: true).removeRoute(route);
    } catch (_) {}
  }

  Future<T> _runWithOptionalMask<T>({
    required String message,
    required Future<T> Function() task,
    Duration minShow = _maskMinShow,
  }) async {
    if (!mounted) return await task();

    final shownAt = DateTime.now();
    await _showGlobalLoadingMask(message: message);

    T? result;
    Object? caught;
    StackTrace? caughtSt;

    try {
      result = await task();
    } catch (e, st) {
      caught = e;
      caughtSt = st;
    } finally {
      final elapsedSinceShown = DateTime.now().difference(shownAt);

      if (elapsedSinceShown < minShow) {
        await Future.delayed(minShow - elapsedSinceShown);
      }

      if (mounted) {
        _hideGlobalLoadingMask();
      }
    }

    if (caught != null) {
      Error.throwWithStackTrace(caught, caughtSt!);
    }

    return result as T;
  }

  Future<void> _openHybridDetailPopup(RealTimeRowVM r) async {
    if (_openingDetail) return;
    _openingDetail = true;

    try {
      final plateId = r.plateId.trim();
      if (plateId.isEmpty) {
        return;
      }

      final plate = await _runWithOptionalMask<PlateModel?>(
        message: '원본 불러오는 중...',
        task: () => _fetchPlateDetail(plateId),
      );

      if (!mounted) return;

      if (plate == null) {
        await _showPlateNotFoundDialog(plateId: plateId, viewRow: r);
        return;
      }

      _trace(
        '원본 조회 후 즉시 작업 수행 바텀시트 오픈',
        meta: <String, dynamic>{
          'screen': widget.screen,
          'action': 'open_bottom_sheet_directly',
          'tabId': widget.spec.id,
          'area': _currentArea,
          'plateId': plateId,
          'plateNumber': r.plateNumber,
          'location': r.location,
        },
      );

      final rootCtx = Navigator.of(context, rootNavigator: true).context;
      await widget.spec.openBottomSheet(rootCtx, plate);
    } finally {
      _openingDetail = false;
    }
  }

  bool _mapsEqual(Map<String, int> a, Map<String, int> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  void _scheduleApplyPlateCountsAfterFrame(
      Map<String, int> countsByDisplayName) {
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

  void _syncLocationPickerCountsFromRows(List<RealTimeRowVM> rows,
      {int attempt = 0}) {
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

    for (final r in rows) {
      final raw = r.location.trim();
      if (raw.isEmpty) continue;
      rawCounts[raw] = (rawCounts[raw] ?? 0) + 1;

      final seg = splitLocationSegments(raw);
      if (seg.length == 1) {
        final leaf = seg[0];
        rawCounts[leaf] = (rawCounts[leaf] ?? 0) + 0;
      }
    }

    final countsByDisplayName = <String, int>{};

    for (final loc in locations) {
      final t = (loc.type ?? 'single').trim();
      final leaf = loc.locationName.trim();
      final parent = (loc.parent ?? '').trim();

      if (t == 'composite_child' || t == 'composite') {
        final key = (parent.isEmpty || leaf.isEmpty)
            ? ''
            : '$parent$kRealTimeSegSep$leaf';
        final display = key.isEmpty ? leaf : key;
        countsByDisplayName[display] = key.isEmpty ? 0 : (rawCounts[key] ?? 0);
        continue;
      }

      if (t == 'composite_parent') {
        countsByDisplayName[leaf] = rawCounts[leaf] ?? 0;
        continue;
      }

      countsByDisplayName[leaf] = rawCounts[leaf] ?? 0;
    }

    _scheduleApplyPlateCountsAfterFrame(countsByDisplayName);
  }

  Widget _buildViewModeTogglePill(ColorScheme cs, TextTheme text) {
    final disabled = _loading || !widget.spec.zoneSupported;
    final toggleLabel = !widget.spec.zoneSupported
        ? '번호판으로 보기(고정)'
        : (_viewMode == RealTimeViewMode.plate ? '구역으로 보기' : '번호판으로 보기');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
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
                    if (!widget.spec.zoneSupported) ...[
                      Icon(Icons.lock_outline,
                          size: 16, color: cs.onSurfaceVariant),
                      const SizedBox(width: 6),
                    ],
                    Expanded(
                      child: Text(
                        toggleLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.labelMedium?.copyWith(
                          color: disabled ? cs.onSurfaceVariant : cs.onSurface,
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

    if (_selectedLocation != kRealTimeLocationAll &&
        !options.contains(_selectedLocation)) {
      _selectedLocation = kRealTimeLocationAll;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: cs.outlineVariant.withOpacity(.6)),
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
                items: <String>[kRealTimeLocationAll, ...options].map((v) {
                  return DropdownMenuItem<String>(
                    value: v,
                    child: Text(
                      v,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelMedium?.copyWith(
                        color: disabled ? cs.onSurfaceVariant : cs.onSurface,
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
    final hint =
    (_viewMode == RealTimeViewMode.zone && widget.spec.zoneSupported)
        ? '부모 또는 자식 주차구역 검색'
        : '번호판 또는 주차 구역으로 검색';

    return TextField(
      controller: _searchCtrl,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
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
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.outlineVariant.withOpacity(0.8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: cs.primary, width: 1.4),
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
        color: cs.onSurface.withOpacity(.92),
      );

  TextStyle _monoStyle(ColorScheme cs) => _cellStyle(cs).copyWith(
    fontFeatures: const [FontFeature.tabularFigures()],
    fontFamilyFallback: const ['monospace'],
  );

  Widget _buildTable(ColorScheme cs) {
    if (_loading) return const RealTimeExpandedLoading();

    if (_rows.isEmpty) {
      if (!_hasFetchedFromServer && _allRows.isEmpty) {
        return const RealTimeExpandedEmpty(
          message: '캐시된 데이터가 없습니다.\n하단 탭을 탭하면 해당 데이터가 갱신됩니다.',
        );
      }
      return const RealTimeExpandedEmpty(message: '표시할 데이터가 없습니다.');
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
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant.withOpacity(.85)),
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
                        child: Text(
                          'No',
                          style: headStyle,
                          overflow: TextOverflow.ellipsis,
                        ),
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
                final rowBg = i.isEven
                    ? cs.surface
                    : cs.surfaceContainerLow.withOpacity(.55);

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
                            color: cs.outlineVariant.withOpacity(.55),
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
                                style: cellStyle.copyWith(
                                    color: cs.onSurfaceVariant),
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

  Future<void> _openZonePlatesDialog(ZoneVM z) async {
    if (!mounted) return;

    _trace(
      '구역 탭(번호판 목록 다이얼로그)',
      meta: <String, dynamic>{
        'screen': widget.screen,
        'action': 'zone_tap_open_dialog',
        'tabId': widget.spec.id,
        'area': _currentArea,
        'zoneKey': z.fullName,
        'zoneParent': z.group,
        'zoneChild': z.child,
        'zoneCurrent': z.current,
        'zoneCapacity': z.capacity,
      },
    );

    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final rows = <RealTimeRowVM>[];
    for (final r in _allRows) {
      final ck = zoneKeyFromRowLocation(r.location);
      if (ck.isNotEmpty && ck == z.fullName) rows.add(r);
    }

    rows.sort((a, b) {
      final ca = a.createdAt;
      final cb = b.createdAt;

      if (ca == null && cb == null) return 0;
      if (ca == null) return _sortOldFirst ? 1 : -1;
      if (cb == null) return _sortOldFirst ? -1 : 1;

      final cmp = ca.compareTo(cb);
      return _sortOldFirst ? cmp : -cmp;
    });

    final dialogNos = widget.spec.dialogNoStrategy
        .buildNos(rows, sortOldFirst: _sortOldFirst);

    await showDialog<void>(
      context: context,
      barrierDismissible: kRealTimeDialogBarrierDismissible,
      builder: (_) {
        final remainText = (z.remaining == null)
            ? '-'
            : (z.remaining! >= 0 ? '${z.remaining}대' : '0대');
        final capText = z.capacity > 0 ? '${z.capacity}대' : '-';

        final title = '구역: ${z.fullName}';
        final subtitle = '현재 ${rows.length}대 / 총 $capText / 잔여 $remainText';

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
                                  size: 40, color: cs.outline),
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
                                  color: cs.outlineVariant.withOpacity(.75)),
                            ),
                            child: Scrollbar(
                              child: ListView.separated(
                                shrinkWrap: true,
                                itemCount: rows.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: cs.outlineVariant.withOpacity(.6),
                                ),
                                itemBuilder: (ctx, i) {
                                  final r = rows[i];
                                  final timeText = _fmtDate(r.createdAt);

                                  final rawNo = (i < dialogNos.length)
                                      ? dialogNos[i]
                                      : (i + 1);
                                  final noText =
                                  rawNo.toString().padLeft(2, '0');

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
                                                noText,
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
                                                      color:
                                                      cs.onSurfaceVariant,
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
                          '항목을 탭하면 작업 수행 바텀시트로 이동합니다.',
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

  Widget _buildZoneAccordion(ColorScheme cs, TextTheme text) {
    if (!widget.spec.zoneSupported) {
      return const RealTimeExpandedEmpty(message: '해당 탭에서는 구역 보기를 지원하지 않습니다.');
    }

    if (_loadingLocationMeta && _cachedLocations.isEmpty) {
      return const RealTimeExpandedLoading();
    }

    if (_cachedLocations.isEmpty) {
      return const RealTimeExpandedEmpty(
        message: '주차구역 캐시가 없습니다.\n설정에서 주차구역 새로고침 후 다시 시도하세요.',
      );
    }

    final groups = buildZoneGroups(
      rows: _allRows,
      meta: _cachedLocations,
      selected: _selectedLocation,
      search: _searchCtrl.text,
    );

    if (groups.isEmpty) {
      return const RealTimeExpandedEmpty(
        message: '표시할 구역이 없습니다.\n(부모/자식 메타 또는 데이터가 비어있습니다)',
      );
    }

    final capFromChildren = groups.fold<int>(0, (s, g) => s + g.totalCapacity);
    final totalCapAll = capFromChildren > 0
        ? capFromChildren
        : (_totalCompositeChildCapacityFromMeta > 0
        ? _totalCompositeChildCapacityFromMeta
        : _totalCapacityFromPrefs);

    final matchedCurAll = groups.fold<int>(0, (s, g) => s + g.totalCurrent);
    final unknown = _allRows.length - matchedCurAll;

    final totalCurAll =
    widget.spec.showUnknownInZoneSummary ? matchedCurAll : _allRows.length;

    final totalRemAll = totalCapAll > 0 ? (totalCapAll - totalCurAll) : null;

    Widget buildZoneRow(ZoneVM z, {required bool indented}) {
      final remainText = (z.remaining == null)
          ? '-'
          : (z.remaining! >= 0 ? '${z.remaining}대' : '0대');
      final capText = z.capacity > 0 ? '${z.capacity}대' : '-';
      final leftPad = indented ? 28.0 : 12.0;

      final remainColor =
      (z.remaining != null && z.remaining! <= 0) ? cs.error : cs.tertiary;

      return Material(
        color: cs.surface,
        child: InkWell(
          onTap: _loading ? null : () => _openZonePlatesDialog(z),
          child: Container(
            width: double.infinity,
            padding: EdgeInsets.fromLTRB(leftPad, 10, 12, 10),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(
                bottom: BorderSide(color: cs.outlineVariant.withOpacity(.55)),
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
                    style:
                    text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 10),
                Text('총 $capText',
                    style:
                    text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                const SizedBox(width: 10),
                Text(
                  '잔여 $remainText',
                  style: text.bodySmall?.copyWith(
                    color: remainColor,
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
      final expanded = _groupExpanded[g.group] ?? true;

      final groupRemainText = g.totalRemaining == null
          ? '-'
          : (g.totalRemaining! >= 0 ? '${g.totalRemaining}대' : '0대');
      final groupRemainColor =
      (g.totalRemaining != null && g.totalRemaining! <= 0)
          ? cs.error
          : cs.tertiary;

      children.add(
        Material(
          color: cs.surface,
          child: InkWell(
            onTap: () => setState(() => _groupExpanded[g.group] = !expanded),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                border: Border(
                  bottom: BorderSide(color: cs.outlineVariant.withOpacity(.65)),
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
                      style:
                      text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(width: 10),
                  Text(
                    '총 ${g.totalCapacity > 0 ? "${g.totalCapacity}대" : "-"}',
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '잔여 $groupRemainText',
                    style: text.bodySmall?.copyWith(
                      color: groupRemainColor,
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

    final summary = totalCapAll > 0
        ? '총 ${totalCapAll}대 / 현재 ${totalCurAll}대 / 잔여 ${totalRemAll ?? 0}대'
        : '현재 ${totalCurAll}대';

    final summaryWithUnknown =
    widget.spec.showUnknownInZoneSummary && unknown > 0
        ? '$summary (미지정 $unknown대)'
        : summary;

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(color: cs.outlineVariant.withOpacity(.85)),
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
                summaryWithUnknown,
                style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
        Expanded(
          child: Scrollbar(
            controller: _scrollCtrl,
            child: ListView(controller: _scrollCtrl, children: children),
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
          Divider(height: 1, color: cs.outlineVariant.withOpacity(.7)),
          Expanded(
            child: (_viewMode == RealTimeViewMode.plate ||
                !widget.spec.zoneSupported)
                ? _buildTable(cs)
                : _buildZoneAccordion(cs, text),
          ),
        ],
      ),
    );
  }
}
