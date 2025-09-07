import 'package:flutter/material.dart';
import 'outside/outside_login_controller.dart';
import 'outside/sections/outside_login_form.dart';
import 'service/service_login_controller.dart';
import 'service/debugs/service_login_debug_firestore_logger.dart';
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
  late final OutsideLoginController _outsideController;

  late final AnimationController _loginAnimationController;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    LoginDebugFirestoreLogger().log(
      '🔵 LoginScreen initState() - 로그인 화면 로딩 시작 (mode=${widget.mode})',
      level: 'info',
    );

    // ✅ 모드에 따라 해당 컨트롤러만 초기화
    if (widget.mode == 'tablet') {
      _tabletController = TabletLoginController(context);
      LoginDebugFirestoreLogger().log('✅ LoginScreen - TabletLoginController 생성 완료', level: 'success');
    } else if (widget.mode == 'outside') {
      _outsideController = OutsideLoginController(context);
      LoginDebugFirestoreLogger().log('✅ LoginScreen - OutsideLoginController 생성 완료', level: 'success');
    } else {
      _loginController = ServiceLoginController(context);
      LoginDebugFirestoreLogger().log('✅ LoginScreen - ServiceLoginController 생성 완료', level: 'success');
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
    LoginDebugFirestoreLogger().log('✅ 로그인 화면 애니메이션 시작', level: 'success');
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 모드별 폼 선택
    final Widget loginForm = (widget.mode == 'tablet')
        ? TabletLoginForm(controller: _tabletController)
        : (widget.mode == 'outside')
        ? OutsideLoginForm(controller: _outsideController)
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

    // ✅ 생성한 컨트롤러만 dispose
    if (widget.mode == 'tablet') {
      _tabletController.dispose();
    } else if (widget.mode == 'outside') {
      _outsideController.dispose();
    } else {
      _loginController.dispose();
    }

    super.dispose();
  }
}
