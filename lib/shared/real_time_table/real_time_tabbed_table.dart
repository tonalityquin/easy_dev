import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' show FontFeature;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart'
    show PointerCancelEvent, PointerDownEvent, PointerMoveEvent, PointerUpEvent;
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show CustomSemanticsAction;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../app/utils/status_dialog.dart';
import '../../app/utils/developer_operation_status_dialog.dart';
import '../../app/utils/operational_data_sync_workflow.dart';
import '../../design_system/common_ui/common_quick_action_surface.dart';
import '../../design_system/common_ui/common_ui_components.dart';
import '../../design_system/common_ui/common_ui_theme.dart';
import '../../features/account/applications/user_state.dart';
import '../../features/location/applications/location_state.dart';
import '../../features/location/applications/parking_parent_order_state.dart';
import '../../features/location/domain/models/grid_rect.dart';
import '../../features/location/domain/models/location_model.dart';
import '../../features/location/domain/models/parking_grid_model.dart';
import '../../features/selector/application/dev_auth.dart';
import '../../features/dev/application/area_state.dart';
import '../page/application/common/type_auto_transition_guard.dart';
import '../page/application/common/type_page_quick_action_scope.dart';
import '../page/application/common/type_view_mode_state.dart';
import '../plate/application/common/view_doc_rows_store.dart';
import '../plate/domain/models/plate_model.dart';
import '../plate/domain/repositories/plate_repository.dart';
import 'real_time_tab_controller.dart';
import 'real_time_table_body.dart';
import 'real_time_table_components.dart';
import 'real_time_table_row_vm.dart';
import 'real_time_table_spec.dart';
import 'real_time_sort_state.dart';
import 'real_time_source_rect_modal.dart';
import 'real_time_status_action_scope.dart';
import 'real_time_parent_map_thumbnail.dart';
import 'real_time_parking_request_shelf.dart';
import 'real_time_table_zone.dart';

class RealTimeViewModeAutoSpec {
  final Duration idleToStatusAfter;

  const RealTimeViewModeAutoSpec({
    this.idleToStatusAfter = const Duration(seconds: 5),
  });
}

class RealTimeTabbedTableBackController {
  Object? _owner;
  Future<bool> Function()? _handler;

  bool get attached => _handler != null;

  Future<bool> consumeBack() async {
    final handler = _handler;
    if (handler == null) return false;
    return handler();
  }

  void _attach(Object owner, Future<bool> Function() handler) {
    _owner = owner;
    _handler = handler;
  }

  void _detach(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    _handler = null;
  }
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
      ) statusBodyBuilder;

  final RealTimeViewModeAutoSpec? viewModeAuto;
  final bool useListContextSurface;
  final bool showColoredSwipeChevrons;
  final RealTimeTabbedTableBackController? backController;

  const RealTimeTabbedTable({
    super.key,
    required this.tabs,
    required this.tabBarStyle,
    required this.initialIndex,
    required this.screen,
    required this.description,
    required this.statusBodyBuilder,
    this.viewModeAuto,
    this.useListContextSurface = false,
    this.showColoredSwipeChevrons = false,
    this.backController,
  }) : assert(tabs.length > 0);

  @override
  State<RealTimeTabbedTable> createState() => _RealTimeTabbedTableState();
}

enum _ContentGestureAxis { undecided, horizontal, vertical, blocked }

