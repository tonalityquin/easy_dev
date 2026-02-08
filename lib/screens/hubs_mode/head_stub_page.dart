import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../routes.dart';
import '../hubs_mode/head_package/head_memo.dart';
import '../hubs_mode/head_package/roadmap_bottom_sheet.dart';

// ▼ 근무지 현황
import '../hubs_mode/head_package/mgmt_package/field.dart' as mgmt;

// ▼ 통계 비교
import '../hubs_mode/head_package/mgmt_package/statistics.dart' as mgmt_stats;

// ▼ 출/퇴근(출석) · 휴게 관리
import '../hubs_mode/head_package/hr_package/attendance_calendar.dart' as hr_att;
import '../hubs_mode/head_package/hr_package/break_calendar.dart' as hr_break;

// ▼ 본사 달력 바텀시트
import '../hubs_mode/head_package/company_calendar_page.dart';

// ✅ 본사 허브 퀵 액션 버블 ON/OFF
import '../hubs_mode/head_package/hub_quick_actions.dart';

// ✅ (분리) 튜토리얼 공용
import '../hubs_mode/head_package/head_tutorials.dart';

// ✅ (신규) 채팅 패키지: 바텀시트/패널
import '../hubs_mode/head_package/chat_package/chat_bottom_sheet.dart';
import 'noti_package/notice_editor_bottom_sheet.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ ParkinWorkin_text.png “브랜드 테마 tint” 유틸
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

/// ✅ 경고 제거 버전: optional 파라미터 제거(내부 상수로 고정)
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

