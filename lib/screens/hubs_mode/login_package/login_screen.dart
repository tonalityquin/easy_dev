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
import 'single/single_login_controller.dart';
import 'single/sections/single_login_form.dart';

// tablet
import 'tablet/tablet_login_controller.dart';
import 'tablet/sections/tablet_login_form.dart';

// double
import 'double/double_login_controller.dart';
import 'double/sections/double_login_form.dart';

// triple
import 'triple/triple_login_controller.dart';
import 'triple/sections/triple_login_form.dart';

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
  SingleLoginController? _singleLoginController;
  TabletLoginController? _tabletController;
  DoubleLoginController? _doubleLoginController;
  TripleLoginController? _tripleLoginController;
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

  // ✅ prefs 로딩 완료 여부(테마 깜빡임/전환 최소화 목적)
  bool _prefsLoaded = false;

  // ─────────────────────────────────────────────
  // Mode normalize
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

  // ─────────────────────────────────────────────
  // Controller factory (중복 제거)
  void _createControllerForMode() {
    switch (_mode) {
      case 'tablet':
        _tabletController = TabletLoginController(context);
        // Tablet만 initState를 postFrame으로 호출하는 기존 정책 유지
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _tabletController?.initState();
        });
        break;

      case 'single':
        _singleLoginController = SingleLoginController(
          context,
          onLoginSucceeded: _navigateAfterLogin,
        );
        break;

      case 'double':
        _doubleLoginController = DoubleLoginController(
          context,
          onLoginSucceeded: _navigateAfterLogin,
        );
        break;

      case 'triple':
        _tripleLoginController = TripleLoginController(
          context,
          onLoginSucceeded: _navigateAfterLogin,
        );
        break;

      case 'minor':
        _minorLoginController = MinorLoginController(
          context,
          onLoginSucceeded: _navigateAfterLogin,
        );
        break;

      case 'service':
      default:
        _serviceLoginController = ServiceLoginController(
          context,
          onLoginSucceeded: _navigateAfterLogin,
        );
        break;
    }
  }

  // ─────────────────────────────────────────────
  // Theme builder (Selector와 동일한 정책 + independent 지원)
  ThemeData _buildThemedLoginTheme(BuildContext context) {
    final baseTheme = Theme.of(context);
    final preset = presetById(_brandPresetId);

    // ✅ 핵심: independent 모드 + 독립 프리셋이면 프리셋 토큰으로 ThemeData를 강제 구성
    if (_themeModeId == 'independent' && preset.independentTokens != null) {
      return applyIndependentTheme(baseTheme, preset.id);
    }

    // ✅ system/light/dark: 컨셉 스킴 적용
    final systemBrightness = MediaQuery.platformBrightnessOf(context);
    final brightness = resolveBrightness(_themeModeId, systemBrightness);

    // 1) 밝기 강제
    final base = withBrightness(baseTheme, brightness);

    // 2) accent 결정: system이면 현재 theme primary 사용, 아니면 프리셋 accent 사용
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

  // ─────────────────────────────────────────────
  // Prefs restore
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
      setState(() {
        _prefsLoaded = true;
      });
    }
  }

  // ─────────────────────────────────────────────
  // Route helpers
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

  // ─────────────────────────────────────────────
  // Login form selector
  Widget _buildLoginForm() {
    switch (_mode) {
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

  // ─────────────────────────────────────────────
  // Auto init (중복 제거)
  void _maybeInitControllerAuto() {
    if (_didInitAuto) return;
    if (_mode == 'tablet') return; // tablet은 자체 postFrame initState 정책 유지

    _didInitAuto = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final alreadyLoggedIn = context.read<UserState>().isLoggedIn;
      if (alreadyLoggedIn) return;

      switch (_mode) {
        case 'single':
          _singleLoginController?.initState();
          break;
        case 'double':
          _doubleLoginController?.initState();
          break;
        case 'triple':
          _tripleLoginController?.initState();
          break;
        case 'minor':
          _minorLoginController?.initState();
          break;
        case 'service':
        default:
          _serviceLoginController?.initState();
          break;
      }
    });
  }

  // ─────────────────────────────────────────────
  // Lifecycle
  @override
  void initState() {
    super.initState();

    _mode = _normalizeMode(widget.mode);

    // ✅ 1) 컨트롤러 생성은 즉시
    _createControllerForMode();

    // ✅ 2) prefs 로딩(테마)
    _restoreBrandAndThemePrefs();

    // ✅ 3) 애니메이션
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

    _maybeInitControllerAuto();
  }

  Widget _buildPrefsLoadingShell(BuildContext context) {
    final base = Theme.of(context);
    final cs = base.colorScheme;

    // ✅ 로딩 시 “눈에 띄는 흰 화면”을 피하기 위해
    // - 시스템 다크면 어두운 배경
    // - 시스템 라이트면 약간 톤다운된 표면
    final sysBrightness = MediaQuery.platformBrightnessOf(context);
    final bg = (sysBrightness == Brightness.dark) ? const Color(0xFF0B0F14) : cs.surface;

    return Scaffold(
      backgroundColor: bg,
      body: const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ prefs 로딩 전: “기본 테마 1프레임(흰 배경)” 노출을 방지
    if (!_prefsLoaded) {
      return _buildPrefsLoadingShell(context);
    }

    final themed = _buildThemedLoginTheme(context);

    // ✅ requiredMode 강제: 테마 적용된 상태에서 차단 UI
    if (_requiredMode != null && _requiredMode != _mode) {
      return Theme(
        data: themed,
        child: Builder(
          builder: (context) {
            final cs = Theme.of(context).colorScheme;

            return PopScope(
              canPop: false,
              child: Scaffold(
                backgroundColor: cs.surface,
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.lock_outline, size: 40, color: cs.onSurface),
                        const SizedBox(height: 12),
                        Text(
                          '접근 가능한 모드가 아닙니다. (요청: ${_requiredMode!}, 현재: $_mode)',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurface),
                          textAlign: TextAlign.center,
                        ),
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

    // ✅ 폼 선택
    final loginForm = _buildLoginForm();

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

    switch (_mode) {
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
