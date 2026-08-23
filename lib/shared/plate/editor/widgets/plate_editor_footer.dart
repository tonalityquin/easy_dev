import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../design_system/common_ui/common_ui_side_dock_frame.dart';
import '../../../../design_system/common_ui/common_ui_theme.dart';

class PlateEditorFooter extends StatelessWidget {
  const PlateEditorFooter({
    super.key,
    this.message,
    required this.actionLabel,
    required this.actionIcon,
    required this.onPressed,
    this.loading = false,
    this.warning = false,
    this.emphasized = false,
    this.actionVariant = CommonButtonVariant.primary,
    this.preserveActionVariantWhenDisabled = false,
  });

  final String? message;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback? onPressed;
  final bool loading;
  final bool warning;
  final bool emphasized;
  final CommonButtonVariant actionVariant;
  final bool preserveActionVariantWhenDisabled;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final resolvedMessage = message?.trim() ?? '';
    final button = CommonButton(
      label: actionLabel,
      icon: actionIcon,
      variant: actionVariant,
      loading: loading,
      expand: resolvedMessage.isEmpty,
      preserveVariantWhenDisabled: preserveActionVariantWhenDisabled,
      haptic: CommonHaptic.medium,
      minHeight: 46,
      onPressed: onPressed,
    );

    return CommonSideDockPrimaryFooter(
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: child,
        ),
        child: resolvedMessage.isEmpty
            ? SizedBox(
                key: ValueKey<String>('action-only-$actionLabel'),
                width: double.infinity,
                child: button,
              )
            : Row(
                key: ValueKey<String>('message-$resolvedMessage-$actionLabel'),
                children: [
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: reduceMotion
                          ? Duration.zero
                          : const Duration(milliseconds: 160),
                      child: Text(
                        resolvedMessage,
                        key: ValueKey<String>(resolvedMessage),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: warning
                                  ? tokens.warning
                                  : emphasized
                                      ? tokens.accent
                                      : tokens.textSecondary,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  button,
                ],
              ),
      ),
    );
  }
}
