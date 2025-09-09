// lib/screens/dev_stub_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../routes.dart';
import 'dev_package/debug_package/debug_bottom_sheet.dart';
import 'dev_package/github_code_browser_bottom_sheet.dart';
import 'dev_package/github_markdown_bottom_sheet.dart';
import 'dev_package/local_prefs_bottom_sheet.dart';

/// ====== 개발 전용 팔레트 (개발 카드와 동일 톤) ======
/// 버튼/Badge 배경
const kDevPrimary = Color(0xFF6A1B9A); // Deep Purple
const kDevPrimaryHover = Color(0xFF7B1FA2); // (옵션) Hover
const kDevPrimaryPressed = Color(0xFF4A148C); // Pressed / Dark

/// 밝은 포인트(카드 tint/표면 강조)
const kDevTint = Color(0xFFCE93D8); // Purple 200

/// 제목/링크성 텍스트(화이트 배경에서 가독성 우수)
const kDevDarkText = Color(0xFF4A148C);

/// Primary 위 텍스트/아이콘
const kDevOnPrimary = Colors.white;

/// ====== 회사 달력(그린) 팔레트: Head/Hub 카드와 동일 톤 ======
const calBase = Color(0xFF43A047); // base
const calDark = Color(0xFF2E7D32); // dark (title)
const calLight = Color(0xFFA5D6A7); // light (tint)
const calFg = Colors.white; // on base

class DevStubPage extends StatelessWidget {
  const DevStubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        systemOverlayStyle: const SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
          statusBarBrightness: Brightness.light,
        ),
        title: Text(
          '개발 허브',
          style: text.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.2,
            color: cs.onSurface,
          ),
        ),
        iconTheme: IconThemeData(color: cs.onSurface),
        actionsIconTheme: IconThemeData(color: cs.onSurface),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.black.withOpacity(0.06)),
        ),
      ),
      body: SafeArea(
        child: Container(
          color: Colors.white,
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
                    final textScale = MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);

                    final tileWidth = (width - spacing * (crossAxisCount - 1)) / crossAxisCount;
                    final baseTileHeight = 150.0;
                    final tileHeight = baseTileHeight * textScale;
                    final childAspectRatio = tileWidth / tileHeight;

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
                      // ✅ 회사 달력 카드 (그린 팔레트 + tint/titleColor 지원)

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
                      _ActionCard(
                        icon: Icons.bug_report_rounded,
                        title: '디버그',
                        subtitle: 'Firestore Logs\nLocal Logs',
                        bg: cs.errorContainer.withOpacity(.85),
                        fg: cs.onErrorContainer,
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
                                child: DebugBottomSheet(),
                              ),
                            ),
                          );
                        },
                      ),
                      _ActionCard(
                        icon: Icons.calendar_month_rounded,
                        title: '개인 달력',
                        subtitle: 'Google Calendar',
                        bg: calBase,
                        fg: calFg,
                        tintColor: calLight,
                        titleColor: calDark,
                        onTap: () {
                          Navigator.of(context).pushNamed(AppRoutes.devCalendar);
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

      // ✅ Pelican 이미지는 하얀 배경에 최적화 → 탭 시 '/selector'로 이동
      bottomNavigationBar: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(
              top: BorderSide(color: Colors.black.withOpacity(0.06), width: 1),
            ),
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
                child: Image.asset('assets/images/pelican.png'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kDevTint.withOpacity(0.75), // ✅ 개발 tint 적용
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // 아이콘 배지 — Dev Primary 대비 White 아이콘
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: kDevPrimary, // ✅ 개발 Primary
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.developer_mode_rounded, color: kDevOnPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '개발 허브 입니다.',
              style: text.bodyMedium?.copyWith(
                color: kDevDarkText, // ✅ 가독성 좋은 Deep Purple 계열 텍스트
                fontWeight: FontWeight.w700,
              ),
            ),
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
  final Color bg; // 배지 배경(base)
  final Color fg; // 배지 아이콘(onBase)
  final Color? tintColor; // 카드 surfaceTint(light)  ← 추가
  final Color? titleColor; // 제목 색(dark)           ← 추가
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
    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: tintColor ?? bg,
      // ✅ tintColor 지원
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // 여백 최적화
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
                  fontWeight: FontWeight.w700,
                  color: titleColor ?? Colors.black, // ✅ titleColor 지원
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  height: 1.15, // 2줄일 때도 촘촘하게
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
