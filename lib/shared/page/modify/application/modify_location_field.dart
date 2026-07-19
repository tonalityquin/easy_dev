import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';

class ModifyLocationField extends StatelessWidget {
  const ModifyLocationField({
    super.key,
    required this.controller,
    this.widthFactor = .7,
  });

  final TextEditingController controller;
  final double widthFactor;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final textTheme = Theme.of(context).textTheme;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;

    return SizedBox(
      width: screenWidth * widthFactor,
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, child) {
          final text = value.text.trim();
          final isEmpty = text.isEmpty;
          return AnimatedContainer(
            duration: reduceMotion ? Duration.zero : PromptUiMotion.selection,
            curve: PromptUiMotion.standard,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: isEmpty ? tokens.surfaceOverlay : tokens.surfaceSelected,
              borderRadius: BorderRadius.circular(PromptUiShapes.control),
              border: Border.all(
                color: isEmpty ? tokens.borderSubtle : tokens.accent,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.location_on_rounded,
                  size: 20,
                  color: isEmpty ? tokens.iconSecondary : tokens.accent,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: AnimatedSwitcher(
                    duration: reduceMotion
                        ? Duration.zero
                        : PromptUiMotion.selection,
                    switchInCurve: PromptUiMotion.enter,
                    switchOutCurve: PromptUiMotion.exit,
                    child: Text(
                      isEmpty ? '선택되지 않음' : text,
                      key: ValueKey(text),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: textTheme.bodyLarge?.copyWith(
                        color: isEmpty
                            ? tokens.textSecondary
                            : tokens.textPrimary,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  isEmpty
                      ? Icons.add_circle_outline_rounded
                      : Icons.check_circle_rounded,
                  size: 20,
                  color: isEmpty ? tokens.iconSecondary : tokens.success,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
