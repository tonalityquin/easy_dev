import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/models/capability.dart';
import '../../../features/account/applications/user_state.dart';
import '../../../features/dev/application/area_state.dart';
import '../../../features/dev/debug/debug_action_recorder.dart';
import '../../../features/plate/domain/enums/plate_type.dart';
import '../../../features/plate/domain/repositories/plate_repository.dart';
import '../../../features/voice/application/voice_appbar_ui_state.dart';
import '../../../features/voice/controllers/voice_runtime_controller.dart';
import '../../../services/driving_recovery/driving_recovery_gate.dart';
import '../../../shared/page/application/common/type_view_mode_state.dart';
import '../../../utils/tts/plate_tts_event_hub.dart';
import '../../../utils/view_refresh/tts_view_refresh_service.dart';
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
        if (!mounted) {
          return;
        }
        _talkUiState.setEnabled(false);
      });
    }
    final shouldResync = activeSession != null &&
        normalizedArea.isNotEmpty &&
        (_boundTalkArea != normalizedArea || _boundTalkUserId != currentUserId);
    if (shouldResync && !_syncingTalkRuntime) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _syncWorkintalkinRuntime();
      });
    }
    if (activeSession == null &&
        _talkController.active &&
        !_syncingTalkRuntime) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _syncWorkintalkinRuntime(force: true);
      });
    }

    return MultiProvider(
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

          final refreshableBody = TypePageRefreshableBody<PState, PgState>(
            config: widget.config,
          );

          final body = widget.config.recoveryMode == null
              ? refreshableBody
              : DrivingRecoveryGate(
                  mode: widget.config.recoveryMode!,
                  child: refreshableBody,
                );

          return PopScope(
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
              body: body,
              bottomNavigationBar: SafeArea(
                top: false,
                child: TypePageBottomBars(
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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: TypePageOpenEntryButton<PState, PgState>(config: config),
          ),
          const SizedBox(width: 8),
          const Expanded(
            child: TypePageToggleTalkAppBarButton(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  useSafeArea: true,
                  backgroundColor: Colors.transparent,
                  builder: (_) => config.buildDashboardBottomSheet(),
                );
              },
              style: TypePageBrand.filledPrimaryButtonStyle(
                context,
                minHeight: 48,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.dashboard, size: 20),
                  SizedBox(width: 6),
                  Text('대시보드', style: TextStyle(fontWeight: FontWeight.w900)),
                ],
              ),
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
    final label =
        canUseRecordTalk ? (enabled ? '무전기 OFF' : '무전기 ON') : '무전기 비활성';
    final icon = canUseRecordTalk
        ? (enabled ? Icons.toggle_on_rounded : Icons.toggle_off_rounded)
        : Icons.mic_off_rounded;
    final onPressed = canUseRecordTalk
        ? () {
            context.read<VoiceAppbarUiState>().toggle();
          }
        : null;

    final buttonStyle = enabled && canUseRecordTalk
        ? TypePageBrand.filledPrimaryButtonStyle(
            context,
            minHeight: 48,
          )
        : TypePageBrand.outlinedSurfaceButtonStyle(
            context,
            minHeight: 48,
          );

    return ElevatedButton(
      onPressed: onPressed,
      style: buttonStyle,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 22),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
            ),
          ),
        ],
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
    await Navigator.of(context).push<dynamic>(
      buildTypePageSlideRoute<dynamic>(
        config.buildInputScreen(),
        fromLeft: true,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ElevatedButton(
      onPressed: () async {
        _trace(context);
        await _openEntryScreen(context);
      },
      style: TypePageBrand.outlinedSurfaceButtonStyle(
        context,
        minHeight: 48,
        borderColor: cs.primary.withOpacity(0.35),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.add_circle_outline, size: 20, color: cs.primary),
          const SizedBox(width: 8),
          Text(
            '입차',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 13,
              color: cs.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class TypePageModeSwitchBar extends StatelessWidget {
  const TypePageModeSwitchBar({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final mode = context.watch<TypeViewModeState>().mode;
    final label = mode == TypeViewMode.table ? '테이블' : '현황';
    final icon = mode == TypeViewMode.table
        ? Icons.table_rows_rounded
        : Icons.grid_view_rounded;

    return SizedBox(
      height: kBottomNavigationBarHeight,
      child: Material(
        color: cs.surface,
        child: InkWell(
          onTap: () => context.read<TypeViewModeState>().toggle(),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: TypePageBrand.border(cs)),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: cs.onSurfaceVariant.withOpacity(0.7),
                ),
                const SizedBox(width: 10),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      '모드 전환',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: cs.outline,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant.withOpacity(0.75),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.swap_horiz_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant.withOpacity(0.55),
                ),
              ],
            ),
          ),
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
    final cs = Theme.of(context).colorScheme;

    return Consumer2<PgState, PState>(
      builder: (context, pageState, plateState, _) {
        return Stack(
          children: [
            config.buildCurrentPage(context, pageState),
            if (config.isLoading(plateState))
              Container(
                color: cs.surface.withOpacity(.35),
                child: Center(
                  child: SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
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

class TypePageBrand {
  static Color border(ColorScheme cs) => cs.outlineVariant.withOpacity(0.85);

  static Color overlayOnSurface(ColorScheme cs) =>
      cs.outlineVariant.withOpacity(0.12);

  static ButtonStyle outlinedSurfaceButtonStyle(
    BuildContext context, {
    double minHeight = 48,
    Color? borderColor,
  }) {
    final cs = Theme.of(context).colorScheme;
    final bc = borderColor ?? border(cs);

    return ElevatedButton.styleFrom(
      backgroundColor: cs.surface,
      foregroundColor: cs.onSurface,
      minimumSize: Size.fromHeight(minHeight),
      padding: EdgeInsets.zero,
      elevation: 0,
      side: BorderSide(color: bc, width: 1.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
        (states) => states.contains(MaterialState.pressed)
            ? overlayOnSurface(cs)
            : null,
      ),
    );
  }

  static ButtonStyle filledPrimaryButtonStyle(
    BuildContext context, {
    double minHeight = 48,
  }) {
    final cs = Theme.of(context).colorScheme;

    return ElevatedButton.styleFrom(
      backgroundColor: cs.primary,
      foregroundColor: cs.onPrimary,
      minimumSize: Size.fromHeight(minHeight),
      padding: EdgeInsets.zero,
      elevation: 2,
      shadowColor: cs.shadow.withOpacity(0.20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ).copyWith(
      overlayColor: MaterialStateProperty.resolveWith<Color?>(
        (states) => states.contains(MaterialState.pressed)
            ? cs.onPrimary.withOpacity(0.12)
            : null,
      ),
    );
  }
}

PageRouteBuilder<T> buildTypePageSlideRoute<T>(
  Widget page, {
  required bool fromLeft,
}) {
  return PageRouteBuilder<T>(
    transitionDuration: const Duration(milliseconds: 300),
    pageBuilder: (_, __, ___) => page,
    transitionsBuilder: (_, animation, __, child) {
      final begin = Offset(fromLeft ? -1.0 : 1.0, 0);
      final end = Offset.zero;
      final tween = Tween(begin: begin, end: end).chain(
        CurveTween(curve: Curves.easeInOut),
      );
      return SlideTransition(position: animation.drive(tween), child: child);
    },
  );
}
