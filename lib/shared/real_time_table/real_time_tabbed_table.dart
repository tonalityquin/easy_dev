import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/utils/status_dialog.dart';
import '../../app/utils/developer_operation_status_dialog.dart';
import '../../app/utils/operational_data_sync_workflow.dart';
import '../../design_system/common_ui/common_ui_components.dart';
import '../../design_system/common_ui/common_ui_theme.dart';
import '../../features/account/applications/user_state.dart';
import '../../features/location/applications/location_state.dart';
import '../../features/location/domain/models/grid_rect.dart';
import '../../features/location/domain/models/location_model.dart';
import '../../features/location/domain/models/parking_grid_model.dart';
import '../../features/dev/application/area_state.dart';
import '../page/application/common/type_auto_transition_guard.dart';
import '../page/application/common/type_page_quick_action_scope.dart';
import '../page/application/common/type_view_mode_state.dart';
import '../plate/application/common/view_doc_rows_store.dart';
import 'real_time_tab_controller.dart';
import 'real_time_table_body.dart';
import 'real_time_table_components.dart';
import 'real_time_table_spec.dart';
import 'real_time_sort_state.dart';
import 'real_time_source_rect_modal.dart';
import 'real_time_parent_map_thumbnail.dart';
import 'real_time_table_zone.dart';

class RealTimeViewModeAutoSpec {
  final Duration idleToStatusAfter;

  const RealTimeViewModeAutoSpec({
    this.idleToStatusAfter = const Duration(seconds: 5),
  });
}

class RealTimeTabbedTable extends StatefulWidget {
  final List<RealTimeTabSpec> tabs;
  final RealTimeTabBarStyle tabBarStyle;
  final int initialIndex;
  final String screen;
  final String description;
  final Widget Function(
      BuildContext context,
      RealTimeTabSpec spec,
      RealTimeTabController controller,
      )? bodyBuilder;

  final RealTimeViewModeAutoSpec? viewModeAuto;
  final bool useListContextSurface;
  final bool showColoredSwipeChevrons;

  const RealTimeTabbedTable({
    super.key,
    required this.tabs,
    required this.tabBarStyle,
    required this.initialIndex,
    required this.screen,
    required this.description,
    this.bodyBuilder,
    this.viewModeAuto,
    this.useListContextSurface = false,
    this.showColoredSwipeChevrons = false,
  }) : assert(tabs.length > 0);

  @override
  State<RealTimeTabbedTable> createState() => _RealTimeTabbedTableState();
}

