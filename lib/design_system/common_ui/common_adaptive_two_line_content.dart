import 'package:flutter/material.dart';

class CommonAdaptiveTwoLineContent extends StatelessWidget {
  const CommonAdaptiveTwoLineContent({
    super.key,
    required this.title,
    required this.subtitle,
    this.gap = 3,
    this.alignment = CrossAxisAlignment.start,
    this.mainAxisAlignment = MainAxisAlignment.center,
  });

  final Widget title;
  final Widget subtitle;
  final double gap;
  final CrossAxisAlignment alignment;
  final MainAxisAlignment mainAxisAlignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: mainAxisAlignment,
      crossAxisAlignment: alignment,
      children: [
        title,
        SizedBox(height: gap),
        subtitle,
      ],
    );
  }
}
