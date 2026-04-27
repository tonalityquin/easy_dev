import 'package:flutter/material.dart';

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final l1 = la >= lb ? la : lb;
  final l2 = la >= lb ? lb : la;
  return (l1 + 0.05) / (l2 + 0.05);
}

Color _resolveLogoTint({
  required Color background,
  required Color preferred,
  required Color fallback,
  double minContrast = 3.0,
}) {
  if (_contrastRatio(preferred, background) >= minContrast) {
    return preferred;
  }
  return fallback;
}

class CommonBrandTintedLogo extends StatelessWidget {
  const CommonBrandTintedLogo({
    super.key,
    required this.assetPath,
    required this.height,
    this.preferredColor,
    this.fallbackColor,
    this.minContrast = 3.0,
  });

  final String assetPath;
  final double height;
  final Color? preferredColor;
  final Color? fallbackColor;
  final double minContrast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final background = theme.scaffoldBackgroundColor;
    final preferred = preferredColor ?? cs.primary;
    final fallback = fallbackColor ?? cs.onBackground;

    final tint = _resolveLogoTint(
      background: background,
      preferred: preferred,
      fallback: fallback,
      minContrast: minContrast,
    );

    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      height: height,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}
