import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/common_ui/common_ui_side_dock.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dashboard/side_docks/common/dashboard_business_action_runner.dart';
import '../../../../features/dashboard/side_docks/common/dashboard_dock_request.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/dev/debug/debug_action_recorder.dart';
import '../../../../app/utils/developer_operation_status_dialog.dart';
import '../../../secondary/side_docks/secondary_side_dock.dart';
import '../../../plate/application/common/driving_recovery_gate.dart';
import '../../../plate/domain/enums/plate_type.dart';
import '../../../plate/domain/repositories/plate_repository.dart';
import '../../../tts/application/plate_tts_event_hub.dart';
import '../../../tts/services/page/tts_view_refresh_service.dart';
import '../../../real_time_table/real_time_sort_state.dart';
import '../../application/common/type_auto_transition_guard.dart';
import '../../application/common/type_page_quick_action_scope.dart';
import '../../application/common/type_view_mode_state.dart';

typedef TypePageCurrentPageBuilder<PgState extends ChangeNotifier> = Widget
    Function(BuildContext context, PgState pageState);
typedef TypePageSearchAction<PgState extends ChangeNotifier> = Future<void>
    Function(BuildContext context, PgState pageState);
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

class TypePageEntryLaunchData {
  const TypePageEntryLaunchData({
    required this.sourceRect,
    required this.presentationController,
  });

  final Rect sourceRect;
  final CommonSideDockPresentationController presentationController;
}

class TypePageConfig<PState, PgState extends ChangeNotifier> {
  TypePageConfig({
    required this.createPageState,
    required this.enableForTypePages,
    required this.disableAll,
    required this.isLoading,
    required this.clearCurrentSelection,
    required this.buildCurrentPage,
    required this.openSearch,
    required this.buildDepartureCompletedSheet,
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
  final TypePageSearchAction<PgState> openSearch;
  final Widget Function() buildDepartureCompletedSheet;
  final Widget Function() buildDashboardSideDock;
  final Widget Function(TypePageEntryLaunchData launch) buildInputScreen;
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


  Future<void> _runQuickAction(
    BuildContext context, {
    required String label,
    required String actionId,
    required Future<void> Function() action,
  }) async {
    final guard = context.read<TypeAutoTransitionGuard>();
    final screen = widget.config.debugMeta['screen']?.toString() ?? 'type_page';
    final trace = await DeveloperOperationTrace.start(
      context: context,
      title: 'TypePage Quick Action · $label',
      initialMessage: '$label 실행을 준비합니다.',
      useCommonUi: true,
      developerModeMessage: '개발자 모드 ON: debugPrint 코드를 복사할 수 있습니다.',
      standardModeMessage: '개발자 모드 OFF',
      showDialogImmediately: false,
    );
    trace.log('action=$actionId screen=$screen source=fixed_quick_actions', progress: 0.08);

    Object? caughtError;
    StackTrace? caughtStackTrace;

    try {
      await guard.runBlocked<void>(label, () async {
        trace.log('blocked_start action=$actionId', progress: 0.2);
        await action();
        trace.log('action_return action=$actionId', progress: 0.88);
      });
      await trace.succeed('$label 실행을 종료했습니다.');
    } catch (error, stackTrace) {
      caughtError = error;
      caughtStackTrace = stackTrace;
      await trace.fail(
        '$label 실행 중 오류가 발생했습니다.',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (trace.developerMode && context.mounted) {
      await trace.showStatusDialog(context);
    }

    if (caughtError != null && caughtStackTrace != null) {
      Error.throwWithStackTrace(caughtError, caughtStackTrace);
    }
  }

  Future<void> _openDashboardFlow(BuildContext context) async {
    final screen = widget.config.debugMeta['screen']?.toString() ?? 'type_page';
    debugPrint(
      '[TypePageDashboardSideDock] open screen=$screen direction=right_to_left',
    );
    final result = await showCommonRightSideDock<DashboardDockRequest>(
      context: context,
      barrierLabel: '대시보드',
      builder: (_) => widget.config.buildDashboardSideDock(),
    );
    debugPrint(
      '[TypePageDashboardSideDock] closed screen=$screen result=${result?.name ?? 'none'}',
    );
    if (!context.mounted || result == null) return;

    switch (result) {
      case DashboardDockRequest.secondary:
        debugPrint('[TypePageDashboardSideDock] secondary_open screen=$screen');
        await showSecondarySideDock<void>(
          context: context,
          barrierLabel: '운영 관리',
        );
        debugPrint('[TypePageDashboardSideDock] secondary_closed screen=$screen');
        return;
      case DashboardDockRequest.monthlyParking:
      case DashboardDockRequest.departureCompleted:
        await DashboardBusinessActionRunner.run(
          context: context,
          request: result,
          buildDepartureCompletedSheet: widget.config.buildDepartureCompletedSheet,
          debugMeta: widget.config.debugMeta,
        );
        return;
    }
  }

  Future<void> _openEntryFlow(BuildContext context, Rect sourceRect) async {
    DebugActionRecorder.instance.recordAction(
      '입차 화면 열기',
      route: ModalRoute.of(context)?.settings.name,
      meta: <String, dynamic>{...widget.config.debugMeta},
    );
    final presentationController =
        CommonSideDockPresentationController(visible: false);
    debugPrint(
      '[TypePageEntryFlow] ocr_first sourceRect=${sourceRect.left.toStringAsFixed(1)},${sourceRect.top.toStringAsFixed(1)},${sourceRect.width.toStringAsFixed(1)},${sourceRect.height.toStringAsFixed(1)}',
    );
    try {
      await showCommonRightSideDock<dynamic>(
        context: context,
        barrierLabel: '차량 등록',
        maxWidth: 360,
        widthFactor: .92,
        barrierDismissible: false,
        presentationController: presentationController,
        builder: (dockContext) => CommonUiScope(
          child: widget.config.buildInputScreen(
            TypePageEntryLaunchData(
              sourceRect: sourceRect,
              presentationController: presentationController,
            ),
          ),
        ),
      );
    } finally {
      presentationController.dispose();
    }
  }

  Future<void> _openSearchFlow(BuildContext context) async {
    final pageState = context.read<PgState>();
    await widget.config.openSearch(context, pageState);
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
                        body: TypePageQuickActionScope(
                          openEntry: (sourceRect) => _runQuickAction(
                            context,
                            label: '입차 화면',
                            actionId: 'entry',
                            action: () => _openEntryFlow(context, sourceRect),
                          ),
                          openSearch: () => _runQuickAction(
                            context,
                            label: '검색',
                            actionId: 'search',
                            action: () => _openSearchFlow(context),
                          ),
                          openDashboard: () => _runQuickAction(
                            context,
                            label: '대시보드',
                            actionId: 'dashboard',
                            action: () => _openDashboardFlow(context),
                          ),
                          child: body,
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
