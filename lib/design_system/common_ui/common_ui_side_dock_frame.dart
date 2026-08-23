import 'package:flutter/material.dart';

import 'common_ui_components.dart';
import 'common_ui_side_rail.dart';
import 'common_ui_theme.dart';

class CommonSideDockFrame extends StatelessWidget {
  const CommonSideDockFrame({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    required this.onClose,
    this.closeEnabled = true,
    this.onLongPress,
    this.onHeaderTap,
    this.headerAction,
    this.leadingRail,
    this.collapseLeadingRail = false,
    this.footer,
    this.sectionGap,
    this.footerHeight,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final VoidCallback onClose;
  final bool closeEnabled;
  final VoidCallback? onLongPress;
  final VoidCallback? onHeaderTap;
  final Widget? headerAction;
  final Widget? leadingRail;
  final bool collapseLeadingRail;
  final Widget? footer;
  final double? sectionGap;
  final double? footerHeight;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.maybeOf(context);
    final textScale = media?.textScaler.scale(1.0) ?? 1.0;
    final reduceMotion = media?.disableAnimations ?? false;

    return PopScope(
      canPop: closeEnabled,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final dockHeight = constraints.maxHeight.isFinite
              ? constraints.maxHeight
              : media?.size.height ?? 720.0;
          final dockWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : media?.size.width ?? 360.0;
          final railMetrics = CommonSideRailMetrics.resolve(
            dockHeight: dockHeight,
            textScale: textScale,
          );
          final effectiveRailWidth = railMetrics.effectiveRailWidth(dockWidth);
          final effectiveRailGap = railMetrics.effectiveRailGap(dockWidth);
          final effectiveSectionGap = sectionGap ??
              (railMetrics.ultra
                  ? 6.0
                  : railMetrics.compact
                      ? 8.0
                      : 10.0);

          final mainColumn = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: child),
              if (footer != null) ...[
                SizedBox(height: effectiveSectionGap),
                if (footerHeight != null)
                  AnimatedContainer(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    height: footerHeight,
                    child: footer!,
                  )
                else
                  AnimatedSize(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.bottomCenter,
                    child: footer!,
                  ),
              ],
            ],
          );

          final body = leadingRail == null
              ? mainColumn
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AnimatedContainer(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: collapseLeadingRail ? 0 : effectiveRailWidth,
                      child: ClipRect(
                        child: IgnorePointer(
                          ignoring: collapseLeadingRail,
                          child: AnimatedOpacity(
                            duration: reduceMotion
                                ? Duration.zero
                                : const Duration(milliseconds: 130),
                            curve: Curves.easeOutCubic,
                            opacity: collapseLeadingRail ? 0 : 1,
                            child: leadingRail!,
                          ),
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 180),
                      curve: Curves.easeOutCubic,
                      width: collapseLeadingRail ? 0 : effectiveRailGap,
                    ),
                    Expanded(child: mainColumn),
                  ],
                );

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CommonSideDockHeader(
                title: title,
                subtitle: subtitle,
                icon: icon,
                metrics: railMetrics,
                closeEnabled: closeEnabled,
                onClose: onClose,
                onLongPress: onLongPress,
                onTap: onHeaderTap,
                headerAction: headerAction,
              ),
              SizedBox(height: effectiveSectionGap),
              Expanded(child: body),
            ],
          );
        },
      ),
    );
  }
}

class CommonSideDockHeader extends StatelessWidget {
  const CommonSideDockHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.metrics,
    required this.closeEnabled,
    required this.onClose,
    this.onLongPress,
    this.onTap,
    this.headerAction,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final CommonSideRailMetrics metrics;
  final bool closeEnabled;
  final VoidCallback onClose;
  final VoidCallback? onLongPress;
  final VoidCallback? onTap;
  final Widget? headerAction;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final compact = metrics.compact;
    final ultra = metrics.ultra;
    final horizontalPadding = ultra
        ? 10.0
        : compact
            ? 11.0
            : 12.0;
    final verticalPadding = ultra
        ? 8.0
        : compact
            ? 10.0
            : 12.0;
    final identityIconSize = ultra
        ? 36.0
        : compact
            ? 39.0
            : 42.0;
    final identityGlyphSize = ultra
        ? 19.0
        : compact
            ? 20.0
            : 22.0;
    final identityGap = ultra
        ? 9.0
        : compact
            ? 10.0
            : 12.0;
    final subtitleGap = ultra
        ? 2.0
        : compact
            ? 3.0
            : 4.0;
    final subtitleMaxLines = compact ? 1 : 2;

