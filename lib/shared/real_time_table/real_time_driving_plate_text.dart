import 'package:flutter/material.dart';

import '../../design_system/common_ui/common_ui_theme.dart';

class RealTimeDrivingPlateText extends StatelessWidget {
  const RealTimeDrivingPlateText({
    super.key,
    required this.text,
    required this.driving,
    required this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.clip,
    this.softWrap = false,
    this.lineColor,
  });

  final String text;
  final bool driving;
  final TextStyle? style;
  final int maxLines;
  final TextOverflow overflow;
  final bool softWrap;
  final Color? lineColor;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final resolvedStyle = style ?? DefaultTextStyle.of(context).style;
    final resolvedColor = lineColor ??
        resolvedStyle.color ??
        Theme.of(context).colorScheme.onSurface;
    final duration = reduceMotion ? Duration.zero : CommonUiMotion.selection;
    return Stack(
      alignment: Alignment.center,
      clipBehavior: Clip.none,
      children: [
        Text(
          text,
          maxLines: maxLines,
          overflow: overflow,
          softWrap: softWrap,
          style: resolvedStyle,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Align(
              alignment: const Alignment(0, .04),
              child: FractionallySizedBox(
                widthFactor: .94,
                child: AnimatedScale(
                  scale: driving ? 1 : 0,
                  alignment: Alignment.center,
                  duration: duration,
                  curve: driving ? CommonUiMotion.enter : CommonUiMotion.exit,
                  child: AnimatedOpacity(
                    opacity: driving ? 1 : 0,
                    duration: duration,
                    curve: driving ? CommonUiMotion.enter : CommonUiMotion.exit,
                    child: Container(
                      height: 1.6,
                      decoration: BoxDecoration(
                        color: resolvedColor.withOpacity(.78),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
