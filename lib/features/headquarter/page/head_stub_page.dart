import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../application/fab/hub_quick_actions.dart';
import '../widgets/hr/attendance_calendar.dart' as hr_att;
import '../widgets/hr/break_calendar.dart' as hr_break;
import '../widgets/mgmt/field.dart' as mgmt;
import '../widgets/mgmt/statistics.dart' as mgmt_stats;
import 'sheets/company_calendar_page.dart';
import 'sheets/head_memo.dart';
import 'sheets/head_tutorials.dart';
import 'sheets/roadmap_bottom_sheet.dart';

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

    final media = MediaQuery.of(context);
    final bool isShort = media.size.height < 640;
    final bool keyboardOpen = media.viewInsets.bottom > 0;
    final double footerHeight = (isShort || keyboardOpen) ? 72 : 120;

    return Scaffold(
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

                    final tileWidth = (width - spacing * (crossAxisCount - 1)) /
                        crossAxisCount;
                    const baseTileHeight = 150.0;
                    final tileHeight = baseTileHeight * textScale;
                    final childAspectRatio = tileWidth / tileHeight;

                    final a1 = cs.primary;
                    final a2 = cs.secondary;
                    final a3 = cs.tertiary;
                    final a5 = cs.primaryContainer;
                    final a6 = cs.secondaryContainer;
                    final a7 = cs.tertiaryContainer;
                    final a8 = cs.errorContainer;

                    final cards = <Widget>[
                      _ActionCard(
                        icon: Icons.calendar_month_rounded,
                        title: '본사 달력',
                        subtitle: '본사 일정 공유',
                        bg: a1,
                        fg: cs.onPrimary,
                        onTap: () =>
                            CompanyCalendarPage.showAsBottomSheet(context),
                      ),
                      _ActionCard(
                        icon: Icons.how_to_reg_rounded,
                        title: '출/퇴근',
                        subtitle: '직원 출퇴근 관리',
                        bg: a2,
                        fg: cs.onSecondary,
                        onTap: () =>
                            hr_att.AttendanceCalendar.showAsBottomSheet(
                                context),
                      ),
                      _ActionCard(
                        icon: Icons.free_breakfast_rounded,
                        title: '휴게 관리',
                        subtitle: '직원 휴게 관리',
                        bg: a3,
                        fg: cs.onTertiary,
                        onTap: () =>
                            hr_break.BreakCalendar.showAsBottomSheet(context),
                      ),
                      _ActionCard(
                        icon: Icons.edit_note_rounded,
                        title: '향후 로드맵',
                        subtitle: 'After Release',
                        bg: a7,
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
                        icon: Icons.contact_support_rounded,
                        title: '문의하기',
                        subtitle: '이슈 · 오류 · 궁금증',
                        bg: a8,
                        fg: cs.onErrorContainer,
                        onTap: () async => HeadHubActions.openContactForm(context),
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
                        onTap: () =>
                            mgmt_stats.Statistics.showAsBottomSheet(context),
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
                  onTap: null,
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    height: footerHeight,
                    child: Semantics(
                      label: '허브 선택 화면으로 돌아가기',
                      child: Center(
                        child: _BrandTintedLogo(height: footerHeight),
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
    );
  }
}

class _HeaderBanner extends StatelessWidget {
  const _HeaderBanner();

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;

    final base = cs.primary;
    final container = cs.primaryContainer;
    final onContainer = cs.onPrimaryContainer;

    final border = cs.outlineVariant.withOpacity(0.85);

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
          ValueListenableBuilder<bool>(
            valueListenable: HeadHubActions.enabled,
            builder: (context, on, _) {
              final pillBg = on ? base.withOpacity(0.12) : cs.surfaceVariant;

              final pillBorder =
                  on ? base.withOpacity(0.30) : cs.outlineVariant;

              final pillFg = on ? base : cs.onSurfaceVariant;

              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
    final cs = Theme.of(context).colorScheme;

    final cardSurface = cs.surface;
    final border = cs.outlineVariant.withOpacity(0.85);

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
