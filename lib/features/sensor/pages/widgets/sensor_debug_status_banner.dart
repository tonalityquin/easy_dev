import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../selector/application/dev_auth.dart';
import '../../applications/sensor_debug_trace.dart';

class SensorDebugStatusBanner extends StatefulWidget {
  const SensorDebugStatusBanner({
    super.key,
    this.bottom = 82,
  });

  final double bottom;

  @override
  State<SensorDebugStatusBanner> createState() =>
      _SensorDebugStatusBannerState();
}

class _SensorDebugStatusBannerState extends State<SensorDebugStatusBanner> {
  static const Duration _visibleDuration = Duration(milliseconds: 2100);

  Timer? _hideTimer;
  SensorDebugStatusEvent? _event;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    SensorDebugTrace.currentStatus.addListener(_handleStatusChanged);
    DevAuth.devModeEnabled.addListener(_handleDevModeChanged);
    _syncFromNotifiers(notify: false);
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    SensorDebugTrace.currentStatus.removeListener(_handleStatusChanged);
    DevAuth.devModeEnabled.removeListener(_handleDevModeChanged);
    super.dispose();
  }

  void _handleStatusChanged() {
    _syncFromNotifiers();
  }

  void _handleDevModeChanged() {
    _syncFromNotifiers();
  }

  void _syncFromNotifiers({bool notify = true}) {
    _hideTimer?.cancel();
    final enabled = DevAuth.devModeEnabled.value;
    final event = SensorDebugTrace.currentStatus.value;
    final visible = enabled && event != null;
    if (notify && mounted) {
      setState(() {
        _event = event;
        _visible = visible;
      });
    } else {
      _event = event;
      _visible = visible;
    }
    if (visible && !event.sticky) {
      _hideTimer = Timer(_visibleDuration, () {
        if (!mounted || _event?.sequence != event.sequence) return;
        setState(() {
          _visible = false;
        });
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 240);
    final event = _event;

    return Positioned(
      left: 12,
      right: 12,
      bottom: widget.bottom,
      child: IgnorePointer(
        child: AnimatedSwitcher(
          duration: duration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            if (reduceMotion) {
              return FadeTransition(opacity: animation, child: child);
            }
            final curved = CurvedAnimation(
              parent: animation,
              curve: Curves.easeOutCubic,
              reverseCurve: Curves.easeInCubic,
            );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, 0.16),
                  end: Offset.zero,
                ).animate(curved),
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
                  child: child,
                ),
              ),
            );
          },
          child: !_visible || event == null
              ? const SizedBox.shrink(
                  key: ValueKey<String>('sensor-debug-status-hidden'),
                )
              : Center(
                  key: ValueKey<int>(event.sequence),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 430),
                    child: _SensorDebugStatusCard(event: event),
                  ),
                ),
        ),
      ),
    );
  }
}

class _SensorDebugStatusCard extends StatelessWidget {
  const _SensorDebugStatusCard({required this.event});

  final SensorDebugStatusEvent event;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final foreground = _foreground(tokens);
    final background = _background(tokens);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: background.withOpacity(0.96),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: foreground.withOpacity(0.72)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.shadow.withOpacity(0.22),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 22,
              height: 22,
              child: _StatusIcon(
                tone: event.tone,
                color: foreground,
              ),
            ),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    event.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.labelLarge?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.1,
                    ),
                  ),
                  if (event.detail != null) ...<Widget>[
                    const SizedBox(height: 2),
                    Text(
                      event.detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.bodySmall?.copyWith(
                        color: foreground.withOpacity(0.9),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _foreground(CommonUiTokens tokens) {
    switch (event.tone) {
      case SensorDebugStatusTone.progress:
        return tokens.onInfoContainer;
      case SensorDebugStatusTone.success:
        return tokens.onSuccessContainer;
      case SensorDebugStatusTone.warning:
        return tokens.onWarningContainer;
      case SensorDebugStatusTone.error:
        return tokens.onDangerContainer;
      case SensorDebugStatusTone.info:
        return tokens.onAccentContainer;
    }
  }

  Color _background(CommonUiTokens tokens) {
    switch (event.tone) {
      case SensorDebugStatusTone.progress:
        return tokens.infoContainer;
      case SensorDebugStatusTone.success:
        return tokens.successContainer;
      case SensorDebugStatusTone.warning:
        return tokens.warningContainer;
      case SensorDebugStatusTone.error:
        return tokens.dangerContainer;
      case SensorDebugStatusTone.info:
        return tokens.accentContainer;
    }
  }
}

class _StatusIcon extends StatelessWidget {
  const _StatusIcon({
    required this.tone,
    required this.color,
  });

  final SensorDebugStatusTone tone;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (tone == SensorDebugStatusTone.progress) {
      return Padding(
        padding: const EdgeInsets.all(2),
        child: CircularProgressIndicator(
          strokeWidth: 2.2,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        ),
      );
    }
    IconData icon;
    switch (tone) {
      case SensorDebugStatusTone.success:
        icon = Icons.check_circle_rounded;
        break;
      case SensorDebugStatusTone.warning:
        icon = Icons.warning_amber_rounded;
        break;
      case SensorDebugStatusTone.error:
        icon = Icons.error_rounded;
        break;
      case SensorDebugStatusTone.info:
        icon = Icons.sensors_rounded;
        break;
      case SensorDebugStatusTone.progress:
        icon = Icons.sync_rounded;
        break;
    }
    return Icon(icon, size: 22, color: color);
  }
}
