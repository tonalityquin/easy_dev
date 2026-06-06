import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/di/routes.dart';
import '../../../app/theme/theme_prefs_controller.dart';
import '../application/dev_auth.dart';
import '../sheets/update_bottom_sheet.dart';
import '../widgets/cards.dart';
import '../widgets/cards_pager.dart';
import '../widgets/header.dart';
import '../widgets/update_alert_bar.dart';

const String kDevModeEnabledKey = 'dev_mode_enabled_v1';

@immutable
class _SelectorHubsTokens {
  const _SelectorHubsTokens({
    required this.pageBackground,
    required this.appBarBackground,
    required this.appBarForeground,
    required this.divider,
    required this.accent,
    required this.onAccent,
  });

  final Color pageBackground;
  final Color appBarBackground;
  final Color appBarForeground;
  final Color divider;
  final Color accent;
  final Color onAccent;

  factory _SelectorHubsTokens.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return _SelectorHubsTokens(
      pageBackground: cs.background,
      appBarBackground: cs.background,
      appBarForeground: cs.onSurface,
      divider: cs.outlineVariant,
      accent: cs.primary,
      onAccent: cs.onPrimary,
    );
  }
}

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
  if (_contrastRatio(preferred, background) >= minContrast) {
    return preferred;
  }
  return fallback;
}

class _BrandTintedLogo extends StatelessWidget {
  const _BrandTintedLogo({
    required this.height,
  });

  static const String _assetPath = 'assets/images/ParkinWorkin_text.png';
  final double height;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = cs.background;

    final tint = _resolveLogoTint(
      background: bg,
      preferred: cs.primary,
      fallback: cs.onBackground,
      minContrast: 3.0,
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

class SelectorHubsPage extends StatefulWidget {
  const SelectorHubsPage({super.key});

  @override
  State<SelectorHubsPage> createState() => _SelectorHubsPageState();
}

class _SelectorHubsPageState extends State<SelectorHubsPage> {
  String? _savedMode;
  bool _devAuthorized = false;

  @override
  void initState() {
    super.initState();
    _restorePrefs();
  }

  Future<void> _restorePrefs() async {
    final pref = await DevAuth.restorePrefs();
    final prefs = await SharedPreferences.getInstance();
    final devModeEnabled = prefs.getBool(kDevModeEnabledKey) ?? false;

    if (!mounted) return;

    setState(() {
      _savedMode = pref.savedMode;
      _devAuthorized = pref.devAuthorized || devModeEnabled;
    });
  }

  Future<void> _handleUpdateTap(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const FractionallySizedBox(
        heightFactor: 1,
        child: UpdateBottomSheet(),
      ),
    );
  }

  String? _normalizeMode(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;

    switch (v) {
      case 'service':
        return null;
      case 'personal':
      case 'mobile':
      case 'direct':
        return 'personal';
      case 'tablet':
        return 'tablet';
      case 'single':
      case 'simple':
        return 'single';
      case 'double':
      case 'lite':
      case 'light':
        return 'double';
      case 'triple':
      case 'normal':
        return 'triple';
      default:
        return v;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemePrefsController>(
      builder: (context, themeCtrl, _) {
        final tokens = _SelectorHubsTokens.of(context);
        final isDark = Theme.of(context).brightness == Brightness.dark;

        final mode = _normalizeMode(_savedMode);

        final bool personalEnabled;
        final bool tabletEnabled;
        final bool singleEnabled;
        final bool doubleEnabled;
        final bool tripleEnabled;
        final bool minorEnabled;

        if (mode == null) {
          personalEnabled = true;
          tabletEnabled = true;
          singleEnabled = true;
          doubleEnabled = true;
          tripleEnabled = true;
          minorEnabled = true;
        } else if (mode == 'personal') {
          personalEnabled = true;
          tabletEnabled = false;
          singleEnabled = false;
          doubleEnabled = false;
          tripleEnabled = false;
          minorEnabled = false;
        } else if (mode == 'tablet') {
          personalEnabled = false;
          tabletEnabled = true;
          singleEnabled = false;
          doubleEnabled = false;
          tripleEnabled = false;
          minorEnabled = false;
        } else if (mode == 'single') {
          personalEnabled = false;
          tabletEnabled = false;
          singleEnabled = true;
          doubleEnabled = false;
          tripleEnabled = false;
          minorEnabled = false;
        } else if (mode == 'double') {
          personalEnabled = false;
          tabletEnabled = false;
          singleEnabled = false;
          doubleEnabled = true;
          tripleEnabled = false;
          minorEnabled = false;
        } else if (mode == 'triple') {
          personalEnabled = false;
          tabletEnabled = false;
          singleEnabled = false;
          doubleEnabled = false;
          tripleEnabled = true;
          minorEnabled = false;
        } else if (mode == 'minor') {
          personalEnabled = false;
          tabletEnabled = false;
          singleEnabled = false;
          doubleEnabled = false;
          tripleEnabled = false;
          minorEnabled = true;
        } else {
          personalEnabled = true;
          tabletEnabled = true;
          singleEnabled = true;
          doubleEnabled = true;
          tripleEnabled = true;
          minorEnabled = true;
        }

        final List<CardsPagerPage> pages = [
          CardsPagerPage.fullSpan(
            child: const ExperienceCard(),
          ),
          CardsPagerPage.pair(
            primary: PersonalLoginCard(enabled: personalEnabled),
            secondary: TabletCard(enabled: tabletEnabled),
          ),
          CardsPagerPage.pair(
            primary: SingleLoginCard(enabled: singleEnabled),
            secondary: DoubleLoginCard(enabled: doubleEnabled),
          ),
          CardsPagerPage.pair(
            primary: TripleLoginCard(enabled: tripleEnabled),
            secondary: MinorLoginCard(enabled: minorEnabled),
          ),
          if (_devAuthorized)
            CardsPagerPage.pair(
              primary: const ParkingCard(),
              secondary: DevCard(
                onTap: () => Navigator.of(context)
                    .pushReplacementNamed(AppRoutes.devStub),
              ),
            ),
        ];

        final media = MediaQuery.of(context);
        final bool isShort = media.size.height < 640;
        final bool keyboardOpen = media.viewInsets.bottom > 0;
        final double footerHeight = (isShort || keyboardOpen) ? 72 : 120;

        return PopScope(
          canPop: false,
          onPopInvoked: (didPop) {},
          child: Scaffold(
            backgroundColor: tokens.pageBackground,
            appBar: AppBar(
              backgroundColor: tokens.appBarBackground,
              foregroundColor: tokens.appBarForeground,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              scrolledUnderElevation: 0,
              centerTitle: true,
              systemOverlayStyle: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness:
                    isDark ? Brightness.light : Brightness.dark,
                statusBarBrightness:
                    isDark ? Brightness.dark : Brightness.light,
              ),
              title: Text(
                'ParkinWorkin Hubs',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 880),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Header(),
                        const SizedBox(height: 24),
                        CardsPager(pages: pages),
                        const SizedBox(height: 16),
                        UpdateAlertBar(
                          onTapUpdate: () => _handleUpdateTap(context),
                          background: tokens.accent,
                          foreground: tokens.onAccent,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            bottomNavigationBar: AnimatedOpacity(
              opacity: keyboardOpen ? 0.0 : 1.0,
              duration: const Duration(milliseconds: 160),
              child: SafeArea(
                top: false,
                child: SizedBox(
                  height: footerHeight,
                  child: Center(
                    child: Semantics(
                      image: true,
                      label: 'ParkinWorkin 로고',
                      child: _BrandTintedLogo(height: footerHeight),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
