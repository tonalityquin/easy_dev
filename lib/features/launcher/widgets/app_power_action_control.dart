import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/common_ui/common_ui_theme.dart';

enum AppPowerActionVisualState {
  idle,
  processing,
  success,
  failure,
}

class AppPowerActionControl extends StatefulWidget {
  const AppPowerActionControl({
    super.key,
    required this.semanticLabel,
    required this.onPressed,
    this.enabled = true,
    this.state = AppPowerActionVisualState.idle,
    this.size = 94,
    this.iconSize = 48,
  });

  final String semanticLabel;
  final Future<void> Function() onPressed;
  final bool enabled;
  final AppPowerActionVisualState state;
  final double size;
  final double iconSize;

  @override
  State<AppPowerActionControl> createState() => _AppPowerActionControlState();
}

class _AppPowerActionControlState extends State<AppPowerActionControl>
    with TickerProviderStateMixin {
  late final AnimationController _pressController;
  late final AnimationController _processingController;
  bool _pressing = false;

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  bool get _interactive =>
      widget.enabled &&
      widget.state != AppPowerActionVisualState.processing &&
      !_pressing;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _processingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncProcessingAnimation();
  }

  @override
  void didUpdateWidget(covariant AppPowerActionControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.state != widget.state) {
      _syncProcessingAnimation();
    }
  }

  void _syncProcessingAnimation() {
    if (widget.state == AppPowerActionVisualState.processing && !_reduceMotion) {
      if (!_processingController.isAnimating) {
        _processingController.repeat();
      }
      return;
    }
    _processingController.stop();
    _processingController.value = 0;
  }

  Future<void> _handlePressed() async {
    if (!_interactive) return;
    setState(() => _pressing = true);
    await HapticFeedback.mediumImpact();
    if (_reduceMotion) {
      _pressController.value = 1;
    } else {
      await _pressController.forward(from: 0);
    }
    if (!mounted) return;
    setState(() => _pressing = false);
    await widget.onPressed();
  }

  Color _accent(CommonUiTokens tokens) {
    switch (widget.state) {
      case AppPowerActionVisualState.idle:
        return tokens.accent;
      case AppPowerActionVisualState.processing:
        return tokens.accent;
      case AppPowerActionVisualState.success:
        return tokens.success;
      case AppPowerActionVisualState.failure:
        return tokens.danger;
    }
  }

  Color _container(CommonUiTokens tokens) {
    switch (widget.state) {
      case AppPowerActionVisualState.idle:
        return tokens.surfaceRaised;
      case AppPowerActionVisualState.processing:
        return tokens.accentContainer;
      case AppPowerActionVisualState.success:
        return tokens.successContainer;
      case AppPowerActionVisualState.failure:
        return tokens.dangerContainer;
    }
  }

  IconData _icon() {
    switch (widget.state) {
      case AppPowerActionVisualState.success:
        return Icons.check_rounded;
      case AppPowerActionVisualState.idle:
      case AppPowerActionVisualState.processing:
      case AppPowerActionVisualState.failure:
        return Icons.power_settings_new_rounded;
    }
  }

  @override
  void dispose() {
    _pressController.dispose();
    _processingController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final accent = _accent(tokens);
    final diameter = widget.size;

    return Semantics(
      button: true,
      enabled: _interactive,
      label: widget.semanticLabel,
      child: AnimatedBuilder(
        animation: Listenable.merge([
          _pressController,
          _processingController,
        ]),
        builder: (context, child) {
          final value = _pressController.value;
          final press = math.sin(value * math.pi);
          final scale = _reduceMotion ? 1.0 : 1.0 - (0.08 * press);
          final ringOpacity = _reduceMotion ? 0.0 : 0.24 * press;
          final processing =
              widget.state == AppPowerActionVisualState.processing;

          return Transform.scale(
            scale: scale,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (ringOpacity > 0)
                  Opacity(
                    opacity: ringOpacity,
                    child: Container(
                      width: diameter + 18 + (value * 28),
                      height: diameter + 18 + (value * 28),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: tokens.accentContainer,
                        border: Border.all(
                          color: tokens.accent.withOpacity(0.5),
                        ),
                      ),
                    ),
                  ),
                if (processing)
                  RotationTransition(
                    turns: _processingController,
                    child: SizedBox(
                      width: diameter + 22,
                      height: diameter + 22,
                      child: CircularProgressIndicator(
                        value: 0.72,
                        strokeWidth: 2.2,
                        color: accent,
                        backgroundColor: tokens.borderSubtle,
                      ),
                    ),
                  ),
                AnimatedContainer(
                  duration: _reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  width: diameter,
                  height: diameter,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _container(tokens),
                    border: Border.all(
                      color: widget.state == AppPowerActionVisualState.idle
                          ? tokens.borderSubtle
                          : accent.withOpacity(tokens.isDark ? 0.72 : 0.52),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withOpacity(
                          widget.state == AppPowerActionVisualState.idle
                              ? 0.06
                              : 0.16,
                        ),
                        blurRadius: widget.state == AppPowerActionVisualState.idle
                            ? 18
                            : 28,
                        spreadRadius:
                            widget.state == AppPowerActionVisualState.idle ? 0 : 2,
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _interactive ? _handlePressed : null,
                      child: Center(
                        child: AnimatedSwitcher(
                          duration: _reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 180),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          child: Icon(
                            _icon(),
                            key: ValueKey<AppPowerActionVisualState>(widget.state),
                            size: widget.iconSize,
                            color: widget.state == AppPowerActionVisualState.idle
                                ? tokens.iconPrimary
                                : accent,
                          ),
                        ),
                      ),
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
