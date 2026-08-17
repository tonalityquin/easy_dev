import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/dev/debug/debug_action_recorder.dart';
import '../../../secondary/side_docks/secondary_side_dock.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../plate/application/common/driving_recovery_gate.dart';
import '../../../plate/domain/enums/plate_type.dart';
import '../../../plate/domain/repositories/plate_repository.dart';
import '../../../tts/application/plate_tts_event_hub.dart';
import '../../../tts/services/page/tts_view_refresh_service.dart';
import '../../../real_time_table/real_time_sort_state.dart';
import '../../application/common/type_auto_transition_guard.dart';
import '../../application/common/type_view_mode_state.dart';
import 'type_page_bottom_bars.dart';

typedef TypePageCurrentPageBuilder<PgState extends ChangeNotifier> = Widget
    Function(BuildContext context, PgState pageState);
typedef TypePageParkingCompletedControlBarBuilder<
        PgState extends ChangeNotifier>
    = Widget Function(BuildContext context, PgState pageState);
typedef TypePageSelectionClearer<PState, PgState extends ChangeNotifier>
    = Future<void> Function(
  PState plateState,
  PgState pageState,
  String userName,
  void Function(String) onError,
);

class TypePageRealtimeViewsRefreshService {
  TypePageRealtimeViewsRefreshService({
    required this.collections,
  });

  final List<String> collections;

  static final Map<String, DateTime> _blockedUntilByKey = <String, DateTime>{};
  static final Map<String, Map<String, dynamic>?> _lastDataByKey =
      <String, Map<String, dynamic>?>{};

  Duration _cooldownForCollection(String collection) {
    if (collection == 'parking_completed_view') {
      return const Duration(seconds: 15);
    }
    return const Duration(seconds: 3);
  }

  String _key(String collection, String area) => '$collection|${area.trim()}';

  bool _isBlocked(String collection, String area) {
    final until = _blockedUntilByKey[_key(collection, area)];
    if (until == null) return false;
    return DateTime.now().isBefore(until);
  }

  void _startCooldown(String collection, String area) {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) return;

    _blockedUntilByKey[_key(collection, normalizedArea)] = DateTime.now().add(
      _cooldownForCollection(collection),
    );
  }

  Future<void> _fetchOne(
    PlateRepository repository,
    String collection,
    String area,
  ) async {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) return;
    if (_isBlocked(collection, normalizedArea)) return;

    _startCooldown(collection, normalizedArea);

    final data = await repository.fetchViewDocumentData(
      collection: collection,
      area: normalizedArea,
    );
    _lastDataByKey[_key(collection, normalizedArea)] = data;
  }

  Future<void> refreshAllForArea(
    BuildContext context,
    String area,
  ) async {
    final normalizedArea = area.trim();
    if (normalizedArea.isEmpty) return;

    final repository = context.read<PlateRepository>();

    await Future.wait<void>(
      collections.map(
        (collection) => _fetchOne(repository, collection, normalizedArea),
      ),
    );
  }

  Future<void> refreshAllForCurrentArea(BuildContext context) async {
    var area = '';

    try {
      area = context.read<UserState>().currentArea.trim();
    } catch (_) {}

    if (area.isEmpty) {
      try {
        area = context.read<AreaState>().currentArea.trim();
      } catch (_) {}
    }

    if (area.isEmpty) return;
    await refreshAllForArea(context, area);
  }
}

class TypePageConfig<PState, PgState extends ChangeNotifier> {
  TypePageConfig({
    required this.createPageState,
    required this.enableForTypePages,
    required this.disableAll,
    required this.isLoading,
    required this.clearCurrentSelection,
    required this.buildCurrentPage,
    required this.buildParkingCompletedControlBar,
    required this.buildDashboardSideDock,
    required this.buildInputScreen,
    required this.debugMeta,
    this.recoveryMode,
  });

