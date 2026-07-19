import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

class PromptInputSectionCard extends StatelessWidget {
  const PromptInputSectionCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return AnimatedContainer(
      duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
          ? Duration.zero
          : PromptUiMotion.selection,
      curve: PromptUiMotion.standard,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: tokens.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class PromptInputSectionTitle extends StatelessWidget {
  const PromptInputSectionTitle({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: tokens.accentContainer,
            borderRadius: BorderRadius.circular(PromptUiShapes.control),
            border: Border.all(
              color: tokens.accent.withOpacity(tokens.isDark ? 0.54 : 0.36),
            ),
          ),
          alignment: Alignment.center,
          child: Icon(icon, size: 20, color: tokens.onAccentContainer),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: textTheme.titleMedium?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  subtitle!,
                  style: textTheme.bodySmall?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailing != null) ...[
          const SizedBox(width: 8),
          trailing!,
        ],
      ],
    );
  }
}

class PromptInputDialogContent extends StatelessWidget {
  const PromptInputDialogContent({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
    this.tone = PromptInputTone.accent,
    this.maxWidth = 520,
  });

  final IconData icon;
  final String title;
  final Widget body;
  final List<Widget> actions;
  final PromptInputTone tone;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final colors = promptInputToneColors(tokens, tone);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: colors.container,
                  borderRadius: BorderRadius.circular(PromptUiShapes.control),
                  border: Border.all(color: colors.foreground.withOpacity(.34)),
                ),
                alignment: Alignment.center,
                child: Icon(icon, color: colors.foreground, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: textTheme.titleLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Flexible(child: body),
          const SizedBox(height: 18),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: actions,
          ),
        ],
      ),
    );
  }
}

enum PromptInputTone { accent, info, success, warning, danger }

class PromptInputToneColors {
  const PromptInputToneColors({
    required this.container,
    required this.foreground,
  });

  final Color container;
  final Color foreground;
}

PromptInputToneColors promptInputToneColors(
  PromptUiTokens tokens,
  PromptInputTone tone,
) {
  switch (tone) {
    case PromptInputTone.accent:
      return PromptInputToneColors(
        container: tokens.accentContainer,
        foreground: tokens.onAccentContainer,
      );
    case PromptInputTone.info:
      return PromptInputToneColors(
        container: tokens.infoContainer,
        foreground: tokens.onInfoContainer,
      );
    case PromptInputTone.success:
      return PromptInputToneColors(
        container: tokens.successContainer,
        foreground: tokens.onSuccessContainer,
      );
    case PromptInputTone.warning:
      return PromptInputToneColors(
        container: tokens.warningContainer,
        foreground: tokens.onWarningContainer,
      );
    case PromptInputTone.danger:
      return PromptInputToneColors(
        container: tokens.dangerContainer,
        foreground: tokens.onDangerContainer,
      );
  }
}
