import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'stub_package/debug_bottom_sheet.dart';
import 'stub_package/game_arcade_bottom_sheet.dart';
import 'stub_package/github_code_browser_bottom_sheet.dart';
import 'stub_package/github_markdown_bottom_sheet.dart';
import 'stub_package/local_prefs_bottom_sheet.dart';
import 'stub_package/roadmap_bottom_sheet.dart';

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
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.15,
                  children: [
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
                      subtitle: 'Writing',
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
                      subtitle: 'Project',
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
                    // ✅ 추가된 디버그 로그 카드
                    _ActionCard(
                      icon: Icons.bug_report_rounded,
                      title: '디버그',
                      subtitle: 'Firestore Logs',
                      bg: cs.errorContainer.withOpacity(.85),
                      fg: cs.onErrorContainer,
                      onTap: () {
                        showModalBottomSheet(
                          context: context,
                          isScrollControlled: true,
                          backgroundColor: Colors.transparent,
                          builder: (_) => const Material(
                            // 둥근 모서리로 감싸서 다른 시트들과 톤 맞춤
                            borderRadius: BorderRadius.vertical(
                                top: Radius.circular(16)),
                            clipBehavior: Clip.antiAlias,
                            child: SizedBox(
                              height: 560,
                              child: DebugBottomSheet(),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
              Center(
                child: InkWell(
                  onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
                    '/selector', // AppRoutes.selector
                        (route) => false,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: 80,
                    child: Image.asset('assets/images/pelican.png'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
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
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(0.7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: cs.onPrimaryContainer.withOpacity(.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.groups_rounded, color: cs.onPrimaryContainer),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '커뮤니티 허브(임시)\n도구를 여기서 확장합니다.',
              style: text.bodyMedium?.copyWith(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w600,
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
  final VoidCallback? onTap; // 카드 아무 곳이나 탭

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
    // 카드 외곽 InkWell: 본문(아이콘 제외) 탭 처리용
    return Card(
      color: Colors.white,
      elevation: 1,
      clipBehavior: Clip.antiAlias,
      surfaceTintColor: bg,
      child: InkWell(
        // 카드 빈 공간(본문)을 탭했을 때만 onTap
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 아이콘: 별도 InkWell 로 분리
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap, // onIconTap 없으면 onTap을 대신 호출
                  customBorder: const CircleBorder(),
                  child: Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: bg,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(icon, color: fg, size: 28),
                  ),
                ),
              ),
              const SizedBox(height: 10),
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
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
