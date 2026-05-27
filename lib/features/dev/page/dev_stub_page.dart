import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/di/routes.dart';
import 'sheets/dev_quick_actions.dart';
import 'sheets/local_prefs_bottom_sheet.dart';
import 'sheets/sqlite_explorer_bottom_sheet.dart';

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

@immutable
class _DevTokens {
  const _DevTokens({
    required this.pageBackground,
    required this.appBarBackground,
    required this.appBarForeground,
    required this.divider,
    required this.cardSurface,
    required this.cardBorder,
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

    final headerTint = Color.alphaBlend(
      cs.primary.withOpacity(0.16),
      cs.surfaceContainerLow,
    );
    final badgeBg = cs.primary;
    final badgeFg = cs.onPrimary;

    return _DevTokens(
      pageBackground: cs.background,
      appBarBackground: cs.background,
      appBarForeground: cs.onSurface,
      divider: cs.outlineVariant,
      cardSurface: cs.surface,
      cardBorder: cs.outlineVariant.withOpacity(0.85),
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


class DevStubPage extends StatefulWidget {
  const DevStubPage({super.key});

  @override
  State<DevStubPage> createState() => _DevStubPageState();
}

class _DevStubPageState extends State<DevStubPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DevQuickActions.enableDeveloperMode();
    });
  }

  @override
  Widget build(BuildContext context) {
    final tokens = _DevTokens.of(context);
    final text = Theme.of(context).textTheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final media = MediaQuery.of(context);
    final bool isShort = media.size.height < 640;
    final bool keyboardOpen = media.viewInsets.bottom > 0;
    final double footerHeight = (isShort || keyboardOpen) ? 72 : 120;

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
            statusBarIconBrightness:
                isDark ? Brightness.light : Brightness.dark,
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
                      final textScale = MediaQuery.of(context)
                          .textScaleFactor
                          .clamp(1.0, 1.3);

                      final tileWidth =
                          (width - spacing * (crossAxisCount - 1)) /
                              crossAxisCount;
                      const baseTileHeight = 150.0;
                      final tileHeight = baseTileHeight * textScale;
                      final childAspectRatio = tileWidth / tileHeight;

                      final cs = Theme.of(context).colorScheme;

                      final cards = <Widget>[
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
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(16),
                                ),
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
        bottomNavigationBar: AnimatedOpacity(
          opacity: keyboardOpen ? 0.0 : 1.0,
          duration: const Duration(milliseconds: 160),
          child: SafeArea(
            top: false,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: tokens.pageBackground,
                border:
                    Border(top: BorderSide(color: tokens.divider, width: 1)),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.of(context).pushNamedAndRemoveUntil(
                    AppRoutes.selector,
                    (route) => false,
                  ),
                  child: SizedBox(
                    height: footerHeight,
                    child: Center(
                      child: _BrandTintedLogo(height: footerHeight),
                    ),
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
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: tokens.headerBadgeBg,
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child:
                Icon(Icons.developer_mode_rounded, color: tokens.headerBadgeFg),
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
          ValueListenableBuilder<bool>(
            valueListenable: DevQuickActions.enabled,
            builder: (context, on, _) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color:
                          on ? tokens.bubbleChipBgOn : tokens.bubbleChipBgOff,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: on
                            ? tokens.bubbleChipBorderOn
                            : tokens.bubbleChipBorderOff,
                      ),
                    ),
                    child: Text(
                      on ? '개발자 모드 ON' : '개발자 모드 OFF',
                      style: text.labelMedium?.copyWith(
                        color: on
                            ? tokens.bubbleChipTextOn
                            : tokens.bubbleChipTextOff,
                        fontWeight: FontWeight.w700,
                        letterSpacing: .2,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Switch.adaptive(
                    value: on,
                    onChanged: (v) async {
                      if (v) {
                        await DevQuickActions.enableDeveloperMode();
                      } else {
                        await DevQuickActions.disableDeveloperMode();
                      }
                      HapticFeedback.selectionClick();
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            v
                                ? '개발자 모드와 개발 버블이 켜졌습니다.'
                                : '개발자 모드와 개발 버블이 꺼졌습니다.',
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

  final Color? tintColor;

  final VoidCallback? onTap;

  const _ActionCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.bg,
    required this.fg,
    this.tintColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
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
    );
  }
}
