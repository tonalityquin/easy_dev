import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

Duration personalPromptDuration(
  BuildContext context, [
  Duration duration = PromptUiMotion.component,
]) {
  return MediaQuery.maybeOf(context)?.disableAnimations ?? false
      ? Duration.zero
      : duration;
}

class PersonalPromptPanel extends StatelessWidget {
  const PersonalPromptPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin,
    this.selected = false,
    this.accented = false,
    this.borderRadius = PromptUiShapes.card,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final bool selected;
  final bool accented;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final duration = personalPromptDuration(context);
    return AnimatedContainer(
      duration: duration,
      curve: PromptUiMotion.standard,
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: selected
            ? tokens.surfaceSelected
            : accented
                ? tokens.accentContainer
                : tokens.surfaceRaised,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: selected || accented ? tokens.accent : tokens.borderSubtle,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class PersonalPromptStatusPill extends StatelessWidget {
  const PersonalPromptStatusPill({
    super.key,
    required this.label,
    required this.foreground,
    required this.background,
    this.icon,
  });

  final String label;
  final Color foreground;
  final Color background;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AnimatedContainer(
      duration: personalPromptDuration(context, PromptUiMotion.selection),
      curve: PromptUiMotion.standard,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PromptUiShapes.pill),
        border: Border.all(color: foreground.withOpacity(.26)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 15, color: foreground),
            const SizedBox(width: 5),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PersonalPromptAnimatedSwap extends StatelessWidget {
  const PersonalPromptAnimatedSwap({
    super.key,
    required this.child,
    required this.stateKey,
    this.alignment = Alignment.center,
  });

  final Widget child;
  final Object stateKey;
  final AlignmentGeometry alignment;

  @override
  Widget build(BuildContext context) {
    final duration = personalPromptDuration(context);
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: duration,
      switchInCurve: PromptUiMotion.enter,
      switchOutCurve: PromptUiMotion.exit,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: alignment,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: PromptUiMotion.enter,
          reverseCurve: PromptUiMotion.exit,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, .025),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<Object>(stateKey),
        child: child,
      ),
    );
  }
}

class PersonalPromptLoadingState extends StatelessWidget {
  const PersonalPromptLoadingState({
    super.key,
    required this.label,
    this.compact = false,
  });

  final String label;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return PersonalPromptPanel(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 14 : 20,
        vertical: compact ? 14 : 22,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: compact ? 22 : 26,
            height: compact ? 22 : 26,
            child: reduceMotion
                ? Icon(
                    Icons.hourglass_top_rounded,
                    size: compact ? 20 : 24,
                    color: tokens.statusSettlementPending,
                  )
                : CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: tokens.statusSynchronized,
                  ),
          ),
          const SizedBox(width: 12),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class PersonalPromptEmptyState extends StatelessWidget {
  const PersonalPromptEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    return PersonalPromptPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: tokens.surfaceOverlay,
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Icon(icon, color: tokens.iconSecondary, size: 24),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: textTheme.titleSmall?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (message != null && message!.trim().isNotEmpty) ...<Widget>[
            const SizedBox(height: 6),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: textTheme.bodySmall?.copyWith(
                color: tokens.textSecondary,
                height: 1.45,
              ),
            ),
          ],
          if (actionLabel != null && onAction != null) ...<Widget>[
            const SizedBox(height: 14),
            PromptButton(
              label: actionLabel!,
              onPressed: onAction,
              variant: PromptButtonVariant.secondary,
              haptic: PromptHaptic.selection,
            ),
          ],
        ],
      ),
    );
  }
}
