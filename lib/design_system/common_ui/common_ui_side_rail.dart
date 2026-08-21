import 'package:flutter/material.dart';

import 'common_ui_theme.dart';

class CommonSideRailMetrics {
  const CommonSideRailMetrics({
    required this.variantName,
    required this.compact,
    required this.ultra,
    required this.railWidth,
    required this.railGap,
    required this.minimumButtonExtent,
    required this.headerHeight,
    required this.outerHorizontal,
    required this.outerVertical,
    required this.headerGap,
    required this.actionInsetHorizontal,
    required this.actionInsetVertical,
  });

  final String variantName;
  final bool compact;
  final bool ultra;
  final double railWidth;
  final double railGap;
  final double minimumButtonExtent;
  final double headerHeight;
  final double outerHorizontal;
  final double outerVertical;
  final double headerGap;
  final double actionInsetHorizontal;
  final double actionInsetVertical;

  factory CommonSideRailMetrics.resolve({
    required double dockHeight,
    required double textScale,
  }) {
    final ultra = dockHeight < 600 || textScale >= 1.30;
    final compact = !ultra && (dockHeight < 720 || textScale >= 1.15);
    return CommonSideRailMetrics(
      variantName: ultra
          ? 'ultra_compact'
          : compact
              ? 'compact'
              : 'normal',
      compact: compact || ultra,
      ultra: ultra,
      railWidth: ultra
          ? 48.0
          : compact
              ? 52.0
              : 56.0,
      railGap: ultra
          ? 6.0
          : compact
              ? 7.0
              : 8.0,
      minimumButtonExtent: ultra || compact ? 48.0 : 52.0,
      headerHeight: ultra
          ? 34.0
          : compact
              ? 36.0
              : 38.0,
      outerHorizontal: ultra ? 2.0 : 3.0,
      outerVertical: ultra ? 6.0 : 7.0,
      headerGap: 6.0,
      actionInsetHorizontal: ultra
          ? 2.0
          : compact
              ? 3.0
              : 4.0,
      actionInsetVertical: ultra ? 2.0 : 3.0,
    );
  }

  double effectiveRailWidth(double dockWidth) {
    return railWidth < dockWidth * .17
        ? railWidth
        : (dockWidth * .17).clamp(44.0, railWidth).toDouble();
  }

  double effectiveRailGap(double dockWidth) {
    return railGap < dockWidth * .025
        ? railGap
        : (dockWidth * .025).clamp(5.0, railGap).toDouble();
  }
}

class CommonSideRailButtonVisuals {
  const CommonSideRailButtonVisuals({
    required this.foreground,
    required this.textColor,
    required this.background,
    required this.pressedBackground,
    required this.border,
    required this.pressedBorder,
  });

  final Color foreground;
  final Color textColor;
  final Color background;
  final Color pressedBackground;
  final Color border;
  final Color pressedBorder;
}

class CommonSideRailSurface extends StatelessWidget {
  const CommonSideRailSurface({
    super.key,
    required this.title,
    required this.metrics,
    required this.child,
    this.semanticsLabel,
  });

