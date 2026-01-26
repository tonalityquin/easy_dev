import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'routes.dart';

// snackbar helper
import 'utils/snackbar_helper.dart';

// 패키지 분리된 섹션들
import 'screens/hubs_mode/dev_package/debug_package/debug_bottom_sheet.dart';
import 'selector_hubs_package/dev_auth.dart';
import 'selector_hubs_package/cards.dart';
import 'selector_hubs_package/cards_pager.dart';
import 'selector_hubs_package/header.dart';
import 'selector_hubs_package/update_alert_bar.dart';
import 'selector_hubs_package/dev_login_bottom_sheet.dart';
import 'selector_hubs_package/update_bottom_sheet.dart';
import 'selector_hubs_package/brand_theme.dart';

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
      pageBackground: cs.surface,
      appBarBackground: cs.surface,
      appBarForeground: cs.onSurface,
      divider: cs.outlineVariant,
      accent: cs.primary,
      onAccent: cs.onPrimary,
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

  String _brandPresetId = 'system';
  String _themeModeId = 'system'; // system | light | dark

  @override
  void initState() {
    super.initState();
    _restorePrefs();
    _restoreBrandPreset();
    _restoreThemeMode();
  }

  Future<void> _restoreBrandPreset() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(kBrandPresetKey) ?? 'system').trim();
      if (!mounted) return;
      setState(() => _brandPresetId = saved.isEmpty ? 'system' : saved);
    } catch (_) {}
  }

  Future<void> _restoreThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = (prefs.getString(kThemeModeKey) ?? 'system').trim();
      if (!mounted) return;
      setState(() => _themeModeId = saved.isEmpty ? 'system' : saved);
    } catch (_) {}
  }

  Future<void> _restorePrefs() async {
    final pref = await DevAuth.restorePrefs();
    if (!mounted) return;

    final wasService = (pref.savedMode ?? '').trim().toLowerCase() == 'service';

    setState(() {
      _savedMode = pref.savedMode;
      _devAuthorized = pref.devAuthorized;
    });

    if (wasService) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showSelectedSnackbar(context, '서비스 로그인은 종료되었습니다. 다른 모드를 선택해 주세요.');
      });
    }
  }

  Future<void> _setDevAuthorized(bool value) async {
    await DevAuth.setDevAuthorized(value);
    if (mounted) setState(() => _devAuthorized = value);
  }

  Future<void> _resetDevAuth() async {
    await DevAuth.resetDevAuth();
    if (mounted) setState(() => _devAuthorized = false);
  }

  Future<void> _handlePelicanTap(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 1,
        child: DevLoginBottomSheet(
          initialPresetId: _brandPresetId,
          initialThemeModeId: _themeModeId,
          onPresetChanged: (id) {
            if (!mounted) return;
            setState(() => _brandPresetId = id);
          },
          onThemeModeChanged: (id) {
            if (!mounted) return;
            setState(() => _themeModeId = id);
          },
          onSuccess: (id, pw) async {
            await _setDevAuthorized(true);
            if (mounted) {
              Navigator.of(ctx).pop();
              showSuccessSnackbar(context, '개발자 인증 완료. 이제 개발 메뉴를 사용할 수 있습니다.');
            }
          },
          onReset: () async {
            await _resetDevAuth();
            if (mounted) {
              Navigator.of(ctx).pop();
              showSelectedSnackbar(context, '개발자 인증이 초기화되었습니다.');
            }
          },
        ),
      ),
    );
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

  Future<void> _handleLogsTap(BuildContext context) async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const DebugBottomSheet(),
    );
  }

  String? _normalizeMode(String? raw) {
    if (raw == null) return null;
    final v = raw.trim().toLowerCase();
    if (v.isEmpty) return null;

    switch (v) {
      case 'service':
        return null;
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

  ThemeData _buildThemed(ThemeData baseTheme, Brightness brightness, String presetId) {
    final base = withBrightness(baseTheme, brightness);

    final effectivePreset = presetById(presetId);
    final accent = (effectivePreset.id == 'system' || effectivePreset.accent == null)
        ? base.colorScheme.primary
        : effectivePreset.accent!;

    final scheme = buildConceptScheme(brightness: brightness, accent: accent);

    return base.copyWith(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
      ),
      cardTheme: base.cardTheme.copyWith(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 테마 모드 → brightness 결정
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = resolveBrightness(_themeModeId, systemBrightness);

    // ✅ 컨셉 테마 적용(표면 중립 + 포인트만 accent) + 다크모드 반영
    final baseTheme = Theme.of(context);
    final themed = _buildThemed(baseTheme, brightness, _brandPresetId);

    return Theme(
      data: themed,
      child: Builder(
        builder: (context) {
          final tokens = _SelectorHubsTokens.of(context);
          final isDark = Theme.of(context).brightness == Brightness.dark;

          final mode = _normalizeMode(_savedMode);

          final bool singleEnabled;
          final bool tabletEnabled;
          final bool doubleEnabled;
          final bool tripleEnabled;
          final bool minorEnabled;

          if (mode == null) {
            singleEnabled = true;
            tabletEnabled = true;
            doubleEnabled = true;
            tripleEnabled = true;
            minorEnabled = true;
          } else if (mode == 'single') {
            singleEnabled = true;
            tabletEnabled = false;
            doubleEnabled = false;
            tripleEnabled = false;
            minorEnabled = false;
          } else if (mode == 'tablet') {
            singleEnabled = false;
            tabletEnabled = true;
            doubleEnabled = false;
            tripleEnabled = false;
            minorEnabled = false;
          } else if (mode == 'double') {
            singleEnabled = false;
            tabletEnabled = false;
            doubleEnabled = true;
            tripleEnabled = false;
            minorEnabled = false;
          } else if (mode == 'triple') {
            singleEnabled = false;
            tabletEnabled = false;
            doubleEnabled = false;
            tripleEnabled = true;
            minorEnabled = false;
          } else if (mode == 'minor') {
            singleEnabled = false;
            tabletEnabled = false;
            doubleEnabled = false;
            tripleEnabled = false;
            minorEnabled = true;
          } else {
            singleEnabled = true;
            tabletEnabled = true;
            doubleEnabled = true;
            tripleEnabled = true;
            minorEnabled = true;
          }

          final List<List<Widget>> pages = [
            [DoubleLoginCard(enabled: doubleEnabled), TripleLoginCard(enabled: tripleEnabled)],
            [MinorLoginCard(enabled: minorEnabled), SingleLoginCard(enabled: singleEnabled)],
            [TabletCard(enabled: tabletEnabled), const HeadquarterCard()],
            [const CommunityCard(), const FaqCard()],
            if (_devAuthorized)
              [
                const ParkingCard(),
                DevCard(onTap: () => Navigator.of(context).pushReplacementNamed(AppRoutes.devStub)),
              ],
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
                  statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
                  statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
                ),
                title: Text(
                  'Pelican Hubs',
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
                            onTapLogs: () => _handleLogsTap(context),
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
                        button: true,
                        label: '개발자 로그인',
                        hint: '개발자 전용 로그인 시트를 엽니다',
                        child: Tooltip(
                          message: '개발자 로그인',
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () => _handlePelicanTap(context),
                            child: Image.asset(
                              'assets/images/pelican.png',
                              fit: BoxFit.contain,
                              height: footerHeight,
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
  }
}
