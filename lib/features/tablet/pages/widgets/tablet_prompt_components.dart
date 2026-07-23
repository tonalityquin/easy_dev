import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

Duration tabletPromptDuration(
  BuildContext context,
  Duration duration,
) {
  return MediaQuery.maybeOf(context)?.disableAnimations ?? false
      ? Duration.zero
      : duration;
}

class TabletPromptPanel extends StatelessWidget {
  const TabletPromptPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = PromptUiShapes.card,
    this.selected = false,
    this.clipBehavior = Clip.none,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final bool selected;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return AnimatedContainer(
      duration: tabletPromptDuration(context, PromptUiMotion.component),
      curve: PromptUiMotion.standard,
      decoration: BoxDecoration(
        color: selected ? tokens.surfaceSelected : tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: selected ? tokens.accent : tokens.borderSubtle,
          width: selected ? 1.5 : 1,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.shadow,
            blurRadius: selected ? 18 : 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      clipBehavior: clipBehavior,
      padding: padding,
      child: child,
    );
  }
}

class TabletPromptStatusPill extends StatelessWidget {
  const TabletPromptStatusPill({
    super.key,
    required this.label,
    required this.icon,
    this.tone,
    this.selected = false,
  });

  final String label;
  final IconData icon;
  final Color? tone;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final resolvedTone = tone ?? tokens.accent;
    final foreground = selected ? tokens.onAccentContainer : tokens.textSecondary;
    final background = selected ? tokens.accentContainer : tokens.surfaceOverlay;
    return AnimatedContainer(
      duration: tabletPromptDuration(context, PromptUiMotion.selection),
      curve: PromptUiMotion.standard,
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(
          color: selected ? resolvedTone : tokens.borderSubtle,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 15, color: selected ? resolvedTone : tokens.iconSecondary),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class TabletPromptLoadingState extends StatefulWidget {
  const TabletPromptLoadingState({
    super.key,
    this.label = '불러오는 중',
  });

  final String label;

  @override
  State<TabletPromptLoadingState> createState() =>
      _TabletPromptLoadingStateState();
}

class _TabletPromptLoadingStateState extends State<TabletPromptLoadingState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
  }

  void _syncMotion() {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0;
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncMotion();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return _TabletPromptStateViewport(
      child: Semantics(
        label: widget.label,
        value: '처리 중',
        liveRegion: true,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (reduceMotion)
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: tokens.statusSynchronizedContainer,
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
                  border: Border.all(color: tokens.statusSynchronized),
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.hourglass_top_rounded,
                  size: 22,
                  color: tokens.statusSynchronized,
                ),
              )
            else
              SizedBox(
                width: 46,
                height: 46,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final value = _controller.value;
                        return Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius:
                                BorderRadius.circular(PromptUiShapes.control),
                            gradient: LinearGradient(
                              begin: Alignment(-1 + value * 2, 0),
                              end: Alignment(value * 2, 0),
                              colors: <Color>[
                                tokens.shimmerBase,
                                tokens.shimmerHighlight,
                                tokens.shimmerBase,
                              ],
                            ),
                            border: Border.all(color: tokens.borderSubtle),
                          ),
                        );
                      },
                    ),
                    SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: tokens.statusSynchronized,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              widget.label,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

class TabletPromptEmptyState extends StatelessWidget {
  const TabletPromptEmptyState({
    super.key,
    required this.title,
    required this.icon,
    this.message,
  });

  final String title;
  final IconData icon;
  final String? message;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final resolvedMessage = message?.trim();
    return _TabletPromptStateViewport(
      child: Semantics(
        label: title,
        value: resolvedMessage?.isNotEmpty ?? false ? resolvedMessage : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: tokens.surfaceOverlay,
                borderRadius: BorderRadius.circular(PromptUiShapes.card),
                border: Border.all(color: tokens.borderSubtle),
              ),
              child: Icon(icon, color: tokens.iconSecondary, size: 26),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
            ),
            if (resolvedMessage?.isNotEmpty ?? false) ...<Widget>[
              const SizedBox(height: 6),
              Text(
                resolvedMessage!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: tokens.textSecondary,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TabletPromptStateViewport extends StatelessWidget {
  const _TabletPromptStateViewport({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final boundedHeight = constraints.hasBoundedHeight;
        final boundedWidth = constraints.hasBoundedWidth;
        final verticalPadding = !boundedHeight
            ? 20.0
            : constraints.maxHeight >= 120
                ? 20.0
                : constraints.maxHeight >= 64
                    ? 8.0
                    : 0.0;
        final horizontalPadding = !boundedWidth
            ? 20.0
            : constraints.maxWidth >= 160
                ? 20.0
                : constraints.maxWidth >= 80
                    ? 8.0
                    : 0.0;
        final availableHeight = boundedHeight &&
                constraints.maxHeight > verticalPadding * 2
            ? constraints.maxHeight - verticalPadding * 2
            : 0.0;
        final availableWidth = boundedWidth &&
                constraints.maxWidth > horizontalPadding * 2
            ? constraints.maxWidth - horizontalPadding * 2
            : 0.0;

        return ClipRect(
          child: SingleChildScrollView(
            primary: false,
            physics: const ClampingScrollPhysics(),
            padding: EdgeInsets.symmetric(
              horizontal: horizontalPadding,
              vertical: verticalPadding,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minWidth: availableWidth,
                minHeight: availableHeight,
              ),
              child: Center(child: child),
            ),
          ),
        );
      },
    );
  }
}

class TabletPromptAnimatedSwap extends StatelessWidget {
  const TabletPromptAnimatedSwap({
    super.key,
    required this.child,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final duration = tabletPromptDuration(context, PromptUiMotion.component);
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: duration,
      switchInCurve: PromptUiMotion.enter,
      switchOutCurve: PromptUiMotion.exit,
      layoutBuilder: (Widget? currentChild, List<Widget> previousChildren) {
        return Stack(
          alignment: alignment,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (Widget child, Animation<double> animation) {
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.025),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: slide, child: child),
        );
      },
      child: child,
    );
  }
}
