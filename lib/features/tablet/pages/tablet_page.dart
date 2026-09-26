import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../../shared/plate/domain/enums/plate_type.dart';
import '../../../shared/tts/application/plate_tts_event_hub.dart';
import '../../dev/application/area_state.dart';
import '../applications/tablet_debug_trace.dart';
import '../applications/tablet_grid_render_mode_state.dart';
import '../applications/tablet_pad_mode_state.dart';
import '../applications/tablet_parking_completed_view_toggle_state.dart';
import '../applications/tablet_plate_tail4_size_state.dart';
import '../applications/tablet_side_dock_state.dart';
import '../applications/tablet_work_session_state.dart';
import 'panels/tablet_left_panel.dart';
import 'panels/tablet_right_panel.dart';
import 'sheets/widgets/tablet_grid_mode_page.dart';
import 'sheets/widgets/tablet_grid_pad_mode_page.dart';
import 'widgets/tablet_common_components.dart';
import 'widgets/tablet_mode_rail.dart';

class TabletPage extends StatefulWidget {
  const TabletPage({super.key});

  @override
  State<TabletPage> createState() => _TabletPageState();
}

class _TabletPageState extends State<TabletPage> {
  static const int _maxCompletedNoticeCount = 30;

  final List<TabletCompletedDepartureNotice> _completedNotices =
      <TabletCompletedDepartureNotice>[];
  String? _areaCache;
  StreamSubscription<PlateTtsEvent>? _ttsEventSub;

  void _addCompletedNotice(PlateTtsEvent event) {
    final docId = event.docId.trim();
    final tail4 = _tail4Digits(event.plateNumber);
    if (docId.isEmpty || tail4.isEmpty) return;
    final timestampMs = event.timestampMs;
    final completedAt = timestampMs > 0
        ? DateTime.fromMillisecondsSinceEpoch(timestampMs)
        : DateTime.now();
    final notice = TabletCompletedDepartureNotice(
      docId: docId,
      tail4: tail4,
      completedAt: completedAt,
    );
    TabletDebugTrace.record(
      'TabletPage',
      'departure_completed_notice',
      <String, Object?>{
        'docId': docId,
        'tail4': tail4,
        'completedAt': completedAt.toIso8601String(),
      },
    );
    setState(() {
      _completedNotices.removeWhere((item) => item.docId == docId);
      _completedNotices.insert(0, notice);
      if (_completedNotices.length > _maxCompletedNoticeCount) {
        _completedNotices.removeRange(
          _maxCompletedNoticeCount,
          _completedNotices.length,
        );
      }
    });
  }

  void _clearCompletedNoticesForAreaChange() {
    setState(_completedNotices.clear);
  }

  void _openSideDock() {
    HapticFeedback.selectionClick();
    final mode = context.read<TabletPadModeState>().mode;
    TabletDebugTrace.record(
      'TabletSideDock',
      'open_requested',
      <String, Object?>{
        'source': 'edge_tap',
        'mode': mode.name,
      },
    );
    unawaited(
      context.read<TabletSideDockState>().open(
            source: 'edge_tap',
          ),
    );
  }

  @override
  void initState() {
    super.initState();
    TabletDebugTrace.clear();
    TabletDebugTrace.record('TabletPage', 'initialized');
    context.read<TabletParkingCompletedViewToggleState>().reset();
    context.read<TabletPlateTail4SizeState>().reset();
    context.read<TabletGridRenderModeState>().reset();
    TabletDebugTrace.record(
      'TabletPage',
      'session_defaults_applied',
      <String, Object?>{
        'parkingCompletedSubscription': false,
        'plateTail4Size': 32,
        'gridRenderMode': 'twoD',
      },
    );
    PlateTtsEventHub.ensureStarted();
    _ttsEventSub = PlateTtsEventHub.stream.listen((event) {
      final currentArea = context.read<AreaState>().currentArea.trim();
      if (currentArea.isEmpty || event.area.trim() != currentArea) return;
      if (event.type == PlateType.departureCompleted.firestoreValue) {
        _addCompletedNotice(event);
      }
    });
  }

