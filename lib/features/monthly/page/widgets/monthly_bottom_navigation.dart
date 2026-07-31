import 'package:flutter/material.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';

class MonthlyBottomNavigation extends StatelessWidget {
  const MonthlyBottomNavigation({
    super.key,
    required this.showKeypad,
    required this.keypad,
    required this.actionButton,
    this.backgroundColor,
  });

  final bool showKeypad;
  final Widget keypad;
  final Widget actionButton;
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return AnimatedContainer(
      duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
      curve: CommonUiMotion.standard,
      padding: EdgeInsets.fromLTRB(12, 10, 12, bottomInset > 0 ? 8 : 12),
      decoration: BoxDecoration(
        color: backgroundColor ?? tokens.surfaceRaised,
        border: Border(top: BorderSide(color: tokens.borderSubtle)),
        boxShadow: [
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 14,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: AnimatedSwitcher(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.layout,
        reverseDuration: reduceMotion ? Duration.zero : CommonUiMotion.component,
        switchInCurve: CommonUiMotion.enter,
        switchOutCurve: CommonUiMotion.exit,
        transitionBuilder: (child, animation) {
          final offset = Tween<Offset>(
            begin: const Offset(0, 0.04),
            end: Offset.zero,
          ).animate(animation);
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(position: offset, child: child),
          );
        },
        child: KeyedSubtree(
          key: ValueKey<bool>(showKeypad),
          child: showKeypad ? keypad : actionButton,
        ),
      ),
    );
  }
}
