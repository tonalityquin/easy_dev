import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/theme/brand_theme.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../account/applications/user_state.dart';
import '../../controllers/double/double_login_controller.dart';
import '../../controllers/minor/minor_login_controller.dart';
import '../../controllers/personal/personal_login_controller.dart';
import '../../controllers/service/service_login_controller.dart';
import '../../controllers/single/single_login_controller.dart';
import '../../controllers/tablet/tablet_login_controller.dart';
import '../../controllers/triple/triple_login_controller.dart';
import '../double/double_login_form.dart';
import '../minor/minor_login_form.dart';
import '../personal/personal_login_form.dart';
import '../single/single_login_form.dart';
import '../tablet/tablet_login_form.dart';
import '../triple/triple_login_form.dart';
import 'service_login_form.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.mode = 'service'});

  final String mode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  late final String _mode;

  ServiceLoginController? _serviceLoginController;
  SingleLoginController? _singleLoginController;
  PersonalLoginController? _personalController;
  TabletLoginController? _tabletController;
  DoubleLoginController? _doubleLoginController;
  TripleLoginController? _tripleLoginController;
  MinorLoginController? _minorLoginController;

  String? _redirectAfterLogin;
  String? _requiredMode;
  bool _didInitAuto = false;
  String _brandPresetId = 'system';
  String _themeModeId = 'system';
  bool _prefsLoaded = false;

  static String _normalizeMode(String? raw) {
    final value = (raw ?? '').trim().toLowerCase();
    switch (value) {
      case 'service':
        return 'service';
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
      case 'minor':
        return 'minor';
      default:
        return 'service';
    }
  }

  static String? _normalizeModeNullable(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    return _normalizeMode(value);
  }

  bool get _usesPromptUi => _mode != 'service';

  void _createControllerForMode() {
    switch (_mode) {
      case 'personal':
        _personalController = PersonalLoginController(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _personalController?.initState();
        });
        return;
      case 'tablet':
        _tabletController = TabletLoginController(context);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _tabletController?.initState();
        });
        return;
      case 'single':
        _singleLoginController = SingleLoginController(
          context,
          onLoginSucceeded: _navigateAfterLogin,
        );
        return;
      case 'double':
        _doubleLoginController = DoubleLoginController(
          context,
          onLoginSucceeded: _navigateAfterLogin,
        );
        return;
      case 'triple':
        _tripleLoginController = TripleLoginController(
          context,
          onLoginSucceeded: _navigateAfterLogin,
        );
        return;
      case 'minor':
        _minorLoginController = MinorLoginController(
          context,
          onLoginSucceeded: _navigateAfterLogin,
        );
        return;
      case 'service':
      default:
        _serviceLoginController = ServiceLoginController(
          context,
          onLoginSucceeded: _navigateAfterLogin,
        );
        return;
    }
  }

  ThemeData _buildThemedLoginTheme(BuildContext context) {
    final baseTheme = Theme.of(context);
    final preset = presetById(_brandPresetId);

    if (_themeModeId == 'independent' && preset.independentTokens != null) {
      return applyIndependentTheme(baseTheme, preset.id);
    }

    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = resolveBrightness(_themeModeId, systemBrightness);
    final base = withBrightness(baseTheme, brightness);
    final accent = preset.id == 'system' || preset.accent == null
        ? base.colorScheme.primary
        : preset.accent!;
    final scheme = buildConceptScheme(brightness: brightness, accent: accent);

    return base.copyWith(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: base.appBarTheme.copyWith(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: scheme.surface.withOpacity(0),
      ),
      cardTheme: base.cardTheme.copyWith(
        color: scheme.surfaceContainerLow,
        surfaceTintColor: scheme.surface.withOpacity(0),
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: scheme.surface.withOpacity(0),
        surfaceTintColor: scheme.surface.withOpacity(0),
      ),
      dividerTheme: base.dividerTheme.copyWith(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
    );
  }

  Future<void> _restoreBrandAndThemePrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final preset = (prefs.getString(kBrandPresetKey) ?? 'system').trim();
      final mode = (prefs.getString(kThemeModeKey) ?? 'system').trim();
      if (!mounted) return;
      setState(() {
        _brandPresetId = preset.isEmpty ? 'system' : preset;
        _themeModeId = mode.isEmpty ? 'system' : mode;
        _prefsLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _prefsLoaded = true);
    }
  }

  bool _isHeadTarget() {
    return _redirectAfterLogin == AppRoutes.headStub ||
        _redirectAfterLogin == AppRoutes.headquarterPage;
  }

  String _defaultRouteForMode() {
    switch (_mode) {
      case 'personal':
      case 'tablet':
        return AppRoutes.tablet;
      case 'single':
        return AppRoutes.singleCommute;
      case 'double':
        return AppRoutes.doubleCommute;
      case 'triple':
        return AppRoutes.tripleCommute;
      case 'minor':
        return AppRoutes.minorCommute;
      case 'service':
      default:
        return AppRoutes.commute;
    }
  }

  void _navigateAfterLogin() {
    if (_isHeadTarget()) {
      final selectedArea =
          context.read<UserState>().session?.selectedArea.trim() ?? '';
      if (selectedArea != 'belivus') {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(AppRoutes.selector);
        return;
      }
    }

    final route = _redirectAfterLogin ?? _defaultRouteForMode();
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  Widget _buildLoginForm() {
    switch (_mode) {
      case 'personal':
        return PersonalLoginForm(controller: _personalController!);
      case 'tablet':
        return TabletLoginForm(controller: _tabletController!);
      case 'single':
        return SingleLoginForm(controller: _singleLoginController!);
      case 'double':
        return DoubleLoginForm(controller: _doubleLoginController!);
      case 'triple':
        return TripleLoginForm(controller: _tripleLoginController!);
      case 'minor':
        return MinorLoginForm(controller: _minorLoginController!);
      case 'service':
      default:
        return ServiceLoginForm(controller: _serviceLoginController!);
    }
  }

  void _maybeInitControllerAuto() {
    if (_didInitAuto) return;
    if (_mode == 'personal' || _mode == 'tablet') return;
    _didInitAuto = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (_mode) {
        case 'single':
          _singleLoginController?.initState();
          return;
        case 'double':
          _doubleLoginController?.initState();
          return;
        case 'triple':
          _tripleLoginController?.initState();
          return;
        case 'minor':
          _minorLoginController?.initState();
          return;
        case 'service':
        default:
          _serviceLoginController?.initState();
          return;
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _mode = _normalizeMode(widget.mode);
    _createControllerForMode();
    _restoreBrandAndThemePrefs();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final redirect = args['redirectAfterLogin'];
      if (redirect is String && redirect.isNotEmpty) {
        _redirectAfterLogin = redirect;
      }
      final requiredMode = args['requiredMode'];
      if (requiredMode is String && requiredMode.isNotEmpty) {
        _requiredMode = _normalizeModeNullable(requiredMode);
      }
    }
    _maybeInitControllerAuto();
  }

  Widget _buildPrefsLoadingShell(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final base = ThemeData(brightness: brightness, useMaterial3: true);
    return Theme(
      data: base,
      child: PromptUiScope(
        child: Builder(
          builder: (context) {
            final tokens = PromptUiTheme.of(context);
            return AnnotatedRegion<SystemUiOverlayStyle>(
              value: _systemUiStyle(tokens),
              child: Scaffold(
                backgroundColor: tokens.canvas,
                body: Center(
                  child: Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: tokens.surfaceRaised,
                      borderRadius:
                          BorderRadius.circular(PromptUiShapes.control),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    alignment: Alignment.center,
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.2,
                        color: tokens.accent,
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  SystemUiOverlayStyle _systemUiStyle(PromptUiTokens tokens) {
    final iconBrightness =
        tokens.isDark ? Brightness.light : Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: tokens.surface,
      statusBarIconBrightness: iconBrightness,
      statusBarBrightness:
          tokens.isDark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: tokens.surface,
      systemNavigationBarIconBrightness: iconBrightness,
      systemNavigationBarDividerColor: tokens.borderSubtle,
    );
  }

  Widget _buildModeMismatch() {
    return Builder(
      builder: (context) {
        final tokens = PromptUiTheme.of(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: _systemUiStyle(tokens),
          child: PopScope(
            canPop: false,
            child: Scaffold(
              backgroundColor: tokens.canvas,
              body: SafeArea(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: PromptAnimatedReveal(
                        child: Container(
                          padding: const EdgeInsets.all(22),
                          decoration: BoxDecoration(
                            color: tokens.surfaceRaised,
                            borderRadius:
                                BorderRadius.circular(PromptUiShapes.card),
                            border: Border.all(color: tokens.borderSubtle),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: tokens.shadow,
                                blurRadius: 18,
                                offset: const Offset(0, 9),
                              ),
                            ],
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              Center(
                                child: Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: tokens.warningContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(
                                    Icons.lock_outline_rounded,
                                    color: tokens.warning,
                                    size: 30,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                '접근 가능한 모드가 아닙니다.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleLarge
                                    ?.copyWith(
                                      color: tokens.textPrimary,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '요청 모드: ${_requiredMode!}\n현재 모드: $_mode',
                                textAlign: TextAlign.center,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: tokens.textSecondary),
                              ),
                              const SizedBox(height: 18),
                              PromptButton(
                                label: '허브로 돌아가기',
                                icon: Icons.hub_rounded,
                                expand: true,
                                onPressed: () => Navigator.of(context)
                                    .pushReplacementNamed(AppRoutes.selector),
                                haptic: PromptHaptic.selection,
                              ),
                            ],
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
    );
  }

  Widget _buildPromptScreen(Widget loginForm) {
    return Builder(
      builder: (context) {
        final tokens = PromptUiTheme.of(context);
        return AnnotatedRegion<SystemUiOverlayStyle>(
          value: _systemUiStyle(tokens),
          child: PopScope(
            canPop: false,
            child: Scaffold(
              backgroundColor: tokens.canvas,
              body: AnimatedSwitcher(
                duration: MediaQuery.maybeOf(context)?.disableAnimations ?? false
                    ? Duration.zero
                    : PromptUiMotion.component,
                switchInCurve: PromptUiMotion.enter,
                switchOutCurve: PromptUiMotion.exit,
                child: KeyedSubtree(
                  key: ValueKey<String>(_mode),
                  child: loginForm,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildLegacyServiceScreen(Widget loginForm) {
    return Builder(
      builder: (context) {
        final colorScheme = Theme.of(context).colorScheme;
        return PopScope(
          canPop: false,
          child: Scaffold(
            backgroundColor: colorScheme.surface,
            body: Padding(
              padding: const EdgeInsets.all(20),
              child: Center(
                child: SingleChildScrollView(child: loginForm),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_prefsLoaded) {
      return _buildPrefsLoadingShell(context);
    }

    final themed = _buildThemedLoginTheme(context);
    final loginForm = _buildLoginForm();

    if (_requiredMode != null && _requiredMode != _mode) {
      return Theme(
        data: themed,
        child: PromptUiScope(child: _buildModeMismatch()),
      );
    }

    if (!_usesPromptUi) {
      return Theme(
        data: themed,
        child: _buildLegacyServiceScreen(loginForm),
      );
    }

    return Theme(
      data: themed,
      child: PromptUiScope(child: _buildPromptScreen(loginForm)),
    );
  }

  @override
  void dispose() {
    switch (_mode) {
      case 'personal':
        _personalController?.dispose();
        break;
      case 'tablet':
        _tabletController?.dispose();
        break;
      case 'single':
        _singleLoginController?.dispose();
        break;
      case 'double':
        _doubleLoginController?.dispose();
        break;
      case 'triple':
        _tripleLoginController?.dispose();
        break;
      case 'minor':
        _minorLoginController?.dispose();
        break;
      case 'service':
      default:
        _serviceLoginController?.dispose();
        break;
    }
    super.dispose();
  }
}
