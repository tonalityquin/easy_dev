// lib/screens/community_stub_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../hubs_mode/community_package/game_arcade_bottom_sheet.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ ParkinWorkin_text.png “브랜드 테마 tint” 유틸 (HeadStubPage/SelectorHubsPage와 동일 컨셉)
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

/// ✅ 경고 제거 버전: optional 파라미터(미사용) 제거
class _BrandTintedLogo extends StatelessWidget {
  const _BrandTintedLogo({required this.height});

  static const String _assetPath = 'assets/images/ParkinWorkin_text.png';
  static const double _minContrast = 3.0;

  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.background;

    final tint = _resolveLogoTint(
      background: bg,
      preferred: cs.primary,       // 브랜드 강조(우선)
      fallback: cs.onBackground,   // 가독성 최우선(폴백)
      minContrast: _minContrast,
    );

    return Image.asset(
      _assetPath,
      fit: BoxFit.contain,
      height: height,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}

/// ✅ 커뮤니티 화면 토큰(브랜드테마 기반)
@immutable
class _CommunityTokens {
  const _CommunityTokens({
    required this.pageBackground,
    required this.appBarBackground,
    required this.appBarForeground,
    required this.divider,
    required this.cardSurface,
    required this.cardBorder,
    required this.title,
    required this.subtitle,
  });

  final Color pageBackground;
  final Color appBarBackground;
  final Color appBarForeground;
  final Color divider;

  final Color cardSurface;
  final Color cardBorder;

  final Color title;
  final Color subtitle;

  factory _CommunityTokens.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _CommunityTokens(
      pageBackground: cs.background,
      appBarBackground: cs.background,
      appBarForeground: cs.onSurface,
      divider: cs.outlineVariant,

      cardSurface: cs.surface,
      cardBorder: cs.outlineVariant.withOpacity(0.85),

      title: cs.onSurface,
      subtitle: cs.onSurfaceVariant,
    );
  }
}

class CommunityStubPage extends StatelessWidget {
  const CommunityStubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = _CommunityTokens.of(context);
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ 이 화면에서만 뒤로가기 pop을 막아 앱 종료 방지 (알림 스낵바 없음)
    return PopScope(
      canPop: false,
      child: Scaffold(
        // ✅ white 하드코딩 제거 → 브랜드테마/독립 프리셋 반영
        backgroundColor: tokens.pageBackground,
        appBar: AppBar(
          backgroundColor: tokens.appBarBackground,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          systemOverlayStyle: SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
            statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
          ),
          title: Text(
            '커뮤니티 허브',
            style: text.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.2,
              color: tokens.appBarForeground,
            ),
          ),
          iconTheme: IconThemeData(color: tokens.appBarForeground),
          actionsIconTheme: IconThemeData(color: tokens.appBarForeground),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: tokens.divider),
          ),
        ),
        body: SafeArea(
          child: Container(
            // ✅ white 하드코딩 제거
            color: tokens.pageBackground,
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _HeaderBanner(),
                const SizedBox(height: 16),

                // ✅ 반응형 Grid
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final crossAxisCount = width >= 1100
                          ? 4
                          : width >= 800
                          ? 3
                          : 2;

                      const spacing = 12.0;
                      final textScale =
                      MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);

                      final tileWidth =
                          (width - spacing * (crossAxisCount - 1)) / crossAxisCount;
                      const baseTileHeight = 150.0;
                      final tileHeight = baseTileHeight * textScale;
                      final childAspectRatio = tileWidth / tileHeight;

                      // ✅ 커뮤니티에서도 “브랜드테마 반영”을 위해 scheme 기반 accent 사용
                      // (커뮤니티 느낌은 secondary 라인으로 통일)
                      final accent = cs.secondary;
                      final onAccent = cs.onSecondary;

                      final cards = <Widget>[
                        _ActionCard(
                          icon: Icons.videogame_asset_rounded,
                          title: '아케이드',
                          subtitle: 'Arcade',
                          accent: accent,
                          onAccent: onAccent,
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => GameArcadeBottomSheet(rootContext: context),
                            );
                          },
                        ),
                        // (이전) 로드맵 카드는 HeadStubPage로 이동
                      ];

                      return GridView.builder(
                        padding: EdgeInsets.zero,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: childAspectRatio,
                        ),
                        itemCount: cards.length,
                        itemBuilder: (context, i) => cards[i],
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),

        // ✅ 하단 로고도 “브랜드테마 tint” 적용 + 하드코딩 white/black divider 제거
        bottomNavigationBar: SafeArea(
          top: false,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.pageBackground,
              border: Border(
                top: BorderSide(color: tokens.divider, width: 1),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
                  '/selector',
                      (route) => false,
                ),
                child: SizedBox(
                  height: 120,
                  child: Center(
                    child: _BrandTintedLogo(height: 52),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ✅ “커뮤니티 허브 입니다.” 배너도 ColorScheme 기반으로 전면 테마 반영
class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    // ✅ 커뮤니티 배너는 secondary 라인을 사용(브랜드테마 반영)
    final base = cs.secondary;
    final container = cs.secondaryContainer;
    final onContainer = cs.onSecondaryContainer;

    final border = cs.outlineVariant.withOpacity(0.85);

    // ✅ container를 background에 블렌딩해서 독립 프리셋에서도 과하지 않게
    final bg0 = Color.alphaBlend(container.withOpacity(0.92), cs.background);
    final bg1 = Color.alphaBlend(base.withOpacity(0.10), cs.background);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [bg0, bg1],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: border),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: base.withOpacity(0.14),
              shape: BoxShape.circle,
              border: Border.all(color: base.withOpacity(0.22)),
            ),
            alignment: Alignment.center,
            child: Icon(Icons.groups_rounded, color: base),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '커뮤니티 허브 입니다.',
              style: text.bodyMedium?.copyWith(
                color: onContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// ✅ 카드 섹션도 “브랜드테마 반영”
/// - Card: cs.surface, border: cs.outlineVariant
/// - accent(아이콘 원형색)을 카드 전체 배경에 아주 옅게 overlay
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final Color onAccent;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onAccent,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = _CommunityTokens.of(context);
    final cs = Theme.of(context).colorScheme;

    final tint = Color.alphaBlend(accent.withOpacity(0.10), tokens.cardSurface);

    return Card(
      elevation: 0,
      color: tokens.cardSurface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: tokens.cardBorder, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [tokens.cardSurface, tint],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Semantics(
                  button: true,
                  label: title,
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: cs.shadow.withOpacity(0.10),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: onAccent, size: 26),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: tokens.title,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: tokens.subtitle,
                    fontSize: 12,
                    height: 1.15,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
