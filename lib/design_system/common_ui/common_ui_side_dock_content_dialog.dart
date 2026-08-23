import 'package:flutter/material.dart';

import 'common_ui_components.dart';
import 'common_ui_theme.dart';

class CommonSideDockContentDialogHost extends StatefulWidget {
  const CommonSideDockContentDialogHost({
    super.key,
    required this.child,
    required this.activeKey,
    required this.dialog,
    required this.originAlignment,
    required this.onDismiss,
    this.widthFactor = .96,
    this.heightFactor = .94,
  });

  final Widget child;
  final String? activeKey;
  final Widget? dialog;
  final Alignment originAlignment;
  final VoidCallback onDismiss;
  final double widthFactor;
  final double heightFactor;

  @override
  State<CommonSideDockContentDialogHost> createState() =>
      _CommonSideDockContentDialogHostState();
}

class _CommonSideDockContentDialogHostState
    extends State<CommonSideDockContentDialogHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Widget? _displayedDialog;
  String? _displayedKey;
  Alignment _displayedOrigin = Alignment.centerLeft;
  int _transitionSerial = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 180),
    );
    if (widget.dialog != null && widget.activeKey != null) {
      _displayedDialog = widget.dialog;
      _displayedKey = widget.activeKey;
      _displayedOrigin = widget.originAlignment;
      _controller.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant CommonSideDockContentDialogHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newKey = widget.activeKey;
    final newDialog = widget.dialog;
    if (newKey == _displayedKey && newDialog != null) {
      _displayedDialog = newDialog;
      _displayedOrigin = widget.originAlignment;
      return;
    }
    _transitionSerial += 1;
    final serial = _transitionSerial;
    if (newDialog == null || newKey == null) {
      _closeDisplayed(serial);
      return;
    }
    _swapDisplayed(serial, newKey, newDialog, widget.originAlignment);
  }

  bool get _reduceMotion =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  Future<void> _closeDisplayed(int serial) async {
    if (_displayedDialog == null) return;
    if (_reduceMotion) {
      _controller.value = 0;
    } else {
      await _controller.reverse();
    }
    if (!mounted || serial != _transitionSerial) return;
    setState(() {
      _displayedDialog = null;
      _displayedKey = null;
    });
  }

  Future<void> _swapDisplayed(
    int serial,
    String key,
    Widget dialog,
    Alignment origin,
  ) async {
    if (_displayedDialog != null) {
      if (_reduceMotion) {
        _controller.value = 0;
      } else {
        await _controller.reverse();
      }
      if (!mounted || serial != _transitionSerial) return;
    }
    setState(() {
      _displayedDialog = dialog;
      _displayedKey = key;
      _displayedOrigin = origin;
    });
    if (_reduceMotion) {
      _controller.value = 1;
    } else {
      await _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          widget.child,
          if (_displayedDialog != null)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = reduceMotion
                      ? 1.0
                      : Curves.easeOutCubic.transform(_controller.value);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      IgnorePointer(
                        ignoring: t < .98,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: widget.onDismiss,
                          child: ColoredBox(
                            color: CommonUiTheme.of(context)
                                .scrim
                                .withOpacity(.22 * t),
                          ),
                        ),
                      ),
                      Center(
                        child: FractionallySizedBox(
                          widthFactor: widget.widthFactor,
                          heightFactor: widget.heightFactor,
                          child: ClipRect(
                            clipper: _ContentDialogCropClipper(
                              progress: t,
                              origin: _displayedOrigin,
                            ),
                            child: Opacity(
                              opacity: t,
                              child: Transform.scale(
                                alignment: _displayedOrigin,
                                scale: .96 + (.04 * t),
                                child: _displayedDialog!,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}



class CommonSideDockContentCropSwitcher extends StatelessWidget {
  const CommonSideDockContentCropSwitcher({
    super.key,
    required this.activeKey,
    required this.child,
    this.originAlignment = Alignment.centerLeft,
    this.duration = const Duration(milliseconds: 220),
    this.reverseDuration = const Duration(milliseconds: 180),
  });

  final String activeKey;
  final Widget child;
  final Alignment originAlignment;
  final Duration duration;
  final Duration reverseDuration;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSwitcher(
      duration: reduceMotion ? Duration.zero : duration,
      reverseDuration: reduceMotion ? Duration.zero : reverseDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (transitionChild, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return AnimatedBuilder(
          animation: curved,
          child: transitionChild,
          builder: (context, animatedChild) {
            final value = curved.value;
            return ClipRect(
              clipper: _ContentDialogCropClipper(
                progress: value,
                origin: originAlignment,
              ),
              child: Opacity(
                opacity: value,
                child: Transform.scale(
                  alignment: originAlignment,
                  scale: .96 + (.04 * value),
                  child: animatedChild,
                ),
              ),
            );
          },
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(activeKey),
        child: child,
      ),
    );
  }
}

class _ContentDialogCropClipper extends CustomClipper<Rect> {
  const _ContentDialogCropClipper({
    required this.progress,
    required this.origin,
  });

  final double progress;
  final Alignment origin;

  @override
  Rect getClip(Size size) {
    final t = progress.clamp(0.0, 1.0).toDouble();
    final width = size.width * (.12 + (.88 * t));
    final height = size.height * (.10 + (.90 * t));
    final xFactor = ((origin.x + 1) / 2).clamp(0.0, 1.0).toDouble();
    final yFactor = ((origin.y + 1) / 2).clamp(0.0, 1.0).toDouble();
    final left = (size.width - width) * xFactor;
    final top = (size.height - height) * yFactor;
    return Rect.fromLTWH(left, top, width, height);
  }

  @override
  bool shouldReclip(covariant _ContentDialogCropClipper oldClipper) {
    return oldClipper.progress != progress || oldClipper.origin != origin;
  }
}

class CommonSideDockContentDialog extends StatelessWidget {
  const CommonSideDockContentDialog({
    super.key,
    required this.title,
    required this.icon,
    required this.onClose,
    required this.child,
    this.footer,
  });

  final String title;
  final IconData icon;
  final VoidCallback onClose;
  final Widget child;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Material(
      color: tokens.transparent,
      child: AnimatedContainer(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: tokens.accentContainer,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      icon,
                      color: tokens.onAccentContainer,
                      size: 19,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                  ),
                  CommonIconButton(
                    icon: Icons.close_rounded,
                    tooltip: '닫기',
                    size: 36,
                    iconSize: 18,
                    haptic: CommonHaptic.selection,
                    onPressed: onClose,
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: tokens.borderSubtle),
            Expanded(child: child),
            if (footer != null) ...[
              Divider(height: 1, color: tokens.borderSubtle),
              Padding(
                padding: const EdgeInsets.all(10),
                child: footer!,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