class _RealTimeTabbedTableState extends State<RealTimeTabbedTable>
    with TickerProviderStateMixin {
  static const double _modeReelTravel = 44;
  static const double _modeReelDistanceThreshold = 22;
  static const double _modeReelVelocityThreshold = 320;
  static const double _tableSwipeVisualActivationDistance = 14;
  static const double _tableSwipeCommitDistanceThreshold = 42;
  static const double _tableSwipeVelocityThreshold = 320;
  static const double _tableSwipeHintIdleOpacity = .40;
  static const double _tableSwipeHintActiveOpacity = .88;
  static const double _tableSwipeHintOppositeOpacity = .12;
  static const double _tableSwipeHintMaxTranslate = 4;
  static const double _tableSwipeHintMaxScale = 1.06;
  static const Duration _parentSelectorReopenCooldown =
      Duration(milliseconds: 180);

  late int _currentTableIndex;
  late final AnimationController _hudPulseController;
  late final AnimationController _tableSwipeController;
  late final AnimationController _statusVisualPulseController;
  late final AnimationController _modeReelController;
  late final AnimationController _modeReelHintController;
  final GlobalKey _modeReelSourceKey = GlobalKey(debugLabel: 'mode-reel-source');

  late final List<RealTimeTabController> _controllers;

  double _horizontalDragDistance = 0;
  double _horizontalSwipeViewportWidth = 1;
  bool _horizontalDragActive = false;
  bool _tableSwipeVisualActivated = false;
  bool _tableTransitioning = false;
  bool _tableSwipeGuardBlocked = false;
  int _swipePhysicalDirection = 0;
  int _swipeTableStep = 0;
  int _swipeDestinationIndex = -1;
  bool _tableSwipeHintSettlingCommit = false;
  double _tableSwipeHintSettleStartIntensity = 0;
  double _tableSwipeHintSettleStartControllerValue = 0;
  String? _lastTableContextBarLayoutSignature;

  double _modeReelDragDistance = 0;
  bool _modeReelDragActive = false;
  bool _modeReelTransitioning = false;
  bool _modeReelGuardBlocked = false;
  bool _modeReelDetentTriggered = false;
  int _modeReelPhysicalDirection = 0;
  int _modeReelDebugBucket = -1;
  TypeViewMode? _modeReelFromMode;
  bool _modeReelSelectorPressActive = false;
  bool _parentSelectorOpen = false;
  RealTimeSourceRectModalCollapseInfo? _lastParentSelectorCollapseInfo;
  String _lastParentSelectorCloseSource = 'route';
  DateTime? _parentSelectorReopenBlockedUntil;
  int _lastParentSelectorDuplicateCloseCount = 0;
  int _lastParentSelectorNavigatorPopCount = 0;

  bool _gatesLoaded = false;
  late List<bool> _enabled;

  TypeViewModeState? _viewMode;
  TypeAutoTransitionGuard? _autoGuard;
  LocationState? _locationState;
  Timer? _idleTimer;
  bool _idleSyncScheduled = false;

  bool _transitionMaskOn = false;
  String _transitionMaskMessage = '데이터 불러오는 중...';
  bool _debugDialogShowing = false;
  bool _operationalSyncRunning = false;
  bool _parkingCapabilityInitialized = false;
  bool _parkingCapabilitySyncScheduled = false;
  ParkingViewCapability _parkingViewCapability =
      ParkingViewCapability.loading;

  @override
  void initState() {
    super.initState();

    _enabled = List<bool>.filled(widget.tabs.length, false);
    _controllers = List<RealTimeTabController>.generate(
      widget.tabs.length,
      (index) => RealTimeTabController(debugLabel: widget.tabs[index].id),
    );

    _currentTableIndex =
        widget.initialIndex.clamp(0, widget.tabs.length - 1);

    _hudPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
      value: 0,
    )..addStatusListener(_onHudPulseStatus);

    _tableSwipeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 230),
      value: 0,
    );

    _statusVisualPulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 180),
      value: 0,
    )..addStatusListener(_onStatusVisualPulseStatus);

    _modeReelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 0,
    );

    _modeReelHintController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
      value: 0,
    );

    _loadGates();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachAutoGuardListener();
    _attachLocationStateListener();
    _syncSortContextAfterBuild();
    if (widget.viewModeAuto == null) {
      _detachViewModeListener();
      return;
    }
    TypeViewModeState? next;
    try {
      next = context.read<TypeViewModeState>();
    } catch (_) {
      next = null;
    }
    if (_viewMode != next) {
      _detachViewModeListener();
      _viewMode = next;
      _viewMode?.addListener(_onViewModeChanged);
    }
    _scheduleIdleSyncAfterBuild();
  }

  void _attachLocationStateListener() {
    LocationState? next;
    try {
      next = context.read<LocationState>();
    } catch (_) {
      next = null;
    }
    if (_locationState != next) {
      _locationState?.removeListener(_onLocationStateChanged);
      _locationState = next;
      _locationState?.addListener(_onLocationStateChanged);
    }
    _syncParkingCapabilityFromLocationState(rebuild: false);
  }

  void _detachLocationStateListener() {
    _locationState?.removeListener(_onLocationStateChanged);
    _locationState = null;
  }

  void _onLocationStateChanged() {
    if (!mounted) return;
    _syncParkingCapabilityFromLocationState(rebuild: true);
  }

  void _syncParkingCapabilityFromLocationState({required bool rebuild}) {
    final nextCapability =
        _locationState?.parkingViewCapability ??
            ParkingViewCapability.tableAndStatus;
    if (_parkingCapabilityInitialized &&
        _parkingViewCapability == nextCapability) {
      return;
    }
    final previous = _parkingViewCapability;
    if (rebuild && mounted) {
      setState(() {
        _parkingViewCapability = nextCapability;
        _parkingCapabilityInitialized = true;
      });
    } else {
      _parkingViewCapability = nextCapability;
      _parkingCapabilityInitialized = true;
    }
    _scheduleParkingCapabilitySync(
      previous: previous,
      next: nextCapability,
    );
  }

  Future<void> _runModeReelHintAnimation() async {
    if (!mounted || !_statusViewSupported) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _modeReelHintController.value = 0;
      return;
    }
    _modeReelHintController.stop();
    for (var index = 0; index < 2; index++) {
      if (!mounted || !_statusViewSupported) break;
      await _modeReelHintController.forward(from: 0);
      if (index == 0 && mounted && _statusViewSupported) {
        await Future<void>.delayed(const Duration(milliseconds: 120));
      }
    }
    if (mounted) {
      _modeReelHintController.value = 0;
    }
  }

  void _scheduleParkingCapabilitySync({
    required ParkingViewCapability previous,
    required ParkingViewCapability next,
  }) {
    if (_parkingCapabilitySyncScheduled) return;
    _parkingCapabilitySyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _parkingCapabilitySyncScheduled = false;
      if (!mounted) return;
      final statusEnabled =
          _parkingViewCapability == ParkingViewCapability.tableAndStatus;
      _viewMode?.setStatusEnabled(statusEnabled);
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (statusEnabled && !reduceMotion) {
        unawaited(_runModeReelHintAnimation());
      } else {
        _modeReelHintController.stop();
        _modeReelHintController.value = 0;
      }
      var locationCount = 0;
      var hierarchicalCount = 0;
      var singleCount = 0;
      try {
        final state = context.read<LocationState>();
        locationCount = state.locations.length;
        hierarchicalCount = state.hierarchicalLocationCount;
        singleCount = state.singleLocationCount;
      } catch (_) {}
      _debugLog('parking_view_capability', <String, Object?>{
        'previous': previous.name,
        'next': _parkingViewCapability.name,
        'locationCount': locationCount,
        'hierarchicalCount': hierarchicalCount,
        'singleCount': singleCount,
        'statusEnabled': statusEnabled,
        'autoTransition': statusEnabled,
        'modeControl': statusEnabled
            ? 'vertical_swipe_reel'
            : _parkingViewCapability == ParkingViewCapability.tableOnly
                ? 'static_table_indicator'
                : _parkingViewCapability == ParkingViewCapability.empty
                    ? 'download_surface'
                    : 'loading_surface',
        'firebaseAdditionalRead': 0,
      });
      _syncIdleWithMode();
      if (mounted) setState(() {});
    });
  }

  bool get _statusViewSupported =>
      _parkingViewCapability == ParkingViewCapability.tableAndStatus &&
      (_viewMode?.statusEnabled ?? true);

  void _scheduleIdleSyncAfterBuild() {
    if (_idleSyncScheduled) return;
    _idleSyncScheduled = true;
    _debugLog('idle_sync_scheduled', <String, Object?>{
      'screen': widget.screen,
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _idleSyncScheduled = false;
      if (!mounted) return;
      _debugLog('idle_sync_after_build', <String, Object?>{
        'mode': _viewMode?.mode.name,
        'sort': _sortStateSummary(),
      });
      _syncIdleWithMode();
    });
  }

  void _attachAutoGuardListener() {
    TypeAutoTransitionGuard? next;
    try {
      next = context.read<TypeAutoTransitionGuard>();
    } catch (_) {
      next = null;
    }
    if (_autoGuard == next) return;
    _autoGuard?.removeListener(_onAutoGuardChanged);
    _autoGuard = next;
    _autoGuard?.addListener(_onAutoGuardChanged);
    final auto = widget.viewModeAuto;
    _debugLog('initialized', <String, Object?>{
      'idleMs': auto?.idleToStatusAfter.inMilliseconds,
      'screen': widget.screen,
    });
  }

  void _detachAutoGuardListener() {
    _autoGuard?.removeListener(_onAutoGuardChanged);
    _autoGuard = null;
  }

  void _onAutoGuardChanged() {
    if (!mounted) return;
    _scheduleIdleFromGuard();
  }

  String _sortStateSummary() {
    try {
      return context.read<RealTimeSortState>().summaryLabel;
    } catch (_) {
      return 'unavailable';
    }
  }

  void _syncSortContextAfterBuild() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncSortContext();
    });
  }

  void _syncSortContext() {
    if (widget.tabs.isEmpty) return;
    final index = _currentTableIndex.clamp(0, widget.tabs.length - 1);
    final spec = widget.tabs[index];
    try {
      context.read<RealTimeSortState>().setActiveTab(
            tabId: spec.id,
            collection: spec.collection,
            locationSupported: spec.zoneSupported,
          );
    } catch (_) {}
  }

  void _detachViewModeListener() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _viewMode?.removeListener(_onViewModeChanged);
    _viewMode = null;
  }

  void _onViewModeChanged() {
    if (!mounted) return;
    if (_viewMode?.mode != TypeViewMode.table &&
        (_horizontalDragActive ||
            _tableTransitioning ||
            _tableSwipeController.value > 0)) {
      _horizontalDragActive = false;
      _tableTransitioning = false;
      _horizontalDragDistance = 0;
      _swipePhysicalDirection = 0;
      _swipeTableStep = 0;
      _swipeDestinationIndex = -1;
      _tableSwipeController.stop();
      _tableSwipeController.value = 0;
      _endTableSwipeGuard();
    }
    if (!_modeReelTransitioning &&
        (_modeReelDragActive || _modeReelController.value > 0)) {
      _modeReelDragActive = false;
      _modeReelDragDistance = 0;
      _modeReelPhysicalDirection = 0;
      _modeReelDebugBucket = -1;
      _modeReelDetentTriggered = false;
      _modeReelFromMode = null;
      _modeReelController.stop();
      _modeReelController.value = 0;
      _endModeReelGuard();
    }
    setState(() {});
    _debugLog('view_mode_changed', <String, Object?>{
      'mode': _viewMode?.mode.name,
      'table': widget.tabs[_currentTableIndex].id,
    });
    _syncIdleWithMode();
  }

  void _syncIdleWithMode() {
    final auto = widget.viewModeAuto;
    final vm = _viewMode;
    final guard = _autoGuard;
    if (auto == null || vm == null || guard == null) {
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }

    guard.setCountdownDuration(auto.idleToStatusAfter);

    if (!_statusViewSupported) {
      guard.setCountdownEnabled(false, reason: '현황 보기 미지원');
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }

    if (vm.mode != TypeViewMode.table) {
      guard.setCountdownEnabled(false, reason: '현황 모드');
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
    }

    guard.setCountdownEnabled(true, reason: '테이블 모드');
    _scheduleIdleFromGuard();
  }

  void _debugLog(
    String event, [
    Map<String, Object?> details = const <String, Object?>{},
  ]) {
    final guard = _autoGuard;
    if (guard != null) {
      guard.log(event, details);
      return;
    }
    final buffer = StringBuffer()
      ..write('[RealTimeViewMode] ')
      ..write(DateTime.now().toIso8601String())
      ..write(' event=')
      ..write(event);
    for (final entry in details.entries) {
      if (entry.value == null) continue;
      buffer
        ..write(' ')
        ..write(entry.key)
        ..write('=')
        ..write(entry.value);
    }
    debugPrint(buffer.toString());
  }

  Future<void> _showAutoSwitchDebugDialog() async {
    final guard = _autoGuard;
    if (!mounted || _debugDialogShowing || guard == null) return;
    await guard.refreshDeveloperMode();
    if (!guard.developerModeEnabled || !mounted || _debugDialogShowing) return;
    final code = guard.debugPrintCode.trim();
    if (code.isEmpty) return;
    _debugDialogShowing = true;
    try {
      await StatusDialog.showSuccess(
        context,
        title: '현황 자동 전환 디버그',
        description: guard.debugLines.join('\n'),
        copyText: code,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: const Duration(seconds: 45),
        useCommonUi: true,
      );
    } finally {
      _debugDialogShowing = false;
    }
  }

  void _scheduleIdleFromGuard() {
    _idleTimer?.cancel();
    _idleTimer = null;
    final auto = widget.viewModeAuto;
    final guard = _autoGuard;
    final vm = _viewMode;
    if (auto == null || guard == null || vm == null) return;
    if (!_statusViewSupported) return;
    if (vm.mode != TypeViewMode.table) return;
    if (!guard.countdownRunning) return;

    final remaining = guard.remaining;
    _idleTimer = Timer(remaining, () {
      if (!mounted) return;
      final currentGuard = _autoGuard;
      final currentVm = _viewMode;
      if (currentGuard == null || currentVm == null) return;
      if (!_statusViewSupported || !currentVm.statusEnabled) return;
      if (currentVm.mode != TypeViewMode.table) return;
      if (!currentGuard.countdownElapsed) {
        _scheduleIdleFromGuard();
        return;
      }
      _debugLog('idle_timeout', <String, Object?>{
        'thresholdMs': auto.idleToStatusAfter.inMilliseconds,
        'table': widget.tabs[_currentTableIndex].id,
      });
      unawaited(_runMaskedAutoSwitchToStatus(auto));
    });
  }

  Future<void> _runMaskedAutoSwitchToStatus(
    RealTimeViewModeAutoSpec auto,
  ) async {
    if (!mounted) return;
    if (_transitionMaskOn) return;
    final guard = _autoGuard;
    final vm = _viewMode;
    if (guard == null || vm == null) return;
    if (!_statusViewSupported || !vm.statusEnabled) return;
    if (vm.mode != TypeViewMode.table) return;
    if (!guard.countdownElapsed) return;

    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (_transitionMaskOn) return;
    if (!_statusViewSupported || _viewMode?.statusEnabled != true) return;
    if (_viewMode?.mode != TypeViewMode.table) return;
    if (!guard.countdownElapsed) {
      _debugLog('auto_switch_cancelled', <String, Object?>{
        'reason': guard.isBlocked ? guard.blockReason : 'activity',
      });
      return;
    }

    _debugLog('auto_switch_started', <String, Object?>{
      'from': TypeViewMode.table.name,
      'to': TypeViewMode.status.name,
      'thresholdMs': auto.idleToStatusAfter.inMilliseconds,
      'table': widget.tabs[_currentTableIndex].id,
    });

    setState(() {
      _transitionMaskMessage = '현황 전환 중...';
      _transitionMaskOn = true;
    });

    final started = DateTime.now();
    var switched = false;

    try {
      vm.setMode(TypeViewMode.status);
      switched = vm.mode == TypeViewMode.status;
      _debugLog('auto_switch_completed', <String, Object?>{
        'mode': vm.mode.name,
        'switched': switched,
      });
      await WidgetsBinding.instance.endOfFrame;
    } finally {
      final elapsed = DateTime.now().difference(started);
      const min = Duration(milliseconds: 500);
      if (elapsed < min) {
        await Future.delayed(min - elapsed);
      }
      if (!mounted) return;
      setState(() {
        _transitionMaskOn = false;
        _transitionMaskMessage = '데이터 불러오는 중...';
      });
    }

    if (switched && mounted) {
      unawaited(_showAutoSwitchDebugDialog());
    }
  }

  void _onUserActivity() {
    _autoGuard?.markActivity('table_body');
  }

  void _beginAutoPause() {
    _autoGuard?.beginBlock('테이블 다이얼로그');
  }

  void _endAutoPause() {
    _autoGuard?.endBlock('테이블 다이얼로그');
  }

  Duration _motionDuration(Duration duration) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return reduceMotion ? Duration.zero : duration;
  }

  Widget _sharedAxisYTransition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    final offset = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(curved);
    final scale = Tween<double>(begin: 0.985, end: 1).animate(curved);
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: offset,
        child: ScaleTransition(
          scale: scale,
          alignment: Alignment.center,
          child: child,
        ),
      ),
    );
  }

  Widget _transitionMaskSurface(
    BuildContext context, {
    required String message,
  }) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return AbsorbPointer(
      absorbing: true,
      child: Container(
        color: cs.surface,
        alignment: Alignment.center,
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
              style: (text.titleMedium ?? text.bodyLarge ?? const TextStyle())
                  .copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transitionMaskLayer(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_transitionMaskOn,
        child: AnimatedSwitcher(
          duration: _motionDuration(const Duration(milliseconds: 240)),
          reverseDuration: _motionDuration(const Duration(milliseconds: 180)),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: curved,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
                child: child,
              ),
            );
          },
          child: _transitionMaskOn
              ? KeyedSubtree(
                  key: ValueKey<String>(
                    'transition-mask:$_transitionMaskMessage',
                  ),
                  child: _transitionMaskSurface(
                    context,
                    message: _transitionMaskMessage,
                  ),
                )
              : const SizedBox.expand(
                  key: ValueKey<String>('transition-mask-off'),
                ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _endModeReelGuard();
    _endTableSwipeGuard();
    _detachViewModeListener();
    _detachAutoGuardListener();
    _detachLocationStateListener();
    _modeReelController.dispose();
    _modeReelHintController.dispose();
    _statusVisualPulseController.dispose();
    _tableSwipeController.dispose();
    _hudPulseController.dispose();
    super.dispose();
  }

  int _firstEnabledTableOr(int fallback) {
    if (fallback >= 0 && fallback < _enabled.length && _enabled[fallback]) {
      return fallback;
    }
    for (int i = 0; i < _enabled.length; i++) {
      if (_enabled[i]) return i;
    }
    return fallback.clamp(0, widget.tabs.length - 1);
  }

  Future<void> _loadGates() async {
    try {
      final results = <bool>[];
      for (final t in widget.tabs) {
        results.add(await t.isEnabled());
      }

      if (!mounted) return;

      setState(() {
        _enabled = results;
        _gatesLoaded = true;
        _currentTableIndex = _firstEnabledTableOr(_currentTableIndex);
      });
      _syncSortContextAfterBuild();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _enabled = List<bool>.filled(widget.tabs.length, false);
        _gatesLoaded = true;
        _currentTableIndex =
            widget.initialIndex.clamp(0, widget.tabs.length - 1);
      });
    }
  }

  bool _isTableEnabled(int idx) {
    if (idx < 0 || idx >= _enabled.length) return false;
    return _enabled[idx];
  }

  List<int> _enabledTableIndices() {
    if (!_gatesLoaded) return const <int>[];
    return List<int>.generate(widget.tabs.length, (index) => index)
        .where(_isTableEnabled)
        .toList(growable: false);
  }

  bool _canSwipeTables() {
    if (_viewMode?.mode != TypeViewMode.table) return false;
    if (_transitionMaskOn ||
        _tableTransitioning ||
        _modeReelDragActive ||
        _modeReelTransitioning ||
        _modeReelSelectorPressActive ||
        _parentSelectorOpen) {
      return false;
    }
    return _enabledTableIndices().length > 1;
  }

  int _targetTableIndex(int step) {
    final enabled = _enabledTableIndices();
    if (enabled.length <= 1) return _currentTableIndex;
    final currentPosition = enabled.indexOf(_currentTableIndex);
    if (currentPosition < 0) return enabled.first;
    final targetPosition =
        (currentPosition + step + enabled.length) % enabled.length;
    return enabled[targetPosition];
  }

  bool _isWrappedTransition(int fromIndex, int step) {
    final enabled = _enabledTableIndices();
    if (enabled.length <= 1) return false;
    final currentPosition = enabled.indexOf(fromIndex);
    if (currentPosition < 0) return false;
    if (step < 0) return currentPosition == 0;
    return currentPosition == enabled.length - 1;
  }

  void _beginTableSwipeGuard() {
    if (_tableSwipeGuardBlocked) return;
    final guard = _autoGuard;
    if (guard == null) return;
    guard.beginBlock('상태 테이블 스와이프');
    _tableSwipeGuardBlocked = true;
  }

  void _endTableSwipeGuard() {
    if (!_tableSwipeGuardBlocked) return;
    _tableSwipeGuardBlocked = false;
    _autoGuard?.endBlock('상태 테이블 스와이프');
  }

  int _tableStepForPhysicalDirection(int physicalDirection) {
    return physicalDirection < 0 ? 1 : -1;
  }

  String _physicalDirectionLabel(int physicalDirection) {
    return physicalDirection < 0 ? 'left' : 'right';
  }

  void _setSwipeDirection(int physicalDirection) {
    if (physicalDirection == 0) return;
    final tableStep = _tableStepForPhysicalDirection(physicalDirection);
    final destinationIndex = _targetTableIndex(tableStep);
    if (_swipePhysicalDirection == physicalDirection &&
        _swipeTableStep == tableStep &&
        _swipeDestinationIndex == destinationIndex) {
      return;
    }
    setState(() {
      _swipePhysicalDirection = physicalDirection;
      _swipeTableStep = tableStep;
      _swipeDestinationIndex = destinationIndex;
    });
    if (widget.showColoredSwipeChevrons &&
        destinationIndex >= 0 &&
        destinationIndex < widget.tabs.length) {
      final target = widget.tabs[destinationIndex];
      _debugLog('table_swipe_hint_target', <String, Object?>{
        'screen': widget.screen,
        'edge': physicalDirection < 0 ? 'right' : 'left',
        'physicalDirection': _physicalDirectionLabel(physicalDirection),
        'targetTable': target.id,
        'targetStatusColor': _statusVisualRole(target),
        'idleOpacity': _tableSwipeHintIdleOpacity,
        'activeOpacity': _tableSwipeHintActiveOpacity,
        'oppositeOpacity': _tableSwipeHintOppositeOpacity,
        'maxTranslateDp': _tableSwipeHintMaxTranslate,
        'maxScale': _tableSwipeHintMaxScale,
      });
    }
  }

  double _tableSwipeHintIntentProgress(double rawDistance) {
    final magnitude = rawDistance.abs();
    if (magnitude <= _tableSwipeVisualActivationDistance) return 0;
    final range = math.max(
      1.0,
      _tableSwipeCommitDistanceThreshold -
          _tableSwipeVisualActivationDistance,
    );
    return ((magnitude - _tableSwipeVisualActivationDistance) / range)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  double _tableSwipeHintStrength() {
    if (_horizontalDragActive) {
      return _tableSwipeHintIntentProgress(_horizontalDragDistance);
    }
    if (!_tableTransitioning ||
        _swipePhysicalDirection == 0 ||
        _tableSwipeHintSettleStartIntensity <= 0) {
      return 0;
    }
    final controllerValue =
        _tableSwipeController.value.clamp(0.0, 1.0).toDouble();
    final start =
        _tableSwipeHintSettleStartControllerValue.clamp(0.0, 1.0).toDouble();
    if (_tableSwipeHintSettlingCommit) {
      final remaining = 1 - start;
      if (remaining <= .0001) return 0;
      final t = ((controllerValue - start) / remaining)
          .clamp(0.0, 1.0)
          .toDouble();
      return _tableSwipeHintSettleStartIntensity *
          (1 - Curves.easeOutCubic.transform(t));
    }
    if (start <= .0001) return 0;
    final t = (controllerValue / start).clamp(0.0, 1.0).toDouble();
    return _tableSwipeHintSettleStartIntensity *
        Curves.easeOutCubic.transform(t);
  }

  double _tableSwipeVisualDistance(double rawDistance) {
    final magnitude = rawDistance.abs();
    if (magnitude <= _tableSwipeVisualActivationDistance) return 0;
    final visualMagnitude =
        magnitude - _tableSwipeVisualActivationDistance;
    return rawDistance < 0 ? -visualMagnitude : visualMagnitude;
  }

  double _swipeProgressForVisualDistance(double visualDistance) {
    final width = _horizontalSwipeViewportWidth <= 0
        ? 1.0
        : _horizontalSwipeViewportWidth;
    final usableWidth = math.max(
      1.0,
      width - _tableSwipeVisualActivationDistance,
    );
    return (visualDistance.abs() / usableWidth)
        .clamp(0.0, 1.0)
        .toDouble();
  }

  void _clearTableSwipeVisualState({bool rebuild = true}) {
    _tableSwipeController.value = 0;
    _tableSwipeVisualActivated = false;
    _swipePhysicalDirection = 0;
    _swipeTableStep = 0;
    _swipeDestinationIndex = -1;
    if (rebuild && mounted) {
      setState(() {});
    }
  }

  Duration _swipeSettleDuration({
    required double progress,
    required bool commit,
    required double velocity,
  }) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return Duration.zero;
    final remaining = commit ? 1 - progress : progress;
    final baseMs = commit ? 230 : 190;
    final minMs = commit ? 70 : 80;
    var milliseconds = (baseMs * remaining).round().clamp(minMs, baseMs);
    if (velocity.abs() >= 900) {
      milliseconds = milliseconds.clamp(minMs, 120);
    }
    return Duration(milliseconds: milliseconds.toInt());
  }

  void _onTableHorizontalDragStart(
    DragStartDetails _,
    double viewportWidth,
  ) {
    if (!_canSwipeTables()) return;
    _tableSwipeController.stop();
    _tableSwipeController.value = 0;
    _horizontalSwipeViewportWidth = viewportWidth <= 0 ? 1 : viewportWidth;
    _horizontalDragActive = true;
    _horizontalDragDistance = 0;
    _tableSwipeVisualActivated = false;
    _swipePhysicalDirection = 0;
    _swipeTableStep = 0;
    _swipeDestinationIndex = -1;
    _beginTableSwipeGuard();
    _onUserActivity();
    _debugLog('table_swipe_start', <String, Object?>{
      'screen': widget.screen,
      'table': widget.tabs[_currentTableIndex].id,
      'tableCount': _enabledTableIndices().length,
      'viewportWidth': _horizontalSwipeViewportWidth.toStringAsFixed(1),
      'visualActivationDistance': _tableSwipeVisualActivationDistance,
      'commitDistanceThreshold': _tableSwipeCommitDistanceThreshold,
      'velocityThreshold': _tableSwipeVelocityThreshold,
      'pageStructure': 'stable_stack',
      'currentPageState': 'preserved',
      'rowMountReveal': 'disabled',
      'horizontalOnly': true,
    });
  }

  void _onTableHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_horizontalDragActive) return;
    _horizontalDragDistance += details.delta.dx;
    final visualDistance =
        _tableSwipeVisualDistance(_horizontalDragDistance);
    if (visualDistance == 0) {
      if (_tableSwipeVisualActivated ||
          _swipePhysicalDirection != 0 ||
          _swipeDestinationIndex != -1 ||
          _tableSwipeController.value != 0) {
        _debugLog('table_swipe_visual_deactivated', <String, Object?>{
          'screen': widget.screen,
          'table': widget.tabs[_currentTableIndex].id,
          'rawDistance': _horizontalDragDistance.toStringAsFixed(1),
          'visualDistance': '0.0',
          'visualActivationDistance': _tableSwipeVisualActivationDistance,
        });
        _clearTableSwipeVisualState();
      } else {
        _tableSwipeController.value = 0;
      }
      return;
    }

    final physicalDirection = visualDistance < 0 ? -1 : 1;
    if (!_tableSwipeVisualActivated) {
      _tableSwipeVisualActivated = true;
      _debugLog('table_swipe_visual_activated', <String, Object?>{
        'screen': widget.screen,
        'table': widget.tabs[_currentTableIndex].id,
        'rawDistance': _horizontalDragDistance.toStringAsFixed(1),
        'visualDistance': visualDistance.toStringAsFixed(1),
        'physicalDirection': _physicalDirectionLabel(physicalDirection),
        'visualActivationDistance': _tableSwipeVisualActivationDistance,
        'pageStructure': 'stable_stack',
        'currentPageState': 'preserved',
        'rowMountReveal': 'disabled',
        'horizontalOnly': true,
      });
    }
    _setSwipeDirection(physicalDirection);
    _tableSwipeController.value =
        _swipeProgressForVisualDistance(visualDistance);
  }

  void _onTableHorizontalDragCancel() {
    if (!_horizontalDragActive) return;
    final distance = _horizontalDragDistance;
    final physicalDirection = _swipePhysicalDirection;
    _horizontalDragActive = false;
    unawaited(
      _cancelInteractiveTableSwipe(
        reason: 'gesture_cancelled',
        distance: distance,
        velocity: 0,
        physicalDirection: physicalDirection,
      ),
    );
  }

  void _onTableHorizontalDragEnd(DragEndDetails details) {
    if (!_horizontalDragActive) return;
    final distance = _horizontalDragDistance;
    final velocity = details.primaryVelocity ?? 0;
    _horizontalDragActive = false;

    final distanceAccepted =
        distance.abs() >= _tableSwipeCommitDistanceThreshold;
    final velocityAccepted =
        velocity.abs() >= _tableSwipeVelocityThreshold;
    if (!distanceAccepted && !velocityAccepted) {
      unawaited(
        _cancelInteractiveTableSwipe(
          reason: 'below_threshold',
          distance: distance,
          velocity: velocity,
          physicalDirection: _swipePhysicalDirection,
        ),
      );
      return;
    }

    final directionValue = velocityAccepted ? velocity : distance;
    final physicalDirection = directionValue < 0 ? -1 : 1;
    _setSwipeDirection(physicalDirection);
    unawaited(
      _commitInteractiveTableSwipe(
        physicalDirection: physicalDirection,
        distance: distance,
        velocity: velocity,
        source: 'gesture',
      ),
    );
  }

  Future<void> _cancelInteractiveTableSwipe({
    required String reason,
    required double distance,
    required double velocity,
    required int physicalDirection,
  }) async {
    final progress = _tableSwipeController.value.clamp(0.0, 1.0).toDouble();
    final visualDistance = _tableSwipeVisualDistance(distance);
    final visualActivated = _tableSwipeVisualActivated && progress > 0;
    final snapBack = visualActivated;
    final duration = snapBack
        ? _swipeSettleDuration(
            progress: progress,
            commit: false,
            velocity: velocity,
          )
        : Duration.zero;
    final tableStep = physicalDirection == 0
        ? 0
        : _tableStepForPhysicalDirection(physicalDirection);
    final hintTargetIndex = tableStep == 0 ? -1 : _targetTableIndex(tableStep);
    final hintTargetSpec = hintTargetIndex >= 0 &&
            hintTargetIndex < widget.tabs.length
        ? widget.tabs[hintTargetIndex]
        : null;
    _debugLog('table_swipe_cancelled', <String, Object?>{
      'reason': reason,
      'physicalDirection': physicalDirection == 0
          ? 'none'
          : _physicalDirectionLabel(physicalDirection),
      'tableStep': tableStep,
      'rawDistance': distance.toStringAsFixed(1),
      'visualDistance': visualDistance.toStringAsFixed(1),
      'visualActivated': visualActivated,
      'progress': progress.toStringAsFixed(3),
      'velocity': velocity.toStringAsFixed(1),
      'visualActivationDistance': _tableSwipeVisualActivationDistance,
      'commitDistanceThreshold': _tableSwipeCommitDistanceThreshold,
      'velocityThreshold': _tableSwipeVelocityThreshold,
      'snapBack': snapBack,
      'snapBackDurationMs': duration.inMilliseconds,
      'table': widget.tabs[_currentTableIndex].id,
      'swipeHintEnabled': widget.showColoredSwipeChevrons,
      'swipeHintEdge': physicalDirection == 0
          ? 'none'
          : physicalDirection < 0
              ? 'right'
              : 'left',
      'swipeHintTarget': hintTargetSpec?.id ?? 'none',
      'swipeHintTargetColor':
          hintTargetSpec == null ? 'none' : _statusVisualRole(hintTargetSpec),
      'statusSignatureScheme':
          'parking_requests=danger;parking_completed=success;departure_requests=info',
      'pageStructure': 'stable_stack',
      'currentPageState': 'preserved',
      'rowMountReveal': 'disabled',
      'verticalRowReplay': false,
    });

    _tableSwipeHintSettlingCommit = false;
    _tableSwipeHintSettleStartIntensity =
        _tableSwipeHintIntentProgress(distance);
    _tableSwipeHintSettleStartControllerValue = progress;
    _tableTransitioning = snapBack;
    try {
      if (!snapBack || duration == Duration.zero) {
        _tableSwipeController.value = 0;
      } else {
        await _tableSwipeController.animateTo(
          0,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      _horizontalDragDistance = 0;
      _tableTransitioning = false;
      _tableSwipeHintSettlingCommit = false;
      _tableSwipeHintSettleStartIntensity = 0;
      _tableSwipeHintSettleStartControllerValue = 0;
      _clearTableSwipeVisualState(rebuild: false);
      _endTableSwipeGuard();
      if (mounted) {
        setState(() {});
      }
      unawaited(
        _showControlStatus(
          title: 'TypePage 테이블 스와이프 취소',
          lines: <String>[
            'tableSwipeCancelled reason=$reason',
            'screen=${widget.screen}',
            'table=${widget.tabs[_currentTableIndex].id}',
            'rawDistance=${distance.toStringAsFixed(1)} visualDistance=${visualDistance.toStringAsFixed(1)}',
            'visualActivationDistance=$_tableSwipeVisualActivationDistance visualActivated=$visualActivated',
            'commitDistanceThreshold=$_tableSwipeCommitDistanceThreshold velocityThreshold=$_tableSwipeVelocityThreshold',
            'velocity=${velocity.toStringAsFixed(1)} progress=${progress.toStringAsFixed(3)}',
            'snapBack=$snapBack snapBackDurationMs=${duration.inMilliseconds}',
            'tapJitterProtected=${!visualActivated}',
            'swipeHintEnabled=${widget.showColoredSwipeChevrons}',
            'swipeHintEdge=${physicalDirection == 0 ? 'none' : physicalDirection < 0 ? 'right' : 'left'} target=${hintTargetSpec?.id ?? 'none'} targetColor=${hintTargetSpec == null ? 'none' : _statusVisualRole(hintTargetSpec)}',
            'swipeHintIdleOpacity=$_tableSwipeHintIdleOpacity swipeHintActiveOpacity=$_tableSwipeHintActiveOpacity swipeHintOppositeOpacity=$_tableSwipeHintOppositeOpacity',
            'swipeHintMaxTranslateDp=$_tableSwipeHintMaxTranslate swipeHintMaxScale=$_tableSwipeHintMaxScale',
            'pageStructure=stable_stack currentPageState=preserved',
            'rowMountReveal=disabled verticalRowReplay=false horizontalOnly=true',
            'firebaseAdditionalRead=0 firebaseAdditionalWrite=0',
          ],
        ),
      );
    }
  }

  Future<void> _commitInteractiveTableSwipe({
    required int physicalDirection,
    required double distance,
    required double velocity,
    required String source,
  }) async {
    if (!_canSwipeTables() && !_tableSwipeGuardBlocked) return;
    if (!_tableSwipeGuardBlocked) {
      _beginTableSwipeGuard();
    }
    _setSwipeDirection(physicalDirection);

    final fromIndex = _currentTableIndex;
    final tableStep = _tableStepForPhysicalDirection(physicalDirection);
    final toIndex = _targetTableIndex(tableStep);
    if (toIndex == fromIndex) {
      await _cancelInteractiveTableSwipe(
        reason: 'same_destination',
        distance: distance,
        velocity: velocity,
        physicalDirection: physicalDirection,
      );
      return;
    }

    final fromSpec = widget.tabs[fromIndex];
    final toSpec = widget.tabs[toIndex];
    final wrapped = _isWrappedTransition(fromIndex, tableStep);
    final area = _readCurrentArea();
    final progress = _tableSwipeController.value.clamp(0.0, 1.0).toDouble();
    final duration = _swipeSettleDuration(
      progress: progress,
      commit: true,
      velocity: velocity,
    );
    final direction = _physicalDirectionLabel(physicalDirection);
    final visualActivatedAtCommit = _tableSwipeVisualActivated;

    _tableSwipeHintSettlingCommit = true;
    _tableSwipeHintSettleStartIntensity = math.max(
      _tableSwipeHintIntentProgress(distance),
      source == 'gesture' ? .72 : .88,
    ).toDouble();
    _tableSwipeHintSettleStartControllerValue = progress;

    _debugLog('table_transition_start', <String, Object?>{
      'screen': widget.screen,
      'source': source,
      'physicalDirection': direction,
      'tableStep': tableStep,
      'fromTable': fromSpec.id,
      'toTable': toSpec.id,
      'fromIndex': fromIndex,
      'toIndex': toIndex,
      'tableCount': _enabledTableIndices().length,
      'distance': distance.toStringAsFixed(1),
      'dragProgress': progress.toStringAsFixed(3),
      'velocity': velocity.toStringAsFixed(1),
      'wrapped': wrapped,
      'animationDurationMs': duration.inMilliseconds,
      'visualActivationDistance': _tableSwipeVisualActivationDistance,
      'commitDistanceThreshold': _tableSwipeCommitDistanceThreshold,
      'velocityThreshold': _tableSwipeVelocityThreshold,
      'visualActivated': visualActivatedAtCommit,
      'pageStructure': 'stable_stack',
      'currentPageState': 'preserved',
      'destinationState': 'promoted_by_spec_key',
      'rowMountReveal': 'disabled',
      'verticalRowReplay': false,
      'horizontalOnly': true,
      'statusVisual': 'rail+ambient_wash+responsive_context_bar',
      'fromStatusColor': _statusVisualRole(fromSpec),
      'toStatusColor': _statusVisualRole(toSpec),
      'swipeHintEnabled': widget.showColoredSwipeChevrons,
      'swipeHintEdge': physicalDirection < 0 ? 'right' : 'left',
      'swipeHintTarget': toSpec.id,
      'swipeHintTargetColor': _statusVisualRole(toSpec),
      'statusSignatureScheme':
          'parking_requests=danger;parking_completed=success;departure_requests=info',
      'swipeHintStartIntensity':
          _tableSwipeHintSettleStartIntensity.toStringAsFixed(3),
      'swipeHintIdleOpacity': _tableSwipeHintIdleOpacity,
      'swipeHintActiveOpacity': _tableSwipeHintActiveOpacity,
      'swipeHintOppositeOpacity': _tableSwipeHintOppositeOpacity,
      'swipeHintMaxTranslateDp': _tableSwipeHintMaxTranslate,
      'swipeHintMaxScale': _tableSwipeHintMaxScale,
    });

    _tableTransitioning = true;
    HapticFeedback.selectionClick();
    _onUserActivity();

    try {
      if (duration == Duration.zero) {
        _tableSwipeController.value = 1;
      } else {
        await _tableSwipeController.animateTo(
          1,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted) return;

      setState(() {
        _currentTableIndex = toIndex;
        _horizontalDragDistance = 0;
        _swipePhysicalDirection = 0;
        _swipeTableStep = 0;
        _swipeDestinationIndex = -1;
        _tableSwipeVisualActivated = false;
      });
      _tableSwipeController.value = 0;
      _syncSortContextAfterBuild();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;

      _debugLog('table_transition_complete', <String, Object?>{
        'screen': widget.screen,
        'source': source,
        'physicalDirection': direction,
        'tableStep': tableStep,
        'fromTable': fromSpec.id,
        'toTable': toSpec.id,
        'wrapped': wrapped,
        'hudActive': toSpec.id,
        'statusVisual': 'rail+ambient_wash+responsive_context_bar',
        'statusColor': _statusVisualRole(toSpec),
        'contextBarLabel': toSpec.label,
        'contextBarLayout': _tableContextLayoutMode(MediaQuery.sizeOf(context).width),
        'pageStructure': 'stable_stack',
        'destinationState': 'promoted_by_spec_key',
        'rowMountReveal': 'disabled',
        'verticalRowReplay': false,
      });
      _triggerStatusVisualPulse(toSpec);
      unawaited(
        _showControlStatus(
          title: 'TypePage 테이블 전환',
          lines: <String>[
            'tableSwipe=$direction source=$source',
            'screen=${widget.screen}',
            'viewMode=${_viewMode?.mode.name ?? 'unknown'}',
            'physicalDirection=$direction tableStep=$tableStep',
            'fromTable=${fromSpec.id} toTable=${toSpec.id}',
            'fromIndex=$fromIndex toIndex=$toIndex wrapped=$wrapped',
            'distance=${distance.toStringAsFixed(1)} velocity=${velocity.toStringAsFixed(1)}',
            'dragProgress=${progress.toStringAsFixed(3)} animationDurationMs=${duration.inMilliseconds}',
            'visualActivationDistance=$_tableSwipeVisualActivationDistance commitDistanceThreshold=$_tableSwipeCommitDistanceThreshold velocityThreshold=$_tableSwipeVelocityThreshold',
            'visualActivated=$visualActivatedAtCommit tapJitterProtection=dead_zone',
            'pageStructure=stable_stack currentPageState=preserved destinationState=promoted_by_spec_key',
            'rowMountReveal=disabled verticalRowReplay=false horizontalOnly=true',
            'hudActive=${toSpec.id}',
            'hudOpacity=active:1.00 inactive:0.76',
            'hudCounts=${_hudCountSummary(area)}',
            'statusVisual=rail+ambient_wash+responsive_context_bar',
            'contextBar=responsive_sort_status smallPhoneResponsive=true',
            'contextBarTableLabel=${toSpec.label}',
            'contextBarLayout=${_tableContextLayoutMode(MediaQuery.sizeOf(context).width)} contextBarWidth=${MediaQuery.sizeOf(context).width.toStringAsFixed(1)}',
            'statusColor=${_statusVisualRole(toSpec)}',
            'contextSurface=${widget.useListContextSurface ? 'list_surface' : 'card_surface'}',
            'swipeHintEnabled=${widget.showColoredSwipeChevrons}',
            'swipeHintEdge=${physicalDirection < 0 ? 'right' : 'left'} target=${toSpec.id} targetColor=${_statusVisualRole(toSpec)}',
            'swipeHintIdleOpacity=$_tableSwipeHintIdleOpacity activeOpacity=$_tableSwipeHintActiveOpacity oppositeOpacity=$_tableSwipeHintOppositeOpacity',
            'swipeHintMaxTranslateDp=$_tableSwipeHintMaxTranslate maxScale=$_tableSwipeHintMaxScale',
            'statusVisualPointer=ignored statusVisualSemantics=excluded',
            'hudPointer=ignored hudSemantics=excluded',
          ],
        ),
      );
    } finally {
      _tableTransitioning = false;
      _tableSwipeHintSettlingCommit = false;
      _tableSwipeHintSettleStartIntensity = 0;
      _tableSwipeHintSettleStartControllerValue = 0;
      _endTableSwipeGuard();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _transitionTableByPhysicalDirection(
    int physicalDirection, {
    required String source,
  }) async {
    if (!_canSwipeTables()) return;
    _horizontalDragActive = false;
    _horizontalDragDistance = 0;
    _tableSwipeVisualActivated = false;
    final screenWidth = MediaQuery.sizeOf(context).width;
    _horizontalSwipeViewportWidth = screenWidth > 0 ? screenWidth : 1;
    _tableSwipeController.stop();
    _tableSwipeController.value = 0;
    _setSwipeDirection(physicalDirection);
    await _commitInteractiveTableSwipe(
      physicalDirection: physicalDirection,
      distance: 0,
      velocity: 0,
      source: source,
    );
  }

  double _hudBaseOpacityForIndex(int index) {
    final destinationIndex = _swipeDestinationIndex;
    final progress = _tableSwipeController.value.clamp(0.0, 1.0).toDouble();
    if (destinationIndex >= 0 &&
        destinationIndex < widget.tabs.length &&
        _swipePhysicalDirection != 0 &&
        progress > 0) {
      if (index == _currentTableIndex) {
        return 1 - (.24 * progress);
      }
      if (index == destinationIndex) {
        return .76 + (.24 * progress);
      }
      return .76;
    }
    return index == _currentTableIndex ? 1 : .76;
  }

  Map<CustomSemanticsAction, VoidCallback>? _tableSemanticsActions() {
    if (!_canSwipeTables()) return null;
    final leftIndex = _targetTableIndex(1);
    final rightIndex = _targetTableIndex(-1);
    return <CustomSemanticsAction, VoidCallback>{
      CustomSemanticsAction(
        label: '오른쪽에서 왼쪽으로 ${widget.tabs[leftIndex].label} 테이블 전환',
      ): () => unawaited(
            _transitionTableByPhysicalDirection(
              -1,
              source: 'semantics',
            ),
          ),
      CustomSemanticsAction(
        label: '왼쪽에서 오른쪽으로 ${widget.tabs[rightIndex].label} 테이블 전환',
      ): () => unawaited(
            _transitionTableByPhysicalDirection(
              1,
              source: 'semantics',
            ),
          ),
    };
  }

  Future<void> _showControlStatus({
    required String title,
    required List<String> lines,
  }) async {
    if (!mounted) return;
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: title,
      initialMessage: lines.isEmpty ? 'TypePage 상태를 확인합니다.' : lines.first,
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
      showDialogImmediately: false,
    );
    for (final line in lines.skip(1)) {
      trace.log(line);
    }
    trace.log('parkingViewCapability=${_parkingViewCapability.name}');
    trace.log('statusEnabled=${_viewMode?.statusEnabled ?? false}');
    trace.log('modeControl=${_parkingViewCapability == ParkingViewCapability.tableAndStatus ? 'vertical_swipe_reel' : _parkingViewCapability == ParkingViewCapability.tableOnly ? 'static_table_indicator' : _parkingViewCapability == ParkingViewCapability.empty ? 'download_surface' : 'loading_surface'}');
    await trace.succeed('TypePage 상태 확인을 완료했습니다.');
    if (trace.developerMode && mounted) {
      await trace.showStatusDialog(context);
    }
  }

  double _hudOpacity(double progress, {required double baseOpacity}) {
    if (baseOpacity >= 1) return 1;
    final p = progress.clamp(0.0, 1.0).toDouble();
    final range = 1 - baseOpacity;
    if (p <= .3) {
      return baseOpacity +
          (range * Curves.easeOutCubic.transform(p / .3));
    }
    return 1.0 -
        (range * Curves.easeInOutCubic.transform((p - .3) / .7));
  }

  void _onHudPulseStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    _debugLog('hud_pulse_complete', <String, Object?>{
      'hudSlots': widget.tabs.length,
      'activeOpacity': '1.00',
      'inactiveOpacity': '0.76',
    });
  }

  void _triggerHudPulse() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _hudPulseController.value = 0;
      _debugLog('hud_pulse_skipped', <String, Object?>{
        'reason': 'reduce_motion',
        'hudSlots': widget.tabs.length,
      });
      return;
    }
    _debugLog('hud_pulse_start', <String, Object?>{
      'hudSlots': widget.tabs.length,
      'activeOpacity': '1.00',
      'inactiveBaseOpacity': '0.76',
      'peakOpacity': '1.00',
    });
    _hudPulseController.stop();
    _hudPulseController.forward(from: 0);
  }

  String _readCurrentArea() {
    final userArea = context.read<UserState>().currentArea.trim();
    final stateArea = context.read<AreaState>().currentArea.trim();
    return userArea.isNotEmpty ? userArea : stateArea;
  }

  String _hudCountSummary(String area) {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) return 'area=empty';
    try {
      final store = context.read<ViewDocRowsStore>();
      return widget.tabs.map((spec) {
        final count = store
            .rows(collection: spec.collection, area: normalizedArea)
            .length;
        return '${spec.id}=$count';
      }).join(',');
    } catch (_) {
      return 'unavailable';
    }
  }

  TypeViewMode _oppositeViewMode(TypeViewMode mode) {
    return mode == TypeViewMode.table
        ? TypeViewMode.status
        : TypeViewMode.table;
  }

  String _modeReelDirectionLabel(int physicalDirection) {
    return physicalDirection < 0 ? 'up' : 'down';
  }

  bool _canUseModeReel() {
    if (!_statusViewSupported) return false;
    if (_viewMode == null || _transitionMaskOn) return false;
    if (_modeReelDragActive ||
        _modeReelTransitioning ||
        _modeReelSelectorPressActive ||
        _parentSelectorOpen) {
      return false;
    }
    if (_horizontalDragActive ||
        _tableTransitioning ||
        _tableSwipeController.value > 0) {
      return false;
    }
    return true;
  }

  int _parentSelectorReopenCooldownRemainingMs() {
    final until = _parentSelectorReopenBlockedUntil;
    if (until == null) return 0;
    final remaining = until.difference(DateTime.now()).inMilliseconds;
    return remaining > 0 ? remaining : 0;
  }

  bool _parentSelectorReopenCooldownActive() {
    return _parentSelectorReopenCooldownRemainingMs() > 0;
  }

  bool _canOpenModeReelParentSelector() {
    return _canUseModeReel() && !_parentSelectorReopenCooldownActive();
  }

  void _beginModeReelGuard() {
    if (_modeReelGuardBlocked) return;
    final guard = _autoGuard;
    if (guard == null) return;
    guard.beginBlock('보기 모드 릴 조작');
    _modeReelGuardBlocked = true;
  }

  void _endModeReelGuard() {
    if (!_modeReelGuardBlocked) return;
    _modeReelGuardBlocked = false;
    _autoGuard?.endBlock('보기 모드 릴 조작');
  }

  double _modeReelProgressForDistance(double distance) {
    return (distance.abs() / _modeReelTravel)
        .clamp(0.0, .98)
        .toDouble();
  }

  Duration _modeReelSettleDuration({
    required double progress,
    required bool commit,
    required double velocity,
  }) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return Duration.zero;
    final remaining = commit ? 1 - progress : progress;
    final baseMs = commit ? 220 : 170;
    final minMs = commit ? 70 : 80;
    var milliseconds = (baseMs * remaining).round().clamp(minMs, baseMs);
    if (velocity.abs() >= 900) {
      milliseconds = milliseconds.clamp(minMs, 110);
    }
    return Duration(milliseconds: milliseconds.toInt());
  }

  void _setModeReelDirection(int physicalDirection) {
    if (physicalDirection == 0 ||
        _modeReelPhysicalDirection == physicalDirection) {
      return;
    }
    setState(() {
      _modeReelPhysicalDirection = physicalDirection;
    });
  }

  void _triggerModeReelDetent({required String source}) {
    if (_modeReelDetentTriggered) return;
    _modeReelDetentTriggered = true;
    HapticFeedback.selectionClick();
    _debugLog('mode_reel_detent', <String, Object?>{
      'source': source,
      'physicalDirection': _modeReelPhysicalDirection == 0
          ? 'none'
          : _modeReelDirectionLabel(_modeReelPhysicalDirection),
      'progress': _modeReelController.value.toStringAsFixed(3),
      'distanceThreshold': _modeReelDistanceThreshold,
    });
  }

  void _onModeReelDragStart(DragStartDetails _) {
    if (!_canUseModeReel()) {
      _debugLog('mode_reel_ignored', <String, Object?>{
        'source': 'gesture',
        'reason': _modeReelTransitioning
            ? 'reel_transitioning'
            : 'other_transition_active',
        'mode': _viewMode?.mode.name,
        'tableSwipeProgress': _tableSwipeController.value.toStringAsFixed(3),
      });
      return;
    }
    final vm = _viewMode;
    if (vm == null) return;
    _onUserActivity();
    _beginModeReelGuard();
    _modeReelController.stop();
    _modeReelController.value = 0;
    setState(() {
      _modeReelDragActive = true;
      _modeReelDragDistance = 0;
      _modeReelPhysicalDirection = 0;
      _modeReelDebugBucket = -1;
      _modeReelDetentTriggered = false;
      _modeReelFromMode = vm.mode;
    });
    _debugLog('mode_reel_drag_start', <String, Object?>{
      'from': vm.mode.name,
      'to': _oppositeViewMode(vm.mode).name,
      'control': 'frameless_bidirectional_icon_reel',
      'visualText': 'none',
      'distanceThreshold': _modeReelDistanceThreshold,
      'velocityThreshold': _modeReelVelocityThreshold,
    });
  }

  void _onModeReelDragUpdate(DragUpdateDetails details) {
    if (!_modeReelDragActive || _modeReelTransitioning) return;
    _modeReelDragDistance += details.delta.dy;
    final physicalDirection = _modeReelDragDistance < 0
        ? -1
        : _modeReelDragDistance > 0
            ? 1
            : 0;
    if (physicalDirection != 0) {
      _setModeReelDirection(physicalDirection);
    }
    final progress = _modeReelProgressForDistance(_modeReelDragDistance);
    _modeReelController.value = progress;
    if (progress >=
        _modeReelDistanceThreshold / _modeReelTravel) {
      _triggerModeReelDetent(source: 'gesture');
    } else if (progress < .38) {
      _modeReelDetentTriggered = false;
    }
    final bucket = (progress * 4).floor().clamp(0, 3).toInt();
    if (bucket != _modeReelDebugBucket && bucket > 0) {
      _modeReelDebugBucket = bucket;
      _debugLog('mode_reel_drag_update', <String, Object?>{
        'physicalDirection': physicalDirection == 0
            ? 'none'
            : _modeReelDirectionLabel(physicalDirection),
        'distance': _modeReelDragDistance.toStringAsFixed(1),
        'progress': progress.toStringAsFixed(3),
        'bucket': bucket,
      });
    }
  }

  void _onModeReelDragEnd(DragEndDetails details) {
    if (!_modeReelDragActive || _modeReelTransitioning) return;
    final distance = _modeReelDragDistance;
    final velocity = details.primaryVelocity ?? 0;
    final distanceAccepted = distance.abs() >= _modeReelDistanceThreshold;
    final velocityAccepted = velocity.abs() >= _modeReelVelocityThreshold;
    if (!distanceAccepted && !velocityAccepted) {
      _modeReelDragActive = false;
      unawaited(
        _cancelModeReelTransition(
          reason: 'below_threshold',
          distance: distance,
          velocity: velocity,
        ),
      );
      return;
    }
    final directionValue = velocityAccepted ? velocity : distance;
    final physicalDirection = directionValue < 0 ? -1 : 1;
    _setModeReelDirection(physicalDirection);
    _modeReelDragActive = false;
    unawaited(
      _commitModeReelTransition(
        physicalDirection: physicalDirection,
        distance: distance,
        velocity: velocity,
        source: 'gesture',
      ),
    );
  }

  void _onModeReelDragCancel() {
    if (!_modeReelDragActive || _modeReelTransitioning) return;
    final distance = _modeReelDragDistance;
    _modeReelDragActive = false;
    unawaited(
      _cancelModeReelTransition(
        reason: 'gesture_cancelled',
        distance: distance,
        velocity: 0,
      ),
    );
  }

  Future<void> _cancelModeReelTransition({
    required String reason,
    required double distance,
    required double velocity,
  }) async {
    final progress = _modeReelController.value.clamp(0.0, 1.0).toDouble();
    final duration = _modeReelSettleDuration(
      progress: progress,
      commit: false,
      velocity: velocity,
    );
    final direction = _modeReelPhysicalDirection == 0
        ? 'none'
        : _modeReelDirectionLabel(_modeReelPhysicalDirection);
    _modeReelTransitioning = true;
    _debugLog('mode_reel_cancel', <String, Object?>{
      'reason': reason,
      'physicalDirection': direction,
      'distance': distance.toStringAsFixed(1),
      'velocity': velocity.toStringAsFixed(1),
      'progress': progress.toStringAsFixed(3),
      'snapBackDurationMs': duration.inMilliseconds,
      'mode': _viewMode?.mode.name,
    });
    try {
      if (duration == Duration.zero) {
        _modeReelController.value = 0;
      } else {
        await _modeReelController.animateTo(
          0,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
    } finally {
      _modeReelController.value = 0;
      _modeReelDragDistance = 0;
      _modeReelPhysicalDirection = 0;
      _modeReelDebugBucket = -1;
      _modeReelDetentTriggered = false;
      _modeReelFromMode = null;
      _modeReelTransitioning = false;
      _endModeReelGuard();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _commitModeReelTransition({
    required int physicalDirection,
    required double distance,
    required double velocity,
    required String source,
  }) async {
    final vm = _viewMode;
    if (vm == null) {
      _endModeReelGuard();
      return;
    }
    if (!_modeReelGuardBlocked) {
      _beginModeReelGuard();
    }
    _modeReelTransitioning = true;
    _setModeReelDirection(physicalDirection);
    final from = _modeReelFromMode ?? vm.mode;
    final to = _oppositeViewMode(from);
    final area = _readCurrentArea();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    var progress = _modeReelController.value.clamp(0.0, 1.0).toDouble();
    final initialDuration = _modeReelSettleDuration(
      progress: progress,
      commit: true,
      velocity: velocity,
    );
    final direction = _modeReelDirectionLabel(physicalDirection);
    _debugLog('mode_reel_commit', <String, Object?>{
      'source': source,
      'from': from.name,
      'to': to.name,
      'physicalDirection': direction,
      'distance': distance.toStringAsFixed(1),
      'velocity': velocity.toStringAsFixed(1),
      'progress': progress.toStringAsFixed(3),
      'distanceThreshold': _modeReelDistanceThreshold,
      'velocityThreshold': _modeReelVelocityThreshold,
      'animationDurationMs': initialDuration.inMilliseconds,
      'motion': 'translateY+rotationX+opacity+scale',
      'visualText': 'none',
      'reduceMotion': reduceMotion,
    });
    try {
      if (progress < .5 && !reduceMotion) {
        final detentMs =
            (100 * (.5 - progress) / .5).round().clamp(45, 100).toInt();
        await _modeReelController.animateTo(
          .5,
          duration: Duration(milliseconds: detentMs),
          curve: Curves.easeOutCubic,
        );
        progress = .5;
      }
      if (!_statusViewSupported || !vm.statusEnabled) {
        _debugLog('mode_reel_commit_cancelled', <String, Object?>{
          'reason': 'status_view_disabled_during_transition',
          'capability': _parkingViewCapability.name,
        });
        _modeReelController.value = 0;
        return;
      }
      _triggerModeReelDetent(source: source);
      vm.setMode(to);
      _triggerHudPulse();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      progress = _modeReelController.value.clamp(0.0, 1.0).toDouble();
      final duration = _modeReelSettleDuration(
        progress: progress,
        commit: true,
        velocity: velocity,
      );
      if (duration == Duration.zero) {
        _modeReelController.value = 1;
      } else {
        await _modeReelController.animateTo(
          1,
          duration: duration,
          curve: Curves.easeOutCubic,
        );
      }
      if (!mounted) return;
      _debugLog('mode_reel_settle_complete', <String, Object?>{
        'source': source,
        'from': from.name,
        'to': to.name,
        'physicalDirection': direction,
        'detent': true,
        'control': 'frameless_bidirectional_icon_reel',
      });
      unawaited(
        _showControlStatus(
          title: 'TypePage 보기 모드 릴 전환',
          lines: <String>[
            'control=frameless_bidirectional_icon_reel',
            'viewMode=${from.name}->${to.name}',
            'screen=${widget.screen}',
            'table=${widget.tabs[_currentTableIndex].id}',
            'source=$source physicalDirection=$direction',
            'distance=${distance.toStringAsFixed(1)} velocity=${velocity.toStringAsFixed(1)}',
            'distanceThreshold=$_modeReelDistanceThreshold velocityThreshold=$_modeReelVelocityThreshold',
            'detent=true haptic=selectionClick',
            'motion=translateY+rotationX+opacity+scale',
            'visualGuide=vertical_chevrons+next_mode_ghost tableIcon=table_rows_rounded statusIcon=custom_dot_map',
            'reelFrame=none reelBorder=none reelTouchHeight=64',
            'hudCounts=${_hudCountSummary(area)}',
            'hudOpacity=active:1.00 inactive:0.76->1.00->0.76',
            'statusVisual=rail+ambient_wash tableOnly=true',
            'statusColor=${_statusVisualRole(widget.tabs[_currentTableIndex])}',
            'guard=blocked_until_reel_settle',
            'reduceMotion=$reduceMotion',
          ],
        ),
      );
    } finally {
      _modeReelController.value = 0;
      _modeReelDragDistance = 0;
      _modeReelPhysicalDirection = 0;
      _modeReelDebugBucket = -1;
      _modeReelDetentTriggered = false;
      _modeReelFromMode = null;
      _modeReelTransitioning = false;
      _endModeReelGuard();
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _runModeReelProgrammatic({
    required int physicalDirection,
    required String source,
  }) async {
    if (!_canUseModeReel()) {
      _debugLog('mode_reel_ignored', <String, Object?>{
        'source': source,
        'reason': _modeReelTransitioning
            ? 'reel_transitioning'
            : 'other_transition_active',
        'mode': _viewMode?.mode.name,
        'tableSwipeProgress': _tableSwipeController.value.toStringAsFixed(3),
      });
      return;
    }
    final vm = _viewMode;
    if (vm == null) return;
    _onUserActivity();
    _beginModeReelGuard();
    _modeReelController.stop();
    _modeReelController.value = 0;
    setState(() {
      _modeReelDragActive = false;
      _modeReelDragDistance = 0;
      _modeReelPhysicalDirection = physicalDirection;
      _modeReelDebugBucket = -1;
      _modeReelDetentTriggered = false;
      _modeReelFromMode = vm.mode;
    });
    _debugLog('mode_reel_programmatic_start', <String, Object?>{
      'source': source,
      'from': vm.mode.name,
      'to': _oppositeViewMode(vm.mode).name,
      'physicalDirection': _modeReelDirectionLabel(physicalDirection),
    });
    await _commitModeReelTransition(
      physicalDirection: physicalDirection,
      distance: 0,
      velocity: 0,
      source: source,
    );
  }

  void _onModeReelTap() {
    unawaited(
      _openModeReelParentSelector(
        interaction: 'tap',
      ),
    );
  }

  Future<void> _onModeReelLongPress() {
    return _openModeReelParentSelector(
      interaction: 'long_press',
    );
  }

  Rect? _modeReelSourceRect() {
    final sourceContext = _modeReelSourceKey.currentContext;
    final renderObject = sourceContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return null;
    final origin = renderObject.localToGlobal(Offset.zero);
    return origin & renderObject.size;
  }

  Future<List<_ParentSelectorItem>> _resolveModeReelParentItems() async {
    final area = _readCurrentArea();
    LocationState state;
    try {
      state = context.read<LocationState>();
    } catch (_) {
      _debugLog('parent_selector_data_failed', <String, Object?>{
        'reason': 'location_state_unavailable',
        'area': area,
      });
      return const <_ParentSelectorItem>[];
    }
    var locations = List<LocationModel>.of(state.locations);
    if (locations.isEmpty) {
      await state.loadFromLocationCache();
      if (!mounted) return const <_ParentSelectorItem>[];
      locations = List<LocationModel>.of(state.locations);
    }
    if (area.isNotEmpty) {
      final areaLocations = locations
          .where((location) => location.area.trim() == area)
          .toList(growable: false);
      if (areaLocations.isNotEmpty) {
        locations = areaLocations;
      }
    }
    final parentNames = extractParentsFromMeta(locations).toList()
      ..sort(naturalLocationCompare);
    final parentByRef = <String, LocationModel>{};
    final childRectsByParent = <String, List<GridRect>>{};
    for (final location in locations) {
      final type = (location.type ?? 'single').trim();
      if (type == 'composite_parent') {
        final name = location.locationName.trim();
        final id = location.id.trim();
        if (name.isNotEmpty) parentByRef[name] = location;
        if (id.isNotEmpty) parentByRef[id] = location;
        continue;
      }
      if (type != 'composite_child' && type != 'composite') continue;
      final parent = (location.parent ?? '').trim();
      final rect = location.childRect;
      if (parent.isEmpty || rect == null) continue;
      childRectsByParent.putIfAbsent(parent, () => <GridRect>[]).add(
            rect.normalized(),
          );
    }
    final items = <_ParentSelectorItem>[];
    for (final parent in parentNames) {
      final parentSource = parentByRef[parent];
      final rects = List<GridRect>.of(
        childRectsByParent[parent] ?? const <GridRect>[],
      );
      items.add(
        _ParentSelectorItem(
          parent: parent,
          grid: parentSource?.parkingGrid,
          childRects: List<GridRect>.unmodifiable(rects),
        ),
      );
    }
    final gridReady = items.where((item) => item.grid != null).length;
    final rectFallback = items
        .where((item) => item.grid == null && item.childRects.isNotEmpty)
        .length;
    final iconFallback = items.length - gridReady - rectFallback;
    _debugLog('parent_selector_data_resolved', <String, Object?>{
      'area': area,
      'parentCount': items.length,
      'gridReady': gridReady,
      'childRectFallback': rectFallback,
      'iconFallback': iconFallback,
      'firebaseAdditionalRead': 0,
      'source': 'location_state_or_cache',
      'preview': 'parking_grid_or_child_rect_thumbnail',
    });
    return items;
  }

  _ParentSelectorGridMetrics _parentSelectorGridMetrics(
    BuildContext context,
    int parentCount,
  ) {
    final media = MediaQuery.of(context);
    final safeWidth = math.max(
      220.0,
      media.size.width - media.padding.left - media.padding.right,
    ).toDouble();
    final safeHeight = math.max(
      220.0,
      media.size.height - media.padding.top - media.padding.bottom,
    ).toDouble();
    final compact = safeWidth < 600;
    final baseRect = realTimeSourceRectModalTargetRect(
      context,
      compactHeightFactor: 1,
      wideHeightFactor: 1,
      compactMaxHeight: 620,
      wideMaxHeight: 700,
    );
    const horizontalPadding = 10.0;
    const crossAxisSpacing = 6.0;
    const mainAxisSpacing = 8.0;
    final innerWidth = math.max(
      1.0,
      baseRect.width - horizontalPadding * 2,
    ).toDouble();
    final desiredCellWidth = compact ? 96.0 : 108.0;
    final maxColumns = compact ? 4 : 6;
    var columns = (innerWidth / desiredCellWidth).floor();
    columns = columns.clamp(2, maxColumns).toInt();
    final tileWidth = math.max(
      1.0,
      (innerWidth - crossAxisSpacing * (columns - 1)) / columns,
    ).toDouble();
    final previewHeight = (tileWidth * .58).clamp(46.0, 64.0).toDouble();
    final tileExtent = previewHeight + 26;
    final rows = parentCount <= 0 ? 0 : (parentCount + columns - 1) ~/ columns;
    final gridContentHeight = rows <= 0
        ? 0.0
        : rows * tileExtent + math.max(0, rows - 1) * mainAxisSpacing;
    final viewportHeightLimit = math.max(
      220.0,
      safeHeight - 32.0,
    ).toDouble();
    final targetHeight = math.min(
      compact ? 420.0 : 520.0,
      viewportHeightLimit,
    ).toDouble();
    final gridViewportHeight = math.max(
      0.0,
      targetHeight - 55.0,
    ).toDouble();
    final scrollNeeded = gridContentHeight > gridViewportHeight + .5;
    return _ParentSelectorGridMetrics(
      columns: columns,
      rows: rows,
      previewHeight: previewHeight,
      tileExtent: tileExtent,
      crossAxisSpacing: crossAxisSpacing,
      mainAxisSpacing: mainAxisSpacing,
      horizontalPadding: horizontalPadding,
      targetHeight: targetHeight,
      gridViewportHeight: gridViewportHeight,
      gridContentHeight: gridContentHeight,
      scrollNeeded: scrollNeeded,
      modalWidth: baseRect.width,
      modalCenter: baseRect.center,
    );
  }

  Rect _parentSelectorTargetRect(_ParentSelectorGridMetrics metrics) {
    return Rect.fromCenter(
      center: metrics.modalCenter,
      width: metrics.modalWidth,
      height: metrics.targetHeight,
    );
  }

  Future<String?> _showParentSelectorDialog({
    required String interaction,
    required Rect sourceRect,
    required List<_ParentSelectorItem> parents,
    required _ParentSelectorGridMetrics metrics,
    required String currentParent,
  }) async {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final targetRect = _parentSelectorTargetRect(metrics);
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 340);
    var closeSource = 'route';
    var closeRequested = false;
    var duplicateCloseCount = 0;
    var navigatorPopCount = 0;
    final collapsedCompleter = Completer<void>();
    _lastParentSelectorCollapseInfo = null;
    _lastParentSelectorCloseSource = closeSource;
    _lastParentSelectorDuplicateCloseCount = 0;
    _lastParentSelectorNavigatorPopCount = 0;
    _debugLog('parent_selector_expand_started', <String, Object?>{
      'source': 'mode_reel',
      'interaction': interaction,
      'sourceRect': realTimeSourceRectDebug(sourceRect),
      'targetRect': realTimeSourceRectDebug(targetRect),
      'parentCount': parents.length,
      'durationMs': duration.inMilliseconds,
      'dialogBorder': 'hidden',
      'dialogSurfaceOpacity': '0.92->0.96',
      'dialogShape': 'rounded_surface',
      'dialogShadow': 'subtle',
      'scrimOpacity': '0.26',
      'blurSigma': '4.5',
      'motion': 'source_rect_crop_expand_reverse_collapse',
      'layout': 'compact_parent_preview_grid',
      'order': 'row_major_left_to_right',
      'dialogSizing': 'fixed_per_viewport',
      'dialogHeight': metrics.targetHeight.toStringAsFixed(1),
      'columns': metrics.columns,
      'rows': metrics.rows,
      'gridViewportHeight': metrics.gridViewportHeight.toStringAsFixed(1),
      'gridContentHeight': metrics.gridContentHeight.toStringAsFixed(1),
      'verticalScroll': metrics.scrollNeeded,
      'previewHeight': metrics.previewHeight.toStringAsFixed(1),
      'tileExtent': metrics.tileExtent.toStringAsFixed(1),
      'thumbnailFrame': 'none',
      'parentLabel': 'bottom_center',
    });
    final result = await showGeneralDialog<String>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      barrierLabel: '부모 주차 구역 선택',
      barrierColor: Colors.transparent,
      transitionDuration: duration,
      pageBuilder: (_, __, ___) => const SizedBox.expand(),
      transitionBuilder: (dialogContext, animation, _, __) {
        void close([String? value, String source = 'dialog_header']) {
          if (closeRequested) {
            duplicateCloseCount += 1;
            _lastParentSelectorDuplicateCloseCount = duplicateCloseCount;
            _debugLog('parent_selector_close_ignored', <String, Object?>{
              'source': source,
              'entryInteraction': interaction,
              'reason': 'close_already_requested',
              'duplicateCloseCount': duplicateCloseCount,
              'navigatorPopCount': navigatorPopCount,
              'animationValue': animation.value.toStringAsFixed(3),
              'animationStatus': animation.status.name,
              'closePolicy': 'exactly_once',
            });
            return;
          }
          closeRequested = true;
          closeSource = source;
          _lastParentSelectorCloseSource = source;
          navigatorPopCount += 1;
          _lastParentSelectorNavigatorPopCount = navigatorPopCount;
          _debugLog('parent_selector_close_requested', <String, Object?>{
            'source': source,
            'entryInteraction': interaction,
            'animationValue': animation.value.toStringAsFixed(3),
            'animationStatus': animation.status.name,
            'closePolicy': 'exactly_once',
            'navigatorPopCount': navigatorPopCount,
            'duplicateCloseCount': duplicateCloseCount,
            'scrimReverseInput': 'absorbed',
          });
          Navigator.of(dialogContext, rootNavigator: true).pop(value);
        }
        return RealTimeSourceRectModalTransition(
          animation: animation,
          sourceRect: sourceRect,
          targetRect: targetRect,
          reduceMotion: reduceMotion,
          closeSemanticsLabel: '부모 주차 구역 선택 닫기',
          onCloseRequested: (source) => close(null, source),
          onSystemPop: () {
            closeRequested = true;
            if (navigatorPopCount < 1) {
              navigatorPopCount = 1;
            }
            _lastParentSelectorNavigatorPopCount = navigatorPopCount;
            closeSource = 'system_back';
            _lastParentSelectorCloseSource = closeSource;
            _debugLog('parent_selector_system_back', <String, Object?>{
              'interaction': interaction,
              'sourceRect': realTimeSourceRectDebug(sourceRect),
              'closePolicy': 'exactly_once',
              'navigatorPopCount': navigatorPopCount,
              'scrimReverseInput': 'absorbed',
            });
          },
          onExpanded: () {
            _debugLog('parent_selector_expand_completed', <String, Object?>{
              'entryInteraction': interaction,
              'targetRect': realTimeSourceRectDebug(targetRect),
              'parentCount': parents.length,
              'interactionState': 'enabled',
            });
          },
          onCollapseLifecycle: (info) {
            _lastParentSelectorCollapseInfo = info;
            _debugLog('parent_selector_collapse_lifecycle', <String, Object?>{
              'source': closeSource,
              'interaction': interaction,
              'expandedBeforeCollapse': info.expandedBeforeCollapse,
              'earlyCollapse': info.earlyCollapse,
              'maxRawProgress': info.maxRawProgress.toStringAsFixed(3),
              'callback': 'guaranteed_on_dismissed',
              'earlyReverseCurve': info.earlyCollapse
                  ? 'continuous_easeOutCubic'
                  : 'easeInOutCubic',
            });
          },
          onCollapsed: () {
            if (!collapsedCompleter.isCompleted) {
              collapsedCompleter.complete();
            }
            _debugLog('parent_selector_collapse_completed', <String, Object?>{
              'interaction': interaction,
              'targetRect': realTimeSourceRectDebug(sourceRect),
              'source': closeSource,
            });
          },
          builder: (context, progress, interactionEnabled) {
            return _ParentSelectorDialogSurface(
              parents: parents,
              metrics: metrics,
              currentParent: currentParent,
              progress: progress,
              interactionEnabled: interactionEnabled,
              onClose: () => close(null, 'dialog_header'),
              onSelected: (item) {
                HapticFeedback.selectionClick();
                _debugLog('parent_selector_parent_tapped', <String, Object?>{
                  'interaction': interaction,
                  'parent': item.parent,
                  'fromMode': _viewMode?.mode.name,
                  'toMode': TypeViewMode.status.name,
                  'previewSource': item.previewSource,
                  'layout': 'compact_parent_preview_grid',
                  'columns': metrics.columns,
                  'rows': metrics.rows,
                  'dialogSizing': 'fixed_per_viewport',
                  'verticalScroll': metrics.scrollNeeded,
                });
                close(item.parent, 'parent_selected');
              },
            );
          },
        );
      },
    );
    if (!collapsedCompleter.isCompleted) {
      try {
        await collapsedCompleter.future.timeout(
          reduceMotion
              ? const Duration(milliseconds: 80)
              : const Duration(milliseconds: 520),
        );
      } on TimeoutException {
        _debugLog('parent_selector_collapse_wait_timeout', <String, Object?>{
          'source': closeSource,
          'interaction': interaction,
          'result': result,
        });
      }
    }
    _lastParentSelectorCloseSource = closeSource;
    return result;
  }

  Future<void> _openModeReelParentSelector({
    required String interaction,
  }) async {
    if (!_canUseModeReel()) {
      _debugLog('mode_reel_ignored', <String, Object?>{
        'source': interaction,
        'reason': 'other_transition_active',
        'mode': _viewMode?.mode.name,
      });
      return;
    }
    if (!_canOpenModeReelParentSelector()) {
      _debugLog('mode_reel_parent_selector_ignored', <String, Object?>{
        'source': interaction,
        'reason': 'reopen_cooldown',
        'mode': _viewMode?.mode.name,
        'remainingMs': _parentSelectorReopenCooldownRemainingMs(),
        'cooldownMs': _parentSelectorReopenCooldown.inMilliseconds,
      });
      return;
    }
    final vm = _viewMode;
    if (vm == null) return;
    final sourceRect = _modeReelSourceRect();
    if (sourceRect == null) {
      _debugLog('parent_selector_open_rejected', <String, Object?>{
        'reason': 'mode_reel_source_rect_unavailable',
      });
      return;
    }
    _onUserActivity();
    _beginModeReelGuard();
    setState(() {
      _modeReelSelectorPressActive = true;
      _parentSelectorOpen = true;
    });
    final haptic = interaction == 'long_press'
        ? 'mediumImpact'
        : 'selectionClick';
    if (interaction == 'long_press') {
      HapticFeedback.mediumImpact();
    } else {
      HapticFeedback.selectionClick();
    }
    _debugLog('mode_reel_parent_selector_started', <String, Object?>{
      'fromMode': vm.mode.name,
      'sourceRect': realTimeSourceRectDebug(sourceRect),
      'control': 'frameless_bidirectional_icon_reel',
      'interaction': interaction,
      'action': 'parent_selector',
      'haptic': haptic,
      'modeSwitch': 'vertical_reel_only',
    });
    String? selectedParent;
    var parents = const <_ParentSelectorItem>[];
    try {
      parents = await _resolveModeReelParentItems();
      if (!mounted) return;
      if (parents.isEmpty) {
        _debugLog('parent_selector_open_rejected', <String, Object?>{
          'reason': 'no_parent_locations',
          'area': _readCurrentArea(),
        });
        return;
      }
      final metrics = _parentSelectorGridMetrics(context, parents.length);
      if (!(MediaQuery.maybeOf(context)?.disableAnimations ?? false)) {
        await Future<void>.delayed(const Duration(milliseconds: 90));
        if (!mounted) return;
      }
      selectedParent = await _showParentSelectorDialog(
        interaction: interaction,
        sourceRect: sourceRect,
        parents: parents,
        metrics: metrics,
        currentParent: _controllers[_currentTableIndex].activeParent,
      );
      if (!mounted) return;
      if (selectedParent == null || selectedParent.trim().isEmpty) {
        final collapseInfo = _lastParentSelectorCollapseInfo;
        _debugLog('parent_selector_cancelled', <String, Object?>{
          'interaction': interaction,
          'fromMode': vm.mode.name,
          'parentCount': parents.length,
          'closeSource': _lastParentSelectorCloseSource,
          'collapseCallbackObserved': collapseInfo != null,
          'expandedBeforeCollapse': collapseInfo?.expandedBeforeCollapse,
          'earlyCollapse': collapseInfo?.earlyCollapse,
          'maxRawProgress': collapseInfo?.maxRawProgress.toStringAsFixed(3),
        });
        unawaited(
          _showControlStatus(
            title: 'Mode Reel 부모 선택 취소',
            lines: <String>[
              'control=frameless_bidirectional_icon_reel interaction=${interaction}_cancelled',
              'dialog=parent_selector closeSource=$_lastParentSelectorCloseSource',
              'tapBehavior=parent_selector modeSwitchInput=vertical_reel_only',
              'selectorEntryHaptic=$haptic',
              'closePolicy=exactly_once navigatorPopCount=$_lastParentSelectorNavigatorPopCount duplicateCloseCount=$_lastParentSelectorDuplicateCloseCount',
              'scrimReverseInput=absorbed systemBackDuringReverse=blocked',
              'selectorReopenCooldownMs=${_parentSelectorReopenCooldown.inMilliseconds}',
              'collapseCallback=guaranteed_on_animation_dismissed',
              'collapseCallbackObserved=${collapseInfo != null}',
              'expandedBeforeCollapse=${collapseInfo?.expandedBeforeCollapse ?? false}',
              'earlyCollapse=${collapseInfo?.earlyCollapse ?? false}',
              'maxRawProgress=${collapseInfo?.maxRawProgress.toStringAsFixed(3) ?? 'n/a'}',
              'earlyReverseCurve=${collapseInfo == null ? 'n/a' : (collapseInfo.earlyCollapse ? 'continuous_easeOutCubic' : 'easeInOutCubic')}',
              'dialogMotion=source_rect_crop_expand_reverse_collapse',
              'selectorLayout=compact_parent_preview_grid order=row_major_left_to_right',
              'dialogSizing=fixed_per_viewport dialogHeight=${metrics.targetHeight.toStringAsFixed(1)}',
              'columns=${metrics.columns} rows=${metrics.rows}',
              'gridViewportHeight=${metrics.gridViewportHeight.toStringAsFixed(1)} gridContentHeight=${metrics.gridContentHeight.toStringAsFixed(1)}',
              'verticalScroll=${metrics.scrollNeeded} overflowPolicy=grid_vertical_scroll_only',
              'preview=parking_grid_or_child_rect_thumbnail thumbnailFrame=none',
              'parentLabel=bottom_center',
              'debugPrint=clipboard_copy_supported',
            ],
          ),
        );
        return;
      }
      final selectedItem = parents.firstWhere(
        (item) => item.parent == selectedParent,
      );
      if (!_statusViewSupported || !vm.statusEnabled) {
        _debugLog('parent_selector_result_ignored', <String, Object?>{
          'reason': 'status_view_disabled',
          'capability': _parkingViewCapability.name,
          'selectedParent': selectedItem.parent,
        });
        return;
      }
      final from = vm.mode;
      final controller = _controllers[_currentTableIndex];
      final request = controller.requestParentFocus(
        selectedParent,
        deferUntilNextBind: from != TypeViewMode.status,
      );
      if (vm.mode != TypeViewMode.status) {
        vm.setMode(TypeViewMode.status);
        _triggerHudPulse();
      }
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _debugLog('parent_focus_requested', <String, Object?>{
        'serial': request.serial,
        'interaction': interaction,
        'parent': request.parent,
        'fromMode': from.name,
        'toMode': TypeViewMode.status.name,
        'table': widget.tabs[_currentTableIndex].id,
      });
      unawaited(
        _showControlStatus(
          title: 'Mode Reel 부모 주차 구역 선택',
          lines: <String>[
            'control=frameless_bidirectional_icon_reel interaction=$interaction',
            'dialog=parent_selector dialogSource=mode_reel_rect',
            'tapBehavior=parent_selector modeSwitchInput=vertical_reel_only',
            'selectorEntryHaptic=$haptic',
            'closePolicy=exactly_once navigatorPopCount=$_lastParentSelectorNavigatorPopCount duplicateCloseCount=$_lastParentSelectorDuplicateCloseCount',
            'scrimReverseInput=absorbed systemBackDuringReverse=blocked',
            'selectorReopenCooldownMs=${_parentSelectorReopenCooldown.inMilliseconds}',
            'dialogMotion=source_rect_crop_expand_reverse_collapse',
            'dialogBorder=hidden dialogSurface=opacity_0.92_to_0.96',
            'dialogShape=rounded_surface dialogShadow=subtle',
            'scrim=0.26 blurSigma=4.5 durationMs=340',
            'sourceRect=${realTimeSourceRectDebug(sourceRect)}',
            'selectedParent=${request.parent} requestSerial=${request.serial}',
            'fromMode=${from.name} toMode=${TypeViewMode.status.name}',
            'parentCount=${parents.length} firebaseAdditionalRead=0',
            'selectorLayout=compact_parent_preview_grid order=row_major_left_to_right',
            'dialogSizing=fixed_per_viewport dialogHeight=${metrics.targetHeight.toStringAsFixed(1)}',
            'columns=${metrics.columns} rows=${metrics.rows}',
            'gridViewportHeight=${metrics.gridViewportHeight.toStringAsFixed(1)} gridContentHeight=${metrics.gridContentHeight.toStringAsFixed(1)}',
            'verticalScroll=${metrics.scrollNeeded} overflowPolicy=grid_vertical_scroll_only',
            'previewHeight=${metrics.previewHeight.toStringAsFixed(1)} tileExtent=${metrics.tileExtent.toStringAsFixed(1)}',
            'preview=parking_grid_or_child_rect_thumbnail thumbnailFrame=none',
            'parentLabel=bottom_center',
            'selectedPreviewSource=${selectedItem.previewSource}',
            'selectionMotion=scale_1.0_to_0.94_plus_check_90ms',
            'gridReady=${parents.where((item) => item.grid != null).length}',
            'childRectFallback=${parents.where((item) => item.grid == null && item.childRects.isNotEmpty).length}',
            'iconFallback=${parents.where((item) => item.grid == null && item.childRects.isEmpty).length}',
            'guard=blocked_until_parent_selector_closed_and_status_requested',
            'collapseCallback=guaranteed_on_animation_dismissed',
            'collapseCallbackObserved=${_lastParentSelectorCollapseInfo != null}',
            'expandedBeforeCollapse=${_lastParentSelectorCollapseInfo?.expandedBeforeCollapse ?? false}',
            'earlyCollapse=${_lastParentSelectorCollapseInfo?.earlyCollapse ?? false}',
            'maxRawProgress=${_lastParentSelectorCollapseInfo?.maxRawProgress.toStringAsFixed(3) ?? 'n/a'}',
            'earlyReverseCurve=${_lastParentSelectorCollapseInfo?.earlyCollapse == true ? 'continuous_easeOutCubic' : 'easeInOutCubic'}',
            'debugPrint=clipboard_copy_supported',
          ],
        ),
      );
    } finally {
      _parentSelectorReopenBlockedUntil =
          DateTime.now().add(_parentSelectorReopenCooldown);
      _debugLog('mode_reel_parent_selector_rearm_started', <String, Object?>{
        'cooldownMs': _parentSelectorReopenCooldown.inMilliseconds,
        'closePolicy': 'exactly_once',
        'navigatorPopCount': _lastParentSelectorNavigatorPopCount,
        'duplicateCloseCount': _lastParentSelectorDuplicateCloseCount,
        'motion': 'reel_press_release_120ms_then_rearm_cooldown',
      });
      if (mounted) {
        setState(() {
          _modeReelSelectorPressActive = false;
          _parentSelectorOpen = false;
        });
      } else {
        _modeReelSelectorPressActive = false;
        _parentSelectorOpen = false;
      }
      _endModeReelGuard();
      _onUserActivity();
    }
  }

  Map<CustomSemanticsAction, VoidCallback>? _modeReelSemanticsActions() {
    if (!_canUseModeReel()) return null;
    final vm = _viewMode;
    if (vm == null) return null;
    final to = _oppositeViewMode(vm.mode);
    return <CustomSemanticsAction, VoidCallback>{
      CustomSemanticsAction(
        label: '위로 돌려 ${to == TypeViewMode.table ? '테이블' : '현황'} 보기로 전환',
      ): () => unawaited(
            _runModeReelProgrammatic(
              physicalDirection: -1,
              source: 'semantics_up',
            ),
          ),
      CustomSemanticsAction(
        label: '아래로 돌려 ${to == TypeViewMode.table ? '테이블' : '현황'} 보기로 전환',
      ): () => unawaited(
            _runModeReelProgrammatic(
              physicalDirection: 1,
              source: 'semantics_down',
            ),
          ),
    };
  }

  Future<void> _runEntryQuickActionFromSurface(
    TypePageEntryQuickAction action,
    Rect sourceRect,
  ) async {
    _onUserActivity();
    _debugLog('quick_action_tap', <String, Object?>{
      'action': 'entry',
      'table': widget.tabs[_currentTableIndex].id,
      'mode': _viewMode?.mode.name,
      'sourceRect': '${sourceRect.left.toStringAsFixed(1)},${sourceRect.top.toStringAsFixed(1)},${sourceRect.width.toStringAsFixed(1)},${sourceRect.height.toStringAsFixed(1)}',
    });
    try {
      await action(sourceRect);
      _debugLog('quick_action_complete', <String, Object?>{
        'action': 'entry',
      });
    } catch (error, stackTrace) {
      _debugLog('quick_action_failure', <String, Object?>{
        'action': 'entry',
        'error': error,
      });
      debugPrint(
        '[TypePageQuickAction] action_failure action=entry error=$error\nStackTrace:\n$stackTrace',
      );
    }
  }

  Future<void> _runQuickActionFromSurface(
    String actionId,
    TypePageQuickAction action,
  ) async {
    _onUserActivity();
    _debugLog('quick_action_tap', <String, Object?>{
      'action': actionId,
      'table': widget.tabs[_currentTableIndex].id,
      'mode': _viewMode?.mode.name,
    });
    try {
      await action();
      _debugLog('quick_action_complete', <String, Object?>{
        'action': actionId,
      });
    } catch (error, stackTrace) {
      _debugLog('quick_action_failure', <String, Object?>{
        'action': actionId,
        'error': error,
      });
      debugPrint(
        '[TypePageQuickAction] action_failure action=$actionId error=$error\nStackTrace:\n$stackTrace',
      );
    }
  }

  String _resolveArea() {
    final userArea =
        context.select<UserState, String>((s) => s.currentArea.trim());
    final stateArea =
        context.select<AreaState, String>((s) => s.currentArea.trim());
    return userArea.isNotEmpty ? userArea : stateArea;
  }

  Color _statusHudColor(RealTimeTabSpec spec, CommonUiTokens tokens) {
    final id = spec.id.trim().toLowerCase();
    final collection = spec.collection.trim().toLowerCase();
    if (id == 'parking_requests' || collection == 'parking_requests_view') {
      return tokens.statusParkingRequested;
    }
    if (id == 'parking_completed' || collection == 'parking_completed_view') {
      return tokens.statusParkingCompleted;
    }
    if (id == 'departure_requests' ||
        collection == 'departure_requests_view') {
      return tokens.statusDepartureRequested;
    }
    return tokens.accent;
  }

  String _statusVisualRole(RealTimeTabSpec spec) {
    final id = spec.id.trim().toLowerCase();
    final collection = spec.collection.trim().toLowerCase();
    if (id == 'parking_requests' || collection == 'parking_requests_view') {
      return 'danger';
    }
    if (id == 'parking_completed' || collection == 'parking_completed_view') {
      return 'success';
    }
    if (id == 'departure_requests' ||
        collection == 'departure_requests_view') {
      return 'info';
    }
    return 'accent';
  }

  Color _statusVisualColor(CommonUiTokens tokens) {
    final currentIndex =
        _currentTableIndex.clamp(0, widget.tabs.length - 1);
    final currentColor = _statusHudColor(widget.tabs[currentIndex], tokens);
    final destinationIndex = _swipeDestinationIndex;
    if (destinationIndex < 0 ||
        destinationIndex >= widget.tabs.length ||
        destinationIndex == currentIndex ||
        _swipePhysicalDirection == 0) {
      return currentColor;
    }
    final destinationColor =
        _statusHudColor(widget.tabs[destinationIndex], tokens);
    final progress =
        _tableSwipeController.value.clamp(0.0, 1.0).toDouble();
    return Color.lerp(currentColor, destinationColor, progress) ?? currentColor;
  }

  String _tableContextLayoutMode(double width) {
    if (width >= 390) return 'regular';
    if (width >= 330) return 'compact';
    return 'narrow';
  }

  void _scheduleTableContextBarLayoutTrace({
    required double width,
    required String layout,
    required String sortLabel,
    required RealTimeTabSpec spec,
  }) {
    final signature = '$layout:${width.round() ~/ 8}:${spec.id}:$sortLabel';
    if (_lastTableContextBarLayoutSignature == signature) return;
    _lastTableContextBarLayoutSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _debugLog('table_context_bar_layout', <String, Object?>{
        'screen': widget.screen,
        'width': width.toStringAsFixed(1),
        'layout': layout,
        'sortLabel': sortLabel,
        'table': spec.id,
        'tableLabel': spec.label,
        'statusColor': _statusVisualRole(spec),
        'statusSignatureScheme':
            'parking_requests=danger;parking_completed=success;departure_requests=info',
        'contextSurface':
            widget.useListContextSurface ? 'list_surface' : 'card_surface',
        'swipeHintEnabled': widget.showColoredSwipeChevrons,
        'swipeHintStyle': widget.showColoredSwipeChevrons
            ? 'signature_color_chevron'
            : 'none',
        'smallPhoneResponsive': true,
        'firebaseAdditionalRead': 0,
      });
    });
  }

  Widget _buildTableContextSortSurface({
    required ColorScheme cs,
    required TextTheme text,
    required RealTimeSortState sortState,
    required String layout,
    required bool reduceMotion,
  }) {
    final regular = layout == 'regular';
    final narrow = layout == 'narrow';
    final label = regular ? sortState.summaryLabel : sortState.timeOrderLabel;
    final horizontalPadding = regular ? 11.0 : narrow ? 6.0 : 8.0;
    final iconSize = regular ? 17.0 : 16.0;

    Widget content({required FontWeight fontWeight}) {
      return Row(
        children: <Widget>[
          if (!narrow) ...<Widget>[
            Icon(
              Icons.table_rows_rounded,
              size: iconSize,
              color: cs.onSurfaceVariant,
            ),
            SizedBox(width: regular ? 7 : 5),
          ],
          Expanded(
            child: AnimatedSwitcher(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0, .12),
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: Align(
                key: ValueKey<String>('sort:$layout:$label'),
                alignment: Alignment.centerLeft,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    label,
                    maxLines: 1,
                    softWrap: false,
                    style: text.labelMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontWeight: fontWeight,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Semantics(
      label: '현재 정렬, ${sortState.timeOrderLabel}',
      child: widget.useListContextSurface
          ? SizedBox(
              height: 44,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: content(fontWeight: FontWeight.w700),
              ),
            )
          : AnimatedContainer(
              duration: reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 190),
              curve: Curves.easeOutCubic,
              constraints: const BoxConstraints(minHeight: 44),
              padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: cs.outlineVariant.withOpacity(.62),
                ),
              ),
              child: content(fontWeight: FontWeight.w900),
            ),
    );
  }

  Widget _buildTableContextStatusSurface({
    required TextTheme text,
    required CommonUiTokens tokens,
    required bool reduceMotion,
  }) {
    if (widget.useListContextSurface) {
      return AnimatedBuilder(
        animation: _statusVisualPulseController,
        builder: (context, _) {
          final currentIndex =
              _currentTableIndex.clamp(0, widget.tabs.length - 1);
          final currentSpec = widget.tabs[currentIndex];
          final signatureColor = _statusHudColor(currentSpec, tokens);
          final pulse = reduceMotion
              ? 0.0
              : _statusVisualPulseStrength(_statusVisualPulseController.value);
          final color = Color.lerp(
                signatureColor.withOpacity(tokens.isDark ? .88 : .84),
                signatureColor,
                pulse,
              ) ??
              signatureColor;
          return Semantics(
            label: '현재 테이블, ${currentSpec.label}',
            child: SizedBox(
              height: 44,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(.06, 0),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Center(
                    key: ValueKey<String>('status:${currentSpec.id}'),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        currentSpec.label,
                        maxLines: 1,
                        softWrap: false,
                        style: text.labelMedium?.copyWith(
                          color: color,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .1,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _tableSwipeController,
        _statusVisualPulseController,
      ]),
      builder: (context, _) {
        final currentIndex =
            _currentTableIndex.clamp(0, widget.tabs.length - 1);
        final currentSpec = widget.tabs[currentIndex];
        final destinationIndex = _swipeDestinationIndex;
        final destinationValid = destinationIndex >= 0 &&
            destinationIndex < widget.tabs.length &&
            destinationIndex != currentIndex &&
            _swipePhysicalDirection != 0;
        final destinationSpec =
            destinationValid ? widget.tabs[destinationIndex] : null;
        final rawProgress = destinationValid
            ? _tableSwipeController.value.clamp(0.0, 1.0).toDouble()
            : 0.0;
        final progress = reduceMotion
            ? (rawProgress >= .5 ? 1.0 : 0.0)
            : rawProgress;
        final currentColor = _statusHudColor(currentSpec, tokens);
        final destinationColor = destinationSpec == null
            ? currentColor
            : _statusHudColor(destinationSpec, tokens);
        final color = destinationSpec == null
            ? currentColor
            : Color.lerp(currentColor, destinationColor, progress) ??
                currentColor;
        final pulse = reduceMotion
            ? 0.0
            : _statusVisualPulseStrength(_statusVisualPulseController.value);
        final fillOpacity = (tokens.isDark ? .14 : .10) + (.025 * pulse);
        final borderOpacity = .34 + (.12 * pulse);
        final scale = 1 + (.012 * pulse);
        final direction = _swipePhysicalDirection == 0
            ? -1.0
            : _swipePhysicalDirection.toDouble();
        final currentOpacity = destinationSpec == null ? 1.0 : 1 - progress;
        final destinationOpacity = destinationSpec == null ? 0.0 : progress;

        Widget labelFor(
          RealTimeTabSpec spec, {
          required double opacity,
          required double translateX,
        }) {
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0).toDouble(),
            child: Transform.translate(
              offset: Offset(translateX, 0),
              child: Center(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    spec.label,
                    maxLines: 1,
                    softWrap: false,
                    style: text.labelMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w900,
                      letterSpacing: .1,
                    ),
                  ),
                ),
              ),
            ),
          );
        }

        return Semantics(
          label: '현재 테이블, ${currentSpec.label}',
          child: Transform.scale(
            scale: scale,
            child: Container(
              constraints: const BoxConstraints(minHeight: 44),
              padding: const EdgeInsets.symmetric(horizontal: 9),
              decoration: BoxDecoration(
                color: color.withOpacity(fillOpacity),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(
                  color: color.withOpacity(borderOpacity),
                ),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  labelFor(
                    currentSpec,
                    opacity: currentOpacity,
                    translateX: direction * 5 * progress,
                  ),
                  if (destinationSpec != null)
                    labelFor(
                      destinationSpec,
                      opacity: destinationOpacity,
                      translateX: -direction * 5 * (1 - progress),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildTableSwipeEdgeChevron({
    required bool leftEdge,
    required CommonUiTokens tokens,
    required bool reduceMotion,
    required double extent,
  }) {
    if (!widget.showColoredSwipeChevrons ||
        !_gatesLoaded ||
        _enabledTableIndices().length <= 1) {
      return SizedBox(width: extent, height: 44);
    }
    final targetStep = leftEdge ? -1 : 1;
    final targetIndex = _targetTableIndex(targetStep);
    if (targetIndex < 0 || targetIndex >= widget.tabs.length) {
      return SizedBox(width: extent, height: 44);
    }
    final targetSpec = widget.tabs[targetIndex];
    final targetColor = _statusHudColor(targetSpec, tokens);
    final selectedDirection = leftEdge ? 1 : -1;
    return ExcludeSemantics(
      child: IgnorePointer(
        child: AnimatedBuilder(
          animation: _tableSwipeController,
          builder: (context, _) {
            final strength = _tableSwipeHintStrength();
            final hasDirection = _swipePhysicalDirection != 0;
            final selected =
                hasDirection && _swipePhysicalDirection == selectedDirection;
            final opacity = !hasDirection
                ? _tableSwipeHintIdleOpacity
                : selected
                    ? _tableSwipeHintIdleOpacity +
                        ((_tableSwipeHintActiveOpacity -
                                _tableSwipeHintIdleOpacity) *
                            strength)
                    : _tableSwipeHintIdleOpacity +
                        ((_tableSwipeHintOppositeOpacity -
                                _tableSwipeHintIdleOpacity) *
                            strength);
            final translate = reduceMotion || !selected
                ? 0.0
                : (leftEdge ? 1.0 : -1.0) *
                    _tableSwipeHintMaxTranslate *
                    strength;
            final scale = reduceMotion || !selected
                ? 1.0
                : 1 + ((_tableSwipeHintMaxScale - 1) * strength);
            return SizedBox(
              width: extent,
              height: 44,
              child: Center(
                child: Transform.translate(
                  offset: Offset(translate, 0),
                  child: Transform.scale(
                    scale: scale,
                    child: Icon(
                      leftEdge
                          ? Icons.chevron_right_rounded
                          : Icons.chevron_left_rounded,
                      size: 20,
                      color: targetColor.withOpacity(
                        opacity.clamp(0.0, 1.0).toDouble(),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTableContextBar(ColorScheme cs) {
    final tableMode = (_viewMode?.mode ?? TypeViewMode.table) ==
        TypeViewMode.table;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSize(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedSwitcher(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 190),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SizeTransition(
              sizeFactor: curved,
              axisAlignment: -1,
              child: child,
            ),
          );
        },
        child: tableMode
            ? Consumer<RealTimeSortState>(
                key: const ValueKey<String>('table-context-bar'),
                builder: (context, sortState, _) {
                  final text = Theme.of(context).textTheme;
                  final tokens = CommonUiTheme.of(context);
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final mediaWidth = MediaQuery.sizeOf(context).width;
                      final width = constraints.maxWidth.isFinite &&
                              constraints.maxWidth > 0
                          ? constraints.maxWidth
                          : mediaWidth;
                      final layout = _tableContextLayoutMode(width);
                      final regular = layout == 'regular';
                      final narrow = layout == 'narrow';
                      final horizontalPadding = widget.useListContextSurface
                          ? 4.0
                          : regular
                              ? 12.0
                              : narrow
                                  ? 8.0
                                  : 10.0;
                      final gap = regular ? 8.0 : narrow ? 4.0 : 6.0;
                      final leftFlex = regular ? 58 : narrow ? 46 : 52;
                      final rightFlex = 100 - leftFlex;
                      final edgeExtent = narrow ? 28.0 : 30.0;
                      final spec = widget.tabs[
                          _currentTableIndex.clamp(0, widget.tabs.length - 1)];
                      _scheduleTableContextBarLayoutTrace(
                        width: width,
                        layout: layout,
                        sortLabel: sortState.timeOrderLabel,
                        spec: spec,
                      );
                      final canSwipe = _canSwipeTables();
                      final listSurfaceChildren = <Widget>[
                        if (widget.showColoredSwipeChevrons)
                          _buildTableSwipeEdgeChevron(
                            leftEdge: true,
                            tokens: tokens,
                            reduceMotion: reduceMotion,
                            extent: edgeExtent,
                          ),
                        Expanded(
                          flex: leftFlex,
                          child: _buildTableContextSortSurface(
                            cs: cs,
                            text: text,
                            sortState: sortState,
                            layout: layout,
                            reduceMotion: reduceMotion,
                          ),
                        ),
                        Padding(
                          padding: EdgeInsets.symmetric(horizontal: gap),
                          child: Container(
                            width: 1,
                            height: 18,
                            color: cs.outlineVariant.withOpacity(.48),
                          ),
                        ),
                        Expanded(
                          flex: rightFlex,
                          child: _buildTableContextStatusSurface(
                            text: text,
                            tokens: tokens,
                            reduceMotion: reduceMotion,
                          ),
                        ),
                        if (widget.showColoredSwipeChevrons)
                          _buildTableSwipeEdgeChevron(
                            leftEdge: false,
                            tokens: tokens,
                            reduceMotion: reduceMotion,
                            extent: edgeExtent,
                          ),
                      ];
                      final cardSurfaceChildren = <Widget>[
                        Expanded(
                          flex: leftFlex,
                          child: _buildTableContextSortSurface(
                            cs: cs,
                            text: text,
                            sortState: sortState,
                            layout: layout,
                            reduceMotion: reduceMotion,
                          ),
                        ),
                        SizedBox(width: gap),
                        Expanded(
                          flex: rightFlex,
                          child: _buildTableContextStatusSurface(
                            text: text,
                            tokens: tokens,
                            reduceMotion: reduceMotion,
                          ),
                        ),
                      ];
                      return GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        excludeFromSemantics: true,
                        onHorizontalDragStart: canSwipe
                            ? (details) => _onTableHorizontalDragStart(
                                  details,
                                  width <= 0 ? 1 : width,
                                )
                            : null,
                        onHorizontalDragUpdate:
                            canSwipe ? _onTableHorizontalDragUpdate : null,
                        onHorizontalDragEnd:
                            canSwipe ? _onTableHorizontalDragEnd : null,
                        onHorizontalDragCancel:
                            canSwipe ? _onTableHorizontalDragCancel : null,
                        child: Container(
                          padding: EdgeInsets.fromLTRB(
                            horizontalPadding,
                            4,
                            horizontalPadding,
                            6,
                          ),
                          decoration: BoxDecoration(
                            color: cs.surface,
                            border: Border(
                              bottom: BorderSide(
                                color: cs.outlineVariant.withOpacity(.70),
                              ),
                            ),
                          ),
                          child: SizedBox(
                            height: 44,
                            child: Row(
                              children: widget.useListContextSurface
                                  ? listSurfaceChildren
                                  : cardSurfaceChildren,
                            ),
                          ),
                        ),
                      );
                    },
                  );
                },
              )
            : const SizedBox.shrink(
                key: ValueKey<String>('table-context-bar-hidden'),
              ),
      ),
    );
  }

  double _statusVisualPulseStrength(double progress) {
    final p = progress.clamp(0.0, 1.0).toDouble();
    if (p <= .35) {
      return Curves.easeOutCubic.transform(p / .35);
    }
    return 1 - Curves.easeInOutCubic.transform((p - .35) / .65);
  }

  void _onStatusVisualPulseStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed || !mounted) return;
    final spec = widget.tabs[_currentTableIndex];
    _debugLog('status_visual_pulse_complete', <String, Object?>{
      'table': spec.id,
      'statusColor': _statusVisualRole(spec),
      'statusVisual': 'rail+ambient_wash+responsive_context_bar',
    });
  }

  void _triggerStatusVisualPulse(RealTimeTabSpec spec) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _statusVisualPulseController.value = 0;
      _debugLog('status_visual_pulse_skipped', <String, Object?>{
        'reason': 'reduce_motion',
        'table': spec.id,
        'statusColor': _statusVisualRole(spec),
        'statusSignatureScheme':
            'parking_requests=danger;parking_completed=success;departure_requests=info',
      });
      return;
    }
    _debugLog('status_visual_pulse_start', <String, Object?>{
      'table': spec.id,
      'statusColor': _statusVisualRole(spec),
      'railOpacity': '0.68->0.95->0.68',
      'durationMs': _statusVisualPulseController.duration?.inMilliseconds,
    });
    _statusVisualPulseController.stop();
    _statusVisualPulseController.forward(from: 0);
  }

  Widget _buildStatusContextOverlay() {
    final tokens = CommonUiTheme.of(context);
    final tableMode = _viewMode?.mode == TypeViewMode.table;
    return Positioned.fill(
      child: ExcludeSemantics(
        child: IgnorePointer(
          ignoring: true,
          child: AnimatedOpacity(
            opacity: tableMode ? 1 : 0,
            duration: _motionDuration(const Duration(milliseconds: 180)),
            curve: Curves.easeOutCubic,
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[
                _tableSwipeController,
                _statusVisualPulseController,
              ]),
              builder: (context, _) {
                final color = _statusVisualColor(tokens);
                final pulse = _statusVisualPulseStrength(
                  _statusVisualPulseController.value,
                );
                final railOpacity = .68 + (.27 * pulse);
                final washBase = tokens.isDark ? .07 : .045;
                final washOpacity = washBase + (.012 * pulse);
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    Align(
                      alignment: Alignment.topCenter,
                      child: SizedBox(
                        width: double.infinity,
                        height: 84,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: <Color>[
                                color.withOpacity(washOpacity),
                                color.withOpacity(washOpacity * .42),
                                Colors.transparent,
                              ],
                              stops: const <double>[0, .44, 1],
                            ),
                          ),
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.topCenter,
                      child: Opacity(
                        opacity: railOpacity.clamp(0.0, 1.0).toDouble(),
                        child: SizedBox(
                          width: double.infinity,
                          height: 3,
                          child: ColoredBox(color: color),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHudCount({
    required RealTimeTabSpec spec,
    required int index,
    required String area,
    required CommonUiTokens tokens,
  }) {
    final collection = spec.collection.trim();
    final normalizedArea = area.trim();
    if (collection.isEmpty || normalizedArea.isEmpty) {
      return const SizedBox.shrink();
    }

    final color = _statusHudColor(spec, tokens);
    return Selector<ViewDocRowsStore, int>(
      selector: (_, store) =>
          store.rows(collection: collection, area: normalizedArea).length,
      builder: (context, count, _) {
        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            _hudPulseController,
            _tableSwipeController,
          ]),
          builder: (context, child) {
            final baseOpacity = _hudBaseOpacityForIndex(index);
            return Opacity(
              opacity: _hudOpacity(
                _hudPulseController.value,
                baseOpacity: baseOpacity,
              ),
              child: child,
            );
          },
          child: AnimatedSwitcher(
            duration: _motionDuration(const Duration(milliseconds: 170)),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
                reverseCurve: Curves.easeInCubic,
              );
              return FadeTransition(
                opacity: curved,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0, .16),
                    end: Offset.zero,
                  ).animate(curved),
                  child: child,
                ),
              );
            },
            child: Text(
              '$count',
              key: ValueKey<String>('${spec.id}:$count'),
              textAlign: TextAlign.center,
              style: (Theme.of(context).textTheme.titleLarge ??
                      const TextStyle())
                  .copyWith(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
                fontFeatures: const <FontFeature>[
                  FontFeature.tabularFigures(),
                ],
                height: 1,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatePageAt(int index) {
    final normalizedIndex = index.clamp(0, widget.tabs.length - 1);
    final spec = widget.tabs[normalizedIndex];
    final Widget content;

    if (_isTableEnabled(normalizedIndex)) {
      final table = KeyedSubtree(
        key: ValueKey<String>('table:${spec.id}'),
        child: RealTimeTableBody(
          controller: _controllers[normalizedIndex],
          spec: spec,
          description: widget.description,
          screen: widget.screen,
          onUserActivity: _onUserActivity,
          onAutoPauseStart: _beginAutoPause,
          onAutoPauseEnd: _endAutoPause,
        ),
      );
      final custom = widget.bodyBuilder;
      final activeChild = custom != null
          ? KeyedSubtree(
              key: ValueKey<String>('status:${spec.id}'),
              child: custom(
                context,
                spec,
                _controllers[normalizedIndex],
              ),
            )
          : table;
      content = AnimatedSwitcher(
        duration: _motionDuration(const Duration(milliseconds: 320)),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: _sharedAxisYTransition,
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        child: activeChild,
      );
    } else {
      content = RealTimeLockedPanel(
        title: '${spec.label} 실시간 테이블이 비활성화되어 있습니다',
        message: '설정에서 “${spec.label} 실시간 모드 사용”을 ON으로 변경한 뒤 다시 시도해 주세요.',
      );
    }

    return KeyedSubtree(
      key: ValueKey<String>('state-page:${spec.id}'),
      child: content,
    );
  }

  Widget _buildInteractiveSwipePages(double viewportWidth) {
    final currentIndex = _currentTableIndex;
    final currentSpec = widget.tabs[currentIndex];
    final currentPage = _buildStatePageAt(currentIndex);
    final destinationIndex = _swipeDestinationIndex;
    final hasDestination = destinationIndex >= 0 &&
        destinationIndex < widget.tabs.length &&
        destinationIndex != currentIndex;
    final destinationSpec =
        hasDestination ? widget.tabs[destinationIndex] : null;
    final destinationPage =
        hasDestination ? _buildStatePageAt(destinationIndex) : null;

    return ClipRect(
      child: AnimatedBuilder(
        animation: _tableSwipeController,
        builder: (context, _) {
          final progress =
              _tableSwipeController.value.clamp(0.0, 1.0).toDouble();
          final direction = _swipePhysicalDirection;
          final swipeActive =
              destinationPage != null && destinationSpec != null && direction != 0;
          final currentDx =
              swipeActive ? direction * progress * viewportWidth : 0.0;
          final destinationDx = swipeActive
              ? direction * (progress - 1) * viewportWidth
              : 0.0;
          final currentOpacity =
              swipeActive ? 1 - (.08 * progress) : 1.0;
          final destinationOpacity =
              swipeActive ? .92 + (.08 * progress) : 0.0;

          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              if (swipeActive)
                KeyedSubtree(
                  key: ValueKey<String>(
                    'swipe-page:${destinationSpec.id}',
                  ),
                  child: Transform.translate(
                    offset: Offset(destinationDx, 0),
                    child: Opacity(
                      opacity:
                          destinationOpacity.clamp(0.0, 1.0).toDouble(),
                      child: destinationPage,
                    ),
                  ),
                )
              else
                const SizedBox.shrink(
                  key: ValueKey<String>('swipe-page:empty-destination'),
                ),
              KeyedSubtree(
                key: ValueKey<String>('swipe-page:${currentSpec.id}'),
                child: Transform.translate(
                  offset: Offset(currentDx, 0),
                  child: Opacity(
                    opacity: currentOpacity.clamp(0.0, 1.0).toDouble(),
                    child: currentPage,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSwipeableStateContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final viewportWidth = constraints.maxWidth.isFinite &&
                constraints.maxWidth > 0
            ? constraints.maxWidth
            : screenWidth > 0
                ? screenWidth
                : 1.0;
        final canSwipe = _canSwipeTables();
        return Semantics(
          customSemanticsActions: _tableSemanticsActions(),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragStart: canSwipe
                ? (details) => _onTableHorizontalDragStart(
                      details,
                      viewportWidth,
                    )
                : null,
            onHorizontalDragUpdate:
                canSwipe ? _onTableHorizontalDragUpdate : null,
            onHorizontalDragEnd: canSwipe ? _onTableHorizontalDragEnd : null,
            onHorizontalDragCancel:
                canSwipe ? _onTableHorizontalDragCancel : null,
            child: _buildInteractiveSwipePages(viewportWidth),
          ),
        );
      },
    );
  }

  Widget _buildQuickActions(
    BuildContext context,
    TypePageQuickActionScope actions,
    ColorScheme cs,
  ) {
    return Row(
      children: [
        Expanded(
          child: _TypePageQuickActionControl(
            semanticsLabel: '입차',
            icon: Icons.add_circle_outline_rounded,
            foreground: cs.primary,
            showProgressWhileRunning: false,
            onPressed: (sourceRect) =>
                _runEntryQuickActionFromSurface(actions.openEntry, sourceRect),
          ),
        ),
        Expanded(
          child: _TypePageQuickActionControl(
            semanticsLabel: '검색',
            icon: Icons.manage_search_rounded,
            foreground: cs.onSurfaceVariant,
            onPressed: (_) => _runQuickActionFromSurface(
              'search',
              actions.openSearch,
            ),
          ),
        ),
        Expanded(
          child: _TypePageQuickActionControl(
            semanticsLabel: '대시보드',
            icon: Icons.dashboard_rounded,
            foreground: cs.onSurfaceVariant,
            onPressed: (_) => _runQuickActionFromSurface(
              'dashboard',
              actions.openDashboard,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLayerSurface(ColorScheme cs) {
    final actions = TypePageQuickActionScope.maybeOf(context);
    if (actions == null) return const SizedBox.shrink();
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: widget.tabBarStyle.containerColor(cs),
        border: Border(
          top: BorderSide(color: widget.tabBarStyle.borderColor(cs)),
        ),
      ),
      child: _buildQuickActions(context, actions, cs),
    );
  }

  double _modeControlRowExtent(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final bottomPadding = bottomInset > 8 ? bottomInset : 8.0;
    final contentHeight = _parkingViewCapability == ParkingViewCapability.empty
        ? 72.0
        : 64.0;
    return 7 + contentHeight + bottomPadding;
  }

  Widget _buildStatusCountOverlay({
    required String area,
    required double modeReelExtent,
  }) {
    final tokens = CommonUiTheme.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: modeReelExtent + 56,
      height: 34,
      child: ExcludeSemantics(
        child: IgnorePointer(
          ignoring: true,
          child: Row(
            children: List<Widget>.generate(widget.tabs.length, (index) {
              final spec = widget.tabs[index];
              return Expanded(
                child: Align(
                  alignment: Alignment.center,
                  child: _buildStatusHudCount(
                    spec: spec,
                    index: index,
                    area: area,
                    tokens: tokens,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildModeReelGlyph(
    TypeViewMode mode,
    Color color, {
    double size = 25,
  }) {
    if (mode == TypeViewMode.table) {
      return Icon(
        Icons.table_rows_rounded,
        size: size,
        color: color,
      );
    }
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _StatusDotMapGlyphPainter(color: color),
      ),
    );
  }

  Widget _buildModeReelItem({
    required TypeViewMode mode,
    required Color color,
    required double translateY,
    required double rotationX,
    required double opacity,
    required double scale,
  }) {
    return Transform.translate(
      offset: Offset(0, translateY),
      child: Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..setEntry(3, 2, .0018)
          ..rotateX(rotationX),
        child: Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0).toDouble(),
            child: _buildModeReelGlyph(mode, color),
          ),
        ),
      ),
    );
  }

  Widget _buildModeReelGuide({
    required ColorScheme cs,
    required TypeViewMode nextMode,
    required double opacity,
    required double offsetY,
  }) {
    final guideColor = cs.primary.withOpacity(.64 * opacity);
    final ghostColor = cs.primary.withOpacity(.30 * opacity);
    return Transform.translate(
      offset: Offset(0, offsetY),
      child: Opacity(
        opacity: opacity.clamp(0.0, 1.0).toDouble(),
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            Align(
              alignment: const Alignment(0, -1),
              child: Icon(
                Icons.keyboard_arrow_up_rounded,
                size: 15,
                color: guideColor,
              ),
            ),
            Align(
              alignment: const Alignment(0, -.58),
              child: _buildModeReelGlyph(
                nextMode,
                ghostColor,
                size: 11,
              ),
            ),
            Align(
              alignment: const Alignment(0, .58),
              child: _buildModeReelGlyph(
                nextMode,
                ghostColor,
                size: 11,
              ),
            ),
            Align(
              alignment: const Alignment(0, 1),
              child: Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 15,
                color: guideColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeReelVisual(ColorScheme cs) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return ExcludeSemantics(
      child: SizedBox(
        width: 112,
        height: 64,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              _modeReelController,
              _modeReelHintController,
            ]),
            builder: (context, _) {
              final liveMode = _viewMode?.mode ?? TypeViewMode.table;
              final from = (_modeReelDragActive || _modeReelTransitioning)
                  ? (_modeReelFromMode ?? liveMode)
                  : liveMode;
              final to = _oppositeViewMode(from);
              final progress = _modeReelController.value
                  .clamp(0.0, 1.0)
                  .toDouble();
              final direction = _modeReelPhysicalDirection == 0
                  ? -1
                  : _modeReelPhysicalDirection;
              final guideOpacity =
                  (1 - progress * 2.2).clamp(0.0, 1.0).toDouble();
              final hintWave = reduceMotion || progress > .01
                  ? 0.0
                  : math.sin(_modeReelHintController.value * math.pi * 2);
              final hintOffset = hintWave * 2.4;
              if (reduceMotion) {
                final visibleMode = progress >= .5 ? to : from;
                return Stack(
                  fit: StackFit.expand,
                  children: <Widget>[
                    _buildModeReelGuide(
                      cs: cs,
                      nextMode: _oppositeViewMode(visibleMode),
                      opacity: 1,
                      offsetY: 0,
                    ),
                    Center(
                      child: _buildModeReelGlyph(
                        visibleMode,
                        cs.primary,
                        size: 27,
                      ),
                    ),
                  ],
                );
              }
              final travel = 36.0;
              final maxAngle = math.pi * 55 / 180;
              final currentY = direction * travel * progress;
              final nextY = -direction * travel * (1 - progress);
              final currentAngle = direction * maxAngle * progress;
              final nextAngle = -direction * maxAngle * (1 - progress);
              final currentOpacity = 1 - (.70 * progress);
              final nextOpacity = progress <= .02
                  ? 0.0
                  : .30 + (.70 * progress);
              final currentScale = 1 - (.12 * progress);
              final nextScale = .88 + (.12 * progress);
              return Stack(
                fit: StackFit.expand,
                children: <Widget>[
                  _buildModeReelGuide(
                    cs: cs,
                    nextMode: to,
                    opacity: guideOpacity,
                    offsetY: hintOffset,
                  ),
                  Center(
                    child: _buildModeReelItem(
                      mode: to,
                      color: cs.primary,
                      translateY: nextY,
                      rotationX: nextAngle,
                      opacity: nextOpacity,
                      scale: nextScale,
                    ),
                  ),
                  Center(
                    child: _buildModeReelItem(
                      mode: from,
                      color: cs.primary,
                      translateY: currentY,
                      rotationX: currentAngle,
                      opacity: currentOpacity,
                      scale: currentScale,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildModeReelSurface(ColorScheme cs) {
    final mode = _viewMode?.mode ?? TypeViewMode.table;
    final nextMode = _oppositeViewMode(mode);
    return Container(
      key: const ValueKey<String>('parking-mode:table-and-status'),
      color: widget.tabBarStyle.containerColor(cs),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 7, 12, 8),
        child: Semantics(
          button: true,
          enabled: _canUseModeReel(),
          label: '보기 모드 전환 및 부모 주차 구역 선택',
          value:
              '현재 ${mode == TypeViewMode.table ? '테이블' : '현황'} 보기. 위 또는 아래로 밀어 ${nextMode == TypeViewMode.table ? '테이블' : '현황'} 보기로 전환할 수 있습니다. 탭하면 부모 주차 구역을 선택합니다.',
          onTap: _onModeReelTap,
          onLongPress: () => unawaited(_onModeReelLongPress()),
          customSemanticsActions: _modeReelSemanticsActions(),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            excludeFromSemantics: true,
            onTap: _onModeReelTap,
            onLongPressStart: (_) => unawaited(_onModeReelLongPress()),
            onVerticalDragStart: _onModeReelDragStart,
            onVerticalDragUpdate: _onModeReelDragUpdate,
            onVerticalDragEnd: _onModeReelDragEnd,
            onVerticalDragCancel: _onModeReelDragCancel,
            child: SizedBox(
              height: 64,
              width: double.infinity,
              child: Center(
                child: KeyedSubtree(
                  key: _modeReelSourceKey,
                  child: AnimatedScale(
                    scale: _modeReelSelectorPressActive ? .94 : 1,
                    duration: _motionDuration(
                      const Duration(milliseconds: 120),
                    ),
                    curve: Curves.easeOutCubic,
                    child: AnimatedOpacity(
                      opacity: _modeReelSelectorPressActive ? .88 : 1,
                      duration: _motionDuration(
                        const Duration(milliseconds: 120),
                      ),
                      child: _buildModeReelVisual(cs),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTableOnlyModeSurface(ColorScheme cs) {
    return Container(
      key: const ValueKey<String>('parking-mode:table-only'),
      color: widget.tabBarStyle.containerColor(cs),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 7, 12, 8),
        child: Semantics(
          label: '현재 지역은 테이블 보기만 지원합니다.',
          child: SizedBox(
            height: 64,
            width: double.infinity,
            child: Center(
              child: ExcludeSemantics(
                child: SizedBox(
                  width: 112,
                  height: 64,
                  child: Stack(
                    fit: StackFit.expand,
                    children: <Widget>[
                      Center(
                        child: Icon(
                          Icons.table_rows_rounded,
                          size: 29,
                          color: cs.primary,
                        ),
                      ),
                      Align(
                        alignment: const Alignment(0, .76),
                        child: Icon(
                          Icons.horizontal_rule_rounded,
                          size: 26,
                          color: cs.outlineVariant.withOpacity(.72),
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
    );
  }

  Widget _buildLocationLoadingSurface(ColorScheme cs) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey<String>('parking-mode:loading'),
      color: widget.tabBarStyle.containerColor(cs),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 7, 12, 8),
        child: SizedBox(
          height: 64,
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    color: cs.primary,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '주차 구역 확인 중',
                  style: text.labelLarge?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _runOperationalSyncFromEmptySurface() async {
    if (_operationalSyncRunning) return;
    setState(() {
      _operationalSyncRunning = true;
    });
    _debugLog('operational_sync_requested', <String, Object?>{
      'source': 'realtime_location_empty_surface',
      'capability': _parkingViewCapability.name,
    });
    try {
      final result = await OperationalDataSyncWorkflow.runCurrentArea(
        context: context,
        useCommonUi: true,
      );
      _debugLog('operational_sync_result', <String, Object?>{
        'source': 'realtime_location_empty_surface',
        'result': result.name,
      });
    } catch (error, stackTrace) {
      _debugLog('operational_sync_failure', <String, Object?>{
        'source': 'realtime_location_empty_surface',
        'error': error,
      });
      debugPrint(
        '[RealTimeViewMode] operational_sync_failure error=$error\nStackTrace:\n$stackTrace',
      );
    } finally {
      if (mounted) {
        setState(() {
          _operationalSyncRunning = false;
        });
      }
    }
  }

  Widget _buildLocationEmptySurface(ColorScheme cs) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey<String>('parking-mode:empty'),
      color: widget.tabBarStyle.containerColor(cs),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 7, 12, 8),
        child: SizedBox(
          height: 72,
          child: Row(
            children: <Widget>[
              Icon(
                Icons.location_off_rounded,
                size: 22,
                color: cs.onSurfaceVariant,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '주차 구역 데이터가 없습니다.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.labelLarge?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '현재 지역의 운영 데이터를 내려받아 주세요.',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: text.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 150,
                child: CommonButton(
                  label: _operationalSyncRunning ? '내려받는 중' : '지금 내려받기',
                  icon: Icons.download_rounded,
                  loading: _operationalSyncRunning,
                  onPressed: _operationalSyncRunning
                      ? null
                      : _runOperationalSyncFromEmptySurface,
                  minHeight: 44,
                  preserveVariantWhenDisabled: true,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParkingModeControlSurface(ColorScheme cs) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final child = switch (_parkingViewCapability) {
      ParkingViewCapability.loading => _buildLocationLoadingSurface(cs),
      ParkingViewCapability.empty => _buildLocationEmptySurface(cs),
      ParkingViewCapability.tableOnly => _buildTableOnlyModeSurface(cs),
      ParkingViewCapability.tableAndStatus => _buildModeReelSurface(cs),
    };
    return AnimatedSize(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      child: AnimatedSwitcher(
        duration: reduceMotion
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
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final area = _resolveArea();
    final modeReelExtent = _modeControlRowExtent(context);
    return Container(
      color: cs.surface,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Column(
            children: [
              _buildTableContextBar(cs),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildSwipeableStateContent(),
                    _buildStatusContextOverlay(),
                    _transitionMaskLayer(context),
                  ],
                ),
              ),
              _buildLayerSurface(cs),
              _buildParkingModeControlSurface(cs),
            ],
          ),
          _buildStatusCountOverlay(
            area: area,
            modeReelExtent: modeReelExtent,
          ),
        ],
      ),
    );
  }

}

class _ParentSelectorItem {
  const _ParentSelectorItem({
    required this.parent,
    required this.grid,
    required this.childRects,
  });

  final String parent;
  final ParkingGridModel? grid;
  final List<GridRect> childRects;

  String get previewSource {
    if (grid != null) return 'parent_parking_grid';
    if (childRects.isNotEmpty) return 'child_rects';
    return 'icon_fallback';
  }
}

class _ParentSelectorGridMetrics {
  const _ParentSelectorGridMetrics({
    required this.columns,
    required this.rows,
    required this.previewHeight,
    required this.tileExtent,
    required this.crossAxisSpacing,
    required this.mainAxisSpacing,
    required this.horizontalPadding,
    required this.targetHeight,
    required this.gridViewportHeight,
    required this.gridContentHeight,
    required this.scrollNeeded,
    required this.modalWidth,
    required this.modalCenter,
  });

  final int columns;
  final int rows;
  final double previewHeight;
  final double tileExtent;
  final double crossAxisSpacing;
  final double mainAxisSpacing;
  final double horizontalPadding;
  final double targetHeight;
  final double gridViewportHeight;
  final double gridContentHeight;
  final bool scrollNeeded;
  final double modalWidth;
  final Offset modalCenter;
}

class _ParentSelectorDialogSurface extends StatelessWidget {
  const _ParentSelectorDialogSurface({
    required this.parents,
    required this.metrics,
    required this.currentParent,
    required this.progress,
    required this.interactionEnabled,
    required this.onClose,
    required this.onSelected,
  });

  final List<_ParentSelectorItem> parents;
  final _ParentSelectorGridMetrics metrics;
  final String currentParent;
  final double progress;
  final bool interactionEnabled;
  final VoidCallback onClose;
  final ValueChanged<_ParentSelectorItem> onSelected;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final headerProgress =
        ((progress - .52) / .48).clamp(0.0, 1.0).toDouble();
    final surfaceOpacity = (.92 + .04 * progress).clamp(0.0, 1.0).toDouble();
    final contentProgress =
        ((progress - .34) / .66).clamp(0.0, 1.0).toDouble();
    return Material(
      color: cs.surface.withOpacity(surfaceOpacity),
      child: Stack(
        children: [
          Positioned.fill(
            top: 41,
            child: IgnorePointer(
              ignoring: !interactionEnabled,
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  metrics.horizontalPadding,
                  4,
                  metrics.horizontalPadding,
                  10,
                ),
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: metrics.scrollNeeded
                      ? const BouncingScrollPhysics()
                      : const NeverScrollableScrollPhysics(),
                  itemCount: parents.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: metrics.columns,
                    crossAxisSpacing: metrics.crossAxisSpacing,
                    mainAxisSpacing: metrics.mainAxisSpacing,
                    mainAxisExtent: metrics.tileExtent,
                  ),
                  itemBuilder: (context, index) {
                    final item = parents[index];
                    final stagger = ((contentProgress * 1.2) - index * .04)
                        .clamp(0.0, 1.0)
                        .toDouble();
                    return Opacity(
                      opacity: stagger,
                      child: Transform.translate(
                        offset: Offset(0, 6 * (1 - stagger)),
                        child: Transform.scale(
                          scale: .94 + .06 * stagger,
                          child: _ParentSelectorTile(
                            item: item,
                            previewHeight: metrics.previewHeight,
                            selected:
                                item.parent.trim() == currentParent.trim(),
                            onTap: () => onSelected(item),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          if (headerProgress > .01)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 38,
              child: IgnorePointer(
                ignoring: headerProgress < .9,
                child: Opacity(
                  opacity: headerProgress,
                  child: Transform.translate(
                    offset: Offset(0, -8 * (1 - headerProgress)),
                    child: ColoredBox(
                      color: cs.surface.withOpacity(.94),
                      child: Row(
                        children: [
                          Semantics(
                            button: true,
                            label: '부모 주차 구역 선택 닫기',
                            child: IconButton(
                              onPressed: onClose,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints.tightFor(
                                width: 38,
                                height: 38,
                              ),
                              splashRadius: 18,
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                size: 20,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Center(
                              child: Icon(
                                Icons.local_parking_rounded,
                                size: 20,
                                color: cs.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 38),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ParentSelectorTile extends StatefulWidget {
  const _ParentSelectorTile({
    required this.item,
    required this.previewHeight,
    required this.selected,
    required this.onTap,
  });

  final _ParentSelectorItem item;
  final double previewHeight;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_ParentSelectorTile> createState() => _ParentSelectorTileState();
}

class _ParentSelectorTileState extends State<_ParentSelectorTile> {
  bool _pressed = false;
  bool _activating = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value || _activating) return;
    setState(() {
      _pressed = value;
    });
  }

  Future<void> _activate() async {
    if (_activating) return;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    setState(() {
      _pressed = false;
      _activating = true;
    });
    if (!reduceMotion) {
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
    }
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final selected = widget.selected || _activating;
    final scale = _activating ? .94 : (_pressed ? .97 : 1.0);
    final opacity = _pressed ? .82 : 1.0;
    final duration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 110);
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.item.parent,
      child: AnimatedScale(
        scale: scale,
        duration: duration,
        curve: Curves.easeOutCubic,
        child: AnimatedOpacity(
          opacity: opacity,
          duration: duration,
          curve: Curves.easeOutCubic,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTapDown: (_) => _setPressed(true),
              onTapCancel: () => _setPressed(false),
              onTapUp: (_) => _setPressed(false),
              onTap: () => unawaited(_activate()),
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: widget.previewHeight,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          IgnorePointer(
                            ignoring: true,
                            child: ExcludeSemantics(
                              child: RealTimeParentMapThumbnail(
                                grid: widget.item.grid,
                                childRects: widget.item.childRects,
                                selected: selected,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            right: 0,
                            child: AnimatedSwitcher(
                              duration: reduceMotion
                                  ? Duration.zero
                                  : const Duration(milliseconds: 150),
                              switchInCurve: Curves.easeOutBack,
                              switchOutCurve: Curves.easeInCubic,
                              transitionBuilder: (child, animation) {
                                return ScaleTransition(
                                  scale: animation,
                                  child: FadeTransition(
                                    opacity: animation,
                                    child: child,
                                  ),
                                );
                              },
                              child: selected
                                  ? Icon(
                                      Icons.check_circle_rounded,
                                      key: const ValueKey<String>('selected'),
                                      size: 16,
                                      color: cs.primary,
                                    )
                                  : const SizedBox(
                                      key: ValueKey<String>('not-selected'),
                                      width: 16,
                                      height: 16,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 22,
                      child: Center(
                        child: Text(
                          widget.item.parent,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: text.labelMedium?.copyWith(
                            color: cs.onSurface,
                            fontWeight:
                                selected ? FontWeight.w900 : FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusDotMapGlyphPainter extends CustomPainter {
  const _StatusDotMapGlyphPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    final radius = size.shortestSide * .105;
    final points = <Offset>[
      Offset(size.width * .24, size.height * .28),
      Offset(size.width * .76, size.height * .28),
      Offset(size.width * .50, size.height * .50),
      Offset(size.width * .24, size.height * .72),
      Offset(size.width * .76, size.height * .72),
    ];
    for (final point in points) {
      canvas.drawCircle(point, radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _StatusDotMapGlyphPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _TypePageQuickActionControl extends StatefulWidget {
  const _TypePageQuickActionControl({
    required this.semanticsLabel,
    required this.icon,
    required this.foreground,
    required this.onPressed,
    this.showProgressWhileRunning = true,
  });

  final String semanticsLabel;
  final IconData icon;
  final Color foreground;
  final Future<void> Function(Rect sourceRect) onPressed;
  final bool showProgressWhileRunning;

  @override
  State<_TypePageQuickActionControl> createState() =>
      _TypePageQuickActionControlState();
}

class _TypePageQuickActionControlState
    extends State<_TypePageQuickActionControl> {
  bool _pressed = false;
  bool _running = false;

  Future<void> _invoke() async {
    if (_running) return;
    setState(() {
      _running = true;
    });
    HapticFeedback.selectionClick();
    final renderObject = context.findRenderObject();
    final sourceRect = renderObject is RenderBox && renderObject.hasSize
        ? (() {
            final origin = renderObject.localToGlobal(Offset.zero);
            final extent = math.min(44.0, renderObject.size.shortestSide);
            final center = origin + renderObject.size.center(Offset.zero);
            return Rect.fromCenter(
              center: center,
              width: extent,
              height: extent,
            );
          })()
        : Rect.fromCenter(
            center: MediaQuery.sizeOf(context).center(Offset.zero),
            width: 44,
            height: 44,
          );
    try {
      await widget.onPressed(sourceRect);
    } finally {
      if (!mounted) return;
      setState(() {
        _running = false;
        _pressed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      enabled: !_running,
      child: AnimatedScale(
        scale: _pressed ? .95 : 1,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            radius: 24,
            containedInkWell: true,
            highlightShape: BoxShape.circle,
            onTap: _running ? null : () => unawaited(_invoke()),
            onTapDown: _running
                ? null
                : (_) {
                    setState(() {
                      _pressed = true;
                    });
                  },
            onTapUp: _running
                ? null
                : (_) {
                    setState(() {
                      _pressed = false;
                    });
                  },
            onTapCancel: _running
                ? null
                : () {
                    setState(() {
                      _pressed = false;
                    });
                  },
            child: SizedBox.expand(
              child: Center(
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  child: _running && widget.showProgressWhileRunning
                      ? SizedBox(
                          key: const ValueKey<String>('running'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: widget.foreground,
                          ),
                        )
                      : Icon(
                          widget.icon,
                          key: const ValueKey<String>('icon'),
                          size: 24,
                          color: widget.foreground,
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

