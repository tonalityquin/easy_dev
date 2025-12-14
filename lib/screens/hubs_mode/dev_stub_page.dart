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

    // ✅ 이 화면에서만 뒤로가기 pop을 막아 앱 종료 방지 (알림 스낵바 없음)
    return PopScope(
      canPop: false,
      child: Scaffold(
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
                      final textScale =
                      MediaQuery.of(context).textScaleFactor.clamp(1.0, 1.3);

                      final tileWidth =
                          (width - spacing * (crossAxisCount - 1)) / crossAxisCount;
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
                              builder: (_) => const DebugBottomSheet(),  // ✅ 깔끔하게 이 한 줄
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
                          tintColor: kDevTint.withOpacity(0.45),
                          titleColor: kDevDarkText,
                          onTap: () async {
                            await DevMemo.togglePanel();
                          },
                        ),

                        // ✅ 개인 달력 (그린 팔레트) — 바텀시트(92%)로 열기
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
                          tintColor: kDevTint.withOpacity(0.35),
                          titleColor: kDevDarkText,
                          onTap: () async {
                            GoogleDocsDocPanel.enabled.value = true;
                            await GoogleDocsDocPanel.togglePanel();
                          },
                        ),

                        // ✅ NEW: SQLite 탐색기
                        _ActionCard(
                          icon: Icons.storage_rounded,
                          title: 'SQLite',
                          subtitle: 'DB 탐색기 · 미리보기',
                          bg: cs.primaryContainer,
                          fg: cs.onPrimaryContainer,
                          tintColor: Colors.blueGrey.withOpacity(.15),
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
      ),
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

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

          // 🔘 ON/OFF 토글 — 오른쪽에 고정
          ValueListenableBuilder<bool>(
            valueListenable: DevQuickActions.enabled,
            builder: (context, on, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: on ? kDevPrimary.withOpacity(.12) : cs.surfaceVariant,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: on ? kDevPrimary.withOpacity(.35) : cs.outlineVariant,
                      ),
                    ),
                    child: Text(
                      on ? 'Bubble ON' : 'Bubble OFF',
                      style: text.labelMedium?.copyWith(
                        color: on ? kDevDarkText : cs.outline,
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
                        // 켜질 때 바로 부착 시도
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
  final Color bg; // 배지 배경(base)
  final Color fg; // 배지 아이콘(onBase)
  final Color? tintColor; // 카드 surfaceTint(light)
  final Color? titleColor; // 제목 색(dark)
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