class HeadStubPage extends StatelessWidget {
  const HeadStubPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // ✅ 이 화면에서만 뒤로가기 pop을 막아 앱 종료 방지 (스낵바 없음)
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: cs.background,
        appBar: AppBar(
          backgroundColor: cs.background,
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
            child: Container(height: 1, color: cs.outlineVariant),
          ),
        ),
        body: SafeArea(
          child: Container(
            color: cs.background,
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

                      // ✅ 카드별 accent를 ColorScheme 기반으로 분배(브랜드테마 반영)
                      // - “카드별 색 구분”은 유지하되, 고정 팔레트 대신 scheme의 key color 사용
                      final a1 = cs.primary;
                      final a2 = cs.secondary;
                      final a3 = cs.tertiary;
                      final a4 = cs.error; // notice 계열에 활용(오렌지 고정 제거)
                      final a5 = cs.primaryContainer;
                      final a6 = cs.secondaryContainer;
                      final a7 = cs.tertiaryContainer;
                      final a8 = cs.surfaceVariant;

                      final cards = <Widget>[
                        _ActionCard(
                          icon: Icons.calendar_month_rounded,
                          title: '본사 달력',
                          subtitle: 'Google Calendar\nSpread Sheets',
                          bg: a1,
                          fg: cs.onPrimary,
                          onTap: () => CompanyCalendarPage.showAsBottomSheet(context),
                        ),
                        _ActionCard(
                          icon: Icons.how_to_reg_rounded,
                          title: '출/퇴근',
                          subtitle: 'Spread Sheets',
                          bg: a2,
                          fg: cs.onSecondary,
                          onTap: () => hr_att.AttendanceCalendar.showAsBottomSheet(context),
                        ),
                        _ActionCard(
                          icon: Icons.free_breakfast_rounded,
                          title: '휴게 관리',
                          subtitle: 'Spread Sheets',
                          bg: a3,
                          fg: cs.onTertiary,
                          onTap: () => hr_break.BreakCalendar.showAsBottomSheet(context),
                        ),
                        _ActionCard(
                          icon: Icons.edit_note_rounded,
                          title: '향후 로드맵',
                          subtitle: 'After Release',
                          bg: a7,
                          fg: cs.onTertiaryContainer,
                          // 컨테이너 계열은 원형 아이콘 배경이 연해질 수 있어 title/텍스트는 onSurface로 유지
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
                          icon: Icons.sticky_note_2_rounded,
                          title: '메모',
                          subtitle: '플로팅 버블 · 어디서나 기록',
                          bg: a5,
                          fg: cs.onPrimaryContainer,
                          onTap: () async => HeadMemo.openPanel(),
                        ),
                        _ActionCard(
                          icon: Icons.menu_book_rounded,
                          title: '튜토리얼',
                          subtitle: 'PDF 가이드 모음',
                          bg: a6,
                          fg: cs.onSecondaryContainer,
                          onTap: () async => HeadTutorials.open(context),
                        ),
                        _ActionCard(
                          icon: Icons.chat_bubble_rounded,
                          title: '채팅',
                          subtitle: '구역 채팅 (Sheets)',
                          bg: a8,
                          fg: cs.onSurfaceVariant,
                          onTap: () => chatBottomSheet(context),
                        ),
                        _ActionCard(
                          icon: Icons.campaign_rounded,
                          title: '공지',
                          subtitle: '휴대폰에서 공지 작성/수정',
                          bg: a4,
                          fg: cs.onError,
                          onTap: () async => NoticeEditorBottomSheet.showAsBottomSheet(context),
                        ),
                        _ActionCard(
                          icon: Icons.map_rounded,
                          title: '근무지 현황',
                          subtitle: 'Division별 지역 · 인원',
                          bg: a2,
                          fg: cs.onSecondary,
                          onTap: () => mgmt.Field.showAsBottomSheet(context),
                        ),
                        _ActionCard(
                          icon: Icons.stacked_line_chart_rounded,
                          title: '통계 비교',
                          subtitle: '입·출차/정산 추이',
                          bg: a3,
                          fg: cs.onTertiary,
                          onTap: () => mgmt_stats.Statistics.showAsBottomSheet(context),
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

                // ✅ 하단 ParkinWorkin_text: 브랜드 테마 tint 적용
                Center(
                  child: InkWell(
                    onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
                      AppRoutes.selector,
                          (route) => false,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 80,
                      child: Semantics(
                        label: '허브 선택 화면으로 돌아가기',
                        button: true,
                        child: Center(
                          child: _BrandTintedLogo(height: 48),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// ✅ “본사 허브입니다.” 배너도 ColorScheme 기반으로 전면 테마 반영
class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    // ✅ 브랜드(Primary) 기반 토큰
    final base = cs.primary;
    final container = cs.primaryContainer;
    final onContainer = cs.onPrimaryContainer;

    // ✅ 배너 테두리/바탕도 테마 기반
    final border = cs.outlineVariant.withOpacity(0.85);

    // ✅ 그라데이션: container 톤을 살리되, 배경과 자연스럽게 섞이도록 background와 블렌딩
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
            child: Icon(Icons.groups_rounded, color: base),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '본사 허브입니다.',
              style: text.bodyMedium?.copyWith(
                color: onContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),

          // 🔘 ON/OFF 토글 — 오른쪽 고정 (HeadHubActions 버블)
          ValueListenableBuilder<bool>(
            valueListenable: HeadHubActions.enabled,
            builder: (context, on, _) {
              final pillBg = on
                  ? base.withOpacity(0.12)
                  : cs.surfaceVariant;

              final pillBorder = on
                  ? base.withOpacity(0.30)
                  : cs.outlineVariant;

              final pillFg = on
                  ? base
                  : cs.onSurfaceVariant;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: pillBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: pillBorder),
                    ),
                    child: Text(
                      on ? 'Bubble ON' : 'Bubble OFF',
                      style: text.labelMedium?.copyWith(
                        color: pillFg,
                        fontWeight: FontWeight.w800,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch.adaptive(
                    value: on,
                    onChanged: (v) async {
                      HeadHubActions.setEnabled(v);
                      if (v) {
                        await HeadHubActions.mountIfNeeded();
                      }
                      HapticFeedback.selectionClick();

                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            v ? '본사 허브 버블이 켜졌습니다.' : '본사 허브 버블이 꺼졌습니다.',
                          ),
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

/// ✅ 카드 섹션도 “브랜드테마 반영”
/// - Card 자체는 cs.surface(또는 surfaceContainerLow) 기반
/// - bg(아이콘 원형색)를 카드 배경에 아주 옅게 overlay(= 브랜드 tint 느낌)
class _ActionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color bg; // 아이콘 원형 배경(= accent)
  final Color fg; // 아이콘 색
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
    final cs = Theme.of(context).colorScheme;

    final cardSurface = cs.surface;
    final border = cs.outlineVariant.withOpacity(0.85);

    // ✅ 카드 전체 tint: bg를 surface에 아주 옅게 섞어서 “브랜드톤”이 전반에 배도록
    final tint = Color.alphaBlend(bg.withOpacity(0.10), cardSurface);

    return Card(
      elevation: 0,
      color: cardSurface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: border, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [cardSurface, tint],
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
                      color: bg,
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
                    child: Icon(icon, color: fg, size: 26),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  textAlign: TextAlign.center,
                  style: TextStyle(
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
      ),
    );
  }
}
