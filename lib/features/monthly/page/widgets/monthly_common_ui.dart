import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_overlays.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';

enum MonthlyCommonMessageTone { info, success, warning, danger }

void showMonthlyCommonMessage(
  BuildContext context,
  String message, {
  MonthlyCommonMessageTone tone = MonthlyCommonMessageTone.info,
}) {
  if (!context.mounted) return;
  final tokens = CommonUiTheme.of(context);
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  final background = switch (tone) {
    MonthlyCommonMessageTone.info => tokens.infoContainer,
    MonthlyCommonMessageTone.success => tokens.successContainer,
    MonthlyCommonMessageTone.warning => tokens.warningContainer,
    MonthlyCommonMessageTone.danger => tokens.dangerContainer,
  };
  final foreground = switch (tone) {
    MonthlyCommonMessageTone.info => tokens.onInfoContainer,
    MonthlyCommonMessageTone.success => tokens.onSuccessContainer,
    MonthlyCommonMessageTone.warning => tokens.onWarningContainer,
    MonthlyCommonMessageTone.danger => tokens.onDangerContainer,
  };
  final icon = switch (tone) {
    MonthlyCommonMessageTone.info => Icons.info_outline_rounded,
    MonthlyCommonMessageTone.success => Icons.check_circle_outline_rounded,
    MonthlyCommonMessageTone.warning => Icons.warning_amber_rounded,
    MonthlyCommonMessageTone.danger => Icons.error_outline_rounded,
  };

  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: background,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 18),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
          side: BorderSide(color: foreground.withOpacity(0.24)),
        ),
        content: Row(
          children: [
            Icon(icon, color: foreground, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
}

Future<bool> showMonthlyCommonConfirmation({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '취소',
  bool destructive = false,
  IconData icon = Icons.help_outline_rounded,
}) async {
  final result = await showCommonOverlayDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final tokens = CommonUiTheme.of(dialogContext);
      final textTheme = Theme.of(dialogContext).textTheme;
      final tone = destructive ? tokens.danger : tokens.accent;
      final containerTone = destructive
          ? tokens.dangerContainer
          : tokens.accentContainer;
      final onContainerTone = destructive
          ? tokens.onDangerContainer
          : tokens.onAccentContainer;

      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Material(
          color: tokens.surfaceRaised,
          surfaceTintColor: tokens.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
            side: BorderSide(color: tokens.borderSubtle),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: containerTone,
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                    border: Border.all(color: tone.withOpacity(0.34)),
                  ),
                  child: Icon(icon, color: onContainerTone, size: 26),
                ),
                const SizedBox(height: 16),
                Text(
                  title,
                  style: textTheme.titleLarge?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  message,
                  style: textTheme.bodyMedium?.copyWith(
                    color: tokens.textSecondary,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: CommonButton(
                        label: cancelLabel,
                        variant: CommonButtonVariant.tertiary,
                        haptic: CommonHaptic.selection,
                        onPressed: () => Navigator.of(dialogContext).pop(false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: CommonButton(
                        label: confirmLabel,
                        variant: destructive
                            ? CommonButtonVariant.destructive
                            : CommonButtonVariant.primary,
                        haptic: destructive
                            ? CommonHaptic.heavy
                            : CommonHaptic.medium,
                        onPressed: () => Navigator.of(dialogContext).pop(true),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  return result ?? false;
}

Future<void> showMonthlyCommonProgress({
  required BuildContext context,
  required String title,
  required String message,
}) {
  return showCommonOverlayDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final tokens = CommonUiTheme.of(dialogContext);
      final textTheme = Theme.of(dialogContext).textTheme;
      return ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Material(
          color: tokens.surfaceRaised,
          surfaceTintColor: tokens.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(CommonUiShapes.dialog),
            side: BorderSide(color: tokens.borderSubtle),
          ),
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Row(
              children: [
                SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.6,
                    color: tokens.accent,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        message,
                        style: textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

InputDecoration monthlyCommonInputDecoration(
  BuildContext context, {
  required String label,
  Widget? prefixIcon,
  Widget? suffixIcon,
  String? suffixText,
  bool enabled = true,
  String? errorText,
}) {
  final tokens = CommonUiTheme.of(context);
  return InputDecoration(
    labelText: label,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    suffixText: suffixText,
    errorText: errorText,
    labelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: enabled ? tokens.textSecondary : tokens.textDisabled,
          fontWeight: FontWeight.w600,
        ),
    floatingLabelStyle: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: tokens.accent,
          fontWeight: FontWeight.w700,
        ),
    filled: true,
    fillColor: enabled ? tokens.surfaceOverlay : tokens.surfaceDisabled,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(CommonUiShapes.control),
      borderSide: BorderSide(color: tokens.borderSubtle),
    ),
    disabledBorder: OutlineInputBorder(
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

class MonthlyCommonSection extends StatelessWidget {
  const MonthlyCommonSection({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.child,
    this.trailing,
    this.delay = Duration.zero,
    this.padding = const EdgeInsets.all(16),
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget child;
  final Widget? trailing;
  final Duration delay;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return CommonAnimatedReveal(
      delay: reduceMotion ? Duration.zero : delay,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
        curve: CommonUiMotion.standard,
        padding: padding,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(CommonUiShapes.card),
          border: Border.all(color: tokens.borderSubtle),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tokens.accentContainer,
                    borderRadius: BorderRadius.circular(CommonUiShapes.control),
                    border: Border.all(
                      color: tokens.accent.withOpacity(tokens.isDark ? 0.56 : 0.34),
                    ),
                  ),
                  child: Icon(icon, size: 21, color: tokens.onAccentContainer),
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
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: textTheme.bodySmall?.copyWith(
                          color: tokens.textSecondary,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 10),
                  trailing!,
                ],
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class MonthlyCommonBadge extends StatelessWidget {
  const MonthlyCommonBadge({
    super.key,
    required this.label,
    this.icon,
    this.tone = MonthlyCommonMessageTone.info,
  });

  final String label;
  final IconData? icon;
  final MonthlyCommonMessageTone tone;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final background = switch (tone) {
      MonthlyCommonMessageTone.info => tokens.infoContainer,
      MonthlyCommonMessageTone.success => tokens.successContainer,
      MonthlyCommonMessageTone.warning => tokens.warningContainer,
      MonthlyCommonMessageTone.danger => tokens.dangerContainer,
    };
    final foreground = switch (tone) {
      MonthlyCommonMessageTone.info => tokens.onInfoContainer,
      MonthlyCommonMessageTone.success => tokens.onSuccessContainer,
      MonthlyCommonMessageTone.warning => tokens.onWarningContainer,
      MonthlyCommonMessageTone.danger => tokens.onDangerContainer,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(CommonUiShapes.pill),
        border: Border.all(color: foreground.withOpacity(0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: foreground, size: 15),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: foreground,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
