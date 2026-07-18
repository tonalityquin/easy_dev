import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'prompt_ui_theme.dart';

typedef PromptAction = dynamic Function();

enum PromptButtonVariant {
  primary,
  secondary,
  tertiary,
  destructive,
}

enum PromptHaptic {
  none,
  selection,
  light,
  medium,
  heavy,
}

Future<void> _performHaptic(PromptHaptic haptic) async {
  switch (haptic) {
    case PromptHaptic.none:
      return;
    case PromptHaptic.selection:
      await HapticFeedback.selectionClick();
      return;
    case PromptHaptic.light:
      await HapticFeedback.lightImpact();
      return;
    case PromptHaptic.medium:
      await HapticFeedback.mediumImpact();
      return;
    case PromptHaptic.heavy:
      await HapticFeedback.heavyImpact();
      return;
  }
}

Future<void> _invokePromptAction(PromptAction? action) async {
  if (action == null) return;
  final result = action();
  if (result is Future) {
    await result;
  }
}

class PromptButton extends StatefulWidget {
  const PromptButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = PromptButtonVariant.primary,
    this.loading = false,
    this.selected = false,
    this.expand = false,
    this.tooltip,
    this.semanticsLabel,
    this.haptic = PromptHaptic.none,
    this.minHeight,
  });

  final String label;
  final PromptAction? onPressed;
  final IconData? icon;
  final PromptButtonVariant variant;
  final bool loading;
  final bool selected;
  final bool expand;
  final String? tooltip;
  final String? semanticsLabel;
  final PromptHaptic haptic;
  final double? minHeight;

  @override
  State<PromptButton> createState() => _PromptButtonState();
}

