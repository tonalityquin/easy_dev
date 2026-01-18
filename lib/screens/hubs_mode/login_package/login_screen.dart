import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../routes.dart';
import '../../../states/user/user_state.dart';

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
import 'lite/lite_login_controller.dart';
import 'lite/sections/lite_login_form.dart';

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
      // ✅ minor: 전용 컨트롤러 연결
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

  @override
  Widget build(BuildContext context) {
    if (_requiredMode != null && _requiredMode != _mode) {
      return PopScope(
        canPop: false,
        child: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.lock_outline, size: 40),
                  const SizedBox(height: 12),
                  Text(
                    '접근 가능한 모드가 아닙니다. (요청: ${_requiredMode!}, 현재: $_mode)',
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
    }

    final Widget loginForm;
    if (_mode == 'tablet') {
      loginForm = TabletLoginForm(controller: _tabletController!);
    } else if (_mode == 'single') {
      loginForm = SimpleLoginForm(controller: _simpleLoginController!);
    } else if (_mode == 'double') {
      loginForm = LiteLoginForm(controller: _liteLoginController!);
    } else if (_mode == 'triple') {
      loginForm = NormalLoginForm(controller: _normalLoginController!);
    } else if (_mode == 'minor') {
      // ✅ minor 폼 연결
      loginForm = MinorLoginForm(controller: _minorLoginController!);
    } else {
      loginForm = ServiceLoginForm(controller: _serviceLoginController!);
    }

    return PopScope(
      canPop: false,
      child: Scaffold(
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
