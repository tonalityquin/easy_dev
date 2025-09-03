import 'package:flutter/material.dart';
import 'tablet_login_controller.dart';
import 'debugs/tablet_login_debug_firestore_logger.dart';
import 'sections/tablet_login_form.dart';

class TabletLoginScreen extends StatefulWidget {
  const TabletLoginScreen({super.key});

  @override
  State<TabletLoginScreen> createState() => _TabletLoginScreenState();
}

class _TabletLoginScreenState extends State<TabletLoginScreen> with SingleTickerProviderStateMixin {
  late final TabletLoginController _tabletLoginController;
  late final AnimationController _loginAnimationController;
  late final Animation<Offset> _offsetAnimation;
  late final Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();

    TabletLoginDebugFirestoreLogger().log(
      '🔵 TabletLoginScreen initState() - 로그인 화면 로딩 시작',
      level: 'info',
    );

    _tabletLoginController = TabletLoginController(context);

    TabletLoginDebugFirestoreLogger().log(
      '✅ TabletLoginScreen - TabletLoginController 생성 완료',
      level: 'success',
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

    TabletLoginDebugFirestoreLogger().log(
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
                child: TabletLoginForm(controller: _tabletLoginController),
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
    _tabletLoginController.dispose();
    super.dispose();
  }
}
