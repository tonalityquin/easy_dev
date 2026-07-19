import 'package:flutter/material.dart';

import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_overlays.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';

Future<bool> showOpsConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String cancelLabel = '취소',
  IconData icon = Icons.help_outline_rounded,
  bool destructive = false,
  bool barrierDismissible = true,
}) async {
  final result = await showPromptOverlayDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (dialogContext) {
      final tokens = PromptUiTheme.of(dialogContext);
      final toneBackground =
          destructive ? tokens.dangerContainer : tokens.accentContainer;
      final toneForeground =
          destructive ? tokens.onDangerContainer : tokens.onAccentContainer;
      return PromptDialogFrame(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: toneBackground,
                        borderRadius: BorderRadius.circular(
                          PromptUiShapes.control,
                        ),
                        border: Border.all(color: tokens.borderSubtle),
                      ),
                      alignment: Alignment.center,
                      child: Icon(icon, color: toneForeground, size: 23),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: Theme.of(dialogContext)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  color: tokens.textPrimary,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          const SizedBox(height: 7),
                          Text(
                            message,
                            style: Theme.of(dialogContext)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: tokens.textSecondary,
                                  height: 1.45,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: PromptButton(
                        label: cancelLabel,
                        onPressed: () => Navigator.pop(dialogContext, false),
                        variant: PromptButtonVariant.tertiary,
                        haptic: PromptHaptic.selection,
                        expand: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: PromptButton(
                        label: confirmLabel,
                        onPressed: () => Navigator.pop(dialogContext, true),
                        variant: destructive
                            ? PromptButtonVariant.destructive
                            : PromptButtonVariant.primary,
                        haptic: destructive
                            ? PromptHaptic.medium
                            : PromptHaptic.selection,
                        expand: true,
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

class OpsDialogShell extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;
  final Widget? actions;
  final bool danger;

  const OpsDialogShell({
    super.key,
    required this.title,
    required this.icon,
    required this.child,
    this.actions,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final background = danger ? tokens.dangerContainer : tokens.accentContainer;
    final foreground =
        danger ? tokens.onDangerContainer : tokens.onAccentContainer;
    return PromptDialogFrame(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.all(18),
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
                      color: background,
                      borderRadius: BorderRadius.circular(PromptUiShapes.control),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: foreground, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              child,
              if (actions != null) ...[
                const SizedBox(height: 18),
                actions!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
