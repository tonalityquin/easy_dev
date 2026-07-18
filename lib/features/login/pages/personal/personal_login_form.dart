import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/di/routes.dart';
import '../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../controllers/personal/personal_login_controller.dart';
import '../common/prompt_login_ui.dart';
import 'personal_sign_up_dialog.dart';

class PersonalLoginForm extends StatefulWidget {
  const PersonalLoginForm({super.key, required this.controller});

  final PersonalLoginController controller;

  @override
  State<PersonalLoginForm> createState() => _PersonalLoginFormState();
}

class _PersonalLoginFormState extends State<PersonalLoginForm> {
  late final PersonalLoginController _controller;

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
    final result = await _controller.login(setState);
    if (!mounted) return;
    setState(() {});

    if (result.success) {
      showPromptLoginSnack(
        context,
        message: result.message,
        success: true,
      );
      Navigator.of(context).pushReplacementNamed(AppRoutes.personal);
      return;
    }

    await showPromptLoginFailure(
      context,
      title: '로그인 실패',
      description: result.message,
      copyText: result.copyText ?? result.message,
      copyButtonLabel: '실패 내용 복사',
    );
  }

  Future<void> _onLoginButtonPressed() async {
    if (_controller.isLoading) return;
    _trace(
      '로그인 버튼',
      meta: <String, dynamic>{
        'screen': 'personal_login',
        'action': 'login',
        'collection': 'personal_accounts',
      },
    );
    await _handleLogin();
  }

  Future<void> _onSignUpButtonPressed() async {
    if (_controller.isLoading) return;
    _trace(
      '회원가입 버튼',
      meta: <String, dynamic>{
        'screen': 'personal_login',
        'action': 'signup',
        'collection': 'personal_accounts',
      },
    );

    HapticFeedback.selectionClick();
    final developerMode = await _controller.isDeveloperModeEnabled();
    if (!mounted) return;

    if (developerMode) {
      final created = await showPromptDialog<bool>(
        context: context,
        barrierDismissible: !_controller.isLoading,
        builder: (_) => PersonalSignUpDialog(controller: _controller),
      );
      if (!mounted) return;
      if (created == true) {
        setState(() {});
        showPromptLoginSnack(
          context,
          message: '개인형 계정을 생성했습니다.',
          success: true,
        );
      }
      return;
    }

    await _controller.openExternalSignUpForm();
    if (!mounted) return;
    showPromptLoginSnack(
      context,
      message: '개발자 모드가 아니어서 회원가입 Google Form을 열었습니다.',
      success: true,
    );
  }

  Future<void> _onLogoutPressed() async {
    _trace(
      '더보기 로그아웃',
      meta: <String, dynamic>{
        'screen': 'personal_login',
        'action': 'logout',
      },
    );

    HapticFeedback.selectionClick();
    if (!_controller.isLoggedIn) {
      showPromptLoginSnack(
        context,
        message: '로그인된 개인형 계정이 없습니다.',
        success: false,
      );
      return;
    }

    final result = await _controller.logout(setState);
    if (!mounted) return;
    setState(() {});
    showPromptLoginSnack(
      context,
      message: result.message,
      success: result.success,
    );
  }

  void _onTopCompanyLogoTapped() {
    _trace(
      '회사 로고(상단)',
      meta: <String, dynamic>{
        'screen': 'personal_login',
        'asset': 'assets/images/ParkinWorkin_logo.png',
        'action': 'tap',
      },
    );
  }

  void _onFooterLogoTapped() {
    _trace(
      '회사 로고(펠리컨)',
      meta: <String, dynamic>{
        'screen': 'personal_login',
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

  Widget _buildMoreMenu(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: BorderRadius.circular(PromptUiShapes.control),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: PopupMenuButton<String>(
        tooltip: '더보기',
        color: tokens.surfaceRaised,
        icon: Icon(Icons.more_vert_rounded, color: tokens.iconPrimary),
        onSelected: (value) {
          if (value == 'logout') {
            _onLogoutPressed();
          }
        },
        itemBuilder: (context) => <PopupMenuEntry<String>>[
          PopupMenuItem<String>(
            value: 'logout',
            enabled: !_controller.isLoading,
            child: Row(
              children: <Widget>[
                Icon(Icons.logout_rounded, color: tokens.iconSecondary),
                const SizedBox(width: 10),
                Text(
                  '로그아웃',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final statusName = _controller.loggedInName ?? '개인형 계정';
    return PromptLoginScaffold(
      spec: PromptLoginModeSpec.personal,
      onTopLogoPressed: _onTopCompanyLogoTapped,
      onFooterLogoPressed: _onFooterLogoTapped,
      topTrailing: _buildMoreMenu(context),
      status: _controller.isLoggedIn
          ? PromptLoginStatusBanner(
              visible: true,
              message: '$statusName 로그인 상태',
            )
          : null,
      fields: PromptLoginFields(
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
        passwordLabel: '비밀번호(5자리)',
        passwordKeyboardType: TextInputType.number,
        passwordInputFormatters: <TextInputFormatter>[
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(5),
        ],
        enabled: !_controller.isLoading,
      ),
      actions: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 390;
          final loginButton = PromptButton(
            label: _controller.isLoading ? '로그인 중' : '로그인',
            icon: Icons.login_rounded,
            expand: true,
            loading: _controller.isLoading,
            onPressed: _controller.isLoading ? null : _onLoginButtonPressed,
            haptic: PromptHaptic.light,
          );
          final signUpButton = PromptButton(
            label: '회원가입',
            icon: Icons.person_add_alt_1_rounded,
            variant: PromptButtonVariant.secondary,
            expand: true,
            onPressed: _controller.isLoading ? null : _onSignUpButtonPressed,
            haptic: PromptHaptic.selection,
          );

          return PromptAnimatedReveal(
            delay: const Duration(milliseconds: 240),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      loginButton,
                      const SizedBox(height: 10),
                      signUpButton,
                    ],
                  )
                : Row(
                    children: <Widget>[
                      Expanded(child: loginButton),
                      const SizedBox(width: 10),
                      Expanded(child: signUpButton),
                    ],
                  ),
          );
        },
      ),
    );
  }
}
