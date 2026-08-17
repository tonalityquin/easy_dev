import 'dart:async';
import 'dart:convert';
import 'dart:ui' show FontFeature;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/utils/developer_operation_status_dialog.dart';
import '../../app/utils/operational_data_sync_workflow.dart';
import '../../features/account/applications/user_state.dart';
import '../../features/dev/application/area_state.dart';
import '../../features/dev/debug/debug_action_recorder.dart';
import '../../features/location/applications/location_state.dart';
import '../../features/location/domain/models/location_model.dart';
import '../plate/application/common/view_doc_rows_store.dart';
import '../plate/domain/models/plate_model.dart';
import '../plate/domain/repositories/plate_repository.dart';
import 'real_time_location_board.dart';
import 'real_time_sort_state.dart';
import 'real_time_tab_controller.dart';
import 'real_time_table_components.dart';
import 'real_time_table_row_vm.dart';
import 'real_time_table_spec.dart';
import 'real_time_table_zone.dart';

enum RealTimeViewMode { plate, zone }


class _DrivingBadge extends StatelessWidget {
  const _DrivingBadge({
    required this.colorScheme,
    required this.textTheme,
  });

  final ColorScheme colorScheme;
  final TextTheme textTheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: colorScheme.error.withOpacity(.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.error.withOpacity(.36)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.directions_car_filled, size: 12, color: colorScheme.error),
          const SizedBox(width: 3),
          Text(
            '주행 중',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (textTheme.labelSmall ?? const TextStyle(fontSize: 11))
                .copyWith(
              color: colorScheme.error,
              fontWeight: FontWeight.w900,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

class RealTimeTableBody extends StatefulWidget {
  final RealTimeTabController controller;
  final RealTimeTabSpec spec;
  final String description;
  final String screen;
  final VoidCallback? onUserActivity;
  final VoidCallback? onAutoPauseStart;
  final VoidCallback? onAutoPauseEnd;

  const RealTimeTableBody({
    super.key,
    required this.controller,
    required this.spec,
    required this.description,
    required this.screen,
    this.onUserActivity,
    this.onAutoPauseStart,
    this.onAutoPauseEnd,
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

  Timer? _elapsedTicker;
  DateTime _elapsedNow = DateTime.now();
  String _selectedLocation = kRealTimeLocationAll;

  final ScrollController _scrollCtrl = ScrollController();

  ViewDocRowsStore? _store;
  int _storeRev = 0;
  String _storeArea = '';
  AreaState? _areaState;
  UserState? _userState;
  RealTimeSortState? _sortState;

  final Map<String, PlateModel> _plateDetailCache = <String, PlateModel>{};
  final Map<String, Future<PlateModel?>> _plateDetailInflight =
  <String, Future<PlateModel?>>{};

  bool _openingDetail = false;
  bool _zoneNavigationTraceBusy = false;
  bool _sortOrderTraceBusy = false;
  bool _sortOldFirst = false;
  String _lastLocationBoardDebugSignature = '';

  RealTimeViewMode _viewMode = RealTimeViewMode.plate;

  List<LocationModel> _cachedLocations = <LocationModel>[];
  int _totalCapacityFromPrefs = 0;
  String _locationsLoadedArea = '';
  bool _loadingLocationMeta = false;
  bool _operationalDataSyncing = false;

  Map<String, int>? _pendingPlateCountsByDisplayName;
  bool _plateCountsApplyScheduled = false;
  Map<String, int>? _lastAppliedPlateCountsByDisplayName;

  @override
  bool get wantKeepAlive => true;

  void _markUserActivity() {
    widget.onUserActivity?.call();
  }

  String get _currentArea {
    final a1 = context.read<UserState>().currentArea.trim();
    final a2 = context.read<AreaState>().currentArea.trim();
    return a1.isNotEmpty ? a1 : a2;
  }

  bool _rowMatchesSelectedLocation(String rawLocation) {
    final selected = _selectedLocation.trim();
    if (selected.isEmpty || selected == kRealTimeLocationAll) return true;

    if (selected.contains(kRealTimeSegSep)) {
      return zoneKeyFromRowLocation(rawLocation) == selected;
    }

    return parentFromRowLocation(rawLocation) == selected;
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

    widget.controller.bind(_refreshFromUser);
    if (!widget.spec.zoneSupported) {
      _viewMode = RealTimeViewMode.plate;
    }

    _applyFilterAndSort();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bindProviders();
    _bindSortState();
    _pullFromStore(reason: 'didChangeDependencies');
    if (widget.spec.zoneSupported) {
      _ensureLocationMetaLoaded();
    }
  }

  @override
  void dispose() {
    widget.controller.unbind();
    _elapsedTicker?.cancel();
    _scrollCtrl.dispose();
    _store?.removeListener(_onStoreChanged);
    _areaState?.removeListener(_onAreaChanged);
    _userState?.removeListener(_onAreaChanged);
    _sortState?.removeListener(_onSortStateChanged);

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

  void _bindSortState() {
    RealTimeSortState? next;
    try {
      next = context.read<RealTimeSortState>();
    } catch (_) {
      next = null;
    }
    if (identical(_sortState, next)) return;
    _sortState?.removeListener(_onSortStateChanged);
    _sortState = next;
    _sortState?.addListener(_onSortStateChanged);
    _syncDerivedSortState(notify: false);
  }

  void _onSortStateChanged() {
    if (!mounted) return;
    _syncDerivedSortState(notify: true);
  }

  void _syncDerivedSortState({required bool notify}) {
    final state = _sortState;
    if (state == null) return;
    final usesLocation = state.usesLocation && widget.spec.zoneSupported;
    final nextMode = usesLocation ? RealTimeViewMode.zone : RealTimeViewMode.plate;
    final nextSelected = usesLocation
        ? state.selectedLocation
        : kRealTimeLocationAll;
    final nextSortOldFirst = state.sortOldFirst;
    final changed = _viewMode != nextMode ||
        _selectedLocation != nextSelected ||
        _sortOldFirst != nextSortOldFirst;
    _viewMode = nextMode;
    _selectedLocation = nextSelected;
    _sortOldFirst = nextSortOldFirst;
    if (usesLocation) {
      unawaited(_ensureLocationMetaLoaded());
    }
    if (!changed) return;
    debugPrint(
      '[RealTimePriority] screen=${widget.screen} tab=${widget.spec.id} priority=${state.priorityMode.name} mode=${state.mode.name} order=${state.timeOrderLabel} view=${_viewMode.name} selected=$_selectedLocation',
    );
    if (notify) {
      setState(_applyFilterAndSort);
    } else {
      _applyFilterAndSort();
    }
    if (!usesLocation) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollCtrl.hasClients) return;
        final reduceMotion =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false;
        if (reduceMotion) {
          _scrollCtrl.jumpTo(0);
        } else {
          unawaited(
            _scrollCtrl.animateTo(
              0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
            ),
          );
        }
      });
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
        isSelected: e.isSelected,
        selectedBy: e.selectedBy,
      ),
    )
        .toList(growable: false);

    setState(() {
      _allRows = List<RealTimeRowVM>.of(rows);
      if (!widget.spec.zoneSupported) {
        _viewMode = RealTimeViewMode.plate;
      }

      _applyFilterAndSort();
      _loading = false;
      _hasFetchedFromServer = true;
    });

    if (widget.spec.syncLocationCounts) {
      _syncLocationPickerCountsFromRows(_allRows);
    }
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

      _locationsLoadedArea = area;

    } finally {
      _loadingLocationMeta = false;
      if (mounted) setState(() {});
    }
  }