  final String title;
  final String? semanticsLabel;
  final CommonSideRailMetrics metrics;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return Semantics(
      container: true,
      label: semanticsLabel ?? title,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: metrics.outerHorizontal,
          vertical: metrics.outerVertical,
        ),
        decoration: BoxDecoration(
          color: tokens.surface.withOpacity(.26),
          border: Border(right: BorderSide(color: tokens.borderSubtle)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: metrics.headerHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    width: metrics.ultra ? 18 : 22,
                    height: 3,
                    decoration: BoxDecoration(
                      color: tokens.iconSecondary,
                      borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: textTheme.labelSmall?.copyWith(
                      color: tokens.textSecondary,
                      fontWeight: FontWeight.w900,
                      height: 1.02,
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(height: metrics.headerGap),
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class CommonSideRailActionButton extends StatefulWidget {
  const CommonSideRailActionButton({
    super.key,
    required this.semanticLabel,
    required this.visualLabel,
    required this.selected,
    required this.enabled,
    required this.compact,
    required this.extent,
    required this.onTap,
    this.icon,
    this.iconChild,
    this.disabledReason = '',
    this.visuals,
    this.tooltip = '',
  }) : assert(icon != null || iconChild != null);

  final String semanticLabel;
  final String visualLabel;
  final IconData? icon;
  final Widget? iconChild;
  final bool selected;
  final bool enabled;
  final String disabledReason;
  final bool compact;
  final double extent;
  final VoidCallback onTap;
  final CommonSideRailButtonVisuals? visuals;
  final String tooltip;

  @override
  State<CommonSideRailActionButton> createState() =>
      _CommonSideRailActionButtonState();
}

class _CommonSideRailActionButtonState
    extends State<CommonSideRailActionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final enabled = widget.enabled;
    final defaultForeground = widget.selected && enabled
        ? tokens.accent
        : enabled
            ? tokens.iconPrimary
            : tokens.iconDisabled;
    final defaultTextColor = widget.selected && enabled
        ? tokens.accent
        : enabled
            ? tokens.textPrimary
            : tokens.textDisabled;
    final defaultBackground = widget.selected && enabled
        ? tokens.accentContainer.withOpacity(.62)
        : enabled
            ? tokens.surfaceRaised
            : tokens.surfaceDisabled;
    final defaultPressedBackground = widget.selected && enabled
        ? tokens.accentContainer.withOpacity(.86)
        : enabled
            ? tokens.accentContainer.withOpacity(.72)
            : tokens.surfaceDisabled;
    final defaultBorder = widget.selected && enabled
        ? tokens.accent.withOpacity(.38)
        : tokens.borderSubtle;
    final defaultPressedBorder = widget.selected && enabled
        ? tokens.accent.withOpacity(.58)
        : enabled
            ? tokens.accent.withOpacity(.42)
            : tokens.warning;
    final visuals = widget.visuals;
    final foreground = visuals?.foreground ?? defaultForeground;
    final textColor = visuals?.textColor ?? defaultTextColor;
    final background = _pressed
        ? visuals?.pressedBackground ?? defaultPressedBackground
        : visuals?.background ?? defaultBackground;
    final border = _pressed
        ? visuals?.pressedBorder ?? defaultPressedBorder
        : visuals?.border ?? defaultBorder;

    final icon = widget.iconChild ??
        Icon(
          widget.icon,
          size: widget.compact ? 19 : 20,
          color: foreground,
        );
    final core = AnimatedOpacity(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      opacity: enabled ? 1 : .56,
      child: AnimatedScale(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        curve: CommonUiMotion.standard,
        scale: _pressed ? (enabled ? .97 : .985) : 1,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: enabled ? widget.onTap : null,
            onHighlightChanged: (value) {
              if (!mounted) return;
              setState(() {
                _pressed = enabled && value;
              });
            },
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
              curve: CommonUiMotion.standard,
              width: double.infinity,
              height: widget.extent,
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: border),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: Tween<double>(begin: .84, end: 1).animate(
                            CurvedAnimation(
                              parent: animation,
                              curve: Curves.easeOutBack,
                            ),
                          ),
                          child: child,
                        ),
                      );
                    },
                    child: KeyedSubtree(
                      key: ValueKey<String>(
                        'icon:${widget.visualLabel}:${widget.selected}:${widget.enabled}:${widget.icon?.codePoint ?? widget.iconChild?.runtimeType ?? 'none'}',
                      ),
                      child: AnimatedScale(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        curve: Curves.easeOutCubic,
                        scale: _pressed && enabled ? 1.04 : 1,
                        child: icon,
                      ),
                    ),
                  ),
                  SizedBox(height: widget.compact ? 2 : 3),
                  AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      return FadeTransition(
                        opacity: animation,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, .12),
                            end: Offset.zero,
                          ).animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Text(
                      widget.visualLabel,
                      key: ValueKey<String>('label:${widget.visualLabel}'),
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                      textAlign: TextAlign.center,
                      style: textTheme.labelSmall?.copyWith(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ) ??
                          TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w800,
                            height: 1.05,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    return Semantics(
      container: true,
      button: true,
      selected: widget.selected,
      enabled: enabled,
      excludeSemantics: true,
      label: widget.semanticLabel,
      value: enabled || widget.disabledReason.isEmpty
          ? null
          : widget.disabledReason,
      child: widget.tooltip.isEmpty
          ? core
          : Tooltip(message: widget.tooltip, child: core),
    );
  }
}
