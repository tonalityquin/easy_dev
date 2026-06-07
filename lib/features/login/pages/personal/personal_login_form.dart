import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../app/di/routes.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../controllers/personal/personal_login_controller.dart';
import 'personal_sign_up_dialog.dart';

double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final l1 = la >= lb ? la : lb;
  final l2 = la >= lb ? lb : la;
  return (l1 + 0.05) / (l2 + 0.05);
}

Color _resolveLogoTint({
  required Color background,
  required Color preferred,
  required Color fallback,
  double minContrast = 3.0,
}) {
  if (_contrastRatio(preferred, background) >= minContrast) return preferred;
  return fallback;
}

class _BrandTintedLogo extends StatelessWidget {
  const _BrandTintedLogo({
    required this.assetPath,
    required this.height,
    required this.preferredColor,
    required this.fallbackColor,
    this.minContrast = 3.0,
  });

  final String assetPath;
  final double height;
  final Color preferredColor;
  final Color fallbackColor;
  final double minContrast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;

    final tint = _resolveLogoTint(
      background: bg,
      preferred: preferredColor,
      fallback: fallbackColor,
      minContrast: minContrast,
    );

    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      height: height,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}

class PersonalLoginForm extends StatefulWidget {
  const PersonalLoginForm({super.key, required this.controller});

  final PersonalLoginController controller;

  @override
  State<PersonalLoginForm> createState() => _PersonalLoginFormState();
}

class _PersonalLoginFormState extends State<PersonalLoginForm> {
  late final PersonalLoginController _controller;

  static const String _kPelicanTagAsset = 'assets/images/pelican_text.png';
  static const double _kTagExtraHeight = 70.0;

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

  void _showSnack(String message, {required bool success}) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: success
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _handleLogin() async {
    final result = await _controller.login(setState);
    if (!mounted) return;
    setState(() {});

    if (result.success) {
      _showSnack(result.message, success: true);
      Navigator.of(context).pushReplacementNamed(AppRoutes.personal);
      return;
    }

    await StatusDialog.showFailure(
      context,
      title: StatusDialog.loginFailed,
      description: result.message,
      copyText: result.copyText ?? result.message,
      copyButtonLabel: '실패 내용 복사',
    );
  }

  void _onLoginButtonPressed() {
    if (_controller.isLoading) return;

    _trace(
      '로그인 버튼',
      meta: <String, dynamic>{
        'screen': 'personal_login',
        'action': 'login',
        'collection': 'personal_accounts',
      },
    );

    _handleLogin();
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

    final devMode = await _controller.isDeveloperModeEnabled();
    if (!mounted) return;

    if (devMode) {
      final created = await showDialog<bool>(
        context: context,
        barrierDismissible: !_controller.isLoading,
        builder: (dialogContext) => PersonalSignUpDialog(
          controller: _controller,
        ),
      );
      if (!mounted) return;
      if (created == true) {
        setState(() {});
        _showSnack('개인형 계정을 생성했습니다.', success: true);
      }
      return;
    }

    await _controller.openExternalSignUpForm();
    if (!mounted) return;
    _showSnack('개발자 모드가 아니어서 회원가입 Google Form을 열었습니다.', success: true);
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
      _showSnack('로그인된 개인형 계정이 없습니다.', success: false);
      return;
    }

    final result = await _controller.logout(setState);
    if (!mounted) return;
    setState(() {});
    _showSnack(result.message, success: result.success);
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

