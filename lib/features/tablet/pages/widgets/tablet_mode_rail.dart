import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/terminal/presentation/parkinworkin_terminal_navigator.dart';
import '../../../../app/utils/operational_data_sync_workflow.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../selector/application/dev_auth.dart';
import '../../applications/tablet_debug_trace.dart';
import '../../applications/tablet_grid_render_mode_state.dart';
import '../../applications/tablet_pad_mode_state.dart';
import '../../applications/tablet_parking_completed_view_toggle_state.dart';
import '../../applications/tablet_plate_tail4_size_state.dart';
import '../../applications/tablet_work_session_state.dart';

class TabletModeRail extends StatefulWidget {
  const TabletModeRail({super.key});

  @override
  State<TabletModeRail> createState() => _TabletModeRailState();
}

class _TabletModeRailState extends State<TabletModeRail>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _refreshController;
  late final ScrollController _actionScrollController;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: CommonUiMotion.overlay,
    );
    _refreshController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _actionScrollController = ScrollController();
    unawaited(DevAuth.isDevModeEnabled());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final reduceMotion =
          MediaQuery.maybeOf(context)?.disableAnimations ?? false;
      if (reduceMotion) {
        _entryController.value = 1;
      } else {
        _entryController.forward();
      }
    });
    TabletDebugTrace.record('TabletRail', 'mounted');
  }

  @override
  void dispose() {
    _entryController.dispose();
    _refreshController.dispose();
    _actionScrollController.dispose();
    super.dispose();
  }

  void _setMode(PadMode mode) {
    final state = context.read<TabletPadModeState>();
    if (state.mode == mode) return;
    HapticFeedback.selectionClick();
    TabletDebugTrace.record(
      'TabletRail',
      'mode_change_requested',
      <String, Object?>{
        'from': state.mode.name,
        'to': mode.name,
      },
    );
    state.setMode(mode);
  }

  void _toggleParkingCompleted() {
    HapticFeedback.selectionClick();
    final state = context.read<TabletParkingCompletedViewToggleState>();
    state.toggle();
    TabletDebugTrace.record(
      'TabletRail',
      'parking_completed_subscription_toggled',
      <String, Object?>{
        'enabled': state.includeParkingCompletedView,
      },
    );
  }

  Future<void> _showThemePending() async {
    HapticFeedback.selectionClick();
    TabletDebugTrace.record('TabletRail', 'theme_pending_opened');
    await StatusDialog.showSuccess(
      context,
      title: '테마 설정',
      description: '준비 중입니다.',
      useCommonUi: true,
    );
  }

  Future<void> _refreshData() async {
    if (_refreshing) return;
    HapticFeedback.selectionClick();
    setState(() => _refreshing = true);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduceMotion) {
      _refreshController.repeat();
    }
    TabletDebugTrace.record('TabletRail', 'refresh_started');
    try {
      final result = await OperationalDataSyncWorkflow.run(
        context: context,
        title: '데이터 새로고침',
        message: '현재 지역의 운영 데이터를 새로고침합니다.',
        useCommonUi: true,
      );
      TabletDebugTrace.record(
        'TabletRail',
        'refresh_finished',
        <String, Object?>{'result': result.name},
      );
    } catch (error) {
      TabletDebugTrace.record(
        'TabletRail',
        'refresh_failed',
        <String, Object?>{'error': error},
      );
      if (mounted) {
        await StatusDialog.showFailure(
          context,
          title: '데이터 새로고침 실패',
          description: error.toString(),
          useCommonUi: true,
        );
      }
    } finally {
      _refreshController.stop();
      _refreshController.value = 0;
      if (mounted) {
        setState(() => _refreshing = false);
      }
    }
  }

  void _nextPlateSize() {
    HapticFeedback.selectionClick();
    final state = context.read<TabletPlateTail4SizeState>();
    final previous = state.size;
    state.next();
    TabletDebugTrace.record(
      'TabletRail',
      'plate_size_next',
      <String, Object?>{
        'from': previous.label,
        'to': state.size.label,
      },
    );
  }

  void _toggleGridRenderMode() {
    HapticFeedback.selectionClick();
    final state = context.read<TabletGridRenderModeState>();
    final previous = state.mode;
    state.toggle();
    TabletDebugTrace.record(
      'TabletRail',
      'grid_render_mode_toggled',
      <String, Object?>{
        'from': previous.name,
        'to': state.mode.name,
      },
    );
  }

  Future<void> _openTerminal() async {
    HapticFeedback.selectionClick();
    TabletDebugTrace.record('TabletRail', 'terminal_open_requested');
    await showParkinWorkinTerminal(
      context,
      source: 'tablet_rail',
    );
    TabletDebugTrace.record('TabletRail', 'terminal_closed');
  }

  Future<void> _logout() async {
    HapticFeedback.mediumImpact();
    TabletDebugTrace.record('TabletRail', 'logout_requested');
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: true,
      delay: const Duration(seconds: 1),
      useCommonUi: true,
    );
  }

  Future<void> _endWork() async {
    HapticFeedback.mediumImpact();
    TabletDebugTrace.record('TabletRail', 'work_end_requested');
    await context.read<TabletWorkSessionState>().stopWork();
    await Future<void>.delayed(const Duration(milliseconds: 32));
    if (!mounted) return;
    TabletDebugTrace.record('TabletRail', 'app_exit_requested');
    await AppExitService.exitApp(
      context,
      useCommonUi: true,
    );
  }

  Future<void> _showDeveloperStatus() async {
    HapticFeedback.selectionClick();
    TabletDebugTrace.record('TabletRail', 'developer_status_requested');
    await TabletDebugTrace.showStatusDialog(
      context,
      title: '태블릿 개발자 상태',
    );
  }

  bool _handleActionScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      TabletDebugTrace.record(
        'TabletRail',
        'action_scroll_started',
        <String, Object?>{
          'offset': notification.metrics.pixels.round(),
          'maxOffset': notification.metrics.maxScrollExtent.round(),
        },
      );
    } else if (notification is ScrollEndNotification) {
      TabletDebugTrace.record(
        'TabletRail',
        'action_scroll_ended',
        <String, Object?>{
          'offset': notification.metrics.pixels.round(),
          'maxOffset': notification.metrics.maxScrollExtent.round(),
        },
      );
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final mode = context.watch<TabletPadModeState>().mode;
    final parkingCompleted = context
        .watch<TabletParkingCompletedViewToggleState>()
        .includeParkingCompletedView;
    final plateSize = context.watch<TabletPlateTail4SizeState>().size;
    final gridMode = context.watch<TabletGridRenderModeState>().mode;

    final rail = SizedBox(
      width: 92,
      child: Material(
        color: tokens.surface,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 8),
            _ModeButton(
              icon: Icons.dashboard_rounded,
              label: 'Big',
              selected: mode == PadMode.big,
              onPressed: () => _setMode(PadMode.big),
            ),
            _ModeButton(
              icon: Icons.dialpad_rounded,
              label: 'Small',
              selected: mode == PadMode.small,
              onPressed: () => _setMode(PadMode.small),
            ),
            _ModeButton(
              icon: Icons.monitor_rounded,
              label: 'Show',
              selected: mode == PadMode.show,
              onPressed: () => _setMode(PadMode.show),
            ),
            _ModeButton(
              icon: Icons.smartphone_rounded,
              label: 'Mobile',
              selected: mode == PadMode.mobile,
              onPressed: () => _setMode(PadMode.mobile),
            ),
            _ModeButton(
              icon: Icons.space_dashboard_rounded,
              label: 'Grid Pad',
              selected: mode == PadMode.gridPad,
              onPressed: () => _setMode(PadMode.gridPad),
            ),
            _ModeButton(
              icon: Icons.grid_view_rounded,
              label: 'Grid',
              selected: mode == PadMode.grid,
              onPressed: () => _setMode(PadMode.grid),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Scrollbar(
                    controller: _actionScrollController,
                    thumbVisibility: true,
                    thickness: 2.5,
                    radius: const Radius.circular(999),
                    child: NotificationListener<ScrollNotification>(
                      onNotification: _handleActionScrollNotification,
                      child: SingleChildScrollView(
                        controller: _actionScrollController,
                        physics: const ClampingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: IntrinsicHeight(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: <Widget>[
                                Divider(
                                  height: 1,
                                  thickness: 1,
                                  color: tokens.borderSubtle,
                                ),
                                const SizedBox(height: 4),
                                _ActionButton(
                                  icon: parkingCompleted
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  label: parkingCompleted
                                      ? '입차 ON'
                                      : '입차 OFF',
                                  selected: parkingCompleted,
                                  onPressed: _toggleParkingCompleted,
                                ),
                                _ActionButton(
                                  icon: Icons.palette_outlined,
                                  label: '테마',
                                  onPressed: () =>
                                      unawaited(_showThemePending()),
                                ),
                                _ActionButton(
                                  iconWidget: RotationTransition(
                                    turns: _refreshController,
                                    child: Icon(
                                      Icons.refresh_rounded,
                                      size: 21,
                                      color: tokens.iconSecondary,
                                    ),
                                  ),
                                  label: _refreshing ? '갱신 중' : '새로고침',
                                  enabled: !_refreshing,
                                  onPressed: () => unawaited(_refreshData()),
                                ),
                                _ActionButton(
                                  icon: Icons.format_size_rounded,
                                  label: plateSize.label,
                                  onPressed: _nextPlateSize,
                                ),
                                _ActionButton(
                                  icon: gridMode == TabletGridRenderMode.twoD
                                      ? Icons.grid_view_rounded
                                      : Icons.view_in_ar_rounded,
                                  label: gridMode == TabletGridRenderMode.twoD
                                      ? '2D'
                                      : '3D',
                                  selected:
                                      gridMode == TabletGridRenderMode.threeD,
                                  onPressed: _toggleGridRenderMode,
                                ),
                                _ActionButton(
                                  icon: Icons.terminal_rounded,
                                  label: '터미널',
                                  onPressed: () => unawaited(_openTerminal()),
                                ),
                                ValueListenableBuilder<bool>(
                                  valueListenable: DevAuth.devModeEnabled,
                                  builder: (context, enabled, _) {
                                    if (!enabled) {
                                      return const SizedBox.shrink();
                                    }
                                    return _ActionButton(
                                      icon: Icons.bug_report_outlined,
                                      label: 'DEBUG',
                                      selected: true,
                                      onPressed: () =>
                                          unawaited(_showDeveloperStatus()),
                                    );
                                  },
                                ),
                                _ActionButton(
                                  icon: Icons.logout_rounded,
                                  label: '로그아웃',
                                  onPressed: () => unawaited(_logout()),
                                ),
                                _ActionButton(
                                  icon: Icons.power_settings_new_rounded,
                                  label: '업무 종료',
                                  destructive: true,
                                  onPressed: () => unawaited(_endWork()),
                                ),
                                const SizedBox(height: 6),
                              ],
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
        ),
      ),
    );

    if (reduceMotion) return rail;
    return AnimatedBuilder(
      animation: _entryController,
      child: rail,
      builder: (context, child) {
        final animation = CurvedAnimation(
          parent: _entryController,
          curve: CommonUiMotion.enter,
        );
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(-0.12, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return _RailButton(
      icon: icon,
      label: label,
      selected: selected,
      height: 48,
      onPressed: onPressed,
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.onPressed,
    this.selected = false,
    this.enabled = true,
    this.destructive = false,
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback onPressed;
  final bool selected;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return _RailButton(
      icon: icon,
      iconWidget: iconWidget,
      label: label,
      selected: selected,
      enabled: enabled,
      destructive: destructive,
      height: 43,
      onPressed: onPressed,
    );
  }
}

class _RailButton extends StatefulWidget {
  const _RailButton({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.selected,
    required this.onPressed,
    required this.height,
    this.enabled = true,
    this.destructive = false,
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final bool selected;
  final VoidCallback onPressed;
  final double height;
  final bool enabled;
  final bool destructive;

  @override
  State<_RailButton> createState() => _RailButtonState();
}

class _RailButtonState extends State<_RailButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final duration = MediaQuery.maybeOf(context)?.disableAnimations == true
        ? Duration.zero
        : CommonUiMotion.selection;
    final foreground = widget.destructive
        ? tokens.danger
        : widget.selected
            ? tokens.accent
            : tokens.textSecondary;
    final background = widget.selected
        ? tokens.surfaceSelected
        : tokens.transparent;

    return Semantics(
      button: true,
      selected: widget.selected,
      enabled: widget.enabled,
      label: widget.label,
      child: AnimatedScale(
        duration: MediaQuery.maybeOf(context)?.disableAnimations == true
            ? Duration.zero
            : CommonUiMotion.press,
        curve: CommonUiMotion.standard,
        scale: _pressed ? 0.95 : 1,
        child: AnimatedContainer(
          duration: duration,
          curve: CommonUiMotion.standard,
          height: widget.height,
          decoration: BoxDecoration(
            color: background,
            border: Border(
              left: BorderSide(
                color: widget.selected ? tokens.accent : tokens.transparent,
                width: 3,
              ),
            ),
          ),
          child: Material(
            color: tokens.transparent,
            child: InkWell(
              onHighlightChanged: widget.enabled
                  ? (value) => setState(() => _pressed = value)
                  : null,
              onTap: widget.enabled ? widget.onPressed : null,
              child: Opacity(
                opacity: widget.enabled ? 1 : 0.45,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: <Widget>[
                      const SizedBox(width: 6),
                      AnimatedSwitcher(
                        duration: duration,
                        child: SizedBox(
                          key: ValueKey<String>(
                            '${widget.label}-${widget.selected}-${widget.icon}',
                          ),
                          width: 24,
                          child: Center(
                            child: widget.iconWidget ??
                                Icon(
                                  widget.icon,
                                  size: 21,
                                  color: foreground,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: AnimatedDefaultTextStyle(
                          duration: duration,
                          curve: CommonUiMotion.standard,
                          style: (text.labelSmall ?? const TextStyle()).copyWith(
                            color: foreground,
                            fontSize: 10.5,
                            fontWeight: widget.selected
                                ? FontWeight.w800
                                : FontWeight.w600,
                            height: 1,
                          ),
                          child: Text(
                            widget.label,
                            maxLines: 1,
                            overflow: TextOverflow.fade,
                            softWrap: false,
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
      ),
    );
  }
}
