import 'package:flutter/material.dart';

class TabletPlateNumberDisplaySection extends StatelessWidget {
  final TextEditingController controller;
  final bool Function(String value) isValidPlate;

  const TabletPlateNumberDisplaySection({
    super.key,
    required this.controller,
    required this.isValidPlate,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortestSide >= 600;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight =
        (constraints.hasBoundedHeight && constraints.maxHeight.isFinite)
            ? constraints.maxHeight
            : (isTablet ? 120.0 : 84.0);

        final boxHeight = maxHeight.clamp(
          isTablet ? 72.0 : 60.0,
          isTablet ? 152.0 : 112.0,
        );

        final horizontalPadding = (boxHeight * 0.22).clamp(14.0, 24.0);
        final verticalPadding = (boxHeight * 0.16).clamp(8.0, 18.0);

        final emptyFontSize = (boxHeight * 0.32).clamp(18.0, 30.0);
        final valueFontSize = (boxHeight * 0.58).clamp(26.0, 58.0);

        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final input = value.text.trim();
            final valid = isValidPlate(input);
            final hasInput = input.isNotEmpty;

            final backgroundColor = hasInput
                ? Color.alphaBlend(
              (valid ? cs.primary : cs.error).withOpacity(.07),
              cs.surface,
            )
                : cs.surfaceContainerHigh;

            final borderColor = hasInput
                ? (valid
                ? cs.primary.withOpacity(.92)
                : cs.error.withOpacity(.88))
                : cs.outlineVariant.withOpacity(.85);

            final displayColor = hasInput
                ? (valid ? cs.onSurface : cs.error)
                : cs.onSurfaceVariant;

            return SizedBox(
              width: double.infinity,
              height: boxHeight,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                curve: Curves.easeOut,
                decoration: BoxDecoration(
                  color: backgroundColor,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: borderColor, width: 1.2),
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding,
                  vertical: verticalPadding,
                ),
                child: ClipRect(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        hasInput ? input : '번호 입력 대기 중',
                        maxLines: 1,
                        softWrap: false,
                        style: (text.titleLarge ?? const TextStyle()).copyWith(
                          fontSize: hasInput ? valueFontSize : emptyFontSize,
                          fontWeight:
                          hasInput ? FontWeight.w900 : FontWeight.w800,
                          letterSpacing: hasInput ? 1.0 : 0.1,
                          color: displayColor,
                          height: 1.0,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}