  String _operationalSyncDebugMessage(
    String event, {
    OperationalDataSyncResult? result,
    Object? error,
  }) {
    final parts = <String>[
      '[REALTIME_ZONE_SYNC]',
      'timestamp=${DateTime.now().toIso8601String()}',
      'screen=${widget.screen}',
      'area=${_currentArea.trim()}',
      'event=$event',
      'cacheCount=${_cachedLocations.length}',
      'syncing=$_operationalDataSyncing',
    ];
    if (result != null) parts.add('result=${result.name}');
    if (error != null) parts.add('error=$error');
    return parts.join(' ');
  }

  Future<void> _downloadOperationalDataForCurrentArea() async {
    if (_operationalDataSyncing) {
      debugPrint(_operationalSyncDebugMessage('duplicate_tap_ignored'));
      return;
    }

    debugPrint(_operationalSyncDebugMessage('download_requested'));
    _markUserActivity();
    widget.onAutoPauseStart?.call();

    if (mounted) {
      setState(() => _operationalDataSyncing = true);
    }

    try {
      final result = await OperationalDataSyncWorkflow.run(
        context: context,
        title: '현재 지역 데이터 내려받기',
        message: '현재 지역의 주차 구역, 섹터, 정산 데이터를 로컬에 내려받기 전 요청을 준비하고 있습니다.',
        useCommonUi: true,
      );

      debugPrint(
        _operationalSyncDebugMessage(
          'download_finished',
          result: result,
        ),
      );

      if (result == OperationalDataSyncResult.completed && mounted) {
        await _ensureLocationMetaLoaded(force: true);
      }
    } catch (error, stackTrace) {
      debugPrint(
        _operationalSyncDebugMessage(
          'download_exception',
          error: error,
        ),
      );
      debugPrintStack(
        label: '[REALTIME_ZONE_SYNC] stackTrace',
        stackTrace: stackTrace,
      );
    } finally {
      widget.onAutoPauseEnd?.call();
      _markUserActivity();
      if (mounted) {
        setState(() => _operationalDataSyncing = false);
      }
    }
  }

