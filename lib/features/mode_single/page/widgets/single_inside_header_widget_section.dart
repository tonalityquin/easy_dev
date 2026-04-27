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
  if (_contrastRatio(preferred, background) >= minContrast) return preferred;
  return fallback;
}


class _BrandTintedLogo extends StatelessWidget {
  const _BrandTintedLogo({
    required this.assetPath,
    required this.height,
  });

  final String assetPath;
  final double height;

  static const double _kMinContrast = 3.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final bg = theme.scaffoldBackgroundColor;

    final tint = _resolveLogoTint(
      background: bg,
      preferred: cs.primary,
      fallback: cs.onBackground,
      minContrast: _kMinContrast,
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

class SingleInsideHeaderWidgetSection extends StatelessWidget {
  const SingleInsideHeaderWidgetSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        SizedBox(
          height: 240,
          
          child: const _BrandTintedLogo(
            assetPath: 'assets/images/ParkinWorkin_logo.png',
            height: 240,
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }
}
