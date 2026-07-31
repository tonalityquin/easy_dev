import 'package:flutter/material.dart';

import '../../../../../design_system/common_ui/common_ui_theme.dart';

class InputBottomNavigation extends StatelessWidget {
  final bool showKeypad;
  final Widget keypad;
  final Widget actionButton;
  final VoidCallback? onTap;
  final Color? backgroundColor;

  const InputBottomNavigation({
    super.key,
    required this.showKeypad,
    required this.keypad,
    required this.actionButton,
    this.onTap,
    this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.layout,
        curve: CommonUiMotion.standard,
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
          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
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
            key: ValueKey(showKeypad),
            child: showKeypad ? keypad : actionButton,
          ),
        ),
      ),
    );
  }
}
