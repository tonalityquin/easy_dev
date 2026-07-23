import 'package:flutter/material.dart';

import '../../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../widgets/tablet_prompt_components.dart';
import 'tablet_num_keypad_for_tablet_plate_search.dart';

class TabletAnimatedKeypad extends StatelessWidget {
  const TabletAnimatedKeypad({
    super.key,
    required this.slideAnimation,
    required this.fadeAnimation,
    required this.controller,
    required this.onComplete,
    required this.onReset,
    this.maxLength = 4,
    this.enableDigitModeSwitch = false,
    this.fullHeight = false,
  });

  final Animation<Offset> slideAnimation;
  final Animation<double> fadeAnimation;
  final TextEditingController controller;
  final VoidCallback onComplete;
  final VoidCallback onReset;
  final int maxLength;
  final bool enableDigitModeSwitch;
  final bool fullHeight;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final keypad = AnimatedContainer(
      duration: tabletPromptDuration(context, PromptUiMotion.component),
      curve: PromptUiMotion.standard,
      constraints: fullHeight
          ? const BoxConstraints()
          : BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.45,
            ),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(PromptUiShapes.card),
        ),
        border: Border(
          top: BorderSide(color: tokens.borderSubtle),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: 8),
        child: TabletNumKeypadForTabletPlateSearch(
          controller: controller,
          maxLength: maxLength,
          enableDigitModeSwitch: enableDigitModeSwitch,
          onComplete: onComplete,
          onReset: onReset,
        ),
      ),
    );

    return FadeTransition(
      opacity: fadeAnimation,
      child: SlideTransition(
        position: slideAnimation,
        child: fullHeight ? SizedBox.expand(child: keypad) : keypad,
      ),
    );
  }
}
