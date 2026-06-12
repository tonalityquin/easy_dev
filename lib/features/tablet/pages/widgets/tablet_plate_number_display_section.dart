import 'package:flutter/material.dart';

class TabletPlateNumberDisplaySection extends StatelessWidget {
  final TextEditingController controller;
  final bool Function(String value) isValidPlate;

  const TabletPlateNumberDisplaySection({
    super.key,
    required this.controller,
    required this.isValidPlate,
  });

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
    return isTablet ? 360.0 : 280.0;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final shortestSide = MediaQuery.of(context).size.shortestSide;
    final isTablet = shortestSide >= 600;

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
            final tone = hasInput ? (valid ? cs.primary : cs.error) : cs.primary;

            return Align(
              alignment: Alignment.topLeft,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: hasInput
                    ? _DigitWrapDisplay(
                        key: ValueKey<String>('digits-$input-$valid'),
                        input: input,
                        maxDigits: _maxDigits,
                        boxSize: digitBoxSize,
                        spacing: spacing,
                        tone: tone,
                        valid: valid,
                        textTheme: text,
                      )
                    : _EmptyPlateNumberDisplay(
                        key: const ValueKey<String>('empty'),
                        width: emptyWidth,
                        height: emptyHeight,
                        colorScheme: cs,
                        textTheme: text,
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
  final String input;
  final int maxDigits;
  final double boxSize;
  final double spacing;
  final Color tone;
  final bool valid;
  final TextTheme textTheme;

  const _DigitWrapDisplay({
    super.key,
    required this.input,
    required this.maxDigits,
    required this.boxSize,
    required this.spacing,
    required this.tone,
    required this.valid,
    required this.textTheme,
  });

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
      children: [
        for (var i = 0; i < chars.length; i++)
          _DigitTile(
            digit: chars[i],
            boxSize: boxSize,
            tone: tone,
            valid: valid,
            textTheme: textTheme,
          ),
      ],
    );
  }
}

class _DigitTile extends StatelessWidget {
  final String digit;
  final double boxSize;
  final Color tone;
  final bool valid;
  final TextTheme textTheme;

  const _DigitTile({
    required this.digit,
    required this.boxSize,
    required this.tone,
    required this.valid,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final background = Color.alphaBlend(
      tone.withOpacity(valid ? 0.10 : 0.08),
      cs.surface,
    );
    final borderColor = tone.withOpacity(valid ? 0.82 : 0.72);
    final fontSize = (boxSize * 0.54).clamp(24.0, 40.0).toDouble();

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: boxSize,
      height: boxSize,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.25),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.04),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Text(
        digit,
        maxLines: 1,
        softWrap: false,
        style: (textTheme.titleLarge ?? const TextStyle()).copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.2,
          height: 1.0,
          color: valid ? cs.onSurface : cs.error,
        ),
      ),
    );
  }
}

class _EmptyPlateNumberDisplay extends StatelessWidget {
  final double width;
  final double height;
  final ColorScheme colorScheme;
  final TextTheme textTheme;

  const _EmptyPlateNumberDisplay({
    super.key,
    required this.width,
    required this.height,
    required this.colorScheme,
    required this.textTheme,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withOpacity(0.85),
          width: 1.2,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.dialpad_rounded,
            color: colorScheme.onSurfaceVariant,
            size: 20,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '번호 입력 대기 중',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: (textTheme.bodyLarge ?? const TextStyle()).copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w800,
                height: 1.0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
