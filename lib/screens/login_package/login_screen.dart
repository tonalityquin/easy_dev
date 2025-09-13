// lib/screens/login_package/login_screen.dart
import 'package:flutter/material.dart';
import 'service/service_login_controller.dart';
import 'service/sections/service_login_form.dart';

// tablet
import 'tablet/tablet_login_controller.dart';
import 'tablet/sections/tablet_login_form.dart';

// ✅ outside

class LoginScreen extends StatefulWidget {
  // ✅ mode: 'service' | 'tablet' | 'outside'
  const LoginScreen({super.key, this.mode = 'service'});

  final String mode;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  // 필요한 것만 생성/폐기
  late final ServiceLoginController _loginController;
  late final TabletLoginController _tabletController;

  late final AnimationController _loginAnimationController;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    // ✅ 모드에 따라 해당 컨트롤러만 초기화
    if (widget.mode == 'tablet') {
      _tabletController = TabletLoginController(context);

    } else {
      _loginController = ServiceLoginController(context);
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
  Widget build(BuildContext context) {
    // ✅ 모드별 폼 선택
    final Widget loginForm = (widget.mode == 'tablet')
        ? TabletLoginForm(controller: _tabletController)
        : ServiceLoginForm(controller: _loginController);

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
      _tabletController.dispose();
    } else {
      // 기본은 'service' 모드이므로 else에서 서비스 컨트롤러 정리
      _loginController.dispose();
    }

    // ✅ 어떤 모드든 무조건 마지막에 호출
    super.dispose();
  }
}
