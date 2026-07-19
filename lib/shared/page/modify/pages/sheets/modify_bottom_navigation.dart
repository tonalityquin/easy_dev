import 'package:flutter/material.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';

class ModifyBottomNavigation extends StatelessWidget {
  const ModifyBottomNavigation({
    super.key,
    this.showKeypad,
    this.keypad,
    required this.actionButton,
    this.onTap,
    this.backgroundColor,
  });

  final bool? showKeypad;
  final Widget? keypad;
  final Widget actionButton;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final showKeyboardContent = showKeypad == true && keypad != null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : PromptUiMotion.layout,
        curve: PromptUiMotion.standard,
        decoration: BoxDecoration(
          color: backgroundColor ?? tokens.surfaceRaised,
          border: Border(top: BorderSide(color: tokens.borderSubtle)),
          boxShadow: [
            BoxShadow(
              color: tokens.shadow,
              blurRadius: 16,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : PromptUiMotion.component,
          switchInCurve: PromptUiMotion.enter,
          switchOutCurve: PromptUiMotion.exit,
          transitionBuilder: (child, animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, .035),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey(showKeyboardContent),
            child: showKeyboardContent ? keypad! : actionButton,
          ),
        ),
      ),
    );
  }
}
