import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../routes.dart'; // 기본 redirect(AppRoutes.commute) 사용
import '../../../states/user/user_state.dart'; // 로그인/selectedArea 확인

// service
import 'service/service_login_controller.dart';
import 'service/sections/service_login_form.dart';

// simple
import 'simple/simple_login_controller.dart';
import 'simple/sections/simple_login_form.dart';

// tablet
import 'tablet/tablet_login_controller.dart';
import 'tablet/sections/tablet_login_form.dart';

// ✅ lite
import 'lite/lite_login_controller.dart';
import 'lite/sections/lite_login_form.dart';

class LoginScreen extends StatefulWidget {
  // ✅ mode: 'service' | 'tablet' | 'simple' | 'lite'
  const LoginScreen({super.key, this.mode = 'service'});

  final String mode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  // 필요한 것만 생성/폐기
  ServiceLoginController? _serviceLoginController;
  SimpleLoginController? _simpleLoginController;
  TabletLoginController? _tabletController;
  LiteLoginController? _liteLoginController;

  late final AnimationController _loginAnimationController;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _opacityAnimation;

  // ▼ 라우트 인자
  String? _redirectAfterLogin; // 로그인 성공 후 목적지
  String? _requiredMode; // 모드 강제(옵션)
  bool _didInitAuto = false; // 자동 로그인 게이트 1회 실행 보장

  @override
  void initState() {
    super.initState();

    // ✅ 모드에 따라 해당 컨트롤러만 초기화
    if (widget.mode == 'tablet') {
      _tabletController = TabletLoginController(context);
      // 태블릿 자동 초기화는 화면 생성 후 1회만 트리거
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _tabletController!.initState();
      });
    } else if (widget.mode == 'simple') {
      _simpleLoginController = SimpleLoginController(
        context,
        onLoginSucceeded: _navigateAfterLogin,
      );
    } else if (widget.mode == 'lite') {
      _liteLoginController = LiteLoginController(
        context,
        onLoginSucceeded: _navigateAfterLogin,
      );
    } else {
      // 기본은 service
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

    // ▼ 라우트 인자 수신
    final args = ModalRoute.of(context)?.settings.arguments;
    if (args is Map) {
      final ra = args['redirectAfterLogin'];
      if (ra is String && ra.isNotEmpty) {
        _redirectAfterLogin = ra;
      }
      final rm = args['requiredMode'];
      if (rm is String && rm.isNotEmpty) {
        _requiredMode = rm;
      }
    }

    // ▼ 자동 로그인 게이트: 라우트 인자를 먼저 확보한 뒤 1회만 실행
    //   - service / simple / lite 모두 자동 로그인 적용 (tablet만 제외)
    if (!_didInitAuto && widget.mode != 'tablet') {
      _didInitAuto = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        final alreadyLoggedIn = context.read<UserState>().isLoggedIn;
        if (!alreadyLoggedIn) {
          if (widget.mode == 'simple') {
            _simpleLoginController?.initState();
          } else if (widget.mode == 'lite') {
            _liteLoginController?.initState();
          } else {
            _serviceLoginController?.initState();
          }
        }
      });
    }
  }

  bool _isHeadTarget() {
    return _redirectAfterLogin == AppRoutes.headStub ||
        _redirectAfterLogin == AppRoutes.headquarterPage;
  }

  /// ✅ 모드별 기본 라우트 결정
  /// - service  → /commute
  /// - simple   → /simple_commute
  /// - tablet   → /commute (정책에 따라 변경 가능)
  /// - lite     → /lite_commute (LiteCommuteInsideScreen)
  String _defaultRouteForMode() {
    switch (widget.mode) {
      case 'simple':
        return AppRoutes.simpleCommute;
      case 'tablet':
        return AppRoutes.commute;
      case 'lite':
        return AppRoutes.liteCommute; // ✅ 핵심 변경
      case 'service':
      default:
        return AppRoutes.commute;
    }
  }

  void _navigateAfterLogin() {
    // ✅ 본사 진입은 'selectedArea == belivus' 일 때만 허용 (하드코딩)
    if (_isHeadTarget()) {
      final selectedArea = context.read<UserState>().user?.selectedArea?.trim() ?? '';
      if (selectedArea != 'belivus') {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed(AppRoutes.selector);
        return;
      }
    }

    // ✅ 모드 기본값 + 인자로 들어온 redirectAfterLogin 우선
    final defaultRoute = _defaultRouteForMode();
    final route = _redirectAfterLogin ?? defaultRoute;

    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    // (선택) requiredMode 강제 – 모드가 다르면 접근 차단/안내
    if (_requiredMode != null && _requiredMode != widget.mode) {
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
                    '접근 가능한 모드가 아닙니다. '
                        '(요청: ${_requiredMode!}, 현재: ${widget.mode})',
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

    // ✅ 모드별 폼 선택
    final Widget loginForm;
    if (widget.mode == 'tablet') {
      loginForm = TabletLoginForm(controller: _tabletController!);
    } else if (widget.mode == 'simple') {
      loginForm = SimpleLoginForm(controller: _simpleLoginController!);
    } else if (widget.mode == 'lite') {
      loginForm = LiteLoginForm(controller: _liteLoginController!);
    } else {
      loginForm = ServiceLoginForm(controller: _serviceLoginController!);
    }

    // ✅ 이 화면에서만 뒤로가기 pop을 막아 앱 종료 방지
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

    if (widget.mode == 'tablet') {
      _tabletController?.dispose();
    } else if (widget.mode == 'simple') {
      _simpleLoginController?.dispose();
    } else if (widget.mode == 'lite') {
      _liteLoginController?.dispose();
    } else {
      _serviceLoginController?.dispose();
    }

    super.dispose();
  }
}
