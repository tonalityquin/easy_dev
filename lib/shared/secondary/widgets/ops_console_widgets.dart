import 'package:flutter/material.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

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

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(
        builder: (context) {
          final tokens = PromptUiTheme.of(context);
          final reduceMotion =
              MediaQuery.maybeOf(context)?.disableAnimations ?? false;
          return Scaffold(
            backgroundColor: tokens.canvas,
            body: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  PromptAnimatedReveal(
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
                    PromptAnimatedReveal(
                      delay: const Duration(milliseconds: 45),
                      offset: const Offset(0, .025),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        child: commandBar!,
                      ),
                    ),
                  Expanded(
                    child: Stack(
                      children: [
                        AnimatedSwitcher(
                          duration: reduceMotion
                              ? Duration.zero
                              : PromptUiMotion.component,
                          switchInCurve: PromptUiMotion.enter,
                          switchOutCurve: PromptUiMotion.exit,
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
                                  : PromptUiMotion.selection,
                              child: ColoredBox(
                                color: tokens.scrim.withOpacity(.12),
                                child: Center(
                                  child: Container(
                                    width: 50,
                                    height: 50,
                                    decoration: BoxDecoration(
                                      color: tokens.surfaceRaised,
                                      borderRadius: BorderRadius.circular(
                                        PromptUiShapes.control,
                                      ),
                                      border: Border.all(
                                        color: tokens.borderSubtle,
                                      ),
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
                                      width: 24,
                                      height: 24,
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
                ],
              ),
            ),
            bottomNavigationBar: bottomBar,
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
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final subtitleText = subtitle?.trim() ?? '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
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
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: tokens.onAccentContainer, size: 23),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleLarge?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (subtitleText.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitleText,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          fontWeight: FontWeight.w500,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (areaLabel != null && areaLabel!.trim().isNotEmpty) ...[
                const SizedBox(width: 10),
                OpsHeaderPill(text: areaLabel!),
              ],
              if (trailing != null) ...[
                const SizedBox(width: 8),
                trailing!,
              ],
            ],
          ),
          if (metrics.isNotEmpty) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 78,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: metrics.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) => PromptAnimatedReveal(
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
    final tokens = PromptUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
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
    final tokens = PromptUiTheme.of(context);
    final color = metric.color ?? tokens.accent;
    return Container(
      width: 118,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
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
    final tokens = PromptUiTheme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
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
    final tokens = PromptUiTheme.of(context);
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
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final foreground = selected ? tokens.onAccentContainer : tokens.textSecondary;
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
        decoration: BoxDecoration(
          color: selected ? tokens.accentContainer : tokens.surfaceOverlay,
          borderRadius: BorderRadius.circular(PromptUiShapes.pill),
          border: Border.all(
            color: selected ? tokens.accent : tokens.borderSubtle,
          ),
        ),
        child: Material(
          color: tokens.transparent,
          borderRadius: BorderRadius.circular(PromptUiShapes.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(PromptUiShapes.pill),
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
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final accent = accentColor ?? tokens.accent;
    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
      curve: PromptUiMotion.standard,
      margin: margin,
      decoration: BoxDecoration(
        color: selected ? tokens.surfaceSelected : tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
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
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: tokens.accentContainer,
            borderRadius: BorderRadius.circular(PromptUiShapes.control),
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
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(color: color.withOpacity(.32)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
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
    final tokens = PromptUiTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: tokens.iconSecondary),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
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
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: PromptAnimatedReveal(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: tokens.accentContainer,
                  borderRadius: BorderRadius.circular(PromptUiShapes.card),
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
    final tokens = PromptUiTheme.of(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomInset),
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
    return PromptButton(
      label: label,
      icon: icon,
      onPressed: onPressed,
      expand: true,
      haptic: danger ? PromptHaptic.medium : PromptHaptic.selection,
      variant: danger
          ? PromptButtonVariant.destructive
          : tonal
              ? PromptButtonVariant.secondary
              : PromptButtonVariant.primary,
    );
  }
}

class OpsDivider extends StatelessWidget {
  const OpsDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1, color: PromptUiTheme.of(context).borderSubtle);
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
  });

  @override
  Widget build(BuildContext context) {
    return PromptUiScope(
      child: Builder(
        builder: (context) {
          final tokens = PromptUiTheme.of(context);
          final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
          return Material(
            color: tokens.transparent,
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Container(
                decoration: BoxDecoration(
                  color: tokens.canvas,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(PromptUiShapes.sheet),
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
                            PromptUiShapes.pill,
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
                            PromptIconButton(
                              icon: Icons.close_rounded,
                              tooltip: '닫기',
                              onPressed: () => Navigator.pop(context),
                              haptic: PromptHaptic.selection,
                            ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: bodyPadding,
                          child: PromptAnimatedReveal(child: body),
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
    final tokens = PromptUiTheme.of(context);
    final background = danger ? tokens.dangerContainer : tokens.infoContainer;
    final foreground =
        danger ? tokens.onDangerContainer : tokens.onInfoContainer;
    return AnimatedContainer(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : PromptUiMotion.selection,
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
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
  final tokens = PromptUiTheme.of(context);
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
      borderRadius: BorderRadius.circular(PromptUiShapes.control),
      borderSide: BorderSide(color: tokens.borderSubtle),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(PromptUiShapes.control),
      borderSide: BorderSide(color: tokens.focusRing, width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(PromptUiShapes.control),
      borderSide: BorderSide(color: tokens.danger),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(PromptUiShapes.control),
      borderSide: BorderSide(color: tokens.danger, width: 1.5),
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(PromptUiShapes.control),
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
    final tokens = PromptUiTheme.of(context);
    final foreground = selected ? tokens.onAccentContainer : tokens.textSecondary;
    return AnimatedContainer(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : PromptUiMotion.selection,
      decoration: BoxDecoration(
        color: selected ? tokens.accentContainer : tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        border: Border.all(
          color: selected ? tokens.accent : tokens.borderSubtle,
        ),
      ),
      child: Material(
        color: tokens.transparent,
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(PromptUiShapes.control),
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
