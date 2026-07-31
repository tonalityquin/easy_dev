import 'dart:async';

import 'package:flutter/material.dart';

import '../../design_system/common_ui/common_ui_theme.dart';

void showCustomSnackBar({
  required BuildContext context,
  required String message,
  required Color backgroundColor,
  required IconData icon,
  Color iconColor = Colors.white,
  Color textColor = Colors.white,
  Color? borderColor,
  Duration duration = const Duration(seconds: 5),
  VoidCallback? onTap,
  bool useCommonUi = false,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);

  late final OverlayEntry overlayEntry;

  if (useCommonUi) {
    overlayEntry = OverlayEntry(
      builder: (context) => _CommonSnackbarOverlay(
        backgroundColor: backgroundColor,
        borderColor: borderColor ?? backgroundColor,
        icon: icon,
        iconColor: iconColor,
        textColor: textColor,
        message: message,
        duration: duration,
        onTap: onTap,
        onDismiss: () {
          if (overlayEntry.mounted) {
            overlayEntry.remove();
          }
        },
      ),
    );
  } else {
    overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: MediaQuery.of(context).padding.top + 20,
        left: 20,
        right: 20,
        child: GestureDetector(
          onTap: () {
            overlayEntry.remove();
            onTap?.call();
          },
          child: _SnackbarContainer(
            color: backgroundColor,
            icon: icon,
            iconColor: iconColor,
            message: message,
          ),
        ),
      ),
    );
  }

  overlay.insert(overlayEntry);

  if (!useCommonUi) {
    Future.delayed(duration, () {
      if (overlayEntry.mounted) overlayEntry.remove();
    });
  }
}

void showSuccessSnackbar(
  BuildContext context,
  String message, {
  bool useCommonUi = false,
}) {
  if (useCommonUi) {
    final tokens = CommonUiTheme.of(context);
    showCustomSnackBar(
      context: context,
      message: message,
      backgroundColor: tokens.successContainer,
      borderColor: tokens.success.withOpacity(tokens.isDark ? 0.58 : 0.36),
      icon: Icons.check_circle_outline_rounded,
      iconColor: tokens.success,
      textColor: tokens.onSuccessContainer,
      useCommonUi: true,
    );
    return;
  }

  showCustomSnackBar(
    context: context,
    message: message,
    backgroundColor: Colors.green,
    icon: Icons.check_circle_outline,
  );
}

void showFailedSnackbar(
  BuildContext context,
  String message, {
  bool useCommonUi = false,
}) {
  if (useCommonUi) {
    final tokens = CommonUiTheme.of(context);
    showCustomSnackBar(
      context: context,
      message: message,
      backgroundColor: tokens.dangerContainer,
      borderColor: tokens.danger.withOpacity(tokens.isDark ? 0.58 : 0.36),
      icon: Icons.error_outline_rounded,
      iconColor: tokens.danger,
      textColor: tokens.onDangerContainer,
      useCommonUi: true,
    );
    return;
  }

  showCustomSnackBar(
    context: context,
    message: message,
    backgroundColor: Colors.redAccent,
    icon: Icons.error_outline,
  );
}

void showSelectedSnackbar(
  BuildContext context,
  String message, {
  bool useCommonUi = false,
}) {
  if (useCommonUi) {
    final tokens = CommonUiTheme.of(context);
    showCustomSnackBar(
      context: context,
      message: message,
      backgroundColor: tokens.warningContainer,
      borderColor: tokens.warning.withOpacity(tokens.isDark ? 0.58 : 0.36),
      icon: Icons.warning_amber_rounded,
      iconColor: tokens.warning,
      textColor: tokens.onWarningContainer,
      useCommonUi: true,
    );
    return;
  }

  showCustomSnackBar(
    context: context,
    message: message,
    backgroundColor: Colors.yellow[800]!,
    icon: Icons.warning_amber_rounded,
    iconColor: Colors.black,
  );
}

class _CommonSnackbarOverlay extends StatefulWidget {
  const _CommonSnackbarOverlay({
    required this.backgroundColor,
    required this.borderColor,
    required this.icon,
    required this.iconColor,
    required this.textColor,
    required this.message,
    required this.duration,
    required this.onDismiss,
    this.onTap,
  });

  final Color backgroundColor;
  final Color borderColor;
  final IconData icon;
  final Color iconColor;
  final Color textColor;
  final String message;
  final Duration duration;
  final VoidCallback onDismiss;
  final VoidCallback? onTap;

  @override
  State<_CommonSnackbarOverlay> createState() =>
      _CommonSnackbarOverlayState();
}

class _CommonSnackbarOverlayState extends State<_CommonSnackbarOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _position;
  Timer? _timer;
  bool _started = false;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: CommonUiMotion.component,
      reverseDuration: CommonUiMotion.selection,
    );
    final curve = CurvedAnimation(
      parent: _controller,
      curve: CommonUiMotion.enter,
      reverseCurve: CommonUiMotion.exit,
    );
    _opacity = Tween<double>(begin: 0, end: 1).animate(curve);
    _position = Tween<Offset>(
      begin: const Offset(0, -0.16),
      end: Offset.zero,
    ).animate(curve);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
    _timer = Timer(widget.duration, _dismiss);
  }

  Future<void> _dismiss() async {
    if (_dismissing) return;
    _dismissing = true;
    _timer?.cancel();
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (!reduceMotion && _controller.value > 0) {
      await _controller.reverse();
    }
    if (mounted) {
      widget.onDismiss();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final text = Theme.of(context).textTheme;

    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: FadeTransition(
        opacity: _opacity,
        child: SlideTransition(
          position: _position,
          child: Material(
            color: tokens.transparent,
            child: Semantics(
              liveRegion: true,
              label: widget.message,
              child: GestureDetector(
                onTap: () async {
                  widget.onTap?.call();
                  await _dismiss();
                },
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 640),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: widget.backgroundColor,
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                    border: Border.all(color: widget.borderColor),
                    boxShadow: [
                      BoxShadow(
                        color: tokens.shadow,
                        blurRadius: 16,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.icon,
                        color: widget.iconColor,
                        size: 22,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.message,
                          style: text.bodyMedium?.copyWith(
                            color: widget.textColor,
                            fontWeight: FontWeight.w600,
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

class _SnackbarContainer extends StatelessWidget {
  const _SnackbarContainer({
    required this.color,
    required this.icon,
    required this.message,
    this.iconColor = Colors.white,
  });

  final Color color;
  final IconData icon;
  final String message;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 8,
              offset: Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
