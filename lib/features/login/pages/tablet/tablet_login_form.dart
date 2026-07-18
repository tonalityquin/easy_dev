import 'package:flutter/material.dart';

import '../../../../app/di/routes.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../controllers/tablet/tablet_login_controller.dart';
import '../common/prompt_login_ui.dart';

class TabletLoginForm extends StatefulWidget {
  const TabletLoginForm({super.key, required this.controller});

  final TabletLoginController controller;

  @override
  State<TabletLoginForm> createState() => _TabletLoginFormState();
}

class _TabletLoginFormState extends State<TabletLoginForm> {
  late final TabletLoginController _controller;

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
      await showPromptLoginFailure(context);
    }
  }

  Future<void> _onLoginButtonPressed() async {
    if (_controller.isLoading) return;
    _trace(
      '로그인 버튼',
      meta: <String, dynamic>{
        'screen': 'tablet_login',
        'action': 'login',
      },
    );
    await _handleLogin();
  }

  void _onTopCompanyLogoTapped() {
    _trace(
      '회사 로고(상단)',
      meta: <String, dynamic>{
        'screen': 'tablet_login',
        'asset': 'assets/images/ParkinWorkin_logo.png',
        'action': 'tap',
      },
    );
  }

  void _onFooterLogoTapped() {
    _trace(
      '회사 로고(펠리컨)',
      meta: <String, dynamic>{
        'screen': 'tablet_login',
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
  Widget build(BuildContext context) {
    return PromptLoginScaffold(
      spec: PromptLoginModeSpec.tablet,
      onTopLogoPressed: _onTopCompanyLogoTapped,
      onFooterLogoPressed: _onFooterLogoTapped,
      fields: PromptLoginFields(
        nameController: _controller.nameController,
        nameFocus: _controller.nameFocus,
        accountController: _controller.phoneController,
        accountFocus: _controller.phoneFocus,
        passwordController: _controller.passwordController,
        passwordFocus: _controller.passwordFocus,
        accountLabel: '영어 아이디(핸들)',
        accountIcon: Icons.alternate_email_rounded,
        accountKeyboardType: TextInputType.text,
        onAccountChanged: (value) =>
            _controller.formatPhoneNumber(value, setState),
        obscurePassword: _controller.obscurePassword,
        onTogglePassword: () =>
            setState(() => _controller.togglePassword()),
        onSubmit: _onLoginButtonPressed,
        enabled: !_controller.isLoading,
      ),
      actions: PromptAnimatedReveal(
        delay: const Duration(milliseconds: 240),
        child: PromptButton(
          label: _controller.isLoading ? '로그인 중' : '로그인',
          icon: Icons.login_rounded,
          expand: true,
          loading: _controller.isLoading,
          onPressed: _controller.isLoading ? null : _onLoginButtonPressed,
          haptic: PromptHaptic.light,
        ),
      ),
    );
  }
}
