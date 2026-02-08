// lib/screens/dev_stub_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../routes.dart';
import '../hubs_mode/dev_package/debug_package/debug_bottom_sheet.dart';
import '../hubs_mode/dev_package/github_code_browser_bottom_sheet.dart';
import '../hubs_mode/dev_package/github_markdown_bottom_sheet.dart';
import '../hubs_mode/dev_package/local_prefs_bottom_sheet.dart';
import '../hubs_mode/dev_package/dev_memo.dart';
import '../hubs_mode/dev_package/google_docs_bottom_sheet.dart';
// ✅ 추가: SQLite 탐색기
import '../hubs_mode/dev_package/sqlite_explorer_bottom_sheet.dart';

// ✅ 추가: DevCalendarPage 바텀시트 호출용 import
import '../hubs_mode/dev_package/dev_calendar_page.dart';

// ✅ 추가: 개발용 플로팅 버블 on/off 토글을 위해 가져옴
import '../hubs_mode/dev_package/dev_quick_actions.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ ParkinWorkin_text.png “브랜드 테마 tint” 유틸 (Head/Community/Faq와 동일 컨셉)
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

/// ✅ 경고 방지: optional 파라미터 제거(실사용만)
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
      preferred: cs.primary,
      fallback: cs.onBackground,
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

/// ─────────────────────────────────────────────────────────────
/// ✅ Dev 허브 토큰: “브랜드 테마” 기준으로 전체 화면 요소를 결정
@immutable
class _DevTokens {
  const _DevTokens({
    required this.pageBackground,
    required this.appBarBackground,
    required this.appBarForeground,
    required this.divider,

    required this.cardSurface,
    required this.cardBorder,

    required this.titleColor,
    required this.subtitleColor,

    required this.headerTintSurface,
    required this.headerBadgeBg,
    required this.headerBadgeFg,
    required this.headerTextColor,

    required this.bubbleChipBgOn,
    required this.bubbleChipBgOff,
    required this.bubbleChipBorderOn,
    required this.bubbleChipBorderOff,
    required this.bubbleChipTextOn,
    required this.bubbleChipTextOff,
  });

  final Color pageBackground;
  final Color appBarBackground;
  final Color appBarForeground;
  final Color divider;

  final Color cardSurface;
  final Color cardBorder;

  final Color titleColor;
  final Color subtitleColor;

  final Color headerTintSurface;
  final Color headerBadgeBg;
  final Color headerBadgeFg;
  final Color headerTextColor;

  final Color bubbleChipBgOn;
  final Color bubbleChipBgOff;
  final Color bubbleChipBorderOn;
  final Color bubbleChipBorderOff;
  final Color bubbleChipTextOn;
  final Color bubbleChipTextOff;

  factory _DevTokens.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Dev “느낌”은 유지하되(보라톤), 화면 전체는 테마 기반으로 반영
    // - 헤더/토글은 primary 계열을 적극 사용
    // - 카드/보더/텍스트는 surface/onSurfaceVariant 규칙 준수
    final headerTint = Color.alphaBlend(cs.primary.withOpacity(0.16), cs.surfaceContainerLow);
    final badgeBg = cs.primary;
    final badgeFg = cs.onPrimary;

    return _DevTokens(
      pageBackground: cs.background,
      appBarBackground: cs.background,
      appBarForeground: cs.onSurface,
      divider: cs.outlineVariant,

      cardSurface: cs.surface,
      cardBorder: cs.outlineVariant.withOpacity(0.85),

      titleColor: cs.onSurface,
      subtitleColor: cs.onSurfaceVariant,

      headerTintSurface: headerTint,
      headerBadgeBg: badgeBg,
      headerBadgeFg: badgeFg,
      headerTextColor: cs.onSurface,

      bubbleChipBgOn: cs.primary.withOpacity(0.12),
      bubbleChipBgOff: cs.surfaceVariant,
      bubbleChipBorderOn: cs.primary.withOpacity(0.35),
      bubbleChipBorderOff: cs.outlineVariant,
      bubbleChipTextOn: cs.primary,
      bubbleChipTextOff: cs.outline,
    );
  }
}

/// ─────────────────────────────────────────────────────────────
/// ✅ 회사 달력(그린) 팔레트: 기존 의도 유지(카드별 대표색)
const calBase = Color(0xFF43A047); // base
const calDark = Color(0xFF2E7D32); // dark (title)
const calLight = Color(0xFFA5D6A7); // light (tint)
const calFg = Colors.white; // on base

