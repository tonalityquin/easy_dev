import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/models/capability.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../features/account/applications/user_state.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/dev/debug/debug_action_recorder.dart';
import '../../../../features/voice/application/voice_appbar_ui_state.dart';
import '../../../../features/voice/controllers/voice_runtime_controller.dart';
import '../../../plate/application/common/driving_recovery_gate.dart';
import '../../../plate/domain/enums/plate_type.dart';
import '../../../plate/domain/repositories/plate_repository.dart';
import '../../../tts/application/plate_tts_event_hub.dart';
import '../../../tts/services/page/tts_view_refresh_service.dart';
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
    required this.buildDashboardBottomSheet,
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
  final Widget Function() buildDashboardBottomSheet;
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
  final VoiceRuntimeController _talkController =
      VoiceRuntimeController.instance;
  final VoiceAppbarUiState _talkUiState = VoiceAppbarUiState();

  StreamSubscription<PlateTtsEvent>? _ttsEventSub;
  Timer? _ttsDebounceTimer;
  bool _pendingFull = false;
  bool _pendingDepartureOnly = false;
  String _pendingArea = '';
  bool _syncingTalkRuntime = false;
  String _boundTalkArea = '';
  String _boundTalkUserId = '';

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final plateState = context.read<PState>();
      widget.config.enableForTypePages(plateState);

      PlateTtsEventHub.ensureStarted();
      _ttsEventSub ??= PlateTtsEventHub.stream.listen(_onTtsEvent);
      await _syncWorkintalkinRuntime(force: true);
    });
  }

  String _resolveTalkArea() {
    final currentArea = context.read<AreaState>().currentArea.trim();
    if (currentArea.isNotEmpty) {
      return currentArea;
    }
    return context.read<UserState>().currentArea.trim();
  }

  Future<void> _syncWorkintalkinRuntime({bool force = false}) async {
    if (_syncingTalkRuntime || !mounted) {
      return;
    }
    final session = context.read<UserState>().session;
    final area = _resolveTalkArea();
    if (session == null || area.isEmpty) {
      _boundTalkArea = '';
      _boundTalkUserId = '';
      await _talkController.stop();
      return;
    }
    final alreadyBound = !force &&
        _boundTalkArea == area &&
        _boundTalkUserId == session.id &&
        _talkController.active;
    if (alreadyBound) {
      return;
    }
    _syncingTalkRuntime = true;
    try {
      await _talkController.start(session: session, areaName: area);
      _boundTalkArea = area;
      _boundTalkUserId = session.id;
    } finally {
      _syncingTalkRuntime = false;
    }
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
    unawaited(_talkController.stop());
    _talkUiState.dispose();

    try {
      final plateState = context.read<PState>();
      widget.config.disableAll(plateState);
    } catch (_) {}

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final activeSession = context.watch<UserState>().session;
    final currentArea = context.watch<AreaState>().currentArea.trim();
    final fallbackArea = context.watch<UserState>().currentArea.trim();
    final normalizedArea = currentArea.isNotEmpty ? currentArea : fallbackArea;
    final currentUserId = activeSession?.id ?? '';
    final canUseTalkUi = context
        .watch<AreaState>()
        .capabilitiesOfCurrentArea
        .contains(Capability.record);

    if (!canUseTalkUi && _talkUiState.enabled) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _talkUiState.setEnabled(false);
      });
    }

    final shouldResync = activeSession != null &&
        normalizedArea.isNotEmpty &&
        (_boundTalkArea != normalizedArea || _boundTalkUserId != currentUserId);
    if (shouldResync && !_syncingTalkRuntime) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncWorkintalkinRuntime();
      });
    }

    if (activeSession == null &&
        _talkController.active &&
        !_syncingTalkRuntime) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _syncWorkintalkinRuntime(force: true);
      });
    }

    return PromptUiScope(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<TypeViewModeState>(
            create: (_) => TypeViewModeState(),
          ),
          ChangeNotifierProvider<VoiceAppbarUiState>.value(
            value: _talkUiState,
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
            final tokens = PromptUiTheme.of(context);
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
                  await widget.config.clearCurrentSelection(
                    plateState,
                    pageState,
                    userName,
                    (msg) => debugPrint(msg),
                  );
                },
                child: Scaffold(
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
              ),
            );
          },
        ),
      ),
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
    await showPromptOverlayBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      transparentBackground: true,
      builder: (_) => config.buildDashboardBottomSheet(),
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
          const Expanded(child: TypePageToggleTalkAppBarButton()),
          const SizedBox(width: 8),
          Expanded(
            child: PromptButton(
              label: '대시보드',
              icon: Icons.dashboard_rounded,
              onPressed: () => _openDashboard(context),
              expand: true,
              minHeight: 48,
              haptic: PromptHaptic.selection,
            ),
          ),
        ],
      ),
    );
  }
}

