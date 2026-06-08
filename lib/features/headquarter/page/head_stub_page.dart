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
    final bg = Color.alphaBlend(cs.surfaceVariant.withOpacity(.20), cs.background);

    final tint = _resolveLogoTint(
      background: bg,
      preferred: cs.primary,
      fallback: cs.onSurface,
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

  List<_HeadHubAction> _actions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return <_HeadHubAction>[
      _HeadHubAction(
        icon: Icons.calendar_month_rounded,
        title: '본사 달력',
        color: cs.primary,
        foreground: cs.onPrimary,
        onTap: () => CompanyCalendarPage.showAsBottomSheet(context),
      ),
      _HeadHubAction(
        icon: Icons.how_to_reg_rounded,
        title: '출/퇴근',
        color: cs.secondary,
        foreground: cs.onSecondary,
        onTap: () => hr_att.AttendanceCalendar.showAsBottomSheet(context),
      ),
      _HeadHubAction(
        icon: Icons.free_breakfast_rounded,
        title: '휴게 관리',
        color: cs.tertiary,
        foreground: cs.onTertiary,
        onTap: () => hr_break.BreakCalendar.showAsBottomSheet(context),
      ),
      _HeadHubAction(
        icon: Icons.edit_note_rounded,
        title: '로드맵',
        color: cs.tertiaryContainer,
        foreground: cs.onTertiaryContainer,
        onTap: () {
          showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => const RoadmapBottomSheet(),
          );
        },
      ),
      _HeadHubAction(
        icon: Icons.sticky_note_2_rounded,
        title: '메모',
        color: cs.primaryContainer,
        foreground: cs.onPrimaryContainer,
        onTap: () async => HeadMemo.openPanel(),
      ),
      _HeadHubAction(
        icon: Icons.menu_book_rounded,
        title: '튜토리얼',
        color: cs.secondaryContainer,
        foreground: cs.onSecondaryContainer,
        onTap: () async => HeadTutorials.open(context),
      ),
      _HeadHubAction(
        icon: Icons.contact_support_rounded,
        title: '문의하기',
        color: cs.errorContainer,
        foreground: cs.onErrorContainer,
        onTap: () async => HeadHubActions.openContactForm(context),
      ),
      _HeadHubAction(
        icon: Icons.map_rounded,
        title: '근무지 현황',
        color: cs.secondary,
        foreground: cs.onSecondary,
        onTap: () => mgmt.Field.showAsBottomSheet(context),
      ),
      _HeadHubAction(
        icon: Icons.stacked_line_chart_rounded,
        title: '통계 비교',
        color: cs.tertiary,
        foreground: cs.onTertiary,
        onTap: () => mgmt_stats.Statistics.showAsBottomSheet(context),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final bool isShort = media.size.height < 640;
    final bool keyboardOpen = media.viewInsets.bottom > 0;
    final double footerHeight = (isShort || keyboardOpen) ? 64 : 104;
    final actions = _actions(context);
    final pageBackground = Color.alphaBlend(cs.surfaceVariant.withOpacity(.20), cs.background);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: Scaffold(
        backgroundColor: pageBackground,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _HeadOpsHeader(actionCount: actions.length),
                const SizedBox(height: 12),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth;
                      final crossAxisCount = width >= 1100
                          ? 4
                          : width >= 760
                              ? 3
                              : 2;
                      const spacing = 10.0;
                      final tileWidth = (width - spacing * (crossAxisCount - 1)) / crossAxisCount;
                      const tileHeight = 124.0;
                      final childAspectRatio = tileWidth / tileHeight;

                      return GridView.builder(
                        padding: EdgeInsets.zero,
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: crossAxisCount,
                          mainAxisSpacing: spacing,
                          crossAxisSpacing: spacing,
                          childAspectRatio: childAspectRatio,
                        ),
                        itemCount: actions.length,
                        itemBuilder: (context, index) => _HeadActionCard(
                          action: actions[index],
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 10),
                Center(
                  child: SizedBox(
                    height: footerHeight,
                    child: Center(
                      child: _BrandTintedLogo(height: footerHeight),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _HeadOpsHeader extends StatelessWidget {
  const _HeadOpsHeader({required this.actionCount});

  final int actionCount;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 13),
      decoration: BoxDecoration(
        color: cs.inverseSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: cs.outlineVariant.withOpacity(.42)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.08),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: '뒤로가기',
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              const SizedBox(width: 8),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: cs.primary,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.apartment_rounded, color: cs.onPrimary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  '본사 허브',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (textTheme.titleLarge ?? const TextStyle(fontSize: 22)).copyWith(
                    color: cs.onInverseSurface,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.3,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _BubbleController(),
            ],
          ),
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _HeadMetric(label: '기능', value: '$actionCount', icon: Icons.grid_view_rounded, color: cs.primary),
                const SizedBox(width: 8),
                ValueListenableBuilder<bool>(
                  valueListenable: HeadHubActions.enabled,
                  builder: (context, on, _) {
                    return _HeadMetric(
                      label: '버블',
                      value: on ? 'ON' : 'OFF',
                      icon: Icons.bubble_chart_rounded,
                      color: on ? cs.primary : cs.onInverseSurface,
                    );
                  },
                ),
                const SizedBox(width: 8),
                _HeadMetric(label: '화면', value: '허브', icon: Icons.hub_rounded, color: cs.secondary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BubbleController extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<bool>(
      valueListenable: HeadHubActions.enabled,
      builder: (context, on, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
              decoration: BoxDecoration(
                color: on ? cs.primary : cs.onInverseSurface.withOpacity(.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: on ? cs.primary : cs.onInverseSurface.withOpacity(.14),
                ),
              ),
              child: Text(
                on ? 'ON' : 'OFF',
                style: TextStyle(
                  color: on ? cs.onPrimary : cs.onInverseSurface,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
            const SizedBox(width: 6),
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
                    content: Text(v ? '본사 허브 버블 ON' : '본사 허브 버블 OFF'),
                    behavior: SnackBarBehavior.floating,
                    duration: const Duration(milliseconds: 900),
                  ),
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _HeadMetric extends StatelessWidget {
  const _HeadMetric({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: 108,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: cs.onInverseSurface.withOpacity(.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.onInverseSurface.withOpacity(.12)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onInverseSurface.withOpacity(.62),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onInverseSurface,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -.1,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeadHubAction {
  const _HeadHubAction({
    required this.icon,
    required this.title,
    required this.color,
    required this.foreground,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final Color color;
  final Color foreground;
  final VoidCallback? onTap;
}

class _HeadActionCard extends StatelessWidget {
  const _HeadActionCard({required this.action});

  final _HeadHubAction action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: cs.outlineVariant.withOpacity(.70)),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withOpacity(.04),
                blurRadius: 12,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: action.color,
                        borderRadius: BorderRadius.circular(13),
                      ),
                      child: Icon(action.icon, color: action.foreground, size: 21),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant.withOpacity(.72)),
                  ],
                ),
                const Spacer(),
                Text(
                  action.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                    letterSpacing: -.15,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
