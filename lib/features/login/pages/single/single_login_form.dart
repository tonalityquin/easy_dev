import 'package:flutter/material.dart';

import '../../../../app/di/routes.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../controllers/single/single_login_controller.dart';
import '../common/common_login_ui.dart';
import '../../../../design_system/common_ui/common_ui_components.dart';

class SingleLoginForm extends StatefulWidget {
  const SingleLoginForm({super.key, required this.controller});

  final SingleLoginController controller;

  @override
  State<SingleLoginForm> createState() => _SingleLoginFormState();
}

class _SingleLoginFormState extends State<SingleLoginForm> {
  late final SingleLoginController _controller;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller;
    _controller.bindStateListener(_handleControllerStateChanged);
  }

  void _handleControllerStateChanged() {
    if (!mounted) return;
    setState(() {});
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
    if (!success && !_controller.interactionLocked) {
      await showCommonLoginFailure(context);
    }
  }

  Future<void> _onLoginButtonPressed() async {
    if (_controller.interactionLocked) return;
    _trace(
      '로그인 버튼',
      meta: <String, dynamic>{
        'screen': 'simple_login',
        'action': 'login',
      },
    );
    await _handleLogin();
  }

  void _onTopCompanyLogoTapped() {
    _trace(
      '회사 로고(상단)',
      meta: <String, dynamic>{
        'screen': 'simple_login',
        'asset': 'assets/images/ParkinWorkin_logo.png',
        'action': 'tap',
      },
    );
  }

  void _onFooterLogoTapped() {
    _trace(
      '회사 로고(펠리컨)',
      meta: <String, dynamic>{
        'screen': 'simple_login',
        'asset': 'assets/images/ParkinWorkin_text.png',
        'action': 'back_to_selector',
        'to': AppRoutes.selector,
      },
    );
    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.selector,
      (route) => false,
    );
  }


  @override
  void dispose() {
    _controller.bindStateListener(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final transitionDuration = reduceMotion
        ? Duration.zero
        : const Duration(milliseconds: 220);

    return CommonLoginScaffold(
      spec: CommonLoginModeSpec.single,
      onTopLogoPressed: _onTopCompanyLogoTapped,
      onFooterLogoPressed: _onFooterLogoTapped,
      fields: CommonLoginFields(
        nameController: _controller.nameController,
        nameFocus: _controller.nameFocus,
        accountController: _controller.phoneController,
        accountFocus: _controller.phoneFocus,
        passwordController: _controller.passwordController,
        passwordFocus: _controller.passwordFocus,
        accountLabel: '전화번호',
        accountIcon: Icons.phone_rounded,
        accountKeyboardType: TextInputType.phone,
        onAccountChanged: (value) =>
            _controller.formatPhoneNumber(value, setState),
        obscurePassword: _controller.obscurePassword,
        onTogglePassword: () =>
            setState(() => _controller.togglePassword()),
        onSubmit: _onLoginButtonPressed,
        enabled: !_controller.interactionLocked,
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
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: scale,
                child: child,
              ),
            );
          },
          child: CommonButton(
            key: ValueKey<String>(_controller.buttonLabel),
            label: _controller.buttonLabel,
            icon: Icons.login_rounded,
            expand: true,
            loading: _controller.isLoading,
            onPressed: _controller.interactionLocked
                ? null
                : _onLoginButtonPressed,
            haptic: CommonHaptic.light,
          ),
        ),
      ),
    );
  }
}
