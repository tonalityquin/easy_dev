import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/common_ui/common_ui_theme.dart';
import '../../application/common/type_view_mode_state.dart';

class TypePageBottomBars extends StatelessWidget {
  const TypePageBottomBars({
    super.key,
    required this.tableActions,
    required this.modeSwitch,
    this.duration = CommonUiMotion.component,
  });

  final Widget tableActions;
  final Widget modeSwitch;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final tokens = CommonUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final mode = context.watch<TypeViewModeState>().mode;
    final showTableActions = mode == TypeViewMode.table;
    final child = showTableActions
        ? Column(
            key: const ValueKey<String>('bars:table'),
            mainAxisSize: MainAxisSize.min,
            children: [
              tableActions,
              modeSwitch,
            ],
          )
        : Column(
            key: const ValueKey<String>('bars:status'),
            mainAxisSize: MainAxisSize.min,
            children: [modeSwitch],
          );

    return Material(
      color: tokens.surface,
      surfaceTintColor: tokens.transparent,
      elevation: 0,
      child: AnimatedSize(
        duration: reduceMotion ? Duration.zero : CommonUiMotion.layout,
        curve: CommonUiMotion.standard,
        alignment: Alignment.bottomCenter,
        child: AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : duration,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          transitionBuilder: (current, animation) {
            if (reduceMotion) return current;
            final curved = CurvedAnimation(
              parent: animation,
              curve: CommonUiMotion.enter,
              reverseCurve: CommonUiMotion.exit,
            );
            final offset = Tween<Offset>(
              begin: const Offset(0, 0.045),
              end: Offset.zero,
            ).animate(curved);
            return FadeTransition(
              opacity: curved,
              child: SlideTransition(position: offset, child: current),
            );
          },
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              alignment: Alignment.bottomCenter,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          child: child,
        ),
      ),
    );
  }
}
