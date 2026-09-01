import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/di/routes.dart';
import '../../../app/init/app_start_debug_trace.dart';
import '../../../app/init/startup_tasks.dart';
import '../../../app/terminal/presentation/parkinworkin_terminal_screen.dart';
import '../../../app/tutorial/widgets/app_start_cinematic_reveal.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';
import '../../selector/application/dev_auth.dart';
import '../application/launcher_actions.dart';
import '../application/launcher_diagnostics.dart';
import '../widgets/app_power_action_control.dart';

class PowerBootScreen extends StatefulWidget {
  const PowerBootScreen({
    super.key,
    this.startupReport,
  });

  final StartupReport? startupReport;

  @override
  State<PowerBootScreen> createState() => _PowerBootScreenState();
}

class _PowerBootScreenState extends State<PowerBootScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _revealController;
  bool _poweringOn = false;
  bool _exiting = false;

  bool get _interactionLocked => _poweringOn || _exiting;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  StartupReport? get _report => widget.startupReport ?? StartupTasks.lastReport;

  @override
  void initState() {
    super.initState();
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    AppStartDebugTrace.log('power_boot', 'screen_init');
    LauncherDiagnostics.record(
      'power_screen_init',
      scope: 'power_boot',
      meta: <String, Object?>{
        'startupReady': _report?.readyCount ?? 0,
      },
    );
    unawaited(DevAuth.isDevModeEnabled());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_reduceMotion) {
        _revealController.value = 1;
      } else {
        _revealController.forward(from: 0);
      }
    });
  }

  Future<void> _powerOn() async {
    if (_interactionLocked) return;
    setState(() => _poweringOn = true);
    AppStartDebugTrace.log('power_boot', 'power_pressed');
    LauncherDiagnostics.record(
      'power_pressed',
      scope: 'power_boot',
      meta: <String, Object?>{
        'startupReady': _report?.readyCount ?? 0,
      },
    );

    final reduceMotion = _reduceMotion;
    final report = _report;
    if (!mounted) return;

    final route = PageRouteBuilder<void>(
      settings: const RouteSettings(name: AppRoutes.modeLauncher),
      transitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 260),
      reverseTransitionDuration:
          reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
      pageBuilder: (context, animation, secondaryAnimation) {
        return ParkinWorkinTerminalScreen.launcher(startupReport: report);
      },
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        if (reduceMotion) return child;
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: .992, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
    Navigator.of(context).pushReplacement(route);
  }

  Future<void> _openAbout() async {
    if (_interactionLocked) return;
    await HapticFeedback.selectionClick();
    LauncherDiagnostics.record(
      'power_about_requested',
      scope: 'power_boot',
    );
    await LauncherActions.openAbout(context);
    if (!mounted) return;
    LauncherDiagnostics.record(
      'power_about_returned',
      scope: 'power_boot',
    );
  }

  Future<void> _exitApp() async {
    if (_interactionLocked) return;
    setState(() => _exiting = true);
    try {
      await HapticFeedback.mediumImpact();
      LauncherDiagnostics.record(
        'power_exit_lock_start',
        scope: 'power_boot',
        meta: <String, Object?>{
          'poweringOn': _poweringOn,
          'exiting': _exiting,
        },
      );
      if (!_reduceMotion) {
        await Future<void>.delayed(const Duration(milliseconds: 180));
      }
      if (!mounted) return;
      LauncherDiagnostics.record(
        'power_exit_requested',
        scope: 'power_boot',
      );
      await LauncherActions.exitApp(context);
      if (!mounted) return;
      LauncherDiagnostics.record(
        'power_exit_action_returned',
        scope: 'power_boot',
      );
    } finally {
      if (mounted) {
        setState(() => _exiting = false);
        LauncherDiagnostics.record(
          'power_exit_lock_release',
          scope: 'power_boot',
          meta: <String, Object?>{
            'poweringOn': _poweringOn,
            'exiting': _exiting,
          },
        );
      }
    }
  }

  Future<void> _showDeveloperStatus() async {
    LauncherDiagnostics.record(
      'power_status_requested',
      scope: 'power_boot',
    );
    await LauncherDiagnostics.showStatus(
      context,
      title: 'Power Boot Status',
      description: <String>[
        'Startup ready: ${_report?.readyCount ?? 0}/4',
        'Notifications: ${_report?.notificationsReady == true ? 'READY' : 'WARN'}',
        'Reminder: ${_report?.reminderReady == true ? 'READY' : 'WARN'}',
        'Productivity store: ${_report?.chillStoreReady == true ? 'READY' : 'WARN'}',
        'Foreground service: ${_report?.foregroundServiceReady == true ? 'ACTIVE' : 'WARN'}',
        'Powering on: $_poweringOn',
        'Exiting: $_exiting',
        'Interaction locked: $_interactionLocked',
        'Footer actions: about/exit',
      ].join('\n'),
      scope: 'power_boot',
    );
  }

  Widget _buildPowerControl(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reveal = CurvedAnimation(
      parent: _revealController,
      curve: Curves.easeOutCubic,
    );

    return AppStartCinematicReveal(
      animation: reveal,
      reduceMotion: _reduceMotion,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppPowerActionControl(
                semanticLabel: 'ParkinWorkin 시작',
                enabled: !_interactionLocked,
                state: _poweringOn
                    ? AppPowerActionVisualState.processing
                    : AppPowerActionVisualState.idle,
                onPressed: _powerOn,
              ),
              const SizedBox(height: 30),
              AnimatedOpacity(
                opacity: _interactionLocked ? 0.35 : 1,
                duration: _reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 190),
                curve: Curves.easeOutCubic,
                child: Text(
                  '시작합니다.',
                  textAlign: TextAlign.center,
                  style: textTheme.headlineSmall?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                    height: 1.5,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFooterActions(BuildContext context) {
    final animation = _reduceMotion
        ? const AlwaysStoppedAnimation<double>(1)
        : CurvedAnimation(
            parent: _revealController,
            curve: const Interval(.28, 1, curve: Curves.easeOutCubic),
          );
    final slide = Tween<Offset>(
      begin: const Offset(0, .18),
      end: Offset.zero,
    ).animate(animation);

    return IgnorePointer(
      ignoring: _interactionLocked,
      child: FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: slide,
          child: AnimatedOpacity(
            opacity: _exiting ? 0.82 : _poweringOn ? 0.28 : 1,
            duration: _reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 190),
            curve: Curves.easeOutCubic,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(28, 0, 28, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _PowerBootFooterAction(
                      label: '파킨워킨에 대해 알아보기',
                      icon: Icons.info_outline_rounded,
                      enabled: !_interactionLocked,
                      reduceMotion: _reduceMotion,
                      onPressed: _openAbout,
                    ),
                    const SizedBox(height: 4),
                    _PowerBootFooterAction(
                      label: '앱 종료',
                      icon: Icons.power_settings_new_rounded,
                      enabled: !_interactionLocked,
                      reduceMotion: _reduceMotion,
                      processing: _exiting,
                      destructive: true,
                      onPressed: _exitApp,
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

  @override
  void dispose() {
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          final brightness = tokens.isDark ? Brightness.light : Brightness.dark;
          return PopScope(
            canPop: false,
            child: AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: tokens.canvas,
                statusBarIconBrightness: brightness,
                statusBarBrightness:
                    tokens.isDark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: tokens.canvas,
                systemNavigationBarIconBrightness: brightness,
                systemNavigationBarDividerColor: tokens.canvas,
              ),
              child: Scaffold(
                backgroundColor: tokens.canvas,
                body: SafeArea(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Center(child: _buildPowerControl(context)),
                      Align(
                        alignment: Alignment.bottomCenter,
                        child: _buildFooterActions(context),
                      ),
                      Align(
                        alignment: Alignment.topRight,
                        child: ValueListenableBuilder<bool>(
                          valueListenable: DevAuth.devModeEnabled,
                          builder: (context, enabled, child) {
                            if (!enabled) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.all(12),
                              child: IconButton.filledTonal(
                                onPressed:
                                    _interactionLocked ? null : _showDeveloperStatus,
                                icon: const Icon(Icons.terminal_rounded),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _PowerBootFooterAction extends StatefulWidget {
  const _PowerBootFooterAction({
    required this.label,
    required this.icon,
    required this.enabled,
    required this.reduceMotion,
    required this.onPressed,
    this.destructive = false,
    this.processing = false,
  });

  final String label;
  final IconData icon;
  final bool enabled;
  final bool reduceMotion;
  final Future<void> Function() onPressed;
  final bool destructive;
  final bool processing;

  @override
  State<_PowerBootFooterAction> createState() =>
      _PowerBootFooterActionState();
}

class _PowerBootFooterActionState extends State<_PowerBootFooterAction> {
  bool _pressed = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final baseColor = widget.destructive ? tokens.danger : tokens.textSecondary;
    final activeColor = widget.destructive ? tokens.danger : tokens.accent;
    final foreground = _pressed || _hovered ? activeColor : baseColor;
    final background = _pressed || _hovered
        ? (widget.destructive
            ? tokens.dangerContainer.withOpacity(tokens.isDark ? .42 : .56)
            : tokens.surfaceSelected)
        : tokens.transparent;

    return Semantics(
      button: true,
      enabled: widget.enabled,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) {
          if (widget.enabled) setState(() => _hovered = true);
        },
        onExit: (_) {
          if (_hovered) setState(() => _hovered = false);
        },
        child: AnimatedScale(
          scale: _pressed ? .975 : 1,
          duration: widget.reduceMotion
              ? Duration.zero
              : const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: widget.reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 170),
            curve: Curves.easeOutCubic,
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(CommonUiShapes.button),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.enabled ? widget.onPressed : null,
                onHighlightChanged: (value) {
                  if (_pressed == value) return;
                  setState(() => _pressed = value);
                },
                borderRadius: BorderRadius.circular(CommonUiShapes.button),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 44),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedSwitcher(
                          duration: widget.reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 150),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: ScaleTransition(
                                scale: Tween<double>(begin: .82, end: 1)
                                    .animate(animation),
                                child: child,
                              ),
                            );
                          },
                          child: widget.processing
                              ? SizedBox(
                                  key: const ValueKey<String>('processing'),
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.8,
                                    color: activeColor,
                                  ),
                                )
                              : Icon(
                                  widget.icon,
                                  key: ValueKey<String>(
                                    'icon-${widget.icon.codePoint}',
                                  ),
                                  size: 18,
                                  color: widget.enabled
                                      ? foreground
                                      : tokens.textDisabled,
                                ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.label,
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                color: widget.enabled
                                    ? foreground
                                    : tokens.textDisabled,
                                fontWeight: FontWeight.w600,
                                letterSpacing: -.1,
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
      ),
    );
  }
}