    HapticFeedback.selectionClick();
  }

  void _onPelicanLogoTapped() {
    _trace(
      '회사 로고(펠리컨)',
      meta: <String, dynamic>{
        'screen': 'personal_login',
        'asset': 'assets/images/ParkinWorkin_text.png',
        'action': 'back_to_selector',
        'to': AppRoutes.selector,
      },
    );

    HapticFeedback.selectionClick();

    Navigator.of(context).pushNamedAndRemoveUntil(
      AppRoutes.selector,
      (route) => false,
    );
  }

  ThemeData _buildBrandLocalTheme(ThemeData baseTheme) {
    final cs = baseTheme.colorScheme;

    return baseTheme.copyWith(
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          minimumSize: const Size.fromHeight(55),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(55),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          side: BorderSide(color: cs.outlineVariant),
          foregroundColor: cs.primary,
        ),
      ),
      iconTheme: baseTheme.iconTheme.copyWith(color: cs.primary),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: cs.primary,
          splashFactory: InkRipple.splashFactory,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: cs.primary,
        selectionColor: cs.primaryContainer.withOpacity(.35),
        selectionHandleColor: cs.primary,
      ),
    );
  }

  Widget _buildScreenTag(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final base = theme.textTheme.labelSmall ??
        const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        );

    final fontSize = (base.fontSize ?? 11).toDouble();
    final tagImageHeight = fontSize + _kTagExtraHeight;

    final tagPreferredTint = cs.onSurfaceVariant.withOpacity(0.80);

    return Positioned(
      top: 12,
      left: 12,
      child: IgnorePointer(
        child: Semantics(
          label: 'screen_tag: personal login (image)',
          child: ExcludeSemantics(
            child: _BrandTintedLogo(
              assetPath: _kPelicanTagAsset,
              height: tagImageHeight,
              preferredColor: tagPreferredTint,
              fallbackColor: cs.onBackground,
              minContrast: 3.0,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMoreMenu(BuildContext context) {
    return Positioned(
      top: 4,
      right: 4,
      child: SafeArea(
        child: PopupMenuButton<String>(
          tooltip: '더보기',
          icon: const Icon(Icons.more_vert_rounded),
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
                children: const <Widget>[
                  Icon(Icons.logout_rounded),
                  SizedBox(width: 10),
                  Text('로그아웃'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoginStatus(BuildContext context) {
    if (!_controller.isLoggedIn) {
      return const SizedBox.shrink();
    }

    final cs = Theme.of(context).colorScheme;
    final name = _controller.loggedInName ?? '개인형 계정';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withOpacity(.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.primary.withOpacity(.24)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.check_circle_rounded, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$name 로그인 상태',
              style: TextStyle(
                color: cs.onPrimaryContainer,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final themed = _buildBrandLocalTheme(baseTheme);
    final cs = baseTheme.colorScheme;

    final media = MediaQuery.of(context);
    final bool isShort = media.size.height < 640;
    final bool keyboardOpen = media.viewInsets.bottom > 0;
    final double footerHeight = (isShort || keyboardOpen) ? 72 : 120;
    final double topLogoHeight = isShort ? 280 : 360;

    return Theme(
      data: themed,
      child: Material(
        color: Colors.transparent,
        child: SafeArea(
          child: Stack(
            children: [
              SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: _onTopCompanyLogoTapped,
                      child: SizedBox(
                        height: topLogoHeight,
                        child: Center(
                          child: _BrandTintedLogo(
                            assetPath: 'assets/images/ParkinWorkin_logo.png',
                            height: topLogoHeight,
                            preferredColor: cs.primary,
                            fallbackColor: cs.onBackground,
                            minContrast: 3.0,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildLoginStatus(context),
                    if (_controller.isLoggedIn) const SizedBox(height: 16),
                    TextField(
                      controller: _controller.nameController,
                      focusNode: _controller.nameFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context).requestFocus(_controller.phoneFocus),
                      decoration: _controller.inputDecoration(
                        label: '이름',
                        icon: Icons.person,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller.phoneController,
                      focusNode: _controller.phoneFocus,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) => _controller.formatPhoneNumber(value, setState),
                      onSubmitted: (_) => FocusScope.of(context).requestFocus(_controller.passwordFocus),
                      decoration: _controller.inputDecoration(
                        label: '전화번호',
                        icon: Icons.phone,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _controller.passwordController,
                      focusNode: _controller.passwordFocus,
                      obscureText: _controller.obscurePassword,
                      keyboardType: TextInputType.number,
                      inputFormatters: <TextInputFormatter>[
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(5),
                      ],
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _onLoginButtonPressed(),
                      decoration: _controller.inputDecoration(
                        label: '비밀번호(5자리)',
                        icon: Icons.lock,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _controller.obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () => setState(() => _controller.togglePassword()),
                          tooltip: _controller.obscurePassword ? '표시' : '숨기기',
                        ),
                      ),
                    ),
                    const SizedBox(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.login),
                            label: Text(
                              _controller.isLoading ? '로딩 중...' : '로그인',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                            onPressed: _controller.isLoading ? null : _onLoginButtonPressed,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                            label: const Text(
                              '회원가입',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.1,
                              ),
                            ),
                            onPressed: _controller.isLoading ? null : _onSignUpButtonPressed,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    AnimatedOpacity(
                      opacity: keyboardOpen ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 160),
                      child: Center(
                        child: InkWell(
                          onTap: _onPelicanLogoTapped,
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            height: footerHeight,
                            child: _BrandTintedLogo(
                              assetPath: 'assets/images/ParkinWorkin_text.png',
                              height: footerHeight,
                              preferredColor: cs.primary,
                              fallbackColor: cs.onBackground,
                              minContrast: 3.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
              _buildScreenTag(context),
              _buildMoreMenu(context),
            ],
          ),
        ),
      ),
    );
  }
}
