import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class CommonQuickActionSurface extends StatelessWidget {
  const CommonQuickActionSurface({
    super.key,
    required this.backgroundColor,
    required this.borderColor,
    required this.child,
  });

  static const double height = 48;
  static const double verticalPadding = 2;

  final Color backgroundColor;
  final Color borderColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      padding: const EdgeInsets.symmetric(vertical: verticalPadding),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          top: BorderSide(color: borderColor),
        ),
      ),
      child: child,
    );
  }
}

class CommonQuickActionControl extends StatefulWidget {
  const CommonQuickActionControl({
    super.key,
    required this.semanticsLabel,
    required this.icon,
    required this.foreground,
    required this.onPressed,
    this.showProgressWhileRunning = true,
  });

  final String semanticsLabel;
  final IconData icon;
  final Color foreground;
  final Future<void> Function(Rect sourceRect)? onPressed;
  final bool showProgressWhileRunning;

  @override
  State<CommonQuickActionControl> createState() =>
      _CommonQuickActionControlState();
}

class _CommonQuickActionControlState extends State<CommonQuickActionControl> {
  bool _pressed = false;
  bool _running = false;

  Future<void> _invoke() async {
    final action = widget.onPressed;
    if (_running || action == null) return;
    setState(() {
      _running = true;
    });
    HapticFeedback.selectionClick();
    final renderObject = context.findRenderObject();
    final sourceRect = renderObject is RenderBox && renderObject.hasSize
        ? (() {
            final origin = renderObject.localToGlobal(Offset.zero);
            final extent = math.min(44.0, renderObject.size.shortestSide);
            final center = origin + renderObject.size.center(Offset.zero);
            return Rect.fromCenter(
              center: center,
              width: extent,
              height: extent,
            );
          })()
        : Rect.fromCenter(
            center: MediaQuery.sizeOf(context).center(Offset.zero),
            width: 44,
            height: 44,
          );
    try {
      await action(sourceRect);
    } finally {
      if (!mounted) return;
      setState(() {
        _running = false;
        _pressed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = widget.onPressed != null && !_running;
    return Semantics(
      button: true,
      label: widget.semanticsLabel,
      enabled: enabled,
      child: AnimatedScale(
        scale: _pressed ? .95 : 1,
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 120),
        curve: Curves.easeOutCubic,
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            radius: 24,
            containedInkWell: true,
            highlightShape: BoxShape.circle,
            onTap: enabled ? () => unawaited(_invoke()) : null,
            onTapDown: enabled
                ? (_) {
                    setState(() {
                      _pressed = true;
                    });
                  }
                : null,
            onTapUp: enabled
                ? (_) {
                    setState(() {
                      _pressed = false;
                    });
                  }
                : null,
            onTapCancel: enabled
                ? () {
                    setState(() {
                      _pressed = false;
                    });
                  }
                : null,
            child: SizedBox.expand(
              child: Center(
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 160),
                  child: _running && widget.showProgressWhileRunning
                      ? SizedBox(
                          key: const ValueKey<String>('running'),
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            color: widget.foreground,
                          ),
                        )
                      : Icon(
                          widget.icon,
                          key: const ValueKey<String>('icon'),
                          size: 24,
                          color: widget.foreground,
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
