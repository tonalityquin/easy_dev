import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../routes.dart';
import '../../../states/user/user_state.dart';

// ✅ 컨셉 테마 + 프리셋/다크모드 키/헬퍼
import '../../../selector_hubs_package/brand_theme.dart';

// service
import 'service/service_login_controller.dart';
import 'service/sections/service_login_form.dart';

// single
import 'simple/simple_login_controller.dart';
import 'simple/sections/simple_login_form.dart';

// tablet
import 'tablet/tablet_login_controller.dart';
import 'tablet/sections/tablet_login_form.dart';

// double
import 'double/lite_login_controller.dart';
import 'double/sections/double_login_form.dart';

// triple
import 'normal/normal_login_controller.dart';
import 'normal/sections/normal_login_form.dart';

// ✅ minor
import 'minor/minor_login_controller.dart';
import 'minor/sections/minor_login_form.dart';

class LoginScreen extends StatefulWidget {
  // ✅ mode: 'service' | 'tablet' | 'single' | 'double' | 'triple' | 'minor'
  //    (하위 호환) 'simple'→'single', 'lite'/'light'→'double', 'normal'→'triple'
  const LoginScreen({super.key, this.mode = 'service'});

  final String mode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final String _mode;

  ServiceLoginController? _serviceLoginController;
  SimpleLoginController? _simpleLoginController;
  TabletLoginController? _tabletController;
  LiteLoginController? _liteLoginController;
  NormalLoginController? _normalLoginController;

  // ✅ minor
  MinorLoginController? _minorLoginController;

  late final AnimationController _loginAnimationController;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _opacityAnimation;

  String? _redirectAfterLogin;
  String? _requiredMode;
  bool _didInitAuto = false;

  // ✅ 전역 컨셉 테마 설정(Selector에서 선택한 값과 동일하게 적용)
  String _brandPresetId = 'system';
  String _themeModeId = 'system';

  static String _normalizeMode(String? raw) {
    final v = (raw ?? '').trim().toLowerCase();
    switch (v) {
      case 'service':
        return 'service';
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
    final t = raw.trim();
    if (t.isEmpty) return null;
    return _normalizeMode(t);
  }

  @override
  void initState() {
    super.initState();

    _mode = _normalizeMode(widget.mode);

    // ✅ 브랜드/다크모드 복원(로그인 화면도 동일 테마 적용)
    _restoreBrandAndThemePrefs();

    if (_mode == 'tablet') {
      _tabletController = TabletLoginController(context);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tabletController!.initState();
      });
    } else if (_mode == 'single') {
      _simpleLoginController = SimpleLoginController(
        context,
        onLoginSucceeded: _navigateAfterLogin,
      );
    } else if (_mode == 'double') {
      _liteLoginController = LiteLoginController(
        context,
        onLoginSucceeded: _navigateAfterLogin,
      );
    } else if (_mode == 'triple') {
      _normalLoginController = NormalLoginController(
        context,
        onLoginSucceeded: _navigateAfterLogin,
      );
    } else if (_mode == 'minor') {
      _minorLoginController = MinorLoginController(
        context,
        onLoginSucceeded: _navigateAfterLogin,
      );
    } else {
      _serviceLoginController = ServiceLoginController(
        context,
        onLoginSucceeded: _navigateAfterLogin,
      );
    }

