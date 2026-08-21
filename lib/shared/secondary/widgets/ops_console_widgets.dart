import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../design_system/common_ui/common_ui_components.dart';
import '../../../design_system/common_ui/common_ui_theme.dart';

class OpsConsolePresentationScope extends InheritedWidget {
  const OpsConsolePresentationScope({
    super.key,
    required this.embedded,
    required super.child,
  });

  final bool embedded;

  static bool isEmbedded(BuildContext context) {
    return context
            .dependOnInheritedWidgetOfExactType<OpsConsolePresentationScope>()
            ?.embedded ??
        false;
  }

  @override
  bool updateShouldNotify(OpsConsolePresentationScope oldWidget) {
    return embedded != oldWidget.embedded;
  }
}

class OpsMetric {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;

  const OpsMetric({
    required this.label,
    required this.value,
    required this.icon,
    this.color,
  });
}

class OpsConsoleScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? areaLabel;
  final List<OpsMetric> metrics;
  final Widget? commandBar;
  final Widget body;
  final Widget? trailing;
  final Widget? bottomBar;
  final bool loading;

  const OpsConsoleScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    required this.body,
    this.areaLabel,
    this.metrics = const <OpsMetric>[],
    this.commandBar,
    this.trailing,
    this.bottomBar,
    this.loading = false,
  });

  Widget _content(
    BuildContext context, {
    required bool embedded,
    required CommonUiTokens tokens,
    required bool reduceMotion,
  }) {
    final main = Column(
      children: [
        CommonAnimatedReveal(
          child: OpsConsoleHeader(
            title: title,
            subtitle: subtitle,
            icon: icon,
            areaLabel: areaLabel,
            metrics: metrics,
            trailing: trailing,
          ),
        ),
        if (commandBar != null)
          CommonAnimatedReveal(
            delay: const Duration(milliseconds: 45),
            offset: const Offset(0, .025),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                embedded ? 10 : 16,
                embedded ? 8 : 12,
                embedded ? 10 : 16,
                0,
              ),
              child: commandBar!,
            ),
          ),
        Expanded(
          child: Stack(
            children: [
              AnimatedSwitcher(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.component,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                child: KeyedSubtree(
                  key: ValueKey<bool>(loading),
                  child: body,
                ),
              ),
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: !loading,
                  child: AnimatedOpacity(
                    opacity: loading ? 1 : 0,
                    duration: reduceMotion
                        ? Duration.zero
                        : CommonUiMotion.selection,
                    child: ColoredBox(
                      color: tokens.scrim.withOpacity(.12),
                      child: Center(
                        child: Container(
                          width: embedded ? 44 : 50,
                          height: embedded ? 44 : 50,
                          decoration: BoxDecoration(
                            color: tokens.surfaceRaised,
                            borderRadius: BorderRadius.circular(
                              CommonUiShapes.control,
                            ),
                            border: Border.all(color: tokens.borderSubtle),
                            boxShadow: [
                              BoxShadow(
                                color: tokens.shadow,
                                blurRadius: 18,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: SizedBox(
                            width: embedded ? 21 : 24,
                            height: embedded ? 21 : 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.6,
                              color: tokens.accent,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        if (embedded && bottomBar != null) bottomBar!,
      ],
    );

    if (embedded) {
      return Material(
        color: tokens.canvas,
        child: main,
      );
    }

    return Scaffold(
      backgroundColor: tokens.canvas,
      body: SafeArea(
        bottom: false,
        child: main,
      ),
      bottomNavigationBar: bottomBar,
    );
  }

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          final reduceMotion =
              MediaQuery.maybeOf(context)?.disableAnimations ?? false;
          final embedded = OpsConsolePresentationScope.isEmbedded(context);
          return _content(
            context,
            embedded: embedded,
            tokens: tokens,
            reduceMotion: reduceMotion,
          );
        },
      ),
    );
  }
}

class OpsConsoleHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? areaLabel;
  final List<OpsMetric> metrics;
  final Widget? trailing;

  const OpsConsoleHeader({
    super.key,
    required this.title,
    this.subtitle,
    required this.icon,
    this.areaLabel,
    this.metrics = const <OpsMetric>[],
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final subtitleText = subtitle?.trim() ?? '';
    final embedded = OpsConsolePresentationScope.isEmbedded(context);
    final iconSize = embedded ? 36.0 : 44.0;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        embedded ? 10 : 16,
        embedded ? 9 : 14,
        embedded ? 10 : 16,
        embedded ? 10 : 16,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border(bottom: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: iconSize,
                height: iconSize,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                alignment: Alignment.center,
                child: Icon(
                  icon,
                  color: tokens.onAccentContainer,
                  size: embedded ? 19 : 23,
                ),
              ),
              SizedBox(width: embedded ? 8 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: (embedded
                              ? textTheme.titleSmall
                              : textTheme.titleLarge)
                          ?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitleText.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitleText,
                        maxLines: embedded ? 1 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w500,
                          height: 1.25,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (!embedded &&
                  areaLabel != null &&
                  areaLabel!.trim().isNotEmpty) ...[
                const SizedBox(width: 10),
                OpsHeaderPill(text: areaLabel!),
              ],
              if (trailing != null) ...[
                SizedBox(width: embedded ? 4 : 8),
                trailing!,
              ],
            ],
          ),
          if (metrics.isNotEmpty) ...[
            SizedBox(height: embedded ? 8 : 14),
            SizedBox(
              height: embedded ? 68 : 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: metrics.length,
                separatorBuilder: (_, __) => SizedBox(width: embedded ? 6 : 8),
                itemBuilder: (context, index) => CommonAnimatedReveal(
                  delay: Duration(milliseconds: index * 35),
                  offset: const Offset(.025, 0),
                  child: OpsMetricCard(metric: metrics[index]),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class OpsHeaderPill extends StatelessWidget {
  final String text;

  const OpsHeaderPill({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w600,
            ),
      ),
    );
  }
}

class OpsMetricCard extends StatelessWidget {
  final OpsMetric metric;

  const OpsMetricCard({super.key, required this.metric});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final color = metric.color ?? tokens.accent;
    final embedded = OpsConsolePresentationScope.isEmbedded(context);
    return Container(
      width: embedded ? 100 : 118,
      padding: EdgeInsets.fromLTRB(
        embedded ? 9 : 12,
        embedded ? 8 : 10,
        embedded ? 9 : 12,
        embedded ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(metric.icon, size: 16, color: color),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const Spacer(),
          Text(
            metric.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class OpsCommandPanel extends StatelessWidget {
  final List<Widget> children;

  const OpsCommandPanel({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class OpsSearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;

  const OpsSearchField({super.key, required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: tokens.textPrimary,
            fontWeight: FontWeight.w500,
          ),
      decoration: opsInputDecoration(
        context,
        label: hint,
        prefixIcon: const Icon(Icons.search_rounded),
      ),
    );
  }
}

class OpsFilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final IconData? icon;

  const OpsFilterChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final foreground = selected ? tokens.onAccentContainer : tokens.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        decoration: BoxDecoration(
          color: selected ? tokens.accentContainer : tokens.surfaceOverlay,
          borderRadius: BorderRadius.circular(CommonUiShapes.pill),
          border: Border.all(
            color: selected ? tokens.accent : tokens.borderSubtle,
          ),
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(CommonUiShapes.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(CommonUiShapes.pill),
            onTap: onSelected,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 15, color: foreground),
                    const SizedBox(width: 5),
                  ],
                  Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: foreground,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OpsPanel extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final Color? accentColor;

  const OpsPanel({
    super.key,
    required this.child,
    this.margin = const EdgeInsets.only(bottom: 10),
    this.padding = const EdgeInsets.all(14),
    this.selected = false,
    this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final accent = accentColor ?? tokens.accent;
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.standard,
      margin: margin,
      decoration: BoxDecoration(
        color: selected ? tokens.surfaceSelected : tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(CommonUiShapes.card),
        border: Border.all(
          color: selected ? accent : tokens.borderSubtle,
          width: selected ? 1.4 : 1,
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class OpsSectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget? trailing;

  const OpsSectionTitle({
    super.key,
    required this.title,
    required this.icon,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tokens.accentContainer,
            borderRadius: BorderRadius.circular(CommonUiShapes.control),
            border: Border.all(color: tokens.borderSubtle),
          ),
          alignment: Alignment.center,
          child: Icon(icon, color: tokens.onAccentContainer, size: 19),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w400,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ],
    );
  }
}

class OpsStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const OpsStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(.12),
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: color.withOpacity(.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class OpsInfoPill extends StatelessWidget {
  final String text;
  final IconData? icon;

  const OpsInfoPill({super.key, required this.text, this.icon});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tokens.iconSecondary),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class OpsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const OpsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: CommonAnimatedReveal(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(CommonUiShapes.card),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: tokens.onAccentContainer, size: 28),
              ),
              const SizedBox(height: 13),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                message,
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w400,
                  height: 1.4,
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: 14),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class OpsBottomActionBar extends StatelessWidget {
  final List<Widget> children;

  const OpsBottomActionBar({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final embedded = OpsConsolePresentationScope.isEmbedded(context);
    final bottomInset = embedded ? 0.0 : MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(
        embedded ? 10 : 16,
        embedded ? 8 : 10,
        embedded ? 10 : 16,
        (embedded ? 9 : 12) + bottomInset,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
      ),
      child: Row(children: children),
    );
  }
}

class OpsActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool danger;
  final bool tonal;

  const OpsActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.danger = false,
    this.tonal = false,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return CommonButton(
          label: label,
          icon: icon,
          onPressed: onPressed,
          expand: constraints.hasBoundedWidth,
          haptic: danger ? CommonHaptic.medium : CommonHaptic.selection,
          variant: danger
              ? CommonButtonVariant.destructive
              : tonal
                  ? CommonButtonVariant.secondary
                  : CommonButtonVariant.primary,
        );
      },
    );
  }
}

class OpsDivider extends StatelessWidget {
  const OpsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: CommonUiTheme.of(context).borderSubtle);
  }
}

class OpsWorkSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final String? areaLabel;
  final List<OpsMetric> metrics;
  final Widget body;
  final Widget? bottomBar;
  final Widget? trailing;
  final EdgeInsetsGeometry bodyPadding;
  final ScrollPhysics? bodyScrollPhysics;
  final ScrollController? bodyScrollController;

  const OpsWorkSheet({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.body,
    this.areaLabel,
    this.metrics = const <OpsMetric>[],
    this.bottomBar,
    this.trailing,
    this.bodyPadding = const EdgeInsets.fromLTRB(16, 14, 16, 24),
    this.bodyScrollPhysics,
    this.bodyScrollController,
  });

  @override
  Widget build(BuildContext context) {
    return CommonUiScope(
      child: Builder(
        builder: (context) {
          final tokens = CommonUiTheme.of(context);
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          return Material(
            color: tokens.transparent,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.canvas,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(CommonUiShapes.sheet),
                  ),
                  border: Border(
                    top: BorderSide(color: tokens.borderSubtle),
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 42,
                        height: 4,
                        decoration: BoxDecoration(
                          color: tokens.handle,
                          borderRadius: BorderRadius.circular(
                            CommonUiShapes.pill,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OpsConsoleHeader(
                        title: title,
                        subtitle: subtitle,
                        icon: icon,
                        areaLabel: areaLabel,
                        metrics: metrics,
                        trailing: trailing ??
                            CommonIconButton(
                              icon: Icons.close_rounded,
                              tooltip: '닫기',
                              onPressed: () => Navigator.pop(context),
                              haptic: CommonHaptic.selection,
                            ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: bodyScrollController,
                          physics: bodyScrollPhysics,
                          padding: bodyPadding,
                          child: CommonAnimatedReveal(child: body),
                        ),
                      ),
                      if (bottomBar != null) bottomBar!,
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class OpsWorkSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const OpsWorkSection({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.subtitle,
    this.trailing,
    this.padding = const EdgeInsets.all(14),
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  Widget build(BuildContext context) {
    return OpsPanel(
      margin: margin,
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OpsSectionTitle(
            title: title,
            subtitle: subtitle,
            icon: icon,
            trailing: trailing,
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class OpsInlineMessage extends StatelessWidget {
  final String? message;
  final bool danger;
  final IconData icon;

  const OpsInlineMessage({
    super.key,
    required this.message,
    this.danger = true,
    this.icon = Icons.error_outline_rounded,
  });

  @override
  Widget build(BuildContext context) {
    if (message == null || message!.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final tokens = CommonUiTheme.of(context);
    final background = danger ? tokens.dangerContainer : tokens.infoContainer;
    final foreground =
        danger ? tokens.onDangerContainer : tokens.onInfoContainer;
    return AnimatedContainer(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : CommonUiMotion.selection,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(
          color: danger ? tokens.danger : tokens.info,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: foreground, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration opsInputDecoration(
  BuildContext context, {
  required String label,
  String? errorText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? suffixText,
  bool locked = false,
}) {
  final tokens = CommonUiTheme.of(context);
  return InputDecoration(
    labelText: label,
    errorText: errorText,
    prefixIcon: prefixIcon,
    suffixIcon: locked
        ? Icon(Icons.lock_rounded, color: tokens.iconSecondary)
        : suffixIcon,
    suffixText: suffixText,
    isDense: true,
    filled: true,
    fillColor: locked ? tokens.surfaceDisabled : tokens.surfaceOverlay,
    contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
    labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w500,
        ),
    suffixStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: tokens.textSecondary,
          fontWeight: FontWeight.w500,
        ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
      borderSide: BorderSide(color: tokens.borderSubtle),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
      borderSide: BorderSide(color: tokens.focusRing, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
      borderSide: BorderSide(color: tokens.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
      borderSide: BorderSide(color: tokens.danger, width: 1.5),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
    ),
  );
}

class OpsFormChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  const OpsFormChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final foreground = selected ? tokens.onAccentContainer : tokens.textSecondary;
    return AnimatedContainer(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : CommonUiMotion.selection,
      decoration: BoxDecoration(
        color: selected ? tokens.accentContainer : tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(
          color: selected ? tokens.accent : tokens.borderSubtle,
        ),
      ),
      child: Material(
        color: tokens.transparent,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(CommonUiShapes.control),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 17, color: foreground),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: foreground,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OpsDockStatusSegmentItem<T> {
  const OpsDockStatusSegmentItem({
    required this.value,
    required this.label,
    required this.count,
    required this.color,
  });

  final T value;
  final String label;
  final int count;
  final Color color;
}

class OpsDockStatusSegments<T> extends StatelessWidget {
  const OpsDockStatusSegments({
    super.key,
    required this.selected,
    required this.items,
    required this.onSelected,
  });

  final T selected;
  final List<OpsDockStatusSegmentItem<T>> items;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      height: 38,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(CommonUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: _OpsDockStatusSegment<T>(
                item: item,
                selected: selected == item.value,
                onTap: () => onSelected(item.value),
              ),
            ),
        ],
      ),
    );
  }
}

class _OpsDockStatusSegment<T> extends StatelessWidget {
  const _OpsDockStatusSegment({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final OpsDockStatusSegmentItem<T> item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(9),
        child: AnimatedContainer(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          curve: CommonUiMotion.standard,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? item.color.withOpacity(.13) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? item.color.withOpacity(.34)
                  : Colors.transparent,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.label,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected ? item.color : tokens.textSecondary,
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(width: 4),
                AnimatedDefaultTextStyle(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: selected ? item.color : tokens.textPrimary,
                            fontWeight: FontWeight.w900,
                          ) ??
                      TextStyle(
                        color: selected ? item.color : tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                      ),
                  child: Text('${item.count}'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class OpsDockSearchField extends StatelessWidget {
  const OpsDockSearchField({
    super.key,
    required this.controller,
    required this.query,
    required this.semanticLabel,
    required this.onChanged,
    required this.onClear,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String query;
  final String semanticLabel;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Semantics(
      textField: true,
      label: semanticLabel,
      child: SizedBox(
        height: 40,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          onSubmitted: onSubmitted,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          maxLength: maxLength,
          textInputAction: TextInputAction.search,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
          decoration: InputDecoration(
            counterText: '',
            isDense: true,
            filled: true,
            fillColor: tokens.surfaceRaised,
            prefixIcon: Icon(
              Icons.search_rounded,
              size: 18,
              color: tokens.iconSecondary,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 36,
              minHeight: 36,
            ),
            suffixIcon: query.trim().isEmpty
                ? null
                : IconButton(
                    onPressed: onClear,
                    icon: Icon(
                      Icons.close_rounded,
                      size: 17,
                      color: tokens.iconSecondary,
                    ),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 34,
                      minHeight: 34,
                    ),
                    tooltip: '검색 초기화',
                  ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 10,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              borderSide: BorderSide(color: tokens.borderSubtle),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(CommonUiShapes.control),
              borderSide: BorderSide(color: tokens.accent, width: 1.4),
            ),
          ),
        ),
      ),
    );
  }
}

class OpsDockListSurface extends StatelessWidget {
  const OpsDockListSurface({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: child,
      ),
    );
  }
}

class OpsDockSelectableRowSurface extends StatefulWidget {
  const OpsDockSelectableRowSurface({
    super.key,
    required this.selected,
    required this.selectionColor,
    required this.selectedContainer,
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(11, 10, 13, 10),
  });

  final bool selected;
  final Color selectionColor;
  final Color selectedContainer;
  final VoidCallback onTap;
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  State<OpsDockSelectableRowSurface> createState() =>
      _OpsDockSelectableRowSurfaceState();
}

class _OpsDockSelectableRowSurfaceState
    extends State<OpsDockSelectableRowSurface> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return AnimatedScale(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.press,
      curve: CommonUiMotion.enter,
      scale: _pressed ? .985 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          onHighlightChanged: (value) {
            if (!mounted) return;
            setState(() => _pressed = value);
          },
          child: Stack(
            children: [
              AnimatedContainer(
                duration:
                    reduceMotion ? Duration.zero : CommonUiMotion.selection,
                curve: CommonUiMotion.standard,
                color: widget.selected
                    ? widget.selectedContainer.withOpacity(.55)
                    : _pressed
                        ? tokens.surfaceSelected.withOpacity(.55)
                        : Colors.transparent,
                padding: widget.padding,
                child: AnimatedSize(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: widget.child,
                ),
              ),
              Positioned(
                top: 8,
                bottom: 8,
                right: 0,
                child: AnimatedContainer(
                  duration:
                      reduceMotion ? Duration.zero : CommonUiMotion.selection,
                  curve: CommonUiMotion.standard,
                  width: widget.selected ? 3 : 0,
                  decoration: BoxDecoration(
                    color: widget.selectionColor,
                    borderRadius: BorderRadius.circular(CommonUiShapes.pill),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OpsDockContextFooter extends StatelessWidget {
  const OpsDockContextFooter({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
      decoration: BoxDecoration(
        color: tokens.surface.withOpacity(.94),
        border: Border(
          top: BorderSide(color: tokens.borderSubtle),
        ),
      ),
      child: Row(children: children),
    );
  }
}

class OpsDockContextFooterTransition extends StatelessWidget {
  const OpsDockContextFooterTransition({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSize(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
      curve: CommonUiMotion.enter,
      alignment: Alignment.bottomCenter,
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .06),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        ),
        child: child,
      ),
    );
  }
}

class OpsDockResultSwitcher extends StatelessWidget {
  const OpsDockResultSwitcher({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 160),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: child,
    );
  }
}

class OpsDockLoadingOverlay extends StatelessWidget {
  const OpsDockLoadingOverlay({
    super.key,
    required this.loading,
  });

  final bool loading;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !loading,
        child: AnimatedOpacity(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          opacity: loading ? 1 : 0,
          child: ColoredBox(
            color: tokens.canvas.withOpacity(.82),
            child: Center(
              child: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.surfaceRaised,
                  borderRadius: BorderRadius.circular(CommonUiShapes.control),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                alignment: Alignment.center,
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: tokens.accent,
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