class DevStubPage extends StatelessWidget {
  const DevStubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = _DevTokens.of(context);
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ 이 화면에서만 뒤로가기 pop을 막아 앱 종료 방지 (알림 스낵바 없음)
    return PopScope(
      canPop: false,
      child: Scaffold(
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
            '개발 허브',
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
            color: tokens.pageBackground,
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeaderBanner(tokens: tokens),
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
                      final textScale = MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);

                      final tileWidth = (width - spacing * (crossAxisCount - 1)) / crossAxisCount;
                      const baseTileHeight = 150.0;
                      final tileHeight = baseTileHeight * textScale;
                      final childAspectRatio = tileWidth / tileHeight;

                      final cs = Theme.of(context).colorScheme;

                      final cards = <Widget>[
                        _ActionCard(
                          icon: Icons.code,
                          title: '코드',
                          subtitle: 'Dev',
                          bg: cs.primaryContainer,
                          fg: cs.onPrimaryContainer,
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const GithubCodeBrowserBottomSheet(
                                owner: 'tonalityquin',
                                repo: 'easy_dev',
                                defaultBranch: 'main',
                              ),
                            );
                          },
                        ),
                        _ActionCard(
                          icon: Icons.menu_book_rounded,
                          title: '텍스트',
                          subtitle: 'Side Project',
                          bg: cs.primaryContainer,
                          fg: cs.onPrimaryContainer,
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const GithubMarkdownBottomSheet(
                                owner: 'tonalityquin',
                                repo: 'side_project',
                                defaultBranch: 'main',
                              ),
                            );
                          },
                        ),
                        // ✅ 로컬 Prefs
                        _ActionCard(
                          icon: Icons.computer_rounded,
                          title: '로컬 컴퓨터',
                          subtitle: 'SharedPreferences',
                          bg: cs.surfaceVariant,
                          fg: cs.onSurfaceVariant,
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const LocalPrefsBottomSheet(),
                            );
                          },
                        ),
                        // ✅ 디버그
                        _ActionCard(
                          icon: Icons.bug_report_rounded,
                          title: '디버그',
                          subtitle: 'DB&API Logs\nLocal Logs',
                          bg: cs.errorContainer.withOpacity(.85),
                          fg: cs.onErrorContainer,
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const DebugBottomSheet(),
                            );
                          },
                        ),

                        // ✅ 메모: 카드 탭 → 메모 패널 열기
                        _ActionCard(
                          icon: Icons.sticky_note_2_rounded,
                          title: 'MarkDown',
                          subtitle: 'Obsidian',
                          bg: cs.primaryContainer,
                          fg: cs.onPrimaryContainer,
                          tintColor: cs.primary.withOpacity(0.10),
                          titleColor: cs.primary,
                          onTap: () async {
                            await DevMemo.togglePanel();
                          },
                        ),

                        // ✅ 개인 달력(그린 팔레트) — 바텀시트로 열기
                        _ActionCard(
                          icon: Icons.calendar_month_rounded,
                          title: '개인 달력',
                          subtitle: 'Google Calendar',
                          bg: calBase,
                          fg: calFg,
                          tintColor: calLight,
                          titleColor: calDark,
                          onTap: () {
                            DevCalendarPage.showAsBottomSheet(context);
                          },
                        ),

                        // ✅ 구글 독스: 패널 토글
                        _ActionCard(
                          icon: Icons.description_outlined,
                          title: '구글 독스',
                          subtitle: '문서 편집 · Docs API',
                          bg: cs.primaryContainer,
                          fg: cs.onPrimaryContainer,
                          tintColor: cs.primary.withOpacity(0.08),
                          titleColor: cs.primary,
                          onTap: () async {
                            GoogleDocsDocPanel.enabled.value = true;
                            await GoogleDocsDocPanel.togglePanel();
                          },
                        ),

                        // ✅ SQLite 탐색기
                        _ActionCard(
                          icon: Icons.storage_rounded,
                          title: 'SQLite',
                          subtitle: 'DB 탐색기 · 미리보기',
                          bg: cs.primaryContainer,
                          fg: cs.onPrimaryContainer,
                          tintColor: cs.secondary.withOpacity(0.08),
                          onTap: () {
                            showModalBottomSheet(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (_) => const Material(
                                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                                clipBehavior: Clip.antiAlias,
                                child: SizedBox(
                                  height: 560,
                                  child: SQLiteExplorerBottomSheet(),
                                ),
                              ),
                            );
                          },
                        ),
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

        // ✅ 하단 로고: 브랜드 테마 tint 적용 + divider 적용
        bottomNavigationBar: SafeArea(
          top: false,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: tokens.pageBackground,
              border: Border(top: BorderSide(color: tokens.divider, width: 1)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
                  AppRoutes.selector,
                      (route) => false,
                ),
                child: SizedBox(
                  height: 120,
                  child: Center(
                    child: _BrandTintedLogo(height: 56),
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

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner({required this.tokens});

  final _DevTokens tokens;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: tokens.headerTintSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tokens.divider.withOpacity(0.85)),
      ),
      child: Row(
        children: [
          // 아이콘 배지 — 테마 primary 기반
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tokens.headerBadgeBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Icon(Icons.developer_mode_rounded, color: tokens.headerBadgeFg),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '개발 허브 입니다.',
              style: text.bodyMedium?.copyWith(
                color: tokens.headerTextColor,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          // 🔘 ON/OFF 토글 — 오른쪽 고정(브랜드 테마 반영)
          ValueListenableBuilder<bool>(
            valueListenable: DevQuickActions.enabled,
            builder: (context, on, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: on ? tokens.bubbleChipBgOn : tokens.bubbleChipBgOff,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: on ? tokens.bubbleChipBorderOn : tokens.bubbleChipBorderOff,
                      ),
                    ),
                    child: Text(
                      on ? 'Bubble ON' : 'Bubble OFF',
                      style: text.labelMedium?.copyWith(
                        color: on ? tokens.bubbleChipTextOn : tokens.bubbleChipTextOff,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch.adaptive(
                    value: on,
                    onChanged: (v) async {
                      DevQuickActions.setEnabled(v);
                      if (v) {
                        await DevQuickActions.mountIfNeeded();
                      }
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(v ? '개발 버블이 켜졌습니다.' : '개발 버블이 꺼졌습니다.'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(milliseconds: 900),
                        ),
                      );
                    },
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  // 배지 색(카드 아이콘 원형)
  final Color bg;
  final Color fg;

  // 카드 표면 tint, 제목 컬러(옵션)
  final Color? tintColor;
  final Color? titleColor;

  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bg,
    required this.fg,
    this.tintColor,
    this.titleColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      // ✅ white 고정 제거 → 테마 surface
      color: cs.surface,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: tintColor ?? bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: fg, size: 26),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                title,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: titleColor ?? cs.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  // ✅ grey 하드코딩 제거 → onSurfaceVariant
                  color: cs.onSurfaceVariant,
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
    );
  }
}
