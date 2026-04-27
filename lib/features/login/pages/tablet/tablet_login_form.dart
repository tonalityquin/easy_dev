import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../../widgets/dialog/status_dialog_package/status_dialog.dart';
import '../../../../app/di/routes.dart';
import '../../../dev/debug/debug_action_recorder.dart';
import '../../controllers/tablet/tablet_login_controller.dart';

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

class TabletLoginForm extends StatefulWidget {
  final TabletLoginController controller;

  const TabletLoginForm({super.key, required this.controller});

  @override
  State<TabletLoginForm> createState() => _TabletLoginFormState();
}

class _TabletLoginFormState extends State<TabletLoginForm> {
  late final TabletLoginController _controller;

  
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
        'screen': 'tablet_login',
        'action': 'login',
      },
    );

    _handleLogin();
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

    HapticFeedback.selectionClick();
  }

  void _onPelicanLogoTapped() {
    _trace(
      '회사 로고(펠리컨)',
      meta: <String, dynamic>{
        'screen': 'tablet_login',
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
          label: 'screen_tag: tablet login (image)',
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
                      keyboardType: TextInputType.text,
                      textCapitalization: TextCapitalization.none,
                      autocorrect: false,
                      enableSuggestions: false,
                      textInputAction: TextInputAction.next,
                      onChanged: (value) =>
                          _controller.formatPhoneNumber(value, setState),
                      onSubmitted: (_) => FocusScope.of(context)
                          .requestFocus(_controller.passwordFocus),
                      decoration: _controller.inputDecoration(
                        label: "영어 아이디(핸들)",
                        icon: Icons.alternate_email,
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
                          style: IconButton.styleFrom(
                            foregroundColor: cs.primary,
                          ),
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
            ],
          ),
        ),
      ),
    );
  }
}
