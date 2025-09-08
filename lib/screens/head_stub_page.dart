import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../routes.dart'; // ▼ AppRoutes 사용
import 'head_package/github_code_browser_bottom_sheet.dart';
import 'head_package/roadmap_bottom_sheet.dart';

class HeadStubPage extends StatelessWidget {
  const HeadStubPage({super.key});

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
          '본사 허브',
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

              // ✅ 반응형 Grid: 화면 너비/텍스트배율에 따라 열 수와 타일 비율 계산
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

                    // 타일 기준 높이(컨텐츠에 여유), 텍스트 배율 반영
                    final baseTileHeight = 150.0;
                    final tileHeight = baseTileHeight * textScale;
                    final childAspectRatio = tileWidth / tileHeight;

                    // ── 팔레트 정의 (base/dark/light) ─────────────────────────
                    // Roadmap — Deep Purple
                    const roadBase = Color(0xFF7E57C2);
                    const roadDark = Color(0xFF5E35B1);
                    const roadLight = Color(0xFFB39DDB);

                    // Code — Cobalt Blue
                    const codeBase = Color(0xFF1976D2);
                    const codeDark = Color(0xFF1565C0);
                    const codeLight = Color(0xFF90CAF9);

                    // Company Calendar — Green
                    const calBase = Color(0xFF43A047);
                    const calDark = Color(0xFF2E7D32);
                    const calLight = Color(0xFFA5D6A7);

                    // Labor Guide — Orange/Amber
                    const laborBase = Color(0xFFF57C00);
                    const laborDark = Color(0xFFE65100);
                    const laborLight = Color(0xFFFFCC80);

                    final cards = <Widget>[
                      _ActionCard(
                        icon: Icons.edit_note_rounded,
                        title: '로드맵',
                        subtitle: 'After Release',
                        bg: roadBase,
                        fg: Colors.white,
                        tintColor: roadLight,
                        titleColor: roadDark,
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
                        icon: Icons.code,
                        title: '코드',
                        subtitle: 'Github',
                        bg: codeBase,
                        fg: Colors.white,
                        tintColor: codeLight,
                        titleColor: codeDark,
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
                        icon: Icons.calendar_month_rounded,
                        title: '회사 달력',
                        subtitle: 'Google Calendar\nGoogle Sheet', // ✅ 2줄
                        bg: calBase,
                        fg: Colors.white,
                        tintColor: calLight,
                        titleColor: calDark,
                        onTap: () {
                          Navigator.of(context).pushNamed(AppRoutes.companyCalendar);
                        },
                      ),
                      _ActionCard(
                        icon: Icons.gavel_rounded,
                        title: '회사 노무',
                        subtitle: 'Google Drive',
                        bg: laborBase,
                        fg: Colors.white,
                        tintColor: laborLight,
                        titleColor: laborDark,
                        onTap: () {
                          Navigator.of(context).pushNamed(AppRoutes.laborGuide);
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
              '본사 허브 입니다.',
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
  final Color bg;          // 배지 배경(base)
  final Color fg;          // 배지 아이콘(onBase)
  final Color? tintColor;  // 카드 surfaceTint(light)
  final Color? titleColor; // 제목 색(dark)
  final VoidCallback? onTap; // 카드 아무 곳이나 탭

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
      child: InkWell(
        onTap: onTap,
        child: Padding(
          // 살짝 여백 절약
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
                  color: titleColor ?? Colors.black,
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
                  height: 1.15, // 줄간격을 살짝 촘촘하게
                ),
                maxLines: 2, // 최대 2줄
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
