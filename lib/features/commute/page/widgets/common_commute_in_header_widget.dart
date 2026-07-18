import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../utils/common_brand_tinted_logo.dart';

class CommonCommuteInHeaderWidget extends StatelessWidget {
  const CommonCommuteInHeaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return LayoutBuilder(
      builder: (context, constraints) {
        final logoSize = constraints.maxWidth >= 560 ? 204.0 : 178.0;
        return PromptAnimatedReveal(
          delay: const Duration(milliseconds: 30),
          duration: PromptUiMotion.layout,
          offset: const Offset(0, 0.025),
          child: Semantics(
            image: true,
            label: 'Parkin Workin',
            child: AnimatedContainer(
              duration: reduceMotion ? Duration.zero : PromptUiMotion.layout,
              curve: PromptUiMotion.standard,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
              decoration: BoxDecoration(
                color: tokens.surfaceRaised,
                borderRadius: BorderRadius.circular(PromptUiShapes.card),
                border: Border.all(color: tokens.borderSubtle),
                boxShadow: [
                  BoxShadow(
                    color: tokens.shadow,
                    blurRadius: tokens.isDark ? 18 : 14,
                    offset: const Offset(0, 7),
                  ),
                ],
              ),
              child: ExcludeSemantics(
                child: SizedBox(
                  width: logoSize,
                  height: logoSize,
                  child: Center(
                    child: CommonBrandTintedLogo(
                      assetPath: 'assets/images/ParkinWorkin_logo.png',
                      height: logoSize,
                      preferredColor: tokens.accent,
                      fallbackColor: tokens.textPrimary,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