class _PromptButtonState extends State<PromptButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool _invoking = false;

  bool get _enabled => widget.onPressed != null && !widget.loading && !_invoking;

  Future<void> _activate() async {
    if (!_enabled) return;
    setState(() => _invoking = true);
    try {
      await _performHaptic(widget.haptic);
      if (!mounted) return;
      await _invokePromptAction(widget.onPressed);
    } finally {
      if (mounted) {
        setState(() {
          _invoking = false;
          _pressed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final colors = _buttonColors(tokens);
    final height = widget.minHeight ??
        (widget.variant == PromptButtonVariant.tertiary ? 46.0 : 52.0);
    final contentScale = _pressed && _enabled ? 0.98 : 1.0;
    final shadows = <BoxShadow>[
      if (_focused)
        BoxShadow(
          color: tokens.focusRing,
          blurRadius: 0,
          spreadRadius: 2,
        )
      else if (_hovered && _enabled)
        BoxShadow(
          color: tokens.shadow,
          blurRadius: 12,
          offset: const Offset(0, 5),
        ),
    ];

    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        child: Stack(
          alignment: Alignment.center,
          children: [
            AnimatedOpacity(
              duration: reduceMotion ? Duration.zero : PromptUiMotion.instant,
              opacity: widget.loading || _invoking ? 0 : 1,
              child: AnimatedScale(
                scale: contentScale,
                duration: reduceMotion ? Duration.zero : PromptUiMotion.press,
                curve: PromptUiMotion.enter,
                child: Row(
                  mainAxisSize:
                      widget.expand ? MainAxisSize.max : MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (widget.icon != null) ...[
                      Icon(widget.icon, size: 20, color: colors.foreground),
                      const SizedBox(width: 8),
                    ],
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              color: colors.foreground,
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                    if (widget.selected) ...[
                      const SizedBox(width: 8),
                      Icon(
                        Icons.check_rounded,
                        size: 18,
                        color: colors.foreground,
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.loading || _invoking)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: colors.foreground,
                ),
              ),
          ],
        ),
      ),
    );

    Widget button = Semantics(
      button: true,
      enabled: _enabled,
      selected: widget.selected,
      label: widget.semanticsLabel ?? widget.label,
      value: widget.loading || _invoking ? '처리 중' : null,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        curve: PromptUiMotion.standard,
        width: widget.expand ? double.infinity : null,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
          border: Border.all(color: colors.border, width: 1),
          boxShadow: shadows,
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(PromptUiShapes.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _enabled ? _activate : null,
            onHighlightChanged: (value) {
              if (_pressed == value) return;
              setState(() => _pressed = value);
            },
            onHover: (value) {
              if (_hovered == value) return;
              setState(() => _hovered = value);
            },
            onFocusChange: (value) {
              if (_focused == value) return;
              setState(() => _focused = value);
            },
            mouseCursor:
                _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            overlayColor: WidgetStatePropertyAll(
              colors.foreground.withOpacity(_pressed ? 0.10 : 0.05),
            ),
            borderRadius: BorderRadius.circular(PromptUiShapes.button),
            child: content,
          ),
        ),
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }

    return button;
  }

  _PromptButtonColors _buttonColors(PromptUiTokens tokens) {
    if (!_enabled && !widget.loading && !_invoking) {
      return _PromptButtonColors(
        background: widget.variant == PromptButtonVariant.tertiary
            ? tokens.transparent
            : tokens.surfaceDisabled,
        foreground: tokens.textDisabled,
        border: widget.variant == PromptButtonVariant.tertiary
            ? tokens.transparent
            : tokens.borderSubtle,
      );
    }

    switch (widget.variant) {
      case PromptButtonVariant.primary:
        return _PromptButtonColors(
          background: _pressed
              ? tokens.accentPressed
              : _hovered
                  ? tokens.accentHover
                  : tokens.accent,
          foreground: tokens.onAccent,
          border: tokens.transparent,
        );
      case PromptButtonVariant.secondary:
        return _PromptButtonColors(
          background: widget.selected || _pressed || _hovered
              ? tokens.surfaceSelected
              : tokens.accentContainer,
          foreground: widget.selected || _pressed
              ? tokens.accentPressed
              : tokens.onAccentContainer,
          border: widget.selected
              ? tokens.accent
              : tokens.accent.withOpacity(tokens.isDark ? 0.62 : 0.46),
        );
      case PromptButtonVariant.tertiary:
        return _PromptButtonColors(
          background: _pressed || _hovered || widget.selected
              ? tokens.surfaceSelected
              : tokens.transparent,
          foreground: _pressed || widget.selected
              ? tokens.accentPressed
              : tokens.accent,
          border: tokens.transparent,
        );
      case PromptButtonVariant.destructive:
        return _PromptButtonColors(
          background: _pressed ? tokens.danger : tokens.dangerContainer,
          foreground: _pressed ? tokens.onDanger : tokens.onDangerContainer,
          border: tokens.danger,
        );
    }
  }
}

class _PromptButtonColors {
  const _PromptButtonColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

class PromptIconButton extends StatefulWidget {
  const PromptIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.loading = false,
    this.destructive = false,
    this.haptic = PromptHaptic.none,
    this.size = 46,
    this.iconSize = 22,
  });

  final IconData icon;
  final String tooltip;
  final PromptAction? onPressed;
  final bool selected;
  final bool loading;
  final bool destructive;
  final PromptHaptic haptic;
  final double size;
  final double iconSize;

  @override
  State<PromptIconButton> createState() => _PromptIconButtonState();
}

class _PromptIconButtonState extends State<PromptIconButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool _invoking = false;

  bool get _enabled => widget.onPressed != null && !widget.loading && !_invoking;

  Future<void> _activate() async {
    if (!_enabled) return;
    setState(() => _invoking = true);
    try {
      await _performHaptic(widget.haptic);
      if (!mounted) return;
      await _invokePromptAction(widget.onPressed);
    } finally {
      if (mounted) {
        setState(() {
          _invoking = false;
          _pressed = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final background = !_enabled && !widget.loading && !_invoking
        ? tokens.transparent
        : widget.selected
            ? tokens.accentContainer
            : _pressed || _hovered
                ? tokens.surfaceSelected
                : tokens.surface;
    final foreground = !_enabled && !widget.loading && !_invoking
        ? tokens.iconDisabled
        : widget.destructive
            ? tokens.danger
            : widget.selected || _pressed
                ? tokens.accentPressed
                : tokens.iconPrimary;
    final border = widget.selected
        ? tokens.accent
        : background == tokens.transparent
            ? tokens.transparent
            : tokens.borderSubtle;
    final shadows = <BoxShadow>[
      if (_focused)
        BoxShadow(
          color: tokens.focusRing,
          blurRadius: 0,
          spreadRadius: 2,
        ),
    ];

    return Tooltip(
      message: widget.tooltip,
      child: Semantics(
        button: true,
        enabled: _enabled,
        selected: widget.selected,
        label: widget.tooltip,
        value: widget.loading || _invoking ? '처리 중' : null,
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(PromptUiShapes.control),
            border: Border.all(color: border, width: 1),
            boxShadow: shadows,
          ),
          child: Material(
            color: tokens.transparent,
            borderRadius: BorderRadius.circular(PromptUiShapes.control),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _enabled ? _activate : null,
              onHighlightChanged: (value) {
                if (_pressed == value) return;
                setState(() => _pressed = value);
              },
              onHover: (value) {
                if (_hovered == value) return;
                setState(() => _hovered = value);
              },
              onFocusChange: (value) {
                if (_focused == value) return;
                setState(() => _focused = value);
              },
              mouseCursor:
                  _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
              child: Center(
                child: widget.loading || _invoking
                    ? SizedBox(
                        width: 19,
                        height: 19,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: foreground,
                        ),
                      )
                    : AnimatedScale(
                        scale: _pressed && _enabled ? 0.92 : 1,
                        duration: reduceMotion
                            ? Duration.zero
                            : PromptUiMotion.press,
                        curve: PromptUiMotion.enter,
                        child: Icon(
                          widget.icon,
                          size: widget.iconSize,
                          color: foreground,
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

class PromptAnimatedReveal extends StatefulWidget {
  const PromptAnimatedReveal({
    super.key,
    required this.child,
    this.offset = const Offset(0, 0.04),
    this.delay = Duration.zero,
    this.duration = PromptUiMotion.component,
  });

  final Widget child;
  final Offset offset;
  final Duration delay;
  final Duration duration;

  @override
  State<PromptAnimatedReveal> createState() => _PromptAnimatedRevealState();
}

class _PromptAnimatedRevealState extends State<PromptAnimatedReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _position;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: widget.duration);
    final curve = CurvedAnimation(
      parent: _controller,
      curve: PromptUiMotion.enter,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _position = Tween<Offset>(
      begin: widget.offset,
      end: Offset.zero,
    ).animate(curve);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      void start() {
        if (!mounted) return;
        if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
          _controller.value = 1;
        } else {
          _controller.forward();
        }
      }

      if (widget.delay == Duration.zero) {
        start();
      } else {
        _timer = Timer(widget.delay, start);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _position, child: widget.child),
    );
  }
}

class PromptSheetScaffold extends StatefulWidget {
  const PromptSheetScaffold({
    super.key,
    required this.title,
    required this.icon,
    required this.body,
    required this.onClose,
    this.bodyExpanded = true,
  });

  final String title;
  final IconData icon;
  final Widget body;
  final VoidCallback onClose;
  final bool bodyExpanded;

  @override
  State<PromptSheetScaffold> createState() => _PromptSheetScaffoldState();
}

class _PromptSheetScaffoldState extends State<PromptSheetScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: PromptUiMotion.overlay,
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: PromptUiMotion.enter,
      reverseCurve: PromptUiMotion.exit,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _position = Tween<Offset>(
      begin: const Offset(0, 0.035),
      end: Offset.zero,
    ).animate(curve);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final body = widget.bodyExpanded ? Expanded(child: widget.body) : widget.body;
    final shape = RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(PromptUiShapes.sheet),
      ),
      side: BorderSide(color: tokens.borderSubtle),
    );

    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _position,
        child: Material(
          color: tokens.surfaceRaised,
          surfaceTintColor: tokens.transparent,
          shadowColor: tokens.shadow,
          elevation: 0,
          shape: shape,
          clipBehavior: Clip.antiAlias,
          child: SafeArea(
            top: false,
            minimum: const EdgeInsets.only(bottom: 8),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 32,
                  height: 4,
                  decoration: BoxDecoration(
                    color: tokens.handle,
                    borderRadius: BorderRadius.circular(PromptUiShapes.pill),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: tokens.accentContainer,
                          borderRadius:
                              BorderRadius.circular(PromptUiShapes.control),
                          border: Border.all(
                            color: tokens.accent.withOpacity(
                              tokens.isDark ? 0.54 : 0.36,
                            ),
                          ),
                        ),
                        child: Icon(
                          widget.icon,
                          size: 20,
                          color: tokens.onAccentContainer,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: text.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      PromptIconButton(
                        icon: Icons.close_rounded,
                        tooltip: '닫기',
                        onPressed: widget.onClose,
                        haptic: PromptHaptic.selection,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Divider(height: 1, color: tokens.borderSubtle),
                body,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PromptDialogFrame extends StatefulWidget {
  const PromptDialogFrame({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<PromptDialogFrame> createState() => _PromptDialogFrameState();
}

class _PromptDialogFrameState extends State<PromptDialogFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: PromptUiMotion.component,
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: PromptUiMotion.enter,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _scale = Tween<double>(begin: 0.96, end: 1).animate(curve);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return FadeTransition(
      opacity: _opacity,
      child: ScaleTransition(
        scale: _scale,
        child: Dialog(
          backgroundColor: tokens.surfaceRaised,
          surfaceTintColor: tokens.transparent,
          shadowColor: tokens.shadow,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PromptUiShapes.dialog),
            side: BorderSide(color: tokens.borderSubtle),
          ),
          child: SafeArea(
            minimum: const EdgeInsets.all(16),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

Future<T?> showPromptDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final tokens = PromptUiTheme.of(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: tokens.scrim,
    builder: (dialogContext) {
      return PromptUiScope(
        child: PromptDialogFrame(child: builder(dialogContext)),
      );
    },
  );
}
