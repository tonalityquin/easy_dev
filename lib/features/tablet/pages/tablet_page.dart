import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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
      _completedNotices.removeWhere((x) => x.docId == docId);
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
    setState(() {
      _completedNotices.clear();
    });
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final area = context.select<AreaState, String?>((s) => s.currentArea) ?? '';
    final padMode = context.select<TabletPadModeState, PadMode>((s) => s.mode);
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

    Widget pageContent = const SizedBox.expand();

    if (canRenderWorkingContent) {
      switch (padMode) {
        case PadMode.gridPad:
          pageContent = ColoredBox(
            color: cs.surfaceContainerLow,
            child: TabletGridPadModePage(
              key: ValueKey('grid-pad-pane-$area'),
              area: area,
            ),
          );
          break;
        case PadMode.grid:
          pageContent = ColoredBox(
            color: cs.surfaceContainerLow,
            child: TabletGridModePage(
              key: ValueKey('grid-pane-$area'),
              area: area,
            ),
          );
          break;
        case PadMode.show:
          pageContent = ColoredBox(
            color: cs.surfaceContainerLow,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: _PanelCard(
                child: LeftPaneDeparturePlates(
                  key: ValueKey('left-pane-$area-show'),
                  columns: 5,
                  completedNotices: _completedNotices,
                ),
              ),
            ),
          );
          break;
        case PadMode.mobile:
          pageContent = ColoredBox(
            color: cs.surface,
            child: RightPaneSearchPanel(
              key: ValueKey('mobile-pane-$area'),
              area: area,
            ),
          );
          break;
        case PadMode.big:
        case PadMode.small:
          pageContent = Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ColoredBox(
                  color: cs.surfaceContainerLow,
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: _PanelCard(
                      child: LeftPaneDeparturePlates(
                        key: ValueKey('left-pane-$area'),
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
                color: cs.outlineVariant,
              ),
              Expanded(
                child: ColoredBox(
                  color: cs.surface,
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                    ),
                    child: RightPaneSearchPanel(
                      key: ValueKey('right-pane-$area'),
                      area: area,
                    ),
                  ),
                ),
              ),
            ],
          );
          break;
      }
    }

    final scaffold = Scaffold(
      backgroundColor: cs.surface,
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(kToolbarHeight),
        child: SafeArea(
          bottom: false,
          child: TabletTopNavigation(isAreaSelectable: canRenderWorkingContent),
        ),
      ),
      body: SafeArea(
        top: false,
        bottom: true,
        child: pageContent,
      ),
    );

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) {
        if (didPop) return;
      },
      child: Stack(
        children: [
          IgnorePointer(
            ignoring: !canRenderWorkingContent,
            child: scaffold,
          ),
          if (!workStateReady)
            const Positioned.fill(
              child: _TabletWorkSessionLoadingOverlay(),
            )
          else if (!workActive)
            const Positioned.fill(
              child: _TabletWorkSessionInactiveOverlay(),
            ),
        ],
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  final Widget child;

  const _PanelCard({required this.child});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outline.withOpacity(.12)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }
}

class _TabletWorkSessionLoadingOverlay extends StatelessWidget {
  const _TabletWorkSessionLoadingOverlay();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Stack(
      children: [
        ModalBarrier(
          dismissible: false,
          color: Colors.black.withOpacity(0.28),
        ),
        Center(
          child: Container(
            width: 280,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: cs.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: cs.outlineVariant.withOpacity(.75)),
              boxShadow: [
                BoxShadow(
                  color: cs.shadow.withOpacity(.14),
                  blurRadius: 18,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  '업무 상태 확인 중',
                  textAlign: TextAlign.center,
                  style: (text.bodyMedium ?? const TextStyle()).copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _TabletWorkSessionInactiveOverlay extends StatelessWidget {
  const _TabletWorkSessionInactiveOverlay();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Stack(
      children: [
        ModalBarrier(
          dismissible: false,
          color: Colors.black.withOpacity(0.34),
        ),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              decoration: BoxDecoration(
                color: cs.surface,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outlineVariant.withOpacity(.80)),
                boxShadow: [
                  BoxShadow(
                    color: cs.shadow.withOpacity(.18),
                    blurRadius: 24,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: cs.primary.withOpacity(.10),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          Icons.pause_circle_outline,
                          color: cs.primary,
                          size: 26,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '업무 종료 상태',
                          style: (text.titleMedium ?? const TextStyle()).copyWith(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: () async {
                      await context.read<TabletWorkSessionState>().startWork();
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('업무 시작'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                ],
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
