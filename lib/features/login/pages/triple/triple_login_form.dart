import 'package:flutter/material.dart';

import '../../../../shared/auth/account_code_number.dart';

import '../../../../app/di/routes.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../controllers/triple/triple_login_controller.dart';
import '../common/code_number_debug_action.dart';
import '../common/common_login_ui.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';

class TripleLoginForm extends StatefulWidget {
  const TripleLoginForm({super.key, required this.controller});

  final TripleLoginController controller;

  @override
  State<TripleLoginForm> createState() => _TripleLoginFormState();
}

class _TripleLoginFormState extends State<TripleLoginForm> {
  late final TripleLoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
  }

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  Future<void> _handleLogin() async {
    final success = await _controller.login(setState);
    if (!mounted) return;
    setState(() {});
    if (!success) {
      await showCommonLoginFailure(context);
    }
  }

  Future<void> _onLoginButtonPressed() async {
    if (_controller.isLoading) return;
    _trace(
      '로그인 버튼',
      meta: <String, dynamic>{
        'screen': 'normal_login',
        'action': 'login',
      },
    );
    await _handleLogin();
  }

  void _onTopCompanyLogoTapped() {
    _trace(
      '회사 로고(상단)',
      meta: <String, dynamic>{
        'screen': 'normal_login',
        'asset': 'assets/images/ParkinWorkin_logo.png',
        'action': 'tap',
      },
    );
  }

  void _onFooterLogoTapped() {
    _trace(
      '회사 로고(펠리컨)',
      meta: <String, dynamic>{
        'screen': 'normal_login',
        'asset': 'assets/images/ParkinWorkin_text.png',
        'action': 'back_to_mode_launcher',
        'to': AppRoutes.modeLauncher,
      },
    );
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.modeLauncher,
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return CommonLoginScaffold(
      spec: CommonLoginModeSpec.triple,
      onTopLogoPressed: _onTopCompanyLogoTapped,
      onFooterLogoPressed: _onFooterLogoTapped,
      topTrailing: const CodeNumberDebugAction(
        scope: 'triple',
        title: '코드번호 로그인 로그',
      ),
      fields: CommonLoginFields(
        nameController: _controller.nameController,
        nameFocus: _controller.nameFocus,
        accountController: _controller.codeNumberController,
        accountFocus: _controller.codeNumberFocus,
        passwordController: _controller.passwordController,
        passwordFocus: _controller.passwordFocus,
        accountLabel: '코드번호',
        accountIcon: Icons.tag_rounded,
        accountKeyboardType: TextInputType.text,
        accountInputFormatters: const [
          AccountCodeNumberInputFormatter(),
        ],
        onAccountChanged: (value) =>
            _controller.formatCodeNumber(value, setState),
        obscurePassword: _controller.obscurePassword,
        onTogglePassword: () =>
            setState(() => _controller.togglePassword()),
        onSubmit: _onLoginButtonPressed,
        enabled: !_controller.isLoading,
      ),
      actions: CommonAnimatedReveal(
        delay: const Duration(milliseconds: 240),
        child: AnimatedSwitcher(
          duration: transitionDuration,
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            final scale = Tween<double>(begin: 0.98, end: 1).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            );
            final slide = Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(
                parent: animation,
                curve: Curves.easeOutCubic,
              ),
            );
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: slide,
                child: ScaleTransition(
                  scale: scale,
                  child: child,
                ),
              ),
            );
          },
          child: CommonButton(
            key: ValueKey<bool>(_controller.isLoading),
            label: _controller.isLoading ? '로그인 중' : '로그인',
            icon: Icons.login_rounded,
            expand: true,
            loading: _controller.isLoading,
            onPressed: _controller.isLoading ? null : _onLoginButtonPressed,
            haptic: CommonHaptic.light,
          ),
        ),
      ),
    );
  }
}
