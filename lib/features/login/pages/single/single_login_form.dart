import 'package:flutter/material.dart';
import '../../../../app/di/routes.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../controllers/single/single_login_controller.dart';

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
    this.preferredColor,
    this.fallbackColor,
    this.minContrast = 3.0,
  });

  final String assetPath;
  final double height;

  
  final Color? preferredColor;

  
  final Color? fallbackColor;

  final double minContrast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    
    final bg = theme.scaffoldBackgroundColor;

    final preferred = preferredColor ?? cs.primary;
    final fallback = fallbackColor ?? cs.onBackground;

    final tint = _resolveLogoTint(
      background: bg,
      preferred: preferred,
      fallback: fallback,
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

class SingleLoginForm extends StatefulWidget {
  final SingleLoginController controller;

  const SingleLoginForm({super.key, required this.controller});

  @override
  State<SingleLoginForm> createState() => _SingleLoginFormState();
}

class _SingleLoginFormState extends State<SingleLoginForm> {
  late final SingleLoginController _controller;

  
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

  void _handleLogin() {
    _controller.login(setState).then((ok) async {
      if (!ok && mounted) {
        await StatusDialog.showFailure(context, title: StatusDialog.loginFailed);
      }
    });
  }

  void _onLoginButtonPressed() {
    if (_controller.isLoading) return;

    _trace(
      '로그인 버튼',
      meta: <String, dynamic>{
        'screen': 'simple_login',
        'action': 'login',
      },
    );

    _handleLogin();
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

  void _onPelicanLogoTapped() {
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

  ThemeData _buildBrandLocalTheme(ThemeData baseTheme) {
    final cs = baseTheme.colorScheme;

    return baseTheme.copyWith(
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: cs.primary,
          foregroundColor: cs.onPrimary,
          minimumSize: const Size.fromHeight(55),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          elevation: 1.5,
          shadowColor: cs.shadow.withOpacity(0.18),
        ),
      ),
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
          label: 'screen_tag: simple login image',
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

  @override
  Widget build(BuildContext context) {
    final baseTheme = Theme.of(context);
    final themed = _buildBrandLocalTheme(baseTheme);

    
    final media = MediaQuery.of(context);
    final bool isShort = media.size.height < 640;
    final bool keyboardOpen = media.viewInsets.bottom > 0;
    final double footerHeight = (isShort || keyboardOpen) ? 72 : 120;

    
    final double topLogoHeight = isShort ? 280 : 360;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Theme(
          data: themed,
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
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    TextField(
                      controller: _controller.nameController,
                      focusNode: _controller.nameFocus,
                      textInputAction: TextInputAction.next,
                      onSubmitted: (_) => FocusScope.of(context)
                          .requestFocus(_controller.phoneFocus),
                      decoration: _controller.inputDecoration(
                        label: "이름",
                        icon: Icons.person,
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _controller.phoneController,
                      focusNode: _controller.phoneFocus,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) =>
                          _controller.formatPhoneNumber(value, setState),
                      onSubmitted: (_) => FocusScope.of(context)
                          .requestFocus(_controller.passwordFocus),
                      decoration: _controller.inputDecoration(
                        label: "전화번호",
                        icon: Icons.phone,
                      ),
                    ),
                    const SizedBox(height: 16),

                    TextField(
                      controller: _controller.passwordController,
                      focusNode: _controller.passwordFocus,
                      obscureText: _controller.obscurePassword,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _onLoginButtonPressed(),
                      decoration: _controller.inputDecoration(
                        label: "비밀번호(5자리 이상)",
                        icon: Icons.lock,
                        suffixIcon: IconButton(
                          icon: Icon(
                            _controller.obscurePassword
                                ? Icons.visibility_off
                                : Icons.visibility,
                          ),
                          onPressed: () =>
                              setState(() => _controller.togglePassword()),
                          tooltip: _controller.obscurePassword ? '표시' : '숨기기',
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    SizedBox(
                      width: double.infinity,
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
                        onPressed:
                        _controller.isLoading ? null : _onLoginButtonPressed,
                      ),
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
            ],
          ),
        ),
      ),
    );
  }
}