  @override
  void dispose() {
    _ttsEventSub?.cancel();
    _ttsEventSub = null;
    TabletDebugTrace.record('TabletPage', 'disposed');
    super.dispose();
  }

  Widget _buildModeContent({
    required BuildContext context,
    required PadMode padMode,
    required String area,
  }) {
    final tokens = CommonUiTheme.of(context);
    switch (padMode) {
      case PadMode.gridPad:
        return TabletGridPadModePage(
          key: ValueKey<String>('grid-pad-pane-$area'),
          area: area,
        );
      case PadMode.grid:
        return TabletGridModePage(
          key: ValueKey<String>('grid-pane-$area'),
          area: area,
        );
      case PadMode.show:
        return ColoredBox(
          key: ValueKey<String>('show-pane-$area'),
          color: tokens.canvas,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: LeftPaneDeparturePlates(
              key: ValueKey<String>('left-pane-$area-show'),
              completedNotices: _completedNotices,
            ),
          ),
        );
      case PadMode.mobile:
        return ColoredBox(
          key: ValueKey<String>('mobile-pane-$area'),
          color: tokens.surface,
          child: RightPaneSearchPanel(
            key: ValueKey<String>('mobile-search-$area'),
            area: area,
          ),
        );
      case PadMode.big:
      case PadMode.small:
        return Row(
          key: ValueKey<String>('split-${padMode.name}-$area'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: ColoredBox(
                color: tokens.canvas,
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: LeftPaneDeparturePlates(
                    key: ValueKey<String>('left-pane-$area'),
                    completedNotices: _completedNotices,
                  ),
                ),
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: tokens.borderSubtle,
            ),
            Expanded(
              child: ColoredBox(
                color: tokens.surface,
                child: RightPaneSearchPanel(
                  key: ValueKey<String>('right-pane-$area'),
                  area: area,
                ),
              ),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          final area =
              context.select<AreaState, String?>((state) => state.currentArea) ??
                  '';
          final padMode =
              context.select<TabletPadModeState, PadMode>((state) => state.mode);
          final workState = context.watch<TabletWorkSessionState>();
          final dockState = context.watch<TabletSideDockState>();
          final workStateReady = workState.isReady;
          final dockStateReady = dockState.isReady;
          final workActive = workState.isActive;
          final canRenderWorkingContent =
              workStateReady && dockStateReady && workActive;
          final dockOpen = dockStateReady && dockState.isOpen;

          if (_areaCache != area) {
            final previous = _areaCache;
            _areaCache = area;
            TabletDebugTrace.record(
              'TabletPage',
              'area_changed',
              <String, Object?>{
                'from': previous ?? '',
                'to': area,
              },
            );
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _clearCompletedNoticesForAreaChange();
            });
          }

          final content = canRenderWorkingContent
              ? _buildModeContent(
                  context: context,
                  padMode: padMode,
                  area: area,
                )
              : const SizedBox.expand(
                  key: ValueKey<String>('inactive-content'),
                );

          final scaffold = Scaffold(
            backgroundColor: tokens.surface,
            body: SafeArea(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (dockStateReady)
                          _TabletSideDockShell(
                            open: dockOpen,
                            rail: const TabletModeRail(),
                          ),
                        Expanded(
                          child: TabletCommonAnimatedSwap(child: content),
                        ),
                      ],
                    ),
                  ),
                  if (canRenderWorkingContent && !dockOpen)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 24,
                      child: GestureDetector(
                        behavior: HitTestBehavior.translucent,
                        onTap: _openSideDock,
                      ),
                    ),
                ],
              ),
            ),
          );

          return PopScope(
            canPop: false,
            onPopInvoked: (didPop) {},
            child: Stack(
              children: <Widget>[
                IgnorePointer(
                  ignoring: !canRenderWorkingContent,
                  child: scaffold,
                ),
                Positioned.fill(
                  child: TabletCommonAnimatedSwap(
                    child: !workStateReady || !dockStateReady
                        ? const _TabletWorkSessionLoadingOverlay(
                            key: ValueKey<String>('work-loading'),
                          )
                        : !workActive
                            ? const _TabletWorkSessionInactiveOverlay(
                                key: ValueKey<String>('work-inactive'),
                              )
                            : const SizedBox.shrink(
                                key: ValueKey<String>('work-active'),
                              ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _TabletSideDockShell extends StatefulWidget {
  const _TabletSideDockShell({
    required this.open,
    required this.rail,
  });

  final bool open;
  final Widget rail;

  @override
  State<_TabletSideDockShell> createState() => _TabletSideDockShellState();
}

class _TabletSideDockShellState extends State<_TabletSideDockShell>
    with SingleTickerProviderStateMixin {
  static const double _railWidth = 92;
  static const double _dividerWidth = 1;
  static const Duration _duration = Duration(milliseconds: 220);

  late final AnimationController _controller;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: _duration,
      value: widget.open ? 1 : 0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextReduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion == nextReduceMotion) return;
    _reduceMotion = nextReduceMotion;
    if (_reduceMotion) {
      _controller.value = widget.open ? 1 : 0;
    }
  }

  @override
  void didUpdateWidget(covariant _TabletSideDockShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.open == widget.open) return;
    final target = widget.open ? 1.0 : 0.0;
    if (_reduceMotion) {
      _controller.value = target;
      return;
    }
    _controller.animateTo(
      target,
      duration: _duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final fullWidth = _railWidth + _dividerWidth;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final value = _controller.value;
        final opacity = ((value - 0.12) / 0.88).clamp(0.0, 1.0).toDouble();

        return SizedBox(
          width: fullWidth * value,
          child: ClipRect(
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: <Widget>[
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: fullWidth,
                  child: Opacity(
                    opacity: opacity,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        widget.rail,
                        VerticalDivider(
                          width: _dividerWidth,
                          thickness: _dividerWidth,
                          color: tokens.borderSubtle,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TabletWorkSessionLoadingOverlay extends StatelessWidget {
  const _TabletWorkSessionLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Stack(
      children: <Widget>[
        ModalBarrier(dismissible: false, color: tokens.scrim),
        const Center(
          child: CommonAnimatedReveal(
            child: Material(
              type: MaterialType.transparency,
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 26,
                ),
                child: TabletCommonLoadingState(
                  label: '업무 상태 확인 중',
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TabletWorkSessionInactiveOverlay extends StatelessWidget {
  const _TabletWorkSessionInactiveOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Stack(
      children: <Widget>[
        ModalBarrier(dismissible: false, color: tokens.scrim),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: CommonAnimatedReveal(
              child: Material(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Icon(
                            Icons.pause_circle_outline_rounded,
                            color: tokens.statusOffline,
                            size: 30,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '업무 종료 상태',
                              style: text.titleLarge?.copyWith(
                                color: tokens.textPrimary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      CommonButton(
                        label: '업무 시작',
                        icon: Icons.play_arrow_rounded,
                        expand: true,
                        onPressed: () async {
                          TabletDebugTrace.record(
                            'TabletPage',
                            'work_start_requested',
                          );
                          await context
                              .read<TabletWorkSessionState>()
                              .startWork();
                        },
                        haptic: CommonHaptic.medium,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

String _digitsOnly(String value) => value.replaceAll(RegExp(r'[^0-9]'), '');

String _tail4Digits(String plateNumber) {
  final digits = _digitsOnly(plateNumber);
  if (digits.length <= 4) return digits;
  return digits.substring(digits.length - 4);
}