class TypePageToggleTalkAppBarButton extends StatelessWidget {
  const TypePageToggleTalkAppBarButton({super.key});

  @override
  Widget build(BuildContext context) {
    final areaCaps = context.watch<AreaState>().capabilitiesOfCurrentArea;
    final canUseRecordTalk = areaCaps.contains(Capability.record);
    final enabled = context.watch<VoiceAppbarUiState>().enabled;
    final label = canUseRecordTalk
        ? enabled
            ? 'OFF'
            : 'ON'
        : '비활성';
    final icon = canUseRecordTalk
        ? enabled
            ? Icons.toggle_on_rounded
            : Icons.toggle_off_rounded
        : Icons.mic_off_rounded;

    return PromptButton(
      label: label,
      icon: icon,
      onPressed: canUseRecordTalk
          ? () => context.read<VoiceAppbarUiState>().toggle()
          : null,
      variant: enabled && canUseRecordTalk
          ? PromptButtonVariant.primary
          : PromptButtonVariant.secondary,
      selected: enabled && canUseRecordTalk,
      expand: true,
      minHeight: 48,
      haptic: PromptHaptic.selection,
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
        PromptUiScope(child: config.buildInputScreen()),
        fromLeft: true,
        reduceMotion: reduceMotion,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PromptButton(
      label: '입차',
      icon: Icons.add_circle_outline_rounded,
      onPressed: () async {
        _trace(context);
        await _openEntryScreen(context);
      },
      variant: PromptButtonVariant.secondary,
      expand: true,
      minHeight: 48,
      haptic: PromptHaptic.selection,
    );
  }
}

class TypePageModeSwitchBar extends StatelessWidget {
  const TypePageModeSwitchBar({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
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
        child: PromptButton(
          label: label,
          icon: icon,
          onPressed: () => context.read<TypeViewModeState>().toggle(),
          variant: PromptButtonVariant.tertiary,
          selected: isTable,
          expand: true,
          minHeight: 44,
          haptic: PromptHaptic.selection,
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
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Consumer2<PgState, PState>(
      builder: (context, pageState, plateState, _) {
        final loading = config.isLoading(plateState);
        return Stack(
          children: [
            AnimatedSwitcher(
              duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
              switchInCurve: PromptUiMotion.enter,
              switchOutCurve: PromptUiMotion.exit,
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
                      reduceMotion ? Duration.zero : PromptUiMotion.selection,
                  curve: PromptUiMotion.standard,
                  child: ColoredBox(
                    color: tokens.scrim,
                    child: Center(
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: tokens.surfaceRaised,
                          borderRadius:
                              BorderRadius.circular(PromptUiShapes.card),
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
  final duration = reduceMotion ? Duration.zero : PromptUiMotion.layout;
  return PageRouteBuilder<T>(
    transitionDuration: duration,
    reverseTransitionDuration: duration,
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      if (reduceMotion) return child;
      final curved = CurvedAnimation(
        parent: animation,
        curve: PromptUiMotion.enter,
        reverseCurve: PromptUiMotion.exit,
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