    return CommonSideDockReveal(
      order: 0,
      offsetY: 6,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: AnimatedContainer(
          duration:
              reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          padding: EdgeInsets.symmetric(
            horizontal: horizontalPadding,
            vertical: verticalPadding,
          ),
          decoration: BoxDecoration(
            color: tokens.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                width: identityIconSize,
                height: identityIconSize,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: tokens.shadow,
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 180),
                  switchInCurve: Curves.easeOutBack,
                  switchOutCurve: Curves.easeInCubic,
                  child: Icon(
                    icon,
                    key: ValueKey<int>(icon.codePoint),
                    color: tokens.onAccentContainer,
                    size: identityGlyphSize,
                  ),
                ),
              ),
              SizedBox(width: identityGap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 190),
                      switchInCurve: Curves.easeOutCubic,
                      switchOutCurve: Curves.easeInCubic,
                      transitionBuilder: (child, animation) {
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween<Offset>(
                              begin: const Offset(0, .08),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        );
                      },
                      child: Text(
                        title,
                        key: ValueKey<String>(title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w900,
                          letterSpacing: .1,
                        ),
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      SizedBox(height: subtitleGap),
                      AnimatedSwitcher(
                        duration: reduceMotion
                            ? Duration.zero
                            : const Duration(milliseconds: 190),
                        switchInCurve: Curves.easeOutCubic,
                        switchOutCurve: Curves.easeInCubic,
                        child: Text(
                          subtitle.trim(),
                          key: ValueKey<String>(subtitle.trim()),
                          maxLines: subtitleMaxLines,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.bodySmall?.copyWith(
                            color: tokens.textSecondary,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (headerAction != null) ...[
                const SizedBox(width: 6),
                headerAction!,
              ],
              const SizedBox(width: 8),
              CommonIconButton(
                icon: Icons.close_rounded,
                tooltip: '닫기',
                onPressed: closeEnabled ? onClose : null,
                haptic: CommonHaptic.selection,
                size: 42,
                iconSize: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class CommonSideDockReveal extends StatelessWidget {
  const CommonSideDockReveal({
    super.key,
    required this.order,
    required this.child,
    this.offsetY = 9,
  });

  final int order;
  final Widget child;
  final double offsetY;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) return child;

    final delayMs = order.clamp(0, 10).toInt() * 22;
    const motionMs = 190;
    final totalMs = delayMs + motionMs;
    final start = delayMs / totalMs;

    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: Duration(milliseconds: totalMs),
      curve: Curves.linear,
      child: child,
      builder: (context, value, animatedChild) {
        final normalized = value <= start
            ? 0.0
            : ((value - start) / (1 - start)).clamp(0.0, 1.0).toDouble();
        final motion = Curves.easeOutCubic.transform(normalized);
        return Opacity(
          opacity: motion,
          child: Transform.translate(
            offset: Offset(0, offsetY * (1 - motion)),
            child: animatedChild,
          ),
        );
      },
    );
  }
}

class CommonSideDockSection extends StatelessWidget {
  const CommonSideDockSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle = '',
    this.accentColor,
    this.order = 2,
  });

  final String title;
  final String subtitle;
  final Widget child;
  final Color? accentColor;
  final int order;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;

    return CommonSideDockReveal(
      order: order,
      offsetY: 6,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 3,
                height: 18,
                margin: const EdgeInsets.only(top: 1),
                decoration: BoxDecoration(
                  color: accentColor ?? tokens.accent,
                  borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: textTheme.titleSmall?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if (subtitle.trim().isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle.trim(),
                        style: textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          height: 1.2,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 10),
            child: child,
          ),
        ],
      ),
    );
  }
}

class CommonSideDockPrimaryFooter extends StatelessWidget {
  const CommonSideDockPrimaryFooter({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return CommonSideDockReveal(
      order: 4,
      offsetY: 6,
      child: AnimatedContainer(
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 190),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: tokens.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
