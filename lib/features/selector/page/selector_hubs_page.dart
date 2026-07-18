import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/di/routes.dart';
import '../../../app/theme/theme_prefs_controller.dart';
import '../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../application/dev_auth.dart';
import '../sheets/update_bottom_sheet.dart';
import '../widgets/cards.dart';
import '../widgets/cards_pager.dart';
import '../widgets/header.dart';
import '../widgets/update_alert_bar.dart';

const String kDevModeEnabledKey = 'dev_mode_enabled_v1';

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
  const _BrandTintedLogo({required this.height});

  static const String _assetPath = 'assets/images/ParkinWorkin_text.png';
  final double height;

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final tint = _resolveLogoTint(
      background: tokens.canvas,
      preferred: tokens.accent,
      fallback: tokens.textPrimary,
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
    final tokens = PromptUiTheme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: tokens.transparent,
      barrierColor: tokens.scrim,
      builder: (sheetContext) {
        return const PromptUiScope(
          child: FractionallySizedBox(
            heightFactor: 1,
            child: UpdateBottomSheet(),
          ),
        );
      },
    );
  }

  String? _normalizeMode(String? raw) {
    if (raw == null) return null;
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return null;

    switch (value) {
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
        return value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemePrefsController>(
      builder: (context, _, __) {
        return PromptUiScope(
          child: Builder(
            builder: (context) {
              final tokens = PromptUiTheme.of(context);
              final isDark = tokens.isDark;
              final mode = _normalizeMode(_savedMode);

              final personalEnabled = mode == null || mode == 'personal';
              final tabletEnabled = mode == null || mode == 'tablet';
              final singleEnabled = mode == null || mode == 'single';
              final doubleEnabled = mode == null || mode == 'double';
              final tripleEnabled = mode == null || mode == 'triple';
              final minorEnabled = mode == null || mode == 'minor';
              final unknownMode = mode != null &&
                  !<String>{
                    'personal',
                    'tablet',
                    'single',
                    'double',
                    'triple',
                    'minor',
                  }.contains(mode);

              final pages = <CardsPagerPage>[
                CardsPagerPage.fullSpan(child: const ExperienceCard()),
                CardsPagerPage.pair(
                  primary: PersonalLoginCard(
                    enabled: unknownMode || personalEnabled,
                  ),
                  secondary: TabletCard(
                    enabled: unknownMode || tabletEnabled,
                  ),
                ),
                CardsPagerPage.pair(
                  primary: SingleLoginCard(
                    enabled: unknownMode || singleEnabled,
                  ),
                  secondary: DoubleLoginCard(
                    enabled: unknownMode || doubleEnabled,
                  ),
                ),
                CardsPagerPage.pair(
                  primary: TripleLoginCard(
                    enabled: unknownMode || tripleEnabled,
                  ),
                  secondary: MinorLoginCard(
                    enabled: unknownMode || minorEnabled,
                  ),
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
              final isShort = media.size.height < 640;
              final keyboardOpen = media.viewInsets.bottom > 0;
              final footerHeight = isShort || keyboardOpen ? 72.0 : 120.0;
              final reduceMotion = media.disableAnimations;

              return PopScope(
                canPop: false,
                onPopInvoked: (didPop) {},
                child: Scaffold(
                  backgroundColor: tokens.canvas,
                  appBar: AppBar(
                    backgroundColor: tokens.surface,
                    foregroundColor: tokens.textPrimary,
                    surfaceTintColor: tokens.transparent,
                    elevation: 0,
                    scrolledUnderElevation: 0,
                    centerTitle: true,
                    systemOverlayStyle: SystemUiOverlayStyle(
                      statusBarColor: tokens.transparent,
                      statusBarIconBrightness:
                          isDark ? Brightness.light : Brightness.dark,
                      statusBarBrightness:
                          isDark ? Brightness.dark : Brightness.light,
                      systemNavigationBarColor: tokens.surface,
                      systemNavigationBarIconBrightness:
                          isDark ? Brightness.light : Brightness.dark,
                    ),
                    title: Text(
                      'ParkinWorkin Hubs',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.2,
                          ),
                    ),
                    iconTheme: IconThemeData(color: tokens.iconPrimary),
                    actionsIconTheme:
                        IconThemeData(color: tokens.iconPrimary),
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(1),
                      child: Container(
                        height: 1,
                        color: tokens.borderSubtle,
                      ),
                    ),
                  ),
                  body: SafeArea(
                    bottom: false,
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 880),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const PromptAnimatedReveal(
                                child: Header(),
                              ),
                              const SizedBox(height: 24),
                              PromptAnimatedReveal(
                                delay: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 50),
                                child: CardsPager(pages: pages),
                              ),
                              const SizedBox(height: 16),
                              PromptAnimatedReveal(
                                delay: reduceMotion
                                    ? Duration.zero
                                    : const Duration(milliseconds: 90),
                                child: UpdateAlertBar(
                                  onTapUpdate: () => _handleUpdateTap(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  bottomNavigationBar: IgnorePointer(
                    ignoring: keyboardOpen,
                    child: AnimatedSlide(
                      offset: keyboardOpen ? const Offset(0, 0.25) : Offset.zero,
                      duration:
                          reduceMotion ? Duration.zero : PromptUiMotion.component,
                      curve: PromptUiMotion.enter,
                      child: AnimatedOpacity(
                        opacity: keyboardOpen ? 0 : 1,
                        duration: reduceMotion
                            ? Duration.zero
                            : PromptUiMotion.selection,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: tokens.surface,
                            border: Border(
                              top: BorderSide(color: tokens.borderSubtle),
                            ),
                          ),
                          child: SafeArea(
                            top: false,
                            minimum: const EdgeInsets.only(bottom: 8),
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
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
