import 'package:flutter/material.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ 로고(PNG) 가독성 보장 유틸
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

/// ✅ 단색(검정 고정) PNG 로고를 테마에 맞춰 tint 하는 위젯
///
/// - 경고 제거를 위해: "호출부에서 한 번도 안 넘기는 optional 파라미터"는 제거
/// - 기본 정책은 고정: preferred=cs.primary, fallback=cs.onBackground, minContrast=3.0
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

class DoubleCommuteInHeaderWidget extends StatelessWidget {
  const DoubleCommuteInHeaderWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const SizedBox(height: 24),
        SizedBox(
          height: 240,
          // ✅ 상단 로고 tint 적용 (단색/검정 고정 로고 대비 보장)
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