  final PgState Function() createPageState;
  final void Function(PState plateState) enableForTypePages;
  final void Function(PState plateState) disableAll;
  final bool Function(PState plateState) isLoading;
  final TypePageSelectionClearer<PState, PgState> clearCurrentSelection;
  final TypePageCurrentPageBuilder<PgState> buildCurrentPage;
  final TypePageParkingCompletedControlBarBuilder<PgState>
      buildParkingCompletedControlBar;
  final Widget Function() buildDashboardSideDock;
  final Widget Function() buildInputScreen;
  final Map<String, dynamic> debugMeta;
  final DrivingRecoveryMode? recoveryMode;
}

class TypePageShell<PState, PgState extends ChangeNotifier>
    extends StatefulWidget {
  const TypePageShell({
    super.key,
    required this.config,
  });

  final TypePageConfig<PState, PgState> config;

  @override
  State<TypePageShell<PState, PgState>> createState() =>
      _TypePageShellState<PState, PgState>();
}

class _TypePageShellState<PState, PgState extends ChangeNotifier>
    extends State<TypePageShell<PState, PgState>> {
  StreamSubscription<PlateTtsEvent>? _ttsEventSub;
  Timer? _ttsDebounceTimer;
  bool _pendingFull = false;
  bool _pendingDepartureOnly = false;
  String _pendingArea = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final plateState = context.read<PState>();
      widget.config.enableForTypePages(plateState);
      PlateTtsEventHub.ensureStarted();
      _ttsEventSub ??= PlateTtsEventHub.stream.listen(_onTtsEvent);
    });
  }

  void _onTtsEvent(PlateTtsEvent event) {
    if (!mounted) return;

    final currentArea = context.read<AreaState>().currentArea.trim();
    if (currentArea.isEmpty || currentArea != event.area) return;

    _pendingArea = currentArea;

    if (event.type == PlateType.departureCompleted.firestoreValue) {
      if (!_pendingFull) _pendingDepartureOnly = true;
    } else {
      _pendingFull = true;
    }

    _ttsDebounceTimer?.cancel();
    _ttsDebounceTimer = Timer(const Duration(milliseconds: 250), () async {
      final area = _pendingArea.trim();
      final doFull = _pendingFull;
      final doDepartureOnly = _pendingDepartureOnly;

      _pendingFull = false;
      _pendingDepartureOnly = false;
      _pendingArea = '';

      if (area.isEmpty) return;
      if (!mounted) return;

      if (doFull) {
        await TtsViewRefreshService.refreshFull(area);
      } else if (doDepartureOnly) {
        await TtsViewRefreshService.refreshDepartureOnly(area);
      }
    });
  }

  @override
  void dispose() {
    _ttsDebounceTimer?.cancel();
    _ttsDebounceTimer = null;
    unawaited(_ttsEventSub?.cancel() ?? Future.value());
    _ttsEventSub = null;

    try {
      final plateState = context.read<PState>();
      widget.config.disableAll(plateState);
    } catch (_) {}

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<TypeViewModeState>(
            create: (_) => TypeViewModeState(),
          ),
          ChangeNotifierProvider<TypeAutoTransitionGuard>(
            create: (_) => TypeAutoTransitionGuard(),
          ),
          ChangeNotifierProvider<RealTimeSortState>(
            create: (_) => RealTimeSortState(),
          ),
          ChangeNotifierProvider<PgState>(
            create: (_) => widget.config.createPageState(),
          ),
        ],
        child: Builder(
          builder: (context) {
            final plateState = context.read<PState>();
            final pageState = context.read<PgState>();
            final userName = context.read<UserState>().name;
            final tokens = CommonUiTheme.of(context);
            final isDark = tokens.brightness == Brightness.dark;

            final refreshableBody = TypePageRefreshableBody<PState, PgState>(
              config: widget.config,
            );

            final body = widget.config.recoveryMode == null
                ? refreshableBody
                : DrivingRecoveryGate(
                    mode: widget.config.recoveryMode!,
                    child: refreshableBody,
                  );

            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: tokens.surface,
                statusBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
                statusBarBrightness:
                    isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: tokens.surface,
                systemNavigationBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
              ),
              child: PopScope(
                canPop: false,
                onPopInvoked: (didPop) async {
                  if (didPop) return;
                  if (RealTimeChildFocusBackGuard.handleBack()) {
                    debugPrint(
                      '[RealTimeChildFocusBackGuard] system_back consumed=true action=child_to_parent',
                    );
                    return;
                  }
                  await widget.config.clearCurrentSelection(
                    plateState,
                    pageState,
                    userName,
                    (msg) => debugPrint(msg),
                  );
                },
                child: TypePageInteractionBoundary(
                  child: Stack(
                    children: [
                      Scaffold(
                        backgroundColor: tokens.canvas,
                        body: body,
                        bottomNavigationBar: TypePageBottomBars(
                          tableTop: TypePageParkingCompletedControlBar<PgState>(
                            builder: widget.config.buildParkingCompletedControlBar,
                          ),
                          tableMiddle: TypePageEntryDashboardBar(
                            config: widget.config,
                          ),
                          modeSwitch: const TypePageModeSwitchBar(),
                        ),
                      ),
                      const TypeAutoTransitionDebugIndicator(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class TypePageInteractionBoundary extends StatelessWidget {
  const TypePageInteractionBoundary({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final guard = context.read<TypeAutoTransitionGuard>();
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (notification is ScrollStartNotification) {
          guard.beginScroll();
        } else if (notification is ScrollEndNotification) {
          guard.endScroll();
        }
        return false;
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: guard.pointerDown,
        onPointerMove: guard.pointerMove,
        onPointerUp: guard.pointerUp,
        onPointerCancel: guard.pointerCancel,
        onPointerSignal: guard.pointerSignal,
        onPointerHover: (_) => guard.markActivity('pointer_hover'),
        child: child,
      ),
    );
  }
}

class TypeAutoTransitionDebugIndicator extends StatefulWidget {
  const TypeAutoTransitionDebugIndicator({super.key});

  @override
  State<TypeAutoTransitionDebugIndicator> createState() =>
      _TypeAutoTransitionDebugIndicatorState();
}

class _TypeAutoTransitionDebugIndicatorState
    extends State<TypeAutoTransitionDebugIndicator> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      final guard = context.read<TypeAutoTransitionGuard>();
      if (!guard.developerModeEnabled) return;
      if (!guard.countdownRunning) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _ticker = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final guard = context.watch<TypeAutoTransitionGuard>();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.component;
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return Positioned(
      top: 10,
      right: 10,
      child: SafeArea(
        child: IgnorePointer(
          child: AnimatedSwitcher(
            duration: duration,
            switchInCurve: CommonUiMotion.enter,
            switchOutCurve: CommonUiMotion.exit,
            transitionBuilder: (child, animation) {
              final curved = CurvedAnimation(
                parent: animation,
                curve: CommonUiMotion.enter,
                reverseCurve: CommonUiMotion.exit,
              );
              return FadeTransition(
                opacity: curved,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
                  alignment: Alignment.topRight,
                  child: child,
                ),
              );
            },
            child: !guard.developerModeEnabled
                ? const SizedBox.shrink(
                    key: ValueKey<String>('auto-debug-hidden'),
                  )
                : Container(
                    key: const ValueKey<String>('auto-debug-visible'),
                    width: 178,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: tokens.surfaceRaised.withOpacity(0.94),
                      borderRadius: BorderRadius.circular(CommonUiShapes.card),
                      border: Border.all(color: tokens.borderSubtle),
                      boxShadow: [
                        BoxShadow(
                          color: tokens.shadow,
                          blurRadius: 14,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: _TypeAutoTransitionDebugContent(
                      guard: guard,
                      textTheme: textTheme,
                      accent: tokens.accent,
                      foreground: tokens.textPrimary,
                      secondary: tokens.textSecondary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

class _TypeAutoTransitionDebugContent extends StatefulWidget {
  const _TypeAutoTransitionDebugContent({
    required this.guard,
    required this.textTheme,
    required this.accent,
    required this.foreground,
    required this.secondary,
  });

  final TypeAutoTransitionGuard guard;
  final TextTheme textTheme;
  final Color accent;
  final Color foreground;
  final Color secondary;

  @override
  State<_TypeAutoTransitionDebugContent> createState() =>
      _TypeAutoTransitionDebugContentState();
}

class _TypeAutoTransitionDebugContentState
    extends State<_TypeAutoTransitionDebugContent> {
  String? _lastVisualState;
  int _visualStateRevision = 0;

  ValueKey<String> _visualStateKey(String state) {
    if (_lastVisualState != state) {
      _lastVisualState = state;
      _visualStateRevision += 1;
    }
    return ValueKey<String>('status-$state-$_visualStateRevision');
  }

  @override
  Widget build(BuildContext context) {
    final guard = widget.guard;
    final running = guard.countdownRunning;
    final blocked = guard.isBlocked;
    final remainingSeconds = guard.remaining.inMilliseconds / 1000;
    final visualState = running
        ? 'running'
        : blocked
            ? 'blocked'
            : 'disabled';
    final visualStateKey = _visualStateKey(visualState);
    final title = running
        ? 'STATUS ${remainingSeconds.toStringAsFixed(1)}s'
        : blocked
            ? 'STATUS PAUSE'
            : 'STATUS OFF';
    final detail = blocked
        ? guard.blockReason ?? '작업 중'
        : guard.countdownEnabled
            ? '전환 대기'
            : guard.disabledReason;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSwitcher(
          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
              ? Duration.zero
              : CommonUiMotion.selection,
          child: Row(
            key: visualStateKey,
            children: [
              Icon(
                running
                    ? Icons.timer_outlined
                    : blocked
                        ? Icons.pause_circle_outline_rounded
                        : Icons.stop_circle_outlined,
                size: 17,
                color: running ? widget.accent : widget.secondary,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      (widget.textTheme.labelLarge ?? const TextStyle()).copyWith(
                    color: widget.foreground,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            minHeight: 5,
            value: running ? guard.progress : 0,
            backgroundColor: widget.secondary.withOpacity(0.18),
            valueColor: AlwaysStoppedAnimation<Color>(widget.accent),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          detail,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: (widget.textTheme.labelSmall ?? const TextStyle()).copyWith(
            color: widget.secondary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class TypePageParkingCompletedControlBar<PgState extends ChangeNotifier>
    extends StatelessWidget {
  const TypePageParkingCompletedControlBar({
    super.key,
    required this.builder,
  });

  final TypePageParkingCompletedControlBarBuilder<PgState> builder;

  @override
  Widget build(BuildContext context) {
    final pageState = context.read<PgState>();
    return builder(context, pageState);
  }
}

class TypePageEntryDashboardBar<PState, PgState extends ChangeNotifier>
    extends StatelessWidget {
  const TypePageEntryDashboardBar({
    super.key,
    required this.config,
  });

  final TypePageConfig<PState, PgState> config;

  Future<void> _openDashboard(BuildContext context) async {
    final guard = context.read<TypeAutoTransitionGuard>();
    await guard.runBlocked<void>(
      '대시보드',
      () async {
        final screen = config.debugMeta['screen']?.toString() ?? 'type_page';
        debugPrint('[TypePageDashboardSideDock] open screen=$screen direction=right_to_left');
        final result = await showCommonRightSideDock<SecondaryDockRequest>(
          context: context,
          barrierLabel: '대시보드',
          builder: (_) => config.buildDashboardSideDock(),
        );
        debugPrint(
          '[TypePageDashboardSideDock] closed screen=$screen result=${result?.name ?? 'none'}',
        );
        if (result == SecondaryDockRequest.open && context.mounted) {
          debugPrint(
            '[TypePageDashboardSideDock] secondary_open screen=$screen',
          );
          await showSecondarySideDock<void>(
            context: context,
            barrierLabel: '운영 관리',
          );
          debugPrint(
            '[TypePageDashboardSideDock] secondary_closed screen=$screen',
          );
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          Expanded(
            child: TypePageOpenEntryButton<PState, PgState>(config: config),
          ),
          const SizedBox(width: 8),
          const Expanded(child: TypePageSortButton()),
          const SizedBox(width: 8),
          Expanded(
            child: CommonButton(
              label: '대시보드',
              icon: Icons.dashboard_rounded,
              onPressed: () => _openDashboard(context),
              expand: true,
              minHeight: 48,
              haptic: CommonHaptic.selection,
            ),
          ),
        ],
      ),
    );
  }
}

class TypePageSortButton extends StatelessWidget {
  const TypePageSortButton({super.key});

  Future<void> _togglePriority(
    BuildContext context,
    RealTimeSortState state,
  ) async {
    final guard = context.read<TypeAutoTransitionGuard>();
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final before = state.priorityLabel;
    final target = state.isZonePriority ? '정렬' : '구역';
    state.togglePriority(reason: 'type_page_bottom_button');
    final after = state.priorityLabel;
    final blockedBySupport = target == '구역' && !state.locationSupported;
    debugPrint(
      '[TypePagePriority] source=bottom_button before=$before target=$target after=$after priority=${state.priorityMode.name} order=${state.timeOrderLabel} zoneSupported=${state.locationSupported} zoneBlocked=$blockedBySupport',
    );
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: '실시간 보기 전환',
      initialMessage:
          'source=type_page_bottom_button before=$before target=$target after=$after zoneSupported=${state.locationSupported}',
      useCommonUi: true,
      showDialogImmediately: false,
      developerModeMessage: '개발자 모드 ON: 전환 상태를 Status Dialog에서 확인할 수 있습니다.',
      standardModeMessage: '일반 모드: 중앙 버튼 한 번으로 보기를 즉시 전환합니다.',
    );
    if (!context.mounted) return;
    trace.log(
      'after=$after priority=${state.priorityMode.name} mode=${state.mode.name} order=${state.timeOrderLabel} parent=${state.parent.isEmpty ? '-' : state.parent} child=${state.child.isEmpty ? '-' : state.child} selectedLocation=${state.selectedLocation} zoneSupported=${state.locationSupported} zoneBlocked=$blockedBySupport reducedMotion=$reduceMotion',
      progress: .82,
    );
    await trace.succeed(
      blockedBySupport
          ? '구역 미지원 탭이므로 정렬 보기를 유지했습니다.'
          : '$after 보기로 즉시 전환했습니다.',
    );
    if (!context.mounted || !trace.developerMode) return;
    await guard.runBlocked<void>(
      '실시간 보기 전환 개발자 상태',
      () => trace.showStatusDialog(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<RealTimeSortState>();
    final zone = state.isZonePriority;
    final label = state.priorityLabel;
    final compact = MediaQuery.sizeOf(context).width < 370;
    final semantics = zone
        ? '$label 보기 · 부모 주차 구역'
        : '$label 보기 · ${state.timeOrderLabel}';
    return Semantics(
      button: true,
      selected: zone,
      label: semantics,
      child: Tooltip(
        message: semantics,
        child: CommonButton(
          label: label,
          icon: compact
              ? null
              : zone
                  ? Icons.grid_view_rounded
                  : Icons.sort_rounded,
          onPressed: () => _togglePriority(context, state),
          variant: CommonButtonVariant.secondary,
          selected: zone,
          expand: true,
          minHeight: 48,
          haptic: CommonHaptic.selection,
        ),
      ),
    );
  }
}

class TypePageOpenEntryButton<PState, PgState extends ChangeNotifier>
    extends StatelessWidget {
  const TypePageOpenEntryButton({
    super.key,
    required this.config,
  });

  final TypePageConfig<PState, PgState> config;

  void _trace(BuildContext context) {
    DebugActionRecorder.instance.recordAction(
      '입차 화면 열기 버튼',
      route: ModalRoute.of(context)?.settings.name,
      meta: <String, dynamic>{...config.debugMeta},
    );
  }

  Future<void> _openEntryScreen(BuildContext context) async {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    await Navigator.of(context).push<dynamic>(
      buildTypePageSlideRoute<dynamic>(
        CommonUiScope(child: config.buildInputScreen()),
        fromLeft: true,
        reduceMotion: reduceMotion,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonButton(
      label: '입차',
      icon: Icons.add_circle_outline_rounded,
      onPressed: () async {
        _trace(context);
        final guard = context.read<TypeAutoTransitionGuard>();
        await guard.runBlocked<void>(
          '입차 화면',
          () => _openEntryScreen(context),
        );
      },
      variant: CommonButtonVariant.secondary,
      expand: true,
      minHeight: 48,
      haptic: CommonHaptic.selection,
    );
  }
}

class TypePageModeSwitchBar extends StatelessWidget {
  const TypePageModeSwitchBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final mode = context.watch<TypeViewModeState>().mode;
    final isTable = mode == TypeViewMode.table;
    final label = isTable ? '테이블 보기' : '현황 보기';
    final icon = isTable ? Icons.table_rows_rounded : Icons.grid_view_rounded;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 7, 12, 8),
        child: CommonButton(
          label: label,
          icon: icon,
          onPressed: () => context.read<TypeViewModeState>().toggle(),
          variant: CommonButtonVariant.tertiary,
          selected: isTable,
          expand: true,
          minHeight: 44,
          haptic: CommonHaptic.selection,
        ),
      ),
    );
  }
}

class TypePageRefreshableBody<PState, PgState extends ChangeNotifier>
    extends StatelessWidget {
  const TypePageRefreshableBody({
    super.key,
    required this.config,
  });

  final TypePageConfig<PState, PgState> config;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Consumer2<PgState, PState>(
      builder: (context, pageState, plateState, _) {
        final loading = config.isLoading(plateState);
        return Stack(
          children: [
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
              switchInCurve: CommonUiMotion.enter,
              switchOutCurve: CommonUiMotion.exit,
              child: KeyedSubtree(
                key: ValueKey<int>(pageState.hashCode),
                child: config.buildCurrentPage(context, pageState),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                ignoring: !loading,
                child: AnimatedOpacity(
                  opacity: loading ? 1 : 0,
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  curve: CommonUiMotion.standard,
                  child: ColoredBox(
                    color: tokens.scrim,
                    child: Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: tokens.surfaceRaised,
                          borderRadius:
                              BorderRadius.circular(CommonUiShapes.card),
                          border: Border.all(color: tokens.borderSubtle),
                          boxShadow: [
                            BoxShadow(
                              color: tokens.shadow,
                              blurRadius: 18,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: SizedBox(
                          width: 26,
                          height: 26,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.8,
                            color: tokens.accent,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

PageRouteBuilder<T> buildTypePageSlideRoute<T>(
  Widget page, {
  required bool fromLeft,
  bool reduceMotion = false,
}) {
  final duration = reduceMotion ? Duration.zero : CommonUiMotion.layout;
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: CommonUiMotion.enter,
        reverseCurve: CommonUiMotion.exit,
      );
      final position = Tween<Offset>(
        begin: Offset(fromLeft ? -0.08 : 0.08, 0),
        end: Offset.zero,
      ).animate(curved);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(position: position, child: child),
      );
    },
  );
}
