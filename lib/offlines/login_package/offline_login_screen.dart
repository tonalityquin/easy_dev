// lib/offlines/login_package/offline_login_screen.dart
// ─────────────────────────────────────────────────────────────────────────────
// LoginScreen 과 동일한 빌드 구조(뒤로가기 차단 + Padding + Center + Scroll + Fade/Slide)

import 'package:flutter/material.dart';
import 'service/offline_login_controller.dart';
import 'service/sections/offline_login_form.dart';

// ★ 추가: 오프라인 세션 존재 시 즉시 진입을 위한 서비스
import 'package:easydev/offlines/offline_auth_service.dart';

class OfflineLoginScreen extends StatefulWidget {
  final VoidCallback? onLoginSucceeded;

  const OfflineLoginScreen({
    super.key,
    this.onLoginSucceeded,
  });

  @override
  State<OfflineLoginScreen> createState() => _OfflineLoginScreenState();
}

class _OfflineLoginScreenState extends State<OfflineLoginScreen>
    with SingleTickerProviderStateMixin {
  late final OfflineLoginController _controller;

  late final AnimationController _loginAnimationController;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    _controller = OfflineLoginController(
      onLoginSucceeded: widget.onLoginSucceeded,
    );

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

    // ★ 추가: 이미 오프라인 세션이 있으면 즉시 성공 처리(바로 진입)
    //  - controller 내부 저장 로직과 무관하게, 앱 진입 스킵 UX 보장
    Future.microtask(() async {
      final has = await OfflineAuthService.instance.hasSession();
      if (!mounted) return;
      if (has) {
        // routes.dart에서 onLoginSucceeded 콜백이 '/offline_commute'로 네비게이션함
        widget.onLoginSucceeded?.call();
      }
    });
  }

  @override
  void dispose() {
    _loginAnimationController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Padding(
          // ✅ 수정: 위치 인자 대신 named 파라미터 사용
          padding: const EdgeInsets.all(20),
          child: Center(
            child: SingleChildScrollView(
              child: FadeTransition(
                opacity: _opacityAnimation,
                child: SlideTransition(
                  position: _offsetAnimation,
                  child: OfflineLoginForm(controller: _controller),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