  Widget _buildMissingLocationCacheDownload(
    ColorScheme cs,
    TextTheme text,
  ) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final content = Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_download_rounded,
                size: 38,
                color: cs.primary,
              ),
              const SizedBox(height: 12),
              Text(
                '현재 지역에 대한 데이터를 1회 내려받아야 합니다.',
                textAlign: TextAlign.center,
                style: text.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w700,
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _operationalDataSyncing
                    ? null
                    : _downloadOperationalDataForCurrentArea,
                icon: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: _operationalDataSyncing
                      ? const SizedBox(
                          key: ValueKey<String>('syncing'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(
                          Icons.download_rounded,
                          key: ValueKey<String>('download'),
                        ),
                ),
                label: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  child: Text(
                    _operationalDataSyncing ? '내려받는 중' : '지금 내려받기',
                    key: ValueKey<bool>(_operationalDataSyncing),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (reduceMotion) return content;

    return TweenAnimationBuilder<double>(
      key: const ValueKey<String>('missing_location_cache_download'),
      tween: Tween<double>(begin: 0, end: 1),
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - value)),
            child: Transform.scale(
              scale: 0.985 + (0.015 * value),
              child: child,
            ),
          ),
        );
      },
      child: content,
    );
  }

  void _applyFilterAndSort() {
    if (!widget.spec.zoneSupported) {
      _viewMode = RealTimeViewMode.plate;
    }

    if (_viewMode != RealTimeViewMode.plate) {
      _rows = List<RealTimeRowVM>.of(_allRows);
      _scheduleElapsedTicker();
      return;
    }

    _rows = _allRows.where((r) {
      return _rowMatchesSelectedLocation(r.location);
    }).toList();

    _rows.sort((a, b) {
      final ca = a.createdAt;
      final cb = b.createdAt;

      if (ca == null && cb == null) {
        return naturalLocationCompare(a.plateNumber, b.plateNumber);
      }
      if (ca == null) return 1;
      if (cb == null) return -1;

      final cmp = ca.compareTo(cb);
      if (cmp != 0) return _sortOldFirst ? cmp : -cmp;
      return naturalLocationCompare(a.plateNumber, b.plateNumber);
    });

    _scheduleElapsedTicker();
  }

  void _scheduleElapsedTicker() {
    _elapsedTicker?.cancel();
    if (!mounted || _viewMode != RealTimeViewMode.plate || _rows.isEmpty) {
      return;
    }

    _elapsedNow = DateTime.now();
    final hasSecondPrecision = _rows.any((row) {
      final createdAt = row.createdAt;
      if (createdAt == null) return false;
      final age = _elapsedNow.difference(createdAt);
      return age.isNegative || age.inSeconds < 60;
    });
    final hasMinutePrecision = _rows.any((row) {
      final createdAt = row.createdAt;
      if (createdAt == null) return false;
      final age = _elapsedNow.difference(createdAt);
      return !age.isNegative && age.inHours < 24;
    });

    Duration delay;
    if (hasSecondPrecision) {
      delay = const Duration(seconds: 1);
    } else if (hasMinutePrecision) {
      final seconds = 60 - _elapsedNow.second;
      delay = Duration(seconds: seconds == 0 ? 60 : seconds);
    } else {
      final minutes = 59 - _elapsedNow.minute;
      final seconds = 60 - _elapsedNow.second;
      delay = Duration(minutes: minutes, seconds: seconds);
      if (delay <= Duration.zero) {
        delay = const Duration(hours: 1);
      }
    }

    _elapsedTicker = Timer(delay, () {
      if (!mounted) return;
      setState(() {
        _elapsedNow = DateTime.now();
      });
      _scheduleElapsedTicker();
    });
  }

  String _formatElapsed(DateTime? createdAt) {
    if (createdAt == null) return '—';
    final elapsed = _elapsedNow.difference(createdAt);
    if (elapsed.isNegative || elapsed.inSeconds < 10) return '방금';
    if (elapsed.inSeconds < 60) return '${elapsed.inSeconds}초';
    if (elapsed.inMinutes < 60) return '${elapsed.inMinutes}분';
    if (elapsed.inHours < 24) {
      final minutes = elapsed.inMinutes.remainder(60);
      if (minutes == 0) return '${elapsed.inHours}시간';
      return '${elapsed.inHours}시간 ${minutes}분';
    }
    if (elapsed.inDays >= 100) return '99일+';
    final hours = elapsed.inHours.remainder(24);
    if (hours == 0) return '${elapsed.inDays}일';
    return '${elapsed.inDays}일 ${hours}시간';
  }

  String _tableLocationLabel(String rawLocation) {
    final segments = splitLocationSegments(rawLocation);
    if (segments.isEmpty) return '—';
    if (segments.length == 1) return segments.first;
    return '${segments[0]} › ${segments[1]}';
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
      } finally {
        _plateDetailInflight.remove(id);
      }
    }();

    _plateDetailInflight[id] = fut;
    return fut;
  }

  Future<void> _openHybridDetailPopup(
    RealTimeRowVM r, {
    String source = 'sort_priority_table',
  }) async {
    if (_openingDetail) return;
    _openingDetail = true;
    _markUserActivity();
    widget.onAutoPauseStart?.call();

    DeveloperOperationTrace? trace;
    BuildContext? rootCtx;

    try {
      final plateId = r.plateId.trim();
      if (plateId.isEmpty) return;

      final dockContext = Navigator.of(context, rootNavigator: true).context;
      rootCtx = dockContext;
      trace = await DeveloperOperationTrace.start(
        context: context,
        title: '실시간 상태 빠른 실행',
        initialMessage: '상태 처리 빠른 실행을 준비했습니다.',
        useCommonUi: true,
        developerModeMessage:
            '개발자 모드 ON: 완료 후 빠른 실행 debugPrint 코드를 복사할 수 있습니다.',
        standardModeMessage: '개발자 모드 OFF',
        showDialogImmediately: false,
      );

      final cachedPlate = _plateDetailCache[plateId];
      trace.log(
        'source=$source, priority=${_sortState?.priorityMode.name ?? '-'}, tab=${widget.spec.id}, area=${_currentArea.trim()}, plateId=$plateId, plateNumber=${r.plateNumber}, location=${r.location}, cached=${cachedPlate != null}, autoTransitionPaused=true',
        progress: .28,
      );

      _trace(
        '상태 처리 오른쪽 사이드 도크 즉시 오픈',
        meta: <String, dynamic>{
          'screen': widget.screen,
          'action': 'open_status_side_dock_immediately',
          'source': source,
          'tabId': widget.spec.id,
          'area': _currentArea,
          'plateId': plateId,
          'plateNumber': r.plateNumber,
          'location': r.location,
          'plateDetailCached': cachedPlate != null,
        },
      );

      if (!mounted || !dockContext.mounted) return;

      await widget.spec.openStatusDock(
        dockContext,
        RealTimePlateDetailRequest(
          plateId: plateId,
          plateNumber: r.plateNumber,
          area: _currentArea,
          location: r.location,
          statusTitle: '${widget.spec.label} 상태 처리',
          cachedPlate: cachedPlate,
          loadPlate: () => _fetchPlateDetail(plateId),
        ),
      );
      trace.log(
        'statusDock=closed, source=$source, nextIdleTransition=5s_after_resume',
        progress: .9,
      );
      await trace.succeed('상태 처리 빠른 실행이 종료되었습니다.');
    } catch (error, stackTrace) {
      if (trace != null) {
        await trace.fail(
          '상태 처리 빠른 실행 중 오류가 발생했습니다.',
          error: error,
          stackTrace: stackTrace,
        );
      }
      rethrow;
    } finally {
      if (trace != null &&
          trace.developerMode &&
          rootCtx != null &&
          rootCtx.mounted) {
        await trace.showStatusDialog(rootCtx);
      }
      widget.onAutoPauseEnd?.call();
      _markUserActivity();
      _openingDetail = false;
    }
  }


  void _onZoneParentPageChanged(String parent, int index, int count) {
    if (!widget.spec.zoneSupported) return;
    _markUserActivity();
    debugPrint(
      '[RealTimeZonePriority] source=zone_parent_pager action=page_changed parent=$parent index=$index count=$count design=status_dot_map interaction=parent_child_slot parentTap=child_zone parentSlotTap=disabled childViewport=crop_fit childSlotTap=status_dock childFocusAutoPause=true systemBack=parent_overview occupiedLabel=plate_last4 slotHitPolicy=collision_safe_partition gesturePolicy=raw_single_pointer_pager pageViewPhysics=never_scrollable',
    );
    unawaited(
      _showZoneParentPageTrace(
        parent: parent,
        index: index,
        count: count,
      ),
    );
  }

  Future<void> _showZoneParentPageTrace({
    required String parent,
    required int index,
    required int count,
  }) async {
    if (_zoneNavigationTraceBusy || !mounted) return;
    _zoneNavigationTraceBusy = true;
    try {
      final state = _sortState;
      final trace = await DeveloperOperationTrace.start(
        context: context,
        title: '구역 부모 전환',
        initialMessage:
            'source=zone_parent_pager action=page_changed parent=$parent index=$index count=$count',
        useCommonUi: true,
        showDialogImmediately: false,
        developerModeMessage:
            '개발자 모드 ON: 부모 DOT MAP 좌우 전환 상태를 확인할 수 있습니다.',
        standardModeMessage: '일반 모드: 부모 주차 구역을 좌우로 전환합니다.',
      );
      trace.log(
        'priority=${state?.priorityMode.name ?? '-'} mode=${state?.mode.name ?? '-'} order=${state?.timeOrderLabel ?? '-'} parent=$parent page=${index + 1}/$count parentPaging=horizontal gesturePolicy=raw_single_pointer_pager pageViewPhysics=never_scrollable pageSettle=220ms design=status_dot_map interaction=parent_child_slot parentTap=child_zone parentSlotTap=disabled childViewport=crop_fit childSlotTap=status_dock childFocusAutoPause=true systemBack=parent_overview occupiedLabel=plate_last4 slotHitPolicy=collision_safe_partition firebaseAdditionalRead=0',
        progress: .82,
      );
      await trace.succeed('부모 주차 구역 DOT MAP 전환 상태를 반영했습니다.');
      if (!mounted || !trace.developerMode) return;
      widget.onAutoPauseStart?.call();
      try {
        final rootContext = Navigator.of(context, rootNavigator: true).context;
        if (rootContext.mounted) {
          await trace.showStatusDialog(rootContext);
        }
      } finally {
        widget.onAutoPauseEnd?.call();
        _markUserActivity();
      }
    } finally {
      _zoneNavigationTraceBusy = false;
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

      final parent = parentFromRowLocation(raw);
      if (parent.isNotEmpty) {
        rawCounts[parent] = (rawCounts[parent] ?? 0) + 1;
      }

      final childKey = zoneKeyFromRowLocation(raw);
      if (childKey.isNotEmpty) {
        rawCounts[childKey] = (rawCounts[childKey] ?? 0) + 1;
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

  Widget _buildSortSummaryPill(ColorScheme cs, TextTheme text) {
    final state = _sortState;
    final zone = state?.isZonePriority ?? false;
    final summary = state?.summaryLabel ?? '정렬 · 최신순';
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final accent = zone;
    return Semantics(
      label: '현재 보기 · $summary',
      child: AnimatedContainer(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: accent
              ? cs.primaryContainer.withOpacity(.62)
              : cs.surfaceContainerLow,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accent
                ? cs.primary.withOpacity(.72)
                : cs.outlineVariant.withOpacity(.65),
          ),
        ),
        child: Row(
          children: [
            AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: .88, end: 1).animate(animation),
                  child: child,
                ),
              ),
              child: Icon(
                zone ? Icons.grid_view_rounded : Icons.sort_rounded,
                key: ValueKey<bool>(zone),
                size: 18,
                color: accent ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: AnimatedSwitcher(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0, .14),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: Text(
                  summary,
                  key: ValueKey<String>(summary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: text.labelMedium?.copyWith(
                    color: accent ? cs.primary : cs.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
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

  Future<void> _toggleTimeOrderFromHeader() async {
    final state = _sortState;
    if (state == null || _viewMode != RealTimeViewMode.plate) return;
    _markUserActivity();
    final before = state.timeOrderLabel;
    state.toggleTimeOrder(reason: 'real_time_table_elapsed_header');
    final after = state.timeOrderLabel;
    final oldestAfter = state.isOldest;
    debugPrint(
      '[RealTimeSortOrder] source=real_time_table_header action=toggle_sort_order before=$before after=$after sortField=createdAt nullCreatedAt=last animation=header_rotation_190ms_rows_fade_slide_200ms',
    );
    if (_sortOrderTraceBusy || !mounted) return;
    _sortOrderTraceBusy = true;
    try {
      final trace = await DeveloperOperationTrace.start(
        context: context,
        title: '실시간 정렬 변경',
        initialMessage:
            'source=real_time_table_header action=toggle_sort_order before=$before after=$after sortField=createdAt',
        useCommonUi: true,
        showDialogImmediately: false,
        developerModeMessage:
            '개발자 모드 ON: 정렬 변경 상태를 Status Dialog에서 확인할 수 있습니다.',
        standardModeMessage: '일반 모드: 경과 헤더를 눌러 정렬을 즉시 변경합니다.',
      );
      trace.log(
        'priority=${state.priorityMode.name} order=$after oldest=$oldestAfter field=createdAt nullCreatedAt=last headerTouchTarget=44dp headerAnimation=rotation_190ms rowsAnimation=fade_slide_200ms reducedMotion=${MediaQuery.maybeOf(context)?.disableAnimations ?? false}',
        progress: .82,
      );
      await trace.succeed('$after 정렬로 변경했습니다.');
      if (!mounted || !trace.developerMode) return;
      widget.onAutoPauseStart?.call();
      try {
        final rootContext = Navigator.of(context, rootNavigator: true).context;
        if (rootContext.mounted) {
          await trace.showStatusDialog(rootContext);
        }
      } finally {
        widget.onAutoPauseEnd?.call();
        _markUserActivity();
      }
    } finally {
      _sortOrderTraceBusy = false;
    }
  }

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
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final motionDuration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 160);

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
                flex: 3,
                child: Semantics(
                  button: true,
                  label: _sortOldFirst
                      ? '경과 · 오래된순 · 누르면 최신순으로 변경'
                      : '경과 · 최신순 · 누르면 오래된순으로 변경',
                  child: Tooltip(
                    message: _sortOldFirst
                        ? '오래된순 · 누르면 최신순'
                        : '최신순 · 누르면 오래된순',
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => unawaited(_toggleTimeOrderFromHeader()),
                        borderRadius: BorderRadius.circular(10),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(minHeight: 44),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                Flexible(
                                  child: Text(
                                    '경과',
                                    style: headStyle,
                                    maxLines: 1,
                                    softWrap: false,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 3),
                                AnimatedRotation(
                                  turns: _sortOldFirst ? .5 : 0,
                                  duration: reduceMotion
                                      ? Duration.zero
                                      : const Duration(milliseconds: 190),
                                  curve: Curves.easeOutCubic,
                                  child: Icon(
                                    Icons.arrow_upward_rounded,
                                    size: 16,
                                    color: cs.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 7,
                child: Text(
                  'Plate',
                  style: headStyle,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 5,
                child: Text(
                  'Location',
                  style: headStyle,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: TweenAnimationBuilder<double>(
            key: ValueKey<String>(
              'table_rows:${_sortOldFirst ? 'oldest' : 'newest'}',
            ),
            tween: Tween<double>(begin: 0, end: 1),
            duration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return Opacity(
                opacity: value,
                child: Transform.translate(
                  offset: Offset(0, (1 - value) * 6),
                  child: child,
                ),
              );
            },
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
                final elapsedText = _formatElapsed(r.createdAt);
                final locationText = _tableLocationLabel(r.location);

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
                            flex: 3,
                            child: Semantics(
                              label: r.createdAt == null
                                  ? '경과시간 정보 없음'
                                  : '경과 $elapsedText',
                              child: Align(
                                alignment: Alignment.centerRight,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerRight,
                                  child: AnimatedSwitcher(
                                    duration: motionDuration,
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) {
                                      if (reduceMotion) return child;
                                      final curved = CurvedAnimation(
                                        parent: animation,
                                        curve: Curves.easeOutCubic,
                                        reverseCurve: Curves.easeInCubic,
                                      );
                                      return FadeTransition(
                                        opacity: curved,
                                        child: SlideTransition(
                                          position: Tween<Offset>(
                                            begin: const Offset(0, .08),
                                            end: Offset.zero,
                                          ).animate(curved),
                                          child: child,
                                        ),
                                      );
                                    },
                                    child: Text(
                                      elapsedText,
                                      key: ValueKey<String>(elapsedText),
                                      style: monoStyle.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 7,
                            child: Row(
                              children: [
                                Flexible(
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      r.plateNumber,
                                      style: cellStyle.copyWith(
                                        fontWeight: FontWeight.w900,
                                      ),
                                      maxLines: 1,
                                      softWrap: false,
                                    ),
                                  ),
                                ),
                                if (r.isSelected) ...[
                                  const SizedBox(width: 6),
                                  _DrivingBadge(
                                    colorScheme: cs,
                                    textTheme: text,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 5,
                            child: Semantics(
                              label: 'Location $locationText',
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: AnimatedSwitcher(
                                  duration: motionDuration,
                                  switchInCurve: Curves.easeOutCubic,
                                  switchOutCurve: Curves.easeInCubic,
                                  transitionBuilder: (child, animation) {
                                    if (reduceMotion) return child;
                                    return FadeTransition(
                                      opacity: animation,
                                      child: child,
                                    );
                                  },
                                  child: Text(
                                    locationText,
                                    key: ValueKey<String>(locationText),
                                    style: cellStyle.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                                    maxLines: 1,
                                    softWrap: false,
                                  ),
                                ),
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
        ),
      ],
    );
  }

  Widget _buildLocationBoard(ColorScheme cs, TextTheme text) {
    if (!widget.spec.zoneSupported) {
      return const RealTimeExpandedEmpty(
        message: '해당 탭에서는 구역 보기를 지원하지 않습니다.',
      );
    }

    if (_loadingLocationMeta && _cachedLocations.isEmpty) {
      return const RealTimeExpandedLoading();
    }

    if (_cachedLocations.isEmpty) {
      return _buildMissingLocationCacheDownload(cs, text);
    }

    final state = _sortState;
    if (state == null || !state.isZonePriority) {
      return const RealTimeExpandedEmpty(
        message: '구역 보기 상태를 확인할 수 없습니다.',
      );
    }

    final groups = buildZoneGroups(
      rows: _allRows,
      meta: _cachedLocations,
      selected: kRealTimeLocationAll,
      search: '',
    );

    if (groups.isEmpty) {
      return const RealTimeExpandedEmpty(
        message: '표시할 주차 구역 데이터가 없습니다.',
      );
    }

    final parentGridReady = groups
        .where((item) => item.parentSource?.parkingGrid != null)
        .length;
    final occupiedCount =
        groups.fold<int>(0, (sum, item) => sum + item.totalCurrent);
    final signature =
        '${state.revision}|parent_child_dot_map|${groups.length}|$parentGridReady|$occupiedCount';
    if (_lastLocationBoardDebugSignature != signature) {
      _lastLocationBoardDebugSignature = signature;
      debugPrint(
        '[RealTimeZonePriority] render mode=parent_child_dot_map design=status_dot_map parents=${groups.length} parentGridReady=$parentGridReady occupied=$occupiedCount parentPaging=horizontal gesturePolicy=raw_single_pointer_pager pageViewPhysics=never_scrollable interaction=parent_child_slot parentTap=child_zone parentSlotTap=disabled childViewport=crop_fit childSlotTap=status_dock childFocusAutoPause=true systemBack=parent_overview occupiedLabel=plate_last4 slotHitPolicy=collision_safe_partition firebaseAdditionalRead=0',
      );
    }

    return RealTimeLocationBoard(
      groups: groups,
      onPlateTap: (row) {
        unawaited(
          _openHybridDetailPopup(
            row,
            source: 'zone_child_focus_slot',
          ),
        );
      },
      onParentPageChanged: _onZoneParentPageChanged,
      onUserActivity: _markUserActivity,
      onAutoPauseStart: widget.onAutoPauseStart,
      onAutoPauseEnd: widget.onAutoPauseEnd,
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
          if (_viewMode == RealTimeViewMode.plate || !widget.spec.zoneSupported) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
              child: _buildSortSummaryPill(cs, text),
            ),
            Divider(height: 1, color: cs.outlineVariant.withOpacity(.7)),
          ],
          Expanded(
            child: AnimatedSwitcher(
              duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                  ? Duration.zero
                  : const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                final mode = _sortState?.mode ?? RealTimeSortMode.table;
                final horizontalOffset =
                    mode == RealTimeSortMode.locationParent ? -.025 : 0.0;
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(horizontalOffset, 0),
                      end: Offset.zero,
                    ).animate(curved),
                    child: ScaleTransition(
                      scale: Tween<double>(begin: .99, end: 1).animate(curved),
                      child: child,
                    ),
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<String>(
                  '${_viewMode.name}:${_selectedLocation}',
                ),
                child: (_viewMode == RealTimeViewMode.plate ||
                        !widget.spec.zoneSupported)
                    ? _buildTable(cs)
                    : _buildLocationBoard(cs, text),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
