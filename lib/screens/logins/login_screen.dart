import 'package:flutter/material.dart';
import 'debugs/login_debug_firestore_logger.dart';
import 'sections/login_form.dart';
import 'login_controller.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  late final LoginController _loginController;
  late final AnimationController _loginAnimationController;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    // 로그인 시작 로그 기록
    LoginDebugFirestoreLogger().log(
      '🔵 LoginScreen initState() - 로그인 화면 로딩 시작',
      level: 'info',
    );

    // 로그인 컨트롤러 초기화
    _loginController = LoginController(context);

    // 로그인 컨트롤러 생성 완료 로그
    LoginDebugFirestoreLogger().log(
      '✅ LoginScreen - LoginController 생성 완료',
      level: 'success',
    );

    // 애니메이션 컨트롤러 설정 (화면 전환용)
    _loginAnimationController = AnimationController(
      duration: const Duration(milliseconds: 700),
      vsync: this,
    );

    // 로그인 폼 슬라이드 애니메이션 설정 (아래에서 위로)
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _loginAnimationController, curve: Curves.easeOut),
    );

    // 로그인 폼 페이드 인 애니메이션 설정
    _opacityAnimation = CurvedAnimation(
      parent: _loginAnimationController,
      curve: Curves.easeIn,
    );

    // 애니메이션 실행
    _loginAnimationController.forward();

    // 애니메이션 시작 로그
    LoginDebugFirestoreLogger().log(
      '✅ 로그인 화면 애니메이션 시작',
      level: 'success',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SingleChildScrollView(
            child: FadeTransition(
              opacity: _opacityAnimation,
              child: SlideTransition(
                position: _offsetAnimation,
                child: LoginForm(controller: _loginController), // 로그인 폼 렌더링
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    // 리소스 정리
    _loginAnimationController.dispose();
    _loginController.dispose();
    super.dispose();
  }
}