    _loginAnimationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _loginAnimationController, curve: Curves.easeOut),
    );

    _opacityAnimation = CurvedAnimation(
      parent: _loginAnimationController,
      curve: Curves.easeIn,
    );

    _loginAnimationController.forward();
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
      });
    } catch (_) {
      // 실패 시 기본값 유지
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final ra = args['redirectAfterLogin'];
      if (ra is String && ra.isNotEmpty) {
        _redirectAfterLogin = ra;
      }
      final rm = args['requiredMode'];
      if (rm is String && rm.isNotEmpty) {
        _requiredMode = _normalizeModeNullable(rm);
      }
    }

    if (!_didInitAuto && _mode != 'tablet') {
      _didInitAuto = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final alreadyLoggedIn = context.read<UserState>().isLoggedIn;
        if (!alreadyLoggedIn) {
          if (_mode == 'single') {
            _simpleLoginController?.initState();
          } else if (_mode == 'double') {
            _liteLoginController?.initState();
          } else if (_mode == 'triple') {
            _normalLoginController?.initState();
          } else if (_mode == 'minor') {
            _minorLoginController?.initState();
          } else {
            _serviceLoginController?.initState();
          }
        }
      });
    }
  }

  bool _isHeadTarget() {
    return _redirectAfterLogin == AppRoutes.headStub || _redirectAfterLogin == AppRoutes.headquarterPage;
  }

  String _defaultRouteForMode() {
    switch (_mode) {
      case 'single':
        return AppRoutes.singleCommute;
      case 'tablet':
        return AppRoutes.commute;
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
      final selectedArea = context.read<UserState>().user?.selectedArea?.trim() ?? '';
      if (selectedArea != 'belivus') {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(AppRoutes.selector);
        return;
      }
    }

    final defaultRoute = _defaultRouteForMode();
    final route = _redirectAfterLogin ?? defaultRoute;

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  ThemeData _buildThemedLoginTheme(BuildContext context) {
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = resolveBrightness(_themeModeId, systemBrightness);

    final baseTheme = Theme.of(context);

    // 1) 밝기 강제
    final base = withBrightness(baseTheme, brightness);

    // 2) accent 결정: system이면 현재 theme primary 사용, 아니면 프리셋 accent 사용
    final preset = presetById(_brandPresetId);
    final accent = (preset.id == 'system' || preset.accent == null) ? base.colorScheme.primary : preset.accent!;

    // 3) 컨셉 스킴 생성(표면 중립 + primary만 컨셉)
    final scheme = buildConceptScheme(brightness: brightness, accent: accent);

    return base.copyWith(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
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
    final themed = _buildThemedLoginTheme(context);

    if (_requiredMode != null && _requiredMode != _mode) {
      return Theme(
        data: themed,
        child: Builder(
          builder: (context) {
            return PopScope(
              canPop: false,
              child: Scaffold(
                backgroundColor: Theme.of(context).colorScheme.surface,
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.lock_outline, size: 40),
                        const SizedBox(height: 12),
                        Text('접근 가능한 모드가 아닙니다. (요청: ${_requiredMode!}, 현재: $_mode)'),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.selector),
                          child: const Text('허브로 돌아가기'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    final Widget loginForm;
    if (_mode == 'tablet') {
      loginForm = TabletLoginForm(controller: _tabletController!);
    } else if (_mode == 'single') {
      loginForm = SimpleLoginForm(controller: _simpleLoginController!);
    } else if (_mode == 'double') {
      loginForm = DoubleLoginForm(controller: _liteLoginController!);
    } else if (_mode == 'triple') {
      loginForm = NormalLoginForm(controller: _normalLoginController!);
    } else if (_mode == 'minor') {
      loginForm = MinorLoginForm(controller: _minorLoginController!);
    } else {
      loginForm = ServiceLoginForm(controller: _serviceLoginController!);
    }

    return Theme(
      data: themed,
      child: Builder(
        builder: (context) {
          final cs = Theme.of(context).colorScheme;

          return PopScope(
            canPop: false,
            child: Scaffold(
              backgroundColor: cs.surface,
              body: Padding(
                padding: const EdgeInsets.all(20),
                child: Center(
                  child: SingleChildScrollView(
                    child: FadeTransition(
                      opacity: _opacityAnimation,
                      child: SlideTransition(
                        position: _offsetAnimation,
                        child: loginForm,
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

  @override
  void dispose() {
    _loginAnimationController.dispose();

    if (_mode == 'tablet') {
      _tabletController?.dispose();
    } else if (_mode == 'single') {
      _simpleLoginController?.dispose();
    } else if (_mode == 'double') {
      _liteLoginController?.dispose();
    } else if (_mode == 'triple') {
      _normalLoginController?.dispose();
    } else if (_mode == 'minor') {
      _minorLoginController?.dispose();
    } else {
      _serviceLoginController?.dispose();
    }

    super.dispose();
  }
}
