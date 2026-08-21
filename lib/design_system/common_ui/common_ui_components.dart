import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'common_ui_theme.dart';

typedef CommonAction = dynamic Function();

enum CommonButtonVariant {
  primary,
  secondary,
  tertiary,
  destructive,
}

enum CommonHaptic {
  none,
  selection,
  light,
  medium,
  heavy,
}

Future<void> _performHaptic(CommonHaptic haptic) async {
  switch (haptic) {
    case CommonHaptic.none:
      return;
    case CommonHaptic.selection:
      await HapticFeedback.selectionClick();
      return;
    case CommonHaptic.light:
      await HapticFeedback.lightImpact();
      return;
    case CommonHaptic.medium:
      await HapticFeedback.mediumImpact();
      return;
    case CommonHaptic.heavy:
      await HapticFeedback.heavyImpact();
      return;
  }
}

Future<void> _invokeCommonAction(CommonAction? action) async {
  if (action == null) return;
  final result = action();
  if (result is Future) {
    await result;
  }
}

class CommonButton extends StatefulWidget {
  const CommonButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.variant = CommonButtonVariant.primary,
    this.loading = false,
    this.selected = false,
    this.expand = false,
    this.tooltip,
    this.semanticsLabel,
    this.haptic = CommonHaptic.none,
    this.minHeight,
  });

  final String label;
  final CommonAction? onPressed;
  final IconData? icon;
  final CommonButtonVariant variant;
  final bool loading;
  final bool selected;
  final bool expand;
  final String? tooltip;
  final String? semanticsLabel;
  final CommonHaptic haptic;
  final double? minHeight;

  @override
  State<CommonButton> createState() => _CommonButtonState();
}

