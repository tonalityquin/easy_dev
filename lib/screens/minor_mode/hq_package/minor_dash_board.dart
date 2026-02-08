import 'package:flutter/material.dart';
import '../../../widgets/navigation/minor_top_navigation.dart';
import '../type_package/common_widgets/dashboard_bottom_sheet/minor_hq_dash_board_page.dart';

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

/// ✅ (경고 방지) required 파라미터만 사용하는 tint 로고 위젯
class _BrandTintedLogo extends StatelessWidget {
  const _BrandTintedLogo({
    required this.assetPath,
    required this.height,
    required this.preferredColor,
    required this.fallbackColor,
    this.minContrast = 3.0,
  });

  final String assetPath;
  final double height;

  final Color preferredColor;
  final Color fallbackColor;
  final double minContrast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;

    final tint = _resolveLogoTint(
      background: bg,
      preferred: preferredColor,
      fallback: fallbackColor,
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

class MinorDashBoard extends StatelessWidget {
  const MinorDashBoard({super.key});

  static const String screenTag = 'MinorHeadQuarter'; // 화면 식별 태그

  // ✅ (신규) screenTag 텍스트 대신 사용할 이미지(첨부파일)
  static const String _kScreenTagAsset = 'assets/images/pelican_text.png';

  // ✅ (요청) 좌측 상단 태그 이미지 크기 고정
  static const double _kScreenTagHeight = 54.0;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ✅ 기존 텍스트 색감(onSurfaceVariant)과 동일한 톤으로 이미지 tint 시도
    // 대비 부족 시 onBackground로 폴백
    final tagPreferredTint = cs.onSurfaceVariant.withOpacity(0.80);

    return WillPopScope(
      onWillPop: () async => false, // 뒤로가기 차단(기존 동작 유지)
      child: Scaffold(
        appBar: AppBar(
          title: const MinorTopNavigation(),
          centerTitle: true,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: Border(
            bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1),
          ),

          // ⬇️ 좌측 상단(11시 방향)에 태그 "텍스트" 대신 이미지 고정
          flexibleSpace: SafeArea(
            child: IgnorePointer(
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12, top: 4),
                  child: Semantics(
                    label: 'screen_tag: MinorDashBoard C',
                    child: ExcludeSemantics(
                      child: _BrandTintedLogo(
                        assetPath: _kScreenTagAsset,
                        height: _kScreenTagHeight,
                        preferredColor: tagPreferredTint,
                        fallbackColor: cs.onBackground,
                        minContrast: 3.0,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        body: const MinorHqDashBoardPage(), // 단일 콘텐츠
      ),
    );
  }
}
