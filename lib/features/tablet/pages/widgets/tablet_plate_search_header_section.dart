import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

class TabletPlateSearchHeaderSection extends StatelessWidget {
  const TabletPlateSearchHeaderSection({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return Row(
      children: <Widget>[
        AnimatedContainer(
          duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
              ? Duration.zero
              : PromptUiMotion.selection,
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: tokens.accentContainer,
            borderRadius: BorderRadius.circular(PromptUiShapes.control),
            border: Border.all(
              color: tokens.accent.withOpacity(tokens.isDark ? 0.56 : 0.38),
            ),
          ),
          child: Icon(
            Icons.directions_car_rounded,
            color: tokens.onAccentContainer,
            size: 20,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '번호판 검색',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tokens.textPrimary,
                ),
          ),
        ),
      ],
    );
  }
}