class _CommonButtonState extends State<CommonButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool _invoking = false;
  bool? _pendingPressed;
  bool? _pendingHovered;
  bool? _pendingFocused;
  bool _interactionFrameScheduled = false;

  bool get _available => widget.onPressed != null && !widget.loading;
  bool get _enabled => _available && !_invoking;

  void _queueInteractionState({
    bool? pressed,
    bool? hovered,
    bool? focused,
  }) {
    if (pressed != null) _pendingPressed = pressed;
    if (hovered != null) _pendingHovered = hovered;
    if (focused != null) _pendingFocused = focused;
    if (_interactionFrameScheduled) return;
    _interactionFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _interactionFrameScheduled = false;
      if (!mounted) return;
      final nextPressed = _pendingPressed;
      final nextHovered = _pendingHovered;
      final nextFocused = _pendingFocused;
      _pendingPressed = null;
      _pendingHovered = null;
      _pendingFocused = null;
      final changed =
          (nextPressed != null && nextPressed != _pressed) ||
              (nextHovered != null && nextHovered != _hovered) ||
              (nextFocused != null && nextFocused != _focused);
      if (!changed) return;
      setState(() {
        if (nextPressed != null) _pressed = nextPressed;
        if (nextHovered != null) _hovered = nextHovered;
        if (nextFocused != null) _focused = nextFocused;
      });
    });
  }

  Future<void> _activate() async {
    if (!_enabled) return;
    setState(() => _invoking = true);
    try {
      await _performHaptic(widget.haptic);
      if (!mounted) return;
      await _invokeCommonAction(widget.onPressed);
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
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final colors = _buttonColors(tokens);
    final height = widget.minHeight ??
        (widget.variant == CommonButtonVariant.tertiary ? 46.0 : 52.0);
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
              duration: reduceMotion ? Duration.zero : CommonUiMotion.instant,
              opacity: widget.loading || _invoking ? 0 : 1,
              child: AnimatedScale(
                scale: contentScale,
                duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
                curve: CommonUiMotion.enter,
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
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        width: widget.expand ? double.infinity : null,
        decoration: BoxDecoration(
          color: colors.background,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          border: Border.all(color: colors.border, width: 1),
          boxShadow: shadows,
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(CommonUiShapes.button),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _available ? _activate : null,
            onHighlightChanged: (value) {
              if (_pressed == value && _pendingPressed == null) return;
              _queueInteractionState(pressed: value);
            },
            onHover: (value) {
              if (_hovered == value && _pendingHovered == null) return;
              _queueInteractionState(hovered: value);
            },
            onFocusChange: (value) {
              if (_focused == value && _pendingFocused == null) return;
              _queueInteractionState(focused: value);
            },
            mouseCursor:
                _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
            overlayColor: WidgetStatePropertyAll(
              colors.foreground.withOpacity(_pressed ? 0.10 : 0.05),
            ),
            borderRadius: BorderRadius.circular(CommonUiShapes.button),
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

  _CommonButtonColors _buttonColors(CommonUiTokens tokens) {
    if (!_enabled && !widget.loading && !_invoking) {
      return _CommonButtonColors(
        background: widget.variant == CommonButtonVariant.tertiary
            ? tokens.transparent
            : tokens.surfaceDisabled,
        foreground: tokens.textDisabled,
        border: widget.variant == CommonButtonVariant.tertiary
            ? tokens.transparent
            : tokens.borderSubtle,
      );
    }

    switch (widget.variant) {
      case CommonButtonVariant.primary:
        return _CommonButtonColors(
          background: _pressed
              ? tokens.accentPressed
              : _hovered
                  ? tokens.accentHover
                  : tokens.accent,
          foreground: tokens.onAccent,
          border: tokens.transparent,
        );
      case CommonButtonVariant.secondary:
        return _CommonButtonColors(
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
      case CommonButtonVariant.tertiary:
        return _CommonButtonColors(
          background: _pressed || _hovered || widget.selected
              ? tokens.surfaceSelected
              : tokens.transparent,
          foreground: _pressed || widget.selected
              ? tokens.accentPressed
              : tokens.accent,
          border: tokens.transparent,
        );
      case CommonButtonVariant.destructive:
        return _CommonButtonColors(
          background: _pressed ? tokens.danger : tokens.dangerContainer,
          foreground: _pressed ? tokens.onDanger : tokens.onDangerContainer,
          border: tokens.danger,
        );
    }
  }
}

class _CommonButtonColors {
  const _CommonButtonColors({
    required this.background,
    required this.foreground,
    required this.border,
  });

  final Color background;
  final Color foreground;
  final Color border;
}

class CommonIconButton extends StatefulWidget {
  const CommonIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.loading = false,
    this.destructive = false,
    this.haptic = CommonHaptic.none,
    this.size = 46,
    this.iconSize = 22,
  });

  final IconData icon;
  final String tooltip;
  final CommonAction? onPressed;
  final bool selected;
  final bool loading;
  final bool destructive;
  final CommonHaptic haptic;
  final double size;
  final double iconSize;

  @override
  State<CommonIconButton> createState() => _CommonIconButtonState();
}

class _CommonIconButtonState extends State<CommonIconButton> {
  bool _pressed = false;
  bool _hovered = false;
  bool _focused = false;
  bool _invoking = false;
  bool? _pendingPressed;
  bool? _pendingHovered;
  bool? _pendingFocused;
  bool _interactionFrameScheduled = false;

  bool get _available => widget.onPressed != null && !widget.loading;
  bool get _enabled => _available && !_invoking;

  void _queueInteractionState({
    bool? pressed,
    bool? hovered,
    bool? focused,
  }) {
    if (pressed != null) _pendingPressed = pressed;
    if (hovered != null) _pendingHovered = hovered;
    if (focused != null) _pendingFocused = focused;
    if (_interactionFrameScheduled) return;
    _interactionFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _interactionFrameScheduled = false;
      if (!mounted) return;
      final nextPressed = _pendingPressed;
      final nextHovered = _pendingHovered;
      final nextFocused = _pendingFocused;
      _pendingPressed = null;
      _pendingHovered = null;
      _pendingFocused = null;
      final changed =
          (nextPressed != null && nextPressed != _pressed) ||
              (nextHovered != null && nextHovered != _hovered) ||
              (nextFocused != null && nextFocused != _focused);
      if (!changed) return;
      setState(() {
        if (nextPressed != null) _pressed = nextPressed;
        if (nextHovered != null) _hovered = nextHovered;
        if (nextFocused != null) _focused = nextFocused;
      });
    });
  }

  Future<void> _activate() async {
    if (!_enabled) return;
    setState(() => _invoking = true);
    try {
      await _performHaptic(widget.haptic);
      if (!mounted) return;
      await _invokeCommonAction(widget.onPressed);
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
    final tokens = CommonUiTheme.of(context);
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
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            border: Border.all(color: border, width: 1),
            boxShadow: shadows,
          ),
          child: Material(
            color: tokens.transparent,
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: _available ? _activate : null,
              onHighlightChanged: (value) {
                if (_pressed == value && _pendingPressed == null) return;
                _queueInteractionState(pressed: value);
              },
              onHover: (value) {
                if (_hovered == value && _pendingHovered == null) return;
                _queueInteractionState(hovered: value);
              },
              onFocusChange: (value) {
                if (_focused == value && _pendingFocused == null) return;
                _queueInteractionState(focused: value);
              },
              mouseCursor:
                  _enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
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
                            : CommonUiMotion.press,
                        curve: CommonUiMotion.enter,
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

class CommonAnimatedReveal extends StatefulWidget {
  const CommonAnimatedReveal({
    super.key,
    required this.child,
    this.offset = const Offset(0, 0.04),
    this.delay = Duration.zero,
    this.duration = CommonUiMotion.component,
  });

  final Widget child;
  final Offset offset;
  final Duration delay;
  final Duration duration;

  @override
  State<CommonAnimatedReveal> createState() => _CommonAnimatedRevealState();
}

class _CommonAnimatedRevealState extends State<CommonAnimatedReveal>
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
      curve: CommonUiMotion.enter,
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

class CommonSheetScaffold extends StatefulWidget {
  const CommonSheetScaffold({
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
  State<CommonSheetScaffold> createState() => _CommonSheetScaffoldState();
}

class _CommonSheetScaffoldState extends State<CommonSheetScaffold>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: CommonUiMotion.overlay,
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: CommonUiMotion.enter,
      reverseCurve: CommonUiMotion.exit,
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
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;
    final body = widget.bodyExpanded ? Expanded(child: widget.body) : widget.body;
    final shape = RoundedRectangleBorder(
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(CommonUiShapes.sheet),
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
                    borderRadius: BorderRadius.circular(CommonUiShapes.pill),
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
                              BorderRadius.circular(CommonUiShapes.control),
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
                      CommonIconButton(
                        icon: Icons.close_rounded,
                        tooltip: '닫기',
                        onPressed: widget.onClose,
                        haptic: CommonHaptic.selection,
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

class CommonDialogFrame extends StatefulWidget {
  const CommonDialogFrame({
    super.key,
    required this.child,
    this.animate = true,
  });

  final Widget child;
  final bool animate;

  @override
  State<CommonDialogFrame> createState() => _CommonDialogFrameState();
}

class _CommonDialogFrameState extends State<CommonDialogFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: CommonUiMotion.component,
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: CommonUiMotion.enter,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _scale = Tween<double>(begin: 0.96, end: 1).animate(curve);
    if (!widget.animate) {
      _controller.value = 1;
      return;
    }
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
    final tokens = CommonUiTheme.of(context);
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
            borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
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

Future<T?> showCommonDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
}) {
  final tokens = CommonUiTheme.of(context);
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: tokens.scrim,
    builder: (dialogContext) {
      return CommonUiScope(
        child: CommonDialogFrame(child: builder(dialogContext)),
      );
    },
  );
}
