import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../features/voice/application/voice_appbar_ui_state.dart';
import '../../application/common/type_view_mode_state.dart';

class TypePageBottomBars extends StatelessWidget {
  const TypePageBottomBars({
    super.key,
    required this.tableTop,
    required this.tableMiddle,
    required this.modeSwitch,
    this.duration = PromptUiMotion.component,
  });

  final Widget tableTop;
  final Widget tableMiddle;
  final Widget modeSwitch;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final mode = context.watch<TypeViewModeState>().mode;
    var talkUiEnabled = false;

    try {
      talkUiEnabled = context.watch<VoiceAppbarUiState>().enabled;
    } catch (_) {
      talkUiEnabled = false;
    }

    final showTableBars = mode == TypeViewMode.table || talkUiEnabled;
    final child = showTableBars
        ? Column(
            key: const ValueKey<String>('bars:table'),
            mainAxisSize: MainAxisSize.min,
            children: [
              tableTop,
              tableMiddle,
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
        duration: reduceMotion ? Duration.zero : PromptUiMotion.layout,
        curve: PromptUiMotion.standard,
        alignment: Alignment.bottomCenter,
        child: AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : duration,
          switchInCurve: PromptUiMotion.enter,
          switchOutCurve: PromptUiMotion.exit,
          transitionBuilder: (current, animation) {
            final curved = CurvedAnimation(
              parent: animation,
              curve: PromptUiMotion.enter,
              reverseCurve: PromptUiMotion.exit,
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
