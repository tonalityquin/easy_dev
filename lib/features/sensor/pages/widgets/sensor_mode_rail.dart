import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../app/init/app_exit_service.dart';
import '../../../../app/init/logout_helper.dart';
import '../../../../app/terminal/presentation/parkinworkin_terminal_navigator.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../applications/sensor_debug_trace.dart';
import '../../applications/sensor_operational_data_sync_workflow.dart';
import '../../applications/sensor_side_dock_state.dart';
import '../../applications/sensor_work_session_state.dart';

class SensorModeRail extends StatefulWidget {
  const SensorModeRail({super.key});

  static const double width = 92.0;
  static const double actionHeight = 43.0;
  static const double sensorToggleHeight = 43.0;
  static const double sensorToggleBottomInset =
      1.0 + 4.0 + actionHeight * 5.0 + 6.0;

  @override
  State<SensorModeRail> createState() => _SensorModeRailState();
}

class _SensorModeRailState extends State<SensorModeRail>
    with TickerProviderStateMixin {
  late final AnimationController _entryController;
  late final AnimationController _downloadController;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _entryController = AnimationController(
      vsync: this,
      duration: CommonUiMotion.overlay,
    );
    _downloadController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
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
    SensorDebugTrace.record('SensorRail', 'mounted');
  }

  @override
  void dispose() {
    SensorDebugTrace.record('SensorRail', 'disposed');
    _entryController.dispose();
    _downloadController.dispose();
    super.dispose();
  }

  Future<void> _download() async {
    if (_downloading) return;
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    setState(() => _downloading = true);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduceMotion) {
      _downloadController.repeat(reverse: true);
    }
    SensorDebugTrace.record('SensorRail', 'download_requested');
    try {
      final result = await SensorOperationalDataSyncWorkflow.runCurrentArea(
        context: context,
      );
      SensorDebugTrace.record(
        'SensorRail',
        'download_finished',
        <String, Object?>{'result': result.name},
      );
    } catch (error, stackTrace) {
      SensorDebugTrace.record(
        'SensorRail',
        'download_failed',
        <String, Object?>{
          'error': error,
          'stackTrace': stackTrace,
        },
      );
    } finally {
      _downloadController.stop();
      _downloadController.value = 0;
      if (mounted) {
        setState(() => _downloading = false);
      }
    }
  }

  Future<void> _openTerminal() async {
    await HapticFeedback.selectionClick();
    SensorDebugTrace.record('SensorRail', 'terminal_open_requested');
    await showParkinWorkinTerminal(
      context,
      source: 'sensor_rail',
    );
    SensorDebugTrace.record('SensorRail', 'terminal_closed');
  }

  Future<void> _changeArea() async {
    await HapticFeedback.selectionClick();
    SensorDebugTrace.record(
      'SensorRail',
      'area_change_requested',
      <String, Object?>{'implemented': false},
    );
  }

  Future<void> _logout() async {
    await HapticFeedback.mediumImpact();
    SensorDebugTrace.record('SensorRail', 'logout_requested');
    await LogoutHelper.logoutAndGoToLogin(
      context,
      checkWorking: true,
      delay: const Duration(seconds: 1),
      useCommonUi: true,
    );
  }

  Future<void> _closeSideDock() async {
    await HapticFeedback.selectionClick();
    if (!mounted) return;
    SensorDebugTrace.record(
      'SensorSideDock',
      'close_requested',
      <String, Object?>{'source': 'collapse_button'},
    );
    await context
        .read<SensorSideDockState>()
        .close(source: 'collapse_button');
  }

  Future<void> _exitApp() async {
    await HapticFeedback.mediumImpact();
    if (!mounted) return;
    SensorDebugTrace.record('SensorRail', 'work_end_requested');
    await context
        .read<SensorWorkSessionState>()
        .stopWork(source: 'app_exit');
    await Future<void>.delayed(const Duration(milliseconds: 32));
    if (!mounted) return;
    SensorDebugTrace.record('SensorRail', 'app_exit_requested');
    await AppExitService.exitApp(
      context,
      useCommonUi: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    final downloadIcon = reduceMotion
        ? Icon(
            Icons.download_rounded,
            size: 21,
            color: tokens.iconSecondary,
          )
        : ScaleTransition(
            scale: Tween<double>(begin: 0.88, end: 1.08).animate(
              CurvedAnimation(
                parent: _downloadController,
                curve: Curves.easeInOutCubic,
              ),
            ),
            child: Icon(
              Icons.download_rounded,
              size: 21,
              color: tokens.iconSecondary,
            ),
          );

    final rail = SizedBox(
      width: SensorModeRail.width,
      child: Material(
        color: tokens.surface,
        child: Column(
          children: <Widget>[
            const SizedBox(height: 8),
            _SensorCollapseButton(
              onPressed: () => unawaited(_closeSideDock()),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  const SizedBox(
                    height: SensorModeRail.sensorToggleHeight,
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: tokens.borderSubtle,
                  ),
                  const SizedBox(height: 4),
                  _SensorActionButton(
                    iconWidget: downloadIcon,
                    label: _downloading ? '내려받는 중' : '내려받기',
                    enabled: !_downloading,
                    onPressed: () => unawaited(_download()),
                  ),
                  _SensorActionButton(
                    icon: Icons.swap_horiz_rounded,
                    label: '구역 변경',
                    onPressed: () => unawaited(_changeArea()),
                  ),
                  _SensorActionButton(
                    icon: Icons.terminal_rounded,
                    label: '터미널',
                    onPressed: () => unawaited(_openTerminal()),
                  ),
                  _SensorActionButton(
                    icon: Icons.logout_rounded,
                    label: '로그아웃',
                    onPressed: () => unawaited(_logout()),
                  ),
                  _SensorActionButton(
                    icon: Icons.power_settings_new_rounded,
                    label: '앱 종료',
                    destructive: true,
                    onPressed: () => unawaited(_exitApp()),
                  ),
                  const SizedBox(height: 6),
                ],
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

class _SensorCollapseButton extends StatefulWidget {
  const _SensorCollapseButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_SensorCollapseButton> createState() =>
      _SensorCollapseButtonState();
}

class _SensorCollapseButtonState extends State<_SensorCollapseButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.press;

    return Semantics(
      button: true,
      label: '사이드 도크 닫기',
      child: AnimatedScale(
        duration: duration,
        curve: CommonUiMotion.standard,
        scale: _pressed ? 0.9 : 1,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.standard,
          width: 44,
          height: 36,
          decoration: BoxDecoration(
            color: _pressed ? tokens.surfaceSelected : tokens.transparent,
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
          ),
          child: Material(
            color: tokens.transparent,
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            child: InkWell(
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              onHighlightChanged: (value) => setState(() => _pressed = value),
              onTap: widget.onPressed,
              child: Center(
                child: AnimatedRotation(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  curve: CommonUiMotion.standard,
                  turns: _pressed ? -0.04 : 0,
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 24,
                    color: tokens.iconSecondary,
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

class _SensorActionButton extends StatelessWidget {
  const _SensorActionButton({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.destructive = false,
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool destructive;

  @override
  Widget build(BuildContext context) {
    return _SensorRailButton(
      icon: icon,
      iconWidget: iconWidget,
      label: label,
      onPressed: onPressed,
      enabled: enabled,
      destructive: destructive,
    );
  }
}

class _SensorRailButton extends StatefulWidget {
  const _SensorRailButton({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.onPressed,
    required this.enabled,
    required this.destructive,
  });

  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool destructive;

  @override
  State<_SensorRailButton> createState() => _SensorRailButtonState();
}

class _SensorRailButtonState extends State<_SensorRailButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    final foreground =
        widget.destructive ? tokens.danger : tokens.textSecondary;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: AnimatedScale(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
        curve: CommonUiMotion.standard,
        scale: _pressed ? 0.95 : 1,
        child: AnimatedContainer(
          duration: duration,
          curve: CommonUiMotion.standard,
          height: SensorModeRail.actionHeight,
          color: tokens.transparent,
          child: Material(
            color: tokens.transparent,
            child: InkWell(
              onHighlightChanged: widget.enabled
                  ? (value) => setState(() => _pressed = value)
                  : null,
              onTap: widget.enabled ? widget.onPressed : null,
              child: AnimatedOpacity(
                duration: duration,
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
                            '${widget.label}-${widget.enabled}-${widget.icon}',
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
                            fontWeight: FontWeight.w600,
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
