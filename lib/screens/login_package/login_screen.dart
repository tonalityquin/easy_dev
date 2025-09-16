// lib/screens/login_package/login_screen.dart
import 'package:flutter/material.dart';
import '../../routes.dart'; // redirect 기본값(AppRoutes.commute) 사용
import 'service/service_login_controller.dart';
import 'service/sections/service_login_form.dart';

// tablet
import 'tablet/tablet_login_controller.dart';
import 'tablet/sections/tablet_login_form.dart';

// ✅ outside (향후 확장 대비)

class LoginScreen extends StatefulWidget {
  // ✅ mode: 'service' | 'tablet' | 'outside'
  const LoginScreen({super.key, this.mode = 'service'});

  final String mode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  // 필요한 것만 생성/폐기
  ServiceLoginController? _loginController;
  TabletLoginController? _tabletController;

  late final AnimationController _loginAnimationController;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _opacityAnimation;

  // ▼ 라우트 인자
  String? _redirectAfterLogin; // 로그인 성공 후 목적지
  String? _requiredMode;       // 모드 강제(옵션)
  bool _didInitAuto = false;   // 자동 로그인 게이트 1회 실행 보장

  @override
  void initState() {
    super.initState();

    // ✅ 모드에 따라 해당 컨트롤러만 초기화
    if (widget.mode == 'tablet') {
      _tabletController = TabletLoginController(context);
    } else {
      _loginController = ServiceLoginController(
        context,
        // 성공 시 내비게이션은 화면에서 처리
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
    if (!_didInitAuto && widget.mode == 'service' && _loginController != null) {
      _didInitAuto = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        // 컨트롤러 내부의 자동 로그인 체크(성공 시 onLoginSucceeded 콜백 호출)
        _loginController!.initState();
      });
    }
  }

  void _navigateAfterLogin() {
    // 기본값은 기존과 동일하게 /commute
    final route = _redirectAfterLogin ?? AppRoutes.commute;
    if (!mounted) return;
    Navigator.of(context).pushReplacementNamed(route);
  }

  @override
  Widget build(BuildContext context) {
    // (선택) requiredMode 강제 – 모드가 다르면 접근 차단/안내
    if (_requiredMode != null && _requiredMode != widget.mode) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 40),
                const SizedBox(height: 12),
                Text('접근 가능한 모드가 아닙니다. (요청: ${_requiredMode!}, 현재: ${widget.mode})'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.of(context).pushReplacementNamed(AppRoutes.selector),
                  child: const Text('허브로 돌아가기'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ✅ 모드별 폼 선택
    final Widget loginForm = (widget.mode == 'tablet')
        ? TabletLoginForm(controller: _tabletController!)
        : ServiceLoginForm(controller: _loginController!);

    return Scaffold(
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
    );
  }

  @override
  void dispose() {
    _loginAnimationController.dispose();

    // initState의 분기와 정확히 ‘대칭’ 맞추기
    if (widget.mode == 'tablet') {
      _tabletController?.dispose();
    } else {
      // 기본은 'service' 모드이므로 else에서 서비스 컨트롤러 정리
      _loginController?.dispose();
    }

    super.dispose();
  }
}
