// lib/screens/community_stub_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'community_package/debug_package/debug_bottom_sheet.dart';
import 'community_package/game_arcade_bottom_sheet.dart';
import 'community_package/github_code_browser_bottom_sheet.dart';
import 'community_package/github_markdown_bottom_sheet.dart';
import 'community_package/local_prefs_bottom_sheet.dart';
import 'community_package/roadmap_bottom_sheet.dart';

/// ====== 커뮤니티 전용 팔레트 (대비 강화) ======
/// 버튼/Badge 배경(White와 5.3:1 대비 확보)
const kCommunityPrimary = Color(0xFF00796B); // Teal 700
const kCommunityPrimaryHover = Color(0xFF00897B); // Teal 600
const kCommunityPrimaryPressed = Color(0xFF00695C); // Teal 800
/// 밝은 포인트(배지/하이라이트)
const kCommunityBase = Color(0xFF26A69A); // Teal 400
/// 제목/링크성 텍스트(화이트 배경에서 가독성 우수)
const kCommunityDarkText = Color(0xFF1E8077);
/// 카드 tint/표면 강조
const kCommunityTint = Color(0xFF64D8CB);
/// Primary 위 텍스트/아이콘
const kCommunityOnPrimary = Colors.white;

class CommunityStubPage extends StatelessWidget {
  const CommunityStubPage({super.key});

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
          '커뮤니티 허브',
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

              // ✅ 반응형 Grid (카드 디자인 변경 없음)
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
                    final baseTileHeight = 150.0; // 필요 시 140~170 조정
                    final tileHeight = baseTileHeight * textScale;
                    final childAspectRatio = tileWidth / tileHeight;

                    final cards = <Widget>[
                      _ActionCard(
                        icon: Icons.videogame_asset_rounded,
                        title: '아케이드',
                        subtitle: 'Arcade',
                        bg: cs.secondaryContainer,
                        fg: cs.onSecondaryContainer,
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) =>
                                GameArcadeBottomSheet(rootContext: context),
                          );
                        },
                      ),
                      _ActionCard(
                        icon: Icons.edit_note_rounded,
                        title: '로드맵',
                        subtitle: 'After Release',
                        bg: cs.tertiaryContainer,
                        fg: cs.onTertiaryContainer,
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const RoadmapBottomSheet(),
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
                              // initialPath: 'README.md',
                            ),
                          );
                        },
                      ),
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
                              // initialPath: '',
                            ),
                          );
                        },
                      ),
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
                        subtitle: 'Firestore Logs\nLocal Logs', // ✅ 2줄
                        bg: cs.errorContainer.withOpacity(.85),
                        fg: cs.onErrorContainer,
                        onTap: () {
                          showModalBottomSheet(
                            context: context,
                            isScrollControlled: true,
                            backgroundColor: Colors.transparent,
                            builder: (_) => const Material(
                              borderRadius:
                              BorderRadius.vertical(top: Radius.circular(16)),
                              clipBehavior: Clip.antiAlias,
                              child: SizedBox(
                                height: 560,
                                child: DebugBottomSheet(),
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

      // ✅ Pelican 이미지는 하얀 배경에 최적화 → 탭 시 '/selector'로 이동 로직 복원
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
                '/selector',
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
        // 커뮤니티 tint에 살짝 투명도를 주어 부드럽게
        color: kCommunityTint.withOpacity(0.75),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          // 아이콘 배지 — Primary 대비 White 아이콘
          Container(
            width: 44,
            height: 44,
            decoration: const BoxDecoration(
              color: kCommunityPrimary,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: const Icon(Icons.groups_rounded, color: kCommunityOnPrimary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '커뮤니티 허브 입니다.',
              style: text.bodyMedium?.copyWith(
                color: kCommunityDarkText, // 가독성 좋은 짙은 틸 텍스트
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
  final Color bg;
  final Color fg;
  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bg,
    required this.fg,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: bg,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // 여백 살짝 최적화
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
                style: const TextStyle(fontWeight: FontWeight.w700),
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
