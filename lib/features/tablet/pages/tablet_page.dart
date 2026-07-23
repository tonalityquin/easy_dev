import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../shared/plate/domain/enums/plate_type.dart';
import '../../../shared/tts/application/plate_tts_event_hub.dart';
import '../../dev/application/area_state.dart';
import '../applications/tablet_pad_mode_state.dart';
import '../applications/tablet_work_session_state.dart';
import 'panels/tablet_left_panel.dart';
import 'panels/tablet_right_panel.dart';
import 'sheets/widgets/tablet_grid_mode_page.dart';
import 'sheets/widgets/tablet_grid_pad_mode_page.dart';
import 'sheets/widgets/tablet_top_navigation.dart';
import 'widgets/tablet_prompt_components.dart';

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

  @override
  void initState() {
    super.initState();
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
    super.dispose();
  }

  Widget _buildModeContent({
    required BuildContext context,
    required PadMode padMode,
    required String area,
  }) {
    final tokens = PromptUiTheme.of(context);
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
            padding: const EdgeInsets.all(24),
            child: TabletPromptPanel(
              child: LeftPaneDeparturePlates(
                key: ValueKey<String>('left-pane-$area-show'),
                columns: 5,
                completedNotices: _completedNotices,
              ),
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
                  padding: const EdgeInsets.all(24),
                  child: TabletPromptPanel(
                    child: LeftPaneDeparturePlates(
                      key: ValueKey<String>('left-pane-$area'),
                      columns: 3,
                      completedNotices: _completedNotices,
                    ),
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
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(PromptUiShapes.control),
                  ),
                  child: RightPaneSearchPanel(
                    key: ValueKey<String>('right-pane-$area'),
                    area: area,
                  ),
                ),
              ),
            ),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(
        builder: (context) {
          final tokens = PromptUiTheme.of(context);
          final area =
              context.select<AreaState, String?>((state) => state.currentArea) ??
                  '';
          final padMode =
              context.select<TabletPadModeState, PadMode>((state) => state.mode);
          final workState = context.watch<TabletWorkSessionState>();
          final workStateReady = workState.isReady;
          final workActive = workState.isActive;
          final canRenderWorkingContent = workStateReady && workActive;

          if (_areaCache != area) {
            _areaCache = area;
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
            appBar: PreferredSize(
              preferredSize: const Size.fromHeight(kToolbarHeight),
              child: SafeArea(
                bottom: false,
                child: TabletTopNavigation(
                  isAreaSelectable: canRenderWorkingContent,
                ),
              ),
            ),
            body: SafeArea(
              top: false,
              bottom: true,
              child: TabletPromptAnimatedSwap(child: content),
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
                  child: TabletPromptAnimatedSwap(
                    child: !workStateReady
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

class _TabletWorkSessionLoadingOverlay extends StatelessWidget {
  const _TabletWorkSessionLoadingOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return Stack(
      children: <Widget>[
        ModalBarrier(dismissible: false, color: tokens.scrim),
        Center(
          child: PromptAnimatedReveal(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: TabletPromptPanel(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 26,
                ),
                radius: PromptUiShapes.dialog,
                child: const TabletPromptLoadingState(
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
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    return Stack(
      children: <Widget>[
        ModalBarrier(dismissible: false, color: tokens.scrim),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: PromptAnimatedReveal(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: TabletPromptPanel(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
                  radius: PromptUiShapes.dialog,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: tokens.statusOfflineContainer,
                              borderRadius:
                                  BorderRadius.circular(PromptUiShapes.card),
                              border: Border.all(color: tokens.statusOffline),
                            ),
                            child: Icon(
                              Icons.pause_circle_outline_rounded,
                              color: tokens.statusOffline,
                              size: 26,
                            ),
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
                      PromptButton(
                        label: '업무 시작',
                        icon: Icons.play_arrow_rounded,
                        expand: true,
                        onPressed: () async {
                          await context
                              .read<TabletWorkSessionState>()
                              .startWork();
                        },
                        haptic: PromptHaptic.medium,
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
