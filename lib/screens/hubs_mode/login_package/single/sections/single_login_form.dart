import 'package:flutter/material.dart';

import '../../../../../routes.dart'; // ✅ AppRoutes 사용
import '../single_login_controller.dart';

// ✅ Trace 기록용 Recorder
import '../../../../../screens/hubs_mode/dev_package/debug_package/debug_action_recorder.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ 로고(PNG) 가독성 보장 유틸
///
/// - 단색/검정 고정 PNG가 다크/브랜드 배경에서 안 보이는 문제를 방지:
///   알파(투명도)를 마스크로 사용해 tint.
/// - preferred가 배경과 대비가 부족하면 fallback으로 자동 폴백.
///
/// NOTE: 로고/큰 텍스트는 minContrast=3.0 기준을 기본으로 둡니다.
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

/// ✅ 단색(검정 고정) PNG 로고를 테마에 맞춰 tint 하는 위젯
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

  /// (선택) 기본은 cs.primary
  final Color? preferredColor;

  /// (선택) 기본은 cs.onBackground
  final Color? fallbackColor;

  final double minContrast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // ✅ 실제 화면 배경에 가장 근접한 scaffoldBackgroundColor를 기준으로 대비 판단
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

  // ✅ (신규) 상단 screen tag 이미지
  static const String _kPelicanTagAsset = 'assets/images/pelican_text.png';

  // ✅ (신규) “보이는 크기만” 키우는 스케일 (레이아웃 높이에는 거의 영향 없음)
  static const double _kTagScale = 3.0;

  @override
  void initState() {
    super.initState();
    _controller = widget.controller; // ✅ init은 상위(LoginScreen)에서만 수행
  }

  void _trace(String name, {Map<String, dynamic>? meta}) {
    DebugActionRecorder.instance.recordAction(
      name,
      route: ModalRoute.of(context)?.settings.name,
      meta: meta,
    );
  }

  void _handleLogin() {
    _controller.login(setState);
  }

  void _onLoginButtonPressed() {
    if (_controller.isLoading) return;

    _trace(
      '약식 로그인 버튼',
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

  TextStyle _screenTagStyle(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return (text.labelSmall ?? const TextStyle(fontSize: 11)).copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: cs.onSurfaceVariant.withOpacity(0.80),
      letterSpacing: 0.2,
    );
  }

  /// ✅ (신규) tag 영역: 레이아웃 높이는 텍스트 수준으로 “고정”
  ///             실제 보이는 크기는 Transform.scale로만 확대
  Widget _buildPelicanTag(BuildContext context) {
    final tagStyle = _screenTagStyle(context);
    final tagFontSize = (tagStyle.fontSize ?? 11.0).toDouble();

    // ✅ 레이아웃 점유 높이(=텍스트 1줄 체감치)
    final tagLayoutHeight = tagFontSize + 3.0;

    // ✅ 기존 텍스트 색감(onSurfaceVariant 0.80)으로 이미지 tint
    final cs = Theme.of(context).colorScheme;
    final tagPreferredTint = cs.onSurfaceVariant.withOpacity(0.80);

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, bottom: 8),
        child: Semantics(
          label: 'screen_tag: simple login image',
          child: ExcludeSemantics(
            child: SizedBox(
              height: tagLayoutHeight, // ✅ 레이아웃 높이 고정 (스크린 세로 영향 최소화)
              child: Align(
                alignment: Alignment.centerLeft,
                child: Transform.scale(
                  scale: _kTagScale, // ✅ 여기만 조절하면 “보이는 크기”가 변함
                  alignment: Alignment.centerLeft,
                  child: _BrandTintedLogo(
                    assetPath: _kPelicanTagAsset,
                    height: tagLayoutHeight,
                    preferredColor: tagPreferredTint,
                    fallbackColor: cs.onBackground,
                    minContrast: 3.0,
                  ),
                ),
              ),
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

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Theme(
          data: themed,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                const SizedBox(height: 12),

                // ✅ (변경) 텍스트 tag 대신 pelican_text.png (레이아웃 고정 + 스케일 확대)
                _buildPelicanTag(context),

                // ✅ (변경) 상단 로고 tint 적용
                GestureDetector(
                  onTap: _onTopCompanyLogoTapped,
                  child: SizedBox(
                    height: 360,
                    child: Center(
                      child: _BrandTintedLogo(
                        assetPath: 'assets/images/ParkinWorkin_logo.png',
                        height: 360,
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                TextField(
                  controller: _controller.nameController,
                  focusNode: _controller.nameFocus,
                  textInputAction: TextInputAction.next,
                  onSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_controller.phoneFocus),
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
                  onSubmitted: (_) =>
                      FocusScope.of(context).requestFocus(_controller.passwordFocus),
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
                      icon: Icon(_controller.obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility),
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
                      _controller.isLoading ? '로딩 중...' : '약식 로그인',
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

                const SizedBox(height: 1),

                Center(
                  child: InkWell(
                    onTap: _onPelicanLogoTapped,
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      height: 80,
                      // ✅ (변경) 텍스트 로고 tint 적용
                      child: _BrandTintedLogo(
                        assetPath: 'assets/images/ParkinWorkin_text.png',
                        height: 80,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
