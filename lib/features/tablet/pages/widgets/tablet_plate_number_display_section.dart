import 'package:flutter/material.dart';

import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import 'tablet_prompt_components.dart';

class TabletPlateNumberDisplaySection extends StatelessWidget {
  const TabletPlateNumberDisplaySection({
    super.key,
    required this.controller,
    required this.isValidPlate,
  });

  final TextEditingController controller;
  final bool Function(String value) isValidPlate;

  static const int _maxDigits = 4;

  double _digitBoxSize({
    required bool isTablet,
    required BoxConstraints constraints,
  }) {
    final preferred = isTablet ? 64.0 : 52.0;
    final minSize = isTablet ? 48.0 : 42.0;
    final maxSize = isTablet ? 68.0 : 58.0;
    if (!constraints.hasBoundedHeight || !constraints.maxHeight.isFinite) {
      return preferred;
    }
    return (constraints.maxHeight * 0.48).clamp(minSize, maxSize).toDouble();
  }

  double _availableWidth({
    required bool isTablet,
    required BoxConstraints constraints,
  }) {
    if (constraints.hasBoundedWidth && constraints.maxWidth.isFinite) {
      return constraints.maxWidth;
    }
    return isTablet ? 360 : 280;
  }

  @override
  Widget build(BuildContext context) {
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final isTablet = shortestSide >= 600;
    final duration = tabletPromptDuration(context, PromptUiMotion.selection);
    return LayoutBuilder(
      builder: (context, constraints) {
        final digitBoxSize = _digitBoxSize(
          isTablet: isTablet,
          constraints: constraints,
        );
        final availableWidth = _availableWidth(
          isTablet: isTablet,
          constraints: constraints,
        );
        final spacing = isTablet ? 10.0 : 8.0;
        final emptyWidth = availableWidth
            .clamp(isTablet ? 210.0 : 180.0, isTablet ? 320.0 : 260.0)
            .toDouble();
        final emptyHeight = (digitBoxSize * 0.84)
            .clamp(isTablet ? 48.0 : 42.0, isTablet ? 60.0 : 54.0)
            .toDouble();
        return ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (context, value, _) {
            final input = value.text.trim();
            final valid = input.isNotEmpty && isValidPlate(input);
            final hasInput = input.isNotEmpty;
            return Align(
              alignment: Alignment.topLeft,
              child: AnimatedSwitcher(
                duration: duration,
                reverseDuration: duration,
                switchInCurve: PromptUiMotion.enter,
                switchOutCurve: PromptUiMotion.exit,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: Tween<double>(begin: 0.97, end: 1).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: hasInput
                    ? _DigitWrapDisplay(
                        key: ValueKey<String>('digits-$input-$valid'),
                        input: input,
                        maxDigits: _maxDigits,
                        boxSize: digitBoxSize,
                        spacing: spacing,
                        valid: valid,
                      )
                    : _EmptyPlateNumberDisplay(
                        key: const ValueKey<String>('empty'),
                        width: emptyWidth,
                        height: emptyHeight,
                      ),
              ),
            );
          },
        );
      },
    );
  }
}

class _DigitWrapDisplay extends StatelessWidget {
  const _DigitWrapDisplay({
    super.key,
    required this.input,
    required this.maxDigits,
    required this.boxSize,
    required this.spacing,
    required this.valid,
  });

  final String input;
  final int maxDigits;
  final double boxSize;
  final double spacing;
  final bool valid;

  @override
  Widget build(BuildContext context) {
    final chars = input.length > maxDigits
        ? input.substring(0, maxDigits).split('')
        : input.split('');
    return Wrap(
      alignment: WrapAlignment.start,
      runAlignment: WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.start,
      spacing: spacing,
      runSpacing: spacing,
      children: <Widget>[
        for (var index = 0; index < chars.length; index++)
          PromptAnimatedReveal(
            key: ValueKey<String>('digit-$index-${chars[index]}'),
            delay: Duration(milliseconds: index * 24),
            duration: PromptUiMotion.selection,
            offset: const Offset(0, 0.08),
            child: _DigitTile(
              digit: chars[index],
              boxSize: boxSize,
              valid: valid,
            ),
          ),
      ],
    );
  }
}

class _DigitTile extends StatelessWidget {
  const _DigitTile({
    required this.digit,
    required this.boxSize,
    required this.valid,
  });

  final String digit;
  final double boxSize;
  final bool valid;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final tone = valid ? tokens.accent : tokens.danger;
    final background = valid ? tokens.accentContainer : tokens.dangerContainer;
    final foreground = valid ? tokens.onAccentContainer : tokens.onDangerContainer;
    final fontSize = (boxSize * 0.54).clamp(24.0, 40.0).toDouble();
    return AnimatedContainer(
      duration: tabletPromptDuration(context, PromptUiMotion.selection),
      curve: PromptUiMotion.standard,
      width: boxSize,
      height: boxSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: tone, width: 1.25),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: tokens.shadow,
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Text(
        digit,
        maxLines: 1,
        softWrap: false,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              height: 1,
              color: foreground,
              fontFeatures: const <FontFeature>[
                FontFeature.tabularFigures(),
              ],
            ),
      ),
    );
  }
}

class _EmptyPlateNumberDisplay extends StatelessWidget {
  const _EmptyPlateNumberDisplay({
    super.key,
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return AnimatedContainer(
      duration: tabletPromptDuration(context, PromptUiMotion.selection),
      curve: PromptUiMotion.standard,
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: tokens.surfaceOverlay,
        borderRadius: BorderRadius.circular(PromptUiShapes.card),
        border: Border.all(color: tokens.borderSubtle, width: 1.2),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.dialpad_rounded, color: tokens.iconSecondary, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '번호 입력 대기 중',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: tokens.textSecondary,
                    fontWeight: FontWeight.w600,
                    height: 1,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
