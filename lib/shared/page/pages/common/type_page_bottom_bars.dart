import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../features/voice/application/voice_appbar_ui_state.dart';
import '../../application/common/type_view_mode_state.dart';

class TypePageBottomBars extends StatelessWidget {
  final Widget tableTop;
  final Widget tableMiddle;
  final Widget modeSwitch;
  final Duration duration;

  const TypePageBottomBars({
    super.key,
    required this.tableTop,
    required this.tableMiddle,
    required this.modeSwitch,
    this.duration = const Duration(milliseconds: 220),
  });

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<TypeViewModeState>().mode;
    bool talkUiEnabled = false;

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
            children: [
              modeSwitch,
            ],
          );

    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (c, a) {
        final curved = CurvedAnimation(
          parent: a,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        final offset = Tween<Offset>(
          begin: const Offset(0, 0.04),
          end: Offset.zero,
        ).animate(curved);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(position: offset, child: c),
        );
      },
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.bottomCenter,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      child: child,
    );
  }
}