class _RealTimeTabbedTableState extends State<RealTimeTabbedTable>
    with TickerProviderStateMixin {
  static const double _modeReelTravel = 44;
  static const double _modeReelDistanceThreshold = 22;
  static const double _modeReelVelocityThreshold = 320;
  static const double _contentModeAxisLockDistance = 8;
  static const double _contentModeAxisDominance = 1.15;
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
  static const String _requestTrayPauseReason = '요청 HUD 상세 트레이';
  static const String _requestDockPauseReason = '요청 HUD 상태 처리 사이드 도크';
  static const bool _statusToTableVerticalSwipeLocked = true;

  late int _currentTableIndex;
  late final AnimationController _hudPulseController;
  late final AnimationController _tableSwipeController;
  late final AnimationController _statusVisualPulseController;
  late final AnimationController _requestTrayVisibilityController;
  late final AnimationController _modeReelController;
  late final AnimationController _modeContentRevealController;

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
  String? _lastBottomLayoutSignature;

  double _modeReelDragDistance = 0;
  bool _modeReelDragActive = false;
  bool _modeReelTransitioning = false;
  bool _modeReelGuardBlocked = false;
  bool _modeReelDetentTriggered = false;
  int _modeReelPhysicalDirection = 0;
  int _modeReelDebugBucket = -1;
  TypeViewMode? _modeReelFromMode;
  String? _modeVerticalGestureSource;
  int? _contentGesturePointer;
  Offset _contentGestureAccumulatedDelta = Offset.zero;
  Duration? _contentGestureLastTimeStamp;
  double _contentGestureVelocityX = 0;
  double _contentGestureVelocityY = 0;
  double _contentGestureViewportWidth = 1;
  _ContentGestureAxis _contentGestureAxis = _ContentGestureAxis.undecided;
  bool _parentSelectorOpen = false;
  String _lastParentSelectorCloseSource = 'route';
  DateTime? _parentSelectorReopenBlockedUntil;

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
  ParkingLocationProfile _parkingLocationProfile =
      ParkingLocationProfile.loading;
  RealTimeRequestQueueType? _activeRequestTray;
  int _requestTraySwitchDirection = 0;
  bool _requestTrayAutoPauseActive = false;
  bool _requestTrayCleanupScheduled = false;
  bool _requestTrayClosing = false;
  bool _openingRequestDetail = false;
  bool _requestHudDebugDialogShowing = false;
  bool _bottomLayoutDebugDialogShowing = false;
  final List<String> _requestHudDebugLines = <String>[];
  final Map<RealTimeRequestQueueType, String> _lastRequestHudSignatures =
      <RealTimeRequestQueueType, String>{};
  String? _lastRenderSeparationSignature;
  final Map<RealTimeRequestQueueType, RealTimeTraySortOrder> _requestTraySort =
      <RealTimeRequestQueueType, RealTimeTraySortOrder>{
    RealTimeRequestQueueType.parking: RealTimeTraySortOrder.newestFirst,
    RealTimeRequestQueueType.completed: RealTimeTraySortOrder.newestFirst,
    RealTimeRequestQueueType.departure: RealTimeTraySortOrder.newestFirst,
  };

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

    _requestTrayVisibilityController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 230),
      reverseDuration: const Duration(milliseconds: 190),
      value: 0,
    );

    _modeReelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 0,
    );

    _modeContentRevealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      value: 1,
    );

    _loadGates();
    widget.backController?._attach(this, _handleBackRequest);
  }

  @override
  void didUpdateWidget(covariant RealTimeTabbedTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.backController == widget.backController) return;
    oldWidget.backController?._detach(this);
    widget.backController?._attach(this, _handleBackRequest);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _attachAutoGuardListener();
    _attachLocationStateListener();
    _syncSortContextAfterBuild();
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
    if (widget.viewModeAuto == null) {
      _idleTimer?.cancel();
      _idleTimer = null;
      return;
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

  void _prepareLocationProfileReveal(
    ParkingLocationProfile previousProfile,
    ParkingLocationProfile nextProfile,
  ) {
    if (previousProfile == nextProfile ||
        nextProfile == ParkingLocationProfile.loading ||
        nextProfile == ParkingLocationProfile.empty) {
      return;
    }
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _modeContentRevealController.stop();
    _modeContentRevealController.value = reduceMotion ? 1 : 0;
  }

  void _syncParkingCapabilityFromLocationState({required bool rebuild}) {
    final state = _locationState;
    final nextCapability =
        state?.parkingViewCapability ?? ParkingViewCapability.tableOnly;
    final nextProfile =
        state?.parkingLocationProfile ?? ParkingLocationProfile.textOnly;
    if (_parkingCapabilityInitialized &&
        _parkingViewCapability == nextCapability &&
        _parkingLocationProfile == nextProfile) {
      return;
    }
    final previousCapability = _parkingViewCapability;
    final previousProfile = _parkingLocationProfile;
    _prepareLocationProfileReveal(previousProfile, nextProfile);
    if (rebuild && mounted) {
      setState(() {
        _parkingViewCapability = nextCapability;
        _parkingLocationProfile = nextProfile;
        _parkingCapabilityInitialized = true;
      });
    } else {
      _parkingViewCapability = nextCapability;
      _parkingLocationProfile = nextProfile;
      _parkingCapabilityInitialized = true;
    }
    _scheduleParkingCapabilitySync(
      previousCapability: previousCapability,
      previousProfile: previousProfile,
    );
  }

  TypeViewMode? _targetModeForLocationProfile(
    ParkingLocationProfile profile,
  ) {
    switch (profile) {
      case ParkingLocationProfile.spatialOnly:
        return TypeViewMode.status;
      case ParkingLocationProfile.textOnly:
      case ParkingLocationProfile.mixed:
      case ParkingLocationProfile.invalid:
        return TypeViewMode.table;
      case ParkingLocationProfile.loading:
      case ParkingLocationProfile.empty:
        return null;
    }
  }

  String _locationProfileResolutionReason(
    ParkingLocationProfile profile,
  ) {
    return switch (profile) {
      ParkingLocationProfile.loading => 'location_snapshot_loading',
      ParkingLocationProfile.empty => 'location_snapshot_empty',
      ParkingLocationProfile.textOnly => 'text_locations_table_only',
      ParkingLocationProfile.spatialOnly => 'spatial_locations_status_only',
      ParkingLocationProfile.mixed => 'mixed_location_types_table_fallback',
      ParkingLocationProfile.invalid => 'invalid_location_types_table_fallback',
    };
  }

  void _scheduleParkingCapabilitySync({
    required ParkingViewCapability previousCapability,
    required ParkingLocationProfile previousProfile,
  }) {
    if (_parkingCapabilitySyncScheduled) return;
    _parkingCapabilitySyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _parkingCapabilitySyncScheduled = false;
      if (!mounted) return;
      final profile = _parkingLocationProfile;
      final statusEnabled = profile == ParkingLocationProfile.spatialOnly;
      final targetMode = _targetModeForLocationProfile(profile);
      final vm = _viewMode;
      final beforeMode = vm?.mode;
      vm?.setStatusEnabled(statusEnabled);
      if (targetMode != null) {
        vm?.setMode(targetMode);
      }
      var locationCount = 0;
      var hierarchicalCount = 0;
      var singleCount = 0;
      var spatialCount = 0;
      var textCount = 0;
      var unknownCount = 0;
      try {
        final state = context.read<LocationState>();
        locationCount = state.locations.length;
        hierarchicalCount = state.hierarchicalLocationCount;
        singleCount = state.singleLocationCount;
        spatialCount = state.spatialLocationCount;
        textCount = state.textLocationCount;
        unknownCount = state.unknownLocationCount;
      } catch (_) {}
      final resolvedMode = targetMode?.name ??
          (profile == ParkingLocationProfile.empty ? 'empty' : 'pending');
      final reason = _locationProfileResolutionReason(profile);
      final details = <String, Object?>{
        'area': _readCurrentArea(),
        'previousCapability': previousCapability.name,
        'capability': _parkingViewCapability.name,
        'previousProfile': previousProfile.name,
        'profile': profile.name,
        'locationCount': locationCount,
        'hierarchicalCount': hierarchicalCount,
        'singleCount': singleCount,
        'spatialCount': spatialCount,
        'textCount': textCount,
        'unknownCount': unknownCount,
        'statusEnabled': statusEnabled,
        'resolvedMode': resolvedMode,
        'reason': reason,
        'mixedFallback': profile == ParkingLocationProfile.mixed,
        'invalidFallback': profile == ParkingLocationProfile.invalid,
        'statusCoverageComplete': profile == ParkingLocationProfile.spatialOnly,
        'decisionSource': 'location_state_snapshot',
        'firebaseAdditionalRead': 0,
      };
      _debugLog('location_presentation_resolved', details);
      _emitRequestHudDebug('location_presentation_resolved', details);
      if (targetMode != null && beforeMode == targetMode &&
          previousProfile != profile) {
        _triggerModeContentReveal();
      }
      _syncIdleWithMode();
      if (mounted) setState(() {});
    });
  }

  bool get _statusViewSupported =>
      _parkingLocationProfile == ParkingLocationProfile.spatialOnly &&
      _parkingViewCapability == ParkingViewCapability.statusOnly &&
      (_viewMode?.statusEnabled ?? true);

  bool get _statusModeActive =>
      _statusViewSupported && _viewMode?.mode == TypeViewMode.status;

  bool get _locationPresentationReady =>
      _parkingLocationProfile != ParkingLocationProfile.loading &&
      _parkingLocationProfile != ParkingLocationProfile.empty;

  bool get _renderStatusContent =>
      _locationPresentationReady &&
      _parkingLocationProfile == ParkingLocationProfile.spatialOnly &&
      _statusModeActive;

  bool get _renderTableContent =>
      _locationPresentationReady &&
      _parkingLocationProfile != ParkingLocationProfile.spatialOnly &&
      _viewMode?.mode == TypeViewMode.table;

  String get _renderedContentMode {
    if (_renderStatusContent) return 'status';
    if (_renderTableContent) return 'table';
    if (_parkingLocationProfile == ParkingLocationProfile.empty) return 'empty';
    return 'pending';
  }

  Color _shellBackgroundColor(
    ColorScheme cs,
    CommonUiTokens tokens,
  ) {
    return _parkingLocationProfile == ParkingLocationProfile.spatialOnly
        ? tokens.canvas
        : cs.surface;
  }

  String get _shellBackgroundRole =>
      _parkingLocationProfile == ParkingLocationProfile.spatialOnly
          ? 'common_ui_canvas'
          : 'theme_surface';

  ({
    int locationCount,
    int spatialCount,
    int textCount,
    int unknownCount,
  }) _locationPresentationCounts() {
    final state = _locationState;
    if (state == null) {
      return (
        locationCount: 0,
        spatialCount: 0,
        textCount: 0,
        unknownCount: 0,
      );
    }
    return (
      locationCount: state.locations.length,
      spatialCount: state.spatialLocationCount,
      textCount: state.textLocationCount,
      unknownCount: state.unknownLocationCount,
    );
  }

  double _systemBottomSafeInset(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    if (media == null) return 8;
    return math.max(
      math.max(
        math.max(media.viewPadding.bottom, media.padding.bottom),
        media.systemGestureInsets.bottom,
      ),
      8.0,
    );
  }

  double get _modeControlContentExtent {
    return switch (_parkingViewCapability) {
      ParkingViewCapability.loading => 79,
      ParkingViewCapability.empty => 87,
      ParkingViewCapability.tableOnly => 0,
      ParkingViewCapability.statusOnly => 0,
    };
  }

  _BottomLayoutMetrics _bottomLayoutMetrics(BuildContext context) {
    final hasQuickActions = TypePageQuickActionScope.maybeOf(context) != null;
    return _BottomLayoutMetrics(
      systemBottomInset: _systemBottomSafeInset(context),
      quickActionExtent:
          hasQuickActions ? CommonQuickActionSurface.height : 0,
      modeControlExtent: _modeControlContentExtent,
    );
  }

  void _scheduleRenderSeparationTrace() {
    final tableMounted = _renderTableContent;
    final statusMounted = _renderStatusContent;
    final contentOverlap = tableMounted && statusMounted;
    final renderedMode = _renderedContentMode;
    final signature = <Object?>[
      _viewMode?.mode.name ?? 'unknown',
      renderedMode,
      tableMounted,
      statusMounted,
      contentOverlap,
      _parkingViewCapability.name,
      _parkingLocationProfile.name,
    ].join('|');
    if (_lastRenderSeparationSignature == signature) return;
    _lastRenderSeparationSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final counts = _locationPresentationCounts();
      final details = <String, Object?>{
        'screen': widget.screen,
        'viewMode': _viewMode?.mode.name ?? 'unknown',
        'renderedMode': renderedMode,
        'tableMounted': tableMounted,
        'statusMounted': statusMounted,
        'contentOverlap': contentOverlap,
        'previousChildRetention': false,
        'contentTransition': 'atomic_swap+incoming_reveal',
        'statusBodyBuilderRegistered': true,
        'capability': _parkingViewCapability.name,
        'locationProfile': _parkingLocationProfile.name,
        'profileDecisionReason':
            _locationProfileResolutionReason(_parkingLocationProfile),
        'locationCount': counts.locationCount,
        'spatialCount': counts.spatialCount,
        'textCount': counts.textCount,
        'unknownCount': counts.unknownCount,
      };
      _debugLog('mode_content_render_resolved', details);
      _emitRequestHudDebug('mode_content_render_resolved', details);
    });
  }

  void _scheduleBottomLayoutTrace(_BottomLayoutMetrics metrics) {
    final signature = [
      _viewMode?.mode.name ?? 'unknown',
      _parkingViewCapability.name,
      _parkingLocationProfile.name,
      metrics.systemBottomInset.toStringAsFixed(2),
      metrics.quickActionExtent.toStringAsFixed(2),
      metrics.modeControlExtent.toStringAsFixed(2),
      metrics.bottomActionStackExtent.toStringAsFixed(2),
    ].join('|');
    if (_lastBottomLayoutSignature == signature) return;
    _lastBottomLayoutSignature = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final counts = _locationPresentationCounts();
      final details = <String, Object?>{
        'screen': widget.screen,
        'mode': _viewMode?.mode.name ?? 'unknown',
        'capability': _parkingViewCapability.name,
        'locationProfile': _parkingLocationProfile.name,
        'resolvedMode': _renderedContentMode,
        'locationCount': counts.locationCount,
        'spatialCount': counts.spatialCount,
        'textCount': counts.textCount,
        'unknownCount': counts.unknownCount,
        'systemBottomInset': metrics.systemBottomInset.toStringAsFixed(2),
        'quickActionHeight': metrics.quickActionExtent.toStringAsFixed(2),
        'modeControlExtent': metrics.modeControlExtent.toStringAsFixed(2),
        'bottomActionStackExtent':
            metrics.bottomActionStackExtent.toStringAsFixed(2),
        'hudBottom': metrics.hudBottom.toStringAsFixed(2),
        'trayBottom': metrics.trayBottom.toStringAsFixed(2),
        'reelSurfaceVisible': false,
        'tableOnlySurfaceVisible': false,
      };
      _debugLog('bottom_layout_resolved', details);
      _emitRequestHudDebug('bottom_layout_resolved', details);
    });
  }

  String _bottomLayoutDebugPrintCode(_BottomLayoutMetrics metrics) {
    final counts = _locationPresentationCounts();
    final line = StringBuffer()
      ..write('[RealTimeBottomLayout] ')
      ..write(DateTime.now().toIso8601String())
      ..write(' mode=')
      ..write(_viewMode?.mode.name ?? 'unknown')
      ..write(' capability=')
      ..write(_parkingViewCapability.name)
      ..write(' systemBottomInset=')
      ..write(metrics.systemBottomInset.toStringAsFixed(2))
      ..write(' quickActionHeight=')
      ..write(metrics.quickActionExtent.toStringAsFixed(2))
      ..write(' modeControlExtent=')
      ..write(metrics.modeControlExtent.toStringAsFixed(2))
      ..write(' bottomActionStackExtent=')
      ..write(metrics.bottomActionStackExtent.toStringAsFixed(2))
      ..write(' hudBottom=')
      ..write(metrics.hudBottom.toStringAsFixed(2))
      ..write(' trayBottom=')
      ..write(metrics.trayBottom.toStringAsFixed(2))
      ..write(' reelSurfaceVisible=false')
      ..write(' tableOnlySurfaceVisible=false')
      ..write(' locationProfile=')
      ..write(_parkingLocationProfile.name)
      ..write(' profileDecisionReason=')
      ..write(_locationProfileResolutionReason(_parkingLocationProfile))
      ..write(' locationCount=')
      ..write(counts.locationCount)
      ..write(' spatialCount=')
      ..write(counts.spatialCount)
      ..write(' textCount=')
      ..write(counts.textCount)
      ..write(' unknownCount=')
      ..write(counts.unknownCount)
      ..write(' renderedMode=')
      ..write(_renderedContentMode)
      ..write(' tableMounted=')
      ..write(_renderTableContent)
      ..write(' statusMounted=')
      ..write(_renderStatusContent)
      ..write(' contentOverlap=false')
      ..write(' previousChildRetention=false')
      ..write(' contentTransition=atomic_swap+incoming_reveal')
      ..write(' requestTrayActive=')
      ..write(_activeRequestTray?.sourceKey ?? 'none')
      ..write(' requestTrayClosing=')
      ..write(_requestTrayClosing)
      ..write(' backControllerAttached=')
      ..write(widget.backController?.attached ?? false)
      ..write(' backPriority=request_tray_then_page');
    return 'debugPrint(${jsonEncode(line.toString())});';
  }

  Future<void> _showBottomLayoutDebugDialog() async {
    if (!mounted || _bottomLayoutDebugDialogShowing) return;
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !mounted || _bottomLayoutDebugDialogShowing) return;
    final metrics = _bottomLayoutMetrics(context);
    final counts = _locationPresentationCounts();
    final line = _bottomLayoutDebugPrintCode(metrics);
    final description = <String>[
      'mode=${_viewMode?.mode.name ?? 'unknown'}',
      'capability=${_parkingViewCapability.name}',
      'locationProfile=${_parkingLocationProfile.name}',
      'profileDecisionReason=${_locationProfileResolutionReason(_parkingLocationProfile)}',
      'locationCount=${counts.locationCount}',
      'spatialCount=${counts.spatialCount}',
      'textCount=${counts.textCount}',
      'unknownCount=${counts.unknownCount}',
      'resolvedMode=$_renderedContentMode',
      'systemBottomInset=${metrics.systemBottomInset.toStringAsFixed(2)}',
      'quickActionHeight=${metrics.quickActionExtent.toStringAsFixed(2)}',
      'modeControlExtent=${metrics.modeControlExtent.toStringAsFixed(2)}',
      'bottomActionStackExtent=${metrics.bottomActionStackExtent.toStringAsFixed(2)}',
      'hudBottom=${metrics.hudBottom.toStringAsFixed(2)}',
      'trayBottom=${metrics.trayBottom.toStringAsFixed(2)}',
      'reelSurfaceVisible=false',
      'tableOnlySurfaceVisible=false',
      'renderedMode=$_renderedContentMode',
      'tableMounted=$_renderTableContent',
      'statusMounted=$_renderStatusContent',
      'contentOverlap=false',
      'previousChildRetention=false',
      'contentTransition=atomic_swap+incoming_reveal',
      'requestTrayActive=${_activeRequestTray?.sourceKey ?? 'none'}',
      'requestTrayClosing=$_requestTrayClosing',
      'backControllerAttached=${widget.backController?.attached ?? false}',
      'backPriority=request_tray_then_page',
    ].join('\n');
    _emitRequestHudDebug(
      'bottom_layout_status_dialog_opened',
      <String, Object?>{
        'screen': widget.screen,
        'mode': _viewMode?.mode.name ?? 'unknown',
        'locationProfile': _parkingLocationProfile.name,
        'profileDecisionReason':
            _locationProfileResolutionReason(_parkingLocationProfile),
        'resolvedMode': _renderedContentMode,
        'locationCount': counts.locationCount,
        'spatialCount': counts.spatialCount,
        'textCount': counts.textCount,
        'unknownCount': counts.unknownCount,
        'systemBottomInset': metrics.systemBottomInset.toStringAsFixed(2),
        'bottomActionStackExtent':
            metrics.bottomActionStackExtent.toStringAsFixed(2),
        'hudBottom': metrics.hudBottom.toStringAsFixed(2),
        'trayBottom': metrics.trayBottom.toStringAsFixed(2),
        'reelSurfaceVisible': false,
        'tableOnlySurfaceVisible': false,
        'renderedMode': _renderedContentMode,
        'tableMounted': _renderTableContent,
        'statusMounted': _renderStatusContent,
        'contentOverlap': false,
        'previousChildRetention': false,
        'contentTransition': 'atomic_swap+incoming_reveal',
        'requestTrayActive': _activeRequestTray?.sourceKey ?? 'none',
        'requestTrayClosing': _requestTrayClosing,
        'backControllerAttached': widget.backController?.attached ?? false,
        'backPriority': 'request_tray_then_page',
      },
    );
    _bottomLayoutDebugDialogShowing = true;
    try {
      await StatusDialog.showSuccess(
        context,
        title: '하단 레이아웃 및 모드 렌더링 상태',
        description: description,
        copyText: line,
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: Duration.zero,
        useCommonUi: true,
        awaitManualClose: true,
      );
    } finally {
      _bottomLayoutDebugDialogShowing = false;
    }
  }

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

  void _triggerModeContentReveal() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _modeContentRevealController.stop();
    if (reduceMotion) {
      _modeContentRevealController.value = 1;
      return;
    }
    _modeContentRevealController.value = 0;
    unawaited(
      _modeContentRevealController.animateTo(
        1,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  Widget _buildModeContentReveal(Widget child) {
    return AnimatedBuilder(
      animation: _modeContentRevealController,
      child: child,
      builder: (context, child) {
        final progress = Curves.easeOutCubic.transform(
          _modeContentRevealController.value.clamp(0.0, 1.0).toDouble(),
        );
        return Opacity(
          opacity: .16 + (.84 * progress),
          child: Transform.translate(
            offset: Offset(0, 8 * (1 - progress)),
            child: Transform.scale(
              scale: .992 + (.008 * progress),
              alignment: Alignment.center,
              child: child,
            ),
          ),
        );
      },
    );
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
      _modeVerticalGestureSource = null;
      _resetContentGestureTracking();
      _modeReelController.stop();
      _modeReelController.value = 0;
      _endModeReelGuard();
    }
    setState(() {});
    _triggerModeContentReveal();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    _debugLog('view_mode_changed', <String, Object?>{
      'mode': _viewMode?.mode.name,
      'table': widget.tabs[_currentTableIndex].id,
      'shellBackground': _shellBackgroundRole,
      'statusContentBackground': 'common_ui_canvas',
      'quickActionBackground': _shellBackgroundRole,
      'backgroundUnified': _statusModeActive,
      'backgroundMotion': reduceMotion ? 'disabled' : '230ms_easeOutCubic',
      'locationProfile': _parkingLocationProfile.name,
      'profileDecisionReason':
          _locationProfileResolutionReason(_parkingLocationProfile),
      'renderedMode': _renderedContentMode,
      'tableMounted': _renderTableContent,
      'statusMounted': _renderStatusContent,
      'contentOverlap': false,
      'previousChildRetention': false,
      'contentTransition': reduceMotion
          ? 'atomic_swap'
          : 'atomic_swap+incoming_reveal_220ms',
    });
    _emitRequestHudDebug(
      'status_shell_background_changed',
      <String, Object?>{
        'screen': widget.screen,
        'mode': _viewMode?.mode.name ?? 'unknown',
        'locationProfile': _parkingLocationProfile.name,
        'profileDecisionReason':
            _locationProfileResolutionReason(_parkingLocationProfile),
        'shellBackground': _shellBackgroundRole,
        'statusContentBackground': 'common_ui_canvas',
        'quickActionBackground': _shellBackgroundRole,
        'hudBackground': _shellBackgroundRole,
        'backgroundUnified': _statusModeActive,
        'durationMs': reduceMotion ? 0 : 230,
        'curve': 'easeOutCubic',
      },
    );
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
    guard.setCountdownEnabled(false, reason: '지역 주차구역 유형 고정 모드');
    _idleTimer?.cancel();
    _idleTimer = null;
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

  Widget _transitionMaskSurface(
    BuildContext context, {
    required String message,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return AbsorbPointer(
      absorbing: true,
      child: Container(
        color: _shellBackgroundColor(cs, tokens),
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
    widget.backController?._detach(this);
    if (_requestTrayAutoPauseActive) {
      _requestTrayAutoPauseActive = false;
      _autoGuard?.endBlock(_requestTrayPauseReason);
    }
    if (_openingRequestDetail) {
      _openingRequestDetail = false;
      _autoGuard?.endBlock(_requestDockPauseReason);
    }
    _endModeReelGuard();
    _endTableSwipeGuard();
    _detachViewModeListener();
    _detachAutoGuardListener();
    _detachLocationStateListener();
    _modeReelController.dispose();
    _modeContentRevealController.dispose();
    _requestTrayVisibilityController.dispose();
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
    if (!_renderTableContent) return false;
    if (_viewMode?.mode != TypeViewMode.table) return false;
    if (_transitionMaskOn ||
        _tableTransitioning ||
        _modeReelDragActive ||
        _modeReelTransitioning ||
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

  void _beginTableHorizontalSwipe(
    double viewportWidth, {
    required String inputSource,
  }) {
    if (!_canSwipeTables()) {
      _debugLog('table_swipe_ignored', <String, Object?>{
        'inputSource': inputSource,
        'reason': 'table_swipe_unavailable',
        'viewMode': _viewMode?.mode.name ?? 'unknown',
      });
      return;
    }
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
      'inputSource': inputSource,
      'viewportWidth': _horizontalSwipeViewportWidth.toStringAsFixed(1),
      'axisLockDistance': _contentModeAxisLockDistance,
      'axisDominance': _contentModeAxisDominance,
      'visualActivationDistance': _tableSwipeVisualActivationDistance,
      'commitDistanceThreshold': _tableSwipeCommitDistanceThreshold,
      'velocityThreshold': _tableSwipeVelocityThreshold,
      'pageStructure': 'stable_stack',
      'currentPageState': 'preserved',
      'rowMountReveal': 'disabled',
      'horizontalOnly': true,
    });
  }

  void _updateTableHorizontalSwipe(double deltaX) {
    if (!_horizontalDragActive) return;
    _horizontalDragDistance += deltaX;
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

  void _cancelTableHorizontalSwipe({required String reason}) {
    if (!_horizontalDragActive) return;
    final distance = _horizontalDragDistance;
    final physicalDirection = _swipePhysicalDirection;
    _horizontalDragActive = false;
    unawaited(
      _cancelInteractiveTableSwipe(
        reason: reason,
        distance: distance,
        velocity: 0,
        physicalDirection: physicalDirection,
      ),
    );
  }

  void _endTableHorizontalSwipe(
    double velocity, {
    required String source,
  }) {
    if (!_horizontalDragActive) return;
    final distance = _horizontalDragDistance;
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
        source: source,
      ),
    );
  }

  void _onTableHorizontalDragStart(
    DragStartDetails _,
    double viewportWidth,
  ) {
    _beginTableHorizontalSwipe(
      viewportWidth,
      inputSource: 'gesture_detector',
    );
  }

  void _onTableHorizontalDragUpdate(DragUpdateDetails details) {
    _updateTableHorizontalSwipe(details.delta.dx);
  }

  void _onTableHorizontalDragCancel() {
    _cancelTableHorizontalSwipe(reason: 'gesture_cancelled');
  }

  void _onTableHorizontalDragEnd(DragEndDetails details) {
    _endTableHorizontalSwipe(
      details.primaryVelocity ?? 0,
      source: 'gesture',
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
      (source == 'gesture' || source == 'content_axis_lock') ? .72 : .88,
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
      'axisPolicy': source == 'content_axis_lock'
          ? 'pointer_axis_lock_single_owner'
          : 'gesture_detector_horizontal',
      'axisLockDistance': source == 'content_axis_lock'
          ? _contentModeAxisLockDistance
          : 'not_applicable',
      'axisDominance': source == 'content_axis_lock'
          ? _contentModeAxisDominance
          : 'not_applicable',
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
            'axisPolicy=${source == 'content_axis_lock' ? 'pointer_axis_lock_single_owner' : 'gesture_detector_horizontal'} axisLockDistance=${source == 'content_axis_lock' ? _contentModeAxisLockDistance : 'not_applicable'} axisDominance=${source == 'content_axis_lock' ? _contentModeAxisDominance : 'not_applicable'}',
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
            'hudPointer=request_counts_only hudSemantics=request_counts_only',
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

  Map<CustomSemanticsAction, VoidCallback>? _contentSemanticsActions() {
    final actions = <CustomSemanticsAction, VoidCallback>{};
    final tableActions = _tableSemanticsActions();
    if (tableActions != null) {
      actions.addAll(tableActions);
    }
    final modeActions = _modeReelSemanticsActions();
    if (modeActions != null) {
      actions.addAll(modeActions);
    }
    return actions.isEmpty ? null : actions;
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
    final profileCounts = _locationPresentationCounts();
    trace.log('parkingViewCapability=${_parkingViewCapability.name}');
    trace.log('parkingLocationProfile=${_parkingLocationProfile.name}');
    trace.log('profileDecisionReason=${_locationProfileResolutionReason(_parkingLocationProfile)}');
    trace.log('spatialCount=${profileCounts.spatialCount} textCount=${profileCounts.textCount} unknownCount=${profileCounts.unknownCount}');
    trace.log('statusEnabled=${_viewMode?.statusEnabled ?? false}');
    trace.log('modeControl=${_parkingViewCapability == ParkingViewCapability.statusOnly ? 'reel_hidden+status_profile_locked' : _parkingViewCapability == ParkingViewCapability.tableOnly ? 'reel_hidden+table_profile_locked' : _parkingViewCapability == ParkingViewCapability.empty ? 'download_surface' : 'loading_surface'}');
    await trace.succeed('TypePage 상태 확인을 완료했습니다.');
    if (trace.developerMode && mounted) {
      await trace.showStatusDialog(context);
    }
  }

  Future<void> _showParentOrderStatus({
    required bool success,
    required List<String> lines,
  }) async {
    if (!mounted) return;
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '부모 주차 구역 순서',
      initialMessage: lines.isEmpty ? '부모 주차 구역 순서를 확인합니다.' : lines.first,
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
      showDialogImmediately: false,
    );
    for (final line in lines.skip(1)) {
      trace.log(line);
    }
    if (success) {
      await trace.succeed('부모 주차 구역 순서 저장을 완료했습니다.');
    } else {
      await trace.fail('부모 주차 구역 순서 저장에 실패했습니다.');
    }
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
    guard.beginBlock('보기 모드 세로 전환');
    _modeReelGuardBlocked = true;
  }

  void _endModeReelGuard() {
    if (!_modeReelGuardBlocked) return;
    _modeReelGuardBlocked = false;
    _autoGuard?.endBlock('보기 모드 세로 전환');
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
    _debugLog('mode_vertical_detent', <String, Object?>{
      'source': source,
      'physicalDirection': _modeReelPhysicalDirection == 0
          ? 'none'
          : _modeReelDirectionLabel(_modeReelPhysicalDirection),
      'progress': _modeReelController.value.toStringAsFixed(3),
      'distanceThreshold': _modeReelDistanceThreshold,
    });
  }

  String _modeVerticalBlockedReason() {
    if (!_statusViewSupported) return 'status_not_supported';
    if (_viewMode == null) return 'view_mode_unavailable';
    if (_transitionMaskOn) return 'transition_mask_active';
    if (_modeReelDragActive) return 'vertical_mode_drag_active';
    if (_modeReelTransitioning) return 'vertical_mode_transitioning';
    if (_parentSelectorOpen) return 'parent_selector_open';
    if (_horizontalDragActive) return 'horizontal_table_swipe_active';
    if (_tableTransitioning) return 'table_transitioning';
    if (_tableSwipeController.value > 0) return 'table_swipe_progress_active';
    return 'other_transition_active';
  }

  bool _beginModeVerticalGesture({required String source}) {
    if (!_canUseModeReel()) {
      _debugLog('mode_vertical_ignored', <String, Object?>{
        'source': source,
        'reason': _modeVerticalBlockedReason(),
        'mode': _viewMode?.mode.name,
        'capability': _parkingViewCapability.name,
        'tableSwipeProgress': _tableSwipeController.value.toStringAsFixed(3),
      });
      return false;
    }
    final vm = _viewMode;
    if (vm == null) return false;
    if (_locationPresentationReady) {
      _debugLog('mode_vertical_ignored', <String, Object?>{
        'source': source,
        'reason': 'location_profile_mode_locked',
        'profile': _parkingLocationProfile.name,
        'resolvedMode': _targetModeForLocationProfile(
          _parkingLocationProfile,
        )?.name,
        'transitionLogic': 'preserved',
      });
      return false;
    }
    if (_statusToTableVerticalSwipeLocked &&
        source == 'content_vertical' &&
        vm.mode == TypeViewMode.status) {
      _debugLog('mode_vertical_ignored', <String, Object?>{
        'source': source,
        'reason': 'status_to_table_swipe_locked',
        'from': vm.mode.name,
        'to': TypeViewMode.table.name,
        'transitionLogic': 'preserved',
      });
      return false;
    }
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
      _modeVerticalGestureSource = source;
    });
    _debugLog('mode_vertical_drag_start', <String, Object?>{
      'source': source,
      'from': vm.mode.name,
      'to': _oppositeViewMode(vm.mode).name,
      'control': source == 'content_vertical'
          ? 'content_vertical_surface+linked_reel'
          : 'frameless_bidirectional_icon_reel',
      'visualText': 'none',
      'distanceThreshold': _modeReelDistanceThreshold,
      'velocityThreshold': _modeReelVelocityThreshold,
      'axisPolicy': 'pointer_axis_lock_single_owner',
    });
    return true;
  }

  void _updateModeVerticalGesture({
    required String source,
    required double deltaDy,
  }) {
    if (!_modeReelDragActive ||
        _modeReelTransitioning ||
        _modeVerticalGestureSource != source) {
      return;
    }
    _modeReelDragDistance += deltaDy;
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
    if (progress >= _modeReelDistanceThreshold / _modeReelTravel) {
      _triggerModeReelDetent(source: source);
    } else if (progress < .38) {
      _modeReelDetentTriggered = false;
    }
    final bucket = (progress * 4).floor().clamp(0, 3).toInt();
    if (bucket != _modeReelDebugBucket && bucket > 0) {
      _modeReelDebugBucket = bucket;
      _debugLog('mode_vertical_drag_update', <String, Object?>{
        'source': source,
        'physicalDirection': physicalDirection == 0
            ? 'none'
            : _modeReelDirectionLabel(physicalDirection),
        'distance': _modeReelDragDistance.toStringAsFixed(1),
        'progress': progress.toStringAsFixed(3),
        'bucket': bucket,
      });
    }
  }

  void _endModeVerticalGesture({
    required String source,
    required double velocity,
  }) {
    if (!_modeReelDragActive ||
        _modeReelTransitioning ||
        _modeVerticalGestureSource != source) {
      return;
    }
    final distance = _modeReelDragDistance;
    final distanceAccepted = distance.abs() >= _modeReelDistanceThreshold;
    final velocityAccepted = velocity.abs() >= _modeReelVelocityThreshold;
    if (!distanceAccepted && !velocityAccepted) {
      _modeReelDragActive = false;
      unawaited(
        _cancelModeReelTransition(
          reason: 'below_threshold',
          distance: distance,
          velocity: velocity,
          source: source,
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
        source: source,
      ),
    );
  }

  void _cancelModeVerticalGesture({
    required String source,
    required String reason,
  }) {
    if (!_modeReelDragActive ||
        _modeReelTransitioning ||
        _modeVerticalGestureSource != source) {
      return;
    }
    final distance = _modeReelDragDistance;
    _modeReelDragActive = false;
    unawaited(
      _cancelModeReelTransition(
        reason: reason,
        distance: distance,
        velocity: 0,
        source: source,
      ),
    );
  }

  void _resetContentGestureTracking() {
    _contentGesturePointer = null;
    _contentGestureAccumulatedDelta = Offset.zero;
    _contentGestureLastTimeStamp = null;
    _contentGestureVelocityX = 0;
    _contentGestureVelocityY = 0;
    _contentGestureViewportWidth = 1;
    _contentGestureAxis = _ContentGestureAxis.undecided;
  }

  void _onContentGesturePointerDown(
    PointerDownEvent event,
    double viewportWidth,
  ) {
    if (_contentGesturePointer != null) return;
    _contentGesturePointer = event.pointer;
    _contentGestureAccumulatedDelta = Offset.zero;
    _contentGestureLastTimeStamp = event.timeStamp;
    _contentGestureVelocityX = 0;
    _contentGestureVelocityY = 0;
    _contentGestureViewportWidth = viewportWidth <= 0 ? 1 : viewportWidth;
    _contentGestureAxis = _ContentGestureAxis.undecided;
  }

  void _updateContentGestureVelocity(PointerMoveEvent event) {
    final previousTimeStamp = _contentGestureLastTimeStamp;
    _contentGestureLastTimeStamp = event.timeStamp;
    if (previousTimeStamp == null) return;
    final elapsed = event.timeStamp - previousTimeStamp;
    final micros = elapsed.inMicroseconds;
    if (micros <= 0) return;
    final instantaneousX = event.delta.dx * 1000000 / micros;
    final instantaneousY = event.delta.dy * 1000000 / micros;
    _contentGestureVelocityX = _contentGestureVelocityX == 0
        ? instantaneousX
        : (_contentGestureVelocityX * .65) + (instantaneousX * .35);
    _contentGestureVelocityY = _contentGestureVelocityY == 0
        ? instantaneousY
        : (_contentGestureVelocityY * .65) + (instantaneousY * .35);
  }

  void _onContentGesturePointerMove(PointerMoveEvent event) {
    if (_contentGesturePointer != event.pointer) return;
    _contentGestureAccumulatedDelta += event.delta;
    _updateContentGestureVelocity(event);

    if (_contentGestureAxis == _ContentGestureAxis.blocked) return;

    if (_contentGestureAxis == _ContentGestureAxis.undecided) {
      if (_tableTransitioning ||
          _modeReelTransitioning ||
          _transitionMaskOn ||
            _parentSelectorOpen ||
          _tableSwipeController.value > 0) {
        _contentGestureAxis = _ContentGestureAxis.blocked;
        _debugLog('content_axis_ignored', <String, Object?>{
          'reason': _tableTransitioning
              ? 'table_transitioning'
              : _modeReelTransitioning
                  ? 'vertical_mode_transitioning'
                  : _transitionMaskOn
                      ? 'transition_mask_active'
                      : _parentSelectorOpen
                              ? 'parent_selector_open'
                              : 'table_swipe_progress_active',
        });
        return;
      }

      final dx = _contentGestureAccumulatedDelta.dx.abs();
      final dy = _contentGestureAccumulatedDelta.dy.abs();
      if (math.max(dx, dy) < _contentModeAxisLockDistance) return;

      if (dx > dy * _contentModeAxisDominance) {
        _contentGestureAxis = _ContentGestureAxis.horizontal;
        final tableSwipeAvailable = _canSwipeTables();
        _debugLog('content_axis_locked', <String, Object?>{
          'axis': 'horizontal',
          'dx': dx.toStringAsFixed(1),
          'dy': dy.toStringAsFixed(1),
          'lockDistance': _contentModeAxisLockDistance,
          'dominance': _contentModeAxisDominance,
          'tableSwipeAvailable': tableSwipeAvailable,
          'ownership': tableSwipeAvailable
              ? 'table_horizontal_swipe'
              : 'child_horizontal_or_noop',
        });
        if (tableSwipeAvailable) {
          _beginTableHorizontalSwipe(
            _contentGestureViewportWidth,
            inputSource: 'content_axis_lock',
          );
          if (_horizontalDragActive) {
            _updateTableHorizontalSwipe(
              _contentGestureAccumulatedDelta.dx,
            );
          }
        }
        return;
      }

      if (dy > dx * _contentModeAxisDominance) {
        _contentGestureAxis = _ContentGestureAxis.vertical;
        final started = _beginModeVerticalGesture(
          source: 'content_vertical',
        );
        _debugLog('content_axis_locked', <String, Object?>{
          'axis': 'vertical',
          'dx': dx.toStringAsFixed(1),
          'dy': dy.toStringAsFixed(1),
          'lockDistance': _contentModeAxisLockDistance,
          'dominance': _contentModeAxisDominance,
          'modeSwitchStarted': started,
          'ownership': started ? 'mode_vertical_switch' : 'vertical_noop',
        });
        if (started) {
          _updateModeVerticalGesture(
            source: 'content_vertical',
            deltaDy: _contentGestureAccumulatedDelta.dy,
          );
        }
        return;
      }

      return;
    }

    if (_contentGestureAxis == _ContentGestureAxis.horizontal) {
      _updateTableHorizontalSwipe(event.delta.dx);
      return;
    }

    if (_contentGestureAxis == _ContentGestureAxis.vertical) {
      _updateModeVerticalGesture(
        source: 'content_vertical',
        deltaDy: event.delta.dy,
      );
    }
  }

  void _onContentGesturePointerUp(PointerUpEvent event) {
    if (_contentGesturePointer != event.pointer) return;
    final axis = _contentGestureAxis;
    final velocityX = _contentGestureVelocityX;
    final velocityY = _contentGestureVelocityY;
    if (axis == _ContentGestureAxis.horizontal) {
      _endTableHorizontalSwipe(
        velocityX,
        source: 'content_axis_lock',
      );
    } else if (axis == _ContentGestureAxis.vertical) {
      _endModeVerticalGesture(
        source: 'content_vertical',
        velocity: velocityY,
      );
    }
    if (axis != _ContentGestureAxis.undecided &&
        axis != _ContentGestureAxis.blocked) {
      _debugLog('content_axis_session_end', <String, Object?>{
        'axis': axis.name,
        'velocityX': velocityX.toStringAsFixed(1),
        'velocityY': velocityY.toStringAsFixed(1),
      });
    }
    _resetContentGestureTracking();
  }

  void _onContentGesturePointerCancel(PointerCancelEvent event) {
    if (_contentGesturePointer != event.pointer) return;
    final axis = _contentGestureAxis;
    if (axis == _ContentGestureAxis.horizontal) {
      _cancelTableHorizontalSwipe(reason: 'pointer_cancelled');
    } else if (axis == _ContentGestureAxis.vertical) {
      _cancelModeVerticalGesture(
        source: 'content_vertical',
        reason: 'pointer_cancelled',
      );
    }
    if (axis != _ContentGestureAxis.undecided &&
        axis != _ContentGestureAxis.blocked) {
      _debugLog('content_axis_session_cancel', <String, Object?>{
        'axis': axis.name,
      });
    }
    _resetContentGestureTracking();
  }

  Future<void> _cancelModeReelTransition({
    required String reason,
    required double distance,
    required double velocity,
    required String source,
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
    _debugLog('mode_vertical_cancel', <String, Object?>{
      'source': source,
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
      _modeVerticalGestureSource = null;
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
    final control = source == 'content_vertical'
        ? 'content_vertical_surface+linked_reel'
        : 'frameless_bidirectional_icon_reel';
    _debugLog('mode_vertical_commit', <String, Object?>{
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
      'control': control,
      'visualText': 'none',
      'axisPolicy': 'pointer_axis_lock_single_owner',
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
      _debugLog('mode_vertical_settle_complete', <String, Object?>{
        'source': source,
        'from': from.name,
        'to': to.name,
        'physicalDirection': direction,
        'detent': true,
        'control': control,
      });
      unawaited(
        _showControlStatus(
          title: source == 'content_vertical'
              ? 'TypePage 콘텐츠 보기 모드 전환'
              : 'TypePage 보기 모드 릴 전환',
          lines: <String>[
            'control=$control',
            'viewMode=${from.name}->${to.name}',
            'screen=${widget.screen}',
            'table=${widget.tabs[_currentTableIndex].id}',
            'source=$source physicalDirection=$direction',
            'input=vertical_both_directions axisPolicy=pointer_axis_lock_single_owner',
            'capabilityGate=_canUseModeReel tableOnlyModeSwitchBlocked=true',
            'contentAxisLockDistance=$_contentModeAxisLockDistance contentAxisDominance=$_contentModeAxisDominance horizontalRecognizer=content_removed axisOwner=raw_pointer_single_owner',
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
            'guard=blocked_until_vertical_mode_settle',
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
      _modeVerticalGestureSource = null;
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
    final orderState = context.read<ParkingParentOrderState>();
    final parentNames = orderState.resolveNames(
      area,
      extractParentsFromMeta(locations),
      fallback: naturalLocationCompare,
    );
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
      'orderSource': orderState.hasCustomOrder(area)
          ? 'user_persisted'
          : 'natural_fallback',
      'order': parentNames.join('>'),
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
    required String area,
    required Rect sourceRect,
    required List<_ParentSelectorItem> parents,
    required _ParentSelectorGridMetrics metrics,
    required String currentParent,
  }) async {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final targetRect = _parentSelectorTargetRect(metrics);
    final parentOrderState = context.read<ParkingParentOrderState>();
    final parentOrderSource = parentOrderState.hasCustomOrder(area)
        ? 'user_persisted'
        : 'natural_fallback';
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 340);
    var closeSource = 'route';
    var closeRequested = false;
    var duplicateCloseCount = 0;
    var navigatorPopCount = 0;
    final collapsedCompleter = Completer<void>();
    _lastParentSelectorCloseSource = closeSource;
    _debugLog('parent_selector_expand_started', <String, Object?>{
      'source': interaction == 'status_parent_header'
          ? 'status_parent_header'
          : 'mode_reel',
      'interaction': interaction,
      'sourceRect': realTimeSourceRectDebug(sourceRect),
      'targetRect': realTimeSourceRectDebug(targetRect),
      'area': area,
      'parentCount': parents.length,
      'parentOrderSource': parentOrderSource,
      'parentOrder': parents.map((item) => item.parent).join('>'),
      'orderPersistence': ParkingParentOrderState.prefsKey,
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
              onOrderDebug: (event, details) {
                _debugLog(event, <String, Object?>{
                  'area': area,
                  'entryInteraction': interaction,
                  ...details,
                });
              },
              onOrderSaved: (orderedItems) async {
                final orderState = context.read<ParkingParentOrderState>();
                final before = orderState.resolveNames(
                  area,
                  parents.map((item) => item.parent),
                  fallback: naturalLocationCompare,
                );
                final after = orderedItems
                    .map((item) => item.parent.trim())
                    .where((name) => name.isNotEmpty)
                    .toList(growable: false);
                _debugLog('parent_order_save_started', <String, Object?>{
                  'area': area,
                  'before': before.join('>'),
                  'after': after.join('>'),
                  'count': after.length,
                  'storage': ParkingParentOrderState.prefsKey,
                });
                final saved = await orderState.setOrder(area, after);
                if (!mounted) return saved;
                _debugLog(
                  saved ? 'parent_order_saved' : 'parent_order_save_failed',
                  <String, Object?>{
                    'area': area,
                    'before': before.join('>'),
                    'after': after.join('>'),
                    'count': after.length,
                    'persisted': saved,
                    'affectedConsumers':
                        'status_parent_header,parking_editor,status_parent_paging',
                  },
                );
                unawaited(
                  _showParentOrderStatus(
                    success: saved,
                    lines: <String>[
                      'area=$area persisted=$saved storage=${ParkingParentOrderState.prefsKey}',
                      'before=${before.join('>')}',
                      'after=${after.join('>')}',
                      'parentCount=${after.length}',
                      'statusHeaderOrder=user_persisted_with_natural_fallback',
                      'parkingEditorOrder=user_persisted_with_natural_fallback',
                      'statusParentPagingOrder=user_persisted_with_natural_fallback',
                      'newParentPolicy=append_after_saved_order_with_natural_sort',
                      'deletedParentPolicy=ignore_when_unavailable',
                      'appRestart=persisted_shared_preferences',
                      'editMotion=fade_scale_reorder_settle',
                      'reduceMotion=${MediaQuery.maybeOf(context)?.disableAnimations ?? false}',
                      'debugPrint=clipboard_copy_supported',
                    ],
                  ),
                );
                return saved;
              },
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

  Future<void> _openStatusHeaderParentSelector(
    Rect sourceRect,
    String currentParent,
  ) async {
    if (_parentSelectorOpen || _transitionMaskOn || _tableTransitioning) {
      _debugLog('status_parent_selector_ignored', <String, Object?>{
        'reason': _parentSelectorOpen
            ? 'parent_selector_open'
            : _transitionMaskOn
                ? 'transition_mask_active'
                : 'table_transitioning',
        'mode': _viewMode?.mode.name,
        'currentParent': currentParent,
      });
      return;
    }
    if (!_canOpenModeReelParentSelector()) {
      _debugLog('status_parent_selector_ignored', <String, Object?>{
        'reason': 'reopen_cooldown',
        'remainingMs': _parentSelectorReopenCooldownRemainingMs(),
        'cooldownMs': _parentSelectorReopenCooldown.inMilliseconds,
        'currentParent': currentParent,
      });
      return;
    }
    final vm = _viewMode;
    if (vm == null || vm.mode != TypeViewMode.status || !_statusViewSupported) {
      _debugLog('status_parent_selector_ignored', <String, Object?>{
        'reason': 'status_mode_required',
        'mode': vm?.mode.name,
        'statusSupported': _statusViewSupported,
        'currentParent': currentParent,
      });
      return;
    }
    _onUserActivity();
    _beginModeReelGuard();
    setState(() => _parentSelectorOpen = true);
    HapticFeedback.selectionClick();
    final selectorArea = _readCurrentArea();
    final parentOrderState = context.read<ParkingParentOrderState>();
    final parentOrderSource = parentOrderState.hasCustomOrder(selectorArea)
        ? 'user_persisted'
        : 'natural_fallback';
    _debugLog('status_parent_selector_started', <String, Object?>{
      'source': 'status_parent_header',
      'sourceRect': realTimeSourceRectDebug(sourceRect),
      'currentParent': currentParent,
      'area': selectorArea,
      'parentOrderSource': parentOrderSource,
      'action': 'parent_selector_and_order_editor',
      'reelVisible': false,
      'firebaseAdditionalRead': 0,
    });
    try {
      final parents = await _resolveModeReelParentItems();
      if (!mounted) return;
      if (parents.isEmpty) {
        _debugLog('status_parent_selector_ignored', <String, Object?>{
          'reason': 'no_parent_locations',
          'area': selectorArea,
        });
        return;
      }
      final metrics = _parentSelectorGridMetrics(context, parents.length);
      final selectedParent = await _showParentSelectorDialog(
        interaction: 'status_parent_header',
        area: selectorArea,
        sourceRect: sourceRect,
        parents: parents,
        metrics: metrics,
        currentParent: currentParent,
      );
      if (!mounted || selectedParent == null || selectedParent.trim().isEmpty) {
        _debugLog('status_parent_selector_closed', <String, Object?>{
          'source': 'status_parent_header',
          'selectedParent': selectedParent ?? '-',
          'closeSource': _lastParentSelectorCloseSource,
        });
        return;
      }
      final controller = _controllers[_currentTableIndex];
      final request = controller.requestParentFocus(
        selectedParent,
        deferUntilNextBind: false,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      _debugLog('status_parent_focus_requested', <String, Object?>{
        'serial': request.serial,
        'source': 'status_parent_header',
        'parent': request.parent,
        'mode': vm.mode.name,
        'table': widget.tabs[_currentTableIndex].id,
        'parentOrderSource': parentOrderSource,
      });
    } finally {
      _parentSelectorReopenBlockedUntil =
          DateTime.now().add(_parentSelectorReopenCooldown);
      if (mounted) {
        setState(() => _parentSelectorOpen = false);
      } else {
        _parentSelectorOpen = false;
      }
      _endModeReelGuard();
      _onUserActivity();
    }
  }

  Map<CustomSemanticsAction, VoidCallback>? _modeReelSemanticsActions() {
    if (_locationPresentationReady) return null;
    if (!_canUseModeReel()) return null;
    final vm = _viewMode;
    if (vm == null) return null;
    if (_statusToTableVerticalSwipeLocked && vm.mode == TypeViewMode.status) {
      return null;
    }
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

  RealTimeRequestQueueType? _requestTypeForSpec(RealTimeTabSpec spec) {
    final collection = spec.collection.trim();
    if (collection == RealTimeRequestQueueType.parking.collection) {
      return RealTimeRequestQueueType.parking;
    }
    if (collection == RealTimeRequestQueueType.completed.collection) {
      return RealTimeRequestQueueType.completed;
    }
    if (collection == RealTimeRequestQueueType.departure.collection) {
      return RealTimeRequestQueueType.departure;
    }
    return null;
  }

  RealTimeTabSpec? _requestSpecForType(RealTimeRequestQueueType type) {
    for (final spec in widget.tabs) {
      if (spec.collection.trim() == type.collection) return spec;
    }
    return null;
  }

  Color _interactiveStatusHudColor(
    RealTimeTabSpec spec,
    CommonUiTokens tokens,
  ) {
    final base = _statusHudColor(spec, tokens);
    return Color.lerp(base, tokens.textPrimary, .14) ?? base;
  }

  void _recordRequestHudDebugLine(String line) {
    final normalized = line.trim();
    if (normalized.isEmpty) return;
    _requestHudDebugLines.add(normalized);
    if (_requestHudDebugLines.length > 180) {
      _requestHudDebugLines.removeRange(
        0,
        _requestHudDebugLines.length - 180,
      );
    }
  }

  void _emitRequestHudDebug(
    String event,
    Map<String, Object?> details,
  ) {
    final buffer = StringBuffer()
      ..write('[RealTimeRequestHud] ')
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
    final line = buffer.toString();
    debugPrint(line);
    _recordRequestHudDebugLine(line);
  }

  void _scheduleRequestHudStateTrace({
    required RealTimeRequestQueueType type,
    required String area,
    required int count,
  }) {
    final signature = '$area|$count';
    if (_lastRequestHudSignatures[type] == signature) return;
    _lastRequestHudSignatures[type] = signature;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _emitRequestHudDebug(
        'hud_state_changed',
        <String, Object?>{
          'screen': widget.screen,
          'type': type.sourceKey,
          'collection': type.collection,
          'area': area,
          'count': count,
          'interactive': count > 0,
          'opacity': count > 0 ? '1.0' : 'table_context',
          'color': count > 0 ? 'status_emphasized' : 'status_base',
          'attention': count > 0 ? 'bang_breathing_11oclock' : 'none',
          'tap': count > 0 ? 'enabled' : 'disabled',
          'firebaseAdditionalRead': 0,
        },
      );
    });
  }

  String _requestHudDebugPrintCode() {
    if (_requestHudDebugLines.isEmpty) {
      return 'debugPrint(${jsonEncode('[RealTimeRequestHud] 기록된 로그가 없습니다.')});';
    }
    return _requestHudDebugLines
        .map((line) => 'debugPrint(${jsonEncode(line)});')
        .join('\n');
  }

  Future<void> _showRequestHudDebugDialog({
    required RealTimeRequestQueueType type,
    required String area,
    required int count,
  }) async {
    if (!mounted || _requestHudDebugDialogShowing) return;
    final developerMode = await DevAuth.isDevModeEnabled();
    if (!developerMode || !mounted || _requestHudDebugDialogShowing) return;
    final store = context.read<ViewDocRowsStore>();
    final rows = store.rows(collection: type.collection, area: area);
    final selected = rows.where((row) => row.isSelected).length;
    final bottomLayout = _bottomLayoutMetrics(context);
    final profileCounts = _locationPresentationCounts();
    _emitRequestHudDebug(
      'status_dialog_opened',
      <String, Object?>{
        'screen': widget.screen,
        'type': type.sourceKey,
        'collection': type.collection,
        'area': area,
        'count': count,
        'selected': selected,
        'activeTray': _activeRequestTray?.sourceKey ?? 'none',
        'requestTrayClosing': _requestTrayClosing,
        'backControllerAttached': widget.backController?.attached ?? false,
        'backPriority': 'request_tray_then_page',
        'sortOrder': _requestSortOrder(type).name,
        'interactive': count > 0,
        'opacity': count > 0 ? '1.0' : 'table_context',
        'color': count > 0 ? 'status_emphasized' : 'status_base',
        'attention': count > 0 ? 'bang_breathing_11oclock' : 'none',
        'trayOwner': 'real_time_tabbed_table',
        'rootOverlayEntry': false,
        'firebaseAdditionalRead': 0,
        'locationProfile': _parkingLocationProfile.name,
        'profileDecisionReason':
            _locationProfileResolutionReason(_parkingLocationProfile),
        'locationCount': profileCounts.locationCount,
        'spatialCount': profileCounts.spatialCount,
        'textCount': profileCounts.textCount,
        'unknownCount': profileCounts.unknownCount,
        'systemBottomInset':
            bottomLayout.systemBottomInset.toStringAsFixed(2),
        'bottomActionStackExtent':
            bottomLayout.bottomActionStackExtent.toStringAsFixed(2),
        'hudBottom': bottomLayout.hudBottom.toStringAsFixed(2),
        'trayBottom': bottomLayout.trayBottom.toStringAsFixed(2),
        'reelSurfaceVisible': false,
        'tableOnlySurfaceVisible': false,
        'renderedMode': _renderedContentMode,
        'tableMounted': _renderTableContent,
        'statusMounted': _renderStatusContent,
        'contentOverlap': false,
        'previousChildRetention': false,
        'contentTransition': 'atomic_swap+incoming_reveal',
      },
    );
    final lines = _requestHudDebugLines.length <= 80
        ? List<String>.of(_requestHudDebugLines)
        : _requestHudDebugLines.sublist(_requestHudDebugLines.length - 80);
    _requestHudDebugDialogShowing = true;
    try {
      await StatusDialog.showSuccess(
        context,
        title: '상태 HUD 상태',
        description: lines.join('\n'),
        copyText: _requestHudDebugPrintCode(),
        copyButtonLabel: 'debugPrint 코드 복사',
        visibleDuration: Duration.zero,
        useCommonUi: true,
        awaitManualClose: true,
      );
    } finally {
      _requestHudDebugDialogShowing = false;
    }
  }

  DateTime? _requestRowAt(RealTimeRowVM row) {
    return row.primaryAt ?? row.createdAt ?? row.updatedAt;
  }

  int _compareRequestRows(RealTimeRowVM a, RealTimeRowVM b) {
    final at = _requestRowAt(a);
    final bt = _requestRowAt(b);
    if (at != null && bt != null) {
      final timeCompare = bt.compareTo(at);
      if (timeCompare != 0) return timeCompare;
    } else if (at != null) {
      return -1;
    } else if (bt != null) {
      return 1;
    }
    final plateCompare = a.plateNumber.compareTo(b.plateNumber);
    if (plateCompare != 0) return plateCompare;
    return a.plateId.compareTo(b.plateId);
  }

  List<RealTimeRowVM> _buildRequestRows(
    ViewDocRowsStore store,
    String area,
    RealTimeRequestQueueType type,
    RealTimeTraySortOrder sortOrder,
  ) {
    final rows = store
        .rows(collection: type.collection, area: area)
        .map(
          (source) => RealTimeRowVM(
            plateId: source.plateId,
            plateNumber: source.plateNumber,
            location: source.location,
            primaryAt: source.primaryAt,
            updatedAt: source.updatedAt,
            createdAt: source.createdAt,
            isSelected: source.isSelected,
            selectedBy: source.selectedBy,
          ),
        )
        .toList(growable: false)
      ..sort(_compareRequestRows);
    if (sortOrder == RealTimeTraySortOrder.oldestFirst) {
      return List<RealTimeRowVM>.unmodifiable(rows.reversed);
    }
    return List<RealTimeRowVM>.unmodifiable(rows);
  }

  void _markRequestHudActivity() {
    _autoGuard?.markActivity('request_hud');
  }

  void _beginRequestTrayAutoPause() {
    if (_requestTrayAutoPauseActive) return;
    _requestTrayAutoPauseActive = true;
    _autoGuard?.beginBlock(_requestTrayPauseReason);
  }

  void _endRequestTrayAutoPause() {
    if (!_requestTrayAutoPauseActive) return;
    _requestTrayAutoPauseActive = false;
    _autoGuard?.endBlock(_requestTrayPauseReason);
  }

  int _requestTrayTypeIndex(RealTimeRequestQueueType type) {
    final spec = _requestSpecForType(type);
    if (spec == null) return -1;
    return widget.tabs.indexOf(spec);
  }

  RealTimeTraySortOrder _requestSortOrder(RealTimeRequestQueueType type) {
    return _requestTraySort[type] ?? RealTimeTraySortOrder.newestFirst;
  }

  void _toggleRequestTraySort(RealTimeRequestQueueType type) {
    final previous = _requestSortOrder(type);
    final next = previous == RealTimeTraySortOrder.newestFirst
        ? RealTimeTraySortOrder.oldestFirst
        : RealTimeTraySortOrder.newestFirst;
    HapticFeedback.selectionClick();
    setState(() {
      _requestTraySort[type] = next;
      _requestTraySwitchDirection = 0;
    });
    _emitRequestHudDebug(
      'request_tray_sort_changed',
      <String, Object?>{
        'screen': widget.screen,
        'type': type.sourceKey,
        'collection': type.collection,
        'from': previous.name,
        'to': next.name,
        'timeBasis': 'primaryAt',
      },
    );
  }

  Future<void> _toggleRequestTray(
    RealTimeRequestQueueType type, {
    required String area,
    required int count,
  }) async {
    if (count <= 0 || _requestTrayClosing) return;
    _markRequestHudActivity();
    final previous = _activeRequestTray;
    if (previous == type) {
      await _closeRequestTray(reason: 'hud_toggle_same_type');
      return;
    }
    if (previous == null) {
      _beginRequestTrayAutoPause();
      _requestTraySwitchDirection = 0;
      setState(() => _activeRequestTray = type);
      final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _requestTrayVisibilityController.value = 1;
      } else {
        await _requestTrayVisibilityController.forward(from: 0);
      }
    } else {
      final previousIndex = _requestTrayTypeIndex(previous);
      final nextIndex = _requestTrayTypeIndex(type);
      _requestTraySwitchDirection = previousIndex < 0 || nextIndex < 0
          ? 0
          : nextIndex > previousIndex
              ? 1
              : nextIndex < previousIndex
                  ? -1
                  : 0;
      setState(() => _activeRequestTray = type);
      if (_requestTrayVisibilityController.value < 1) {
        _requestTrayVisibilityController.value = 1;
      }
    }
    _emitRequestHudDebug(
      previous == null ? 'request_tray_opened' : 'request_tray_switched',
      <String, Object?>{
        'screen': widget.screen,
        'area': area,
        'previous': previous?.sourceKey ?? 'none',
        'active': type.sourceKey,
        'count': count,
        'sortOrder': _requestSortOrder(type).name,
        'owner': 'real_time_tabbed_table',
        'source': 'status_count_hud',
        'openMotion': 'fade_translateY_scale_230ms',
        'closeMotion': 'fade_translateY_scale_190ms_reverse_before_null',
        'rootOverlayEntry': false,
        'firebaseAdditionalRead': 0,
      },
    );
  }

  Future<bool> _handleBackRequest() async {
    if (_requestTrayClosing) {
      _emitRequestHudDebug(
        'request_tray_back_consumed_closing',
        <String, Object?>{
          'screen': widget.screen,
          'mode': _viewMode?.mode.name ?? 'unknown',
          'type': _activeRequestTray?.sourceKey ?? 'none',
          'routePopBlocked': true,
          'closing': true,
          'closeMotion': 'fade_translateY_scale_190ms_reverse_before_null',
        },
      );
      return true;
    }
    final active = _activeRequestTray;
    if (active == null) return false;
    _emitRequestHudDebug(
      'request_tray_back_intercepted',
      <String, Object?>{
        'screen': widget.screen,
        'mode': _viewMode?.mode.name ?? 'unknown',
        'type': active.sourceKey,
        'collection': active.collection,
        'routePopBlocked': true,
        'closeReason': 'system_back',
        'closing': false,
        'closeMotion': 'fade_translateY_scale_190ms_reverse_before_null',
      },
    );
    try {
      await _closeRequestTray(reason: 'system_back');
    } catch (error, stackTrace) {
      _emitRequestHudDebug(
        'request_tray_back_close_failure',
        <String, Object?>{
          'screen': widget.screen,
          'mode': _viewMode?.mode.name ?? 'unknown',
          'type': active.sourceKey,
          'error': error,
          'routePopBlocked': true,
        },
      );
      debugPrint(
        '[RealTimeRequestHud] request_tray_back_close_failure error=$error\nStackTrace:\n$stackTrace',
      );
    }
    return true;
  }

  Future<void> _closeRequestTray({required String reason}) async {
    final active = _activeRequestTray;
    if (active == null || _requestTrayClosing) return;
    _requestTrayClosing = true;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    try {
      if (reduceMotion) {
        _requestTrayVisibilityController.value = 0;
      } else {
        await _requestTrayVisibilityController.reverse();
      }
      if (mounted) {
        setState(() {
          _activeRequestTray = null;
          _requestTraySwitchDirection = 0;
        });
      } else {
        _activeRequestTray = null;
        _requestTraySwitchDirection = 0;
      }
      _endRequestTrayAutoPause();
      _emitRequestHudDebug(
        'request_tray_closed',
        <String, Object?>{
          'screen': widget.screen,
          'type': active.sourceKey,
          'reason': reason,
          'owner': 'real_time_tabbed_table',
          'motion': 'reverse_complete_then_state_null',
        },
      );
    } finally {
      _requestTrayClosing = false;
    }
  }

  void _scheduleInvalidRequestTrayClose(RealTimeRequestQueueType type) {
    if (_requestTrayCleanupScheduled) return;
    _requestTrayCleanupScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _requestTrayCleanupScheduled = false;
      if (!mounted || _activeRequestTray != type) return;
      unawaited(_closeRequestTray(reason: 'rows_empty'));
    });
  }

  bool _isRequestRowSelectedNow(
    RealTimeRowVM row,
    RealTimeRequestQueueType type,
    String area,
  ) {
    if (row.isSelected) return true;
    final plateId = row.plateId.trim();
    if (plateId.isEmpty) return false;
    final currentRows = context.read<ViewDocRowsStore>().rows(
          collection: type.collection,
          area: area,
        );
    for (final current in currentRows) {
      if (current.plateId.trim() == plateId) return current.isSelected;
    }
    return false;
  }

  String _expectedPlateTypeForRequest(RealTimeRequestQueueType type) {
    return switch (type) {
      RealTimeRequestQueueType.parking => 'parkingRequests',
      RealTimeRequestQueueType.completed => 'parkingCompleted',
      RealTimeRequestQueueType.departure => 'departureRequests',
    };
  }

  Future<void> _openRequestStatusDock({
    required RealTimeRowVM row,
    required RealTimeRequestQueueType type,
    required String area,
  }) async {
    final source = 'status_count_hud_${type.sourceKey}_request_tray';
    if (_isRequestRowSelectedNow(row, type, area)) {
      _emitRequestHudDebug(
        'status_dock_blocked',
        <String, Object?>{
          'reason': 'driving',
          'source': source,
          'type': type.sourceKey,
          'collection': type.collection,
          'plateId': row.plateId,
          'plateNumber': row.plateNumber,
          'selectedBy': row.selectedBy ?? '-',
          'action': 'keep_request_tray_open',
        },
      );
      return;
    }
    if (_openingRequestDetail) {
      _emitRequestHudDebug(
        'status_dock_blocked',
        <String, Object?>{
          'reason': 'already_open',
          'source': source,
          'plateId': row.plateId,
        },
      );
      return;
    }
    final spec = _requestSpecForType(type);
    if (spec == null) {
      _emitRequestHudDebug(
        'status_dock_blocked',
        <String, Object?>{
          'reason': 'spec_missing',
          'source': source,
          'type': type.sourceKey,
          'collection': type.collection,
          'plateId': row.plateId,
        },
      );
      return;
    }
    final plateId = row.plateId.trim();
    if (plateId.isEmpty) {
      _emitRequestHudDebug(
        'status_dock_blocked',
        <String, Object?>{
          'reason': 'plate_id_empty',
          'source': source,
          'plateNumber': row.plateNumber,
        },
      );
      return;
    }

    _openingRequestDetail = true;
    _markRequestHudActivity();
    _autoGuard?.beginBlock(_requestDockPauseReason);
    final expectedPlateType = _expectedPlateTypeForRequest(type);
    _emitRequestHudDebug(
      'status_dock_open',
      <String, Object?>{
        'source': source,
        'screen': widget.screen,
        'type': type.sourceKey,
        'collection': type.collection,
        'area': area,
        'plateId': plateId,
        'plateNumber': row.plateNumber,
        'location': row.location,
        'expectedPlateType': expectedPlateType,
        'trayOwner': 'real_time_tabbed_table',
        'firebaseAdditionalRead': 0,
      },
    );
    await _closeRequestTray(reason: 'plate_tap_confirmed');
    try {
      final dockContext = Navigator.of(context, rootNavigator: true).context;
      if (!mounted || !dockContext.mounted) return;
      await spec.openStatusDock(
        dockContext,
        RealTimePlateDetailRequest(
          plateId: plateId,
          plateNumber: row.plateNumber,
          area: area,
          location: row.location,
          statusTitle: '${spec.label} 상태 처리',
          cachedPlate: null,
          loadPlate: () async {
            final startedAt = DateTime.now();
            _emitRequestHudDebug(
              'plate_detail_load_start',
              <String, Object?>{
                'source': source,
                'plateId': plateId,
                'collection': type.collection,
                'expectedPlateType': expectedPlateType,
                'repository': 'PlateRepository.getPlate',
              },
            );
            try {
              if (!mounted) return null;
              final plate = await context.read<PlateRepository>().getPlate(plateId);
              _emitRequestHudDebug(
                'plate_detail_load_success',
                <String, Object?>{
                  'source': source,
                  'plateId': plateId,
                  'found': plate != null,
                  'expectedPlateType': expectedPlateType,
                  'actualPlateType': plate?.typeEnum?.name ?? '-',
                  'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
                },
              );
              return plate;
            } catch (error, stackTrace) {
              _emitRequestHudDebug(
                'plate_detail_load_failure',
                <String, Object?>{
                  'source': source,
                  'plateId': plateId,
                  'expectedPlateType': expectedPlateType,
                  'elapsedMs': DateTime.now().difference(startedAt).inMilliseconds,
                  'error': error,
                  'stackTrace': stackTrace,
                },
              );
              rethrow;
            }
          },
        ),
      );
      _emitRequestHudDebug(
        'status_dock_closed',
        <String, Object?>{
          'source': source,
          'type': type.sourceKey,
          'plateId': plateId,
        },
      );
    } catch (error, stackTrace) {
      _emitRequestHudDebug(
        'status_dock_failure',
        <String, Object?>{
          'source': source,
          'type': type.sourceKey,
          'plateId': plateId,
          'error': error,
          'stackTrace': stackTrace,
        },
      );
      rethrow;
    } finally {
      _autoGuard?.endBlock(_requestDockPauseReason);
      _markRequestHudActivity();
      _openingRequestDetail = false;
    }
  }

  Alignment _requestTrayAlignment(RealTimeRequestQueueType type) {
    final spec = _requestSpecForType(type);
    if (spec == null || widget.tabs.length <= 1) return Alignment.bottomCenter;
    final index = widget.tabs.indexOf(spec);
    if (index <= 0) return Alignment.bottomLeft;
    if (index >= widget.tabs.length - 1) return Alignment.bottomRight;
    final ratio = index / (widget.tabs.length - 1);
    if (ratio < .34) return Alignment.bottomLeft;
    if (ratio > .66) return Alignment.bottomRight;
    return Alignment.bottomCenter;
  }

  Widget _buildRequestTrayOverlay({
    required String area,
    required double bottomActionStackExtent,
  }) {
    final active = _activeRequestTray;
    if (active == null || area.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    return Positioned.fill(
      child: Consumer<ViewDocRowsStore>(
        builder: (context, store, _) {
          final sortOrder = _requestSortOrder(active);
          final rows = _buildRequestRows(store, area, active, sortOrder);
          if (rows.isEmpty && !_requestTrayClosing) {
            _scheduleInvalidRequestTrayClose(active);
          }
          final tokens = CommonUiTheme.of(context);
          final reduceMotion =
              MediaQuery.maybeOf(context)?.disableAnimations ?? false;
          final switchDuration =
              reduceMotion ? Duration.zero : CommonUiMotion.component;
          final bottomInset = bottomActionStackExtent + 56;
          return AnimatedBuilder(
            animation: _requestTrayVisibilityController,
            builder: (context, child) {
              final raw = reduceMotion
                  ? (_activeRequestTray == null ? 0.0 : 1.0)
                  : _requestTrayVisibilityController.value;
              final progress = Curves.easeOutCubic.transform(
                raw.clamp(0.0, 1.0).toDouble(),
              );
              final scale = .985 + (.015 * progress);
              final translateY = 8 * (1 - progress);
              return Stack(
                children: [
                  Positioned.fill(
                    bottom: bottomInset - 18,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(
                        _closeRequestTray(reason: 'outside_tap'),
                      ),
                      child: ColoredBox(
                        color: tokens.scrim.withOpacity(.045 * progress),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    top: 0,
                    bottom: bottomInset,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final trayWidth = (constraints.maxWidth - 24)
                            .clamp(0.0, 480.0)
                            .toDouble();
                        final trayHeight = (constraints.maxHeight * .52)
                            .clamp(170.0, 420.0)
                            .toDouble();
                        return AnimatedAlign(
                          alignment: _requestTrayAlignment(active),
                          duration: switchDuration,
                          curve: CommonUiMotion.standard,
                          child: Opacity(
                            opacity: progress,
                            child: Transform.translate(
                              offset: Offset(0, translateY),
                              child: Transform.scale(
                                scale: scale,
                                alignment: Alignment.bottomCenter,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 0, 12, 6),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: trayWidth,
                                      maxHeight: trayHeight,
                                    ),
                                    child: AnimatedSwitcher(
                                      duration: switchDuration,
                                      switchInCurve: CommonUiMotion.enter,
                                      switchOutCurve: CommonUiMotion.exit,
                                      transitionBuilder: (child, animation) {
                                        final direction =
                                            _requestTraySwitchDirection == 0
                                                ? 0.0
                                                : _requestTraySwitchDirection > 0
                                                    ? .035
                                                    : -.035;
                                        final curved = CurvedAnimation(
                                          parent: animation,
                                          curve: CommonUiMotion.enter,
                                          reverseCurve: CommonUiMotion.exit,
                                        );
                                        return FadeTransition(
                                          opacity: curved,
                                          child: SlideTransition(
                                            position: Tween<Offset>(
                                              begin: Offset(direction, .025),
                                              end: Offset.zero,
                                            ).animate(curved),
                                            child: ScaleTransition(
                                              scale: Tween<double>(
                                                begin: .985,
                                                end: 1,
                                              ).animate(curved),
                                              child: child,
                                            ),
                                          ),
                                        );
                                      },
                                      child: RealTimeRequestTray(
                                        key: ValueKey<String>(
                                          'request_hud_tray:${active.sourceKey}:${sortOrder.name}',
                                        ),
                                        type: active,
                                        rows: rows,
                                        sortOrder: sortOrder,
                                        onSortToggle: () =>
                                            _toggleRequestTraySort(active),
                                        onDebugLine:
                                            _recordRequestHudDebugLine,
                                        onClose: () => unawaited(
                                          _closeRequestTray(
                                            reason: 'close_button',
                                          ),
                                        ),
                                        onRequestTap: (row) =>
                                            _openRequestStatusDock(
                                          row: row,
                                          type: active,
                                          area: area,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
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
    final tableMode = _renderTableContent;
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

  Widget _buildTableCollectionAccentOverlay() {
    final tokens = CommonUiTheme.of(context);
    final tableMode = _renderTableContent;
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

    final requestType = _requestTypeForSpec(spec);
    return Selector<ViewDocRowsStore, int>(
      selector: (_, store) =>
          store.rows(collection: collection, area: normalizedArea).length,
      builder: (context, count, _) {
        final interactive = requestType != null && count > 0;
        final activeTray = requestType != null && _activeRequestTray == requestType;
        if (requestType != null) {
          _scheduleRequestHudStateTrace(
            type: requestType,
            area: normalizedArea,
            count: count,
          );
        }
        final baseColor = _statusHudColor(spec, tokens);
        final targetColor = interactive
            ? _interactiveStatusHudColor(spec, tokens)
            : baseColor;
        final countVisual = AnimatedDefaultTextStyle(
          duration: _motionDuration(CommonUiMotion.selection),
          curve: CommonUiMotion.standard,
          style: (Theme.of(context).textTheme.titleLarge ?? const TextStyle())
              .copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: targetColor,
            fontFeatures: const <FontFeature>[
              FontFeature.tabularFigures(),
            ],
            height: 1,
          ),
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
            ),
          ),
        );

        return AnimatedBuilder(
          animation: Listenable.merge(<Listenable>[
            _hudPulseController,
            _tableSwipeController,
          ]),
          builder: (context, child) {
            final baseOpacity = interactive ? 1.0 : _hudBaseOpacityForIndex(index);
            final opacity = interactive
                ? 1.0
                : _hudOpacity(
                    _hudPulseController.value,
                    baseOpacity: baseOpacity,
                  );
            return Opacity(opacity: opacity, child: child);
          },
          child: _RequestHudCell(
            enabled: interactive,
            attentionVisible: interactive,
            attentionSteady: false,
            statusColor: targetColor,
            semanticsLabel: requestType == null
                ? '${spec.label} $count대'
                : '${requestType.label} $count대',
            onTap: interactive
                ? () {
                    HapticFeedback.selectionClick();
                    _emitRequestHudDebug(
                      'hud_tap',
                      <String, Object?>{
                        'screen': widget.screen,
                        'type': requestType.sourceKey,
                        'collection': requestType.collection,
                        'area': normalizedArea,
                        'count': count,
                        'opacity': '1.0',
                        'color': 'status_emphasized',
                        'attention': 'bang_breathing_11oclock',
                        'action': activeTray ? 'close_request_tray' : 'open_request_tray',
                      },
                    );
                    unawaited(
                      _toggleRequestTray(
                        requestType,
                        area: normalizedArea,
                        count: count,
                      ),
                    );
                  }
                : null,
            onLongPress: interactive
                ? () => unawaited(
                      _showRequestHudDebugDialog(
                        type: requestType,
                        area: normalizedArea,
                        count: count,
                      ),
                    )
                : null,
            child: countVisual,
          ),
        );
      },
    );
  }

  Widget _buildStatePageAt(int index) {
    final normalizedIndex = index.clamp(0, widget.tabs.length - 1);
    final spec = widget.tabs[normalizedIndex];
    final Widget content;

    if (!_renderTableContent && !_renderStatusContent) {
      content = const SizedBox.shrink(
        key: ValueKey<String>('location-presentation:pending'),
      );
    } else if (_isTableEnabled(normalizedIndex)) {
      final Widget activeContent;
      if (_renderStatusContent) {
        activeContent = KeyedSubtree(
          key: ValueKey<String>('status:${spec.id}'),
          child: widget.statusBodyBuilder(
            context,
            spec,
            _controllers[normalizedIndex],
          ),
        );
      } else {
        activeContent = KeyedSubtree(
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
      }
      content = _buildModeContentReveal(activeContent);
    } else {
      content = RealTimeLockedPanel(
        title: '${spec.label} 실시간 테이블이 비활성화되어 있습니다',
        message: '설정에서 “${spec.label} 실시간 모드 사용”을 ON으로 변경한 뒤 다시 시도해 주세요.',
      );
    }

    return KeyedSubtree(
      key: ValueKey<String>(
        'state-page:$_renderedContentMode:${spec.id}',
      ),
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
        final canTrackContentGesture = _statusViewSupported || canSwipe;
        return Semantics(
          customSemanticsActions: _contentSemanticsActions(),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: canTrackContentGesture
                ? (event) => _onContentGesturePointerDown(
                      event,
                      viewportWidth,
                    )
                : null,
            onPointerMove: canTrackContentGesture
                ? _onContentGesturePointerMove
                : null,
            onPointerUp: canTrackContentGesture
                ? _onContentGesturePointerUp
                : null,
            onPointerCancel: canTrackContentGesture
                ? _onContentGesturePointerCancel
                : null,
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
          child: CommonQuickActionControl(
            semanticsLabel: '입차',
            icon: Icons.add_circle_outline_rounded,
            foreground: cs.primary,
            showProgressWhileRunning: false,
            onPressed: (sourceRect) =>
                _runEntryQuickActionFromSurface(actions.openEntry, sourceRect),
          ),
        ),
        Expanded(
          child: CommonQuickActionControl(
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
          child: CommonQuickActionControl(
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
    final tokens = CommonUiTheme.of(context);
    final targetBackground = _shellBackgroundColor(cs, tokens);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final surface = TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: targetBackground),
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: Curves.easeOutCubic,
      builder: (context, background, child) {
        return CommonQuickActionSurface(
          backgroundColor: background ?? targetBackground,
          borderColor: widget.tabBarStyle.borderColor(cs),
          child: child!,
        );
      },
      child: _buildQuickActions(context, actions, cs),
    );
    return ValueListenableBuilder<bool>(
      valueListenable: DevAuth.devModeEnabled,
      child: surface,
      builder: (context, developerMode, child) {
        if (!developerMode) return child!;
        return GestureDetector(
          behavior: HitTestBehavior.translucent,
          onLongPress: () => unawaited(_showBottomLayoutDebugDialog()),
          child: child,
        );
      },
    );
  }

  Widget _buildBottomSafeAreaSpacer(
    ColorScheme cs,
    _BottomLayoutMetrics metrics,
  ) {
    final tokens = CommonUiTheme.of(context);
    final targetBackground = metrics.modeControlExtent > 0
        ? widget.tabBarStyle.containerColor(cs)
        : _shellBackgroundColor(cs, tokens);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: targetBackground),
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: Curves.easeOutCubic,
      builder: (context, background, _) {
        return ColoredBox(
          color: background ?? targetBackground,
          child: SizedBox(height: metrics.systemBottomInset),
        );
      },
    );
  }

  Widget _buildStatusCountOverlay({
    required String area,
    required double bottomActionStackExtent,
  }) {
    final tokens = CommonUiTheme.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: bottomActionStackExtent + 1,
      height: 48,
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
    );
  }

  Widget _buildLocationLoadingSurface(ColorScheme cs) {
    final text = Theme.of(context).textTheme;
    return Container(
      key: const ValueKey<String>('parking-mode:loading'),
      color: widget.tabBarStyle.containerColor(cs),
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
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
      padding: const EdgeInsets.fromLTRB(12, 7, 12, 8),
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
    );
  }

  Widget _buildParkingModeControlSurface(ColorScheme cs) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final child = switch (_parkingViewCapability) {
      ParkingViewCapability.loading => _buildLocationLoadingSurface(cs),
      ParkingViewCapability.empty => _buildLocationEmptySurface(cs),
      ParkingViewCapability.tableOnly => const SizedBox.shrink(
          key: ValueKey<String>('parking-mode:table-only-no-reel'),
        ),
      ParkingViewCapability.statusOnly => const SizedBox.shrink(
          key: ValueKey<String>('parking-mode:status-only-no-reel'),
        ),
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
    final tokens = CommonUiTheme.of(context);
    final area = _resolveArea();
    final bottomLayout = _bottomLayoutMetrics(context);
    _scheduleBottomLayoutTrace(bottomLayout);
    _scheduleRenderSeparationTrace();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final shellBackground = _shellBackgroundColor(cs, tokens);
    return RealTimeStatusActionScope(
      onOpenParentSelector: _openStatusHeaderParentSelector,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
        curve: Curves.easeOutCubic,
        color: shellBackground,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Column(
              children: [
                if (_renderTableContent) _buildTableContextBar(cs),
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      _buildSwipeableStateContent(),
                      if (_renderTableContent)
                        _buildTableCollectionAccentOverlay(),
                      _transitionMaskLayer(context),
                    ],
                  ),
                ),
                _buildLayerSurface(cs),
                _buildParkingModeControlSurface(cs),
                _buildBottomSafeAreaSpacer(cs, bottomLayout),
              ],
            ),
            _buildRequestTrayOverlay(
              area: area,
              bottomActionStackExtent: bottomLayout.bottomActionStackExtent,
            ),
            _buildStatusCountOverlay(
              area: area,
              bottomActionStackExtent: bottomLayout.bottomActionStackExtent,
            ),
          ],
        ),
      ),
    );
  }

}


class _BottomLayoutMetrics {
  const _BottomLayoutMetrics({
    required this.systemBottomInset,
    required this.quickActionExtent,
    required this.modeControlExtent,
  });

  final double systemBottomInset;
  final double quickActionExtent;
  final double modeControlExtent;

  double get bottomActionStackExtent =>
      systemBottomInset + quickActionExtent + modeControlExtent;

  double get hudBottom => bottomActionStackExtent + 1;

  double get trayBottom => bottomActionStackExtent + 56;
}


class _RequestHudCell extends StatefulWidget {
  const _RequestHudCell({
    required this.enabled,
    required this.attentionVisible,
    required this.attentionSteady,
    required this.statusColor,
    required this.semanticsLabel,
    required this.child,
    this.onTap,
    this.onLongPress,
  });

  final bool enabled;
  final bool attentionVisible;
  final bool attentionSteady;
  final Color statusColor;
  final String semanticsLabel;
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<_RequestHudCell> createState() => _RequestHudCellState();
}

class _RequestHudCellState extends State<_RequestHudCell> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (!mounted || _pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  void didUpdateWidget(covariant _RequestHudCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && _pressed) {
      _pressed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final pressDuration = reduceMotion ? Duration.zero : const Duration(milliseconds: 90);
    return Semantics(
      button: widget.enabled,
      enabled: widget.enabled,
      label: widget.semanticsLabel,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTapDown: widget.enabled ? (_) => _setPressed(true) : null,
        onTapUp: widget.enabled ? (_) => _setPressed(false) : null,
        onTapCancel: widget.enabled ? () => _setPressed(false) : null,
        onTap: widget.enabled ? widget.onTap : null,
        onLongPress: widget.enabled ? widget.onLongPress : null,
        child: SizedBox(
          width: double.infinity,
          height: 48,
          child: AnimatedScale(
            duration: pressDuration,
            curve: Curves.easeOutCubic,
            scale: _pressed ? .96 : 1,
            child: Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                widget.child,
                Transform.translate(
                  offset: const Offset(-16, -13),
                  child: _RequestAttentionMark(
                    visible: widget.attentionVisible,
                    steady: widget.attentionSteady,
                    color: widget.statusColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RequestAttentionMark extends StatefulWidget {
  const _RequestAttentionMark({
    required this.visible,
    required this.steady,
    required this.color,
  });

  final bool visible;
  final bool steady;
  final Color color;

  @override
  State<_RequestAttentionMark> createState() => _RequestAttentionMarkState();
}

class _RequestAttentionMarkState extends State<_RequestAttentionMark>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 950),
      value: 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion != next) {
      _reduceMotion = next;
    }
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _RequestAttentionMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (!widget.visible || widget.steady || _reduceMotion) {
      _controller.stop();
      _controller.value = widget.visible ? 1 : 0;
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final duration = _reduceMotion ? Duration.zero : const Duration(milliseconds: 230);
    return AnimatedOpacity(
      duration: duration,
      curve: Curves.easeOutCubic,
      opacity: widget.visible ? 1 : 0,
      child: AnimatedScale(
        duration: duration,
        curve: Curves.easeOutBack,
        scale: widget.visible ? 1 : .82,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final pulse = widget.steady || _reduceMotion
                ? 1.0
                : Curves.easeInOutSine.transform(_controller.value);
            final scale = widget.steady || _reduceMotion ? 1.0 : 1 + (.08 * pulse);
            final opacity = widget.steady || _reduceMotion ? 1.0 : .76 + (.24 * pulse);
            return Opacity(
              opacity: opacity,
              child: Transform.scale(
                scale: scale,
                child: child,
              ),
            );
          },
          child: Text(
            '!',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: widget.color,
              fontSize: 11,
              height: 1,
              fontWeight: FontWeight.w900,
              shadows: <Shadow>[
                Shadow(
                  color: widget.color.withOpacity(.24),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
        ),
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

class _ParentSelectorDialogSurface extends StatefulWidget {
  const _ParentSelectorDialogSurface({
    required this.parents,
    required this.metrics,
    required this.currentParent,
    required this.progress,
    required this.interactionEnabled,
    required this.onClose,
    required this.onSelected,
    required this.onOrderSaved,
    required this.onOrderDebug,
  });

  final List<_ParentSelectorItem> parents;
  final _ParentSelectorGridMetrics metrics;
  final String currentParent;
  final double progress;
  final bool interactionEnabled;
  final VoidCallback onClose;
  final ValueChanged<_ParentSelectorItem> onSelected;
  final Future<bool> Function(List<_ParentSelectorItem>) onOrderSaved;
  final void Function(String event, Map<String, Object?> details) onOrderDebug;

  @override
  State<_ParentSelectorDialogSurface> createState() =>
      _ParentSelectorDialogSurfaceState();
}

class _ParentSelectorDialogSurfaceState
    extends State<_ParentSelectorDialogSurface> {
  late List<_ParentSelectorItem> _displayParents;
  late List<_ParentSelectorItem> _draftParents;
  bool _editing = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _displayParents = List<_ParentSelectorItem>.of(widget.parents);
    _draftParents = List<_ParentSelectorItem>.of(widget.parents);
  }

  @override
  void didUpdateWidget(covariant _ParentSelectorDialogSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_editing && !_saving && !identical(oldWidget.parents, widget.parents)) {
      _displayParents = List<_ParentSelectorItem>.of(widget.parents);
      _draftParents = List<_ParentSelectorItem>.of(widget.parents);
    }
  }

  void _enterEdit() {
    if (!widget.interactionEnabled || _saving || _editing) return;
    HapticFeedback.selectionClick();
    setState(() {
      _editing = true;
      _draftParents = List<_ParentSelectorItem>.of(_displayParents);
    });
    widget.onOrderDebug('parent_order_edit_started', <String, Object?>{
      'count': _draftParents.length,
      'before': _draftParents.map((item) => item.parent).join('>'),
      'layout': 'reorderable_list',
      'selectionDuringEdit': 'disabled',
      'motion': 'fade_scale_210ms',
    });
  }

  void _cancelEdit() {
    if (_saving || !_editing) return;
    HapticFeedback.selectionClick();
    widget.onOrderDebug('parent_order_edit_cancelled', <String, Object?>{
      'count': _draftParents.length,
      'draft': _draftParents.map((item) => item.parent).join('>'),
      'persisted': false,
    });
    setState(() {
      _editing = false;
      _draftParents = List<_ParentSelectorItem>.of(_displayParents);
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    if (_saving || !_editing) return;
    var targetIndex = newIndex;
    if (targetIndex > oldIndex) targetIndex -= 1;
    if (targetIndex == oldIndex ||
        oldIndex < 0 ||
        oldIndex >= _draftParents.length ||
        targetIndex < 0 ||
        targetIndex >= _draftParents.length) {
      return;
    }
    final moved = _draftParents[oldIndex];
    setState(() {
      final item = _draftParents.removeAt(oldIndex);
      _draftParents.insert(targetIndex, item);
    });
    HapticFeedback.selectionClick();
    widget.onOrderDebug('parent_order_reordered', <String, Object?>{
      'parent': moved.parent,
      'fromIndex': oldIndex,
      'toIndex': targetIndex,
      'count': _draftParents.length,
      'draft': _draftParents.map((item) => item.parent).join('>'),
      'haptic': 'selectionClick',
      'motion': 'reorder_proxy_scale_1.025_settle',
    });
  }

  Future<void> _saveEdit() async {
    if (_saving || !_editing) return;
    setState(() => _saving = true);
    final ordered = List<_ParentSelectorItem>.unmodifiable(_draftParents);
    widget.onOrderDebug('parent_order_edit_save_requested', <String, Object?>{
      'count': ordered.length,
      'after': ordered.map((item) => item.parent).join('>'),
    });
    final saved = await widget.onOrderSaved(ordered);
    if (!mounted) return;
    if (saved) {
      HapticFeedback.selectionClick();
      setState(() {
        _displayParents = List<_ParentSelectorItem>.of(ordered);
        _draftParents = List<_ParentSelectorItem>.of(ordered);
        _editing = false;
        _saving = false;
      });
      widget.onOrderDebug('parent_order_edit_saved', <String, Object?>{
        'count': ordered.length,
        'after': ordered.map((item) => item.parent).join('>'),
        'persisted': true,
        'haptic': 'selectionClick',
      });
      return;
    }
    setState(() => _saving = false);
    widget.onOrderDebug('parent_order_edit_save_failed', <String, Object?>{
      'count': ordered.length,
      'after': ordered.map((item) => item.parent).join('>'),
      'persisted': false,
    });
  }

  void _handleHeaderBack() {
    if (_editing) {
      _cancelEdit();
      return;
    }
    widget.onClose();
  }

  Widget _buildGrid(BuildContext context, double contentProgress) {
    final parents = _displayParents;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.metrics.horizontalPadding,
        4,
        widget.metrics.horizontalPadding,
        10,
      ),
      child: GridView.builder(
        padding: EdgeInsets.zero,
        physics: widget.metrics.scrollNeeded
            ? const BouncingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        itemCount: parents.length,
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: widget.metrics.columns,
          crossAxisSpacing: widget.metrics.crossAxisSpacing,
          mainAxisSpacing: widget.metrics.mainAxisSpacing,
          mainAxisExtent: widget.metrics.tileExtent,
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
                  previewHeight: widget.metrics.previewHeight,
                  selected:
                      item.parent.trim() == widget.currentParent.trim(),
                  onTap: () => widget.onSelected(item),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEditList(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return ReorderableListView.builder(
      padding: EdgeInsets.fromLTRB(
        widget.metrics.horizontalPadding,
        6,
        widget.metrics.horizontalPadding,
        10,
      ),
      buildDefaultDragHandles: false,
      physics: const BouncingScrollPhysics(),
      itemCount: _draftParents.length,
      onReorder: _reorder,
      proxyDecorator: (child, index, animation) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return AnimatedBuilder(
          animation: curved,
          builder: (context, _) {
            final value = curved.value;
            return Transform.scale(
              scale: 1 + .025 * value,
              child: Opacity(
                opacity: 1 - .04 * value,
                child: Material(
                  color: Colors.transparent,
                  elevation: 8 * value,
                  borderRadius: BorderRadius.circular(12),
                  child: child,
                ),
              ),
            );
          },
        );
      },
      itemBuilder: (context, index) {
        final item = _draftParents[index];
        return _ParentOrderEditRow(
          key: ValueKey<String>(
            'parent-order-${ParkingParentOrderState.canonicalKey(item.parent)}',
          ),
          item: item,
          index: index,
          selected: item.parent.trim() == widget.currentParent.trim(),
          enabled: !_saving,
        );
      },
    );
  }

  Widget _buildBody(BuildContext context, double contentProgress) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 210);
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final scale = Tween<double>(begin: .985, end: 1).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(scale: scale, child: child),
        );
      },
      child: _editing
          ? KeyedSubtree(
              key: const ValueKey<String>('parent-order-edit'),
              child: _buildEditList(context),
            )
          : KeyedSubtree(
              key: const ValueKey<String>('parent-order-grid'),
              child: _buildGrid(context, contentProgress),
            ),
    );
  }

  Widget _buildHeaderAction(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_editing) {
      return Semantics(
        button: true,
        label: '부모 주차 구역 순서 저장',
        child: IconButton(
          onPressed: _saving ? null : () => unawaited(_saveEdit()),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 38, height: 38),
          splashRadius: 18,
          icon: AnimatedSwitcher(
            duration: (MediaQuery.maybeOf(context)?.disableAnimations ?? false)
                ? Duration.zero
                : const Duration(milliseconds: 160),
            child: _saving
                ? SizedBox(
                    key: const ValueKey<String>('saving'),
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: cs.primary,
                    ),
                  )
                : Icon(
                    Icons.check_rounded,
                    key: const ValueKey<String>('save'),
                    size: 20,
                    color: cs.primary,
                  ),
          ),
        ),
      );
    }
    return Semantics(
      button: true,
      label: '부모 주차 구역 순서 편집',
      child: IconButton(
        onPressed: widget.interactionEnabled && _displayParents.length > 1
            ? _enterEdit
            : null,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
        splashRadius: 18,
        icon: Icon(
          Icons.swap_vert_rounded,
          size: 20,
          color: cs.primary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final headerProgress =
        ((widget.progress - .52) / .48).clamp(0.0, 1.0).toDouble();
    final surfaceOpacity =
        (.92 + .04 * widget.progress).clamp(0.0, 1.0).toDouble();
    final contentProgress =
        ((widget.progress - .34) / .66).clamp(0.0, 1.0).toDouble();
    return Material(
      color: cs.surface.withOpacity(surfaceOpacity),
      child: Stack(
        children: [
          Positioned.fill(
            top: 41,
            child: IgnorePointer(
              ignoring: !widget.interactionEnabled || _saving,
              child: _buildBody(context, contentProgress),
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
                            label: _editing
                                ? '부모 주차 구역 순서 편집 취소'
                                : '부모 주차 구역 선택 닫기',
                            child: IconButton(
                              onPressed: _saving ? null : _handleHeaderBack,
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
                            child: AnimatedSwitcher(
                              duration: (MediaQuery.maybeOf(context)
                                              ?.disableAnimations ??
                                          false)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 180),
                              switchInCurve: Curves.easeOutCubic,
                              switchOutCurve: Curves.easeInCubic,
                              child: _editing
                                  ? Text(
                                      '순서 편집',
                                      key: const ValueKey<String>('edit-title'),
                                      textAlign: TextAlign.center,
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge
                                          ?.copyWith(
                                            color: cs.onSurface,
                                            fontWeight: FontWeight.w900,
                                          ),
                                    )
                                  : Icon(
                                      Icons.local_parking_rounded,
                                      key: const ValueKey<String>(
                                        'parking-title',
                                      ),
                                      size: 20,
                                      color: cs.primary,
                                    ),
                            ),
                          ),
                          _buildHeaderAction(context),
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

class _ParentOrderEditRow extends StatelessWidget {
  const _ParentOrderEditRow({
    super.key,
    required this.item,
    required this.index,
    required this.selected,
    required this.enabled,
  });

  final _ParentSelectorItem item;
  final int index;
  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: AnimatedContainer(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: selected ? cs.primaryContainer.withOpacity(.22) : cs.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? cs.primary.withOpacity(.34)
                : cs.outlineVariant.withOpacity(.42),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 28,
              child: Text(
                '${index + 1}',
                textAlign: TextAlign.center,
                style: text.labelMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 58,
              height: 38,
              child: IgnorePointer(
                child: ExcludeSemantics(
                  child: RealTimeParentMapThumbnail(
                    grid: item.grid,
                    childRects: item.childRects,
                    selected: selected,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                item.parent,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: text.labelLarge?.copyWith(
                  color: cs.onSurface,
                  fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                ),
              ),
            ),
            if (selected)
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.check_circle_rounded,
                  size: 17,
                  color: cs.primary,
                ),
              ),
            IgnorePointer(
              ignoring: !enabled,
              child: ReorderableDragStartListener(
                index: index,
                child: Semantics(
                  button: true,
                  label: '${item.parent} 순서 이동',
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: Icon(
                      Icons.drag_handle_rounded,
                      size: 22,
                      color: enabled
                          ? cs.onSurfaceVariant
                          : cs.onSurfaceVariant.withOpacity(.35),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
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

